; Dictionary Headers for Liara Forth for the W65C265SXB
; Scot W. Stevenson <scot.stevenson@gmail.com>
; First version: 05. Dec 2016
; This version: 18. September 2017
;
; Originally this code was written in Typist's Assembler Notation for
; the 65c02/65816, see docs/MANUAL.md for more information
;
; converted to 64tass format by Piotr Meyer <aniou@smutek.pl>, Aug 2019

; Dictionary headers are kept separately from the code, which allows various
; tricks in the code. We roughly follow the Gforth terminology: The Execution
; Token (xt) is the address of the first byte of a word's code that can be,
; uh, executed; the Name Token (nt) is a pointer to the beginning of the
; word's header in the Dictionary. There, the link to the next word in the
; Dictionary is always one cell down from the current word's own nt. In the code
; itself, we use "nt_<WORD>" for the nt and "xt_<WORD>" for the xt. 
;
; This gives us the following header structure:
;
;              8 bit     8 bit
;               LSB       MSB
; nt_word ->  +--------+--------+
;             | Length | Status |
;          +2 +--------+--------+
;             | Next Header     | -> nt_next_word
;          +4 +-----------------+
;             | Start of Code   | -> xt_word 
;          +6 +-----------------+
;             | End of Code     | -> z_word
;          +8 +--------+--------+
;             | Name   |        |
;             +--------+--------+
;             |        |        |
;             +--------+--------+
;             |        |  ...   | (name string does not end with a zero)
;          +n +--------+--------+
;
; The Status Byte is created by adding the flags defined in
; definitions.tasm. 
;
;       CO - Compile Only
;       IM - Immediate Word
;       NN - Never Native Compile 
;       AN - Always Native Compile (may not be called by JSR)

; Note there are currently four bits unused. By default, all words can be
; natively compiled (compiled inline) or as a subroutine jump target; the system
; decides which variant to use based on a threshold the user can set. The NN
; flag forbids native compiling, the AN flag forces it.  

; The last word (top word in code) is always BYE. It is marked as the last word
; by its value of 0000 in its Next Header field. The words are sorted with the
; more common ones first (further down in code) so they are found earlier.
; Anything to do with output comes later (further up) because things will
; always be slow if there is a human involved.

nt_bye          .byte 03     ; length of word string
        .byte 00     ; status byte
        .word 0000   ; next word in dictionary, 0000 signals end
        .word xt_bye ; start of code, the xt of this word
        .word z_bye  ; end of code (points to RTS)
        .text "bye"  ; word name, always lower case

nt_cold         .byte 4, 00
        .word nt_bye, xt_cold, z_cold
        .text "cold"  

nt_word         .byte 4, 00
        .word nt_cold, xt_word, z_word
        .text "word"

nt_find         .byte 4, 00
        .word nt_word, xt_find, z_find
        .text "find"

nt_aligned      .byte 7, 00
        .word nt_find, xt_aligned, z_aligned
        .text "aligned"

nt_align        .byte 5, 00
        .word nt_aligned, xt_align, z_align
        .text "align"

nt_wordsnsizes  .byte $0b, 00
        .word nt_align, xt_wordsnsizes, z_wordsnsizes
        .text "words&sizes"

nt_words        .byte 5, 00
        .word nt_wordsnsizes, xt_words, z_words
        .text "words"

nt_unloop       .byte 6, CO
        .word nt_words, xt_unloop, z_unloop
        .text "unloop"

nt_pploop       .byte 7, CO
        .word nt_unloop, xt_pploop, z_pploop
        .text "(+loop)"

nt_ploop        .byte 5, IM+CO
        .word nt_pploop, xt_ploop, z_ploop
        .text "+loop"

nt_loop         .byte 4, IM+CO
        .word nt_ploop, xt_loop, z_loop
        .text "loop"

nt_leave        .byte 5, CO
        .word nt_loop, xt_leave, z_leave
        .text "leave"

nt_exit         .byte 4, CO
        .word nt_leave, xt_exit, z_exit
        .text "exit"

nt_recurse      .byte 7, IM+CO
        .word nt_exit, xt_recurse, z_recurse
        .text "recurse"

