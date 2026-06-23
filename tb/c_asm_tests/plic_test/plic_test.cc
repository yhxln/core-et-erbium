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
#include <string.h>
#include <string.h>
#include "cacheops.h"
#include "plic_test.h"

// Test assumes vm off

#define DIAG_UEI 5
#define DIAG_UEI_SHIFT 56


#define PLIC_BASE_ADDRESS 0xa0000000
#define PLIC_ENABLE 0x2000
#define PLIC_CLAIM 0x200004
#define PLIC_THRESHOLD 0x200000
#define PLIC_PENDING 0x1000
#define PLIC_PRIORITY 0x0

#define SYSREG_BASE_ADDRESS 0x2000000
#define SYSTEMCONFIG_REG_OFFSET 0x8
#define SYSINTERRUPT_REG_OFFSET 0x20

#define NUM_SOURCES 8
#define NUM_CONTEXTS 2

void assert_vm_off()
{
    uint64_t matp, satp;
    asm volatile ("csrr %[reg], matp\n" : [reg] "=r" (matp)::);
    asm volatile ("csrr %[reg], satp\n" : [reg] "=r" (satp)::);

    if (matp != 0 || satp != 0) C_TEST_FAIL;

}

typedef struct {
    uint64_t mcause;
    uint64_t mtval;
    uint64_t mepc;
    uint64_t mstatus;
} trap_info_t;

volatile trap_info_t g_last_trap = {0, 0, 0, 0};

volatile uint32_t set_interrupt_source = 0;
volatile uint32_t expected_claim_value = 0;
volatile uint32_t expected_pending_value = 0;
volatile bool expected_interrupt = 0;

volatile uint32_t *plic_enable_register = (volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_ENABLE);
volatile uint32_t *plic_pending_register = (volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_PENDING);
volatile uint32_t *plic_claim_register = (volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_CLAIM);
volatile uint32_t *plic_threshold_register = (volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_THRESHOLD);
volatile uint32_t *plic_priority_register = (volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_PRIORITY);

volatile uint32_t *sysregs_systemconfig_register = (volatile uint32_t *)(SYSREG_BASE_ADDRESS + SYSTEMCONFIG_REG_OFFSET);
volatile uint32_t *sysregs_sysinterrupt_register = (volatile uint32_t *)(SYSREG_BASE_ADDRESS + SYSINTERRUPT_REG_OFFSET);


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

#include <stdint.h>

static inline uint32_t clear_interrupt_bit(uint32_t pending, int bit_num) {
    if (bit_num < 0 || bit_num >= 64) {
        return pending;  // Invalid bit, no change
    }
    return pending & ~(1ULL << bit_num);
}

uint32_t plic_select_interrupt(uint32_t pending_64) {
    if (pending_64 == 0) {
        return 0;
    }
    // Isolate lowest set bit (highest priority in PLIC)
    return pending_64 & -pending_64;
}

static inline int plic_select_interrupt_id(uint32_t pending) {
    if (pending == 0) {
        return -1;  // No pending interrupt
    }

    int id = 0;
    while (pending > 1) {
        pending  >>= 1;
        id++;
        if (pending & 1) break;
    }
    return id;
}

void setup_trap_vector()
{
    __asm__ __volatile__
    (
     "la t0, machine_handler\n"
    //  "ori t0, t0, 1\n"
     "csrw mtvec, t0\n"
      //enable interrupt
     "li t0, 1\n"
     "slli t0, t0, 23\n"
     "csrs mie, t0\n"
     "li t0, 1\n"
     "slli t0, t0, 11\n"
     "csrs mie, t0\n"
     "csrsi mstatus, 8\n"
     : : : "t0"
    );
}


