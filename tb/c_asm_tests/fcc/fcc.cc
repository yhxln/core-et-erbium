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

//
// Description : This test exercise basic Fast Credit Counter functionality
//

#include "macros.h"
#include "fcc.h"

/* Thread 0 */
#define CREDINC0 0x803400C0
#define CREDINC1 0x803400C8

/* Thread 1 */
#define CREDINC2 0x803400D0
#define CREDINC3 0x803400D8

#define MINION_MASK 0xFFFFFFFFFFFFFFFFULL

int main() {

    volatile uint64_t *fcc_th0 = (uint64_t*) CREDINC0;
    volatile uint64_t *fcc_th1 = (uint64_t*) CREDINC2;

    *fcc_th0 = MINION_MASK;
    *fcc_th1 = MINION_MASK;

    for (uint32_t j = 0; j < 16; ++j) {
       wait_for_credit(0);
    }

    // Make sure the credit counter is 0
    if (get_credit_count_nb(0) != 0) {
       C_TEST_FAIL;
    }

    C_TEST_PASS;
    return 0;
}
