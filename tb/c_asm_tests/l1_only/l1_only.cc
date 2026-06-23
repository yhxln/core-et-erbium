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

int main() {

    /* LCG */
    uint64_t seed = 12;

    uint64_t x;
    __asm__ __volatile__ ("li %[x], 164603309694725029ul" : [x] "=r" (x) : : );

    uint64_t y;
    __asm__ __volatile__ ("li %[y], 14738995463583502973ul" : [y] "=r" (y) : : );

    for (int i = 0; i < 27; i++) {
        for (int b = 0; b < 8; b++) {
            seed = (x * seed) % y;
        }
    }

    /* RV Hint */
    __asm__ __volatile__ (
        "slti x0, %[seed], 0x516"
            :
            : [seed] "r" (seed)
            :
    );

    /* Gold ref computed using sys_emu */
    uint64_t gold;
    __asm__ __volatile__ ("li %[gold], 0xb1faccfe85e59c31" : [gold] "=r" (gold) : : );

    if (seed != gold) {
        C_TEST_FAIL;
    }

    C_TEST_PASS;
    return 0;
}
