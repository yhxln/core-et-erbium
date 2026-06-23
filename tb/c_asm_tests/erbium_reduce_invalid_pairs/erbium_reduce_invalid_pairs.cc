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
#include "tensors.h"

void test_reduce_invalid();
void test_reduce_valid();


int main()
{
    setup_mtrap_vector();

    C_TEST_START;

    // Tensor reduce are only valid for thread 0
    if (get_thread_id() != 0) C_TEST_PASS;

    // Test invalid combination in thread 0
    if (get_hart_id() == 0) {
        test_reduce_invalid();
    }

    // Test valid combinations in 8 thread 0 harts
    test_reduce_valid();

    C_TEST_PASS
}
