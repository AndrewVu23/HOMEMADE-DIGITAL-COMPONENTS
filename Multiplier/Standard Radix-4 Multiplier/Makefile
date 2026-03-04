SIM ?= icarus
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES += src/radix4mul.sv
TOPLEVEL = radix4mul
COCOTB_TEST_MODULES = radix4mul_tb

ifeq ($(WAVES), 1)
    VERILOG_SOURCES += tb/radix4mul_wf.sv
    PLUSARGS += +WAVES
endif

# Artifact organization
SIM_BUILD = build/sim_build
export COCOTB_RESULTS_FILE = build/results.xml

export PYTHONPATH := $(PWD)/tb:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim

clear: clean
	rm -rf build

