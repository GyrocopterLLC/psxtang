--Copyright (C)2014-2025 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: IP file
--Tool Version: V1.9.12.01 (64-bit)
--IP Version: 1.1
--Part Number: GW5AST-LV138PG484AC1/I0
--Device: GW5AST-138
--Device Version: C
--Created Time: Thu Feb  5 17:24:22 2026

library IEEE;
use IEEE.std_logic_1164.all;

entity Gowin_MULTALU is
    port (
        dout: out std_logic_vector(47 downto 0);
        a: in std_logic_vector(26 downto 0);
        b: in std_logic_vector(17 downto 0);
        c: in std_logic_vector(47 downto 0);
        addsub1: in std_logic;
        addsub0: in std_logic
    );
end Gowin_MULTALU;

architecture Behavioral of Gowin_MULTALU is

    signal caso: std_logic_vector(47 downto 0);
    signal soa: std_logic_vector(26 downto 0);
    signal gw_gnd: std_logic;
    signal D_i: std_logic_vector(25 downto 0);
    signal SIA_i: std_logic_vector(26 downto 0);
    signal CASI_i: std_logic_vector(47 downto 0);
    signal ADDSUB_i: std_logic_vector(1 downto 0);
    signal CLK_i: std_logic_vector(1 downto 0);
    signal CE_i: std_logic_vector(1 downto 0);
    signal RESET_i: std_logic_vector(1 downto 0);

    --component declaration
    component MULTALU27X18
        generic (
              AREG_CLK : string := "BYPASS";
              AREG_CE : string := "CE0";
              AREG_RESET : string := "RESET0";
              BREG_CLK : string := "BYPASS";
              BREG_CE : string := "CE0";
              BREG_RESET : string := "RESET0";
              DREG_CLK : string := "BYPASS";
              DREG_CE : string := "CE0";
              DREG_RESET : string := "RESET0";
              C_IREG_CLK : string := "BYPASS";
              C_IREG_CE : string := "CE0";
              C_IREG_RESET : string := "RESET0";
              PSEL_IREG_CLK : string := "BYPASS";
              PSEL_IREG_CE : string := "CE0";
              PSEL_IREG_RESET : string := "RESET0";
              PADDSUB_IREG_CLK : string := "BYPASS";
              PADDSUB_IREG_CE : string := "CE0";
              PADDSUB_IREG_RESET : string := "RESET0";
              ADDSUB0_IREG_CLK : string := "BYPASS";
              ADDSUB0_IREG_CE : string := "CE0";
              ADDSUB0_IREG_RESET : string := "RESET0";
              ADDSUB1_IREG_CLK : string := "BYPASS";
              ADDSUB1_IREG_CE : string := "CE0";
              ADDSUB1_IREG_RESET : string := "RESET0";
              CSEL_IREG_CLK : string := "BYPASS";
              CSEL_IREG_CE : string := "CE0";
              CSEL_IREG_RESET : string := "RESET0";
              CASISEL_IREG_CLK : string := "BYPASS";
              CASISEL_IREG_CE : string := "CE0";
              CASISEL_IREG_RESET : string := "RESET0";
              ACCSEL_IREG_CLK : string := "BYPASS";
              ACCSEL_IREG_CE : string := "CE0";
              ACCSEL_IREG_RESET : string := "RESET0";
              PREG_CLK : string := "BYPASS";
              PREG_CE : string := "CE0";
              PREG_RESET : string := "RESET0";
              ADDSUB0_PREG_CLK : string := "BYPASS";
              ADDSUB0_PREG_CE : string := "CE0";
              ADDSUB0_PREG_RESET : string := "RESET0";
              ADDSUB1_PREG_CLK : string := "BYPASS";
              ADDSUB1_PREG_CE : string := "CE0";
              ADDSUB1_PREG_RESET : string := "RESET0";
              CSEL_PREG_CLK : string := "BYPASS";
              CSEL_PREG_CE : string := "CE0";
              CSEL_PREG_RESET : string := "RESET0";
              CASISEL_PREG_CLK : string := "BYPASS";
              CASISEL_PREG_CE : string := "CE0";
              CASISEL_PREG_RESET : string := "RESET0";
              ACCSEL_PREG_CLK : string := "BYPASS";
              ACCSEL_PREG_CE : string := "CE0";
              ACCSEL_PREG_RESET : string := "RESET0";
              C_PREG_CLK : string := "BYPASS";
              C_PREG_CE : string := "CE0";
              C_PREG_RESET : string := "RESET0";
              FB_PREG_EN : string := "FALSE";
              SOA_PREG_EN : string := "FALSE";
              OREG_CLK : string := "BYPASS";
              OREG_CE : string := "CE0";
              OREG_RESET : string := "RESET0";
              MULT_RESET_MODE : string := "SYNC";
              PRE_LOAD : bit_vector := X"000000000000";
              DYN_P_SEL : string := "FALSE";
              P_SEL : bit := '0';
              DYN_P_ADDSUB : string := "FALSE";
              P_ADDSUB : bit := '0';
              DYN_A_SEL : string := "FALSE";
              A_SEL : bit := '0';
              DYN_ADD_SUB_0 : string := "FALSE";
              ADD_SUB_0 : bit := '0';
              DYN_ADD_SUB_1 : string := "FALSE";
              ADD_SUB_1 : bit := '0';
              DYN_C_SEL : string := "FALSE";
              C_SEL : bit := '0';
              DYN_CASI_SEL : string := "FALSE";
              CASI_SEL : bit := '0';
              DYN_ACC_SEL : string := "FALSE";
              ACC_SEL : bit := '0';
              MULT12X12_EN : string := "FALSE"
        );
        port (
            DOUT: out std_logic_vector(47 downto 0);
            CASO: out std_logic_vector(47 downto 0);
            SOA: out std_logic_vector(26 downto 0);
            A: in std_logic_vector(26 downto 0);
            B: in std_logic_vector(17 downto 0);
            C: in std_logic_vector(47 downto 0);
            D: in std_logic_vector(25 downto 0);
            SIA: in std_logic_vector(26 downto 0);
            CASI: in std_logic_vector(47 downto 0);
            ACCSEL: in std_logic;
            CASISEL: in std_logic;
            ASEL: in std_logic;
            PSEL: in std_logic;
            CSEL: in std_logic;
            ADDSUB: in std_logic_vector(1 downto 0);
            PADDSUB: in std_logic;
            CLK: in std_logic_vector(1 downto 0);
            CE: in std_logic_vector(1 downto 0);
            RESET: in std_logic_vector(1 downto 0)
        );
    end component;