nt_j            .byte 1, CO
        .word nt_recurse, xt_j, z_j
        .byte 'j'

nt_i            .byte 1, CO
        .word nt_j, xt_i, z_i
        .byte 'i'

nt_pqdo         .byte 5, CO+AN
        .word nt_i, xt_pqdo, z_pqdo
        .text "(?do)"

nt_pdo          .byte 4, CO+AN
        .word nt_pqdo, xt_pdo, z_pdo
        .text "(do)"

nt_qdo          .byte 3, IM+CO	; may not be Native Compile
        .word nt_pdo, xt_qdo, z_qdo
        .text "?do"

nt_do           .byte 2, IM+CO	; may not be Native Compile
        .word nt_qdo, xt_do, z_do
        .text "do"

nt_marker       .byte 6, IM
        .word nt_do, xt_marker, z_marker
        .text "marker"

nt_wordsize     .byte 8, 00
        .word nt_marker, xt_wordsize, z_wordsize
        .text "wordsize"

nt_pick         .byte 4, 00
        .word nt_wordsize, xt_pick, z_pick
        .text "pick"

nt_bell         .byte 4, 00
        .word nt_pick, xt_bell, z_bell
        .text "bell"

nt_chars        .byte 5, 00
        .word nt_bell, xt_chars, z_chars
        .text "chars"

nt_cellplus     .byte 5, 00
        .word nt_chars, xt_cellplus, z_cellplus
        .text "cell+"

nt_charplus     .byte 5, 00    	; uses code of 1+
        .word nt_cellplus, xt_one_plus, z_one_plus
        .text "char+"

nt_decimal      .byte 7, 00
        .word nt_charplus, xt_decimal, z_decimal
        .text "decimal"

nt_hex          .byte 3, 00
        .word nt_decimal, xt_hex, z_hex
        .text "hex"

nt_unused       .byte 6, 00
        .word nt_hex, xt_unused, z_unused
        .text "unused"

nt_page         .byte 4, 00
        .word nt_unused, xt_page, z_page
        .text "page"

nt_at_xy        .byte 5, 00
        .word nt_page, xt_at_xy, z_at_xy
        .text "at-xy"

nt_tworfetch    .byte 3, NN	; not natively compiled (yet)
        .word nt_at_xy, xt_tworfetch, z_tworfetch
        .text "2r@"

nt_2variable    .byte 9, 00
        .word nt_tworfetch, xt_2variable, z_2variable
        .text "2variable"

nt_dabs         .byte 4, 00
        .word nt_2variable, xt_dabs, z_dabs
        .text "dabs"

nt_dnegate      .byte 7, 00
        .word nt_dabs, xt_dnegate, z_dnegate
        .text "dnegate"

nt_dtos         .byte 3, 00
        .word nt_dnegate, xt_dtos, z_dtos
        .text "d>s"

nt_stod         .byte 3, 00
        .word nt_dtos, xt_stod, z_stod
        .text "s>d"

nt_twofromr     .byte 3, CO                 ; NC is special case
        .word nt_stod, xt_twofromr, z_twofromr
        .text "2r>"

nt_twotor       .byte 3, CO                   ; NC is special case
        .word nt_twofromr, xt_twotor, z_twotor
        .text "2>r"

nt_dminus       .byte 2, 00
        .word nt_twotor, xt_dminus, z_dminus
        .text "d-"

nt_dplus        .byte 2, 00
        .word nt_dminus, xt_dplus, z_dplus
        .text "d+"

nt_fmmod        .byte 6, 00
        .word nt_dplus, xt_fmmod, z_fmmod
        .text "fm/mod"

nt_smrem        .byte 6, 00
        .word nt_fmmod, xt_smrem, z_smrem
        .text "sm/rem"

nt_udmod        .byte 6, 00
        .word nt_smrem, xt_udmod, z_udmod
        .text "ud/mod"

nt_ummod        .byte 6, 00
        .word nt_udmod, xt_ummod, z_ummod
        .text "um/mod"

nt_star         .byte 1, 00
        .word nt_ummod, xt_star, z_star
        .byte '*'

nt_mstar        .byte 2, 00
        .word nt_star, xt_mstar, z_mstar
        .text "m*"

