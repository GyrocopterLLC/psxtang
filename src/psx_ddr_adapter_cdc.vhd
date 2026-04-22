library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity psx_ddr_adapter_cdc is
port (
    rstn_i                      : in  std_logic;
    -- psx side
    psx_clk_i                   : in  std_logic;
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
    ddr_clk_i                   : in  std_logic;
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

architecture arch of psx_ddr_adapter_cdc is
    type tPsxAdapterState is (
        IDLE,
        WRITE,
        READ,
        READ_FLUSH
    );
    type tDdrAdapterState is (
        IDLE,
        WRITE,
        READ
    );
-- psx domain signals
    signal psx_adapter_state        : tPsxAdapterState := IDLE;
    signal psx_wr_en                : std_logic := '0'; -- cdc to ddr domain
    signal psx_rd_en                : std_logic := '0'; -- cdc to ddr domain
    signal psx_cmd_complete         : std_logic := '0'; -- cdc from ddr domain
    signal psx_wr_data              : std_logic_vector(127 downto 0) := (others => '0');
    signal psx_addr                 : std_logic_vector(31 downto 0) := (others => '0');
    signal psx_byte_enable          : std_logic_vector(15 downto 0);

    signal first_read_is_odd        : std_logic := '0';
    signal next_fifo_pop_is_odd     : std_logic := '0';
    signal burst_count_cmds_out     : unsigned(7 downto 0) := x"00";
    signal burst_count_reads_in     : unsigned(7 downto 0) := x"00";
    signal read_wait                : std_logic := '0';

    signal read_fifo_rden           : std_logic := '0';
    signal read_fifo_alfull         : std_logic;
    signal read_fifo_empty          : std_logic;
    signal read_fifo_data           : std_logic_vector(127 downto 0);

-- ddr domain signals

    signal ddr_adapter_state        : tDdrAdapterState := IDLE;
    signal ddr_wr_en                : std_logic := '0'; -- cdc from psx domain
    signal ddr_rd_en                : std_logic := '0'; -- cdc from psx domain
    signal ddr_cmd_complete         : std_logic := '0'; -- cdc to psx domain

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

psx_busy_o <= '0' when (psx_adapter_state = IDLE) else '1';

process (psx_clk_i, rstn_i) begin
    if(rstn_i = '0') then
        psx_adapter_state <= IDLE;
        psx_wr_en <= '0';
        psx_rd_en <= '0';
        psx_addr <= (others => '0');
        psx_wr_data <= (others => '0');
        psx_byte_enable <= (others => '0');
        read_wait <= '0';
        first_read_is_odd  <= '0';
        next_fifo_pop_is_odd <= '0';
        read_fifo_rden <= '0';
        burst_count_cmds_out <= (others => '0');
        burst_count_reads_in <= (others => '0');
    else
        if (rising_edge(psx_clk_i)) then
            
            psx_rd_data_valid_o <= '0';
            read_fifo_rden <= '0';
            psx_wr_en <= '0';
            psx_rd_en <= '0';

            case (psx_adapter_state) is
                when IDLE =>
                    if (psx_wr_en_i = '1') then
                        if (psx_addr_i(3) = '0') then
                            -- even address
                            psx_byte_enable(7 downto 0) <= psx_byte_enable_i;
                            psx_byte_enable(15 downto 8) <=  (others => '0');
                            psx_wr_data(63 downto 0) <= psx_wr_data_i;
                        else
                            -- odd address
                            psx_byte_enable(15 downto 8) <= psx_byte_enable_i;
                            psx_byte_enable(7 downto 0) <=  (others => '0');
                            psx_wr_data(127 downto 64) <= psx_wr_data_i;
                        end if;
                        psx_adapter_state <= WRITE;
                        psx_addr <= psx_addr_i(31 downto 4) & "0000";
                        psx_wr_en <= '1';

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
                        psx_adapter_state <= READ;
                        read_wait <= '1';
                        psx_addr <= psx_addr_i(31 downto 4) & "0000";
                        psx_rd_en <= '1';
                    end if;
                when WRITE =>
                    if (psx_cmd_complete = '1') then
                        psx_adapter_state <= IDLE;
                    end if;
                when READ => 

                    -- process read commands out
                    if (read_wait = '1') then
                        if (psx_cmd_complete = '1') then
                            -- a read command was accepted
                            burst_count_cmds_out <= burst_count_cmds_out - 1;
                            if (burst_count_cmds_out > 1) then
                                psx_addr <= std_logic_vector(unsigned(psx_addr) + 16);
                                if (read_fifo_alfull = '0') then
                                    -- only issue read commands if we have room to save them!
                                    psx_rd_en <= '1';
                                    read_wait <= '1';
                                else
                                    psx_rd_en <= '0';
                                    read_wait <= '0';
                                end if;
                            else
                                -- done with commands
                                psx_rd_en <= '0';
                                read_wait <= '0';
                            end if;
                        end if;
                    else
                        -- not currently waiting for a read command to complete
                        -- We could have been stalled on the FIFO full, see if we need
                        -- to issue a command now...
                        if (burst_count_cmds_out > 0) then
                            if (read_fifo_alfull = '0') then
                                psx_rd_en <= '1';
                                read_wait <= '1';
                            else
                                psx_rd_en <= '0';
                                read_wait <= '0';
                            end if;
                        else
                            -- must be done.
                            psx_rd_en <= '0';
                            read_wait <= '0';
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
                        psx_adapter_state <= READ_FLUSH;
                    end if;
                when READ_FLUSH =>
                    if (read_fifo_empty = '0') then
                        read_fifo_rden <= '1';
                    else
                        psx_adapter_state <= IDLE;
                    end if;
            end case;
        end if;
    end if;
end process;


process (ddr_clk_i, rstn_i) begin
    if(rstn_i = '0') then
        ddr_adapter_state <= IDLE;
        ddr_wr_en_o <= '0';
        ddr_rd_en_o <= '0';
        ddr_cmd_complete <= '0';
        ddr_addr_o <= (others => '0');
        ddr_byte_enable_o <= (others => '0');
        ddr_wr_data_o <= (others => '0');
    else
        if(rising_edge(ddr_clk_i)) then
            case (ddr_adapter_state) is
                when IDLE =>
                    ddr_cmd_complete <= '0';

                    if (ddr_wr_en = '1') then
                        ddr_addr_o <= psx_addr;
                        ddr_byte_enable_o <= psx_byte_enable;
                        ddr_wr_data_o <= psx_wr_data;
                        ddr_wr_en_o <= '1';
                        ddr_adapter_state <= WRITE;
                    elsif (ddr_rd_en = '1') then
                        ddr_addr_o <= psx_addr;
                        ddr_rd_en_o <= '1';
                        ddr_adapter_state <= READ;
                    end if;

                when WRITE =>
                    ddr_cmd_complete <= '0';
                    if (ddr_busy_i = '0') then
                        ddr_wr_en_o <= '0';
                        ddr_adapter_state <= IDLE;
                        ddr_cmd_complete <= '1';
                    end if;

                when READ =>
                    ddr_cmd_complete <= '0';
                    if (ddr_busy_i = '0') then
                        ddr_rd_en_o <= '0';
                        ddr_adapter_state <= IDLE;
                        ddr_cmd_complete <= '1';
                    end if;

            end case;
        end if;
    end if;
end process;

icdcpulse_rden : entity work.cdc_pulse
port map (
    rstn        => rstn_i,
    clk_src     => psx_clk_i,
    clk_dest    => ddr_clk_i,
    pulse_src   => psx_wr_en,
    pulse_dest  => ddr_wr_en
);

icdcpulse_wren : entity work.cdc_pulse
port map (
    rstn        => rstn_i,
    clk_src     => psx_clk_i,
    clk_dest    => ddr_clk_i,
    pulse_src   => psx_rd_en,
    pulse_dest  => ddr_rd_en
);

icdcpulse_complete : entity work.cdc_pulse
port map (
    rstn        => rstn_i,
    clk_src     => ddr_clk_i,
    clk_dest    => psx_clk_i,
    pulse_src   => ddr_cmd_complete,
    pulse_dest  => psx_cmd_complete
);


ireadfifo : entity mem.cdc_fifo
generic map (
    RD_D_SIZE           => 128,
    WR_D_SIZE           => 128,
    RD_DEPTH            => 16,
    WR_DEPTH            => 16
)
port map(
    Data                => ddr_rd_data_i,
    WrClk               => ddr_clk_i,
    RdClk               => psx_clk_i,
    WrEn                => ddr_rd_data_valid_i,
    RdEn                => read_fifo_rden,
    Reset               => not rstn_i,
    AlmostEmptySetTh    => to_unsigned(2, 4),
    AlmostEmptyClrTh    => to_unsigned(3, 4),
    AlmostFullSetTh     => to_unsigned(8, 4),
    AlmostFullClrTh     => to_unsigned(7, 4),
    Wnum                => open, 
    Rnum                => open,
    Almost_Empty        => open,
    Almost_Full         => read_fifo_alfull,
    Q                   => read_fifo_data,
    Empty               => read_fifo_empty,
    Full                => open
);

-- ireadfifo : entity mem.SyncFifoFallThrough
-- generic map (
--     SIZE                => 16,
--     DATAWIDTH           => 128,
--     NEARFULLDISTANCE    => 8,
--     NEAREMPTYDISTANCE   => 2
-- )
-- port map (
--     clk             => ddr_clk_i,
--     reset           => not rstn_i,
--     Din             => ddr_rd_data_i,
--     Wr              => ddr_rd_data_valid_i,
--     Full            => open,
--     NearFull        => read_fifo_alfull,
--     Dout            => read_fifo_data,
--     Rd              => read_fifo_rden,
--     Empty           => read_fifo_empty,
--     NearEmpty       => open
-- );

end architecture;