SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += src/four_bank_sram.sv
VERILOG_SOURCES += src/tag_decoder.sv
VERILOG_SOURCES += src/tag_comparator.sv
VERILOG_SOURCES += src/read_mux.sv
VERILOG_SOURCES += src/write_demux.sv
VERILOG_SOURCES += src/main_mem_mux.sv
VERILOG_SOURCES += src/cache_controller.sv
VERILOG_SOURCES += src/cache_top.sv

TOPLEVEL = cache_top
MODULE = cache_top_cocotb

# Artifact organization
SIM_BUILD = build/sim_build
export COCOTB_RESULTS_FILE = build/results.xml

export PYTHONPATH := tb:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim

clear: clean
	rm -rf build
