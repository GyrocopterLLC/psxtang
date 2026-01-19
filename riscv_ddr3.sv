//********************************************************************
// Replaces the default Gowin DDR3 interface module with a custom
// single AHB to DDR3 interface.
//********************************************************************

module riscv_ae350_ddr3_top
(
    // DDR3 interface
    input   wire            DDR3_MEMORY_CLK,    // Memory clock
    input   wire            DDR3_CLK_IN,        // Clock in
    input   wire            DDR3_RSTN,          // Reset
    input   wire            DDR3_LOCK,          // PLL lock
    output  wire            DDR3_STOP,          // PLL stop
    output 	wire            DDR3_INIT,          // Initialized
    output  wire    [2:0]   DDR3_BANK,
    output  wire            DDR3_CS_N,
    output  wire            DDR3_RAS_N,
    output  wire            DDR3_CAS_N,
    output  wire            DDR3_WE_N,
    output  wire            DDR3_CK,
    output  wire            DDR3_CK_N,
    output  wire            DDR3_CKE,
    output  wire            DDR3_RESET_N,
    output  wire            DDR3_ODT,
    output  wire    [13:0]  DDR3_ADDR,
    output  wire    [1:0]   DDR3_DM,
    inout   wire    [15:0]  DDR3_DQ,
    inout   wire    [1:0]   DDR3_DQS,
    inout   wire    [1:0]   DDR3_DQS_N,

    // External AHB interface
    input   wire            EM_HRESETN, // resets the arbiter and AHB-DDR adapter
    output  wire            EM_HCLK, // copy of DDR_CLK (HCLK from AE350)
    input   wire            EM_HSEL,
    input   wire    [31:0]  EM_HADDR,
    input   wire    [ 1:0]  EM_HTRANS,
    input   wire            EM_HWRITE,
    input   wire    [ 2:0]  EM_HSIZE,
    input   wire    [ 2:0]  EM_HBURST,
    input   wire    [63:0]  EM_HWDATA,
    output  wire    [63:0]  EM_HRDATA,
    output  wire            EM_HREADYOUT,
    output  wire    [ 1:0]  EM_HRESP,

    // AHB bus interface
    input   wire            HCLK,
    input   wire            HRESETN,
    input   wire    [31:0]  HADDR,
    input   wire    [2:0]   HSIZE,
    input   wire            HWRITE,
    input   wire    [1:0]   HTRANS,
    input   wire    [2:0]   HBURST,
    input   wire    [3:0]   HPROT,
    input   wire    [63:0]  HWDATA,
    output  wire            HREADY_O,
    output  wire    [1:0]   HRESP,
    output  wire    [63:0]  HRDATA
);

wire ddr3_memory_clk_div4; // memory interface clock in 1:4 ratio

wire            lpddr_cmd_ready;
wire            lpddr_cmd;
wire            lpddr_cmd_en;
wire [31:0]     cmd_addr;
wire            lpddr_data_ready;
wire [127:0]    wr_data;
wire            lpddr_wdata_en;
wire [ 15:0]    lpddr_wdata_mask;
wire [127:0]    lpddr_rd_data;
wire            lpddr_rd_valid;
wire            lpddr_rd_end;

wire [ 15:0]    mem_byte_en;
assign lpddr_wdata_mask = ~mem_byte_en;

wire mem_cmd_ready;
assign mem_cmd_ready = lpddr_data_ready & lpddr_cmd_ready;

assign EM_HCLK = HCLK;
wire ARB_RESETn;
assign ARB_RESETn = (HRESETN & EM_HRESETN);

wire [1:0] ahb_hresp;
assign HRESP = ahb_hresp[0]; // dump the upper bit, it is unused

// AHB after the arbiter, connected to the AHB-DDR adapter
wire            mem_HSEL;
wire    [31:0]  mem_HADDR;
wire    [ 2:0]  mem_HSIZE;
wire    [ 1:0]  mem_HTRANS;
wire    [63:0]  mem_HWDATA;
wire            mem_HWRITE;
wire    [63:0]  mem_HRDATA;
wire            mem_HREADY_O;
wire    [ 1:0]  mem_HRESP;

