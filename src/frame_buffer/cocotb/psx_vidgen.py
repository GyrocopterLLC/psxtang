import cocotb
from cocotb.triggers import RisingEdge, ClockCycles
from random import getrandbits
from cv2 import imread

class psx_vidgen:
    def __init__(self, pixdiv = 8, hact=320, vact=240, htot=426, vtot=263, hsyncstart=26, hsyncend=56, vsyncstart=5, vsyncend=8, image=None):
        
        if image is not None:
            self.image = imread(image)
            hact_im = self.image.shape[1]
            vact_im = self.image.shape[0]
            if hact != hact_im or vact != vact_im:
                print("Mismatch input image to given video dimensions.")
                assert(False)
        else:
            self.image = None
        self.pixdiv = pixdiv
        self.hact = hact
        self.vact = vact
        self.htot = htot
        self.vtot = vtot
        self.hsyncstart = hsyncstart
        self.hsyncend = hsyncend
        self.vsyncstart = vsyncstart
        self.vsyncend = vsyncend

        self.quit_now = False

    def destroy(self):
        self.quit_now = True

    async def run(self, clk_signal, ce_signal, de_signal, vs_signal, hs_signal, r_signal, g_signal, b_signal):

        ce_signal.value = 0
        de_signal.value = 0
        vs_signal.value = 0
        hs_signal.value = 0

        pixclk_count = 0
        pix_count = 0
        line_count = 0
        while not self.quit_now:
            await RisingEdge(clk_signal)
            pixclk_count += 1
            # set ce on last cycle of the pixel count
            if pixclk_count == self.pixdiv - 1:
                ce_signal.value = 1
                pixactive = True
            else:
                ce_signal.value = 0
                pixactive = False

            if pixclk_count == self.pixdiv: # new pixel, wrap around
                pixclk_count = 0
                pix_count += 1
                if pix_count >= self.hsyncstart and pix_count < self.hsyncend:
                    hs_signal.value = 1
                else:
                    hs_signal.value = 0
                
                if pix_count == self.htot:
                    pix_count = 0
                    line_count += 1

                    if line_count >= self.vsyncstart and line_count < self.vsyncend:
                        vs_signal.value = 1
                    else:
                        vs_signal.value = 0
                    
                    if line_count == self.vtot:
                        line_count = 0
            
            hblank = pix_count < (self.htot - self.hact)
            vblank = line_count < (self.vtot - self.vact)
            if hblank or vblank:
                de_signal.value = 0
                vidactive = False
            else:
                de_signal.value = 1
                vidactive = True
                
            if pixactive and vidactive:
                if self.image is None:
                    r_signal.value = getrandbits(8)
                    g_signal.value = getrandbits(8)
                    b_signal.value = getrandbits(8)
                else:
                    vact_line = line_count - (self.vtot - self.vact)
                    hact_col = pix_count - (self.htot - self.hact)
                    r_signal.value = int(self.image[vact_line,hact_col,2])
                    g_signal.value = int(self.image[vact_line,hact_col,1])
                    b_signal.value = int(self.image[vact_line,hact_col,0])
            else:
                r_signal.value = 0xFC
                g_signal.value = 0xC0
                b_signal.value = 0x18

                


