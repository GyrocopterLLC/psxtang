--Copyright (C)2014-2025 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: Template file for instantiation
--Tool Version: V1.9.12.01 (64-bit)
--IP Version: 1.1
--Part Number: GW5AST-LV138PG484AC1/I0
--Device: GW5AST-138
--Device Version: C
--Created Time: Thu Feb  5 17:24:22 2026

--Change the instance name and port connections to the signal names
----------Copy here to design--------

component Gowin_MULTALU
    port (
        dout: out std_logic_vector(47 downto 0);
        a: in std_logic_vector(26 downto 0);
        b: in std_logic_vector(17 downto 0);
        c: in std_logic_vector(47 downto 0);
        addsub1: in std_logic;
        addsub0: in std_logic
    );
end component;

your_instance_name: Gowin_MULTALU
    port map (
        dout => dout,
        a => a,
        b => b,
        c => c,
        addsub1 => addsub1,
        addsub0 => addsub0
    );

----------Copy end-------------------
