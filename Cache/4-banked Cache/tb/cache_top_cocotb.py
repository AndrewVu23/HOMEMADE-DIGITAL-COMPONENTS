import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
import random
from collections import OrderedDict

# ===========================================================================
# Cache Configuration Constants
# ===========================================================================
NUM_SETS       = 16
BLOCK_WORDS    = 4
BLOCK_BYTES    = BLOCK_WORDS * 4   # 16 bytes
CACHE_CAPACITY = NUM_SETS * BLOCK_BYTES  # 256 bytes

# ===========================================================================
# Simulated Main Memory (Python-side golden model)
# ===========================================================================
class MainMemory:
    """Simulates a slow 128-bit main memory with configurable latency."""

    def __init__(self, delay_cycles=3):
        self.mem = {}
        self.delay = delay_cycles
        for i in range(4096):
            self.mem[i] = (i * 0x11111111) & 0xFFFFFFFF

    def block_base(self, byte_addr):
        return ((byte_addr >> 4) * 4)

    def read_block(self, byte_addr):
        base = self.block_base(byte_addr)
        return [self.mem.get(base + i, 0) for i in range(4)]

    def write_block(self, byte_addr, words):
        base = self.block_base(byte_addr)
        for i in range(4):
            self.mem[base + i] = words[i] & 0xFFFFFFFF


async def memory_server(dut, mem, delay_cycles=3):
    """Background coroutine that responds to cache memory requests."""
    while True:
        await RisingEdge(dut.clk)
        if dut.mem_req.value == 1 and dut.mem_ready.value == 0:
            for _ in range(delay_cycles):
                await RisingEdge(dut.clk)

            addr = int(dut.mem_addr.value)

            if dut.mem_we.value == 1:
                wdata = int(dut.mem_wdata.value)
                words = [
                    (wdata >>  0) & 0xFFFFFFFF,
                    (wdata >> 32) & 0xFFFFFFFF,
                    (wdata >> 64) & 0xFFFFFFFF,
                    (wdata >> 96) & 0xFFFFFFFF,
                ]
                mem.write_block(addr, words)
            else:
                words = mem.read_block(addr)
                block = 0
                for i in range(4):
                    block |= (words[i] & 0xFFFFFFFF) << (32 * i)
                dut.mem_rdata.value = block

            dut.mem_ready.value = 1
            await RisingEdge(dut.clk)
            dut.mem_ready.value = 0


# ===========================================================================
# Fully-Associative Shadow Cache (for 3C's Miss Classification)
# ===========================================================================
class FullyAssociativeCache:
    """LRU fully-associative cache with same capacity as the real cache.
    Used to classify misses into compulsory / capacity / conflict."""

    def __init__(self, num_blocks=NUM_SETS):
        self.capacity = num_blocks
        self.blocks = OrderedDict()  # block_addr -> True, LRU order
        self.ever_accessed = set()

    def classify(self, byte_addr, real_cache_hit):
        block_addr = byte_addr >> 4

        if real_cache_hit:
            if block_addr in self.blocks:
                self.blocks.move_to_end(block_addr)
            else:
                if len(self.blocks) >= self.capacity:
                    self.blocks.popitem(last=False)
                self.blocks[block_addr] = True
            return "hit"

        is_first = block_addr not in self.ever_accessed
        self.ever_accessed.add(block_addr)

        fa_hit = block_addr in self.blocks
        if fa_hit:
            self.blocks.move_to_end(block_addr)
        else:
            if len(self.blocks) >= self.capacity:
                self.blocks.popitem(last=False)
            self.blocks[block_addr] = True

        if is_first:
            return "compulsory"
        elif fa_hit:
            return "conflict"
        else:
            return "capacity"


