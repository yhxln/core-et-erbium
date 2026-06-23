// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: Copyright (c) 2026 Ainekko, Co.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


#include "et_test_common.h"
#include "minion.h"
#include "esrs_rw_test.h"
#include <string.h>
#include <string.h>
#include "cacheops.h"

typedef struct {
    uint64_t mcause;
    uint64_t mtval;
    uint64_t mepc;
    uint64_t mstatus;
} trap_info_t;

volatile uint64_t fail_count = 0;
volatile trap_info_t g_last_trap = {0, 0, 0, 0};

inline void clear_last_trap(void)
{
    g_last_trap.mcause = 0;
    g_last_trap.mtval  = 0;
    g_last_trap.mepc   = 0;
}

inline bool trap_happened(void)
{
    return g_last_trap.mcause != 0;
}


void test_fail (void) {
    fail_count+=1;
    uint64_t v;
    asm volatile ("csrr %0, 0x8d0" : "=r"(v));
}

void setup_trap_vector()
{
    __asm__ __volatile__
    (
     "la t0, machine_handler\n"
     "csrw mtvec, t0\n"
     : : : "t0"
    );
}


void machine_handler()
{
    uint64_t mcause, mtval, mepc, mstatus;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));
    asm volatile ("csrr %0, mtval"  : "=r"(mtval));
    asm volatile ("csrr %0, mepc"   : "=r"(mepc));
    asm volatile ("csrr %0, mstatus": "=r"(mstatus));

    g_last_trap.mcause  = mcause;
    g_last_trap.mtval   = mtval;
    g_last_trap.mepc    = mepc;
    g_last_trap.mstatus = mstatus;
    // Skip offending instruction (assumes 4‑byte instruction)

    if (mcause == 8 || mcause == 9) {  // U/S ecall
        mstatus = (mstatus & ~0x1800UL) | (3UL << 11);  //  MPP = M-mode

        asm volatile (
            "csrw mstatus, %0\n\t"
            ::"r"(mstatus)
        );
        mepc += 4;
    }
    else if (mcause == 5 || mcause == 7) {  // load store access
        mepc += 4;
    }
    else {
        test_fail();
    }


    asm volatile ("csrw mepc, %0" :: "r"(mepc));
}


bool test_read32(uint64_t addr, uint64_t reg_mask, uint64_t expected_val, bool check_val)
{
    volatile uint64_t *p = (volatile uint64_t *)addr;
    clear_last_trap();
    uint64_t val = 0;
    bool error = 0;
    // Potentially faulting load
    val = *p;
    if (check_val == 1) {
        if (val != (expected_val&reg_mask)) {
            error = 1;
        }
    }
    return !trap_happened() && !error;  // true => access OK
}

bool test_write32(uint64_t addr, uint64_t data)
{
    volatile uint64_t *p = (volatile uint64_t *)addr;
    clear_last_trap();
    *p = data;                // potentially faulting store
    return !trap_happened();  // true => access OK
}


typedef enum {
    MODE_U = 0,
    MODE_S = 1,
    MODE_D = 2,
    MODE_M = 3
} priv_mode_t;

// For now: test only M‑mode attributes (allow_m_mode + allow_read/allow_write).
bool test_icache_err_log_info_procedural(uint64_t esr_addr) {
    // 1. Read the current status
    uint64_t current_val = *(volatile uint64_t*)esr_addr;
    bool already_clear = !(current_val & 0x1);

    // 2. Perform the procedural write (Clear command)
    // To clear, bit 0 (valid) must be 1 and bits 7:4 (err_code) must match current code
    uint64_t err_code = (current_val >> 4) & 0xF;
    uint64_t clear_cmd = (err_code << 4) | 0x1;

    if (!test_write32(esr_addr, clear_cmd)) return false;

    // 3. Read back to verify the side-effect (the register should be cleared)
    uint64_t post_clear_val = *(volatile uint64_t*)esr_addr;

    if (already_clear) {
        // If it was already clear, the write shouldn't have changed it to 1
        return !(post_clear_val & 0x1);
    } else {
        // If it was valid, it should now be clear
        return !(post_clear_val & 0x1);
    }
}

