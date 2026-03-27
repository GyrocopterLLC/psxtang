
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */

module cdc_fifo #(
    parameter int RD_D_SIZE = 32,
    parameter int WR_D_SIZE = 32,
    parameter int RD_DEPTH  = 512,
    parameter int WR_DEPTH  = 512,
    parameter int RD_A_SIZE = $clog2(RD_DEPTH),
    parameter int WR_A_SIZE = $clog2(WR_DEPTH)
) (
    input logic [WR_D_SIZE-1:0] Data,   // Data to write into the FIFO
    input logic                 WrClk,
    input logic                 RdClk,
    input logic                 WrEn,
    input logic                 RdEn,

    input logic Reset,  //Reset Synchronization : only Reset

    input logic   [RD_A_SIZE-1:0]     AlmostEmptySetTh,   // Dynamic input threshold of almost empty set to 1
    input logic   [RD_A_SIZE-1:0]     AlmostEmptyClrTh,   // Dynamic input threshold of almost empty set to 0

    input logic [WR_A_SIZE-1:0] AlmostFullSetTh,  // Dynamic input threshold of almost full set to 1
    input logic [WR_A_SIZE-1:0] AlmostFullClrTh,  // Dynamic input threshold of almost full set to 0

    output logic [WR_A_SIZE:0] Wnum,  // Write data count: synchronized to WrClk,
    output logic [RD_A_SIZE:0] Rnum,  // Read data count: synchronized to RdCLK,

    output logic Almost_Empty,  // Flag of Almost empty
    output logic Almost_Full,  // Flag of Almost full

    output logic [RD_D_SIZE-1:0] Q,      // Data read from the fifo
    output logic                 Empty,  // Empty flag
    output logic                 Full    // Full flag
);

    logic         [RD_A_SIZE:0]     rbin_num; // Read pointer : binary
    // (note: 1-bit bigger than raddr_num in order to obtain the right flag signal)
    logic [RD_A_SIZE-1:0] raddr_num;  // Read address
    logic [RD_A_SIZE:0] rbin_num_next;
    logic [RD_A_SIZE:0] rcnt_sub;  // Read data count
    logic [WR_A_SIZE-1:0] waddr;  // Write address
    logic rempty_val;  // Empty value
    logic wfull_val;  // Full  value
    logic arempty_val;  // Almost empty value
    logic awfull_val;  // Almost full  value
    logic [WR_A_SIZE:0] wcnt_sub;  // Write data count
    logic WRst, RRst;

    localparam PWIDTH = 0;
    /******************************************************/
    // The read and write logic for differnt depth
    /******************************************************/

    logic [1:0] reset_r;
    logic [1:0] reset_w;
    always @(negedge RdClk or posedge Reset)
        if (Reset) reset_r <= 2'b11;
        else reset_r <= {reset_r[0], 1'b0};
    assign RRst = reset_r[1];
    always @(negedge WrClk or posedge Reset)
        if (Reset) reset_w <= 2'b11;
        else reset_w <= {reset_w[0], 1'b0};
    assign WRst = reset_w[1];


    always @(posedge RdClk or posedge RRst)
        if (RRst) rbin_num <= 0;
        else rbin_num <= rbin_num_next;

    generate
        if (WR_DEPTH < RD_DEPTH) begin : Small  // WR_DEPTH < RD_DEPTH
            localparam a = RD_DEPTH / WR_DEPTH;

            reg [WR_D_SIZE-1:0] mem[0:(WR_DEPTH-1)]  /* synthesis syn_ramstyle= "block_ram" */;

            reg [WR_D_SIZE-1:0] wdata;  // Data from the fifo
            reg [WR_A_SIZE:0] wptr;  // Write pointer
            reg [WR_A_SIZE:0] rptr;  // Read  pointer
            reg [WR_A_SIZE:0] wq2_rptr;  // Read  pointer synchronized to WrClk
            reg [WR_A_SIZE:0] rq2_wptr;  // Write pointer synchronized to RdCkl
            reg [WR_A_SIZE:0] wq1_rptr;
            reg [WR_A_SIZE:0] rq1_wptr;
            reg [WR_A_SIZE:0] wbin;  // Write pointer: binary
            // in the right flag signal
            wire [RD_A_SIZE:0] wcount_r_1;
            wire [WR_A_SIZE:0] rgraynext;  // Read pointer: gray code
            wire [WR_A_SIZE:0] rbinnext;
            wire [WR_A_SIZE:0] rbinnext_1;
            wire [WR_A_SIZE:0] wgraynext;
            wire [WR_A_SIZE:0] wcount_r;
            wire [WR_A_SIZE:0] rcount_w;
            wire [WR_A_SIZE:0] wbinnext;
            wire [RD_D_SIZE-1:0] wdata_q;

            always @(posedge WrClk)  // Write data into fifo
                if (WrEn && !Full)
                    mem[waddr] <= Data;

            // Read data from fifo
            always @(posedge RdClk or posedge RRst)
                if (RRst) wdata <= 0;
                else if (RdEn ? ~rempty_val : (Empty & !rempty_val))
                    wdata <= mem[raddr_num/a];

            assign wdata_q = RdEn ? wdata[(((raddr_num-1)%a+1)*RD_D_SIZE-1)-:RD_D_SIZE] :  wdata[(((raddr_num)%a+1)*RD_D_SIZE-1)-:RD_D_SIZE];


            assign Q = wdata_q;


            assign raddr_num = rbin_num_next[RD_A_SIZE-1:0];  // Read address

            assign rbin_num_next = rbin_num + (RdEn & ~Empty);  // Obtain the next read pointer
            assign rbinnext       =  rbin_num_next[RD_A_SIZE:0]/a;   // Read address transform because the different depth
            assign rbinnext_1 = rbin_num / a;
            assign rgraynext = (rbinnext >> 1) ^ rbinnext;  // Gray code transform
            assign rempty_val = (rgraynext == rq2_wptr);  // Judge empty value
            assign wcount_r = gry2bin(rq2_wptr);
            assign wcount_r_1 = gry2bin(
                    rq2_wptr
                ) * a;  // Write address transform
            assign rcnt_sub       =  {(wcount_r[WR_A_SIZE]^rbinnext_1[WR_A_SIZE]),wcount_r_1[RD_A_SIZE-1:0]}
                             -{1'b0,rbin_num[RD_A_SIZE-1:0]}; // Caculate the read data count

            assign waddr = wbin[WR_A_SIZE-1:0];  // Write address
            assign wbinnext = wbin + (WrEn & ~Full);
            assign wgraynext = (wbinnext >> 1) ^ wbinnext;  // Gray code transform

            if (WR_A_SIZE == 1) begin : ac  // Cacultate the full value
                assign wfull_val = (wgraynext == ~wq2_rptr[WR_A_SIZE:WR_A_SIZE-1]);
            end else if (WR_A_SIZE > 1) begin : ad
                assign wfull_val   =  (wgraynext == {~wq2_rptr[WR_A_SIZE:WR_A_SIZE-1],wq2_rptr[WR_A_SIZE-2:0]});
            end

            assign rcount_w = gry2bin(wq2_rptr);  // Transform to binary
            assign wcnt_sub       =  {(rcount_w[WR_A_SIZE] ^ wbin[WR_A_SIZE]), wbin[WR_A_SIZE-1:0]}
                            -{1'b0, rcount_w[WR_A_SIZE-1:0]};
            // pointer synchronization
            always @(posedge WrClk or posedge WRst)
                if (WRst) {wq2_rptr, wq1_rptr} <= 0;
                else {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr};

            always @(posedge RdClk or posedge RRst)
                if (RRst) {rq2_wptr, rq1_wptr} <= 0;
                else {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr};

            always @(posedge RdClk or posedge RRst)
                if (RRst) rptr <= 0;
                else rptr <= rgraynext;

            always @(posedge WrClk or posedge WRst)
                if (WRst) {wbin, wptr} <= 0;
                else {wbin, wptr} <= {wbinnext, wgraynext};
        end

else if(WR_DEPTH > RD_DEPTH) begin: Big  // WR_DEPTH > RD_DEPTH, variableas are similar to that when WR_DEPTH < RD_DEPTH
            integer j;
            localparam b = WR_DEPTH / RD_DEPTH;


            reg [WR_D_SIZE-1:0] mem[0:(WR_DEPTH-1)]  /* synthesis syn_ramstyle= "block_ram" */;



            reg [RD_D_SIZE-1:0] wdata_q;
            reg [RD_A_SIZE:0] wptr;
            reg [RD_A_SIZE:0] rptr;
            reg [RD_A_SIZE:0] wq2_rptr;
            reg [RD_A_SIZE:0] rq2_wptr;
            reg [RD_A_SIZE:0] wq1_rptr;
            reg [RD_A_SIZE:0] rq1_wptr;
            reg [WR_A_SIZE:0] wbin;
            wire [RD_A_SIZE:0] rgraynext;
            wire [RD_A_SIZE:0] wgraynext;
            wire [RD_A_SIZE:0] wcount_r;
            wire [RD_A_SIZE:0] rcount_w;
            wire [WR_A_SIZE:0] rcount_w_1;
            wire [WR_A_SIZE:0] wbin_num_next;
            wire [RD_A_SIZE:0] wbinnext;
            wire [RD_A_SIZE:0] wbinnext_1;

            always @(posedge WrClk) if (WrEn && !Full) mem[waddr] <= Data;


            always @(posedge RdClk or posedge RRst)
                if (RRst) wdata_q <= 0;
                else if (RdEn ? ~rempty_val : (Empty & !rempty_val))
                    for (j = 0; j < b; j = j + 1)
                        wdata_q[((j+1)*WR_D_SIZE-1)-:WR_D_SIZE] <= mem[raddr_num*b+j];


            assign Q = wdata_q;

            assign raddr_num = rbin_num_next[RD_A_SIZE-1:0];

            assign rbin_num_next = rbin_num + (RdEn & ~Empty);
            assign rgraynext = (rbin_num_next >> 1) ^ rbin_num_next;
            assign rempty_val = (rgraynext == rq2_wptr);
            assign wcount_r = gry2bin(rq2_wptr);
            assign rcnt_sub        =  {(wcount_r[RD_A_SIZE]^rbin_num[RD_A_SIZE]),wcount_r[RD_A_SIZE-1:0]}
                             -{1'b0,rbin_num[RD_A_SIZE-1:0]};

            assign waddr = wbin[WR_A_SIZE-1:0];
            assign wbin_num_next = wbin + (WrEn & ~Full);
            assign wbinnext = wbin_num_next / b;  //write to read
            assign wbinnext_1 = wbin / b;
            assign wgraynext = (wbinnext >> 1) ^ wbinnext;
            if (RD_A_SIZE == 1) begin : ae
                assign wfull_val = (wgraynext == ~wq2_rptr[RD_A_SIZE:RD_A_SIZE-1]);
            end else if (RD_A_SIZE > 1) begin : af
                assign wfull_val    =  (wgraynext == {~wq2_rptr[RD_A_SIZE:RD_A_SIZE-1],wq2_rptr[RD_A_SIZE-2:0]});
            end
            assign rcount_w = gry2bin(wq2_rptr);
            assign rcount_w_1 = gry2bin(wq2_rptr) * b;
            assign wcnt_sub        =  {(rcount_w[RD_A_SIZE] ^ wbinnext_1[RD_A_SIZE]), wbin[WR_A_SIZE-1:0]}
                             -{1'b0, rcount_w_1[WR_A_SIZE-1:0]};

            always @(posedge WrClk or posedge WRst)
                if (WRst) {wq2_rptr, wq1_rptr} <= 0;
                else {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr};

            always @(posedge RdClk or posedge RRst)
                if (RRst) {rq2_wptr, rq1_wptr} <= 0;
                else {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr};

            always @(posedge RdClk or posedge RRst)
                if (RRst) rptr <= 0;
                else rptr <= rgraynext;

            always @(posedge WrClk or posedge WRst)
                if (WRst) {wbin, wptr} <= 0;
                else {wbin, wptr} <= {wbin_num_next, wgraynext};

        end else if (WR_DEPTH == RD_DEPTH) begin : Equal



            reg  [WR_D_SIZE-1:0] mem       [0:(WR_DEPTH-1)]  /* synthesis syn_ramstyle= "block_ram" */;


            reg [WR_D_SIZE-1:0] wdata_q;

            reg [WR_A_SIZE:0] wptr;
            reg [WR_A_SIZE:0] rptr;
            reg [WR_A_SIZE:0] wq2_rptr;
            reg [WR_A_SIZE:0] rq2_wptr;
            reg [WR_A_SIZE:0] wq1_rptr;
            reg [WR_A_SIZE:0] rq1_wptr;

            reg [WR_A_SIZE:0] wbin;
            wire [WR_A_SIZE:0] rgraynext;
            wire [WR_A_SIZE:0] wgraynext;
            wire [WR_A_SIZE:0] wcount_r;
            wire [WR_A_SIZE:0] rcount_w;
            wire [WR_A_SIZE:0] wbinnext;

            always @(posedge WrClk)
                if (WrEn && !Full)
                    mem[waddr] <= Data;

            always @(posedge RdClk or posedge RRst)
                if (RRst) wdata_q <= 0;
                // else if(~Empty)
                else if (RdEn ? ~rempty_val : (Empty & !rempty_val))
                    wdata_q <= mem[raddr_num];



            assign Q = wdata_q;


            assign raddr_num = rbin_num_next[WR_A_SIZE-1:0];

            assign rbin_num_next = rbin_num + (RdEn & ~Empty);
            assign rgraynext = (rbin_num_next >> 1) ^ rbin_num_next;
            assign rempty_val = (rgraynext == rq2_wptr);
            assign wcount_r = gry2bin(rq2_wptr);
            assign rcnt_sub        =  {(wcount_r[WR_A_SIZE] ^ rbin_num[RD_A_SIZE]),wcount_r[WR_A_SIZE-1:0]}-{1'b0, rbin_num[RD_A_SIZE-1:0]};
            assign waddr = wbin[WR_A_SIZE-1:0];
            assign wbinnext = wbin + (WrEn & ~Full);
            assign wgraynext = (wbinnext >> 1) ^ wbinnext;

            if (WR_A_SIZE == 1) begin : ag
                assign wfull_val = (wgraynext == ~wq2_rptr[WR_A_SIZE:WR_A_SIZE-1]);
            end else if (WR_A_SIZE > 1) begin : ah
                assign wfull_val  =  (wgraynext == {~wq2_rptr[WR_A_SIZE:WR_A_SIZE-1],wq2_rptr[WR_A_SIZE-2:0]});
            end

            assign rcount_w = gry2bin(wq2_rptr);
            assign wcnt_sub        =  {(rcount_w[WR_A_SIZE] ^ wbin[WR_A_SIZE]), wbin[WR_A_SIZE-1:0]} - {1'b0, rcount_w[WR_A_SIZE-1:0]};

            always @(posedge WrClk or posedge WRst)
                if (WRst) {wq2_rptr, wq1_rptr} <= 0;
                else {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr};

            always @(posedge RdClk or posedge RRst)
                if (RRst) {rq2_wptr, rq1_wptr} <= 0;
                else {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr};

            always @(posedge RdClk or posedge RRst)
                if (RRst) rptr <= 0;
                else rptr <= rgraynext;

            always @(posedge WrClk or posedge WRst)
                if (WRst) {wbin, wptr} <= 0;
                else {wbin, wptr} <= {wbinnext, wgraynext};
        end
    endgenerate

    always @(posedge RdClk or posedge RRst)
        if (RRst) Empty <= 1'b1;
        else Empty <= rempty_val;

    always @(posedge WrClk or posedge WRst)
        if (WRst) Full <= 1'b0;
        else Full <= wfull_val;

    assign arempty_val    = (rcnt_sub <= AlmostEmptyClrTh)|((rcnt_sub ==  AlmostEmptyClrTh + 1'b1) & RdEn);
    assign awfull_val = (wcnt_sub >= AlmostFullClrTh) | ((wcnt_sub == AlmostFullClrTh - 1'b1) & WrEn);

    always @(posedge RdClk or posedge RRst) begin
        if (RRst) Almost_Empty <= 1'b1;
        else

           if((arempty_val == 1)&&((rcnt_sub <= AlmostEmptySetTh)|(( rcnt_sub == AlmostEmptySetTh + 1'b1)&RdEn)))
            Almost_Empty <= 1'b1;
        else if (arempty_val == 0) Almost_Empty <= 1'b0;

    end

    always @(posedge WrClk or posedge WRst) begin
        if (WRst) Almost_Full <= 1'b0;
        else

            if((awfull_val == 1)&&((wcnt_sub >= AlmostFullSetTh)|((wcnt_sub == AlmostFullSetTh - 1'b1) & WrEn)))
            Almost_Full <= 1'b1;
        else if (awfull_val == 0) Almost_Full <= 1'b0;

    end

    always @(posedge WrClk or posedge WRst)
        if (WRst) Wnum <= 0;
        else Wnum <= wcnt_sub;


    always @(posedge RdClk or posedge RRst)
        if (RRst) Rnum <= 0;
        else Rnum <= rcnt_sub;

    function [WR_A_SIZE:0] gry2bin;
        input [WR_A_SIZE:0] gry_code;
        integer i;
        begin
            gry2bin[WR_A_SIZE] = gry_code[WR_A_SIZE];
            for (i = WR_A_SIZE - 1; i >= 0; i = i - 1)
            gry2bin[i] = gry2bin[i+1] ^ gry_code[i];
        end
    endfunction
endmodule

/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on WIDTHTRUNC */
