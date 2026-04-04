library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity psx_ddr_adapter is
port (
    rstn_i                      : in  std_logic;
    ddr_clk_i                   : in  std_logic;
    -- psx side
    psx_busy_o                  : out std_logic := '0';
    psx_wr_en_i                 : in  std_logic;
    psx_rd_en_i                 : in  std_logic;
    psx_addr_i                  : in  std_logic_vector(31 downto 0);
    psx_burstcnt_i              : in  std_logic_vector(7 downto 0);
    psx_byte_enable_i           : in  std_logic_vector(7 downto 0);
    psx_wr_data_i               : in  std_logic_vector(63 downto 0);
    psx_rd_data_o               : out std_logic_vector(63 downto 0);
    psx_rd_data_valid_o         : out std_logic := '0';
    -- ddr side
    ddr_busy_i                  : in  std_logic;
    ddr_wr_en_o                 : out std_logic := '0';
    ddr_rd_en_o                 : out std_logic := '0';
    ddr_addr_o                  : out std_logic_vector(31 downto 0);
    ddr_byte_enable_o           : out std_logic_vector(15 downto 0);
    ddr_wr_data_o               : out std_logic_vector(127 downto 0);
    ddr_rd_data_i               : in  std_logic_vector(127 downto 0);
    ddr_rd_data_valid_i         : in  std_logic
);
end entity;

architecture arch of psx_ddr_adapter is
    type tAdapterState is (
        IDLE,
        WRITE,
        READ,
        READ_FLUSH
    );
    signal adapter_state        : tAdapterState := IDLE;

    signal first_read_is_odd    : std_logic := '0';
    signal next_fifo_pop_is_odd : std_logic := '0';
    signal burst_count_cmds_out : unsigned(7 downto 0) := x"00";
    signal burst_count_reads_in : unsigned(7 downto 0) := x"00";

    signal read_fifo_rden           : std_logic := '0';
    signal read_fifo_alfull         : std_logic;
    signal read_fifo_empty          : std_logic;
    signal read_fifo_data           : std_logic_vector(127 downto 0);
