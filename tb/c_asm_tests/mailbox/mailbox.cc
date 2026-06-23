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

#define PAYLOAD(a, b, c, d) \
    ( ((uint32_t)(a) << 24) | \
      ((uint32_t)(b) << 16) | \
      ((uint32_t)(c) << 8)  | \
      ((uint32_t)(d)) )

int main() {

   volatile uint32_t* mailbox0 = (uint32_t*) (0x2000000 + 0x68);
   *mailbox0 = PAYLOAD('H', 'W', '0', '0');

   C_TEST_PASS;
   return 0;
}
