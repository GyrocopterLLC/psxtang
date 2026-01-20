module psxddr_to_ahb

(
    input         RESET,
	//DDR3 RAM interface from psx core
	input         DDRAM_CLK,
	output        DDRAM_BUSY,
	input   [7:0] DDRAM_BURSTCNT,
	input  [28:0] DDRAM_ADDR,
	output [63:0] DDRAM_DOUT,
	output        DDRAM_DOUT_READY,
	input         DDRAM_RD,
	input  [63:0] DDRAM_DIN,
	input   [7:0] DDRAM_BE,
	input         DDRAM_WE,

    // DDR3 RAM interface to AHB ram interface
    output          HCLK,   // direct copy of the input clock.
                            // this is a synchronous module
    output [31:0]   HADDR,         
    output [ 1:0]   HTRANS,
    output          HWRITE,
    output [ 2:0]   HSIZE,
    output [ 2:0]   HBURST,
    output [ 7:0]   HWSTRB,
    output [63:0]   HWDATA,
    input  [63:0]   HRDATA,
    input           HREADY,
    input  [ 1:0]   HRESP
);


logic busy_out = 0;
logic dout_ready_out = 0;
logic [28:0] haddr_out = 0; 
logic hwrite_out = 0;
logic htrans_out = 0;
logic [63:0] hwdata_r = 0;
logic [63:0] hwdata_out = 0;
// logic [63:0] hrdata_r = 0;
logic  [7:0] hwstrb_r = 0;
logic  [7:0] hwstrb_out = 0;
logic  [7:0] burstcnt_r = 0;

typedef enum logic [2:0] {
    IDLE,
    WRITE_ADDR,
    WRITE_DATA,
    READ_ADDR,
    READ_DATA
} ahbstate_t;

ahbstate_t c_s = IDLE;

assign HCLK = DDRAM_CLK;
assign HADDR[31:29] = 3'b000; // upper bits are ignored since they can't be addressed anyway
assign HADDR[28: 0] = haddr_out;
assign HSIZE = 3'b011; // Size always fixed to 64 bits
assign HBURST = 3'b000; // Burst not supported
assign HWRITE = hwrite_out;
assign HTRANS = {htrans_out, 1'b0};


assign DDRAM_BUSY = (c_s == WRITE_ADDR) || (c_s == WRITE_DATA);
assign DDRAM_DOUT = HRDATA; // direct path for reads, not registered. 
assign DDRAM_DOUT_READY = (c_s == READ_DATA) & HREADY;


always_ff @(posedge DDRAM_CLK or posedge RESET) begin
    if(RESET) begin
        c_s <= IDLE;
        htrans_out <= 0;
        hwrite_out <= 0;
    end else begin
        case(c_s)
        IDLE: begin
            if(DDRAM_WE) begin
                c_s <= WRITE_ADDR;
                haddr_out <= DDRAM_ADDR;
                hwrite_out <= 1;
                htrans_out <= 1;
                hwdata_r <= DDRAM_DIN;
                hwstrb_r <= DDRAM_BE;
            end
            else if(DDRAM_RD) begin
                c_s <= READ_ADDR;
                haddr_out <= DDRAM_ADDR;
                hwrite_out <= 0;
                htrans_out <= 1;
                burstcnt_r <= DDRAM_BURSTCNT;
            end
        end
        WRITE_ADDR: begin
            if(HREADY) begin
                c_s <= WRITE_DATA;
                hwrite_out <= 0;
                htrans_out <= 0;
                hwdata_out <= hwdata_r;
                hwstrb_out <= hwstrb_r;
            end
        end
        WRITE_DATA: begin
            if(HREADY) begin
                c_s <= IDLE;
            end
        end

        READ_ADDR: begin
            if(HREADY) begin
                c_s <= READ_DATA;
                if(burstcnt_r == 8'd1) 
                // only need to stop transaction if this is the last of the burst
                // or if it was just a single non-burst read
                    htrans_out <= 0;
                else
                    haddr_out <= haddr_out + 29'd8;
            end
        end
        READ_DATA: begin
            if(HREADY) begin
                burstcnt_r <= burstcnt_r - 8'd1;
                if(burstcnt_r == 8'd1) begin
                    // received final data
                    c_s <= IDLE;
                end else
                if(burstcnt_r == 8'd2) begin
                    // final read request, trans should go to zero now
                    c_s <= READ_DATA;
                    htrans_out <= 0;
                end
                else begin
                    // more reads to follow
                    c_s <= READ_DATA;
                    haddr_out <= haddr_out + 29'd8; // TODO: make the summation over a smaller bit width
                end
            end
        end
        default: begin
            c_s <= IDLE;
            hwrite_out <= 0;
            htrans_out <= 0;
        end
        endcase

    end
end

endmodule
