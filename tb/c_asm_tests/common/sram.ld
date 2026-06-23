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
    bootrom (rx)  : ORIGIN = 0x0200C000, LENGTH = 0x400   /* 1 KB */
    sram    (rwx) : ORIGIN = 0x0200C400, LENGTH = 0x800   /* free region */
    stack   (rw)  : ORIGIN = 0x0200CC00, LENGTH = 0x400   /* 1 KB */
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
    } > sram

    /* Read‑only data */
    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } > sram

    /* Initialized data */
    .data :
    {
        *(.data)
        *(.data.*)
    } > sram

    /* Small data (requires GP) */
    .sdata :
    {
        __global_pointer$ = . + 0x400;   /* required for RISC‑V */
        *(.sdata)
        *(.sdata.*)
    } > sram

    /* Uninitialized data */
    .bss (NOLOAD) :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > sram

    /* Stack region at the end of the SRAM */
    .stack (NOLOAD) :
    {
        . = ALIGN(16);
        *(.stack)
    } > stack
}