void machine_handler()
{
    uint64_t mcause, mtval, mepc, mstatus;
    uint32_t prev_pending_val;


    volatile uint32_t pending_val = 0x0;

    volatile uint32_t claim_val = 0x0;

    asm volatile ("csrr %0, mcause" : "=r"(mcause));
    asm volatile ("csrr %0, mtval"  : "=r"(mtval));
    asm volatile ("csrr %0, mepc"   : "=r"(mepc));
    asm volatile ("csrr %0, mstatus": "=r"(mstatus));

    g_last_trap.mcause  = mcause;
    g_last_trap.mtval   = mtval;
    g_last_trap.mepc    = mepc;
    g_last_trap.mstatus = mstatus;

    if (!expected_interrupt) C_TEST_FAIL;

    if (mcause == 0x800000000000000b) { // machine external interrupt
        asm volatile (
        //clear pending interrupt (will not work mip external int bit is read only)
        "li t0, 1\n"
        "slli t0, t0, 11\n"
        "csrc mip, t0\n"
        );
        pending_val = *plic_pending_register;
        FENCE;
        prev_pending_val = pending_val;
        if (pending_val != expected_pending_value) {
            C_TEST_FAIL;
        }
        claim_val = *plic_claim_register;
        FENCE;
        if (claim_val != expected_claim_value) {
            C_TEST_FAIL;
        }
        // writing to complete
        *plic_claim_register = claim_val;
        FENCE;
        pending_val = *plic_pending_register;
        while (pending_val == prev_pending_val){
            pending_val = *plic_pending_register;
            FENCE;
        }

        expected_pending_value = pending_val;
        expected_claim_value = plic_select_interrupt_id(pending_val);

        if (pending_val != 0) {
            expected_interrupt = 1;
        } else {
            expected_interrupt = 0;
        }

    }
    else {
        C_TEST_FAIL;
    }


    asm volatile ("csrw mepc, %0" :: "r"(mepc+4));
}

typedef enum {
    MODE_U = 0,
    MODE_S = 1,
    MODE_D = 2,
    MODE_M = 3
} priv_mode_t;


void check_plic_registers(void) {

    uint64_t source = 0;
    uint64_t context = 0;
    for (source=1; source < NUM_SOURCES; source++) {
        plic_priority_register=(volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_PRIORITY + source*4);
        if (*plic_priority_register != 1){
            C_TEST_FAIL;
        }
    }
    plic_priority_register = (volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_PRIORITY);

    for (context=0; context < NUM_CONTEXTS; context++) {
        plic_threshold_register=(volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_THRESHOLD + context*0x1000);
        if (*plic_threshold_register != 0){
            C_TEST_FAIL;
        }
    }
    plic_threshold_register = (volatile uint32_t *)(PLIC_BASE_ADDRESS + PLIC_THRESHOLD);

}

int main()
{
    assert_vm_off();

    setup_trap_vector();

    C_TEST_START;

    volatile uint64_t idle_var = 0;

    uint64_t thread_id = get_thread_id();

    uint64_t minion_id = get_minion_id();

    if (thread_id != 0) {
        C_TEST_PASS;
    }

    if (minion_id != 0) {
        C_TEST_PASS;
    }

    uint32_t enable_val = 0x78;

    // check_plic_registers();

    *plic_enable_register = enable_val;

    uint32_t payload = 0x08; //
    set_interrupt_source = payload;
    expected_pending_value = payload << 1;
    expected_interrupt = 1;
    expected_claim_value = plic_select_interrupt_id(payload<<1);
    uint64_t validation1_val = ((uint64_t)DIAG_UEI << (uint64_t)DIAG_UEI_SHIFT) | (payload);

    ///
    volatile uint32_t system_config_read_val = 0;
    volatile uint32_t system_config_write_val = 0;

    system_config_read_val = *sysregs_systemconfig_register;
    FENCE;
    system_config_write_val = system_config_read_val | 0x1;
    *sysregs_systemconfig_register = system_config_write_val;
    FENCE;
    *sysregs_sysinterrupt_register = 0x1;
    FENCE;

    ///
    __asm__ __volatile__ (
    "mv  a7, %[val]\n\t" // Expected value
    "csrw 0x8d1, a7\n\t" // write to validation1
    //"wfi\n\t" // wait for external plic interrupt
    "nop\n\t"
    "nop\n\t"
    //  "%=: \n\t"
     :
     :[val] "r" (validation1_val)
     : "memory", "a7"
    );
    //idle loop
    for (int i=0; i<1000; i++) {
        idle_var++;
    }

    C_TEST_PASS;
}
