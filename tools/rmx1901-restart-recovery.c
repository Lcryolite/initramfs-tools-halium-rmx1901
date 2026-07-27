/* SPDX-License-Identifier: GPL-2.0-or-later */

/*
 * This binary deliberately has no C runtime and no argument interface.
 * Linux AArch64 reboot(2): reboot magic values, RESTART2 command, target.
 */
__asm__(
".text\n"
".global _start\n"
".type _start, %function\n"
"_start:\n"
"  movz x0, #0xdead\n"
"  movk x0, #0xfee1, lsl #16\n"
"  movz x1, #0x1969\n"
"  movk x1, #0x2812, lsl #16\n"
"  movz x2, #0xc3d4\n"
"  movk x2, #0xa1b2, lsl #16\n"
"  adr x3, .Lrecovery\n"
"  movz x8, #142\n"
"  svc #0\n"
"  movz x0, #1\n"
"  movz x8, #93\n"
"  svc #0\n"
".Lreturned:\n"
"  b .Lreturned\n"
".size _start, . - _start\n"
".section .rodata\n"
".Lrecovery:\n"
"  .asciz \"recovery\"\n"
);
