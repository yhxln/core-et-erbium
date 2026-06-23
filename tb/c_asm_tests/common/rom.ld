/* Script for -z combreloc */
/* Copyright (C) 2014-2025 Free Software Foundation, Inc.
   Copying and distribution of this script, with or without modification,
   are permitted in any medium without royalty provided the copyright
   notice and this notice are preserved.  */

/* -------------------------------------------------------------------------- */
/* Memory regions                                                             */
/* -------------------------------------------------------------------------- */
MEMORY
{
    bootrom (rx)  : ORIGIN = 0x02008000, LENGTH = 0x400   /* 1 KB */
    rom     (rwx) : ORIGIN = 0x02008400, LENGTH = 0x1800  /* free region */
    stack   (rw)  : ORIGIN = 0x02009C00, LENGTH = 0x400   /* 1 KB */
}

ENTRY(_boot)

/* -------------------------------------------------------------------------- */
/* Sections                                                                   */
/* -------------------------------------------------------------------------- */
SECTIONS
{
    /* Boot ROM at the top of the SRAM */
    .bootrom :
    {
        *(.bootrom)
    } > bootrom

    /* All executable code goes into SRAM */
    .text :
    {
        *(.text)
        *(.text.*)
    } > rom

    /* Read‑only data */
    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > rom

    /* Initialized data */
    .data :
    {
        *(.data)
        *(.data.*)
    } > rom

    /* Small data (requires GP) */
    .sdata :
    {
        __global_pointer$ = . + 0x400;   /* required for RISC‑V */
        *(.sdata)
        *(.sdata.*)
    } > rom

    /* Uninitialized data */
    .bss (NOLOAD) :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > rom

    /* Stack region at the end of the SRAM */
    .stack (NOLOAD) :
    {
        . = ALIGN(16);
        *(.stack)
    } > stack
}
