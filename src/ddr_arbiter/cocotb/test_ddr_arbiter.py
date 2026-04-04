import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock
from collections import deque
import struct
from random import randint, getrandbits, choices

def prbs31_fast(code):
# Source - https://stackoverflow.com/a/63024100
# Posted by Hankyu Kim
# Retrieved 2026-03-28, License - CC BY-SA 4.0
    next_code = (~((code<<1)^(code<<4)) & 0xFFFFFFF0)
    next_code |= (~(( (code<<1 & 0x0E) | (next_code>>31 & 0x01)) ^ (next_code>>28)) & 0x0000000F)
    return next_code


class ddr_stub:
    def __init__(self, mem_size = 20, rwdelay = 40):
        self.quit_now = False
        self.mem = [getrandbits(8) for _ in range(2**mem_size)]
        self.rwdelay = rwdelay # default is 40ns to read or write from DDR memory

    async def run(self, dut):
        ddr_queue = deque()

        dut.ddr_busy_i.value = 0
        while not self.quit_now:
            if len(ddr_queue) > 7:
                dut.ddr_busy_i.value = 1
            else:
                dut.ddr_busy_i.value = 0
            await RisingEdge(dut.ddr_clk_i)
            
            current_time = cocotb.simtime.get_sim_time(unit='ns')
            # check to add things to the queue
            if len(ddr_queue) <= 7:
                ddraddr = dut.ddr_addr_o.value.to_unsigned()
                if dut.ddr_wr_en_o.value == 1:
                    ddrval = dut.ddr_wr_data_o.value.to_unsigned()
                    ddr_queue.append((current_time, ddraddr, ddrval))
                elif dut.ddr_rd_en_o.value == 1:
                    ddr_queue.append((current_time, ddraddr, None)) # None for write value means read

            # check to remove things from the queue
            readvalid = False
            if len(ddr_queue) > 0:
                if (ddr_queue[0][0] + self.rwdelay) <= current_time: 
                    
                    _, addr, value = ddr_queue.popleft()
                    if value is None:
                        # read data is ready
                        readvalid = True
                        # create 128 bits from 16 consecutive bytes
                        valbytes = bytes(self.mem[addr : (addr + 16)])
                        qlo, qhi = struct.unpack('<QQ', valbytes)
                        dut.ddr_rd_data_i.value = qlo + (qhi << 64)
                    else:
                        # write the value
                        valbytes = value.to_bytes(16, 'little')
                        valints = list(map(int, valbytes))
                        # assign to correct byte address in memory
                        self.mem[addr : (addr + 16)] = valints
            dut.ddr_rd_data_valid_i.value = 1 if readvalid else 0

    def destroy(self):
        self.quit_now = True

