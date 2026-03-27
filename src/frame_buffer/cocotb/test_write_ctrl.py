import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock
import cv2
import numpy as np
from psx_vidgen import psx_vidgen

quit_all_coro = False

'''
async def ddr3_reader(dut):
    image_data = np.zeros((240, 320, 3), dtype=np.uint8)

    # img_x = 0
    # img_y = 0
    frame_num = 0
    while not quit_all_coro:
        await RisingEdge(dut.ddr3_clk_i)
        if dut.ddr3_data_ready_o.value == 1:
            # read a chunk of 16 pixels
            pix_dat = []
            # buf_addr = 16 if dut.ddr3_buffer_half_o.value == 1 else 0
            # dut.ddr3_rd_addr_i.value = buf_addr

            # get video x, y locations
            vidx = dut.ddr3_buffer_start_pixel_o.value.to_unsigned()
            vidy = dut.ddr3_buffer_line_o.value.to_unsigned()

            dut.ddr3_rd_en_i.value = 1
            for i in range(16):
                await RisingEdge(dut.ddr3_clk_i)
                pix_dat.append(dut.ddr3_data_o.value.to_unsigned())
                # dut.ddr3_rd_addr_i.value = (buf_addr + i + 1) % 32

            dut.ddr3_rd_en_i.value = 0
            for i in range(16):
                r = (pix_dat[i] >> 16) & 0xFF
                g = (pix_dat[i] >> 8) & 0xFF
                b = pix_dat[i] & 0xFF
                image_data[vidy, vidx+i, :] = [b, g, r]
                # img_x += 1
                # if img_x >= 320:
                    # img_x = 0
                    # img_y += 1
                    # if img_y >= 240:
                        # img_y = 0
                        # dut._log.info(f"Frame {frame_num} finished.")
                        # cv2.imwrite(f'ddr3_read_frame_{frame_num:02d}.jpg', image_data)
                        # frame_num += 1
            if vidy == 239 and vidx == (320 - 16):
                dut._log.info(f"Frame {frame_num} finished.")
                cv2.imwrite(f'ddr3_read_frame_{frame_num:02d}.jpg', image_data)
                frame_num += 1
'''

                

@cocotb.test()
async def test_write_ctrl(dut):
    imgfilename = 'ResidentEvil-320x240.png'
    # imgfilename = 'Castlevania-299x224.png'
    
    gg = cv2.imread(imgfilename)

    # initialize inputs to zero
    dut.vin_hsync_i.value = 0
    dut.rstn_i.value = 0
    dut.vin_vsync_i.value = 0
    dut.vin_de_i.value = 0
    dut.vin_ce_i.value = 0
    dut.vin_r_i.value = 0
    dut.vin_g_i.value = 0
    dut.vin_b_i.value = 0

    dut.vin_width_i.value = gg.shape[1]
    dut.vin_height_i.value = gg.shape[0]

    # dut.ddr3_rd_en_i.value = 0
    # dut.ddr3_rd_addr_i.value = 0
    

    # start clocks
    # vin clock = 53.693175 MHz (PSX GPU clock freq)
    cocotb.start_soon(Clock(dut.vin_clk_i, 18.62, unit="ns").start())

    # release reset
    await Timer(100, unit="ns")
    dut.rstn_i.value = 1
    await Timer(100, unit="ns")

    # start video input
    htot = gg.shape[1] + 106
    vtot = gg.shape[0] + 23
    vidgen = psx_vidgen(image = imgfilename,
                        hact=gg.shape[1],
                        vact=gg.shape[0],
                        htot=htot,
                        vtot=vtot)

    cocotb.start_soon(vidgen.run(dut.vin_clk_i, dut.vin_ce_i, dut.vin_de_i, dut.vin_vsync_i, dut.vin_hsync_i, dut.vin_r_i, dut.vin_g_i, dut.vin_b_i))
    # cocotb.start_soon(ddr3_reader(dut))


    for i in range(18):
        await Timer(1, unit="ms")
        dut._log.info(f"Test running... {i+1} ms")

    vidgen.destroy()

    quit_all_coro = True

