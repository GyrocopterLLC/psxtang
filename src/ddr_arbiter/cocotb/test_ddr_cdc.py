import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock
import cv2
import numpy as np
from collections import deque
import struct
from random import randint, getrandbits


class ddr_stub:
    def __init__(self, mem_size = 26):
        self.quit_now = False
        self.mem = [0xFF for _ in range(2**mem_size)]

    async def run(self, dut):
        ddr_queue = deque()

        dut.m2_busy_i.value = 0
        while not self.quit_now:
            if len(ddr_queue) > 7:
                dut.m2_busy_i.value = 1
            else:
                dut.m2_busy_i.value = 0
            await RisingEdge(dut.m2_clk_i)
            
            current_time = cocotb.simtime.get_sim_time(unit='ns')
            # check to add things to the queue
            if len(ddr_queue) <= 7:
                ddraddr = dut.m2_addr_o.value.to_unsigned()
                if dut.m2_wr_en_o.value == 1:
                    ddrval = dut.m2_wr_data_o.value.to_unsigned()
                    ddr_queue.append((current_time, ddraddr, ddrval))
                elif dut.m2_rd_en_o.value == 1:
                    ddr_queue.append((current_time, ddraddr, None)) # None for write value means read

            # check to remove things from the queue
            readvalid = False
            if len(ddr_queue) > 0:
                if (ddr_queue[0][0] + 40) <= current_time: 
                    # let's say it takes 40 ns to read or write DDR
                    _, addr, value = ddr_queue.popleft()
                    if value is None:
                        # read data is ready
                        readvalid = True
                        # create 128 bits from 16 consecutive bytes
                        # address is 128-bit words, so multiply by 16 for bytes
                        valbytes = bytes(self.mem[addr*16 : (addr*16) + 16])
                        qlo, qhi = struct.unpack('<QQ', valbytes)
                        dut.m2_rd_data_i.value = qlo + (qhi << 64)
                    else:
                        # write the value
                        valbytes = value.to_bytes(16, 'little')
                        valints = list(map(int, valbytes))
                        # assign to correct byte address in memory
                        # address is 128-bit words, so multiply by 16 for bytes
                        self.mem[addr*16 : (addr*16) + 16] = valints
            dut.m2_rd_data_valid_i.value = 1 if readvalid else 0

    def destroy(self):
        self.quit_now = True


@cocotb.test()
async def test_ddr_cdc(dut):
    dut.rstn_i.value = 0
    dut.m1_rd_en_i.value = 0
    dut.m1_wr_en_i.value = 0
    dut.m1_addr_i.value = 0
    dut.m1_wr_data_i.value = 0

    # pretend to be PSX (67 MHz) and 350 MHz DDR (so divide by 4 = 87.5 MHz)
    cocotb.start_soon(Clock(dut.m1_clk_i, 14.92, unit='ns').start())
    cocotb.start_soon(Clock(dut.m2_clk_i, 11.42, unit='ns').start())

    await ClockCycles(dut.m1_clk_i, 10)
    dut.rstn_i.value = 1

    await ClockCycles(dut.m1_clk_i, 10)

    ddr = ddr_stub(mem_size = 20) 
    cocotb.start_soon(ddr.run(dut))

    for _ in range(100):
        await RisingEdge(dut.m1_clk_i)
        dut.m1_addr_i.value = 4*randint(0, 511)
        read_or_write = randint(0,1)
        if read_or_write == 1:
            dut.m1_rd_en_i.value = 1
            dut.m1_wr_en_i.value = 0
        else:
            dut.m1_wr_en_i.value = 1
            dut.m1_rd_en_i.value = 0
            dut.m1_wr_data_i.value = getrandbits(128)
        d_amt = randint(0, 8)
        if d_amt != 0:
            await RisingEdge(dut.m1_clk_i)
            dut.m1_wr_en_i.value = 0
            dut.m1_rd_en_i.value = 0
            await ClockCycles(dut.m1_clk_i, d_amt-1)

    await ClockCycles(dut.m1_clk_i, 32)

    ddr.destroy()
