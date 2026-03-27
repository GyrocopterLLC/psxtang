import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock
from random import randint, getrandbits
import cv2
import numpy as np
from collections import deque
# from psx_vidgen import psx_vidgen

BURST_SIZE = 16

quit_all_coro = False

async def print_container(dut):

    cx = 0
    cy = 0
    frame_num = 0
    gg = np.zeros((720, 1280, 3), dtype=np.uint8)
    while not quit_all_coro:
        await RisingEdge(dut.vout_clk_i)
        if dut.vout_de_o.value == 1:
            if dut.o_container_active.value == 1:
                gg[cy, cx, :] = [255,255,255]
            else:
                gg[cy, cx, :] = [0,0,0]
            cx += 1
            if cx >= 1280:
                cx = 0
                cy += 1
                if cy >= 720:
                    cy = 0
                    cv2.imwrite(f'container_map_{frame_num:02d}.jpg', gg)
                    dut._log.info(f"Saved container_map_{frame_num:02d}.jpg")
                    frame_num += 1

async def print_scaled_image(dut, src_img):
    cx = 0
    cy = 0
    frame_num = 0
    gg = np.zeros((720, 1280, 3), dtype=np.uint8)
    while not quit_all_coro:
        await RisingEdge(dut.vout_clk_i)
        if dut.vout_de_o.value == 1:
            if dut.o_container_active.value == 1:
                src_x = int(dut.o_cx.value.to_unsigned())
                src_y = int(dut.o_cy.value.to_unsigned())
                gg[cy, cx, :] = src_img[src_y, src_x, :]
            else:
                gg[cy, cx, :] = [0,0,0]
            cx += 1
            if cx >= 1280:
                cx = 0
                cy += 1
                if cy >= 720:
                    cy = 0
                    cv2.imwrite(f'scaled_image_{frame_num:02d}.jpg', gg)
                    dut._log.info(f"Saved scaled_image_{frame_num:02d}.jpg")
                    frame_num += 1


async def frame_saver(dut, img_prefix = "frame_scaled_", sizex=1280, sizey=720):
    global quit_all_coro

    vid_dat = np.zeros((sizey,sizex,3),dtype=np.uint8)
    vidx = 0
    vidy = 0
    frame_num = 0
    while not quit_all_coro:
        await RisingEdge(dut.vout_clk_i)
        if dut.vout_de_o.value == 1:
            vid_dat[vidy,vidx,2] = dut.vout_b_o.value.to_unsigned()
            vid_dat[vidy,vidx,1] = dut.vout_g_o.value.to_unsigned()
            vid_dat[vidy,vidx,0] = dut.vout_r_o.value.to_unsigned()
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

async def ddr3_stub(dut):
    while not quit_all_coro:
        await RisingEdge(dut.vout_clk_i)
        if dut.vout_ddr3_data_req_o.value == 1:
            await Timer(randint(30, 150), unit='ns')
            await RisingEdge(dut.vout_clk_i)
            dut.vout_ddr3_rd_complete_i.value = 1
            await RisingEdge(dut.vout_clk_i)
            dut.vout_ddr3_rd_complete_i.value = 0

class ddr3_module:
    def __init__(self):
        self.quitnow = False
        self.buffer = deque()
    def destroy(self):
        self.quitnow = True

    async def ddr3_requester(self, dut, img_dat):
        this_line_reads = 0
        while not self.quitnow:
            await RisingEdge(dut.vout_clk_i)

            if dut.vout_ddr3_data_req_o.value == 1:
                img_x = dut.vout_ddr3_rd_pixel_o.value.to_unsigned()
                img_y = dut.vout_ddr3_rd_line_o.value.to_unsigned()

                if img_x == 0:
                    # dut._log.info(f"Reading line{img_y}, pixel{img_x} through {img_x + BURST_SIZE - 1}")
                    # dut._log.info(f"Issued {this_line_reads} pixel reads")
                    this_line_reads = 0
                    
                for i in range(BURST_SIZE):
                    if(img_x+i < img_dat.shape[1]):
                        self.buffer.append(img_dat[img_y, img_x + i, :])
                        this_line_reads += 1
                await Timer(randint(30,150), unit='ns') # something like 3 to 15 cycles of 100MHz clock? who knows.
                await RisingEdge(dut.vout_clk_i)
                dut.vout_ddr3_rd_complete_i.value = 1
                await RisingEdge(dut.vout_clk_i)
                dut.vout_ddr3_rd_complete_i.value = 0

    async def buffer_reader(self, dut):
        this_line_pops = 0
        while not self.quitnow:
            await RisingEdge(dut.vout_clk_i)
            if dut.vout_hsync_o.value == 1:
                if this_line_pops != 0:
                    # dut._log.info(f"Issued {this_line_pops} pixel pops")
                    this_line_pops = 0

            if dut.vout_buffer_rd_en_o.value == 1:
                this_line_pops += 1
                imgdat = self.buffer.popleft()
                dut.vout_buffer_rd_data_i.value = int(imgdat[0])*(2**16) + int(imgdat[1])*(2**8) + int(imgdat[2])


@cocotb.test()
async def test_read_ctrl(dut):

    global quit_all_coro

    
    # src_img = cv2.imread('ResidentEvil-320x240.png')
    src_img = cv2.imread('Castlevania-365x274.png')
    vin_height, vin_width, _ = src_img.shape

    # initialize inputs
    dut.rstn_i.value = 0
    dut.vin_width_i.value = vin_width
    dut.vin_height_i.value = vin_height
    dut.vout_width_i.value = 800
    dut.vout_height_i.value = 600

    dut.vout_bg_color_i.value = 0x0

    dut.vout_ddr3_rd_complete_i.value = 0
    dut.vout_buffer_rd_data_i.value = 0
    
    # start clocks
    # CEA-861 720p video clock (74.25 MHz)
    cocotb.start_soon(Clock(dut.vout_clk_i, 13.468, unit="ns").start())

    # release reset
    await Timer(100, unit="ns")
    dut.rstn_i.value = 1
    await Timer(100, unit="ns")

    cocotb.start_soon(print_container(dut))
    cocotb.start_soon(print_scaled_image(dut, src_img))
    cocotb.start_soon(frame_saver(dut, sizex=1280, sizey=720))
    # cocotb.start_soon(ddr3_stub(dut))
    dm = ddr3_module()
    cocotb.start_soon(dm.ddr3_requester(dut, src_img))
    cocotb.start_soon(dm.buffer_reader(dut))

    # just wait for some video signals.
    for i in range(50):
        await Timer(1, unit="ms")
        dut._log.info(f"{i+1} ms")

    quit_all_coro = True