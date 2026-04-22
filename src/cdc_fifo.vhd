library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use ieee.math_real.all;   

entity cdc_fifo is
generic(
    
    RD_D_SIZE : integer := 32;
    WR_D_SIZE : integer := 32;
    RD_DEPTH  : integer := 512;
    WR_DEPTH  : integer := 512;
    RD_A_SIZE : integer := integer(ceil(log2(real(RD_DEPTH))));
    WR_A_SIZE : integer := integer(ceil(log2(real(WR_DEPTH))))
);

port(
    Data                : in  std_logic_vector(WR_D_SIZE-1 downto 0); -- Data to write into the FIFO
    WrClk               : in  std_logic;
    RdClk               : in  std_logic;
    WrEn                : in  std_logic;
    RdEn                : in  std_logic;

    Reset               : in  std_logic; 

    AlmostEmptySetTh    : in  unsigned(RD_A_SIZE-1 downto 0); -- Dynamic input threshold of almost empty set to 1
    AlmostEmptyClrTh    : in  unsigned(RD_A_SIZE-1 downto 0); -- Dynamic input threshold of almost empty set to 0

    AlmostFullSetTh     : in  unsigned(WR_A_SIZE-1 downto 0); -- Dynamic input threshold of almost full set to 1
    AlmostFullClrTh     : in  unsigned(WR_A_SIZE-1 downto 0); -- Dynamic input threshold of almost full set to 0

    Wnum                : out unsigned(WR_A_SIZE downto 0); -- Write data count: synchronized to WrClk,
    Rnum                : out unsigned(RD_A_SIZE downto 0); -- Read data count: synchronized to RdCLK,

    Almost_Empty        : out std_logic;
    Almost_Full         : out std_logic;

    Q                   : out std_logic_vector(RD_D_SIZE-1 downto 0); -- Data read from the fifo
    Empty               : out std_logic;
    Full                : out std_logic

);
end entity;

architecture arch of cdc_fifo is

    signal rbin_num         : std_logic_vector(RD_A_SIZE downto 0); -- Read pointer : binary
    -- (note: 1-bit bigger than raddr_num in order to obtain the right flag signal)
    signal raddr_num        : std_logic_vector(RD_A_SIZE-1 downto 0); -- Read address
    signal rbin_num_next    : std_logic_vector(RD_A_SIZE downto 0);
    signal rcnt_sub         : std_logic_vector(RD_A_SIZE downto 0); -- Read data count
    signal waddr            : std_logic_vector(WR_A_SIZE-1 downto 0);  -- Write address
    signal rempty_val       : std_logic;
    signal wfull_val        : std_logic;
    signal arempty_val      : std_logic;
    signal awfull_val       : std_logic;
    signal wcnt_sub         : std_logic_vector(WR_A_SIZE downto 0); -- Write data count
    signal WRst             : std_logic;
    signal RRst             : std_logic;

    signal reset_r          : std_logic_vector(1 downto 0);
    signal reset_w          : std_logic_vector(1 downto 0);

    function gry2bin(
        gry_code : in std_logic_vector(WR_A_SIZE downto 0))
        return std_logic_vector is
        variable gb_temp : std_logic_vector(WR_A_SIZE downto 0);
        begin
            gb_temp(WR_A_SIZE) := gry_code(WR_A_SIZE);
            for i in WR_A_SIZE-1 downto 0 loop
                gb_temp(i) := gb_temp(i+1) xor gry_code(i);
            end loop;
        return gb_temp;
    end function;

    function gry2bin_big(
        gry_code : in std_logic_vector(RD_A_SIZE downto 0))
        return std_logic_vector is
        variable gb_temp : std_logic_vector(RD_A_SIZE downto 0);
        begin
            gb_temp(RD_A_SIZE) := gry_code(RD_A_SIZE);
            for i in RD_A_SIZE-1 downto 0 loop
                gb_temp(i) := gb_temp(i+1) xor gry_code(i);
            end loop;
        return gb_temp;
    end function;