nt_umstar       .byte 3, 00
        .word nt_mstar, xt_umstar, z_umstar
        .text "um*"

nt_cmoveup      .byte 6, 00
        .word nt_umstar, xt_cmoveup, z_cmoveup
        .text "cmove>"

nt_cmove        .byte 5, 00
        .word nt_cmoveup, xt_cmove, z_cmove
        .text "cmove"

nt_count        .byte 5, 00
        .word nt_cmove, xt_count, z_count
        .text "count"

nt_abortq       .byte 6, CO+IM
        .word nt_count, xt_abortq, z_abortq
        .text "abort", 34	; ABORT"

nt_abort        .byte 5, NN ; TODO check flags - NC possible?
        .word nt_abortq, xt_abort, z_abort
        .text "abort"

nt_parse        .byte 5, 00
        .word nt_abort, xt_parse, z_parse
        .text "parse"

nt_quit         .byte 4, 00
        .word nt_parse, xt_quit, z_quit
        .text "quit"

nt_question     .byte 1, 00
        .word nt_quit, xt_question, z_question
        .byte '?'

nt_int_name     .byte 8, 00
        .word nt_question, xt_int_name, z_int_name
        .text "int>name"

nt_name_int     .byte 8, 00
        .word nt_int_name, xt_name_int, z_name_int
        .text "name>int"

nt_cr           .byte 2, 00
        .word nt_name_int, xt_cr, z_cr 
        .text "cr"

nt_fill         .byte 4, 00
        .word nt_cr, xt_fill, z_fill
        .text "fill"

nt_erase        .byte 5, 00
        .word nt_fill, xt_erase, z_erase
        .text "erase"

nt_numbermore   .byte 2, 00 ; "quoth the rumben"
        .word nt_erase, xt_numbermore, z_numbermore
        .text "#>"

nt_hold         .byte 4, 00
        .word nt_numbermore, xt_hold, z_hold
        .text "hold"

nt_hashs        .byte 2, 00 ; also known as "number-s"
        .word nt_hold, xt_hashs, z_hashs
        .text "#s"

nt_sign         .byte 4, 00
        .word nt_hashs, xt_sign, z_sign
        .text "sign"

nt_hash         .byte 1, 00  ; also known as "number-sign"
        .word nt_sign, xt_hash, z_hash
        .byte '#'

nt_lessnumber   .byte 2, 00
        .word nt_hash, xt_lessnumber, z_lessnumber
        .text "<#"

nt_bl           .byte 2, 00
        .word nt_lessnumber, xt_bl, z_bl
        .text "bl"

nt_spaces       .byte 6, 00
        .word nt_bl, xt_spaces, z_spaces
        .text "spaces"

nt_space        .byte 5, 00
        .word nt_spaces, xt_space, z_space
        .text "space"

nt_dots         .byte 2, 00
        .word nt_space, xt_dots, z_dots
        .text ".s"

nt_type         .byte 4, 00
        .word nt_dots, xt_type, z_type
        .text "type"

nt_udot         .byte 2, 00
        .word nt_type, xt_udot, z_udot
        .text "u."

nt_emit         .byte 4, 0      ; not native compile
        .word nt_udot, xt_emit, z_emit
        .text "emit"

nt_dot          .byte 1, 00
        .word nt_emit, xt_dot, z_dot
        .byte '.'

nt_pad          .byte 3, 00
        .word nt_dot, xt_pad, z_pad
        .text "pad"

nt_base         .byte 4, 00
        .word nt_pad, xt_base, z_base
        .text "base"

nt_nc_limit     .byte 8, 00
        .word nt_base, xt_nc_limit, z_nc_limit
        .text "nc-limit"

nt_input        .byte 5, 00
        .word nt_nc_limit, xt_input, z_input
        .text "input"

nt_output       .byte 6, 00
        .word nt_input, xt_output, z_output
        .text "output"

nt_evaluate     .byte 8, 00
        .word nt_output, xt_evaluate, z_evaluate
        .text "evaluate"

nt_cells        .byte 5, 00	; 2* because we have 16 bit stack
        .word nt_evaluate, xt_two_star, z_two_star
        .text "cells"

