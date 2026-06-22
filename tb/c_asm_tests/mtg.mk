
MTG_ROOT ?= $(HDLET_ROOT)/ip/cpu_subsystem/extern/mtg
export MTG_ROOT

MTG_TEST ?= rand
MTG_VARIANTS := amo cops rand flb_fcc global_amo local_amo mask pi ps rv32f rv32i rv32m rv64i rv64m rv tensor

print-mtg-tests:
	@echo "Available MTG Tests:"
	@for t in $(MTG_VARIANTS:%=mtg_16t_%); do \
		echo "  - $$t"; \
	done

print-mtg-regress-tests:
	@echo "Regression MTG Tests:"
	@for t in $(MTG_VARIANTS:%=mtg_16t_%); do \
		echo "  - $$t"; \
	done

compile_mtg_16t: check_riscv_toolchain create_run_dir
	echo "MTG test is $(MTG_TEST)"; \
	echo "MTG seed is $(SEED)"; \
	elf_name=mtg_16t_$(MTG_TEST)_$(SEED) && \
	mkdir -p $(ELF_RUN_ROOT)/test/$$elf_name && \
	cd $(ELF_RUN_ROOT)/test/$$elf_name &&\
	echo $(SEED) > SEED && \
	$(MTG_ROOT)/mtg.py -thr 0x3 -min 0xff -shi 0x1 -c $(MTG_TEST).py  \
		-s $(SEED) --self_check 0 -ncomps 2500 build \
		> compile_mtg.log 2>&1 && \
	mv base $$elf_name

$(MTG_VARIANTS:%=mtg_16t_%): create_run_dir
	SEED=$${SEED:-$$RANDOM}; \
	$(MAKE) -f $(PARENT_MAKE) compile_mtg_16t \
		ELF_RUN_ROOT=$(ELF_RUN_ROOT) SEED=$$SEED MTG_TEST=$(@:mtg_16t_%=%) && \
	$(MAKE) -f $(PARENT_MAKE) run_elf \
		ELF_RUN_ROOT=$(ELF_RUN_ROOT) TEST_ELF=$(ELF_RUN_ROOT)/test/$@_$$SEED/$@_$$SEED

mtg_regress: $(MTG_VARIANTS:%=mtg_16t_%)

.PHONY: print-mtg-tests print-mtg-regress-tests