void test_esr_priv_mode(priv_mode_t mode, uint64_t esr_addr, uint64_t write_val, uint64_t read_check_val, uint64_t reg_mask, uint64_t reset_val, bool allow_read, bool allow_write, bool allow_m_mode, bool allow_s_mode, bool allow_u_mode, bool check_val)
{
        bool allow_priv_mode = (mode == MODE_M && allow_m_mode ) || (mode == MODE_S && allow_s_mode ) || (mode == MODE_U && allow_u_mode);
        // READ RESET
        bool ok_reset_read = test_read32(esr_addr, reg_mask, reset_val, check_val);
        bool allow_reset_read_priv = allow_read && allow_priv_mode;
        if ((allow_reset_read_priv != ok_reset_read)) {
            C_TEST_FAIL;
        }

        // WRITE
        bool ok_write = test_write32(esr_addr, write_val);
        bool allow_write_priv = allow_write && allow_priv_mode;
        if ((allow_write_priv != ok_write)) {
            test_fail();
        }

        // READ
        bool ok_read = test_read32(esr_addr, reg_mask, read_check_val, check_val);
        bool allow_read_priv = allow_read && allow_priv_mode;
        if ((allow_read_priv != ok_read)) {
            test_fail();
        }

        ok_write = test_write32(esr_addr, reset_val);
        allow_write_priv = allow_write && allow_priv_mode;
        if ((allow_write_priv != ok_write)) {
            test_fail();
        }
}