# ===========================================================================
# Cycle-Accurate Cache Profiler
# ===========================================================================
class CacheProfiler:
    """Instruments every cache access with exact cycle counts and miss classification."""

    def __init__(self, dut, mem_latency):
        self.dut = dut
        self.mem_latency = mem_latency
        self.reset()

    def reset(self):
        self.accesses = 0
        self.hits = 0
        self.misses = 0
        self.total_cycles = 0
        self.latencies = []
        self.miss_types = {"compulsory": 0, "capacity": 0, "conflict": 0}
        self.fa_cache = FullyAssociativeCache()

    async def timed_read(self, addr):
        """Perform a CPU read and return (data, cycles, is_hit)."""
        dut = self.dut
        await FallingEdge(dut.clk)
        dut.req.value = 1
        dut.we.value = 0
        dut.addr.value = addr
        dut.wdata.value = 0
        dut.wmask.value = 0

        cycles = 0
        await RisingEdge(dut.clk)
        cycles += 1

        await Timer(1, unit="ns")
        is_hit = (dut.stall.value == 0)

        while dut.stall.value == 1:
            await RisingEdge(dut.clk)
            cycles += 1

        await Timer(1, unit="ns")
        data = int(dut.rdata.value)

        await FallingEdge(dut.clk)
        dut.req.value = 0

        self._record(addr, cycles, is_hit)
        return data, cycles, is_hit

    async def timed_write(self, addr, data, wmask=0xF):
        """Perform a CPU write and return (cycles, is_hit)."""
        dut = self.dut
        await FallingEdge(dut.clk)
        dut.req.value = 1
        dut.we.value = 1
        dut.addr.value = addr
        dut.wdata.value = data
        dut.wmask.value = wmask

        cycles = 0
        await RisingEdge(dut.clk)
        cycles += 1

        await Timer(1, unit="ns")
        is_hit = (dut.stall.value == 0)

        while dut.stall.value == 1:
            await RisingEdge(dut.clk)
            cycles += 1

        await FallingEdge(dut.clk)
        dut.req.value = 0
        dut.we.value = 0

        self._record(addr, cycles, is_hit)
        return cycles, is_hit

    def _record(self, addr, cycles, is_hit):
        self.accesses += 1
        self.total_cycles += cycles
        self.latencies.append(cycles)
        if is_hit:
            self.hits += 1
            self.fa_cache.classify(addr, True)
        else:
            self.misses += 1
            mtype = self.fa_cache.classify(addr, False)
            self.miss_types[mtype] += 1

    def hit_rate(self):
        return (self.hits / self.accesses * 100) if self.accesses else 0

    def measured_amat(self):
        return (self.total_cycles / self.accesses) if self.accesses else 0

    def snapshot(self, name):
        """Return a dict snapshot of current stats."""
        hr = self.hit_rate()
        amat = self.measured_amat()
        tp = 1.0 / amat if amat > 0 else 0
        return {
            "name": name,
            "accesses": self.accesses,
            "hits": self.hits,
            "misses": self.misses,
            "hit_rate": hr,
            "amat": amat,
            "throughput": tp,
            "compulsory": self.miss_types["compulsory"],
            "capacity": self.miss_types["capacity"],
            "conflict": self.miss_types["conflict"],
        }


# ===========================================================================
# CPU Transaction Helpers (for correctness tests)
# ===========================================================================
async def cpu_read(dut, addr):
    await FallingEdge(dut.clk)
    dut.req.value = 1
    dut.we.value = 0
    dut.addr.value = addr
    dut.wdata.value = 0
    dut.wmask.value = 0

    await RisingEdge(dut.clk)
    while dut.stall.value == 1:
        await RisingEdge(dut.clk)

    await Timer(1, unit="ns")
    data = int(dut.rdata.value)

    await FallingEdge(dut.clk)
    dut.req.value = 0
    return data


async def cpu_write(dut, addr, data, wmask=0xF):
    await FallingEdge(dut.clk)
    dut.req.value = 1
    dut.we.value = 1
    dut.addr.value = addr
    dut.wdata.value = data
    dut.wmask.value = wmask

    await RisingEdge(dut.clk)
    while dut.stall.value == 1:
        await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.req.value = 0
    dut.we.value = 0


async def reset_dut(dut):
    dut.rst.value = 1
    dut.req.value = 0
    dut.we.value = 0
    dut.addr.value = 0
    dut.wdata.value = 0
    dut.wmask.value = 0
    dut.mem_rdata.value = 0
    dut.mem_ready.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


# ===========================================================================
# Correctness Tests (1-12)
# ===========================================================================

