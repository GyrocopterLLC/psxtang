// variable naming notes:
// clock domain is the prefix. "o" or "vout" for video output domain, 
// "vin" or "i" for video input domain, "mem" or "m" for DDR3 domain

// Module inputs all end with "_i", outputs end with "_o".
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
module fb_write_control #
(
    parameter int BURST_SIZE = 16, // Number of pixels per burst
    parameter int PIXEL_SIZE = 24, // Bits per pixel (24 bit = 888 format)
    parameter int MEMORY_WIDTH = 128  // Memory data word size
)
(
    input  logic                    rstn_i,

    input  logic                    vin_clk_i,
    input  logic                    vin_hsync_i,
    input  logic                    vin_vsync_i,
    input  logic                    vin_de_i,
    input  logic                    vin_ce_i,
    input  logic [7:0]              vin_r_i,
    input  logic [7:0]              vin_g_i,
    input  logic [7:0]              vin_b_i,

    input  logic [9:0]              vin_width_i,  // input image width (max: 1024)
    input  logic [8:0]              vin_height_i, // input image height (max: 512)

    output logic                    vin_buf_wr_en_o, // A new pixel is ready to go to memory FIFO
    output logic [PIXEL_SIZE-1:0]   vin_buf_data_o, 
    output logic [9:0]              vin_buf_start_pixel_o, // Pixel count at the start of most recent burst
    output logic [9:0]              vin_buf_start_word_o, // Memory data word count for start of most recent burst
    output logic [8:0]              vin_buf_line_o, // Line for that same burst
    output logic                    vin_buf_data_ready_o, // Burst has been filled 
    output logic                    vin_buf_data_flush_o, // FIFO flush command
    output logic [9:0]              vin_line_length_o, // Line length in number of memory words, calculated after first line

    output logic [1:0]              vin_frame_slot_o // triple buffering uses 3 slots. Increment on Vsync
);

// tabs = 4 spaces

/* 
FUNCTIONALITY OF THIS MODULE:

Video input ("vin") clock domain functions:
- Reads input video data and outputs to external module FIFO
- Every BURST_SIZE pixels issues a frame buffer memory write command, includes the
  target row / col start address of the burst.
- Frame slot increments after every successfully written frame. It tells the read controller that a 
  full frame has been saved in memory. At start (or any resolution change) the frame slot is zero.
  Each non-zero value (1, 2, or 3) means that a full frame has been saved to that location in the buffer.
*/

localparam int BURST_ADDR_WIDTH = $clog2(BURST_SIZE);
localparam int WORDS_PER_BURST = BURST_SIZE * PIXEL_SIZE / MEMORY_WIDTH;

// Hsync, vsync rising edge detectors
logic i_hsync1, i_vsync1;
logic i_hsync_rising, i_vsync_rising;

// frame buffer addressing
logic [BURST_ADDR_WIDTH-1 : 0] i_burst_pos;
logic [9:0]             i_burst_start_pixel;
logic [9:0]             i_burst_start_word;
logic [8:0]             i_current_line;

`ifdef FLUSH_AT_DATA_END
// don't let us flush the fifo RIGHT after a normal BURST_SIZE write has occurred
// give it a little delay timer, this is a maximum of 32 cycles
logic [4:0]             i_flush_timer; 
`endif

