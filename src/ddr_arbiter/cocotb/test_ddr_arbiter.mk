# Makefile for cocotb

# defaults
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES ?= $(PWD)/../ddr_arbiter.sv
VERILOG_SOURCES += $(PWD)/../fifo_sc_ssram.sv

# VERILOG_INCLUDE_DIRS ?= $(PWD)/../src/AHB_Arbiter

# use VHDL_SOURCES for VHDL files

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = ddr_arbiter

# MODULE is the basename of the Python test file
COCOTB_TEST_MODULES = test_ddr_arbiter

# Example of how to add a verilog define
# this is equivalent to `define INSERT_ERROR in the .v file
# COMPILE_ARGS ?= -DINSERT_ERROR 
# and this is how you'd do something like `define NUM_BITS 12
# COMPILE_ARGS ?= -DNUM_BITS=12
# WAVES ?= 1

COMPILE_ARGS ?= +define+SIM
EXTRA_ARGS ?= --trace --trace-structs --trace-fst --trace-params
# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
