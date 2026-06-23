# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright (c) 2026 Ainekko, Co.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#=========================================================================
# Bootrom code for Minion core
#=========================================================================

#ifndef STACK_BASE
#define STACK_BASE 0x41000000
#endif
#ifndef STACK_SIZE_LOG2
#define STACK_SIZE_LOG2 14
#endif
#ifndef STACK_SHIRE_OFFSET
#define STACK_SHIRE_OFFSET 0
#endif

  .section .bootrom, "ax", @progbits
  .global _boot
  .extern program_prcm

_boot:
  # Setup Validation CSR to indicate Start of Boot
  li   a7, 0xDEAD0001;
  csrw validation0, a7;
  # init some csr regs
  csrwi satp, 0
  csrr  t0, mstatus
  li    t1, 0x6000
  or    t0, t0, t1
  csrw  mstatus, t0 # set fs=11 (dirty)
  csrrw x0, fcsr, x0
  csrrw x0, mip, x0
  csrwi tensor_mask, 0
  csrwi tensor_conv_size, 0
  csrwi tensor_conv_ctrl, 0
  # set the stack pointer, different for each thread
  csrr  a1, mhartid
  slli  a1, a1, STACK_SIZE_LOG2
  li    sp, STACK_BASE
  sub   sp, sp, a1
  # Offset stack pointer for performance for each shire
  addi  x31, x0, -STACK_SHIRE_OFFSET
  csrr  x30, mhartid
  andi  x30, x30, -64
  and   x31, x30, x31
  add   sp, sp, x31

  call program_prcm

#####################################################################
# Bus error interrupt enable + trap vector                          #
#####################################################################

  # enable bus error interrupt (ID 23)
  li    t0, (1 << 23)
  csrs  mie, t0

  # enable global machine interrupts (MSTATUS.MIE = bit 3)
  li    t0, (1 << 3)
  csrs  mstatus, t0

  # install machine trap vector
  la    t0, mtrap_vector
  csrw  mtvec, t0

###################################################################

  addi x1,  x0, 0
  addi x3,  x0, 0
  addi x4,  x0, 0
  addi x5,  x0, 0
  addi x6,  x0, 0
  addi x7,  x0, 0
  addi x8,  x0, 0
  addi x9,  x0, 0
  addi x10, x0, 0
  addi x11, x0, 0
  addi x12, x0, 0
  addi x13, x0, 0
  addi x14, x0, 0
  addi x15, x0, 0
  addi x16, x0, 0
  addi x17, x0, 0
  addi x18, x0, 0
  addi x19, x0, 0
  addi x20, x0, 0
  addi x21, x0, 0
  addi x22, x0, 0
  addi x23, x0, 0
  addi x24, x0, 0
  addi x25, x0, 0
  addi x26, x0, 0
  addi x27, x0, 0
  addi x28, x0, 0
  addi x29, x0, 0
  addi x30, x0, 0
  addi x31, x0, 0

  fcvt.s.w f0,  x0
  fcvt.s.w f1,  x0
  fcvt.s.w f2,  x0
  fcvt.s.w f3,  x0
  fcvt.s.w f4,  x0
  fcvt.s.w f5,  x0
  fcvt.s.w f6,  x0
  fcvt.s.w f7,  x0
  fcvt.s.w f8,  x0
  fcvt.s.w f9,  x0
  fcvt.s.w f10, x0
  fcvt.s.w f11, x0
  fcvt.s.w f12, x0
  fcvt.s.w f13, x0
  fcvt.s.w f14, x0
  fcvt.s.w f15, x0
  fcvt.s.w f16, x0
  fcvt.s.w f17, x0
  fcvt.s.w f18, x0
  fcvt.s.w f19, x0
  fcvt.s.w f20, x0
  fcvt.s.w f21, x0
  fcvt.s.w f22, x0
  fcvt.s.w f23, x0
  fcvt.s.w f24, x0
  fcvt.s.w f25, x0
  fcvt.s.w f26, x0
  fcvt.s.w f27, x0
  fcvt.s.w f28, x0
  fcvt.s.w f29, x0
  fcvt.s.w f30, x0
  fcvt.s.w f31, x0

  li zero, 0xf
  mova.m.x zero

  # Setup Validation CSR to indicate End of Boot
  li   a7, 0xDEAD0002;
  csrw validation0, a7;

  la a1, _start
  jalr x0, a1

#####################################################################
# Machine trap vector + TEST_FAIL                                   #
#####################################################################

  .section .text
  .globl mtrap_vector
mtrap_vector:
  csrr  s1, mtval
  csrr  s2, mcause
  csrr  s3, mepc
  addi  s3, s3, 4

  # TEST_FAIL
  fence
  lui   a7, 0x50BAD
  csrw  0x8d0, a7
1:
  wfi
  j     1b
