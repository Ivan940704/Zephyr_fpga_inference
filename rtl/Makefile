IVERILOG ?= iverilog
VVP ?= vvp

BUILD_DIR := build
LEAF_SOURCES := $(wildcard leaf/*.v)
GSU_SOURCES := $(wildcard gsu/*.v)
LINEAR_SOURCES := $(wildcard linear/*.v)
SPARSE_SOURCES := $(wildcard sparse/*.v)
FULLBAND_SOURCES := $(wildcard fullband/*.v)
AXI_SOURCES := $(wildcard axi/*.v)
MEMORY_SOURCES := $(wildcard memory/*.v)
CONTROL_SOURCES := $(wildcard control/*.v)
RTL_SOURCES := $(LEAF_SOURCES) $(GSU_SOURCES) $(LINEAR_SOURCES) $(SPARSE_SOURCES) $(FULLBAND_SOURCES) $(AXI_SOURCES) $(MEMORY_SOURCES) $(CONTROL_SOURCES)
TESTBENCHES := $(sort $(wildcard tb/tb_*.v))
TEST_NAMES := $(basename $(notdir $(TESTBENCHES)))
SIM_BINS := $(addprefix $(BUILD_DIR)/,$(TEST_NAMES))

.PHONY: test reference clean

test: reference $(SIM_BINS)
	@set -e; for sim in $(SIM_BINS); do $(VVP) $$sim; done

reference:
	python3 tests/reference_checks.py

$(BUILD_DIR)/tb_%: tb/tb_%.v $(RTL_SOURCES)
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s tb_$* -o $@ $(RTL_SOURCES) $<

clean:
	rm -rf $(BUILD_DIR)
