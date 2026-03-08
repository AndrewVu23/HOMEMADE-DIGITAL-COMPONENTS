import cocotb
from cocotb.triggers import Timer
import random

async def perform_multiplication(dut, a: int, b: int):
    expected_product = a * b

    dut.A.value = a
    dut.B.value = b
    
    # Wait for combinational logic to settle
    await Timer(1, units="ns")
    
    try:
        actual_product = dut.p.value.integer
    except ValueError:
        raise AssertionError(f"Output product p contained X or Z for {a} * {b}: {dut.p.value.binstr}")

    assert actual_product == expected_product, f"Failed: {a} * {b} -> Expected {expected_product}, got {actual_product}"
    dut._log.info(f"Passed: {a:3} * {b:3} = {actual_product}")


@cocotb.test()
async def wallacemul_tb(dut):  
    dut._log.info("Testing Combinational Wallace Tree Multiplier...")

    # Zeros and Ones
    dut._log.info("Testing Zeros and Ones...")
    await perform_multiplication(dut, 0, 5)
    await perform_multiplication(dut, 5, 0)
    await perform_multiplication(dut, 0, 0)
    await perform_multiplication(dut, 1, 1)

    # Basic Positive Numbers
    dut._log.info("Testing Basic Numbers...")
    await perform_multiplication(dut, 5, 3)
    await perform_multiplication(dut, 10, 15)
    await perform_multiplication(dut, 43, 22)
    
    # Edge Cases (Min/Max values for 8-bit unsigned)
    dut._log.info("Testing Edge Cases (Min/Max values)...")
    MAX_INT = 255
    MIN_INT = 0
    
    await perform_multiplication(dut, MAX_INT, 2)
    await perform_multiplication(dut, 2, MAX_INT)
    await perform_multiplication(dut, MAX_INT, MAX_INT)

    # Randomized Tests 
    dut._log.info("Testing Random Numbers...")
    for _ in range(100):
        a = random.randint(MIN_INT, MAX_INT)
        b = random.randint(MIN_INT, MAX_INT)
        await perform_multiplication(dut, a, b)