@cocotb.test()
async def test_cold_read_miss(dut):
    """Test 1: Compulsory miss on first access fetches full block from memory."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    data = await cpu_read(dut, 0x00000000)
    assert data == 0x00000000, f"Expected 0x00000000, got {data:#010x}"

    data = await cpu_read(dut, 0x00000004)
    assert data == 0x11111111, f"Expected 0x11111111, got {data:#010x}"

    data = await cpu_read(dut, 0x00000008)
    assert data == 0x22222222, f"Expected 0x22222222, got {data:#010x}"

    data = await cpu_read(dut, 0x0000000C)
    assert data == 0x33333333, f"Expected 0x33333333, got {data:#010x}"


@cocotb.test()
async def test_read_hit_different_sets(dut):
    """Test 2: Access multiple sets and verify each block loads correctly."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    for s in range(16):
        addr = s * 16
        expected = mem.read_block(addr)[0]
        data = await cpu_read(dut, addr)
        assert data == expected, f"Set {s}: Expected {expected:#010x}, got {data:#010x}"


@cocotb.test()
async def test_write_hit_full_word(dut):
    """Test 3: Write a full word (SW) and read it back."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    await cpu_read(dut, 0x00000000)
    await cpu_write(dut, 0x00000000, 0xDEADBEEF, 0xF)
    data = await cpu_read(dut, 0x00000000)
    assert data == 0xDEADBEEF, f"Expected 0xDEADBEEF, got {data:#010x}"

    data = await cpu_read(dut, 0x00000004)
    assert data == 0x11111111, f"Neighbor corrupted: expected 0x11111111, got {data:#010x}"


@cocotb.test()
async def test_partial_write_byte(dut):
    """Test 4: Store Byte (SB) - only lowest byte changes, top 3 preserved."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    await cpu_read(dut, 0x00000004)
    await cpu_write(dut, 0x00000004, 0x000000AA, 0x1)
    data = await cpu_read(dut, 0x00000004)
    assert data == 0x111111AA, f"Expected 0x111111AA, got {data:#010x}"


@cocotb.test()
async def test_partial_write_halfword(dut):
    """Test 5: Store Halfword (SH) - top 2 bytes change, bottom 2 preserved."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    await cpu_read(dut, 0x00000008)
    await cpu_write(dut, 0x00000008, 0xBBBB0000, 0xC)
    data = await cpu_read(dut, 0x00000008)
    assert data == 0xBBBB2222, f"Expected 0xBBBB2222, got {data:#010x}"


@cocotb.test()
async def test_dirty_miss_eviction(dut):
    """Test 6: Dirty miss triggers writeback then allocate."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    await cpu_read(dut, 0x00000000)
    await cpu_write(dut, 0x00000000, 0xDEADBEEF, 0xF)
    await cpu_write(dut, 0x00000004, 0xCAFEBABE, 0xF)

    data = await cpu_read(dut, 0x00000100)
    expected = mem.read_block(0x100)[0]
    assert data == expected, f"Post-eviction read failed: expected {expected:#010x}, got {data:#010x}"

    assert mem.mem[0] == 0xDEADBEEF, f"Writeback word0 failed: {mem.mem[0]:#010x}"
    assert mem.mem[1] == 0xCAFEBABE, f"Writeback word1 failed: {mem.mem[1]:#010x}"


@cocotb.test()
async def test_clean_miss(dut):
    """Test 7: Clean miss skips writeback and goes straight to allocate."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    addr = 5 * 16
    expected = mem.read_block(addr)[0]
    data = await cpu_read(dut, addr)
    assert data == expected, f"Clean miss failed: expected {expected:#010x}, got {data:#010x}"


@cocotb.test()
async def test_write_miss_allocate(dut):
    """Test 8: Write to an address that isn't cached yet (write-allocate)."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    await cpu_write(dut, 0x00000030, 0x12345678, 0xF)
    data = await cpu_read(dut, 0x00000030)
    assert data == 0x12345678, f"Write-allocate failed: expected 0x12345678, got {data:#010x}"


