import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock
import cv2
import numpy as np
from psx_vidgen import psx_vidgen
from ddr_stub import ddr_stub

quit_all_coro = False

async def frame_saver(dut, img_prefix = "frame_scaled_", sizex=1280, sizey=720):
    global quit_all_coro

    vid_dat = np.zeros((sizey,sizex,3),dtype=np.uint8)
    vidx = 0
    vidy = 0
    frame_num = 0
    while not quit_all_coro:
        await RisingEdge(dut.vout_clk_i)
        if dut.vout_de_o.value == 1:
            vid_dat[vidy,vidx,2] = dut.vout_r_o.value.to_unsigned()
            vid_dat[vidy,vidx,1] = dut.vout_g_o.value.to_unsigned()
            vid_dat[vidy,vidx,0] = dut.vout_b_o.value.to_unsigned()
            # dut._log.info(f"Recorded pixel {vidx}, {vidy} = {vid_dat[vidx,vidy,:]}")
            vidx += 1
            if vidx >= sizex:
                # dut._log.info(f"New line! Completed line {vidy}")
                vidx = 0
                vidy += 1
                if vidy >= sizey:
                    # frame done!
                    dut._log.info('Frame done!')
                    cv2.imwrite(f'{img_prefix}{frame_num:03}.jpg', vid_dat)
                    vid_dat[:] = 0
                    frame_num += 1
                    vidy = 0
        else:
            if vidx != 0 or vidy != 0:
                if dut.vout_vsync_o.value == 1:
                    dut._log.info('Early frame write')
                    cv2.imwrite(f'{img_prefix}{frame_num:03}.jpg', vid_dat)
                    vid_dat[:] = 0
                    frame_num += 1
                    vidx = 0
                    vidy = 0

                
@cocotb.test()
async def test_fb(dut):
    imgfilename = 'ResidentEvil-320x240.png'
    # imgfilename = 'Castlevania-299x224.png'
    
    gg = cv2.imread(imgfilename)

    # initialize inputs to zero
    dut.rstn_i.value = 0

    dut.vin_hsync_i.value = 0
    dut.vin_vsync_i.value = 0
    dut.vin_de_i.value = 0
    dut.vin_ce_i.value = 0
    dut.vin_r_i.value = 0
    dut.vin_g_i.value = 0
    dut.vin_b_i.value = 0

    dut.vin_width_i.value = gg.shape[1]
    dut.vin_height_i.value = gg.shape[0]

    dut.vout_width_i.value = 800
    dut.vout_height_i.value = 600
    dut.vout_bg_color_i.value = 0x0

    dut.mem_busy_i.value = 0
    dut.mem_rd_data_i.value = 0
    dut.mem_rd_data_valid_i.value = 0


    # start clocks
    # vin clock = 53.693175 MHz (PSX GPU clock freq)
    cocotb.start_soon(Clock(dut.vin_clk_i, 18.62, unit="ns").start())
    # vout clock = 74.25 MHz (CEA-861 720p pixel clock)
    cocotb.start_soon(Clock(dut.vout_clk_i, 13.468, unit="ns").start())
    # ddr clock = 67.7376 MHz (PSX CPU x2)
    cocotb.start_soon(Clock(dut.mem_clk_i, 14.762, unit="ns").start())
    cocotb.start_soon(frame_saver(dut,sizex=1280,sizey=720))

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
    ddrstub = ddr_stub()

    cocotb.start_soon(vidgen.run(dut.vin_clk_i, dut.vin_ce_i, dut.vin_de_i, dut.vin_vsync_i, dut.vin_hsync_i, dut.vin_r_i, dut.vin_g_i, dut.vin_b_i))
    # cocotb.start_soon(ddr3_reader(dut))
    cocotb.start_soon(ddrstub.run(dut))

    for i in range(105):
        await Timer(1, unit="ms")
        dut._log.info(f"Test running... {i+1} ms")

    vidgen.destroy()
    ddrstub.destroy()

    quit_all_coro = True