begin

    -- for a read:
    --  - check if first address is odd. special case on the read if that happens
    --  - begin issuing read requests with incrementing addresses on 128-bit boundaries (16 bytes)
    --  - each read valid received from ddr will result in two read valids to PSX (except if first address is odd, or last address is even)
    --  - hold busy out until burst is done

    -- for a write:
    --  - there are no burst writes. every ddr source in PSX uses burstcnt = 1 for writes
    --  - assign the correct byte enable for upper or lower 8 bytes based on address bit 4
    --  - and set the corresponding side of the write data

    psx_busy_o <= '0' when (adapter_state = IDLE) else '1';

    process (ddr_clk_i, rstn_i) begin
        if(rstn_i = '0') then
            adapter_state        <= IDLE;
            ddr_wr_en_o <= '0';
            ddr_rd_en_o <= '0';
            ddr_addr_o <= (others => '0');
            ddr_wr_data_o <= (others => '0');
            first_read_is_odd  <= '0';
            next_fifo_pop_is_odd <= '0';
            read_fifo_rden <= '0';
            burst_count_cmds_out <= (others => '0');
            burst_count_reads_in <= (others => '0');
        else
            if (rising_edge(ddr_clk_i)) then
                
                psx_rd_data_valid_o <= '0';
                read_fifo_rden <= '0';

                case (adapter_state) is
                    when IDLE =>
                        if (psx_wr_en_i = '1') then
                            if (psx_addr_i(3) = '0') then
                                -- even address
                                ddr_byte_enable_o(7 downto 0) <= psx_byte_enable_i;
                                ddr_byte_enable_o(15 downto 8) <=  (others => '0');
                                ddr_wr_data_o(63 downto 0) <= psx_wr_data_i;
                            else
                                -- odd address
                                ddr_byte_enable_o(15 downto 8) <= psx_byte_enable_i;
                                ddr_byte_enable_o(7 downto 0) <=  (others => '0');
                                ddr_wr_data_o(127 downto 64) <= psx_wr_data_i;
                            end if;
                            adapter_state <= WRITE;
                            ddr_addr_o <= psx_addr_i(31 downto 4) & "0000";
                            ddr_wr_en_o <= '1';

                        elsif (psx_rd_en_i = '1') then
                            if ((psx_burstcnt_i(0) = '1') or (psx_addr_i(3) = '1')) then
                                -- add an extra read if we have an odd address, odd count, or both
                                burst_count_cmds_out <= unsigned(psx_burstcnt_i)/2 + 1;
                            else
                                burst_count_cmds_out <= unsigned(psx_burstcnt_i)/2;
                            end if;
                            burst_count_reads_in <= unsigned(psx_burstcnt_i);
                            first_read_is_odd <= psx_addr_i(3);
                            next_fifo_pop_is_odd <= '0';
                            adapter_state <= READ;
                            ddr_addr_o <= psx_addr_i(31 downto 4) & "0000";
                            ddr_rd_en_o <= '1';
                        end if;
                    when WRITE =>
                        if (ddr_busy_i = '0') then
                            ddr_wr_en_o <= '0';
                            adapter_state <= IDLE;
                        end if;
                    when READ => 
                        -- process read commands out
                        if ((ddr_busy_i = '0') and (ddr_rd_en_o = '1')) then
                            -- a read command was accepted
                            burst_count_cmds_out <= burst_count_cmds_out - 1;
                            if (burst_count_cmds_out > 1) then
                                ddr_addr_o <= std_logic_vector(unsigned(ddr_addr_o) + 16);
                                if (read_fifo_alfull = '0') then
                                    -- only issue read commands if we have room to save them!
                                    ddr_rd_en_o <= '1';
                                else
                                    ddr_rd_en_o <= '0';
                                end if;
                            else
                                -- finished with read commands
                                ddr_rd_en_o <= '0';
                            end if;
                        else
                            -- did not just finish a read command, either because it was busy
                            -- or we were stalled for read fifo to empty
                            -- or we've already finished sending

                            -- check if we are waiting for the fifo to empty out
                            if (burst_count_cmds_out > 0) then
                                if (read_fifo_alfull = '0') then
                                    -- only issue read commands if we have room to save them!
                                    ddr_rd_en_o <= '1';
                                else
                                    ddr_rd_en_o <= '0';
                                end if;
                            end if;
                        end if;

                        -- process read valids in
                        if (burst_count_reads_in > 0) then
                            if(next_fifo_pop_is_odd = '1') then
                                psx_rd_data_o <= read_fifo_data(127 downto 64);
                                psx_rd_data_valid_o <= '1';
                                burst_count_reads_in <= burst_count_reads_in - 1;
                                next_fifo_pop_is_odd <= '0';
                            else
                                if (read_fifo_empty = '0') then
                                    read_fifo_rden <= '1';
                                    next_fifo_pop_is_odd <= '1';
                                    psx_rd_data_o <= read_fifo_data(63 downto 0);
                                    if (first_read_is_odd = '1') then
                                        psx_rd_data_valid_o <= '0'; -- skip the first read data
                                        first_read_is_odd <= '0';
                                    else
                                        psx_rd_data_valid_o <= '1';
                                        burst_count_reads_in <= burst_count_reads_in - 1;
                                    end if;
                                end if;
                            end if;
                        else
                            adapter_state <= READ_FLUSH;
                        end if;
                    when READ_FLUSH =>
                        if (read_fifo_empty = '0') then
                            read_fifo_rden <= '1';
                        else
                            adapter_state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

ireadfifo : entity mem.SyncFifoFallThrough
generic map (
    SIZE                => 16,
    DATAWIDTH           => 128,
    NEARFULLDISTANCE    => 8,
    NEAREMPTYDISTANCE   => 2
)
port map (
    clk             => ddr_clk_i,
    reset           => not rstn_i,
    Din             => ddr_rd_data_i,
    Wr              => ddr_rd_data_valid_i,
    Full            => open,
    NearFull        => read_fifo_alfull,
    Dout            => read_fifo_data,
    Rd              => read_fifo_rden,
    Empty           => read_fifo_empty,
    NearEmpty       => open
);

end architecture;