nt_dotquote     .byte 2, CO+IM
        .word nt_cells, xt_dotquote, z_dotquote
        .byte '.', 34

nt_squote       .byte 2, IM       	; not CO, see source code
        .word nt_dotquote, xt_squote, z_squote
        .byte 's', 34

nt_sliteral     .byte 8, IM+CO
        .word nt_squote, xt_sliteral, z_sliteral
        .text "sliteral"

nt_brackettick  .byte 3, IM+CO
        .word nt_sliteral, xt_brackettick, z_brackettick
        .text "[']"

nt_bracketchar  .byte 6, IM+CO
        .word nt_brackettick, xt_bracketchar, z_bracketchar
        .text "[char]"

nt_literal      .byte 7, IM+CO
        .word nt_bracketchar, xt_literal, z_literal
        .text "literal"

nt_never_compile .byte $0d, 00
        .word nt_literal, xt_never_compile, z_never_compile
        .text "never-compile"

nt_compile_only .byte $0c, 00
        .word nt_never_compile, xt_compile_only, z_compile_only
        .text "compile-only"

nt_immediate    .byte 9, 00
        .word nt_compile_only, xt_immediate, z_immediate
        .text "immediate"

nt_postpone     .byte 8, IM+CO
        .word nt_immediate, xt_postpone, z_postpone
        .text "postpone"

nt_rightbracket .byte 1, 00
        .word nt_postpone, xt_rightbracket, z_rightbracket
        .byte ']'

nt_leftbracket  .byte 1, IM+CO
        .word nt_rightbracket, xt_leftbracket, z_leftbracket
        .byte '['

nt_latestnt     .byte 8, 00
        .word nt_leftbracket, xt_latestnt, z_latestnt
        .text "latestnt"

nt_latestxt     .byte 8, 00
        .word nt_latestnt, xt_latestxt, z_latestxt
        .text "latestxt"

nt_dtrailing    .byte 9, 00
        .word nt_latestxt, xt_dtrailing, z_dtrailing
        .text "-trailing"

nt_slashstring  .byte 7, 00
        .word nt_dtrailing, xt_slashstring, z_slashstring
        .text "/string"

nt_zbranch      .byte 7, IM+CO + NN
        .word nt_slashstring, xt_zbranch, z_zbranch
        .text "0branch"

nt_branch       .byte 6, IM+CO + NN
        .word nt_zbranch, xt_branch, z_branch
        .text "branch"

nt_again        .byte 5, IM+CO
        .word nt_branch, xt_again, z_again
        .text "again"

nt_begin        .byte 5, IM+CO
        .word nt_again, xt_begin, z_begin
        .text "begin"

nt_compilecomma .byte $08, CO
        .word nt_begin, xt_compilecomma, z_compilecomma
        .text "compile,"

nt_semicolon    .byte 1, CO+IM
        .word nt_compilecomma, xt_semicolon, z_semicolon
        .byte ';'

nt_colon        .byte 1, 0
        .word nt_semicolon, xt_colon, z_colon
        .text ":"

nt_allot        .byte 5, 00
        .word nt_colon, xt_allot, z_allot
        .text "allot"

nt_defer        .byte 5, 00
        .word nt_allot, xt_defer, z_defer
        .text "defer"

nt_tobody       .byte 5, 00
        .word nt_defer, xt_tobody, z_tobody
        .text ">body"

nt_does         .byte 5, IM+CO
        .word nt_tobody, xt_does, z_does
        .text "does>"

nt_create       .byte 6, 0
        .word nt_does, xt_create, z_create
        .text "create"

nt_name_string  .byte $0b, 00
        .word nt_create, xt_name_string, z_name_string
        .text "name>string"

nt_2dup         .byte 4, 00
        .word nt_name_string, xt_2dup, z_2dup
        .text "2dup"

nt_abs          .byte 3, 00
        .word nt_2dup, xt_abs, z_abs
        .text "abs"

nt_state        .byte 5, 00
        .word nt_abs, xt_state, z_state
        .text "state"

nt_to_in        .byte 3, 00
        .word nt_state, xt_to_in, z_to_in
        .text ">in"

