// variable naming notes:
// clock domain is the prefix. "o" or "vout" for video output domain, 
// "vin" or "i" for video input domain, "mem" or "m" for DDR3 domain

// Module inputs all end with "_i", outputs end with "_o".
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
module fb_read_control #
(
    parameter int BURST_SIZE = 16, // Number of pixels per burst
    parameter int PIXEL_SIZE = 24,  // Bits per pixel (24 bit = 888 format)
    parameter int MEMORY_WIDTH = 128, // Memory data word size
    // CEA-861 standard for 720p
    parameter int VOUT_WIDTH = 1280,
    parameter int VOUT_HEIGHT = 720,
    parameter int VOUT_H_FRONT_PORCH = 110,
    parameter int VOUT_H_SYNC_WIDTH = 40,
    parameter int VOUT_H_BACK_PORCH = 220,
    parameter int VOUT_V_FRONT_PORCH = 5,
    parameter int VOUT_V_SYNC_WIDTH = 5,
    parameter int VOUT_V_BACK_PORCH = 20,
    parameter string BACKGROUND_TYPE = "GRADIENT" // SOLID or GRADIENT
)
(
    input  logic                    rstn_i,

    input  logic                    vout_clk_i,
    output logic                    vout_hsync_o,
    output logic                    vout_vsync_o,
    output logic                    vout_de_o,
    output logic [7:0]              vout_r_o,
    output logic [7:0]              vout_g_o,
    output logic [7:0]              vout_b_o,
    
    output logic [10:0]             vout_h_count_o, // real pixel output counts
    output logic [9:0]              vout_v_count_o, 

    input  logic [9:0]              vin_width_i,   // input image width (max: 1024)
    input  logic [8:0]              vin_height_i,  // input image height (max: 512)
    input  logic [10:0]             vout_width_i,  // output container width (max: 2048)
    input  logic [9:0]              vout_height_i, // output container height (max: 1024)
    // container is the region within the 720p image that contains upscaled video
    input  logic [PIXEL_SIZE-1:0]   vout_bg_color_i, // for solid color background

    // DDR3 memory requests
    output logic                    vout_buf_data_req_o,
    output logic [8:0]              vout_buf_rd_line_o,
    output logic [9:0]              vout_buf_rd_pixel_o,
    output logic [9:0]              vout_buf_rd_word_o,
    input  logic                    vout_buf_rd_complete_i, // asserted when burst read is complete
    // DDR3 buffer accesses

    output logic                    vout_frame_update_o, // used to latch the current frame slot in the triple buffer
    output logic                    vout_buf_rd_en_o,
    input  logic [23:0]             vout_buf_rd_data_i
);


// tabs = 4 spaces

/* 
FUNCTIONALITY OF THIS MODULE:

Video output ("vout") clock domain functions:
- Generates 720p video signals (hsync, vsync, de)
- Issues burst requests to DDR3 read controller for pixel data, 
  including requested line and pixel location
- Reads pixels from an external BSRAM-backed buffer.
- Upscales received pixel data to fit a "container" within the 720p frame.
- Upscaling is performed by nearest neighbor using the Bresenham algorithm, 
  rather than a fixed ratio.
*/


localparam int WORDS_PER_BURST = BURST_SIZE * PIXEL_SIZE / MEMORY_WIDTH;


// !! Note - probably flush the DDR3 FIFO when reading pixel zero !!
// just in case vin width not divisible by BURST_SIZE

localparam int VOUT_HSYNC_START = VOUT_H_FRONT_PORCH;
localparam int VOUT_HSYNC_END = VOUT_H_FRONT_PORCH + VOUT_H_SYNC_WIDTH;
localparam int VOUT_VSYNC_START = VOUT_V_FRONT_PORCH;
localparam int VOUT_VSYNC_END = VOUT_V_FRONT_PORCH + VOUT_V_SYNC_WIDTH;
localparam int VOUT_H_BLANK = VOUT_H_FRONT_PORCH + VOUT_H_SYNC_WIDTH + VOUT_H_BACK_PORCH;
localparam int VOUT_V_BLANK = VOUT_V_FRONT_PORCH + VOUT_V_SYNC_WIDTH + VOUT_V_BACK_PORCH;
localparam int VOUT_H_TOTAL = VOUT_H_BLANK + VOUT_WIDTH;
localparam int VOUT_V_TOTAL = VOUT_V_BLANK + VOUT_HEIGHT;

// Now as module outputs
// logic [10:0] o_h_count; // real pixel output counts
// logic [9:0]  o_v_count;  

logic [10:0] o_h_container_start; // start/end of container in the output pixel space
logic [9:0]  o_v_container_start;
logic [10:0] o_h_container_end;
logic [9:0]  o_v_container_end;


logic [10:0] o_cx; // position of input video space to show in current output pixel (scaled-down pixel position)
logic [9:0]  o_cy;   
logic [10:0] o_xcnt; // fractional scaling counters
logic [10:0] o_ycnt; 
logic        o_container_active;
logic        o_v_count_prev; // what, only one bit? we just need to update on a new line change. LSB is enough for that.

