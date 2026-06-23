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


#include <cstddef>
#include <cstdint>
#include "macros.h"
#include "cpu_regs.h"
#include "mem_fill.h"

constexpr uint64_t ELEMENT_ERBIUM = 68;

int main() {

    DECL_REGMAP(cpu_regs);
    void* raw = (void*) cpu_regs->ROMRAM.SRAM.mem; // workaround -Werror=address-of-packed-member

    volatile uint64_t* sram = reinterpret_cast<volatile uint64_t*>(raw);
    const size_t num_items = sizeof(cpu_regs->ROMRAM.SRAM.mem) / sizeof(uint64_t);

    mem_fill_parallel(sram, num_items, ELEMENT_ERBIUM);

    mem_verify_parallel(sram, num_items, ELEMENT_ERBIUM);

    C_TEST_PASS;
    return 0;
}
