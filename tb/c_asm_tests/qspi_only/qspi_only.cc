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

#include <stdio.h>
#include <stdlib.h>
#include <cstdint>
#include "macros.h"
#include "minion.h"
#include "et_test_common.h"
#include "system_reg.h"
#include "qspi_reg.h"
#include "cpu_regs.h"

extern "C" void test_mtrap_vector();
extern "C" __attribute__((section(".text"))) uint64_t test_mtrap_handler(uint64_t cause, uint64_t epc, uint64_t tval, uint64_t hart) {
   (void) tval;
   (void) hart;
   (void) cause;
   C_TEST_FAIL;
   return epc;
}

void set_trap_vector()
{
    void (*mtvec_ptr)(void) = &test_mtrap_vector;
    __asm__ __volatile__ ("csrw mtvec, %[mtvec]\n\t" : :[mtvec] "r" (mtvec_ptr) :);
}

int main() {
   C_TEST_START;

   uint64_t hid;
   uint64_t data;
   hid = get_hart_id();

   // Setup machine trap vector
   set_trap_vector();

   // Enable QSPI
   set_system_config_qspi_enable(1);
   //set_qspi_cr_qspi_enable(1);

   if (hid == 0) {
      // Workaround
      DECL_REGMAP(cpu_regs);
      cpu_regs->qspi_registers.CR.w = 0x1;

      // Test xSPI
      data = *((volatile uint32_t*)0x02003000ULL); // Read from xSPI
      FENCE;
      et_printf_long("INFO: Read from QSPI: %lx\n", data);
   }

   C_TEST_PASS;
   return 0;
}
