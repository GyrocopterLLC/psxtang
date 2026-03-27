import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.clock import Clock
from random import getrandbits
import struct
import cv2
from collections import deque
quit_all_coro = False

random_pixels = [getrandbits(8) for _ in range(9*16)]

def get_pixel(i):
    bb = bytes(random_pixels[int(i*3):int((i+1)*3)]) + b'\x00'
    return struct.unpack('<L', bb)[0]

def get_fifo(i):
    bb = bytes(random_pixels[int(16*i):int(16*(i+1))])
    lo, = struct.unpack('<Q', bb[0:8])
    hi, = struct.unpack('<Q', bb[8:16])
    return lo + (hi << 64)

async def fake_fifo(dut):
    fifo_count = 1
    while not quit_all_coro:
        await RisingEdge(dut.vout_clk_i)
        if dut.o_fifo_pop.value == 1:
            if fifo_count < len(random_pixels)//16:
                dut.o_fifo_rd_data.value = get_fifo(fifo_count)
                dut._log.info(f"fifo {fifo_count} = {hex(get_fifo(fifo_count))}")
                dut._log.info(f"fifo {fifo_count} = {list(map(hex, random_pixels[16*fifo_count:16*(fifo_count+1)]))}")
            else:
                dut.o_fifo_rd_data.value = -1
                dut._log.info(f"fifo {fifo_count} popped junk data")
            fifo_count += 1

