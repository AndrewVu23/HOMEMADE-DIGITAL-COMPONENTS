// radix2mul_tb.cpp
// Cycle-accurate Verilator testbench for the Booth radix-2 multiplier.
// Compile with:
//   verilator --cc --exe --build -Wall --coverage \
//     src/radix2mul.sv tb/radix2mul_tb.cpp --Mdir obj_dir
// Run:
//   ./obj_dir/Vradix2mul

#include "Vradix2mul.h"     // auto-generated from radix2mul.sv
#include "verilated.h"      // Verilator runtime
#include "verilated_cov.h"  // coverage support
#include <cstdint>

// verilated.h inlines a legacy fallback (vl_time_stamp64 -> sc_time_stamp) that the
// linker requires even though it is never called when using VerilatedContext.
double sc_time_stamp() { return 0; }
#include <cstdio>

// ── Global pointers ──────────────────────────────────────────────────────────
static VerilatedContext* ctx;
static Vradix2mul*       top;

// ── Advance one clock cycle ───────────────────────────────────────────────────
// Toggles clk low then high. Flip-flops latch on the rising edge (0→1).
static void tick() {
    top->clk = 0;
    top->eval();
    ctx->timeInc(5);

    top->clk = 1;
    top->eval();
    ctx->timeInc(5);
}

// ── Reset the DUT for 2 cycles ────────────────────────────────────────────────
static void reset() {
    top->rst = 1;
    top->en  = 0;
    top->M   = 0;
    top->Q   = 0;
    tick();
    tick();
    top->rst = 0;
    tick();
}

// ── Perform one multiplication and check the result ──────────────────────────
// Waits N+5 = 37 cycles for the result, matching the Python testbench.
static void test_mul(int32_t a, int32_t b) {
    int64_t expected = (int64_t)a * (int64_t)b;

    top->M = (uint32_t)a;   // preserve 2's complement bit pattern
    top->Q = (uint32_t)b;

    // Pulse en for two cycles to transition IDLE → CALC
    top->en = 1;
    tick();
    tick();
    top->en = 0;

    // Wait for computation (N=32 CALC cycles + margin)
    for (int i = 0; i < 37; i++) tick();

    int64_t actual = (int64_t)top->P;

    if (actual == expected) {
        printf("  PASS: %11d * %11d = %lld\n", a, b, (long long)actual);
    } else {
        printf("  FAIL: %11d * %11d => expected %lld, got %lld\n",
               a, b, (long long)expected, (long long)actual);
    }
}

// ── Main ──────────────────────────────────────────────────────────────────────
int main(int argc, char** argv) {
    ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    top = new Vradix2mul{ctx};

    // Initialize all inputs before the first eval
    top->clk = 0;
    top->rst = 0;
    top->en  = 0;
    top->M   = 0;
    top->Q   = 0;
    top->eval();

    reset();

    printf("[Positive numbers]\n");
    test_mul(5,  3);
    test_mul(10, 15);
    test_mul(43, 22);

    printf("\n[Negative numbers]\n");
    test_mul(-5,  3);
    test_mul( 5, -3);
    test_mul(-5, -3);
    test_mul(-15, -15);

    printf("\n[Zeros and ones]\n");
    test_mul(0,  5);
    test_mul(5,  0);
    test_mul(0,  0);
    test_mul(1,  1);
    test_mul(-1, 1);

    printf("\n[Edge cases: INT32_MAX / INT32_MIN]\n");
    int32_t MAX_INT =  2147483647;
    int32_t MIN_INT = -2147483648;
    test_mul(MAX_INT,  2);
    test_mul(2,  MAX_INT);
    test_mul(2,  MIN_INT);
    test_mul(MIN_INT, 2);

    printf("\nSimulation complete. Time = %lu ns\n", (unsigned long)ctx->time());

    // Flush any remaining state in the model (required before coverage write)
    top->final();

    // Write coverage data. VerilatedCov::write() dumps all instrumented counters
    // accumulated during simulation. Only has data when compiled with --coverage.
    VerilatedCov::write("coverage/coverage.dat");

    delete top;
    delete ctx;
    return 0;
}
