import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock
import struct
from collections import deque
from random import getrandbits

class ddr_stub:
    def __init__(self, mem_size = 26):
        self.quit_now = False
        self.mem = [0xFF for _ in range(2**mem_size)]

    async def run(self, dut):
        ddr_queue = deque()

        dut.mem_busy_i.value = 0
        while not self.quit_now:
            if len(ddr_queue) > 7:
                dut.mem_busy_i.value = 1
            else:
                dut.mem_busy_i.value = 0
            await RisingEdge(dut.mem_clk_i)
            
            current_time = cocotb.simtime.get_sim_time(unit='ns')
            # check to add things to the queue
            if len(ddr_queue) <= 7:
                ddraddr = dut.mem_addr_o.value.to_unsigned()
                if dut.mem_wr_en_o.value == 1:
                    ddrval = dut.mem_wr_data_o.value.to_unsigned()
                    ddr_queue.append((current_time, ddraddr, ddrval))
                elif dut.mem_rd_en_o.value == 1:
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
                        dut.mem_rd_data_i.value = qlo + (qhi << 64)
                    else:
                        # write the value
                        valbytes = value.to_bytes(16, 'little')
                        valints = list(map(int, valbytes))
                        # assign to correct byte address in memory
                        # address is 128-bit words, so multiply by 16 for bytes
                        self.mem[addr*16 : (addr*16) + 16] = valints
            dut.mem_rd_data_valid_i.value = 1 if readvalid else 0

    def destroy(self):
        self.quit_now = True