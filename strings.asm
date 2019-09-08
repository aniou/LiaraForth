; List of Strings for Liara Forth for the W65C265SXB
; Scot W. Stevenson <scot.stevenson@gmail.com>
; First version: 01. Apr 2016
; This version:  11. Mar 2017

; converted to 64tass format by Piotr Meyer <aniou@smutek.pl>, Aug 2019

; This file is included by liaraforth.tasm

; ===================================================================
; GENERAL

; All general strings must be zero-terminated, names start with "s_"

s_ok            .text " ok", 0             ; note space at beginning
s_compiled      .text " compiled", 0


; ===================================================================
; ERROR STRINGS

; All error strings must be zero-terminated, names start with "es_"

es_allot        .text "ALLOT out of bounds", 0
es_componly     .text "Interpreting a compile-only word", 0
es_defer        .text "DEFERed word not defined yet", 0
es_divzero      .text "Division by zero", 0
es_error        .text ">>>Error<<<", 0
es_intonly      .text "Not in interpret mode", 0
es_noname       .text "Parsing failure", 0
es_radix        .text "Digit larger than base", 0
es_refill1      .text "QUIT could not get input (REFILL returned -1)", 0
es_refill2      .text "Illegal SOURCE-ID during REFILL", 0
es_state        .text "Already in compile mode", 0
es_underflow    .text "Stack underflow", 0
es_syntax       .text "Undefined word", 0


; ===================================================================
; ANSI VT-100 SEQUENCES

vt100_page      .text AscESC, "[2J", 0       ; clear screen
vt100_home      .text AscESC, "[H", 0        ; cursor home

; go65c816 doesn't support vt terminals (yet)
;vt100_page      .text "vt100_page ", 0       ; clear screen
;vt100_home      .text "vt100_home ", 0       ; cursor home

; ===================================================================
; TESTING STRINGS

; These strings are only used during testing and are removed as Liara Forth is
; developed. All start with "tests_"

tests_prev_cmd  .text "(previous command)", 0
tests_next_cmd  .text "(next command)", 0


; ===================================================================
; ALPHABET STRINGS

; Leave alphastr as the last entry in the source code to make it easier to
; see where this section ends. This cannot be a zero-terminated string
; TODO see if we need lower

abc_str_lower   .text "0123456789abcdefghijklmnopqrstuvwyz"
abc_str_upper   .text "0123456789ABCDEFGHIJKLMNOPQRSTUVWYZ"