begin
    gw_gnd <= '0';

    D_i <= gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd;
    SIA_i <= gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd;
    CASI_i <= gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd & gw_gnd;
    ADDSUB_i <= addsub1 & addsub0;
    CLK_i <= gw_gnd & gw_gnd;
    CE_i <= gw_gnd & gw_gnd;
    RESET_i <= gw_gnd & gw_gnd;

    multalu27x18_inst: MULTALU27X18
        generic map (
            AREG_CLK => "BYPASS",
            AREG_CE => "CE0",
            AREG_RESET => "RESET0",
            BREG_CLK => "BYPASS",
            BREG_CE => "CE0",
            BREG_RESET => "RESET0",
            DREG_CLK => "BYPASS",
            DREG_CE => "CE0",
            DREG_RESET => "RESET0",
            C_IREG_CLK => "BYPASS",
            C_IREG_CE => "CE0",
            C_IREG_RESET => "RESET0",
            PSEL_IREG_CLK => "BYPASS",
            PSEL_IREG_CE => "CE0",
            PSEL_IREG_RESET => "RESET0",
            PADDSUB_IREG_CLK => "BYPASS",
            PADDSUB_IREG_CE => "CE0",
            PADDSUB_IREG_RESET => "RESET0",
            ADDSUB0_IREG_CLK => "BYPASS",
            ADDSUB0_IREG_CE => "CE0",
            ADDSUB0_IREG_RESET => "RESET0",
            ADDSUB1_IREG_CLK => "BYPASS",
            ADDSUB1_IREG_CE => "CE0",
            ADDSUB1_IREG_RESET => "RESET0",
            CSEL_IREG_CLK => "BYPASS",
            CSEL_IREG_CE => "CE0",
            CSEL_IREG_RESET => "RESET0",
            CASISEL_IREG_CLK => "BYPASS",
            CASISEL_IREG_CE => "CE0",
            CASISEL_IREG_RESET => "RESET0",
            ACCSEL_IREG_CLK => "BYPASS",
            ACCSEL_IREG_CE => "CE0",
            ACCSEL_IREG_RESET => "RESET0",
            PREG_CLK => "BYPASS",
            PREG_CE => "CE0",
            PREG_RESET => "RESET0",
            ADDSUB0_PREG_CLK => "BYPASS",
            ADDSUB0_PREG_CE => "CE0",
            ADDSUB0_PREG_RESET => "RESET0",
            ADDSUB1_PREG_CLK => "BYPASS",
            ADDSUB1_PREG_CE => "CE0",
            ADDSUB1_PREG_RESET => "RESET0",
            CSEL_PREG_CLK => "BYPASS",
            CSEL_PREG_CE => "CE0",
            CSEL_PREG_RESET => "RESET0",
            CASISEL_PREG_CLK => "BYPASS",
            CASISEL_PREG_CE => "CE0",
            CASISEL_PREG_RESET => "RESET0",
            ACCSEL_PREG_CLK => "BYPASS",
            ACCSEL_PREG_CE => "CE0",
            ACCSEL_PREG_RESET => "RESET0",
            C_PREG_CLK => "BYPASS",
            C_PREG_CE => "CE0",
            C_PREG_RESET => "RESET0",
            FB_PREG_EN => "FALSE",
            SOA_PREG_EN => "FALSE",
            OREG_CLK => "BYPASS",
            OREG_CE => "CE0",
            OREG_RESET => "RESET0",
            MULT_RESET_MODE => "SYNC",
            PRE_LOAD => X"000000000000",
            DYN_P_SEL => "FALSE",
            P_SEL => '0',
            DYN_P_ADDSUB => "FALSE",
            P_ADDSUB => '0',
            DYN_A_SEL => "FALSE",
            A_SEL => '0',
            DYN_ADD_SUB_0 => "TRUE",
            ADD_SUB_0 => '0',
            DYN_ADD_SUB_1 => "TRUE",
            ADD_SUB_1 => '0',
            DYN_C_SEL => "FALSE",
            C_SEL => '1',
            DYN_CASI_SEL => "FALSE",
            CASI_SEL => '0',
            DYN_ACC_SEL => "FALSE",
            ACC_SEL => '0',
            MULT12X12_EN => "FALSE"
        )
        port map (
            DOUT => dout,
            CASO => caso,
            SOA => soa,
            A => a,
            B => b,
            C => c,
            D => D_i,
            SIA => SIA_i,
            CASI => CASI_i,
            ACCSEL => gw_gnd,
            CASISEL => gw_gnd,
            ASEL => gw_gnd,
            PSEL => gw_gnd,
            CSEL => gw_gnd,
            ADDSUB => ADDSUB_i,
            PADDSUB => gw_gnd,
            CLK => CLK_i,
            CE => CE_i,
            RESET => RESET_i
        );

end Behavioral; --Gowin_MULTALU
