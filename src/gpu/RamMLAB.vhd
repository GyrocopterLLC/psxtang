library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all; 
use IEEE.math_real.all;
-- LIBRARY altera_mf;
-- USE altera_mf.altera_mf_components.all; 

entity RamMLAB is
    generic 
    (
        width           :  natural;
        widthad         :  natural
    );
    port 
    (
        inclock         : in std_logic;
        wren            : in std_logic;
        data            : in std_logic_vector(width-1 downto 0);
        wraddress       : in std_logic_vector(widthad-1 downto 0);
        rdaddress       : in std_logic_vector(widthad-1 downto 0);
        q               : out std_logic_vector(width-1 downto 0)
    );
end;

architecture rtl of RamMLAB is

    -- create memory type
    subtype word_t is std_logic_vector((width-1) downto 0);
    type memory_t is array(2**widthad-1 downto 0) of word_t;

    signal mem : memory_t := (others => (others => '0'));

begin
    -- write process
    process(inclock)
        begin
        if rising_edge(inclock) then
            if(wren = '1') then
                mem(to_integer(unsigned(wraddress))) <= data;
            end if;
        end if;
    end process;

    -- read process (asynchronous! this is why we need distributed ram, not block ram)
    q <= mem(to_integer(unsigned(rdaddress)));


end rtl;