# Makefile for cocotb
VERILATOR_VERSION=`verilator --version | cut -d' ' -f 2 `
# defaults
SIM ?= ghdl
TOPLEVEL_LANG ?= vhdl

VHDL_SOURCES ?= $(PWD)/vhdl_wrapper.vhd
VHDL_SOURCES += $(PWD)/.gvi/counter_v/counter_v_wrapper.vhd

# VERILOG_INCLUDE_DIRS ?= $(PWD)/../src/AHB_Arbiter

# use VHDL_SOURCES for VHDL files

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = vhdl_wrapper

# MODULE is the basename of the Python test file
COCOTB_TEST_MODULES = test_wrapper

# Example of how to add a verilog define
# this is equivalent to `define INSERT_ERROR in the .v file
# COMPILE_ARGS ?= -DINSERT_ERROR 
# and this is how you'd do something like `define NUM_BITS 12
# COMPILE_ARGS ?= -DNUM_BITS=12
# WAVES ?= 1

# COMPILE_ARGS ?= +define+SIM
# EXTRA_ARGS ?= --trace --trace-structs --trace-fst --trace-params
# include cocotb's make rules to take care of the simulator setup

# for ghdl
# COMPILE_ARGS ?= --std=08 -frelaxed
SIM_ARGS ?= --fst=dump.fst --ieee-asserts=disable
EXTRA_ARGS ?= --std=08 -frelaxed 
MAKE_ARGS ?= $(shell cat .gvi/counter_v/counter_v_wrapper.flags) $(shell cat .gvi/common.flags)


# gviexec:  /mnt/d/Documents/GitHub/gvi/gvi.cpp
# 	g++ -o gvi /mnt/d/Documents/GitHub/gvi/gvi.cpp

# .gvi/counter_v/counter_v_wrapper.vhd: gviexec $(PWD)/counter_v.sv
# 	./gvi -vv $(VERILATOR_VERSION) -v $(PWD)/counter_v.sv -t counter_v -c clk_i

# gvi: .gvi/counter_v/counter_v_wrapper.vhd

include $(shell cocotb-config --makefiles)/Makefile.sim