// Video generation.
// Starts in blanking (front porch -> sync -> back porch), then active video region until end of line / frame.

// This block also includes the frame buffer update, which tells the memory controller to latch the most recent 
// fully written frame buffer slot by the video input (write) controller.
// This is a single pulse output at the moment both counts, H and V, roll over to zero.
// The first read requests come at a rising edge of Hsync after Vblanking is over, so
// we should have a little time to spare.

always_ff @(posedge vout_clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        vout_h_count_o <= 0;
        vout_v_count_o <= 0;
        vout_frame_update_o <= 0;
    end else begin
        vout_frame_update_o <= 0; // default zero, will pulse once (below)

        if (vout_h_count_o == VOUT_H_TOTAL - 1) begin
            vout_h_count_o <= 0;
            if (vout_v_count_o == VOUT_V_TOTAL - 1) begin
                vout_v_count_o <= 0;
                vout_frame_update_o <= 1;
            end else begin
                vout_v_count_o <= vout_v_count_o + 1;
            end
        end else begin
            vout_h_count_o <= vout_h_count_o + 1;
        end
    end
end

logic o_hs;
logic o_vs;
logic o_de;

always_ff @(posedge vout_clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        vout_hsync_o <= 0;
        vout_vsync_o <= 0;
        vout_de_o <= 0;
    end else begin
        vout_hsync_o <= o_hs;
        vout_vsync_o <= o_vs;
        vout_de_o <= o_de;
    end
end

always_comb begin
    // Hsync, Vsync generation
    o_hs = (vout_h_count_o >= VOUT_HSYNC_START) && (vout_h_count_o < VOUT_HSYNC_END);
    // Vsync isn't as easy. The spec requires vsync start and end at start of hsync
    if (vout_v_count_o == VOUT_VSYNC_START) begin
        o_vs = (vout_h_count_o >= VOUT_HSYNC_START);
    end else if (vout_v_count_o == VOUT_VSYNC_END) begin
        o_vs = (vout_h_count_o < VOUT_HSYNC_START);
    end else begin
        o_vs = (vout_v_count_o >= VOUT_VSYNC_START) && (vout_v_count_o < VOUT_VSYNC_END);
    end

    o_de = (vout_h_count_o >= VOUT_H_BLANK) && (vout_v_count_o >= VOUT_V_BLANK);
end


// output video pixel calculation
// well, actually input video pixel. We need to track which input pixel we're on when
// requesting data from DDR3 / local buffer. Upscaling done here.

// normally I would just use an = after the declarations up above, but Verilator was weird about it.
always_comb begin
    o_h_container_start = VOUT_H_BLANK;
    o_h_container_start = o_h_container_start + ((VOUT_WIDTH - vout_width_i) / 2);
    o_v_container_start = VOUT_V_BLANK;
    o_v_container_start = o_v_container_start + ((VOUT_HEIGHT - vout_height_i) / 2);

    o_h_container_end = o_h_container_start + vout_width_i;
    o_v_container_end = o_v_container_start + vout_height_i;
end

always_ff @(posedge vout_clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        o_cx <= 0;
        o_cy <= 0;
        o_xcnt <= 0;
        o_ycnt <= 0;
        o_container_active <= 0;
    end else begin
        if(vout_v_count_o >= o_v_container_start && vout_v_count_o < o_v_container_end) begin
            // in vertical container space...

            // *** Horizontal scaling ***
            // activate within horizontal container space
            if (vout_h_count_o == o_h_container_start - 1) begin
                o_container_active <= 1;
            end
            if (vout_h_count_o == o_h_container_end - 1) begin
                o_container_active <= 0;
            end

            if (o_container_active) begin
                o_xcnt <= o_xcnt + vin_width_i;
                if (o_xcnt + vin_width_i >= vout_width_i) begin
                    o_xcnt <= o_xcnt + vin_width_i - vout_width_i;
                    o_cx <= o_cx + 1;
                end
            end else begin
                o_cx <= 0;
                o_xcnt <= 0;
            end
            
            // *** Vertical scaling ***
            o_v_count_prev <= vout_v_count_o[0];
            if( o_v_count_prev != vout_v_count_o[0]) begin
                // new line, update counters
                o_ycnt <= o_ycnt + vin_height_i;
                if (o_ycnt + vin_height_i >= vout_height_i) begin
                    o_ycnt <= o_ycnt + vin_height_i - vout_height_i;
                    o_cy <= o_cy + 1;
                end
            end

        end else begin
            o_v_count_prev <= o_v_container_start[0]; // this way it doesn't increment on first line inside container
            o_cy <= 0;
            o_ycnt <= 0;
        end
    end
end


// DDR3 read request generation
// gotta get that FIFO filled before we need the pixel data
// aiming for 2x BURST_SIZE in the FIFO
// timing for FIFO requests:
// - first request issued at the start of every line. At h_count=0
// - next request issued as soon as remaining fetched pixels is one BURST_SIZE or less
// --- for the first request, that will be immediately. So every line will start with back-to-back bursts.
// - after that, burst request will be issued when each burst has been fully read out until the end of the line

// state masheeen gooo
typedef enum logic {
    IDLE,
    READ
} buffer_read_state;

buffer_read_state buf_state;

always_ff @(posedge vout_clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        buf_state <= IDLE;
        vout_buf_rd_line_o <= 0;
        vout_buf_rd_pixel_o <= 0;
        vout_buf_rd_word_o <= 0;
        vout_buf_data_req_o <= 0;
    end else begin
        vout_buf_data_req_o <= 0;

        case (buf_state)
            IDLE: begin
                if(vout_v_count_o >= o_v_container_start && vout_v_count_o < o_v_container_end) begin

                    if (vout_h_count_o == VOUT_HSYNC_START) begin
                        // start of line, inside container vertical space. Issue read request.
                        vout_buf_rd_line_o <= o_cy;
                        vout_buf_rd_pixel_o <= 0;
                        vout_buf_rd_word_o <= 0;
                        vout_buf_data_req_o <= 1;
                        buf_state <= READ;
                    end else if ((vout_h_count_o >= VOUT_HSYNC_START) && (vout_buf_rd_pixel_o == 0)) begin
                        // issue second read request immediately since we should have available space in the FIFO
                        vout_buf_rd_line_o <= o_cy;
                        vout_buf_rd_pixel_o <= vout_buf_rd_pixel_o + BURST_SIZE;
                        vout_buf_rd_word_o <= vout_buf_rd_word_o + WORDS_PER_BURST;
                        vout_buf_data_req_o <= 1;
                        buf_state <= READ;
                    end else if (o_cx == (vout_buf_rd_pixel_o - 1)) begin // on the final pixel of two bursts ago (just about to start 
                                                                           // into prevous burst), so issue the next one
                        
                        // TODO: Check the math on below. Will it work if width isn't divisible by BURST_SIZE??
                        if((vout_buf_rd_pixel_o + BURST_SIZE) < vin_width_i) begin
                            // only pull a burst if there are still pixels remaining in this line
                            vout_buf_rd_line_o <= o_cy;
                            vout_buf_rd_pixel_o <= vout_buf_rd_pixel_o + BURST_SIZE;
                            vout_buf_rd_word_o <= vout_buf_rd_word_o + WORDS_PER_BURST;
                            vout_buf_data_req_o <= 1;
                            buf_state <= READ;
                        end
                    end
                end
            end

            READ: begin
                if (vout_buf_rd_complete_i) begin
                    buf_state <= IDLE;
                end
            end

            default: buf_state <= IDLE;
        endcase
    end
end

// pixel color output
logic [10:0] o_prev_cx;
logic o_prev_container_active;
assign vout_buf_rd_en_o = o_container_active && (o_cx != o_prev_cx);

assign {vout_r_o, vout_g_o, vout_b_o} = (o_prev_container_active) ? (vout_buf_rd_data_i) : bg_color;

always_ff @(posedge vout_clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        
        o_prev_cx <= 0;
        o_prev_container_active <= 0;
        // vout_r_o <= 0;
        // vout_g_o <= 0;
        // vout_b_o <= 0;
    end else begin
        o_prev_container_active <= o_container_active;
        if (o_container_active) begin
            o_prev_cx <= o_cx;
            // if (vout_buf_rd_en_o) begin
                // single cycle delay to fetch the pixel data from the buffer
                // {vout_r_o, vout_g_o, vout_b_o} <= vout_buf_rd_data_i;
            // end
        end else begin
            // {vout_r_o, vout_g_o, vout_b_o} <= 24'h0C0C0C;
            o_prev_cx <= vin_width_i;
        end
    end
end

// background output
logic [23:0] bg_color;

generate
    if (BACKGROUND_TYPE == "SOLID") begin : BG_SOLID
        assign bg_color = vout_bg_color_i;
    end 
    else if (BACKGROUND_TYPE == "GRADIENT") begin : BG_GRADIENT
        always_ff @(posedge vout_clk_i or negedge rstn_i) begin
            if(!rstn_i) begin
                bg_color <= 24'h000000;
            end else begin
                bg_color[7:0] <= 8'(11'(vout_bg_color_i[7:0]) + 11'(vout_h_count_o) + 11'(vout_v_count_o));
                bg_color[15:8] <= 8'(11'(vout_bg_color_i[15:8]) + 11'(vout_h_count_o) + 11'(vout_v_count_o));;
                bg_color[23:16] <= 8'(11'(vout_bg_color_i[23:16]) + 11'(vout_h_count_o) + 11'(vout_v_count_o));;
            end
        end
    end
    else begin : BG_DEFAULT
        assign bg_color = 24'h808080;
    end
endgenerate

endmodule

/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on WIDTHTRUNC */
