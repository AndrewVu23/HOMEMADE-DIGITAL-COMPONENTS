import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

async def init_and_reset(dut):
    # 100MHz clock
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start()) 

    dut.rst.value = 1
    dut.en.value = 0
    dut.M.value = 0
    dut.Q.value = 0

    # 2-cycle delay
    for _ in range(2):
        await RisingEdge(dut.clk)
    
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def perform_multiplication(dut, multiplicand: int, multiplier: int):
    expected_product = multiplicand * multiplier

    dut.M.value = multiplicand
    dut.Q.value = multiplier
    
    dut.en.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.en.value = 0
    
    N = int(dut.N.value)
    COUNT = int(dut.COUNT.value)
    
    # Wait until it reaches STOP state or wait at least N + 5 (21) clock cycles before moving on to the next step
    # since we need 18 cycles to run (2 cycles for IDLE/STOP, 16 cycles for CALC). I choose 21 just to be safe.
    for _ in range(COUNT + 5):
        await RisingEdge(dut.clk)

    # Verify output P by converting it from binary to signed integer
    try:
        actual_product = dut.P.value.to_signed()
    except ValueError:
        raise AssertionError(f"Output product P contained X or Z for {multiplicand} * {multiplier}")

    assert actual_product == expected_product, f"Failed: {multiplicand} * {multiplier} -> Expected {expected_product}, got {actual_product}"
    dut._log.info(f"Passed: {multiplicand:5} * {multiplier:5} = {actual_product}")


@cocotb.test()
async def radix4mul_tb(dut):  
    await init_and_reset(dut)

    N = int(dut.N.value)
    dut._log.info(f"Multiplier parameter N={N}")

    # Basic Positive Numbers
    dut._log.info("Testing Positive Numbers...")
    await perform_multiplication(dut, 5, 3)
    await perform_multiplication(dut, 10, 15)
    await perform_multiplication(dut, 43, 22)

    # Negative Numbers
    dut._log.info("Testing Negative Numbers...")
    await perform_multiplication(dut, -5, 3)
    await perform_multiplication(dut, 5, -3)
    await perform_multiplication(dut, -5, -3)
    await perform_multiplication(dut, -15, -15)

    # Zeros and Ones
    dut._log.info("Testing Zeros and Ones...")
    await perform_multiplication(dut, 0, 5)
    await perform_multiplication(dut, 5, 0)
    await perform_multiplication(dut, 0, 0)
    await perform_multiplication(dut, 1, 1)
    await perform_multiplication(dut, -1, 1)
    
    # Edge Cases
    dut._log.info("Testing Edge Cases (Min/Max values)...")
    MAX_INT = (1 << (N - 1)) - 1
    MIN_INT = -(1 << (N - 1))
    
    await perform_multiplication(dut, MAX_INT, 2)
    await perform_multiplication(dut, 2, MAX_INT)
    await perform_multiplication(dut, 2, MIN_INT)
    await perform_multiplication(dut, MIN_INT, 2)
    await perform_multiplication(dut, MIN_INT, MIN_INT)
    await perform_multiplication(dut, MAX_INT, MAX_INT)

    # Randomized Tests 
    dut._log.info("Testing Random Numbers...")
    for _ in range(30):
        m = random.randint(MIN_INT, MAX_INT)
        q = random.randint(MIN_INT, MAX_INT)
        await perform_multiplication(dut, m, q)