Gowin_AHB_Arbiter_Top u_arbiter(
    .HCLK(HCLK),
    .HRESETn(ARB_RESETn),
    // Port 0 = external AHB from PL
    //  - this port has highest priority
    .MHSELS0(EM_HSEL),
    .MHADDRS0(EM_HADDR),
    .MHTRANSS0(EM_HTRANS),
    .MHWRITES0(EM_HWRITE),
    .MHSIZES0(EM_HSIZE),
    .MHBURSTS0(EM_HBURST),
    .MHPROTS0(4'b0011), // recommended per ARM for unused HPROT.  Non-cacheable, Non-bufferable, privileged, data access
    .MHMASTERS0(4'b0000),
    .MHWDATAS0(EM_HWDATA),
    .MHMASTLOCKS0(1'b0),
    .MHREADYS0(EM_HREADYOUT), // feedback readyout to ready
    .MHRDATAS0(EM_HRDATA),
    .MHREADYOUTS0(EM_HREADYOUT),
    .MHRESPS0(EM_HRESP),
    // Port 1 = AHB from AE350 Risc-V
    .MHSELS1(1'b1),
    .MHADDRS1(HADDR),
    .MHTRANSS1(HTRANS),
    .MHWRITES1(HWRITE),
    .MHSIZES1(HSIZE),
    .MHBURSTS1(HBURST),
    .MHPROTS1(HPROT),
    .MHMASTERS1(4'b0000),
    .MHWDATAS1(HWDATA),
    .MHMASTLOCKS1(1'b0),
    .MHREADYS1(HREADY_O), // feedback readyout to ready
    .MHRDATAS1(HRDATA),
    .MHREADYOUTS1(HREADY_O),
    .MHRESPS1(ahb_hresp),
    // Subordinate port = AHB-DDR adapter
    .SHRDATAM0(mem_HRDATA),
    .SHREADYOUTM0(mem_HREADY_O),
    .SHRESPM0(mem_HRESP),
    .SHSELM0(mem_HSEL),
    .SHADDRM0(mem_HADDR),
    .SHTRANSM0(mem_HTRANS),
    .SHWRITEM0(mem_HWRITE),
    .SHSIZEM0(mem_HSIZE),
    .SHBURSTM0(),
    .SHPROTM0(),
    .SHMASTERM0(),
    .SHWDATAM0(mem_HWDATA),
    .SHMASTLOCKM0(),
    .SHREADYMUXM0()
);

ahb_to_mem_adapter u_ahb_to_mem(
    .hclk                       (HCLK),
    .hresetn                    (ARB_RESETn),
    .haddr                      (mem_HADDR),
    .hsize                      (mem_HSIZE),
    .htrans                     (mem_HTRANS),
    .hwstrb                     (8'hFF),
    .hwdata                     (mem_HWDATA),
    .hwrite                     (mem_HWRITE),
    .hsel                       (mem_HSEL),
    .hready                     (1'b1),
    .hrdata                     (mem_HRDATA),
    .hreadyout                  (mem_HREADY_O),
    .hresp                      (mem_HRESP),
    .mem_clk                    (ddr3_memory_clk_div4),
    .mem_resetn                 (DDR3_RSTN),
    .mem_addr                   (cmd_addr),
    .mem_wdata                  (wr_data),
    .mem_byte_en                (mem_byte_en),
    .mem_cmd_en                 (lpddr_cmd_en),
    .mem_cmd                    (lpddr_cmd),
    .mem_cmd_ready              (mem_cmd_ready),
    .mem_rdata                  (lpddr_rd_data),
    .mem_data_ready             (lpddr_rd_valid)
);

assign lpddr_wdata_en = lpddr_cmd_en && (lpddr_cmd == 1'b0);

DDR3_Memory_Interface_Top u_ddr3
(
    .memory_clk              (DDR3_MEMORY_CLK),
    .pll_stop                (DDR3_STOP),
    .clk                     (DDR3_CLK_IN),
    .pll_lock                (DDR3_LOCK),
    .rst_n                   (DDR3_RSTN),
    .cmd_ready               (lpddr_cmd_ready),
    .cmd                     ({2'b00,lpddr_cmd}),
    .cmd_en                  (lpddr_cmd_en),
	.addr                    ({cmd_addr[28:1]}), // AHB is byte-addressed, but DDR is 16-bit. Drop the lowest address bit.
	.wr_data_rdy             (lpddr_data_ready),
	.wr_data                 (wr_data),
	.wr_data_en              (lpddr_wdata_en),
	.wr_data_end             (lpddr_wdata_en),
    .wr_data_mask            (lpddr_wdata_mask),
    .rd_data                 (lpddr_rd_data),
    .rd_data_valid           (lpddr_rd_valid),
    .rd_data_end             (lpddr_rd_end),
    .sr_req                  (1'b0),
    .ref_req                 (1'b0),
	.sr_ack                  (),  // output, nc
    .ref_ack                 (),  // output, nc
	.init_calib_complete     (DDR3_INIT),
	.clk_out                 (ddr3_memory_clk_div4),
	.ddr_rst                 (),  // outpout, nc
    .burst                   (1'b1),
	.O_ddr_addr              (DDR3_ADDR),
    .O_ddr_ba                (DDR3_BANK),
    .O_ddr_cs_n              (DDR3_CS_N),
    .O_ddr_ras_n             (DDR3_RAS_N),
    .O_ddr_cas_n             (DDR3_CAS_N),
    .O_ddr_we_n              (DDR3_WE_N),
    .O_ddr_clk               (DDR3_CK),
    .O_ddr_clk_n             (DDR3_CK_N),
    .O_ddr_cke               (DDR3_CKE),
    .O_ddr_odt               (DDR3_ODT),
    .O_ddr_reset_n           (DDR3_RESET_N),
    .O_ddr_dqm               (DDR3_DM),
    .IO_ddr_dq               (DDR3_DQ),
    .IO_ddr_dqs              (DDR3_DQS),
    .IO_ddr_dqs_n            (DDR3_DQS_N)
);

endmodule
