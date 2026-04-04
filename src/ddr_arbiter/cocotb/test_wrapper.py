import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock


@cocotb.test()
async def test_wrapper(dut):
    dut.rstn_i.value = 0
    cocotb.start_soon(Clock(dut.clk_i, 10, 'ns').start())
    await ClockCycles(dut.clk_i, 10)
    dut.rstn_i.value = 1
    await Timer(10, 'us')

    