SIM ?= icarus
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES += src/radix2mul.sv
TOPLEVEL = radix2mul
COCOTB_TEST_MODULES = radix2mul_tb

ifeq ($(WAVES), 1)
    VERILOG_SOURCES += tb/radix2mul_wf.sv
    PLUSARGS += +WAVES
endif

# Artifact organization
SIM_BUILD = build/sim_build
export COCOTB_RESULTS_FILE = build/results.xml

export PYTHONPATH := $(PWD)/tb:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim

clear: clean
	rm -rf build