class ddr_requester:
    def __init__(self):
        self.quit_now = False

    def destroy(self):
        self.quit_now = True

    async def read_listener(self, dut, channel: int, size: int, initial_prbs: int):
        prbs = initial_prbs
        for i in range(size):
            val_expected = prbs
            prbs = prbs31_fast(prbs)
            val_expected += (prbs << 32)
            prbs = prbs31_fast(prbs)
            val_expected += (prbs << 64)
            prbs = prbs31_fast(prbs)
            val_expected += (prbs << 96)
            prbs = prbs31_fast(prbs)
            if channel == 1:
                while dut.ddr1_rd_data_valid_o.value == 0:
                    await RisingEdge(dut.ddr_clk_i)
                val_in = dut.ddr1_rd_data_o.value.to_unsigned()

            if channel == 2:
                while dut.ddr2_rd_data_valid_o.value == 0:
                    await RisingEdge(dut.ddr_clk_i)
                val_in = dut.ddr2_rd_data_o.value.to_unsigned()
            if channel == 3:
                while dut.ddr3_rd_data_valid_o.value == 0:
                    await RisingEdge(dut.ddr_clk_i)
                val_in = dut.ddr3_rd_data_o.value.to_unsigned()
            if val_in != val_expected:
                dut._log.error(f"Mismatch Channel {channel}, read number {i}. Expected {val_expected:016X}, read {val_in:016X}")
                assert(False)

            await RisingEdge(dut.ddr_clk_i)

    async def run_prbs(self, dut, channel: int, start_addr: int, size: int):
        # note: size is number of 32 bit words
        burst_read = True
        burst_write = True
        
        while not self.quit_now:
            prbs = channel + (channel << 8) + (channel << 16) + (channel << 24) # some kinda initializer
            burstcnt = 8
            for i in range(size):
                val_out = prbs
                prbs = prbs31_fast(prbs)
                val_out += (prbs << 32)
                prbs = prbs31_fast(prbs)
                val_out += (prbs << 64)
                prbs = prbs31_fast(prbs)
                val_out += (prbs << 96)
                prbs = prbs31_fast(prbs)
                if channel == 1:
                    dut.ddr1_addr_i.value = start_addr + (16*i)
                    dut.ddr1_rd_en_i.value = 0
                    dut.ddr1_wr_en_i.value = 1
                    dut.ddr1_wr_data_i.value = val_out
                elif channel == 2:
                    dut.ddr2_addr_i.value = start_addr + (16*i)
                    dut.ddr2_rd_en_i.value = 0
                    dut.ddr2_wr_en_i.value = 1
                    dut.ddr2_wr_data_i.value = val_out
                elif channel == 3:
                    dut.ddr3_addr_i.value = start_addr + (16*i)
                    dut.ddr3_rd_en_i.value = 0
                    dut.ddr3_wr_en_i.value = 1
                    dut.ddr3_wr_data_i.value = val_out
                
                await RisingEdge(dut.ddr_clk_i)
                if channel == 1:
                    while dut.ddr1_busy_o.value == 1:
                        await RisingEdge(dut.ddr_clk_i)
                elif channel == 2:
                    while dut.ddr2_busy_o.value == 1:
                        await RisingEdge(dut.ddr_clk_i)
                elif channel == 3:
                    while dut.ddr3_busy_o.value == 1:
                        await RisingEdge(dut.ddr_clk_i)

                if burst_read:
                    burstcnt = burstcnt - 1
                    if burstcnt == 0:
                        burstcnt = 8
                        if channel == 1:
                            dut.ddr1_wr_en_i.value = 0
                        elif channel == 2:
                            dut.ddr2_wr_en_i.value = 0
                        elif channel == 3:
                            dut.ddr3_wr_en_i.value = 0
                        await ClockCycles(dut.ddr_clk_i, randint(16,64))
                else:
                    if channel == 1:
                        dut.ddr1_wr_en_i.value = 0
                    elif channel == 2:
                        dut.ddr2_wr_en_i.value = 0
                    elif channel == 3:
                        dut.ddr3_wr_en_i.value = 0
                    await ClockCycles(dut.ddr_clk_i, randint(4,16))

            prbs = channel + (channel << 8) + (channel << 16) + (channel << 24) # same initialization
            cocotb.start_soon(self.read_listener(dut, channel = channel, size = size, initial_prbs = prbs))
            for i in range(size):
                if channel == 1:
                    dut.ddr1_addr_i.value = start_addr + (16*i)
                    dut.ddr1_rd_en_i.value = 1
                    dut.ddr1_wr_en_i.value = 0
                elif channel == 2:
                    dut.ddr2_addr_i.value = start_addr + (16*i)
                    dut.ddr2_rd_en_i.value = 1
                    dut.ddr2_wr_en_i.value = 0
                elif channel == 3:
                    dut.ddr3_addr_i.value = start_addr + (16*i)
                    dut.ddr3_rd_en_i.value = 1
                    dut.ddr3_wr_en_i.value = 0
                
                await RisingEdge(dut.ddr_clk_i)
                if channel == 1:
                    while dut.ddr1_busy_o.value == 1:
                        await RisingEdge(dut.ddr_clk_i)
                elif channel == 2:
                    while dut.ddr2_busy_o.value == 1:
                        await RisingEdge(dut.ddr_clk_i)
                elif channel == 3:
                    while dut.ddr3_busy_o.value == 1:
                        await RisingEdge(dut.ddr_clk_i)

                if burst_read:
                    burstcnt = burstcnt - 1
                    if burstcnt == 0:
                        burstcnt = 8
                        if channel == 1:
                            dut.ddr1_rd_en_i.value = 0
                        elif channel == 2:
                            dut.ddr2_rd_en_i.value = 0
                        elif channel == 3:
                            dut.ddr3_rd_en_i.value = 0
                        await ClockCycles(dut.ddr_clk_i, randint(16,64))
                else:
                    if channel == 1:
                        dut.ddr1_rd_en_i.value = 0
                    elif channel == 2:
                        dut.ddr2_rd_en_i.value = 0
                    elif channel == 3:
                        dut.ddr3_rd_en_i.value = 0
                    await ClockCycles(dut.ddr_clk_i, randint(4,16))

    async def run_m1(self, dut):
        while not self.quit_now:
            addr = int(4*randint(0,262143))
            read_nwrite = choices([True,False],[0.5,0.5])[0]
            burst = choices([1,4,16],[0.8,0.1,0.1])[0] # bursty every once in a while
            while burst > 0:
                dut.ddr1_addr_i.value = addr
                if read_nwrite:
                    dut.ddr1_rd_en_i.value = 1
                    dut.ddr1_wr_en_i.value = 0
                else:
                    dut.ddr1_wr_en_i.value = 1
                    dut.ddr1_rd_en_i.value = 0
                    dut.ddr1_wr_data_i.value = getrandbits(128)
                await RisingEdge(dut.ddr_clk_i)
                while dut.ddr1_busy_o.value == 1:
                    await RisingEdge(dut.ddr_clk_i)
                burst = burst - 1
                addr = addr + 4
            dut.ddr1_wr_en_i.value = 0
            dut.ddr1_rd_en_i.value = 0
            delay_count = choices([1, 4, 32],[0.2, 0.6, 0.2])[0]
            await ClockCycles(dut.ddr_clk_i, delay_count)

    async def run_m2(self, dut):
        while not self.quit_now:
            addr = int(4*randint(0,262143))
            read_nwrite = choices([True,False],[0.5,0.5])[0]
            burst = choices([1,4,16],[0.8,0.1,0.1])[0] # bursty every once in a while
            while burst > 0:
                dut.ddr2_addr_i.value = addr
                if read_nwrite:
                    dut.ddr2_rd_en_i.value = 1
                    dut.ddr2_wr_en_i.value = 0
                else:
                    dut.ddr2_wr_en_i.value = 1
                    dut.ddr2_rd_en_i.value = 0
                    dut.ddr2_wr_data_i.value = getrandbits(128)
                await RisingEdge(dut.ddr_clk_i)
                while dut.ddr2_busy_o.value == 1:
                    await RisingEdge(dut.ddr_clk_i)
                burst = burst - 1
                addr = addr + 4
            dut.ddr2_wr_en_i.value = 0
            dut.ddr2_rd_en_i.value = 0
            delay_count = choices([1, 4, 32],[0.2, 0.6, 0.2])[0]
            await ClockCycles(dut.ddr_clk_i, delay_count)
            
    async def run_m3(self, dut):
        while not self.quit_now:
            addr = int(4*randint(0,262143))
            read_nwrite = choices([True,False],[0.5,0.5])[0]
            burst = choices([1,4,16],[0.8,0.1,0.1])[0] # bursty every once in a while
            while burst > 0:
                dut.ddr3_addr_i.value = addr
                if read_nwrite:
                    dut.ddr3_rd_en_i.value = 1
                    dut.ddr3_wr_en_i.value = 0
                else:
                    dut.ddr3_wr_en_i.value = 1
                    dut.ddr3_rd_en_i.value = 0
                    dut.ddr3_wr_data_i.value = getrandbits(128)
                await RisingEdge(dut.ddr_clk_i)
                while dut.ddr3_busy_o.value == 1:
                    await RisingEdge(dut.ddr_clk_i)
                burst = burst - 1
                addr = addr + 4
            dut.ddr3_wr_en_i.value = 0
            dut.ddr3_rd_en_i.value = 0
            delay_count = choices([1, 4, 32],[0.2, 0.6, 0.2])[0]
            await ClockCycles(dut.ddr_clk_i, delay_count)


