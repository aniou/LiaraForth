; Definitions for Liara Forth for the W65C265SXB
; Scot W. Stevenson <scot.stevenson@gmail.com>
; First version: 01. Apr 2016
; This version: 09. June 2017

; This file is included by liaraforth.tasm

; Originally this code was written in Typist's Assembler Notation for
; the 65c02/65816, see docs/MANUAL.md for more information
;
; converted to 64tass format by Piotr Meyer <aniou@smutek.pl>, Aug 2019


; I/O facilities are handled in the separate kernel files. The definitions for
; multitasking are preliminary and will probably change

; ===================================================================
; MEMORY MAP 
; We reuse the memory that the Mensch Monitor had been using

        ; TODO add any extra RAM in other banks
        ; TODO add stuff for multitasking

        ;  00:0000  +-------------------+  ram-start, dpage, user0
        ;           |                   |
        ;           |  ^  Data Stack    |  <-- dsp
        ;           |  |                |
        ;  00:0100  +-------------------+  dsp0, stack
        ;           |                   |
        ;           |  ^  Return Stack  |  <-- rsp 
        ;           |  |                |
        ;  00:0200  +-------------------+  rsp0, buffer, buffer0
        ;           |  |                |
        ;           |  v  Input Buffer  |
        ;           |                   |
        ;  00:0300  +-------------------+  cp0
        ;           |  |                |
        ;           |  v  Dictionary    |  <-- cp
        ;           |                   |
        ;   (...)   ~~~~~~~~~~~~~~~~~~~~~
        ;           |                   |
        ;           |                   |
        ;  00:7fff  +-------------------+  ram-end

; Hard physical addresses
ram_start  = $0000		; start of installed RAM
ram_end    = $8000-1		; end of 32k installed RAM

; Soft physical addresses
dpage      = ram_start		; direct page:       0000 - 00ff
stack      = dpage+$0100	; return stack area: 0100 - 01ff
buffer0    = stack+$0100	; buffer areas:      0200 - 02ff

; Defined locations
user0      = dpage		; user and system variables 
dsp0       = stack-1		; initial Data Stack Pointer:   00ff
stack0     = buffer0-1		; initial Return Stack Pointer: 01ff

; Buffers
bsize      = $0080		; size of input/output buffers
buffer1    = buffer0+bsize	; output buffer 0280 (UNUSED)

; Dictionary RAM
cp0        = buffer1+bsize	; Dictionary starts after last buffer
cp_end     = code0-1		; Last RAM byte available

; Other locations
padoffset  = $00ff		; offset from CP to PAD (holds number strings)


; ===================================================================
; DIRECT PAGE ADDRESSES

; All are one cell (two bytes) long to prevent weird errors
; TODO rewrite with USER variables
cp        = user0+00		; Compiler Pointer, 2 bytes
dp        = user0+02		; Dictionary Pointer, 2 bytes
workword  = user0+04		; nt (not xt) of word being compiled
insrc     = user0+06		; Input Source for SOURCE-ID
cib       = user0+08		; Address of current input buffer
ciblen    = user0+10		; Length of current input buffer
toin      = user0+12		; Pointer to CIB (>IN in Forth)
output    = user0+14		; Jump target for EMIT
input     = user0+16		; Jump target for KEY
havekey   = user0+18		; Jump target for KEY?
state     = user0+20		; STATE: -1 compile, 0 interpret
base      = user0+22		; Radix for number conversion
tohold    = user0+24		; Pointer for formatted output 
tmpbranch = user0+26		; temp storage for 0BRANCH, BRANCH only
tmp1      = user0+28		; Temporary storage
tmp2      = user0+30		; Temporary storage
tmp3      = user0+32		; Temporary storage
tmpdsp    = user0+34		; Temporary DSP (X) storage, 2 bytes
tmptos    = user0+36		; Temporary TOS (Y) storage, 2 bytes
nc_limit  = user0+38		; Holds limit for Native Compile size
scratch   = user0+40		; 8 byte scratchpad (see UM/MOD)


; ===================================================================
; HELPER DEFINITIONS

; ASCII characters
AscCC   = $03 		; break (Control-C) ASCII character
AscBELL = $07 		; ACSCII bell sound
AscBS   = $08 		; backspace ASCII character
AscLF   = $0a 		; line feed ASCII character
AscCR   = $0d 		; carriage return ASCII character
AscCN   = $0e 		; ASCII CNTR-n (for next command)
AscCP   = $10 		; ASCII CNTR-p (for previous command)
AscESC  = $1b 		; Escape ASCII character
AscSP   = $20 		; space ASCII character
AscDEL  = $7f 		; DEL ASCII character

; Dictionary flags. The first four bits are currently unused
CO = $0001		; Compile Only
AN = $0002		; Always Native Compile
IM = $0004		; Immediate Word
NN = $0008		; Never Native Compile

