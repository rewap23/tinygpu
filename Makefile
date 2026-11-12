# tinygpu -- run `make help`
#
# SRC=src  runs the same tests against src files.

SRC   ?= src
N     ?= 8
KERNEL ?= vecadd
KERNELS ?= vecadd vecsub vecmul
BUILD := build/$(SRC)
IV    := iverilog -g2005 -Wall -I $(SRC)

# every hardware file, smallest part first
RTL   := $(SRC)/alu.v $(SRC)/regfile.v $(SRC)/writeback.v $(SRC)/lane.v \
         $(SRC)/decoder.v $(SRC)/scheduler.v $(SRC)/thread_mask.v \
         $(SRC)/imem.v $(SRC)/dmem.v $(SRC)/core.v

.PHONY: help all alu regfile decoder scheduler asm core kernels synth schematic clean

define RUN_SIM
cd $(BUILD) && { vvp -n $(1) $(2) > $(1).log; status=$$?; cat $(1).log; test $$status -eq 0; } && ! grep -q 'FAIL' $(1).log
endef

help:
	@echo "make alu        - test alu.v        (all 262,144 input combos)"
	@echo "make regfile    - test regfile.v"
	@echo "make decoder    - test decoder.v    (all 65,536 instructions)"
	@echo "make scheduler  - test scheduler.v  on its own, tick by tick"
	@echo "make asm        - assemble sw/$(KERNEL).asm -> build/.../$(KERNEL).hex"
	@echo "make core       - run vecadd; choose KERNEL=vecmul or vecsub"
	@echo "make core KERNEL=vecmul N=8 - run vector multiplication"
	@echo "make kernels    - run vecadd, vecsub, and vecmul with N=8 and N=7"
	@echo "make synth      - synthesize to gates, print cell counts"
	@echo "make schematic  - draw the 2-bit ALU as gates"
	@echo "make all        - every test"
	@echo "add SRC=src to any target to test your own version"

all: alu regfile decoder scheduler kernels

$(BUILD):
	@mkdir -p $(BUILD)

alu: | $(BUILD)
	$(IV) -o $(BUILD)/tb_alu $(SRC)/alu.v tb/tb_alu.v
	$(call RUN_SIM,tb_alu)

regfile: | $(BUILD)
	$(IV) -o $(BUILD)/tb_regfile $(SRC)/regfile.v tb/tb_regfile.v
	$(call RUN_SIM,tb_regfile)

decoder: | $(BUILD)
	$(IV) -o $(BUILD)/tb_decoder $(SRC)/decoder.v tb/tb_decoder.v
	$(call RUN_SIM,tb_decoder)

scheduler: | $(BUILD)
	$(IV) -o $(BUILD)/tb_scheduler $(SRC)/scheduler.v tb/tb_scheduler.v
	$(call RUN_SIM,tb_scheduler)

asm: | $(BUILD)
	python3 sw/asm.py sw/$(KERNEL).asm $(BUILD)/$(KERNEL).hex

core: asm
	$(IV) -o $(BUILD)/tb_core $(RTL) tb/tb_core.v
	$(call RUN_SIM,tb_core,+N=$(N) +KERNEL=$(KERNEL))
	@echo "waveform: $(BUILD)/tb_core.vcd  (open with gtkwave or surfer)"

kernels:
	@set -e; for kernel in $(KERNELS); do \
		$(MAKE) --no-print-directory core KERNEL=$$kernel N=8; \
		$(MAKE) --no-print-directory core KERNEL=$$kernel N=7; \
	done

synth: | $(BUILD)
	cd $(SRC) && yosys -q -l ../$(BUILD)/synth.log -s ../synth/synth.ys
	@grep -A40 "=== design hierarchy ===" $(BUILD)/synth.log | head -40 || true

schematic: | $(BUILD)
	cd $(SRC) && yosys -q -s ../synth/schematic.ys
	@echo "wrote $(BUILD)/alu_2bit.svg"

clean:
	rm -rf build
