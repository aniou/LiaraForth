# 64tass port of Liara Forth, an "initial" ANSI(ish) Forth for the W65C265SXB (65816 CPU)

## notes about 64tass version

This is a conversion to [64tass assembler](http://tass64.sourceforge.net/) format,
created during work on Liara port to [C256 Foenix platform](https://c256foenix.com/).

At this moment code is able to run in - not released yet - my go65c816 emulator:

Liara Forth was created by [Scot W. Stevenson](https://github.com/scotws/LiaraForth).

![liara in go65c816](https://asciinema.org/a/lEH7boZq2BEuQB7deRrtC5giX.png)(https://asciinema.org/a/lEH7boZq2BEuQB7deRrtC5giX)

## original README

Liara Forth is an ANSI-orientated Forth for the W65C265SXB ("265SXB")
single-board computer that will work with out of the box as a "first Forth".

The 265SXB is an engineering development board -- roughly like the Raspberry Pi
-- produced by the Western Design Center (WDC). It is based on the W65C265S
microcontroler, which in turn has a 65816 microprocessor (MPU) at its core, the
8/16-bit hybrid "big sibling" of the famous 6502 MPU that powered classic
computers such as the VIC-20 and Apple II. The 265SXB is one of the easiest
ways to get started with a 65816 system.

This project is currently in the ALPHA stage. ALPHA means that "pretty much
everything is there, and some of it even does what it is supposed to". Use, as
always, at your own risk. There is further information docs/MANUAL.md . 

There is a discussion thread for Liara Forth [at
6502.org](http://forum.6502.org/viewtopic.php?f=9&t=3649).

