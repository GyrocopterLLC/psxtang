module frame_buffer_top #(
    // ** Global parameters **
    parameter int BURST_SIZE = 48, // Number of pixels per burst
    parameter int PIXEL_SIZE = 24, // Bits per pixel (24 bit = 888 format)
    parameter int MEMORY_WIDTH = 128,  // Memory data word size

    // ** Memory parameters **
    parameter int ADDR_WIDTH = 32, // Memory bus address size
    parameter int MAX_LINE_WIDTH = 9, // Bits needed to describe the number of memory words per line
    parameter int MEM_INCREMENT = 1, // amount to change address in counts of bursts (128bit/16byte)

    // ** Output parameters **
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

    // ** Video input clock domain **
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

    // ** Video output clock domain **
    input  logic                    vout_clk_i,
    input  logic [10:0]             vout_width_i,  // output container width (max: 2048)
    input  logic [9:0]              vout_height_i, // output container height (max: 1024)
    // container is the region within the 720p image that contains upscaled video
    input  logic [PIXEL_SIZE-1:0]   vout_bg_color_i, // for solid color background
    output logic                    vout_hsync_o,
    output logic                    vout_vsync_o,
    output logic                    vout_de_o,
    output logic [7:0]              vout_r_o,
    output logic [7:0]              vout_g_o,
    output logic [7:0]              vout_b_o,
    output logic [10:0]             vout_h_count_o, // real pixel output counts
    output logic [9:0]              vout_v_count_o, 

    // ** Memory clock domain **
    input  logic                    mem_clk_i,
    input  logic                    mem_busy_i,
    output logic                    mem_wr_en_o,
    output logic                    mem_rd_en_o,
    output logic [ADDR_WIDTH-1:0]   mem_addr_o,
    output logic [MEMORY_WIDTH-1:0] mem_wr_data_o,
    input  logic [MEMORY_WIDTH-1:0] mem_rd_data_i,
    input  logic                    mem_rd_data_valid_i
);

// Video input (write) controller to memory controller
logic                   vin_buf_wr_en;
logic [PIXEL_SIZE-1:0]  vin_buf_data;
logic [9:0]             vin_buf_start_pixel;
logic [9:0]             vin_buf_start_word;
logic [8:0]             vin_buf_line;
logic                   vin_buf_data_ready;
logic                   vin_buf_data_flush;
logic [9:0]             vin_line_length;
logic [1:0]             vin_frame_slot;

// Video output (read) controller to memory controller
logic                   vout_buf_data_req;
logic [8:0]             vout_buf_rd_line;
logic [9:0]             vout_buf_rd_pixel;
logic [9:0]             vout_buf_rd_word;
logic                   vout_buf_rd_complete;
logic                   vout_buf_rd_en;
logic                   vout_frame_update;
logic [PIXEL_SIZE-1:0]  vout_buf_rd_data;

fb_mem_control
#(
    .ADDR_WIDTH(ADDR_WIDTH),
    .MEMORY_WIDTH(MEMORY_WIDTH),
    .PIXEL_SIZE(PIXEL_SIZE),
    .BURST_SIZE(BURST_SIZE),
    .MAX_LINE_WIDTH(MAX_LINE_WIDTH),
    .MEM_INCREMENT(MEM_INCREMENT)
)
memctrl
(
    .rstn_i,

    .mem_clk_i,
    .mem_busy_i,
    .mem_wr_en_o,
    .mem_rd_en_o,
    .mem_addr_o,
    .mem_wr_data_o,
    .mem_rd_data_i,
    .mem_rd_data_valid_i,

    .vin_clk_i,
    .vin_width_i,
    .vin_height_i,
    .vin_buf_wr_en_i(vin_buf_wr_en),
    .vin_buf_data_i(vin_buf_data),
    .vin_buf_start_pixel_i(vin_buf_start_pixel),
    .vin_buf_start_word_i(vin_buf_start_word),
    .vin_buf_line_i(vin_buf_line),
    .vin_buf_data_ready_i(vin_buf_data_ready),
    .vin_buf_data_flush_i(vin_buf_data_flush),
    .vin_line_length_i(vin_line_length),
    .vin_frame_slot_i(vin_frame_slot),

    .vout_clk_i,
    .vout_buf_data_req_i(vout_buf_data_req),
    .vout_buf_rd_line_i(vout_buf_rd_line),
    .vout_buf_rd_pixel_i(vout_buf_rd_pixel),
    .vout_buf_rd_word_i(vout_buf_rd_word),
    .vout_buf_rd_complete_o(vout_buf_rd_complete),
    .vout_frame_update_i(vout_frame_update),
    .vout_buf_rd_en_i(vout_buf_rd_en),
    .vout_buf_rd_data_o(vout_buf_rd_data)
);

