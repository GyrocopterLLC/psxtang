import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock
import cv2
import struct

quit_all_coro = False

async def ddr_responder(dut):
    while not quit_all_coro:
        dut.ddr_busy_i.value = 1 # default to busy, make 'em wait!!
        await RisingEdge(dut.ddr_clk_i)
        if dut.ddr_wr_en_o.value == 1:
            dut.ddr_busy_i.value = 0
            await RisingEdge(dut.ddr_clk_i)
            dut.ddr_busy_i.value = 1

@cocotb.test()
async def test_inp(dut):
    global quit_all_coro

    # imgg = cv2.imread('ResidentEvil-320x240.png')
    imgg = cv2.imread('Castlevania-365x274.png')

    dut.rstn_i.value = 0

    dut.ddr_busy_i.value = 0
    dut.ddr_rd_data_i.value = 0
    dut.ddr_rd_data_valid_i.value = 0
    dut.vin_buf_wr_en_i.value = 0
    dut.vin_buf_data_i.value = 0

    dut.vin_buf_start_word_i.value = 0
    dut.vin_buf_line_i.value = 0
    dut.vin_buf_data_ready_i.value = 0
    dut.vin_buf_data_flush_i.value = 0
    dut.vin_line_length_i.value = int(imgg.shape[1] * 3 / 16) # number of bursts per line for a 320 pix wide image

    cocotb.start_soon(Clock(dut.vin_clk_i, 10, unit='ns').start())
    # cocotb.start_soon(Clock(dut.vout_clk_i, 8, unit='ns').start())
    cocotb.start_soon(Clock(dut.ddr_clk_i, 7.5, unit='ns').start())

    cocotb.start_soon(ddr_responder(dut))

    await ClockCycles(dut.vin_clk_i, 10)
    dut.rstn_i.value = 1
    await ClockCycles(dut.vin_clk_i, 10)

    
    for line_out in range(imgg.shape[0]):
        for i in range(imgg.shape[1]):
            await RisingEdge(dut.vin_clk_i)
            val_in = struct.unpack('BBB',imgg[line_out, i].tobytes())
            # val_in = (1 + (i << 4) + ((2 + (i << 4)) << 8) + (3 + (i << 4) << 16)) & 0xFFFFFF
            dut.vin_buf_wr_en_i.value = 1
            dut.vin_buf_data_i.value = val_in[0] + (val_in[1] << 8) + (val_in[2] << 16)
            await RisingEdge(dut.vin_clk_i)
            dut.vin_buf_wr_en_i.value = 0
            # dut.vin_buf_data_i.value = 0
            await ClockCycles(dut.vin_clk_i, 10)
            if i % 16 == 15: 
                # burst time!
                dut.vin_buf_start_word_i.value = int(i * 3 / 16)
                dut.vin_buf_line_i.value = line_out
                dut.vin_buf_data_ready_i.value = 1
                await RisingEdge(dut.vin_clk_i)
                dut.vin_buf_data_ready_i.value = 0
        await ClockCycles(dut.vin_clk_i, 100) # hfrontporch
        if imgg.shape[1] % 16 != 0:
            # fifo flush required
            dut.vin_buf_data_flush_i.value = 1
            await RisingEdge(dut.vin_clk_i)
            dut.vin_buf_data_flush_i.value = 0
            fifo_flush_counts = 1
        else:
            fifo_flush_counts = 0
        await ClockCycles(dut.vin_clk_i, 200 - fifo_flush_counts) # hsyncwidth + hbackporch
        if line_out % 10 == 0:
            dut._log.info(f"Finished line {line_out}")

    # final burst
    # dut.vin_buf_start_word_i.value = int(320*3/16)
    # dut.vin_buf_line_i.value = line_out
    # dut.vin_buf_data_ready_i.value = 1
    # await RisingEdge(dut.vin_clk_i)
    # dut.vin_buf_data_ready_i.value = 0


    await Timer(1,'us')

    quit_all_coro = True