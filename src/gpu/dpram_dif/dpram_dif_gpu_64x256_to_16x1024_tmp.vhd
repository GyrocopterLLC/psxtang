--Copyright (C)2014-2025 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: Template file for instantiation
--Tool Version: V1.9.12.01 (64-bit)
--IP Version: 1.0
--Part Number: GW5AST-LV138PG484AC1/I0
--Device: GW5AST-138
--Device Version: C
--Created Time: Thu Jan 15 12:18:04 2026

--Change the instance name and port connections to the signal names
----------Copy here to design--------

component dpram_dif_gpu_64x256_to_16x1024
    port (
        dout: out std_logic_vector(15 downto 0);
        clka: in std_logic;
        cea: in std_logic;
        clkb: in std_logic;
        ceb: in std_logic;
        oce: in std_logic;
        reset: in std_logic;
        ada: in std_logic_vector(7 downto 0);
        din: in std_logic_vector(63 downto 0);
        adb: in std_logic_vector(9 downto 0)
    );
end component;

your_instance_name: dpram_dif_gpu_64x256_to_16x1024
    port map (
        dout => dout,
        clka => clka,
        cea => cea,
        clkb => clkb,
        ceb => ceb,
        oce => oce,
        reset => reset,
        ada => ada,
        din => din,
        adb => adb
    );

----------Copy end-------------------