fb_read_control
#(
    .BURST_SIZE(BURST_SIZE),
    .PIXEL_SIZE(PIXEL_SIZE),
    .MEMORY_WIDTH(MEMORY_WIDTH),
    .VOUT_WIDTH(VOUT_WIDTH),
    .VOUT_HEIGHT(VOUT_HEIGHT),
    .VOUT_H_FRONT_PORCH(VOUT_H_FRONT_PORCH),
    .VOUT_H_SYNC_WIDTH(VOUT_H_SYNC_WIDTH),
    .VOUT_H_BACK_PORCH(VOUT_H_BACK_PORCH),
    .VOUT_V_FRONT_PORCH(VOUT_V_FRONT_PORCH),
    .VOUT_V_SYNC_WIDTH(VOUT_V_SYNC_WIDTH),
    .VOUT_V_BACK_PORCH(VOUT_V_BACK_PORCH),
    .BACKGROUND_TYPE(BACKGROUND_TYPE)
)
rdctrl
(
    .rstn_i,

    .vout_clk_i,
    .vout_hsync_o,
    .vout_vsync_o,
    .vout_de_o,
    .vout_r_o,
    .vout_g_o,
    .vout_b_o,

    .vin_width_i,
    .vin_height_i,

    .vout_width_i,
    .vout_height_i,
    .vout_bg_color_i,

    .vout_h_count_o,
    .vout_v_count_o,

    .vout_buf_data_req_o(vout_buf_data_req),
    .vout_buf_rd_line_o(vout_buf_rd_line),
    .vout_buf_rd_pixel_o(vout_buf_rd_pixel),
    .vout_buf_rd_word_o(vout_buf_rd_word),
    .vout_buf_rd_complete_i(vout_buf_rd_complete),
    .vout_frame_update_o(vout_frame_update),
    .vout_buf_rd_en_o(vout_buf_rd_en),
    .vout_buf_rd_data_i(vout_buf_rd_data)
);

fb_write_control
#(
    .BURST_SIZE(BURST_SIZE),
    .PIXEL_SIZE(PIXEL_SIZE),
    .MEMORY_WIDTH(MEMORY_WIDTH)
)
wrctrl
(
    .rstn_i,

    .vin_clk_i,
    .vin_hsync_i,
    .vin_vsync_i,
    .vin_de_i,
    .vin_ce_i,
    .vin_r_i,
    .vin_g_i,
    .vin_b_i,

    .vin_width_i,
    .vin_height_i,

    .vin_buf_wr_en_o(vin_buf_wr_en),
    .vin_buf_data_o(vin_buf_data),
    .vin_buf_start_pixel_o(vin_buf_start_pixel),
    .vin_buf_start_word_o(vin_buf_start_word),
    .vin_buf_line_o(vin_buf_line),
    .vin_buf_data_ready_o(vin_buf_data_ready),
    .vin_buf_data_flush_o(vin_buf_data_flush),
    .vin_line_length_o(vin_line_length),

    .vin_frame_slot_o(vin_frame_slot)
);

endmodule
