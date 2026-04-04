// Single clock FIFO
// adjustable data width and size (depth)

// Implementation:
// - First word fallthrough
// - Empty
// - Full
// - AlmostEmpty (with dual dynamic threshold)
// - AlmostFull (with dual dynamic threshold)
// - Write count
// - No output register
// - No ECC
// - Memory is shadow sram ("distributed_ram")

/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */

module fifo_sc_ssram #(
    parameter int DSIZE = 32,
    parameter int DEPTH = 128,
    parameter int ASIZE = $clog2(DEPTH)
) (
    input  logic [DSIZE-1:0] Data,
    input  logic             Clk,
    input  logic             WrEn,
    input  logic             RdEn,
    input  logic             Reset,
    input  logic [ASIZE-1:0] AlmostEmptySetTh,
    input  logic [ASIZE-1:0] AlmostEmptyClrTh,
    input  logic [ASIZE-1:0] AlmostFullSetTh,
    input  logic [ASIZE-1:0] AlmostFullClrTh,
    output logic [  ASIZE:0] Wnum,
    output logic             Almost_Empty,
    output logic             Almost_Full,
    output logic [DSIZE-1:0] Q,
    output logic             Empty,
    output logic             Full
);

    logic [ASIZE-1:0] raddr;
    logic [ASIZE-1:0] waddr;
    logic             rempty_val;
    logic             wfull_val;
    logic             arempty_val;
    logic             awfull_val;
    logic [  ASIZE:0] wcnt_sub;

    logic [  ASIZE:0] rbin_next;
    logic [  ASIZE:0] wbin_next;
    logic [  ASIZE:0] rbin;
    logic [  ASIZE:0] wbin;

    logic [DSIZE-1:0] Q_r2;

    logic [DSIZE-1:0] mem[0:(DEPTH-1)]   /* synthesis syn_ramstyle= "distributed_ram" */;

    /*****************************************/
    // Read and write data logic
    /****************************************/
    always_ff @(posedge Clk)
        if (WrEn && ~Full)
            mem[waddr] <= Data;

    always_ff @(posedge Clk or posedge Reset)
        if (Reset) Q_r2 <= 0;
        // else if (~rempty_val)
        else if (RdEn ? ~rempty_val : (Empty & !rempty_val)) Q_r2 <= mem[raddr];

    assign Q = Q_r2;

    /**********************************************/
    // Control signal logic
    /*********************************************/
    always_ff @(posedge Clk or posedge Reset)
        if (Reset) rbin <= 0;
        else rbin <= rbin_next;

    always_ff @(posedge Clk or posedge Reset)
        if (Reset) wbin <= 0;
        else wbin <= wbin_next;

    assign raddr = rbin_next[ASIZE-1:0];

    assign rbin_next = rbin + (RdEn & ~Empty);

    assign waddr = wbin[ASIZE-1:0];
    assign wbin_next = wbin + (WrEn & ~Full);

    assign wcnt_sub   = {wbin_next[ASIZE]^rbin_next[ASIZE],wbin_next[ASIZE-1:0]} - {1'b0,rbin_next[ASIZE-1:0]};
    assign rempty_val = (rbin_next == wbin);
    assign wfull_val = (wbin_next == {~rbin_next[ASIZE], rbin_next[ASIZE-1:0]});


    always_ff @(posedge Clk or posedge Reset)
        if (Reset) Empty <= 1'b1;
        else Empty <= rempty_val;

    always_ff @(posedge Clk or posedge Reset)
        if (Reset) Full <= 1'b0;
        else Full <= wfull_val;

    assign arempty_val = (wcnt_sub <= AlmostEmptyClrTh);
    assign awfull_val  = (wcnt_sub >= AlmostFullClrTh);


    always_ff @(posedge Clk or posedge Reset) begin
        if (Reset) Almost_Empty <= 1'b1;
        else if ((arempty_val == 1) && (wcnt_sub <= AlmostEmptySetTh))
            Almost_Empty <= 1'b1;
        else if (arempty_val == 0) Almost_Empty <= 1'b0;
    end

    always_ff @(posedge Clk or posedge Reset) begin
        if (Reset) Almost_Full <= 1'b0;
        else if ((awfull_val == 1) && (wcnt_sub >= AlmostFullSetTh))
            Almost_Full <= 1'b1;
        else if (awfull_val == 0) Almost_Full <= 1'b0;
    end

    always_ff @(posedge Clk or posedge Reset)
        if (Reset) Wnum <= 0;
        else Wnum <= wcnt_sub;

endmodule
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on WIDTHTRUNC */
