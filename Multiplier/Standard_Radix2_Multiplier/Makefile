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

# ── Verilator targets ────────────────────────────────────────────────────────
VLTOR_SRC  = src/radix2mul.sv
VLTOR_TB   = tb/radix2mul_tb.cpp
VLTOR_DIR  = obj_dir
VLTOR_BIN  = $(VLTOR_DIR)/Vradix2mul

VERILATOR_ROOT := $(shell verilator -getenv VERILATOR_ROOT)
VLTOR_INCS = -I$(VLTOR_DIR) \
             -I$(VERILATOR_ROOT)/include \
             -I$(VERILATOR_ROOT)/include/vltstd
# Two archives produced by the Verilator-generated Makefile:
#   libVradix2mul.a — DUT objects
#   libverilated.a  — Verilator runtime (verilated.o, verilated_cov.o, verilated_threads.o)
VLTOR_LIBS = $(VLTOR_DIR)/libVradix2mul.a $(VLTOR_DIR)/libverilated.a

.PHONY: vsim vcov vclean

vsim:
	verilator --cc -Wall --Mdir $(VLTOR_DIR) $(VLTOR_SRC)
	cd $(VLTOR_DIR) && env -i PATH="$(PATH)" make -f Vradix2mul.mk
	g++ $(VLTOR_INCS) $(VLTOR_TB) $(VLTOR_LIBS) -o $(VLTOR_BIN)
	mkdir -p coverage
	$(VLTOR_BIN)

vcov:
	verilator --cc -Wall --coverage --Mdir $(VLTOR_DIR) $(VLTOR_SRC)
	cd $(VLTOR_DIR) && env -i PATH="$(PATH)" make -f Vradix2mul.mk
	g++ $(VLTOR_INCS) $(VLTOR_TB) $(VLTOR_LIBS) -o $(VLTOR_BIN)
	mkdir -p coverage/annotated
	$(VLTOR_BIN)
	verilator_coverage --annotate coverage/annotated coverage/coverage.dat
	@echo "Coverage report: coverage/annotated/"

vclean:
	rm -rf $(VLTOR_DIR) coverage/

