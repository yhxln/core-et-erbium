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


// This is an example of how to use the HAL in c_asm_tests/include/hal_cpu_mm.h
// Please notice this is an example, there are better ways to send credits like
// the functions in fcc.h

#include "et_test_common.h"
#include "minion.h"
#include "cpu_regs.h"

int main()
{
    C_TEST_START;

    uint64_t hid = get_hart_id();
    if (hid == 0ULL)
    {
        DECL_REGMAP(cpu_regs);
        cpu_regs->cpu_registers.User_cpu.CREDINC0.w = -1LL;
        cpu_regs->cpu_registers.User_cpu.CREDINC2.w = -1LL;
    }
    wait_for_credit(0);
    C_TEST_PASS;
}
