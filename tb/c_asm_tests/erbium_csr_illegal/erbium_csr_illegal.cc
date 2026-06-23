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

#define CSRRW(OUT, NAME, VAL)                   \
__asm__ __volatile__(                           \
    "csrrw %[out], " #NAME ", %[val]\n"         \
    "ebreak"                                    \
    : [out] "=r" (OUT)                          \
    : [val] "r" (VAL)                           \
    :                                           \
    );

#define TEST_CSR(NAME) CSRRW(out, NAME, in)
#define TEST_CSR_T0(NAME) if (get_thread_id() == 0) {CSRRW(out, NAME, in)}


extern "C" void test_mtrap_vector();


extern "C" uint64_t test_mtrap_handler(uint64_t cause, uint64_t epc, uint64_t tval, uint64_t hart)
{
    (void) tval;
    (void) hart;
    if (cause == MINION_XCTP_CAUSE_ENV_CALL_FROM_M_MODE) {C_TEST_FAIL;} // CSR didn't raise illegal exception
    else if (cause == MINION_XCTP_CAUSE_ILLEGAL_INST) {epc+= 8;} // Skip CSR + ecall
    else {C_TEST_FAIL;} // Unexpected exception

    return epc;
}

void set_trap_vector()
{
    void (*mtvec_ptr)(void) = &test_mtrap_vector;
    __asm__ __volatile__ (
        "csrw mtvec, %[mtvec]\n\t"
        :
        :[mtvec] "r" (mtvec_ptr)
        :
  );
}

int main()
{

    set_trap_vector();
    C_TEST_START;

    uint64_t out = 0;
    uint64_t in = -1;
    TEST_CSR(portctrl0)
    TEST_CSR(portctrl1)
    TEST_CSR(portctrl2)
    TEST_CSR(portctrl3)
    TEST_CSR(porthead0)
    TEST_CSR(porthead1)
    TEST_CSR(porthead2)
    TEST_CSR(porthead3)
    TEST_CSR(portheadnb0)
    TEST_CSR(portheadnb1)
    TEST_CSR(portheadnb2)
    TEST_CSR(portheadnb3)
    TEST_CSR(tensor_load_l2) // Official name is tensor_load_l2scp
    TEST_CSR(tex_send)

    C_TEST_PASS
}