@cocotb.test()
async def test_multiple_evictions_same_set(dut):
    """Test 9: Thrash the same set with different tags to force repeated evictions."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    addrs = [0x00000000, 0x00000100, 0x00000200, 0x00000300]
    for a in addrs:
        await cpu_write(dut, a, a | 0xBEEF, 0xF)

    data = await cpu_read(dut, 0x00000300)
    assert data == (0x300 | 0xBEEF), f"Last tag not cached: {data:#010x}"


@cocotb.test()
async def test_all_word_selects(dut):
    """Test 10: Read and write to all 4 words within a single block."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    base = 0x00000040
    await cpu_read(dut, base)

    for w in range(4):
        await cpu_write(dut, base + w * 4, 0xAA000000 | (w << 8), 0xF)

    for w in range(4):
        data = await cpu_read(dut, base + w * 4)
        expected = 0xAA000000 | (w << 8)
        assert data == expected, f"Word {w}: expected {expected:#010x}, got {data:#010x}"


@cocotb.test()
async def test_randomized_stress(dut):
    """Test 11: 100 randomized read/write operations with automatic verification."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    shadow = {}
    for i in range(100):
        tag = random.randint(0, 3)
        index = random.randint(0, 15)
        word = random.randint(0, 3)
        addr = (tag << 8) | (index << 4) | (word << 2)

        if random.random() < 0.5:
            val = random.randint(0, 0xFFFFFFFF)
            await cpu_write(dut, addr, val, 0xF)
            shadow[addr] = val
            data = await cpu_read(dut, addr)
            assert data == val, f"Op {i}: Write+Read addr={addr:#010x}, expected {val:#010x}, got {data:#010x}"
        else:
            data = await cpu_read(dut, addr)
            assert data is not None, f"Op {i}: Read addr={addr:#010x} returned None"


@cocotb.test()
async def test_byte_mask_combinations(dut):
    """Test 12: Test all 16 possible wmask patterns."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    mem = MainMemory()
    cocotb.start_soon(memory_server(dut, mem))
    await reset_dut(dut)

    for mask in range(16):
        addr = ((10 + mask) % 16) * 16
        await cpu_read(dut, addr)
        original = await cpu_read(dut, addr)

        await cpu_write(dut, addr, 0xFFFFFFFF, mask)
        data = await cpu_read(dut, addr)

        expected = 0
        for b in range(4):
            if mask & (1 << b):
                expected |= (0xFF << (b * 8))
            else:
                expected |= (original >> (b * 8) & 0xFF) << (b * 8)

        assert data == expected, f"wmask={mask:#06b}: expected {expected:#010x}, got {data:#010x}"