nt_source       .byte 6, 00
         .word nt_to_in, xt_source, z_source
         .text "source"

nt_depth        .byte 5, 00
        .word nt_source, xt_depth, z_depth
        .text "depth"

nt_to           .byte 2, 00
        .word nt_depth, xt_to, z_to
        .text "to"

nt_value        .byte 5, 00  ; uses routines of CONSTANT
        .word nt_to, xt_constant, z_constant
        .text "value"

nt_constant     .byte 8, 00
        .word nt_value, xt_constant, z_constant
        .text "constant"

nt_variable     .byte 8, 00
        .word nt_constant, xt_variable, z_variable
        .text "variable"

nt_tick         .byte 1, 00
        .word nt_variable, xt_tick, z_tick
        .byte $27	; hex for "'"

nt_move         .byte 4, 00
        .word nt_tick, xt_move, z_move
        .text "move"

nt_min          .byte 3, 00
        .word nt_move, xt_min, z_min
        .text "min"

nt_max          .byte 3, 00
        .word nt_min, xt_max, z_max
        .text "max"

nt_negate       .byte 6, 00
        .word nt_max, xt_negate, z_negate
        .text "negate"

nt_invert       .byte 6, 00
        .word nt_negate, xt_invert, z_invert
        .text "invert"

nt_char         .byte 4, 00
        .word nt_invert, xt_char, z_char
        .text "char"

nt_rshift       .byte 6, 00
        .word nt_char, xt_rshift, z_rshift
        .text "rshift"

nt_xor          .byte 3, 00
        .word nt_rshift, xt_xor, z_xor
        .text "xor"

nt_or           .byte 2, 00
        .word nt_xor, xt_or, z_or
        .text "or"

nt_and          .byte 3, 00
        .word nt_or, xt_and, z_and
        .text "and"

nt_lshift       .byte 6, 00
        .word nt_and, xt_lshift, z_lshift
        .text "lshift"

nt_plusstore    .byte 2, 00
        .word nt_lshift, xt_plusstore, z_plusstore
        .text "+!"

nt_c_comma      .byte 2, 00
        .word nt_plusstore, xt_c_comma, z_c_comma
        .text "c,"

nt_c_fetch      .byte 2, 00
        .word nt_c_comma, xt_c_fetch, z_c_fetch
        .text "c@"

nt_c_store      .byte 2, 00
        .word nt_c_fetch, xt_c_store, z_c_store
        .text "c!"

nt_two_star     .byte 2, 00
        .word nt_c_store, xt_two_star, z_two_star
        .text "2*"

nt_minus        .byte 1, 00
        .word nt_two_star, xt_minus, z_minus
        .byte '-'

nt_plus         .byte 1, 00
        .word nt_minus, xt_plus, z_plus
        .byte '+'

nt_one_minus    .byte 2, 00
        .word nt_plus, xt_one_minus, z_one_minus
        .text "1-"

nt_one_plus     .byte 2, 00
        .word nt_one_minus, xt_one_plus, z_one_plus
        .text "1+"

nt_zero_notequal .byte 3, 00
        .word nt_one_plus, xt_zero_notequal, z_zero_notequal
        .text "0<>"

nt_zero_more    .byte 2, 00
        .word nt_zero_notequal, xt_zero_more, z_zero_more
        .text "0>"

nt_zero_less    .byte 2, 00
        .word nt_zero_more, xt_zero_less, z_zero_less
        .text "0<"

nt_greater      .byte 1, 00
        .word nt_zero_less, xt_greater, z_greater
        .byte '>'

nt_less         .byte 1, 00
        .word nt_greater, xt_less, z_less
        .byte '<'

nt_zero_equal   .byte 2, 00
        .word nt_less, xt_zero_equal, z_zero_equal
        .text "0="

nt_not_equal    .byte 2, 00
        .word nt_zero_equal, xt_not_equal, z_not_equal
        .text "<>"

nt_equal        .byte 1, 00
        .word nt_not_equal, xt_equal, z_equal
        .byte '='

nt_false        .byte 5, 00
        .word nt_equal, xt_zero, z_zero
        .text "false"

nt_true         .byte 4, 00
        .word nt_false, xt_true, z_true
        .text "true"

