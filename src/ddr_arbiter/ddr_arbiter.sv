module ddr_arbiter 
#(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 128

    // parameterize number of ports?
)
(
    input  logic                    rstn_i,

    input  logic                    ddr_clk_i,  // interface clock
                                                // all ports are synchronous
 
    // Input port 1 - highest priority
    output logic                    ddr1_busy_o,
    input  logic                    ddr1_wr_en_i,
    input  logic                    ddr1_rd_en_i,
    input  logic [ADDR_WIDTH-1:0]   ddr1_addr_i,
    input  logic [DATA_WIDTH-1:0]   ddr1_wr_data_i,
    output logic [DATA_WIDTH-1:0]   ddr1_rd_data_o,
    output logic                    ddr1_rd_data_valid_o,
    // Input port 2
    output logic                    ddr2_busy_o,
    input  logic                    ddr2_wr_en_i,
    input  logic                    ddr2_rd_en_i,
    input  logic [ADDR_WIDTH-1:0]   ddr2_addr_i,
    input  logic [DATA_WIDTH-1:0]   ddr2_wr_data_i,
    output logic [DATA_WIDTH-1:0]   ddr2_rd_data_o,
    output logic                    ddr2_rd_data_valid_o,
    // Input port 3 - lowest priority
    output logic                    ddr3_busy_o,
    input  logic                    ddr3_wr_en_i,
    input  logic                    ddr3_rd_en_i,
    input  logic [ADDR_WIDTH-1:0]   ddr3_addr_i,
    input  logic [DATA_WIDTH-1:0]   ddr3_wr_data_i,
    output logic [DATA_WIDTH-1:0]   ddr3_rd_data_o,
    output logic                    ddr3_rd_data_valid_o,
    // Output port - to memory controller
    input  logic                    ddr_busy_i,
    output logic                    ddr_wr_en_o,
    output logic                    ddr_rd_en_o,
    output logic [ADDR_WIDTH-1:0]   ddr_addr_o,
    output logic [DATA_WIDTH-1:0]   ddr_wr_data_o,
    input  logic [DATA_WIDTH-1:0]   ddr_rd_data_i,
    input  logic                    ddr_rd_data_valid_i
);

logic [2:0] selected_port; // one-hot
logic port1pend, port2pend, port3pend;

logic port1_req, port2_req, port3_req;
assign port1_req = ddr1_rd_en_i || ddr1_wr_en_i;
assign port2_req = ddr2_rd_en_i || ddr2_wr_en_i;
assign port3_req = ddr3_rd_en_i || ddr3_wr_en_i;

assign ddr1_busy_o = ddr_busy_i || (!selected_port[0]);
assign ddr2_busy_o = ddr_busy_i || (!selected_port[1]);
assign ddr3_busy_o = ddr_busy_i || (!selected_port[2]);

assign ddr1_rd_data_o = ddr_rd_data_i;
assign ddr2_rd_data_o = ddr_rd_data_i;
assign ddr3_rd_data_o = ddr_rd_data_i;


// port selection logic
// higher ports get priority
// once selected, stays selected while it has a transaction
// otherwise, switches to the next highest priority port with a pending request
always_ff @(posedge ddr_clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
        selected_port <= 3'b001;
    end else begin
        // if (!burst_locked) begin
        if(port1pend || (selected_port[0] && (port1_req))) begin
            selected_port <= 3'b001;
        end 
        else if(port2pend || (selected_port[1] && (port2_req))) begin
            selected_port <= 3'b010;
        end 
        else if(port3pend || (selected_port[2] && (port3_req))) begin
            selected_port <= 3'b100;
        end
        // end
    end
end

// pending port - just check if it is NOT selected and has a transaction request
always_comb begin
    port1pend = 0;
    if ((!selected_port[0]) && (port1_req)) 
        port1pend = 1;

    port2pend = 0;
    if ((!selected_port[1]) && (port2_req)) 
        port2pend = 1;

    port3pend = 0;
    if ((!selected_port[2]) && (port3_req)) 
        port3pend = 1;
end

// output mux
always_comb begin
    ddr_wr_en_o = ddr1_wr_en_i;
    ddr_rd_en_o = ddr1_rd_en_i;
    ddr_addr_o = ddr1_addr_i;
    ddr_wr_data_o = ddr1_wr_data_i;

    if (selected_port[1]) begin
        ddr_wr_en_o = ddr2_wr_en_i;
        ddr_rd_en_o = ddr2_rd_en_i;
        ddr_addr_o = ddr2_addr_i;
        ddr_wr_data_o = ddr2_wr_data_i;
        
    end else if (selected_port[2]) begin
        ddr_wr_en_o = ddr3_wr_en_i;
        ddr_rd_en_o = ddr3_rd_en_i;
        ddr_addr_o = ddr3_addr_i;
        ddr_wr_data_o = ddr3_wr_data_i;
    end
end

// read valid logic - a bit trickier than the other muxes.
// when a read request has been accepted (ddr_rd_en_o true and ddr_busy_i false), 
// add the currently selected port to a FIFO
// every valid read data coming back pops the earliest FIFO entry and activates that
// port's data valid signal
// Must be a first-word-fallthrough FIFO for this scheme to work combinatorially

logic [2:0] read_fifo_out;
logic read_fifo_wr_en;

// assign read_fifo_wr_en = (ddr1_rd_en_i && (!ddr1_busy_o)) 
//                     || (ddr2_rd_en_i && (!ddr2_busy_o)) 
//                     || (ddr3_rd_en_i && (!ddr3_busy_o));

assign read_fifo_wr_en = ddr_rd_en_o && (!ddr_busy_i);

fifo_sc_ssram #(
    .DSIZE(3),
    .DEPTH(16)
) read_port_fifo (
    .Reset(!rstn_i),
    .Data(selected_port),
    .Clk(ddr_clk_i),
    .WrEn(read_fifo_wr_en),
    .RdEn(ddr_rd_data_valid_i),
    .Q(read_fifo_out),
    .AlmostEmptySetTh(2),
    .AlmostEmptyClrTh(3),
    .AlmostFullSetTh(14),
    .AlmostFullClrTh(13),
    .Almost_Empty(),
    .Almost_Full(),
    .Wnum(),
    .Empty(),
    .Full()
);

always_comb begin
    ddr1_rd_data_valid_o = 0;
    ddr2_rd_data_valid_o = 0;
    ddr3_rd_data_valid_o = 0;

    if(ddr_rd_data_valid_i && read_fifo_out[0]) 
        ddr1_rd_data_valid_o = 1;
    if(ddr_rd_data_valid_i && read_fifo_out[1]) 
        ddr2_rd_data_valid_o = 1;
    if(ddr_rd_data_valid_i && read_fifo_out[2]) 
        ddr3_rd_data_valid_o = 1;
    
end

endmodule

