//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.01 (64-bit)
//IP Version: 1.1
//Part Number: GW5AST-LV138PG484AC1/I0
//Device: GW5AST-138
//Device Version: C
//Created Time: Thu Feb  5 17:23:38 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    Gowin_MULTALU your_instance_name(
        .dout(dout), //output [47:0] dout
        .a(a), //input [26:0] a
        .b(b), //input [17:0] b
        .c(c), //input [47:0] c
        .addsub1(addsub1), //input addsub1
        .addsub0(addsub0) //input addsub0
    );

//--------Copy end-------------------