nt_tonumber     .byte 7, 00	; see if actually NC
        .word nt_true, xt_tonumber, z_tonumber
        .text ">number"

nt_number       .byte 6, 00	; see if actually NC
        .word nt_tonumber, xt_number, z_number
        .text "number"

nt_two          .byte 1, 00
        .word nt_number, xt_two, z_two
        .byte '2'

nt_one          .byte 1, 00
        .word nt_two, xt_one, z_one
        .byte '1'

nt_zero         .byte 1, 00
        .word nt_one, xt_zero, z_zero
        .byte '0'

nt_find_name    .byte 9, 0
        .word nt_zero, xt_find_name, z_find_name
        .text "find-name"

nt_refill       .byte 6, 0 ; TODO check flags
        .word nt_find_name, xt_refill, z_refill
        .text "refill"

nt_parse_name   .byte 10, 0
        .word nt_refill, xt_parse_name, z_parse_name
        .text "parse-name"

nt_source_id    .byte 9, 00
        .word nt_parse_name, xt_source_id, z_source_id
        .text "source-id"

nt_comma        .byte 1, 00
        .word nt_source_id, xt_comma, z_comma
        .byte ','

nt_accept       .byte 6, 00 ; TODO check flags
        .word nt_comma, xt_accept, z_accept 
        .text "accept"

nt_keyq         .byte 4, 00
        .word nt_accept, xt_keyq, z_keyq
        .text "key?"

nt_key          .byte 3, 00
        .word nt_keyq, xt_key, z_key
        .text "key"

nt_backslash    .byte 1, 00
        .word nt_key, xt_backslash, z_backslash
        .byte '\'

nt_qdup         .byte 4, 00
        .word nt_backslash, xt_qdup, z_qdup
        .text "?dup"

nt_tuck         .byte 4, 00
        .word nt_qdup, xt_tuck, z_tuck
        .text "tuck"

nt_nip          .byte 3, 00
        .word nt_tuck, xt_nip, z_nip
        .text "nip"

nt_mrot         .byte 4, 00
        .word nt_nip, xt_mrot, z_mrot
        .text "-rot"

nt_rot          .byte 3, 00
        .word nt_mrot, xt_rot, z_rot
        .text "rot"

nt_2over        .byte 5, 00
        .word nt_rot, xt_2over, z_2over
        .text "2over"

nt_2swap        .byte 5, 00
        .word nt_2over, xt_2swap, z_2swap
        .text "2swap"

nt_execute      .byte 7, 00
        .word nt_2swap, xt_execute, z_execute
        .text "execute"

nt_here         .byte 4, 00
        .word nt_execute, xt_here, z_here
        .text "here"

nt_2drop        .byte 5, 00
        .word nt_here, xt_2drop, z_2drop
        .text "2drop"

nt_rfetch       .byte 2, 0 ; we follow Gforth in making this not CO
        .word nt_2drop, xt_rfetch, z_rfetch
        .text "r@"

nt_fromr        .byte 2, CO    ; NC is special case
        .word nt_rfetch, xt_fromr, z_fromr
        .text "r>"

nt_tor          .byte 2, CO     ; NC is special case
        .word nt_fromr, xt_tor, z_tor
        .text ">r"

nt_digitq       .byte 6, 00
        .word nt_tor, xt_digitq, z_digitq
        .text "digit?"

nt_bounds       .byte 6, 00
        .word nt_digitq, xt_bounds, z_bounds
        .text "bounds"

nt_over         .byte 4, 00
        .word nt_bounds, xt_over, z_over
        .text "over"

nt_fetch        .byte 1, 00
        .word nt_over, xt_fetch, z_fetch
        .text "@"

nt_store        .byte 1, 00
        .word nt_fetch, xt_store, z_store
        .text "!"

nt_swap         .byte 4, 00
        .word nt_store, xt_swap, z_swap
        .text "swap"

nt_dup          .byte 3, 00
        .word nt_swap, xt_dup, z_dup
        .text "dup"

; DROP is always the first entry in dictionary
nt_drop         .byte 4, 00
        .word nt_dup, xt_drop, z_drop
        .text "drop"

; END
