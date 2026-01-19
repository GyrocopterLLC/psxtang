module ahb_to_mem_adapter (
    // Clock and Reset
    input  logic        hclk,
    input  logic        hresetn,
    
    // AHB Slave Interface (64-bit)
    input  logic [31:0] haddr,
    input  logic [2:0]  hsize,
    input  logic [1:0]  htrans,
    input  logic [7:0]  hwstrb,
    input  logic [63:0] hwdata,
    input  logic        hwrite,
    input  logic        hsel,
    input  logic        hready,
    output logic [63:0] hrdata,
    output logic        hreadyout,
    output logic [1:0]  hresp,
    
    // Memory Controller Interface (128-bit)
    input  logic         mem_clk,
    input  logic         mem_resetn,
    
    output logic [31:0]  mem_addr,
    output logic [127:0] mem_wdata,
    output logic [15:0]  mem_byte_en,  // Byte enable mask
    output logic         mem_cmd_en,
    output logic         mem_cmd,    // 1=read, 0=write
    input  logic         mem_cmd_ready,
    input  logic [127:0] mem_rdata,
    input  logic         mem_data_ready
);

    assign hresp = 2'b00;

    // Internal state machine
    typedef enum logic {
        AHB_IDLE = 0,
        WAIT_MEM = 1
    } state_t;

    typedef enum logic [2:0] {
        BYTE = 3'b000,          // 8  bit
        HALFWORD = 3'b001,      // 16 bit
        WORD = 3'b010,          // 32 bit
        DOUBLEWORD = 3'b011,    // 64 bit
        B128_UNUSED = 3'b100,
        B256_UNUSED = 3'b101,
        B512_UNUSED = 3'b110,
        B1024_UNUSED = 3'b111
    } hsize_t;

    function automatic hsize_t size_bits_to_enum(logic [2:0] size_logic);
        hsize_t temp;
        case(size_logic)
        3'b000: temp = BYTE;
        3'b001: temp = HALFWORD;
        3'b010: temp = WORD;
        3'b011: temp = DOUBLEWORD;
        3'b100: temp = B128_UNUSED;
        3'b101: temp = B256_UNUSED;
        3'b110: temp = B512_UNUSED;
        3'b111: temp = B1024_UNUSED;
        endcase
        return temp;
    endfunction
    
    state_t state, next_state;

    assign hreadyout = (state == AHB_IDLE);
    
    // Address phase pipeline registers
    logic [31:0] addr_r;
    logic        write_r;
    logic [2:0]  size_r;
    logic [2:0]  burst_r;
    logic [7:0]  strobe_r;
    logic        valid_transfer;
    
    // Read buffering
    logic [127:0] read_buffer;
    logic         buffer_valid;
    logic [31:4]  buffer_addr;
    logic         read_from_buffer;
    
    // Data accumulation for writes
    logic [63:0] data_r;
    logic [7:0]  byte_en_r;
    logic [127:0] mem_rdata_r;

    // clock crossing signals
    // --- AHB domain ---
    logic        wr_flag; // AHB -> mem
    logic        rd_flag; // AHB -> mem
    logic [1:0]  wr_flag_ack; // mem -> AHB
    logic [1:0]  rd_flag_ack; // mem -> AHB
    logic [1:0]  wr_complete; // mem -> AHB
    logic [1:0]  rd_complete; // mem -> AHB
    logic        wr_complete_r;
    logic        rd_complete_r;
    logic        wr_complete_ack; // AHB -> mem
    logic        rd_complete_ack; // AHB -> mem
    logic        mem_complete;
    // --- mem domain ---
    logic [1:0]  mem_wr_flag; // AHB -> mem
    logic [1:0]  mem_rd_flag; // AHB -> mem
    logic        mem_wr_flag_ack; // mem -> AHB
    logic        mem_rd_flag_ack; // mem -> AHB
    logic        mem_wr_complete; // mem -> AHB
    logic        mem_rd_complete; // mem -> AHB
    logic [1:0]  mem_wr_complete_ack; // AHB -> mem
    logic [1:0]  mem_rd_complete_ack; // AHB -> mem

    // AHB transfer detection
    assign valid_transfer = hsel && htrans[1] && hready;

    // Transaction finished 
    assign mem_complete = (wr_complete[1] && (~wr_complete_r)) || (rd_complete[1] && (~rd_complete_r));
    
    // Rising edge detection for completion signals
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            wr_complete_r <= '0;
            rd_complete_r <= '0;
        end else begin
            wr_complete_r <= wr_complete[1];
            rd_complete_r <= rd_complete[1];
        end
    end

    // State machine
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn)
            state <= AHB_IDLE;
        else
            state <= next_state;
    end
    
    always_comb begin
        next_state = state;
        read_from_buffer = '0;
        
        case (state)
            AHB_IDLE: begin 
                if (valid_transfer) begin
                    if ((~hwrite) && (haddr[31:4] == buffer_addr)) begin
                        read_from_buffer = '1;
                        next_state = AHB_IDLE; // we have the data already in our buffer, simply 
                                           // serve it to hrdata and get ready for the next transaction
                    end
                    else
                        next_state = WAIT_MEM;
                end
            end

            WAIT_MEM: begin
                // take in the write data if a write transaction
                // and wait for write command complete

                // if a read command, wait for read command complete 
                // and serve the data on DATA_PHASE (which is also AHB_IDLE since we could be taking another transaction)
                if (mem_complete) 
                    next_state = AHB_IDLE;
            end

            default: next_state = AHB_IDLE;
        endcase
    end
    
    // Address phase capture
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            addr_r  <= '0;
            write_r <= '0;
            size_r  <= '0;
            strobe_r <= '0;
        end else if (valid_transfer && (state == AHB_IDLE)) begin
            addr_r  <= haddr;
            write_r <= hwrite;
            size_r  <= hsize;
            strobe_r <= hwstrb;
        end
    end

    // Generate byte enable mask based on AHB transfer size and address
    function automatic logic [7:0] generate_byte_enables(logic [2:0] size, logic [2:0] addr_offset);
        logic [7:0] mask;
        case (size)
            3'b000: begin // Byte
                mask = 8'b00000001 << addr_offset;
            end
            3'b001: begin // Halfword (2 bytes)
                mask = 8'b00000011 << addr_offset;
            end
            3'b010: begin // Word (4 bytes)
                mask = 8'b00001111 << addr_offset;
            end
            3'b011: begin // Doubleword (8 bytes)
                mask = 8'b11111111;
            end
            default: mask = 8'b11111111;
        endcase
        return mask;
    endfunction

    // Data phase capture
    always_ff @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            data_r <= '0;
            byte_en_r <= '0;
        end else begin
            if (state == WAIT_MEM) begin

                // --- ??? ---
                // maybe only latch it one time at the beginning of this state?
                data_r <= hwdata;
                byte_en_r <= hwstrb & generate_byte_enables(size_r, addr_r[2:0]);
            end
        end
    end

    // trigger commands, transferred to ddr clock domain
    // -- write trigger
    always_ff @(posedge hclk or negedge hresetn) begin
        if(!hresetn) begin
            wr_flag <= '0;
        end else begin
            // reset flags when write is acknowledged in ddr clock domain
            if(wr_flag && wr_flag_ack[1]) begin
                wr_flag <= '0; // reset
            end
            if((state == AHB_IDLE) && (next_state == WAIT_MEM) && hwrite) begin
                wr_flag <= '1;
            end
        end
    end
    // -- read trigger
    always_ff @(posedge hclk or negedge hresetn) begin
        if(!hresetn) begin
            rd_flag <= '0;
        end else begin
            // reset flags when write is acknowledged in ddr clock domain
            if(rd_flag && rd_flag_ack[1]) begin
                rd_flag <= '0; // reset
            end
            if((state == AHB_IDLE) && (next_state == WAIT_MEM) && (~hwrite)) begin
                rd_flag <= '1;
            end
        end
    end

    // read data complete: save to buffer and deliver data to bus
    always_ff @(posedge hclk or negedge hresetn) begin
        if(!hresetn) begin
            hrdata <= '0;
            read_buffer <= '0;
            buffer_valid <= '0;
            buffer_addr <= '0;
        end else begin
            if(rd_complete[1] && (~rd_complete_r)) begin
                hrdata <= addr_r[3] ? mem_rdata_r[127:64] : mem_rdata_r[63:0];
                read_buffer <= mem_rdata_r;
                buffer_valid <= '1;
                buffer_addr <= addr_r[31:4];
            end

            // if we're doing a quick serve, move the buffer data to hrdata here
            if(read_from_buffer) begin
                hrdata <= haddr[3] ? read_buffer[127:64] : read_buffer[63:0];
            end
        end
    end

    // clock crossing
    // --- AHB domain ---
    assign wr_complete_ack = wr_complete[1];
    assign rd_complete_ack = rd_complete[1];

    always_ff @(posedge hclk or negedge hresetn) begin
        if(!hresetn) begin
            wr_flag_ack <= '0;
            rd_flag_ack <= '0;
            wr_complete <= '0;
            rd_complete <= '0;
        end else begin
            wr_flag_ack <= {wr_flag_ack[0], mem_wr_flag_ack};
            rd_flag_ack <= {rd_flag_ack[0], mem_rd_flag_ack};
            wr_complete <= {wr_complete[0], mem_wr_complete};
            rd_complete <= {rd_complete[0], mem_rd_complete};
        end
    end

    // --- mem domain ---
    assign mem_wr_flag_ack = mem_wr_flag[1];
    assign mem_rd_flag_ack = mem_rd_flag[1];

    always_ff @(posedge mem_clk or negedge mem_resetn) begin
        if(!mem_resetn) begin
            mem_wr_flag <= '0;
            mem_rd_flag <= '0;
            mem_wr_complete_ack <= '0;
            mem_rd_complete_ack <= '0;
        end else begin
            mem_wr_flag <= {mem_wr_flag[0], wr_flag};
            mem_rd_flag <= {mem_rd_flag[0], rd_flag};
            mem_wr_complete_ack <= {mem_wr_complete_ack[0], wr_complete_ack};
            mem_rd_complete_ack <= {mem_rd_complete_ack[0], rd_complete_ack};
        end
    end

    // mem controller state machine
    typedef enum logic [2:0] {
        MEM_IDLE = 0,
        WAIT_WRITE_CMD = 1,
        WRITE_COMPLETE = 2,
        WAIT_READ_CMD = 3,
        WAIT_READ_DATA = 4,
        READ_COMPLETE = 5
    } memc_state_t;

    memc_state_t mem_state, next_mem_state;

    assign mem_wr_complete = mem_state == WRITE_COMPLETE;
    assign mem_rd_complete = mem_state == READ_COMPLETE;

    logic mem_wr_flag_r;
    logic mem_rd_flag_r;

    logic mem_wr_start;
    logic mem_rd_start;

    assign mem_wr_start = mem_wr_flag[1] && (!mem_wr_flag_r);
    assign mem_rd_start = mem_rd_flag[1] && (!mem_rd_flag_r);

    logic mem_wr_start_r;
    logic mem_rd_start_r;

    always_comb begin
        next_mem_state = mem_state;
        
        
        case(mem_state)
        MEM_IDLE: begin
            if (mem_wr_start || mem_wr_start_r)
                next_mem_state = WAIT_WRITE_CMD;
            else if (mem_rd_start || mem_rd_start_r)
                next_mem_state = WAIT_READ_CMD;
        end

        WAIT_WRITE_CMD: begin
            if(mem_cmd_ready)
                next_mem_state = WRITE_COMPLETE;
        end

        WRITE_COMPLETE: begin
            if(mem_wr_complete_ack[1])
                next_mem_state = MEM_IDLE;
        end

        WAIT_READ_CMD: begin
            if(mem_cmd_ready)
                next_mem_state = WAIT_READ_DATA;
        end
        WAIT_READ_DATA: begin
            if(mem_data_ready)
                next_mem_state = READ_COMPLETE;
        end
        READ_COMPLETE: begin
            if(mem_rd_complete_ack[1])
                next_mem_state = MEM_IDLE;
        end

        default: next_mem_state = MEM_IDLE;
        endcase
    end


    always_ff @(posedge mem_clk or negedge mem_resetn) begin
        if(!mem_resetn) begin
            mem_addr <= '0;
            mem_wdata <= '0;
            mem_byte_en <= '0;
            mem_cmd_en <= '0;
            mem_cmd <= '0;
            mem_state <= MEM_IDLE;
            mem_wr_start_r <= '0;
            mem_rd_start_r <= '0;
            mem_wr_flag_r <= '0;
            mem_rd_flag_r <= '0;
        end else begin
            mem_state <= next_mem_state;
            mem_cmd_en <= '0;

            mem_wr_flag_r <= mem_wr_flag[1];
            mem_rd_flag_r <= mem_rd_flag[1];

            if (mem_wr_flag[1] && (!mem_wr_flag_r))
                mem_wr_start_r <= '1;
            if (mem_rd_flag[1] && (!mem_rd_flag_r))
                mem_rd_start_r <= '1;

            case(mem_state)
            WAIT_WRITE_CMD: begin
                mem_wr_start_r <= '0;
                if(mem_cmd_ready) begin
                    mem_addr <= {addr_r[31:4], 4'h0};
                    mem_wdata <= addr_r[3] ? {data_r, 64'b0} : {64'b0, data_r};
                    mem_byte_en <= addr_r[3] ? {byte_en_r, 8'b0} : {8'b0, byte_en_r};
                    mem_cmd <= '0;
                    mem_cmd_en <= '1;
                end
            end
            WAIT_READ_CMD: begin
                mem_rd_start_r <= '0;
                if(mem_cmd_ready) begin
                    mem_addr <= {addr_r[31:4], 4'h0};
                    mem_cmd <= '1;
                    mem_cmd_en <= '1;
                end
            end
            WAIT_READ_DATA: begin
                if(mem_data_ready) begin
                    mem_rdata_r <= mem_rdata;
                end
            end

            default: begin end
            endcase

        end
    end

endmodule