async def fifo_loader(dut):

    for i in range(len(random_pixels) // 16):
        await RisingEdge(dut.ddr_clk_i)
        dut.ddr_rd_data_i.value = get_fifo(i)
        dut.ddr_rd_data_valid_i.value = 1
    await RisingEdge(dut.ddr_clk_i)
    dut.ddr_rd_data_valid_i.value = 0

async def ddr_stub(dut, imgdat):
    requests = deque()

    while not quit_all_coro:
        await RisingEdge(dut.ddr_clk_i)
        current_time = cocotb.simtime.get_sim_time(unit='ns')
        if dut.ddr_rd_en_o.value == 1:
            requests.append((current_time, dut.ddr_addr_o.value.to_unsigned()))
        if len(requests) > 0:
            # let's say it takes 15ns to retrieve a value
            if requests[0][0] + 15 < current_time:
                _, reqaddr = requests.popleft()
                # figure out row, column addressing using the internal values
                line_addr = dut.i_addr_shift.value.to_unsigned()
                line_req = reqaddr >> line_addr
                burst_req = reqaddr & ((1 << line_addr) - 1) # note this is burst number, not actually pixel number
                pix_num = int((burst_req * 16) // 3) # 16 bytes per burst, 3 bytes per pixel
                pix_overlap = int((burst_req * 16) % 3) # this number is how many bytes of this pixel already sent
                rgb = pix_overlap
                imgx = pix_num
                imgy = line_req
                # dut._log.info(f"Request: Line {imgy}, pixel {imgx}, offset {rgb}")
                outb = bytearray([0]*16)
                for i in range(16):
                    if imgy < imgdat.shape[0] and imgx < imgdat.shape[1]:
                        outb[15-i] = imgdat[imgy, imgx, 2 - rgb] # opencv is B,G,R ordered and I prefer R,G,B
                    else:
                        outb[15-i] = getrandbits(8)
                    rgb += 1
                    if rgb >= 3:
                        rgb = 0
                        imgx += 1
                burst_hi, burst_lo = struct.unpack('>QQ', bytes(outb))
                dut.ddr_rd_data_valid_i.value = 1
                dut.ddr_rd_data_i.value = burst_lo + (burst_hi << 64)
            else:
                dut.ddr_rd_data_valid_i.value = 0
        else:
            dut.ddr_rd_data_valid_i.value = 0
                

@cocotb.test()
async def test_inp(dut):
    global quit_all_coro

    imgdat = cv2.imread('ResidentEvil-320x240.png')
    # imgdat = cv2.imread('Castlevania-365x274.png')

    dut.rstn_i.value = 0
    
    dut.vout_ddr3_data_req_i.value = 0
    dut.vout_ddr3_rd_line_i.value = 0
    dut.vout_ddr3_rd_pixel_i.value = 0
    dut.vout_ddr3_rd_word_i.value = 0
    dut.vout_buffer_rd_en_i.value = 0

    dut.ddr_busy_i.value = 0
    dut.ddr_rd_data_valid_i.value = 0
    dut.ddr_rd_data_i.value = 0

    dut.vin_line_length_i.value = int(imgdat.shape[1] * 3 / 16) # number of bursts per line for a ~320~ 365 pix wide image
    # dut.o_fifo_rd_data.value = get_fifo(0)
    # dut.o_fifo_rd_data.value = get_fifo(0)
    # dut._log.info(f"fifo 0 = {hex(get_fifo(0))}")
    # dut._log.info(f"fifo 0 = {list(map(hex, random_pixels[0:16]))}")

    cocotb.start_soon(Clock(dut.vout_clk_i, 10, unit='ns').start())
    cocotb.start_soon(Clock(dut.ddr_clk_i, 8, unit='ns').start())

    await ClockCycles(dut.vout_clk_i, 10)
    dut.rstn_i.value = 1
    await ClockCycles(dut.vout_clk_i, 10)

    # cocotb.start_soon(fake_fifo(dut))
    # await fifo_loader(dut)
    cocotb.start_soon(ddr_stub(dut, imgdat))
    await ClockCycles(dut.vout_clk_i, 10)


    for line in range(25):
        last_pix_request = 0
        last_word_request = 0

        # request initial bursts
        dut.vout_ddr3_data_req_i.value = 1
        dut.vout_ddr3_rd_word_i.value = last_word_request
        dut.vout_ddr3_rd_pixel_i.value = last_pix_request
        dut.vout_ddr3_rd_line_i.value = line
        await RisingEdge(dut.vout_clk_i)
        dut.vout_ddr3_data_req_i.value = 0
        await RisingEdge(dut.vout_ddr3_rd_complete_o)
        await RisingEdge(dut.vout_clk_i)

        # and another from the same line
        last_pix_request += 16
        last_word_request += 3
        dut.vout_ddr3_data_req_i.value = 1
        dut.vout_ddr3_rd_word_i.value = last_word_request
        dut.vout_ddr3_rd_pixel_i.value = last_pix_request
        dut.vout_ddr3_rd_line_i.value = line 
        await RisingEdge(dut.vout_clk_i)
        dut.vout_ddr3_data_req_i.value = 0
        await RisingEdge(dut.vout_ddr3_rd_complete_o)
        await RisingEdge(dut.vout_clk_i)

        # request all the pixels
        for pix in range(imgdat.shape[1]):
            dut.vout_buffer_rd_en_i.value = 1
            await RisingEdge(dut.vout_clk_i)
            dut.vout_buffer_rd_en_i.value = 0
            await ClockCycles(dut.vout_clk_i, 5)
            # need another memory request?
            if pix == (last_pix_request - 1):
                if (pix + 16) < (imgdat.shape[1] - 1):
                    # can't be last pixel, otherwise we'd be done and need no more memory accesses
                    last_pix_request += 16
                    last_word_request += 3
                    dut.vout_ddr3_data_req_i.value = 1
                    dut.vout_ddr3_rd_word_i.value = last_word_request
                    dut.vout_ddr3_rd_pixel_i.value = last_pix_request
                    dut.vout_ddr3_rd_line_i.value = line 
                    await RisingEdge(dut.vout_clk_i)
                    dut.vout_ddr3_data_req_i.value = 0
            await ClockCycles(dut.vout_clk_i, 200) # pretend its hsync
            
        if line % 10 == 0:
            dut._log.info(f"Line {line} done.")


    quit_all_coro = True