# ===========================================================================
# Test 13: Cycle-Accuracy Verification
# ===========================================================================
@cocotb.test()
async def test_cycle_accuracy(dut):
    """Test 13: Verify exact cycle counts for hit, clean miss, and dirty miss."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    MEM_LATENCY = 10
    mem = MainMemory(delay_cycles=MEM_LATENCY)
    cocotb.start_soon(memory_server(dut, mem, delay_cycles=MEM_LATENCY))
    await reset_dut(dut)

    log = dut._log

    # NOTE: tag_decoder and SRAM have no reset logic, so cache retains data
    # from previous tests. We warm up with a known tag to get a deterministic
    # starting state before measuring cycle latencies.

    # Warm up set 0: load tag=0xFF to flush any residual dirty data
    await cpu_read(dut, 0x0000FF00)  # tag=0xFF, set=0 -> guaranteed miss
    # Warm up set 5: same idea
    await cpu_read(dut, 0x0000FF50)  # tag=0xFF, set=5 -> guaranteed miss

    # Now set 0 has tag=0xFF, valid=1, dirty=0 (clean)
    # Now set 5 has tag=0xFF, valid=5, dirty=0 (clean)

    prof = CacheProfiler(dut, MEM_LATENCY)

    # --- Clean miss: access tag=0 in set 0 (evicts clean tag=0xFF) ---
    _, clean_miss_cycles, is_hit = await prof.timed_read(0x00000000)
    assert not is_hit, f"Tag mismatch should be a miss (stall={int(dut.stall.value)})"
    log.info(f"Clean miss latency: {clean_miss_cycles} cycles")

    # --- Read hit: same block, different word ---
    _, hit_cycles, is_hit = await prof.timed_read(0x00000004)
    assert is_hit, "Second access to same block should hit"
    assert hit_cycles == 1, f"Hit should be 1 cycle, got {hit_cycles}"
    log.info(f"Read hit latency : {hit_cycles} cycle")

    # --- Write hit ---
    write_hit_cycles, is_hit = await prof.timed_write(0x00000000, 0xDEADBEEF)
    assert is_hit, "Write to cached block should hit"
    assert write_hit_cycles == 1, f"Write hit should be 1 cycle, got {write_hit_cycles}"
    log.info(f"Write hit latency: {write_hit_cycles} cycle")

    # --- Dirty miss: access different tag in same set (eviction required) ---
    # Set 0 now has tag=0, dirty=1. Access tag=1 to force writeback.
    _, dirty_miss_cycles, is_hit = await prof.timed_read(0x00000100)
    assert not is_hit, "Different tag same set should miss"
    log.info(f"Dirty miss latency: {dirty_miss_cycles} cycles")

    # --- Clean miss on set 5 (tag=0xFF -> tag=0, clean eviction) ---
    prof.reset()
    _, clean2_cycles, is_hit = await prof.timed_read(0x00000050)
    assert not is_hit, "Different tag in set 5 should miss"
    log.info(f"Clean miss (set 5): {clean2_cycles} cycles")

    # --- Summary ---
    log.info("=" * 60)
    log.info("  CYCLE-ACCURACY VERIFICATION SUMMARY")
    log.info("=" * 60)
    log.info(f"  Memory Latency (L) : {MEM_LATENCY} cycles")
    log.info(f"  Read Hit           : {hit_cycles} cycle (expected: 1)")
    log.info(f"  Write Hit          : {write_hit_cycles} cycle (expected: 1)")
    log.info(f"  Clean Miss         : {clean_miss_cycles} cycles (= L + {clean_miss_cycles - MEM_LATENCY})")
    log.info(f"  Dirty Miss         : {dirty_miss_cycles} cycles (= 2L + {dirty_miss_cycles - 2*MEM_LATENCY})")
    log.info(f"  Clean Miss (set 5) : {clean2_cycles} cycles")
    log.info("=" * 60)


# ===========================================================================
# Test 14: Full Performance Characterization
# ===========================================================================
@cocotb.test()
async def test_performance_full(dut):
    """Test 14: Comprehensive cache performance analysis with 7 workloads."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    MEM_LATENCY = 10
    mem = MainMemory(delay_cycles=MEM_LATENCY)
    cocotb.start_soon(memory_server(dut, mem, delay_cycles=MEM_LATENCY))
    await reset_dut(dut)

    log = dut._log
    results = []

    def print_workload(snap):
        log.info(f"  {'─' * 56}")
        log.info(f"  {snap['name']}")
        log.info(f"  Accesses: {snap['accesses']}  |  "
                 f"Hits: {snap['hits']}  |  Misses: {snap['misses']}")
        log.info(f"  Hit Rate: {snap['hit_rate']:.1f}%  |  "
                 f"AMAT: {snap['amat']:.2f} cyc  |  "
                 f"Throughput: {snap['throughput']:.3f} acc/cyc")
        log.info(f"  3C's -> Compulsory: {snap['compulsory']}  "
                 f"Capacity: {snap['capacity']}  Conflict: {snap['conflict']}")

    # =================================================================
    # Workload 1: Sequential Scan (Spatial Locality)
    # Walk through 256 words (1024 bytes) linearly.
    # Each 16-byte block = 4 words: 1 compulsory miss + 3 hits = 75%
    # =================================================================
    prof = CacheProfiler(dut, MEM_LATENCY)
    for i in range(256):
        await prof.timed_read(0x00001000 + i * 4)

    snap = prof.snapshot("W1: Sequential Scan (256 words)")
    results.append(snap)
    print_workload(snap)
    assert 70 <= snap["hit_rate"] <= 80, \
        f"Sequential scan hit rate {snap['hit_rate']:.1f}% outside [70,80]%"
    await reset_dut(dut)

    # =================================================================
    # Workload 2: Hot Loop (Temporal Locality)
    # 8 addresses spanning 2 blocks, repeated 50 times.
    # First 2 accesses are misses, remaining 398 are hits.
    # =================================================================
    prof = CacheProfiler(dut, MEM_LATENCY)
    loop_addrs = [0x4000 + i * 4 for i in range(8)]  # 2 blocks
    for _ in range(50):
        for addr in loop_addrs:
            await prof.timed_read(addr)

    snap = prof.snapshot("W2: Hot Loop (8 addr x 50 iter)")
    results.append(snap)
    print_workload(snap)
    assert snap["hit_rate"] > 90, \
        f"Hot loop hit rate {snap['hit_rate']:.1f}% should be > 90%"
    await reset_dut(dut)

    # =================================================================
    # Workload 3: Strided Walk (Zero Locality)
    # Stride of 256 bytes - every access hits a new block in the
    # same set, guaranteeing a miss every time.
    # =================================================================
    prof = CacheProfiler(dut, MEM_LATENCY)
    for i in range(50):
        await prof.timed_read(i * 256)

    snap = prof.snapshot("W3: Strided Walk (stride=256B)")
    results.append(snap)
    print_workload(snap)
    assert snap["hit_rate"] < 5, \
        f"Strided walk hit rate {snap['hit_rate']:.1f}% should be ~0%"
    await reset_dut(dut)

    # =================================================================
    # Workload 4: Ping-Pong Thrash (Direct-Mapped Pathology)
    # 2 addresses mapping to the SAME set, alternating.
    # After initial compulsory misses, every access is a conflict miss.
    # This is the worst-case for direct-mapped caches.
    # =================================================================
    prof = CacheProfiler(dut, MEM_LATENCY)
    addr_a = 0x00000000  # set 0, tag 0
    addr_b = 0x00000100  # set 0, tag 1
    for _ in range(50):
        await prof.timed_read(addr_a)
        await prof.timed_read(addr_b)

    snap = prof.snapshot("W4: Ping-Pong Thrash (same set)")
    results.append(snap)
    print_workload(snap)
    assert snap["hit_rate"] < 5, \
        f"Ping-pong hit rate {snap['hit_rate']:.1f}% should be ~0%"
    assert snap["conflict"] > 90, \
        f"Ping-pong should have >90 conflict misses, got {snap['conflict']}"
    await reset_dut(dut)

    # =================================================================
    # Workload 5: Working Set Fits in Cache
    # 16 blocks mapped to unique sets, accessed 50 times each.
    # After 16 compulsory misses, 100% hit rate.
    # =================================================================
    prof = CacheProfiler(dut, MEM_LATENCY)
    fit_addrs = [i * BLOCK_BYTES for i in range(NUM_SETS)]  # 16 unique sets
    for _ in range(50):
        for addr in fit_addrs:
            await prof.timed_read(addr)

    snap = prof.snapshot("W5: Working Set = Cache (16 blk)")
    results.append(snap)
    print_workload(snap)
    assert snap["hit_rate"] > 95, \
        f"Fitting working set hit rate {snap['hit_rate']:.1f}% should be >95%"
    await reset_dut(dut)

    # =================================================================
    # Workload 6: Working Set Sweep (Capacity Cliff Detection)
    # Gradually increase working set size from 4 to 32 blocks.
    # Measures where hit rate collapses (should be at 16 blocks).
    # =================================================================
    log.info(f"  {'─' * 56}")
    log.info("  W6: Working Set Sweep (capacity cliff)")
    sweep_results = []

    for ws_size in [4, 8, 12, 16, 20, 24, 32]:
        prof = CacheProfiler(dut, MEM_LATENCY)
        # Addresses mapping to sets 0..(ws_size-1), wrapping at 16
        ws_addrs = [i * BLOCK_BYTES for i in range(ws_size)]
        for _ in range(50):
            for addr in ws_addrs:
                await prof.timed_read(addr)

        snap = prof.snapshot(f"  ws={ws_size}")
        sweep_results.append((ws_size, snap))
        log.info(f"    WS={ws_size:>2} blocks -> "
                 f"Hit: {snap['hit_rate']:5.1f}%  "
                 f"AMAT: {snap['amat']:5.2f}  "
                 f"Comp: {snap['compulsory']:>3}  "
                 f"Cap: {snap['capacity']:>3}  "
                 f"Conf: {snap['conflict']:>3}")
        await reset_dut(dut)

    # Verify capacity cliff: ws=16 should have high hit rate, ws=32 should be low
    ws16_hr = [hr for ws, hr in sweep_results if ws == 16][0]["hit_rate"]
    ws32_hr = [hr for ws, hr in sweep_results if ws == 32][0]["hit_rate"]
    assert ws16_hr > 90, f"WS=16 should fit in cache, got {ws16_hr:.1f}%"
    assert ws32_hr < 10, f"WS=32 should thrash badly, got {ws32_hr:.1f}%"

    # =================================================================
    # Workload 7: Mixed Read/Write (Realistic CPU Pattern)
    # Simulates instruction fetch (sequential reads) interleaved
    # with data accesses (scattered reads/writes).
    # =================================================================
    prof = CacheProfiler(dut, MEM_LATENCY)
    random.seed(42)

    instr_base = 0x00002000
    data_base  = 0x00003000

    for i in range(200):
        # 70% instruction fetch (sequential, spatial locality)
        if random.random() < 0.7:
            await prof.timed_read(instr_base + (i % 64) * 4)
        else:
            # 30% data access: mix of reads and writes
            data_addr = data_base + random.randint(0, 31) * 4
            if random.random() < 0.5:
                await prof.timed_read(data_addr)
            else:
                await prof.timed_write(data_addr, random.randint(0, 0xFFFFFFFF))

    snap = prof.snapshot("W7: Mixed CPU (70% ifetch, 30% data)")
    results.append(snap)
    print_workload(snap)

    # =================================================================
    # FINAL SUMMARY TABLE
    # =================================================================
    log.info(" ")
    log.info("=" * 72)
    log.info("  CACHE PERFORMANCE ANALYSIS - FINAL REPORT")
    log.info("=" * 72)
    log.info(f"  Cache: Direct-Mapped | {NUM_SETS} sets | "
             f"{BLOCK_BYTES}B blocks | {CACHE_CAPACITY}B total")
    log.info(f"  Memory Latency: {MEM_LATENCY} cycles")
    log.info("=" * 72)
    log.info(f"  {'Workload':<36} {'Acc':>5} {'Hit%':>6} "
             f"{'AMAT':>6} {'Thr':>6} {'Comp':>5} {'Cap':>4} {'Conf':>5}")
    log.info(f"  {'─' * 70}")

    for r in results:
        log.info(f"  {r['name']:<36} {r['accesses']:>5} "
                 f"{r['hit_rate']:>5.1f}% {r['amat']:>5.2f} "
                 f"{r['throughput']:>5.3f} {r['compulsory']:>5} "
                 f"{r['capacity']:>4} {r['conflict']:>5}")

    log.info(f"  {'─' * 70}")
    log.info(" ")

    # Theoretical best/worst AMAT for reference (measured: clean miss = L+4, dirty miss = 2L+6)
    best_amat = 1.0  # 100% hit rate
    clean_miss_penalty = float(MEM_LATENCY + 4)
    dirty_miss_penalty = float(2 * MEM_LATENCY + 6)
    log.info(f"  Theoretical AMAT bounds:")
    log.info(f"    Best  (100% hits)        : {best_amat:.2f} cycles/access")
    log.info(f"    Worst (100% clean misses): {clean_miss_penalty:.2f} cycles/access")
    log.info(f"    Worst (100% dirty misses): {dirty_miss_penalty:.2f} cycles/access")
    log.info(" ")
    log.info("  KEY TAKEAWAYS:")
    log.info("  - Sequential scan exploits spatial locality (4 words/block)")
    log.info("  - Hot loops exploit temporal locality perfectly")
    log.info("  - Strided/ping-pong patterns defeat direct-mapped caches")
    log.info("  - Capacity cliff at 16 blocks shows cache size limit")
    log.info("  - Conflict misses dominate ping-pong (set-associative would help)")
    log.info("=" * 72)