begin

    process(RdClk, Reset) begin
        if (Reset = '1') then
            reset_r <= "11";
        else
            if (rising_edge(RdClk)) then
                reset_r <= reset_r(0) & '0';
            end if;
        end if;
    end process;
    RRst <= reset_r(1);

    process(WrClk, Reset) begin
        if (Reset = '1') then
            reset_w <= "11";
        else
            if (rising_edge(WrClk)) then
                reset_w <= reset_w(0) & '0';
            end if;
        end if;
    end process;
    WRst <= reset_w(1);

    process(RdClk, RRst) begin
        if (RRst = '1') then
            rbin_num <= (others => '0');
        else
            if(rising_edge(RdClk)) then
                rbin_num <= rbin_num_next;
            end if;
        end if;
    end process;

    -- The read and write logic for differnt depth

    Small : if (WR_DEPTH < RD_DEPTH) generate
        constant a : integer := RD_DEPTH / WR_DEPTH;

        type memory_array is array (0 to WR_DEPTH-1) of std_logic_vector(WR_D_SIZE-1 downto 0);
        signal mem                  : memory_array := (others => (others => '0'));
            attribute syn_ramstyle:string;
            attribute syn_ramstyle of mem: signal is "block_ram";

        signal wdata                : std_logic_vector(WR_D_SIZE-1 downto 0); -- Data from the fifo
        signal wptr                 : std_logic_vector(WR_A_SIZE downto 0);  -- Write pointer
        signal rptr                 : std_logic_vector(WR_A_SIZE downto 0);  -- Read  pointer
        signal wq2_rptr             : std_logic_vector(WR_A_SIZE downto 0);  -- Read  pointer synchronized to WrClk
        signal rq2_wptr             : std_logic_vector(WR_A_SIZE downto 0);  -- Write pointer synchronized to RdCkl
        signal wq1_rptr             : std_logic_vector(WR_A_SIZE downto 0);
        signal rq1_wptr             : std_logic_vector(WR_A_SIZE downto 0);
        signal wbin                 : std_logic_vector(WR_A_SIZE downto 0);  -- Write pointer: binary

        signal wcount_r_1           : std_logic_vector(RD_A_SIZE downto 0);
        signal rgraynext            : std_logic_vector(WR_A_SIZE downto 0);  -- Read pointer: gray code
        signal rbinnext             : std_logic_vector(WR_A_SIZE downto 0);
        -- signal rbinnext_unsigned    : integer;
        signal rbinnext_1           : std_logic_vector(WR_A_SIZE downto 0);
        signal wgraynext            : std_logic_vector(WR_A_SIZE downto 0);
        signal wcount_r             : std_logic_vector(WR_A_SIZE downto 0);
        signal rcount_w             : std_logic_vector(WR_A_SIZE downto 0);
        signal wbinnext             : std_logic_vector(WR_A_SIZE downto 0);
        signal wdata_q              : std_logic_vector(RD_D_SIZE-1 downto 0);
    begin

        process(WrClk) begin
            -- Write data into fifo
            if(rising_edge(WrClk)) then
                if(WrEn = '1' and Full = '0') then
                    mem(to_integer(unsigned(waddr))) <= Data;
                end if;
            end if;
        end process;

        process(RdClk, RRst) begin
            -- Read data from fifo
            if (RRst = '1') then
                wdata <= (others => '0');
            elsif (rising_edge(RdClk)) then
                wdata <= mem(to_integer(unsigned(raddr_num)/a));
            end if;
        end process;

        wdata_q <= 
            wdata( (((to_integer(unsigned(raddr_num)-1) mod a + 1)) * RD_D_SIZE - 1) downto (((to_integer(unsigned(raddr_num)-1) mod a + 1)) * RD_D_SIZE - RD_D_SIZE) ) 
            when RdEn = '1' else
            wdata( (((to_integer(unsigned(raddr_num)) mod a + 1)) * RD_D_SIZE - 1) downto (((to_integer(unsigned(raddr_num)) mod a + 1)) * RD_D_SIZE - RD_D_SIZE) );
        
        Q <= wdata_q;

        raddr_num <= rbin_num_next(RD_A_SIZE-1 downto 0); -- Read address
        rbin_num_next <= std_logic_vector(unsigned(rbin_num) + 1) when (RdEn = '1' and Empty = '0') else rbin_num; -- Obtain the next read pointer
        
        -- assign rbinnext=  rbin_num_next[RD_A_SIZE:0]/a;   // Read address transform because the different depth
        process(all) 
            variable rbinnext_int : integer;
        begin
            rbinnext_int := to_integer(unsigned(rbin_num_next(RD_A_SIZE downto 0))) / a;
            if rbinnext_int /= 0 then
                rbinnext <= std_logic_vector(to_unsigned(rbinnext_int, WR_A_SIZE + 1));
            else
                rbinnext <= (others => '0');
            end if;
        end process;

        -- assign rbinnext_1 = rbin_num / a;
        process(all)
            variable rbinnext_1_int : integer;
        begin
            rbinnext_1_int := to_integer(unsigned(rbin_num)) / a;
            if rbinnext_1_int /= 0 then
                rbinnext_1 <= std_logic_vector(to_unsigned(rbinnext_1_int, WR_A_SIZE + 1));
            else
                rbinnext_1 <= (others => '0');
            end if;
        end process;

        rgraynext <= std_logic_vector(shift_right(unsigned(rbinnext), 1)) xor rbinnext; -- Gray code transform
        rempty_val <= '1' when (rgraynext = rq2_wptr) else '0'; -- Determine empty
        wcount_r <= gry2bin(rq2_wptr);
        wcount_r_1 <= std_logic_vector(to_unsigned(to_integer(unsigned(gry2bin(rq2_wptr))) * a, RD_A_SIZE + 1)); -- Write address transform
        rcnt_sub <= std_logic_vector(
            unsigned(wcount_r(WR_A_SIZE) xor rbinnext_1(WR_A_SIZE) & wcount_r_1(RD_A_SIZE-1 downto 0))
            - unsigned('0' & rbin_num(RD_A_SIZE-1 downto 0))
        );
        waddr <= wbin(WR_A_SIZE-1 downto 0); -- Write address
        wbinnext <= std_logic_vector(unsigned(wbin) + 1) when (WrEn = '1' and Full = '0') else wbin;
        wgraynext <= std_logic_vector(shift_right(unsigned(wbinnext), 1)) xor wbinnext; -- Gray code transform
        ac: if (WR_A_SIZE = 1) generate
            wfull_val <= '1' when (wgraynext = (not wq2_rptr(WR_A_SIZE downto WR_A_SIZE-1))) else '0';
        else generate
            wfull_val <= '1' when (wgraynext = ((not wq2_rptr(WR_A_SIZE downto WR_A_SIZE-1)) & wq2_rptr(WR_A_SIZE-2 downto 0))) else '0';
        end generate;

        rcount_w <= gry2bin(wq2_rptr); -- Transform to binary
        wcnt_sub <= std_logic_vector(
            unsigned(rcount_w(WR_A_SIZE) xor wbin(WR_A_SIZE) & wbin(WR_A_SIZE-1 downto 0))
            - unsigned('0' & rcount_w(WR_A_SIZE-1 downto 0))
        );
        -- pointer synchronization
        process(WrClk, WRst) begin
            if (WRst = '1') then
                wq2_rptr <= (others => '0');
                wq1_rptr <= (others => '0');
            elsif (rising_edge(WrClk)) then
                wq2_rptr <= wq1_rptr;
                wq1_rptr <= rptr;
            end if;
        end process;

        process(RdClk, RRst) begin
            if (RRst = '1') then
                rq2_wptr <= (others => '0');
                rq1_wptr <= (others => '0');
            elsif (rising_edge(RdClk)) then
                rq2_wptr <= rq1_wptr;
                rq1_wptr <= wptr;
            end if;
        end process;

        process(RdClk, RRst) begin
            if(RRst = '1') then
                rptr <= (others => '0');
            elsif (rising_edge(RdClk)) then
                rptr <= rgraynext;
            end if;
        end process;

        process(WrClk, WRst) begin
            if(WRst = '1') then
                wbin <= (others => '0');
                wptr <= (others => '0');
            elsif (rising_edge(WrClk)) then
                wbin <= wbinnext;
                wptr <= wgraynext;
            end if;
        end process;
    end generate;

    -- WR_DEPTH > RD_DEPTH, variableas are similar to that when WR_DEPTH < RD_DEPTH
    Big : if (WR_DEPTH > RD_DEPTH) generate
        constant b : integer := WR_DEPTH / RD_DEPTH;
        type memory_array is array (0 to WR_DEPTH-1) of std_logic_vector(WR_D_SIZE-1 downto 0);
        signal mem                  : memory_array := (others => (others => '0'));
            attribute syn_ramstyle:string;
            attribute syn_ramstyle of mem: signal is "block_ram";
        signal wdata_q              : std_logic_vector(RD_D_SIZE-1 downto 0) := (others => '0');
        signal wptr                 : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal rptr                 : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal wq2_rptr             : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal rq2_wptr             : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal wq1_rptr             : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal rq1_wptr             : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal wbin                 : std_logic_vector(WR_A_SIZE downto 0) := (others => '0');
        signal rgraynext            : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal wgraynext            : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal wcount_r             : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal rcount_w             : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal rcount_w_1           : std_logic_vector(WR_A_SIZE downto 0) := (others => '0');
        signal wbin_num_next        : std_logic_vector(WR_A_SIZE downto 0) := (others => '0');
        signal wbinnext             : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
        signal wbinnext_1           : std_logic_vector(RD_A_SIZE downto 0) := (others => '0');
    begin

        process(WrClk) begin
            if(rising_edge(WrClk)) then
                if(WrEn = '1' and Full = '0') then
                    mem(to_integer(unsigned(waddr))) <= Data;
                end if;
            end if;
        end process;

        process(RdClk, RRst) begin
            if(RRst = '1') then
                wdata_q <= (others => '0');
            elsif (rising_edge(RdClk)) then
                if((RdEn = '1' and rempty_val = '0') or (RdEn = '0' and (Empty = '1' and rempty_val = '0'))) then
                    for j in 0 to b-1 loop
                        wdata_q( ((j+1)*WR_D_SIZE-1) downto (j*WR_D_SIZE) ) <= mem(to_integer(unsigned(raddr_num))*b + j);
                    end loop;
                end if;
            end if;
        end process;

        Q <= wdata_q;
        raddr_num <= rbin_num_next(RD_A_SIZE-1 downto 0);
        rbin_num_next <= std_logic_vector(unsigned(rbin_num)+1) when (RdEn = '1' and Empty = '0') else rbin_num;
        rgraynext <= std_logic_vector(shift_right(unsigned(rbin_num_next), 1)) xor rbin_num_next;
        rempty_val <= '1' when (rgraynext = rq2_wptr) else '0';
        wcount_r <= gry2bin_big(rq2_wptr);
        rcnt_sub <= std_logic_vector(
            unsigned((wcount_r(RD_A_SIZE) xor rbin_num(RD_A_SIZE)) & wcount_r(RD_A_SIZE-1 downto 0))
            - unsigned('0' & rbin_num(RD_A_SIZE-1 downto 0))
        );
        waddr <= wbin(WR_A_SIZE-1 downto 0);
        wbin_num_next <= std_logic_vector(unsigned(wbin) + 1) when (WrEn = '1' and Full = '0') else wbin;
        wbinnext <= std_logic_vector(to_unsigned(to_integer(unsigned(wbin_num_next)) / b, RD_A_SIZE+1));  --write to read
        wbinnext_1 <= std_logic_vector(to_unsigned(to_integer(unsigned(wbin)) / b, RD_A_SIZE+1));
        wgraynext <= std_logic_vector(shift_right(unsigned(wbinnext), 1)) xor wbinnext;

        ae : if(RD_A_SIZE = 1) generate
            wfull_val <= '1' when (wgraynext = (not wq2_rptr(RD_A_SIZE downto RD_A_SIZE-1))) else '0';
        else generate
            wfull_val <= '1' when (wgraynext = ((not wq2_rptr(RD_A_SIZE downto RD_A_SIZE-1)) & wq2_rptr(RD_A_SIZE-2 downto 0))) else '0';
        end generate;

        rcount_w <= gry2bin_big(wq2_rptr);
        rcount_w_1 <= std_logic_vector(to_unsigned(to_integer(unsigned(gry2bin_big(wq2_rptr))) * b, WR_A_SIZE + 1));
        wcnt_sub <= std_logic_vector(
            unsigned(rcount_w(RD_A_SIZE) xor wbinnext_1(RD_A_SIZE) & wbin(WR_A_SIZE-1 downto 0))
            - unsigned('0' & rcount_w_1(WR_A_SIZE-1 downto 0))
        );

        process(WrClk, WRst) begin
            if(WRst = '1') then
                wq2_rptr <= (others => '0');
                wq1_rptr <= (others => '0');
            elsif rising_edge(WrClk) then
                wq2_rptr <= wq1_rptr;
                wq1_rptr <= rptr;
            end if;
        end process;

        process(RdClk, RRst) begin
            if(RRst = '1') then
                rq2_wptr <= (others => '0');
                rq1_wptr <= (others => '0');
            elsif rising_edge(RdClk) then
                rq2_wptr <= rq1_wptr;
                rq1_wptr <= wptr;
            end if;
        end process;

        process(RdClk, RRst) begin
            if(RRst = '1') then
                rptr <= (others => '0');
            elsif rising_edge(RdClk) then
                rptr <= rgraynext;
            end if;
        end process;

        process(WrClk, WRst) begin
            if(WRst = '1') then
                wbin <= (others => '0');
                wptr <= (others => '0');
            elsif rising_edge(WrClk) then
                wbin <= wbin_num_next;
                wptr <= wgraynext;
            end if;
        end process;

    end generate;
    
    Equal : if(WR_DEPTH = RD_DEPTH) generate
        type memory_array is array (0 to WR_DEPTH-1) of std_logic_vector(WR_D_SIZE-1 downto 0);
        signal mem                  : memory_array := (others => (others => '0'));
            attribute syn_ramstyle:string;
            attribute syn_ramstyle of mem: signal is "block_ram";

        signal wdata_q              : std_logic_vector(WR_D_SIZE-1 downto 0);

        signal wptr                 : std_logic_vector(WR_A_SIZE downto 0);
        signal rptr                 : std_logic_vector(WR_A_SIZE downto 0);
        signal wq2_rptr             : std_logic_vector(WR_A_SIZE downto 0);
        signal rq2_wptr             : std_logic_vector(WR_A_SIZE downto 0);
        signal wq1_rptr             : std_logic_vector(WR_A_SIZE downto 0);
        signal rq1_wptr             : std_logic_vector(WR_A_SIZE downto 0);

        signal wbin                 : std_logic_vector(WR_A_SIZE downto 0);
        signal rgraynext            : std_logic_vector(WR_A_SIZE downto 0);
        signal wgraynext            : std_logic_vector(WR_A_SIZE downto 0);
        signal wcount_r             : std_logic_vector(WR_A_SIZE downto 0);
        signal rcount_w             : std_logic_vector(WR_A_SIZE downto 0);
        signal wbinnext             : std_logic_vector(WR_A_SIZE downto 0);

    begin

        process(WrClk) begin
            if rising_edge(WrClk) then
                if(WrEn = '1' and Full = '0') then
                    mem(to_integer(unsigned(waddr))) <= Data;
                end if;
            end if;
        end process;

        process(RdClk, RRst) begin
            if(RRst = '1') then
                wdata_q <= (others => '0');
            elsif rising_edge(RdClk) then
                if((RdEn = '1' and rempty_val = '0') or (RdEn = '0' and (Empty = '1' and rempty_val = '0'))) then
                    wdata_q <= mem(to_integer(unsigned(raddr_num)));
                end if;
            end if;
        end process;

        Q <= wdata_q;

        raddr_num <= rbin_num_next(WR_A_SIZE-1 downto 0);

        rbin_num_next <= std_logic_vector(unsigned(rbin_num) + 1) when (RdEn = '1' and Empty = '0') else rbin_num;
        rgraynext <= std_logic_vector(shift_right(unsigned(rbin_num_next), 1)) xor rbin_num_next;
        rempty_val <= '1' when (rgraynext = rq2_wptr) else '0';
        wcount_r <= gry2bin(rq2_wptr);
        rcnt_sub <= std_logic_vector(
            unsigned((wcount_r(WR_A_SIZE) xor rbin_num(RD_A_SIZE)) & wcount_r(WR_A_SIZE-1 downto 0))
            - unsigned('0' & rbin_num(RD_A_SIZE-1 downto 0))
        );
        waddr <= wbin(WR_A_SIZE-1 downto 0);
        wbinnext <= std_logic_vector(unsigned(wbin) + 1) when (WrEn = '1' and Full = '0') else wbin;
        wgraynext <= std_logic_vector(shift_right(unsigned(wbinnext), 1)) xor wbinnext;

        ag : if (WR_A_SIZE = 1) generate
            wfull_val <= '1' when (wgraynext = (not wq2_rptr(WR_A_SIZE downto WR_A_SIZE-1))) else '0';
        else generate
            wfull_val <= '1' when (wgraynext = ((not wq2_rptr(WR_A_SIZE downto WR_A_SIZE-1)) & wq2_rptr(WR_A_SIZE-2 downto 0))) else '0';
        end generate;

        rcount_w <= gry2bin(wq2_rptr);
        wcnt_sub <= std_logic_vector(
            unsigned((rcount_w(WR_A_SIZE) xor wbin(WR_A_SIZE)) & wbin(WR_A_SIZE-1 downto 0))
            - unsigned('0' & rcount_w(WR_A_SIZE-1 downto 0))
        );

        process(WrClk, WRst) begin
            if (WRst = '1') then
            wq2_rptr <= (others => '0');
            wq1_rptr <= (others => '0');
            elsif rising_edge(WrClk) then
                wq2_rptr <= wq1_rptr;
                wq1_rptr <= rptr;
            end if;
        end process;

        process(RdClk, RRst) begin
            if (RRst ='1') then
                rq2_wptr <= (others => '0');
                rq1_wptr <= (others => '0');
            elsif rising_edge(RdClk) then
                rq2_wptr <= rq1_wptr;
                rq1_wptr <= wptr;
            end if;
        end process;

        process(RdClk, RRst) begin
            if (RRst ='1') then
                rptr <= (others => '0');
            elsif rising_edge(RdClk) then
                rptr <= rgraynext;
            end if;
        end process;

        process(WrClk, WRst) begin
            if (WRst = '1') then
                wbin <= (others => '0');
                wptr <= (others => '0');
            elsif rising_edge(WrClk) then
                wbin <= wbinnext;
                wptr <= wgraynext;
            end if;
        end process;

    end generate;

    process(RdClk, RRst) begin
        if(RRst = '1') then
            Empty <= '1';
        elsif rising_edge(RdClk) then
            Empty <= rempty_val;
        end if;
    end process;

    process(WrClk, WRst) begin
        if(WRst = '1') then
            Full <= '0';
        elsif rising_edge(WrClk) then
            Full <= wfull_val;
        end if;
    end process;

    arempty_val <= '1' when ((unsigned(rcnt_sub) <= AlmostEmptyClrTh) or ((unsigned(rcnt_sub) = (AlmostEmptyClrTh + 1)) and (RdEn = '1'))) else '0';
    awfull_val <= '1' when ((unsigned(wcnt_sub) >= AlmostFullClrTh) or ((unsigned(wcnt_sub) = (AlmostFullClrTh - 1)) and (WrEn = '1'))) else '0';

    process(RdClk, RRst) begin
        if(RRst = '1') then
            Almost_Empty <= '1';
        elsif rising_edge(RdClk) then
            if((arempty_val = '1') and ((unsigned(rcnt_sub) <= AlmostEmptySetTh) or (( unsigned(rcnt_sub) = (AlmostEmptySetTh + 1)) and (RdEn = '1')))) then
                Almost_Empty <= '1';
            elsif (awfull_val = '1') then 
                Almost_Empty <= '0';
            end if;
        end if;
    end process;

    process(WrClk, WRst) begin
        if (WRst = '1') then
            Almost_Full <= '0';
        elsif rising_edge(WrClk) then
            if( (awfull_val = '1') and ( (unsigned(wcnt_sub) >= AlmostFullSetTh) or ((unsigned(wcnt_sub) = (AlmostFullSetTh - 1)) and (WrEn = '1')))) then
                Almost_Full <= '1';
            elsif (awfull_val = '0') then
                Almost_Full <= '0';
            end if;
        end if;
    end process;

    process(WrClk, WRst) begin
        if (WRst = '1') then
            Wnum <= (others => '0');
        elsif rising_edge(WrClk) then
            Wnum <= unsigned(wcnt_sub);
        end if;
    end process;


    process(RdClk, RRst) begin
        if (RRst = '1') then
            Rnum <= (others => '0');
        elsif rising_edge(RdClk) then
            Rnum <= unsigned(rcnt_sub);
        end if;
    end process;

end architecture;
