/*
Based on hdmi generation in snestang (https://github.com/nand2mario/snestang/tree/main/src/hdmi2)

Takes output from framebuffer and produces HDMI video on
differential pair pins .
Frame buffer generates pixel timing, rather than this module (as in snestang)

*/

/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
module fb_to_hdmi
#(
    // Defaults to 720p 
    // See README.md or CEA-861-D for enumeration of video id codes.
    // Pixel repetition, interlaced scans and other special output modes are not implemented (yet).
    parameter int VIDEO_ID_CODE = 4,
    // The IT content bit indicates that image samples are generated in an ad-hoc
    // manner (e.g. directly from values in a framebuffer, as by a PC video
    // card) and therefore aren't suitable for filtering or analog
    // reconstruction.  This is probably what you want if you treat pixels
    // as "squares".  If you generate a properly bandlimited signal or obtain
    // one from elsewhere (e.g. a camera), this can be turned off.
    //
    // This flag also tends to cause receivers to treat RGB values as full
    // range (0-255).
    parameter bit IT_CONTENT = 1'b1,
    // Defaults to minimum bit lengths required to represent positions.
    // Modify these parameters if you have alternate desired bit lengths.
    parameter int BIT_WIDTH = VIDEO_ID_CODE < 4 ? 10 : VIDEO_ID_CODE == 4 ? 11 : 12,
    parameter int BIT_HEIGHT = VIDEO_ID_CODE == 16 ? 11: 10,

    // A true HDMI signal sends auxiliary data (i.e. audio, preambles) which prevents it from being parsed by DVI signal sinks.
    // HDMI signal sinks are fortunately backwards-compatible with DVI signals.
    // Enable this flag if the output should be a DVI signal. You might want to do this to reduce resource usage or if you're only outputting video.
    parameter bit DVI_OUTPUT = 1'b0,

    // **All parameters below matter ONLY IF you plan on sending auxiliary data (DVI_OUTPUT == 1'b0)**

    // Specify the refresh rate in Hz you are using for audio calculations
    parameter real VIDEO_REFRESH_RATE = 60.0,

    // As specified in Section 7.3, the minimal audio requirements are met: 16-bit or more L-PCM audio at 32 kHz, 44.1 kHz, or 48 kHz.
    // See Table 7-4 or README.md for an enumeration of sampling frequencies supported by HDMI.
    // Note that sinks may not support rates above 48 kHz.
    parameter int AUDIO_RATE = 44100,

    // Defaults to 16-bit audio, the minmimum supported by HDMI sinks. Can be anywhere from 16-bit to 24-bit.
    parameter int AUDIO_BIT_WIDTH = 16,

    // Some HDMI sinks will show the source product description below to users (i.e. in a list of inputs instead of HDMI 1, HDMI 2, etc.).
    // If you care about this, change it below.
    parameter bit [8*8-1:0] VENDOR_NAME = {"Unknown", 8'd0}, // Must be 8 bytes null-padded 7-bit ASCII
    parameter bit [8*16-1:0] PRODUCT_DESCRIPTION = {"FPGA", 96'd0}, // Must be 16 bytes null-padded 7-bit ASCII
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h00, // See README.md or CTA-861-G for the list of valid codes

    // Starting screen coordinate when module comes out of reset.
    //
    // Setting these to something other than (0, 0) is useful when positioning
    // an external video signal within a larger overall frame (e.g.
    // letterboxing an input video signal). This allows you to synchronize the
    // negative edge of reset directly to the start of the external signal
    // instead of to some number of clock cycles before.
    //
    // You probably don't need to change these parameters if you are
    // generating a signal from scratch instead of processing an
    // external signal.
    parameter int START_X = 0,
    parameter int START_Y = 0
)
(
    input  logic                    clk_pixel_x5, // TMDS bit clock
    input  logic                    clk_pixel,    // pixel clock
    input  logic                    clk_audio,   // audio "clock" (enable signal)
    input  logic                    reset,
    input  logic [7:0]              pixel_r,
    input  logic [7:0]              pixel_g,
    input  logic [7:0]              pixel_b,
    input  logic[AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0],

    // These outputs go to your HDMI port
    output logic [2:0]              tmds,
    output logic                    tmds_clock,
    
    // Pixel positions
    input  logic [BIT_WIDTH-1:0]    cx,
    input  logic [BIT_HEIGHT-1:0]   cy,

    input  logic                    vsync,
    input  logic                    hsync,

    // The screen is at the upper left corner of the frame.
    // 0,0 = 0,0 in video
    // the frame includes extra space for sending auxiliary data
    output logic [BIT_WIDTH-1:0]    frame_width,
    output logic [BIT_HEIGHT-1:0]   frame_height,
    output logic [BIT_WIDTH-1:0]    screen_width,
    output logic [BIT_HEIGHT-1:0]   screen_height
);


localparam int NUM_CHANNELS = 3;

logic [BIT_WIDTH-1:0] hsync_pulse_start, hsync_pulse_size;
logic [BIT_HEIGHT-1:0] vsync_pulse_start, vsync_pulse_size;
logic invert;


// See CEA-861-D for more specifics formats described below.
generate
    case (VIDEO_ID_CODE)
        1:
        begin
            assign frame_width = 800;
            assign frame_height = 525;
            assign screen_width = 640;
            assign screen_height = 480;
            assign hsync_pulse_start = 16;
            assign hsync_pulse_size = 96;
            assign vsync_pulse_start = 10;
            assign vsync_pulse_size = 2;
            assign invert = 1;
            end
        2, 3:
        begin
            assign frame_width = 858;
            assign frame_height = 525;
            assign screen_width = 720;
            assign screen_height = 480;
            assign hsync_pulse_start = 16;
            assign hsync_pulse_size = 62;
            assign vsync_pulse_start = 9;
            assign vsync_pulse_size = 6;
            assign invert = 1;
            end
        4:
        begin
            assign frame_width = 1650;
            assign frame_height = 750;
            assign screen_width = 1280;
            assign screen_height = 720;
            assign hsync_pulse_start = 110;
            assign hsync_pulse_size = 40;
            assign vsync_pulse_start = 5;
            assign vsync_pulse_size = 5;
            assign invert = 0;
        end
        16, 34:
        begin
            assign frame_width = 2200;
            assign frame_height = 1125;
            assign screen_width = 1920;
            assign screen_height = 1080;
            assign hsync_pulse_start = 88;
            assign hsync_pulse_size = 44;
            assign vsync_pulse_start = 4;
            assign vsync_pulse_size = 5;
            assign invert = 0;
        end
        17, 18:
        begin
            assign frame_width = 864;
            assign frame_height = 625;
            assign screen_width = 720;
            assign screen_height = 576;
            assign hsync_pulse_start = 12;
            assign hsync_pulse_size = 64;
            assign vsync_pulse_start = 5;
            assign vsync_pulse_size = 5;
            assign invert = 1;
        end
        19:
        begin
            assign frame_width = 1980;
            assign frame_height = 750;
            assign screen_width = 1280;
            assign screen_height = 720;
            assign hsync_pulse_start = 440;
            assign hsync_pulse_size = 40;
            assign vsync_pulse_start = 5;
            assign vsync_pulse_size = 5;
            assign invert = 0;
        end
        95, 105, 97, 107:
        begin
            assign frame_width = 4400;
            assign frame_height = 2250;
            assign screen_width = 3840;
            assign screen_height = 2160;
            assign hsync_pulse_start = 176;
            assign hsync_pulse_size = 88;
            assign vsync_pulse_start = 8;
            assign vsync_pulse_size = 10;
            assign invert = 0;
        end
    endcase
endgenerate

localparam integer GUARD_CHARACTERS = 2;
localparam integer PREAMBLE_CHARACTERS = 8;
localparam integer MIN_CONTROL_CHARACTERS = 4;

localparam real VIDEO_RATE = (VIDEO_ID_CODE == 1 ? 25.2E6
    : VIDEO_ID_CODE == 2 || VIDEO_ID_CODE == 3 ? 27.027E6
    : VIDEO_ID_CODE == 4 ? 74.25E6
    : VIDEO_ID_CODE == 16 ? 148.5E6
    : VIDEO_ID_CODE == 17 || VIDEO_ID_CODE == 18 ? 27E6
    : VIDEO_ID_CODE == 19 ? 74.25E6
    : VIDEO_ID_CODE == 34 ? 74.25E6
    : VIDEO_ID_CODE == 95 || VIDEO_ID_CODE == 105 || VIDEO_ID_CODE == 97 || VIDEO_ID_CODE == 107 ? 594E6
    : 0) * (VIDEO_REFRESH_RATE == 59.94 || VIDEO_REFRESH_RATE == 29.97 ? 1000.0/1001.0 : 1); // https://groups.google.com/forum/#!topic/sci.engr.advanced-tv/DQcGk5R_zsM

/*
I need to generate:
 - video preamble: 10 cycles before video to 3 cycles before
 - video guard: 2 cycles to 1 cycle before video
 - video data period: h active region
 - data island preamble: 10 to 3 cycles before data island (starting 4 cycles after end of video)
 - data island guard (x2): 2 to 1 cycle before data island, and 1 to 2 cycles after
 - data island period: 320 cycles
 - data packet enable(s): single pulse every 32 cycles, starting just before data island. 10x pulses per data island
 - video field end: one cycle pulse at the last pixel of the last line
   - in hdmi.sv it is generated on 1279, data continues to 1280. doesn't matter, only used in a place with packet enable which isnt until 1294

Video active in my framebuffer starting on o_h_count = 371, stopping on o_h_count = 0 (just after wrapping from 1649)
So...
 - Video preamble [361:368]
 - Video guard [369:370]
 - Control area [1:4]
 - Data island preamble [5:12]
 - Data island guard [13:14]
 - Data island [15:334]
 --- Data packet enable [14, 46, 78, 110, 142, 174, 206, 238, 270, 302]
 - Data island guard [335:336]
 - Control area [337:360]
*/

// See Section 5.2
logic video_data_period = 0;
always_ff @(posedge clk_pixel)
begin
    if (reset)
        video_data_period <= 0;
    else
        // video_data_period <= cx < screen_width && cy < screen_height;
        video_data_period <= (cx >= (frame_width - screen_width)) && (cy >= (frame_height - screen_height));
end

logic [2:0] mode = 3'd1;
logic [23:0] video_data = 24'd0;
logic [5:0] control_data = 6'd0;
logic [11:0] data_island_data = 12'd0;

generate
    if (!DVI_OUTPUT)
    begin: true_hdmi_output
        logic video_guard = 1;
        logic video_preamble = 0;
        always_ff @(posedge clk_pixel)
        begin
            if (reset)
            begin
                video_guard <= 1;
                video_preamble <= 0;
            end
            else
            begin
                // video_guard <= cx >= frame_width - 2 && cx < frame_width && (cy == frame_height - 1 || cy < screen_height - 1 /* no VG at end of last line */);
                // video_preamble <= cx >= frame_width - 10 && cx < frame_width - 2 && (cy == frame_height - 1 || cy < screen_height - 1 /* no VP at end of last line */);

                video_guard <= (cx >= (frame_width - screen_width) - GUARD_CHARACTERS) 
                            && (cx < (frame_width - screen_width)) 
                            && (cy >= (frame_height - screen_height));

                video_preamble <= (cx >= (frame_width - screen_width) - (GUARD_CHARACTERS + PREAMBLE_CHARACTERS)) 
                            && (cx < (frame_width - screen_width - GUARD_CHARACTERS)) 
                            && (cy >= (frame_height - screen_height));
            end
        end

        // See Section 5.2.3.1
        int max_num_packets_alongside;
        logic [4:0] num_packets_alongside;
        always_comb
        begin
            max_num_packets_alongside = (frame_width - screen_width  /* VD period */ 
                - GUARD_CHARACTERS /* 2x V guard */ 
                - PREAMBLE_CHARACTERS /* 8x V preamble */ 
                - MIN_CONTROL_CHARACTERS /* 4x Min V control period */ 
                - GUARD_CHARACTERS /* 2x DI trailing guard */ 
                - GUARD_CHARACTERS /* 2x DI leading guard */ 
                - PREAMBLE_CHARACTERS /* 8x DI premable */ 
                - MIN_CONTROL_CHARACTERS /* 4x Min DI control period */) / 32;
            if (max_num_packets_alongside > 18)
                num_packets_alongside = 5'd18;
            else
                num_packets_alongside = 5'(max_num_packets_alongside);
        end

        logic data_island_period_instantaneous;
        // assign data_island_period_instantaneous = num_packets_alongside > 0 && cx >= screen_width + 14 && cx < screen_width + 14 + num_packets_alongside * 32;
        assign data_island_period_instantaneous = num_packets_alongside > 0 
                                                && (cx >= 14) 
                                                && (cx < (14 + (num_packets_alongside * 32)));
        logic packet_enable;
        // assign packet_enable = data_island_period_instantaneous && 5'(cx + screen_width + 18) == 5'd0;
        
        // divisible by 32, starting at cycle 14. 
        //So this math will start on the first cycle of "data_island_period_instantaneous" and pulse every 32 cycles after that too
        assign packet_enable = data_island_period_instantaneous && 5'(cx + (32-14)) == 5'd0; 

        logic data_island_guard = 0;
        logic data_island_preamble = 0;
        logic data_island_period = 0;
        always_ff @(posedge clk_pixel)
        begin
            if (reset)
            begin
                data_island_guard <= 0;
                data_island_preamble <= 0;
                data_island_period <= 0;
            end
            else
            begin
                // data_island_guard <= num_packets_alongside > 0 && (
                //     (cx >= screen_width + 12 && cx < screen_width + 14) /* leading guard */ || 
                //     (cx >= screen_width + 14 + num_packets_alongside * 32 && cx < screen_width + 14 + num_packets_alongside * 32 + 2) /* trailing guard */
                // );
                // data_island_preamble <= num_packets_alongside > 0 && cx >= screen_width + 4 && cx < screen_width + 12;
                // data_island_period <= data_island_period_instantaneous;

                data_island_guard <= (num_packets_alongside > 0)
                    && (((cx >= 12) && (cx < 14))     // leading guard
                        || ((cx >= (14 + (num_packets_alongside * 32))) && (cx < (16 + (num_packets_alongside * 32))))); // trailing guard
                data_island_preamble <= (num_packets_alongside > 0)
                    && (cx >= 4) && (cx < 12);
                data_island_period <= data_island_period_instantaneous;
            end
        end

        // See Section 5.2.3.4
        logic [23:0] header;
        logic [55:0] sub [3:0];
        logic video_field_end;
        assign video_field_end = cx == frame_width - 1'b1 && cy == frame_height - 1'b1;
        logic [4:0] packet_pixel_counter;
        packet_picker #(
            .VIDEO_ID_CODE(VIDEO_ID_CODE),
            .VIDEO_RATE(VIDEO_RATE),
            .IT_CONTENT(IT_CONTENT),
            .AUDIO_RATE(AUDIO_RATE),
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .VENDOR_NAME(VENDOR_NAME),
            .PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
            .SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION)
        ) packet_picker (.clk_pixel(clk_pixel), .clk_audio(clk_audio), .reset(reset), .video_field_end(video_field_end), .packet_enable(packet_enable), .packet_pixel_counter(packet_pixel_counter), .audio_sample_word(audio_sample_word), .header(header), .sub(sub));
        logic [8:0] packet_data;
        packet_assembler packet_assembler (.clk_pixel(clk_pixel), .reset(reset), .data_island_period(data_island_period), .header(header), .sub(sub), .packet_data(packet_data), .counter(packet_pixel_counter));


        always_ff @(posedge clk_pixel)
        begin
            if (reset)
            begin
                mode <= 3'd2;
                video_data <= 24'd0;
                control_data = 6'd0;
                data_island_data <= 12'd0;
            end
            else
            begin
                mode <= data_island_guard ? 3'd4 : data_island_period ? 3'd3 : video_guard ? 3'd2 : video_data_period ? 3'd1 : 3'd0;
                video_data <= {pixel_r, pixel_g, pixel_b};
                control_data <= {{1'b0, data_island_preamble}, {1'b0, video_preamble || data_island_preamble}, {vsync, hsync}}; // ctrl3, ctrl2, ctrl1, ctrl0, vsync, hsync
                data_island_data[11:4] <= packet_data[8:1];
                data_island_data[3] <= cx != 0;
                data_island_data[2] <= packet_data[0];
                data_island_data[1:0] <= {vsync, hsync};
            end
        end
    end
    else // DVI_OUTPUT = 1
    begin
        always_ff @(posedge clk_pixel)
        begin
            if (reset)
            begin
                mode <= 3'd0;
                video_data <= 24'd0;
                control_data <= 6'd0;
            end
            else
            begin
                mode <= video_data_period ? 3'd1 : 3'd0;
                video_data <= {pixel_r, pixel_g, pixel_b};
                control_data <= {4'b0000, {vsync, hsync}}; // ctrl3, ctrl2, ctrl1, ctrl0, vsync, hsync
            end
        end
    end
endgenerate

// All logic below relates to the production and output of the 10-bit TMDS code.
logic [9:0] tmds_internal [NUM_CHANNELS-1:0] /* verilator public_flat */ ;
genvar i;
generate
    // TMDS code production.
    for (i = 0; i < NUM_CHANNELS; i++)
    begin: tmds_gen
        tmds_channel #(.CN(i)) tmds_channel (.clk_pixel(clk_pixel), .video_data(video_data[i*8+7:i*8]), .data_island_data(data_island_data[i*4+3:i*4]), .control_data(control_data[i*2+1:i*2]), .mode(mode), .tmds(tmds_internal[i]));
    end
endgenerate

serializer #(.NUM_CHANNELS(NUM_CHANNELS), .VIDEO_RATE(VIDEO_RATE)) serializer(.clk_pixel(clk_pixel), .clk_pixel_x5(clk_pixel_x5), .reset(reset), .tmds_internal(tmds_internal), .tmds(tmds), .tmds_clock(tmds_clock));

endmodule
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on WIDTHTRUNC */
