
DIAG_TESTS_IGNORE := %.mk include common
DIAG_TESTS := $(filter-out $(DIAG_TESTS_IGNORE), $(notdir $(wildcard $(HDLET_ROOT)/tb/c_asm_tests/*)))

DIAG_REGRESS_TESTS_IGNORE := test_pass
DIAG_REGRESS_TESTS := $(filter-out $(DIAG_REGRESS_TESTS_IGNORE), $(DIAG_TESTS))

print-diag-tests:
	@echo "Available Diagnostic Tests:"
	@for t in $(DIAG_TESTS); do \
		echo "  - $$t"; \
	done


print-diag-regress-tests:
	@echo "Regression Diagnostic Tests:"
	@for t in $(DIAG_REGRESS_TESTS); do \
		echo "  - $$t"; \
	done


compile_diag: check_riscv_toolchain create_run_dir
	elf_name=$(notdir $(TEST_ELF)) && \
	cp -a $(HDLET_ROOT)/tb/c_asm_tests/$$elf_name $(ELF_RUN_ROOT)/test/. && \
	cd $(ELF_RUN_ROOT)/test/$$elf_name && $(MAKE) 2>&1 | tee compile_diag.log

$(DIAG_TESTS): create_run_dir
	$(MAKE) -f $(PARENT_MAKE) compile_diag \
		ELF_RUN_ROOT=$(ELF_RUN_ROOT) TEST_ELF=$@
	if [ -f "$(ELF_RUN_ROOT)/test/$@/test.conf" ]; then \
		echo "Reading config from $(ELF_RUN_ROOT)/test/$@/test.conf"; \
		. "$(ELF_RUN_ROOT)/test/$@/test.conf"; \
		$(MAKE) -f $(PARENT_MAKE) run_elf \
			ELF_RUN_ROOT=$(ELF_RUN_ROOT) \
			TEST_ELF=$(ELF_RUN_ROOT)/test/$@/$@ \
			MINION_MASK=$$MINION_MASK \
			THREAD_MASK=$$THREAD_MASK \
			TIMEOUT=$$TIMEOUT \
			BOOT_PC=$$BOOT_PC; \
	else \
		echo "Config file not found, using default values"; \
		$(MAKE) -f $(PARENT_MAKE) run_elf \
			ELF_RUN_ROOT=$(ELF_RUN_ROOT) \
			TEST_ELF=$(ELF_RUN_ROOT)/test/$@/$@ \
			MINION_MASK=$(MINION_MASK) \
			THREAD_MASK=$(THREAD_MASK) \
			TIMEOUT=$(TIMEOUT) \
			BOOT_PC=$(BOOT_PC); \
	fi

diag_regress: $(DIAG_REGRESS_TESTS)

.PHONY: print-diag-tests print-diag-regress-tests