// Rising edge detection
always_ff @(posedge vin_clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        i_hsync1 <= 0;
        i_vsync1 <= 0;
    end else begin
        i_hsync1 <= vin_hsync_i;
        i_vsync1 <= vin_vsync_i;
    end
end

assign i_hsync_rising = vin_hsync_i & (!i_hsync1);
assign i_vsync_rising = vin_vsync_i & (!i_vsync1);

// frame buffer address generation based on input video pixel coordinates
// input video clock domain
always_ff @(posedge vin_clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        i_current_line <= 0;
        vin_frame_slot_o <= 0;
        i_burst_pos <= 0;
        i_burst_start_pixel <= 0;
        i_burst_start_word <= 0;
        vin_buf_wr_en_o <= 0;
        vin_buf_data_o <= 0;
        vin_buf_start_pixel_o <= 0;
        vin_buf_start_word_o <= 0;
        vin_buf_line_o <= 0;
        vin_buf_data_ready_o <= 0;
        vin_buf_data_flush_o <= 0;
        vin_line_length_o <= 0;
`ifdef FLUSH_AT_DATA_END
        i_flush_timer <= 0;
`endif
    end else begin
        vin_buf_wr_en_o <= 0;
        vin_buf_data_ready_o <= 0;
        vin_buf_data_flush_o <= 0;

`ifdef FLUSH_AT_DATA_END
        if (i_flush_timer != 0) begin
            i_flush_timer <= i_flush_timer - 1;
        end
`endif

        if(vin_ce_i && vin_de_i) begin
            i_burst_pos <= i_burst_pos + 1;
            vin_buf_wr_en_o <= 1;
            vin_buf_data_o <= {vin_r_i, vin_g_i, vin_b_i};
            if (i_burst_pos == (BURST_SIZE - 1)) begin
                i_burst_pos <= 0;
                vin_buf_start_pixel_o <= i_burst_start_pixel;
                vin_buf_start_word_o <= i_burst_start_word;
                vin_buf_line_o <= i_current_line;
                vin_buf_data_ready_o <= 1;
`ifdef FLUSH_AT_DATA_END
                i_flush_timer <= 5'b11111;
`endif
                i_burst_start_pixel <= i_burst_start_pixel + BURST_SIZE;
                i_burst_start_word <= i_burst_start_word + WORDS_PER_BURST;
            end
        end

`ifdef FLUSH_AT_DATA_END
        if ((i_burst_pos != 0) && ((i_burst_start_pixel + i_burst_pos) == vin_width_i)) begin
            // reached the end of line, but still have pixels in the buffer that haven't been saved to memory
            if (i_flush_timer == 0) begin
                vin_buf_start_pixel_o <= i_burst_start_pixel;
                vin_buf_start_word_o <= i_burst_start_word;
                vin_buf_line_o <= i_current_line;
                vin_buf_data_flush_o <= 1; // only place this is set
            end
        end
`endif

        if (i_hsync_rising) begin
            if ((i_burst_start_pixel != 0) || (i_burst_pos != 0)) begin
                // Only increment line counter when there have been pixels
                // Hsync can rise right after vsync when no pixels have 
                // been received, and we should not count that as a line
                i_current_line <= i_current_line + 1;
                
                // while we probably only need to calculate line_length on the 
                // first complete line, setting it every time allows us to correct
                // from a weird video data startup, and reset the line length
                // when input resolution changes

                // but yeah this should stay constant
                vin_line_length_o <= i_burst_start_word + ((i_burst_pos != 0) ? WORDS_PER_BURST : 0);

                // extra WORDS_PER_BURST if there is a non-zero burst position: one more burst will be
                // required after hsync
            end
`ifndef FLUSH_AT_DATA_END
            if(i_burst_pos != 0) begin
                // Hsync rising with data in buffer - happens when line width is not
                // divisible by BURST SIZE. Need to issue a data ready command with
                // less than BURST_SIZE pixels.
                vin_buf_start_pixel_o <= i_burst_start_pixel;
                vin_buf_start_word_o <= i_burst_start_word;
                vin_buf_line_o <= i_current_line;
                vin_buf_data_flush_o <= 1; // only place this is set
                // Note: vin_buf_data_ready_o is NOT set here. It would immediately write the 
                // memory FIFO to DDR, which might not include the final data word. That final
                // word will be written after vin_buf_data_flush_o is asserted for a cycle.
            end
`endif
            i_burst_pos <= 0;
            i_burst_start_pixel <= 0;
            i_burst_start_word <= 0;
        end
        if (i_vsync_rising) begin
            i_current_line <= 0;
            // increment frame slot only if we received a full image -> we're on the final line
            if (i_current_line == vin_height_i) begin
                if (vin_frame_slot_o == 3)
                    vin_frame_slot_o <= 1;
                else
                    vin_frame_slot_o <= vin_frame_slot_o + 1;
            end
        end
    end
end

endmodule
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on WIDTHTRUNC */
