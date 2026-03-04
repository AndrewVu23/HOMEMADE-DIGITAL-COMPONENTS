# HOMEMADE-DIGITAL-COMPONENTS

This is my collection of highly efficient digital components and modules that utilize modern algorithms. These components are designed to be easily integrated into future hardware projects, offering high performance and optimized designs.

## Multipliers

### Radix-2 and Radix-4 Booth Multipliers

#### Algorithm Overview
Booth's multiplication algorithm is a multiplication algorithm that multiplies two signed binary numbers in two's complement notation. 

* **Radix-2 Booth Multiplier**: Instead of simply adding the multiplicand for every '1' in the multiplier, Radix-2 examines 2 consecutive bits of the multiplier at a time and performs addition or subtraction, followed by a shift. This can skip over blocks of 1s and 0s, resulting in fewer additions/subtractions compared to a standard shift-and-add multiplier.
* **Radix-4 Booth Multiplier**: An evolution of Radix-2, the Radix-4 (or Modified Booth) algorithm examines 3 bits at a time (with 1 overlapping bit from the previous group) to reduce the number of partial products by half. This effectively means it can process two bits of the multiplier per cycle, operating roughly **twice as fast** as Radix-2 and significantly faster than a standard multiplier ($N/2$ cycles).

#### Performance vs. Standard Multiplier
* **Standard Multiplier (Shift-and-Add)**: Requires exactly $N$ cycles for an $N$-bit number, performing an addition for every '1' in the multiplier.
* **Radix-2**: Also takes $N$ cycles but significantly reduces the number of add/sub operations.
* **Radix-4**: Operates in $N/2$ cycles, halving the number of partial products and substantially increasing the performance speed.

#### Tradeoffs
While Booth multipliers offer significant performance boosts, they come with certain architectural tradeoffs:
* **Area/Complexity**: Radix-4 requires generating multiples like $2 \times \text{Multiplicand}$ (which is a fast left shift) and handling more complex multiplexer logic to select the correct operation (0, $+M$, $-M$, $+2M$, $-2M$). The control and combinational logic are larger than a basic multiplier.
* **Critical Path**: The muxes and arithmetic logic can marginally increase the critical path delay inside a single clock cycle, though the physical reduction in total cycle count for Radix-4 makes it well worth the cost.

### Design Choices

#### Algorithm Headspace for Edge Cases
In hardware multipliers handling signed (two's complement) numbers, intermediate padding or "headspace" must be allocated. This ensures that when adding and subtracting intermediate steps, we do not hit overflow, which is particularly crucial for handling minimum integer boundaries.

* **Radix-2 (33 bits for a 32-bit multiplier)**:
  * The worst-case arithmetic edge case occurs when subtracting the Multiplicand from the Accumulator. 
  * If the Multiplicand is the maximum negative number ($-2^{31}$), the operation $0 - (-2^{31})$ results in $+2^{31}$.
  * A standard 32-bit signed integer maxes out at $+2^{31}-1$. Thus, we add 1 bit of headspace, using a **33-bit** accumulator to safely store the intermediate $+2^{31}$ value without overflow.

* **Radix-4 (34 bits for a 32-bit multiplier)**:
  * The Radix-4 algorithm needs to perform operations up to $\pm 2 \times \text{Multiplicand}$.
  * The worst-case mathematical edge case is $0 - (2 \times -2^{31}) = +2^{32}$.
  * A 33-bit width can only represent up to $+2^{31}-1$. Thus, we need another extra bit of headspace. We design these combinational paths to be **34 bits** wide (bit 33 holds the value, bit 34 stores the correct sign bit) to gracefully capture this boundary case.
