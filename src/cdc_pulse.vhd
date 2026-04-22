library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

entity cdc_pulse is
port (
    rstn        : in  std_logic;
    clk_src     : in  std_logic;
    clk_dest    : in  std_logic;
    pulse_src   : in  std_logic;
    pulse_dest  : out std_logic
);
end entity;

architecture arch of cdc_pulse is

signal src_toggle   : std_logic := '0';
signal dest_toggle  : std_logic_vector(2 downto 0) := (others => '0');

begin

process(clk_src, rstn) begin
    if(rstn = '0') then
        src_toggle <= '0';
    else
        if(rising_edge(clk_src)) then
            if(pulse_src) then
                src_toggle <= not src_toggle;
            end if;
        end if;
    end if;
end process;

process(clk_dest, rstn) begin
    if(rstn = '0') then
        dest_toggle <= "000";
    else
        if(rising_edge(clk_dest)) then
            dest_toggle(2) <= dest_toggle(1);
            dest_toggle(1) <= dest_toggle(0);
            dest_toggle(0) <= src_toggle;
        end if;
    end if;
end process;

pulse_dest <= dest_toggle(2) xor dest_toggle(1);

end architecture;