@cocotb.test()
async def test_ddr_arbiter(dut):
    # initial values
    dut.rstn_i.value = 0

    dut.ddr1_wr_en_i.value = 0
    dut.ddr1_rd_en_i.value = 0
    dut.ddr1_addr_i.value = 0
    dut.ddr1_wr_data_i.value = 0

    dut.ddr2_wr_en_i.value = 0
    dut.ddr2_rd_en_i.value = 0
    dut.ddr2_addr_i.value = 0
    dut.ddr2_wr_data_i.value = 0

    dut.ddr3_wr_en_i.value = 0
    dut.ddr3_rd_en_i.value = 0
    dut.ddr3_addr_i.value = 0
    dut.ddr3_wr_data_i.value = 0

    dut.ddr_busy_i.value = 0
    dut.ddr_rd_data_i.value = 0
    dut.ddr_rd_data_valid_i.value = 0

    cocotb.start_soon(Clock(dut.ddr_clk_i, 10, unit='ns').start())

    await ClockCycles(dut.ddr_clk_i, 10)
    dut.rstn_i.value = 1
    await ClockCycles(dut.ddr_clk_i, 10)

    # try a few reads / writes 
    ddr = ddr_stub(rwdelay=200)
    cocotb.start_soon(ddr.run(dut))

    requester = ddr_requester()
    # cocotb.start_soon(requester.run_m1(dut))
    # cocotb.start_soon(requester.run_m2(dut))
    # cocotb.start_soon(requester.run_m3(dut))
    cocotb.start_soon(requester.run_prbs(dut, 1, 0, 512))
    await ClockCycles(dut.ddr_clk_i, 17)
    cocotb.start_soon(requester.run_prbs(dut, 2, 16384, 512))
    await ClockCycles(dut.ddr_clk_i, 11)
    cocotb.start_soon(requester.run_prbs(dut, 3, 32768, 512))

    # for _ in range(100):
    #     # let's just use port 2 and see what happens
    #     dut.ddr2_addr_i.value = int(4*randint(0, 262143))
    #     # read_nwrite = randint(0,1)
    #     read_nwrite = 1
    #     if read_nwrite == 0:
    #         dut.ddr2_wr_en_i.value = 1
    #         dut.ddr2_wr_data_i.value = getrandbits(128)
    #     else:
    #         dut.ddr2_rd_en_i.value = 1
    #     await RisingEdge(dut.ddr_clk_i)
    #     # wait for busy to be low for a cycle
    #     while dut.ddr2_busy_o.value == 1:
    #         await RisingEdge(dut.ddr_clk_i)

        
    #     dut.ddr2_wr_en_i.value = 0
    #     dut.ddr2_rd_en_i.value = 0

    #     # await ClockCycles(dut.ddr_clk_i, 4)

    await ClockCycles(dut.ddr_clk_i, 100000)

    ddr.destroy()
    requester.destroy()

