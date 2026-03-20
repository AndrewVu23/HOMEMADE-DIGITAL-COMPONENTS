# Cocotb testbench for full UART
# Usage: make

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

SRC_DIR = ../src

VERILOG_SOURCES += $(SRC_DIR)/baud_rate_gen.sv
VERILOG_SOURCES += $(SRC_DIR)/TX.sv
VERILOG_SOURCES += $(SRC_DIR)/RX.sv
VERILOG_SOURCES += $(SRC_DIR)/UART.sv

TOPLEVEL = UART
MODULE   = UART_cocotb

COMPILE_ARGS += -g2012

SIM_BUILD = build/sim_build

include $(shell cocotb-config --makefiles)/Makefile.sim
