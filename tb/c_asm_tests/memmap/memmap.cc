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

extern "C" void test_mtrap_vector();
extern "C" __attribute__((section(".text"))) uint64_t test_mtrap_handler(uint64_t cause, uint64_t epc, uint64_t tval, uint64_t hart) {
   (void) tval;
   (void) hart;
   (void) cause;

   // Unexpected exception
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

   uint64_t tid;
   uint64_t data;
   tid = get_thread_id();

   // Setup machine trap vector
   set_trap_vector();

   // Enable QSPI
   set_system_config_qspi_enable(1);

   if (tid == 0) {
   // Test System registers
   data = *((volatile uint32_t*)0x02000000ULL); // Read Version from System registers
   //et_printf_long("INFO: Read from System registers: %lx\n", data);
   FENCE;

   // Test MRAM registers
   data = *((volatile uint64_t*)0x02001000ULL); // Read from MRAM registers
   //et_printf_long("INFO: Read from MRAM registers: %lx\n", data);
   FENCE;
   // Test I2C registers
   data = *((volatile uint32_t*)0x02002000ULL); // Read from I2C registers
   //et_printf_long("INFO: Read from I2C registers: %lx\n", data);
   FENCE;

   // Test QSPI registers
   data = *((volatile uint32_t*)0x02003000ULL); // Read from QSPI registers
   //et_printf_long("INFO: Read from QSPI registers: %lx\n", data);
   FENCE;

   // Test UART registers
   //data = *((volatile uint32_t*)0x02004000ULL); // Read from UART registers
   //et_printf_long("INFO: Read from UART registers: %lx\n", data);
   //FENCE;

   // Test Bootrom
   data = *((volatile uint64_t*)0x02008000ULL); // Read from Bootrom
   //et_printf_long("INFO: Read from Bootrom: %lx\n", data);
   FENCE;

   // Test SRAM
   data = *((volatile uint64_t*)0x0200C000ULL); // Read from SRAM
   //et_printf_long("INFO: Read from SRAM: %lx\n", data);
   FENCE;

   // Test xSPI
   //data = *((volatile uint64_t*)0x0200F000ULL); // Read from xSPI
   //et_printf_long("INFO: Read from xSPI: %lx\n", data);
   //FENCE;

   // Test NIC config
   data = *((volatile uint32_t*)0xFE000000ULL); // Read from NIC config
   //et_printf_long("INFO: Read from NIC config: %lx\n", data);
   FENCE;

   // Test MRAM
   data = *((volatile uint64_t*)0x40000000ULL); // Read from MRAM
   et_printf_long("INFO: Read from MRAM: %lx\n", data);
   FENCE;
   }

   C_TEST_PASS;
   return 0;
}