int main()
{
    setup_trap_vector();

    C_TEST_START;

    uint64_t thread_id = get_thread_id();
    uint64_t minion_id = get_minion_id();
    // for ESRs
    uint64_t esr_addr = 0;
    uint64_t mask = 0;
    uint64_t reset_val = 0;
    uint64_t write_val = 0;
    uint64_t read_val = 0;
    bool check_val = 1;

    if (minion_id != 0) {
        C_TEST_PASS;
    }

    if (thread_id != 0) {
        C_TEST_PASS;
    }

        for (int mode = PRV_U; mode <= PRV_M; mode++) {
            if (mode == PRV_D) continue;

            if (mode == MODE_U) {
                MRET_TO_UMODE_END();
            }

            else if (mode == MODE_S) {
                MRET_TO_SMODE_END();
            }

            //-----cpu esrs-----
            // minion_feature
            esr_addr = 0x80f40000;
            mask = 0x3f;
            reset_val = 0x1;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val, mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // thread1_disable
            esr_addr = 0x80f40010;
            mask = 0xff;
            reset_val = 0xff;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // ipi_trigger
            esr_addr = 0x80f40090;
            mask = 0xffff;
            reset_val = 0x0;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // ipi_redirect_filter
            esr_addr = 0x80f40088;
            mask = 0xffff;
            reset_val = 0xffff;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // ipi_redirect_trigger
            esr_addr = 0x80340080;
            mask = 0xffff;
            reset_val = 0x0;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = 0;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 1/*S*/, 1/*U*/, check_val);

            // ipi_redirect_clear
            esr_addr = 0x80f40098;
            mask = 0xffff;
            reset_val = 0x0;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = 0;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            for (int counter = 0 ; counter < 4 ; counter++) {
                // CREDINCx
                esr_addr = 0x803400c0+counter*8;
                mask = 0xff;
                reset_val = 0x0;
                write_val = 0xFFFFFFFFFFFFFFFFULL;
                read_val = 0;
                test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 1/*S*/, 1/*U*/, check_val);
            }

            // mtime local target
            esr_addr = 0x80f40218;
            mask = 0xffff;
            reset_val = 0xffff;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // icache u prefetch
            esr_addr = 0x803402f8;
            mask = 0xffffffffffff;
            reset_val = 0x1; // TODO BEMU issue, BEMU is reading zero
            write_val = (0x40050000ULL)|0xff;
            read_val = 0x1;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 1/*S*/, 1/*U*/, check_val);

            // icache s prefetch
            esr_addr = 0x80740300;
            mask = 0xffffffffffff;
            reset_val = 0x1; // TODO BEMU issue, BEMU is reading zero
            write_val = (0x40050000ULL)|0xff;
            read_val = 0x1;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 1/*S*/, 0/*U*/, check_val);

            // icache m prefetch
            esr_addr = 0x80f40308;
            mask = 0xffffffffffff;
            reset_val = 0x1; // TODO BEMU issue, BEMU is reading zero
            write_val = (0x40050000ULL)|0xff;
            read_val = 0x1;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // shire coop mode
            esr_addr = 0x80740290;
            mask = 0x1;
            reset_val = 0x0;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 1/*S*/, 0/*U*/, check_val);

            // clk_gate_ctl
            esr_addr = 0x80f40310;
            mask = 0x5f;
            reset_val = 0x0; //TODO BEMU expects data is 0xdf but DUT reported 0xff
            write_val = 0xFFFFFFFFFFFFFFFFULL; // TODO; BEMU issue, in BEMU it mismatches and reads 0xdf while RTL reads 0x5f
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // mtime cmp
            esr_addr = 0x80f40208;
            mask = 0xFFFFFFFFFFFFFFFFULL;
            reset_val = 0xFFFFFFFFFFFFFFFFULL;
            write_val = 0x0F0F0F0F0F0F0F0FULL;
            read_val = write_val;
            check_val = 0;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);
            check_val = 1;

            for (int barrier = 0; barrier < 32; barrier++) {
                esr_addr = 0x80340100+barrier*8;
                mask = 0xff;
                reset_val = 0x0;
                write_val = 0xFFFFFFFFFFFFFFFFULL;
                read_val = write_val;
                test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 1/*S*/, 1/*U*/, check_val);
            }

            //======== neigh-esrs========
            // ipi_redirect_pc
            esr_addr = ESR_NEIGH(0, IPI_REDIRECT_PC);
            mask = 0xfffffffffffe; //last bit of pc is always 0 update to sysemu
            reset_val = 0x0;
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 1/*S*/, 1/*U*/, check_val);

            // pmu_ctrl
            esr_addr = ESR_NEIGH(0, PMU_CTRL);
            mask = 0x1;
            reset_val = 0x0;
            write_val = 0x1;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // neigh_chicken
            esr_addr = ESR_NEIGH(0, NEIGH_CHICKEN);
            mask = 0x7f;
            reset_val = 0x0;
            write_val = 0x1ULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // icache_err_log_ctl
            esr_addr = ESR_NEIGH(0, ICACHE_ERR_LOG_CTL);
            mask = 0x7;
            reset_val = 0x6; //TODO_error: mismatch reset value rtl spec 0x6 but sysemu its 0
            write_val = 0xFFFFFFFFFFFFFFFFULL;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            // icache_err_log_info
            esr_addr = ESR_NEIGH(0, ICACHE_ERR_LOG_INFO);
            if (mode == MODE_M) {
                if (!test_write32(ESR_NEIGH(0, ICACHE_ERR_LOG_INFO), 0x1)){
                    C_TEST_FAIL;
                }
            } else {
                mask = 0xfffffffffffffff7;
                reset_val = 0x0;
                write_val = 0x15ULL;
                read_val = write_val;
                test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 0/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);
            }

            // icache_sbe_dbe_counts
            esr_addr = ESR_NEIGH(0, ICACHE_SBE_DBE_COUNTS);
            mask = 0x7ff;
            reset_val = 0x0;
            write_val = 0x0;
            read_val = write_val;
            test_esr_priv_mode(priv_mode_t(mode), esr_addr, write_val, read_val,  mask, reset_val, 1/*R*/, 1/*W*/, 1/*M*/, 0/*S*/, 0/*U*/, check_val);

            if (mode == MODE_U || mode == MODE_S) {
                //ECALL to return to M mode via handler
                asm volatile ("ecall;nop");
            }
        }
        if (fail_count > 0) {
            C_TEST_FAIL;
        }

        C_TEST_PASS;
}
