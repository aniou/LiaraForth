; Liara Forth for the W65C265SXB
; Scot W. Stevenson <scot.stevenson@gmail.com>
; First version: 01. Apr 2016
; This version: 18. Sep 2017

; Originally this code was written in Typist's Assembler Notation for 
; the 65c02/65816, see docs/MANUAL.md for more information
;
; converted to 64tass format by Piotr Meyer <aniou@smutek.pl>, Aug 2019

		.cpu "65816"
		* = $5000    ; start of code to save to built-in RAM

code0                   ; used to calculate UNUSED 

; ===================================================================
; TOP INCLUDES

		.include "macros_inc.asm"
		.include "definitions.asm"

; Hardware dependencies are isolated to a large degree in kernel files. Liara
; Forth ships with two such files: One (very ALPHA) for the crude65816 emulator,
; and one for the 265sxb board. Only use one. Which ever kernel file is used, it
; must contain at least the routines put_chr, get_chr and have_chr, which work
; on the A register

;		.include "kernel_265sxb.tasm"	 ; routines for the W65C265SXB
;		.include "kernel_emu.asm"        ; routines for crude65815 emulator
		.include "kernel_go65c816.asm"   ; routines for go65c816 emulator


; ===================================================================
; DICTIONARY ROUTINES

; Word code routines are sorted alphabetically, except for the first three
; - COLD, ABORT, and QUIT - and a few others that flow into each other. The
; byte and cycle values are calculated without the RTS instruction.

; -------------------------------------------------------------------
; COLD ( -- ) X bytes / X Cycles
; Reset the Forth system. Use BYE to return to the Mensch Monitor. 
xt_cold

                jmp reset_hardware ;  don't use JSR, jump back to start
start
;        .!native        ; these should have been handled by hardware reset
        .al
        .xl
                sei

                ; Initialize the Return Stack (65816 stack)
                ldx #stack0 ;  01ff
                txs

                ; Clear Data Stack. This is repeated in ABORT, but we have no
                ; choice if we want to load high-level words via EVALUATE
                ldy #$0000
                ldx #dsp0
                 
                ; We start out in decimal mode
                lda #$000a
                sta base

                ; We start out with smaller words with less than 20 bytes being
                ; natively compiled, because this includes words like LSHIFT and MAX. 
                lda #0020
                sta nc_limit
               
                ; set the OUTPUT vector to the default, which is always put_chr,
                ; but may have synonyms
                lda #put_chr
                sta output

                ; set the INPUT vector to the default, which is always get_chr,
                ; but may have synonyms
                lda #get_chr
                sta input
               
                ; set the HAVE_KEY vector to the default, which is always
                ; have_chr, but may have synonyms
                lda #have_chr
                sta havekey

                ; The compiler pointer (CP) points to the first free byte
                ; in the Dictionary
                lda #cp0
                sta cp

                lda #buffer0
                sta cib ;  input buffer
                stz ciblen ;  input buffer starts empty
                stz insrc ;  SOURCE-ID is zero
                stz state ;  STATE is zero (interpret mode)
                
                ; The name token (nt) of DROP is always the first one in the
                ; new Dictionary, so we start off the Dictionary Pointer (DP)
                ; there. Anything that comes after that (with WORDS, before
                ; that) is high-level
                lda #nt_drop
                sta dp
 
                ; Clear the screen, assumes vt100 terminal
                jsr xt_page
                
                ; Define high-level words via EVALUATE. At this point, whatever
                ; is in Y (TOS) is garbage, so we don't have to push it to the 
                ; stack first
                dex
                dex
                dex
                dex
                lda #hi_start
                sta $00,x		;  Start address goes in NOS
                ldy #hi_end-hi_start	;  length goes in TOS

                jsr xt_evaluate

                ; fall through to ABORT

; -------------------------------------------------------------------
; ABORT ( -- ) 8+ bytes / X cycles
; Reset the parameter (data) stack pointer and continue as QUIT 
; We can jump here via subroutine because we reset the stack pointer
; anyway. Flows into QUIT.
xt_abort
        .setal    ; paranoid 
                ; clear Data Stack
                ldy #$0000
                ldx #dsp0


                ; drops through to QUIT, z_abort is the same as z_quit.

; -------------------------------------------------------------------
; QUIT ( -- ) X bytes / X cycles
; Reset the input, clearning Return Stack. Jumps to QUIT do not have to be
; subroutine jumps as the Return Stack is cleared anyway. Liara Forth follows
; the ANSI Forth recommendation to use REFILL. Note we don't display the "ok"
; system prompt until after the first output, this follows Gforth.
xt_quit
                ; clear Return Stack
                lda #stack0
                tcs

                ; make sure Instruction Pointer is empty
                ; TODO move this someplace else or else it will end up in ROM
                stz execute_ip

                ; switch SOURCE-ID to zero (keyboard input)
                stz insrc
                
                ; switch to interpret state (STATE is zero)
                stz state
               
quit_get_line
                ; Empty current input buffer
                stz ciblen
               
                ; Accept a line from the current input source
                jsr xt_refill ;  ( -- f )
                
                tya ;  force flag test
                bne quit_refill_successful

                ; If REFILL returned a FALSE flag, something went wrong and we
                ; need to print an error message and reset the machine. We don't
                ; need to save TOS because we're going to clobber it anyway when we
                ; go back to ABORT.
                lda #es_refill1
                jmp error


quit_refill_successful
                ; Assume we have successfully accepted a string of input from
                ; a source, with address cib and length of input in ciblen. We
                ; arrive here still with the TRUE flag from REFILL as TOS (in Y)
                ldy $00,x ;  drop TOS
                inx
                inx
                
                ; make >IN point to begining of buffer
                stz toin
 
                ; Main compile/execute routine
                jsr interpret

                ; Test for Data Stack underflow. Our stack is so large in single
                ; user mode that we don't bother checking for overflow
                cpx #dsp0+1
                bcc quit_ok ;  DSP must always be smaller (!) than DSP0
                
                lda #es_underflow
                jmp error

quit_ok
                ; Display system prompt if all went well. If we're interpreting,
                ; this is " ok", if we're compiling, it's " compiled"
                lda state
                bne quit_compiled

                lda #s_ok
                bra quit_print
quit_compiled
                lda #s_compiled ;  fall through to quit_print
quit_print
                jsr print_string

                ; Awesome line, everybody! Now get the next one
                jmp quit_get_line

z_cold
z_abort
z_quit          ; empty, no RTS required

; -------------------------------------------------------------------
; < "LESS" ( n m -- f ) X bytes / X cycles
; Return true flag if NOS < TOS. See
; http://www.6502.org/tutorials/compare_beyond.html for details on the
; comparisons
xt_less
                tya
                ldy #$0000 ;  default is false

                sec
                sbc $00,x
                beq less_nip ;  the same is not greater
                bvc less_no_ov ;  no overflow, skip ahead

                ; Deal with oveflow because we use signed numbers
                eor #$8000 ;  compliment negative flag

less_no_ov
                ; if we're negative TOS > NOS
                bmi less_nip
                dey
less_nip
                inx
                inx

z_less          rts


; -------------------------------------------------------------------
; <> "NOT-EQUAL" ( n m -- f ) X bytes / X cycles
; Return true flag if TOS and NOS are not the same. This is just a different
; version of EQUAL, we repeat the code for speed reasons
xt_not_equal
                tya
                ldy #$0000 ;  default value is false

                cmp $00,x
                beq not_equal_equal
                dey ;  wraps to 0FFFF (true)

not_equal_equal                 ; yes, this is a silly name
                inx
                inx
     
z_not_equal     rts


; -------------------------------------------------------------------
; <# "LESSNUMBER" ( -- ) 8 bytes / X cycles
; Start the process to create pictured numeric output. The new string is
; constructed from back to front, saving the new character at the beginning of
; the output string. Since we use PAD as a starting address and work backward
; (!), the string is constructed in the space between the end of the dictionary
; (as defined by CP) and the PAD. This allows us to satisfy the ANS Forth
; condition that programs don't fool around with the PAD but still use its
; address. Code based on pForth, see
; http://pforth.googlecode.com/svn/trunk/fth/numberio.fth pForth is in the pubic
; domain. Forth is : <# PAD HLD ! ; we use the internal variable tohold instead
; of HLD.
xt_lessnumber
                jsr xt_pad
                sty tohold

                ldy $00,x
                inx
                inx
   
z_lessnumber    rts


; -------------------------------------------------------------------
; > "GREATER" ( n m -- f ) X bytes / X cycles
; Return true flag if NOS > TOS. See
; http://www.6502.org/tutorials/compare_beyond.html for details on the
; comparisons
xt_greater
                tya
                ldy #$0000 ;  default is false

                sec
                sbc $00,x
                beq greater_nip ;  the same is not greater
                bvc greater_no_ov ;  no overflow, skip ahead

                ; Deal with oveflow because we use signed numbers
                eor #$8000 ;  compliment negative flag

greater_no_ov
                ; if we're still positiv, TOS < NOS
                bpl greater_nip
                dey
greater_nip
                inx
                inx

z_greater       rts


; -------------------------------------------------------------------
; >BODY "TOBODY" ( xt -- addr ) 3 bytes / 6 cycles
; Given a word's execution token (xt), return the address of the start of that
; word's parameter field (PFA). This is the address that HERE would return right
; after CREATE. This is a difficult word for STC Forths, because most words
; don't have a Code Field Area (CFA) to skip. We solve this by testing if the
; first three bytes of the body (that starts at xt) are subroutine jumps to
; DOVAR, DOCONST or DODOES
xt_tobody
                ; In the header, xt already points to the CFA, which CREATE by
                ; default fills with a JSR to DOVAR
        .setas
                lda $0000,y ;  see if we have a JSR instruction
                cmp #$20
        .setal
                bne tobody_nojsr

                ; Okay, so we found a JSR instruction. But is it one of the
                ; right ones?
                iny
                lda $0000,y

                cmp #dovar
                beq tobody_have_cfa
                cmp #doconst
                beq tobody_have_cfa
                cmp #dodoes
                beq tobody_have_cfa
                
                ; This is some other jump, so we go back to beginning of word
                dey ;  restor original xt
                bra tobody_nojsr

tobody_have_cfa
                ; Got the right kind of jump. We've already increased the index
                ; by one, so we just have to add two
                iny
                iny ;  drops through to end
                
tobody_nojsr
                ; If we don't have a jump instruction, the xt already points to
                ; the PFA, because there is no CFA
                ; body
                
z_tobody        rts

; -------------------------------------------------------------------
; >IN "TOIN" ( -- addr ) 6 bytes / 12 cycles
; Return address where pointer to current char in input buffer lives (>IN)
xt_to_in
                dex
                dex
                sty $00,x

                ldy #toin ;  >IN
z_to_in         rts

; -------------------------------------------------------------------
; >NUMBER ( ud addr u -- ud addr u ) X bytes / X cycles
; Convert a string to a double number. Logic here is based on the routine by
; Phil Burk of the same name in pForth; see
; https://github.com/philburk/pforth/blob/master/fth/numberio.fth the original
; Forth code. We arrive here from NUMBER which has made sure that we don't have
; to deal with a sign and we don't have to deal with a dot as a last character
; that signalizes double - this should be a pure number string.
; This routine calles UM*, which uses tmp1, tmp2 and tmp3, so we cannot access
; any of those.
xt_tonumber
        .al
                ; For the math routine, we move the inputs to the scratchpad to
                ; avoid having to fool around with the Data Stack. 
                ;
                ;     +-----+-----+-----+-----+-----+-----+-----+-----+
                ;     |   UD-LO   |   UD-HI   |     N     | UD-HI-LO  |
                ;     |           |           |           |           |
                ;     |  S    S+1 | S+2   S+3 | S+4   S+5 | S+6   S+7 |
                ;     +-----+-----+-----+-----+-----+-----+-----+-----+
                
                ; The math routine works by converting one character to its
                ; numerical value (N) via DIGIT? and storing it in S+4 for
                ; the moment. We then multiply the UD-HI value with the radix
                ; (from BASE) using UM*, which returns a double-cell result. We
                ; discard the high cell of that result (UD-HI-HI) and store the
                ; low cell (UD-HI-LO) in S+6 for now. -- The second part is
                ; multiplying UD-LO with the radix. The high cell (UD-LO-HI)
                ; gets put in S+2, the low cell (HD-LO-LO) in S. We then use
                ; a version of D+ to add ( S S+2 ) and ( S+4 S+6) together,
                ; storing the result back in S and S+2, before we start another
                ; round with it as the new UD-LO and UD-HI.

                ; Fill the scratchpad. We arrive with ( ud-lo ud-hi addr u ).
                ; After this step, the original ud-lo and ud-hi will still be on
                ; the Data Stack, but will be ignored and later overwritten
                lda $04,x ;  ud-lo
                sta scratch
                lda $02,x ;  ud-hi
                sta scratch+2

                ; We push down one on the Data Stack to use TOS for character
                ; conversion - now ( ud-lo ud-hi addr u u ) 
                dex
                dex
                sty $00,x

tonumber_loop
                ; Get one character
                lda ($02,x)
                tay ;  ( ud-lo ud-hi addr u char )

                ; Convert one character. DIGIT? takes care of the correct
                ; register size for A and does a paranoid AND to make sure that
                ; B is zero, so we don't have to do any of that here. 
                jsr xt_digitq ;  ( char -- n -1 | char 0 )
                
                ; This gives us (ud-lo ud-hi addr u char f | n f ), so check the
                ; flag. If it is zero, we return what we have and let the caller
                ; (usually NUMBER) complain to the user
                tya
                bne tonumber_ok

                ldy $00,x
                inx
                inx
                bra tonumber_done

tonumber_ok
                ; Conversion was successful, so we're here with 
                ; ( ud-lo ud-hi addr u n -1 ) and can start the math routine.
                
                ; Save N so we don't have to fool around with the Data Stack
                lda $00,x
                sta scratch+4

                ; Now multiply ud-hi (the one in the scratchpad, not the
                ; original one in the Data Stack) by the radix from BASE. We can
                ; clobber TOS and NOS
                lda scratch+2
                sta $00,x
                ldy base ;  ( ud-lo ud-hi addr u ud-hi base )

                ; UM* returns a double celled number
                jsr xt_umstar ;  ( ud-lo ud-hi addr u ud-hi-lo ud-hi-hi )

                ; Move ud-hi-lo to safety
                lda $00,x ;  ud-hi-lo
                sta scratch+6

                ; Now we multiply ud-lo, overwriting the stack entries
                lda scratch
                sta $00,x ;  ( ud-lo ud-hi addr u ud-lo ud-hi-hi )
                ldy base ;  ( ud-lo ud-hi addr u ud-lo base )

                jsr xt_umstar ;  ( ud-lo ud-hi addr u ud-lo-lo ud-lo-hi )
                sty scratch+2
                lda $00,x
                sta scratch

                ; This is a faster version of D+
                lda scratch
                clc
                adc scratch+4
                sta scratch ;  this is the new ud-lo
                lda scratch+2
                adc scratch+6
                sta scratch+2 ;  this is the new ud-hi

                ; Clean up: Get rid of one of the two top elements on the Data
                ; Stack. NIP is faster if Y is TOS
                inx
                inx ;  ( ud-lo ud-hi addr u ud-lo-hi )

                ; One character down
                inc $02,x ;  increase address
                dec $00,x ;  decrease length

                bne tonumber_loop

tonumber_done
                ; Counter has reached zero or we have an error. In both cases,
                ; we clean up the Data Stack and return. We arrive here with
                ; ( ud-lo ud-hi addr u char ) if there was an error
                ; and ( ud-lo ud-hi addr u ud-lo ) if not
                ldy $00,x
                inx
                inx ;  ( ud-lo ud-hi addr u )

                ; The new ud-lo and ud-hi are still on the scratch pad
                lda scratch ;  new ud-lo
                sta $04,x
                lda scratch+2
                sta $02,x ;  new ud-hi
	
z_tonumber      rts


; -------------------------------------------------------------------
; >R "TOR" ( n -- ) (R: -- n )  7 bytes / 22 cycles
; Move Top of Data Stack to Top of Return Stack
; TODO consider stripping PHA/PLA if natively compiled (see COMPILE,)
xt_tor
        .al                
                ; Save the return address. If this word is natively coded, this
                ; is a complete waste of nine cycles, but required for
                ; subroutine coding
                pla
                ; --- cut for native coding ---

                phy ;  the actual work

                ldy $00,x ;  DROP
                inx
                inx

                ; --- cut for native coding ---
                pha ;  put return address back in place

z_tor           rts


; -------------------------------------------------------------------
; /STRING ( addr u n -- ) X bytes / X cycles
; Remove characters from front of string. Uses tmp1
; Forth version: ROT OVER + ROT ROT - ; 
; TODO check for negative strings so 1 /STRING TYPE won't try to print the whole
; address space; follow Gforth in failing gracefully
xt_slashstring
                sty tmp1

                lda $00,x ;  length
                sec
                sbc tmp1
                tay

                lda $02,x ;  address
                clc
                adc tmp1
                sta $02,x

                inx
                inx

z_slashstring   rts


; -------------------------------------------------------------------
; . "DOT" ( n -- ) X bytes / X cycles
; Print value that is TOS followed by a single space. Forth code is  
; DUP ABS 0 <# #S ROT SIGN #> TYPE SPACE   Based on 
; https://github.com/philburk/pforth/blob/master/fth/numberio.fth Since this is
; used interactively, and humans are slow (just ask GlaDOS), we focus on size.
xt_dot
                jsr xt_dup ;  ( n n )
                jsr xt_abs ;  ( n n )
                jsr xt_zero ;  ( n n 0 )
                jsr xt_lessnumber ;  ( n n 0 )
                jsr xt_hashs ;  ( n ud )
                jsr xt_rot ;  ( ud n )
                jsr xt_sign ;  ( ud )
                jsr xt_numbermore
                jsr xt_type
                jsr xt_space

z_dot           rts


; -------------------------------------------------------------------
; ." "DOTQUOTE" ( -- ) X bytes / X cycles
; Compile string that is printed during run time. ANSI Forth wants this to be
; compile_only, even though everybody and their friend uses it for everything.
; We follow the book here, and recommend .( for general printing. 
xt_dotquote
                dex
                dex
                sty $00,x
                ldy #$0022 ;  ASCII for "

                jsr xt_parse
                jsr xt_sliteral

                pea xt_type
                jsr cmpl_subroutine ;  don't JSR/RTS

z_dotquote      rts


; -------------------------------------------------------------------
; .S "DOTS" ( -- ) X bytes / X cycles
; Print content of Data Stack non-distructively. Since this is for humans, we
; don't have to worry about speed. We follow the format of Gforth
; and print the number of elements first in brackets, followed by the Data Stack
; content (if present). Uses tmp3
xt_dots
        .al
        .xl
                jsr xt_depth ;  ( -- u)

                ; Print stack depth in brackets
                lda #'<'
                jsr emit_a

                ; We keep a copy of the number of things on the stack to use as
                ; a counter further down
                dex ;  DUP
                dex
                sty $00,x

                jsr print_u ;  print unsigned number

                lda #'>'
                jsr emit_a
                jsr xt_space

                ; There will be a lot of cases where .S is used when the stack
                ; is empty. Get them first and exit quickly
                tya ;  force flag test
                beq dots_done

dots_not_empty
                ; We have at least one element on the stack, which used to be in
                ; Y as TOS, but is now NOS and therefore accessable by X. The
                ; depth of the Data Stack is in Y waiting to be used as
                ; a counter. We use this to our advantage. 
                lda #dsp0-4 ;  skip two garbage entries on stack
                sta tmp3 ;  use as pointer

dots_loop
                lda (tmp3) ;  LDA (TMP1)
                phy ;  save our counter
                tay
                jsr xt_dot ;  print one number, drops TOS

                dex ;  restore counter
                dex
                sty $00,x
                ply
                
                dec tmp3 ;  next stack entry
                dec tmp3

                dey
                bne dots_loop

dots_done
                ; word so we save one byte by doing DROP the slow way
                jsr xt_drop

z_dots          rts


; -------------------------------------------------------------------
; , "COMMA" ( n -- ) 11 bytes / 29 cycles
; Allot one cell and store TOS in memory. We ignore alignment issues, though
; satisfy the ANSI requirement that an aligned compiler pointer will remain
; aligned
; There is another variant possible: 
;               tya
;               ldy.d cp
;               sta.y 0000
;               iny
;               iny
;               sty.d cp
;               ldy.dx 00
;               inx
;               inx
; This is as fast as the variant below, but three bytes longer
xt_comma
        .al
                tya
                sta (cp) ;  STA (CP)
                inc cp
                inc cp

                ldy $00,x
                inx
                inx

z_comma         rts


; -------------------------------------------------------------------
; : "COLON" ( "name" -- ) X bytes / X cycles
; Start compilation of new word into the Dictionary. Use the CREATE routine 
; and fill in the rest by hand.
xt_colon
        .al
                ; if we are already in compile mode, complain and abort
                lda state
                beq +

                lda #es_state
                jmp error
+
                ; Switch to compile state. From now on, everything goes in the
                ; Dictionary
                inc state

                ; CREATE is going to change DP to point to the new word's
                ; header. While this is fine for (say) variables, it would mean
                ; that FIND-NAME etc would find a half-finished word when
                ; looking in the Dictionary. To prevent this, we save the old
                ; version of DP and restore it later. The new DP is placed in
                ; the variable WORKWORD until we're finished with a SEMICOLON.
                lda dp
                pha ;  CREATE uses tmp1, tmp2 and tmp3

                jsr xt_create

                ; Get the nt (not the xt!) of the new word as described above.
                ; Only COLON, SEMICOLON and RECURSE access WORKWORD
                lda dp
                sta workword
                pla
                sta dp

                ; CREATE includes a subroutine jump to DOVAR by default. We back
                ; up three bytes and overwrite that. Note that 3 x DEC.D would
                ; use 3 bytes and 18 cycles; this version uses 8 bytes but
                ; only 13 cycles
                lda cp
                sec
                sbc #$0003
                sta cp

z_colon         rts


; -------------------------------------------------------------------
; ; "SEMICOLON" ( -- ) X bytes / X cycles
; End the compilation of a new word into the Dictionary. When we enter this, 
; WORKWORD is pointing to the nt_ of this word in the Dictionary, DP to the
; previous word, and CP to the next free byte.  A Forth definition would be 
; (see "Starting Forth"):
;  : ;  POSTPONE EXIT  REVEAL POSTPONE ; [ ; IMMEDIATE
xt_semicolon
        .al
                sty tmptos

                ; CP is the byte that will be the address we use in the header for
                ; the end-of-compile address (z_word). This is six bytes down in
                ; the header
                ldy #$0006
                lda cp
                sta (workword),y ;  STA (WORKWORD),Y

                ; Add the RTS instruction to the end of the current word. We
                ; don't have to switch the size of the A register because we
                ; only move up the CP by one and the MSB will be overwritten. 
                ; Little endian MPUs for the win!
                lda #$60 ;  opcode for RTS
                sta (cp) ;  STA (CP)
                inc cp ;  MSB will be overwritten

                ; Word definition is complete. Make the new word the last one in
                ; the Dictionary
                lda workword
                sta dp

                ; Get our TOS back
                ldy tmptos
                
                ; Set compile flag back to zero so we're back in interpret mode
                stz state
                
z_semicolon     rts


; -------------------------------------------------------------------
; # "HASH" / "NUMBER-SIGN" ( ud -- ud )  X bytes / X cycles
; Add one character to the beginning of the pictured output string.
; Code based on https://github.com/philburk/pforth/blob/master/fth/numberio.fth
; Forth code is  BASE @ UD/MOD ROT 9 OVER < IF 7 + THEN [CHAR] 0 + HOLD ;
; TODO convert more parts to assembler
xt_hash
        .al
                jsr xt_base ;  ( ud addr )
                jsr xt_fetch ;  ( ud u )
                jsr xt_udmod ;  ( rem ud )
                jsr xt_rot ;  ( ud rem )
 
                ; Convert the number that is left over to an ASCII character. We
                ; use a string lookup for speed. Use either abc_str_lower for
                ; lower case or abc_str_upper for upper case (prefered)
        .setas
                lda abc_str_upper,y
        .setal
                ; overwrite remainder with ASCII value
                and #$00ff
                tay ;  ( ud char )

                jsr xt_hold
                
z_hash          rts


; -------------------------------------------------------------------
; #> "NUMBERMORE" / "NUMBER-GREATER" ( d -- addr u ) X bytes / X cycles
; Finish conversion of pictured number string, putting address and length on the 
; Data Stack. Original Fort is  2DROP HLD @ PAD OVER -  Based on
; https://github.com/philburk/pforth/blob/master/fth/numberio.fth
xt_numbermore
        .al
                ; We simply overwrite the double cell number, saving us a lot of
                ; stack thrashing. First, put the address of the string's head in
                ; TOS and NOS
                ldy tohold
                sty $00,x ;  ( addr addr )

                ; add the address of the string's end, which is PAD
                jsr xt_pad ;  ( addr addr pad )

                sec
                tya
                sbc $00,x ;  pad - addr is the length of the string
                tay ;  ( addr addr n )

                inx ;  NIP
                inx

z_numbermore    rts


; -------------------------------------------------------------------
; #S "HASHS" / "NUMBER SIGN" ( ud -- ud ) X bytes / X cycles
; Completely convert number for pictured numerical output. Based on
; https://github.com/philburk/pforth/blob/master/fth/system.fth
; Original Forth code  BEGIN # 2DUP OR 0= UNTIL
xt_hashs
        .al
hashs_loop
                ; covert a single number ("#")
                jsr xt_hash ;  ( ud -- ud )

                ; stop when the double-celled number on the TOS is zero
                tya
                ora $00,x
                bne hashs_loop
                
z_hashs         rts

; -------------------------------------------------------------------
; ? "QUESTION" ( addr -- ) X bytes / X cycles
; Print content of a variable. This is used interactively and humans are
; slow, so we just go for the subroutine jumps to keep it short
xt_question
                jsr xt_fetch
                jsr xt_dot

z_question      rts


; -------------------------------------------------------------------
; QDUP ( n -- 0 | n n ) X bytes / X cycles
; If top element on Data Stack is not zero, duplicate it
xt_qdup
                tya
                beq z_qdup

                dex
                dex
                sty $00,x

z_qdup          rts


; -------------------------------------------------------------------
; ! "STORE" ( n addr -- ) 9 bytes / X cycles
; Save value at designated memory location
xt_store
        .al
                lda $00,x ;  NOS has value
                sta $0000,y

                ldy $02,x
                inx
                inx
                inx
                inx

z_store         rts


; -------------------------------------------------------------------
; @ "FETCH" ( addr -- n ) 4 bytes / 7-8 cycles
; Get one cell (16 bit) value from given address
xt_fetch
                lda $0000,y
                tay

z_fetch         rts


; -------------------------------------------------------------------
; (+LOOP) "PARENS-PLUSLOOP" ( n -- ) X bytes / X cycles
; Runtime compile for counted loop control. This is used for both +LOOP and
; LOOP which are defined at high level. Note we use a fudge factor for loop
; control so we can test with the Overflow Flag. See (DO) for details. This is
; Native Compile. The step value is TOS in the loop
xt_pploop
        .al
                ; add step to index
                tya ;  step
                clv ;  this is used for loop control
                clc
                adc $01,s ;  add index from top of R
                sta $01,s ;  store it back on top of R

                ; dump step from TOS
                ldy $00,x
                inx
                inx

                ; if the V flag is set, we're done looping and continue after
                ; the +LOOP instruction
                bvs pploop_jmp+3

pploop_jmp
                ; This is why this routine must be natively compiled: We compile
                ; the opcode for jump here without an address to go to, which is
                ; added by the next instruction of LOOP (or +LOOP) during
                ; compile time
                .byte $4C

z_pploop        rts ;  never reached (TODO remove)


; -------------------------------------------------------------------
; (?DO) "PARENS-QUESTION-DO" ( -- ) X bytes / X cycles
; Runtime routine for ?DO. This contains the parts required for the question
; mark and then drops through to (DO). This must be native compile
xt_pqdo
                ; See if TOS and NOS are equal
                ; TODO move this to assembler for speed
                jsr xt_2dup
                jsr xt_equal ;  now ( n1 n2 f )

                tya ;  force flag check
                beq pqdo_done

                ; the two numbers are equal, so we get out of there
                ; first, dump three entries off the Data Stack
                ldy $04,x
                txa
                clc
                adc #$0006
                tax

                ; Abort the whole loop. Since the limit/start parameters are not
                ; on the Return stack yet, we only have the address that points
                ; to the end of the loop. Dump the RTS of ?DO and just use that
                ; RTS
                pla
                rts

pqdo_done
                ; get ready to drop to (DO)
                ldy $00,x ;  drop flag from EQUAL
                inx
                inx
                

; -------------------------------------------------------------------
; (DO) "PARENS-DO" ( limit start -- ; R: -- limit start ) X bytes / X cycles
; Runtime routine for DO loop. Note that ANSI loops quit when the boundry of
; limit-1 and limit is reached, a different mechanism than the FIG Forth loop
; (you can see which version you have by running a loop with start and limit as
; the same value, for instance 0 0 DO -- these will walk through the complete
; number space). This is why there is ?DO, which you should use. We use a "fudge
; factor" for the limit that makes the Overflow Flag trip when it is reached;
; see http://forum.6502.org/viewtopic.php?f=9&t=2> for further discussion of
; this. The source given there for this idea is Laxen & Perry F83. This routine
; must be native compile (and should be anyway for speed). 
xt_pdo
        .al
                ; Create fudge factor (fufa) by subtracting the limit from
                ; $8000, the number that will trip the overflow flag 
                sec
                lda #$8000
                sbc $00,x ;  limit is NOS
                sta $00,x ;  save fufa for later use as NOS
                pha ;  we use fufa instead of limit on R

                ; Index is fufa plus original index
                clc
                tya ;  index is TOS
                adc $00,x ;  add fufa
                pha
                
                ; clean up
                inx
                inx
                inx
                inx
              
z_pqdo
z_pdo           rts


; -------------------------------------------------------------------
; ['] "BRACKET-TICK" ( -- ) X bytes / X cycles
; Store xt of following word during compilation
xt_brackettick
                jsr xt_tick
                jsr xt_literal

z_brackettick   rts


; -------------------------------------------------------------------
; [ "LEFTBRACKET" ( -- ) X bytes / X cycles
; Enter the interpretation state. This is an immediate, compile_only word
xt_leftbracket
                stz state
z_leftbracket   rts


; -------------------------------------------------------------------
; ] "RIGHTBRACKET" ( -- ) X bytes / X cycles
; Enter the compile state. In theory, we should be able to get away with
; a simple INC.A, but this is more error tolerant. For obvious reasons, this
; cannot be COMPILE-ONLY, and native compile doesn't make much sense either
xt_rightbracket
                lda #$0001
                sta state
                
z_rightbracket  rts

; -------------------------------------------------------------------
; [CHAR] "BRACKET-CHAR" ( "c" -- ) X bytes / X cycles
; At compile time, compile the ASCII value of a character as a literal
; This is an immediate, compile_only word. A definition given in 
; http://forth-standard.org/standard/implement is 
; : [CHAR] CHAR POSTPONE LITERAL ; IMMEDIATE
; TODO decide if this is worth unrolling
xt_bracketchar
                jsr xt_char
                jsr xt_literal
             
z_bracketchar   rts


; -------------------------------------------------------------------
; \ "BACKSLASH" ( -- ) 4 bytes / X cycles
; Ignore rest of line as comment
xt_backslash
.al
                ; Advance >IN to end of the line 
                lda ciblen
                sta toin

z_backslash     rts


; -------------------------------------------------------------------
; + "PLUS" ( n m -- n+m ) 7 bytes / X cycles
; Add TOS and NOS
xt_plus
        .al
                tya
                clc
                adc $00,x
                tay
                inx
                inx

z_plus          rts


; -------------------------------------------------------------------
; LOOP ( -- ) X bytes / X cycles
; Compile-time part of LOOP. This does nothing more but push
; 01 on the stack and then call +LOOP. In Forth, this is 
; POSTPONE 1 POSTPONE (+LOOP) , POSTPONE UNLOOP ; IMMEDIATE
; COMPILE-ONLY  Drops through to +LOOP
xt_loop
                ; have the finished word put 0001 on the Data Stack
                pea xt_one
                jsr cmpl_subroutine ;  drops through to +LOOP

; -------------------------------------------------------------------
; +LOOP ( addr -- ) X bytes / X cycles
; Compile-time part of +LOOP, also used for LOOP. is usually realized in Forth
; as  : +LOOP POSTPONE (+LOOP) , POSTPONE UNLOOP ; IMMEDIATE COMPILE-ONLY  Note
; that LOOP uses this routine as well. We jump here with the address for looping
; as TOS, and the address for aborting the loop (LEAVE) as the second
; double-byte entry on the Return Stack (see DO and loops.txt for details).
xt_ploop
                ; compile (+LOOP) - use COMPILE, because this has to be natively
                ; compiled
                dex
                dex
                sty $00,x
                ldy #xt_pploop
                jsr xt_compilecomma

                ; The address we need to loop back to is TOS
                jsr xt_comma

                ; Now compile an UNLOOP for when we're all done
                dex
                dex
                sty $00,x
                ldy #xt_unloop
                jsr xt_compilecomma

                ; Complete the compile of DO (or ?DO) by filling the hole they
                ; left with the current address. This is TOS
                lda cp ;  we need CP-1 for RTS calculation
                dec a
                sta $0000,y

                ldy $00,x
                inx
                inx

z_loop
z_ploop         rts


; -------------------------------------------------------------------
; - "MINUS" ( n m -- n-m ) 10 bytes / X cycles
; Subtract NOS from TOS
xt_minus
        .al
                tya
                eor #$0ffff

                sec ;  not CLC
                adc $00,x

                tay
                inx
                inx
                
z_minus         rts

; -------------------------------------------------------------------
; -ROT ( a b c -- c a b )  X bytes / X cycles
; Rotate top three entries of Data Stack upwards
xt_mrot
        .al
        .xl
                lda $02,x ;  save a
                sty $02,x ;  move c to 3OS
                ldy $00,x ;  move b to TOS
                sta $00,x ;  save a as NOS
             
z_mrot          rts


; -------------------------------------------------------------------
; -TRAILING ( addr u -- addr u ) X bytes / X cycles
; Remove any trailing blanks. Uses tmp3
xt_dtrailing
                ; if u is zero, just return string
                tya ;  force flag check
                beq z_dtrailing

                lda $00,x
                sta tmp3
                dey ;  convert length to index
        .setas

dtrailing_loop
                lda (tmp3),y
                cmp #$20
                bne dtrailing_done
                dey
                bpl dtrailing_loop ;  fall through when done

dtrailing_done
        .setal
                iny ;  convert index to length

z_dtrailing     rts


; -------------------------------------------------------------------
; = "EQUAL" ( n m -- f ) 11 bytes / 18-20 cycles
; See if TOS and NOS are the same
xt_equal
                tya
                ldy #$0000 ;  default value is false

                cmp $00,x
                bne equal_not
                dey ;  wraps to 0FFFF (true)

equal_not
                inx
                inx

z_equal         rts


; -------------------------------------------------------------------
; 0 "ZERO" ( -- 0 ) 7 bytes / 12 cycles
; Pushes the number 0000 on the Data Stack
xt_zero
        .xl
                dex
                dex
                sty $00,x
                ldy #$0000

z_zero          rts
       
; -------------------------------------------------------------------
; 0= "ZERO-EQUAL" ( n -- f ) X bytes / X cycles
; Return the true flag if TOS is zero
xt_zero_equal
        .al
                tya ;  force flag check
                bne ze_not_zero

                ldy #$0ffff
                bra z_zero_equal
ze_not_zero
                ldy #$0000

z_zero_equal    rts


; -------------------------------------------------------------------
; 0< "ZERO-LESS" ( n -- f ) 11 bytes / X cycles
; Return the true flag if TOS is less than zero
xt_zero_less
        .al
                tya ;  force flag check
                bmi zero_less_is_less

                ldy #$0000
                bra z_zero_less

zero_less_is_less
                ldy #$0ffff

z_zero_less     rts

; -------------------------------------------------------------------
; 0<> "ZERO-NOTEQUAL" ( n -- f ) 11 bytes / X cycles
; Return the true flag if TOS is not zero
xt_zero_notequal
        .al
                tya ;  force flag check
                beq zne_is_zero
                ldy #$0ffff
                bra z_zero_notequal
zne_is_zero
                ldy #$0000
z_zero_notequal
                rts


; -------------------------------------------------------------------
; 0> "ZERO-MORE" ( n -- f ) X bytes / X cycles
; Return the true flag if TOS is more than zero
xt_zero_more
        .al
                lda #$0000 ;  default is false

                dey
                bpl zero_more_true ;  was at least 1

                bra zero_more_done ;  nope, stays false

zero_more_true
                dec a ;  wraps to 0ffff, true
zero_more_done
                tay

z_zero_more     rts


; -------------------------------------------------------------------
; 0BRANCH ( 0 | f -- ) X bytes / X cycles
; Branch if TOS is zero. This exects the next two bytes to be the address of
; where to branch to if the test fails. The code may not be natively compiled
; because we need the return address provided by JSR's push to the Return Stack
; This routine uses tmpbranch
xt_zbranch
        .al
                ; encode subroutine jump to run time code 
                pea zbranch_rt
                jsr cmpl_subroutine

z_zbranch       rts

zbranch_rt
                ; See if the flag is zero, which is the whole purpose of this
                ; operation after all
                tya ;  force flag check
                beq zb_zero ;  flag is false (zero), so we branch

                ; Flag is TRUE, so we skip over the next two bytes. Put
                ; differently, this is the part between IF and THEN
                pla
                inc a
                inc a

                bra zb_done

zb_zero
                ; Flag is FALSE, so we take the dump to the address given in the
                ; next two bytes. We don't need Y anymore, so we can use it for
                ; indexing
                pla
                sta tmpbranch
                ldy #$0001
                lda (tmpbranch),y

                ; Subtract one from the address given becasue of the RTS
                ; mechanics
                dec a

zb_done
                ; One we or another, this is where we're going to jump to
                pha

                ; Clean up the Data Stack and jump
                ldy $00,x
                inx
                inx

                rts

; -------------------------------------------------------------------
; 1 "ONE" ( -- 1 ) 7 bytes / 12 cycles
; Pushes the number 1 on the Data Stack
xt_one
        .xl
                dex
                dex
                sty $00,x
                ldy #$0001

z_one           rts


; -------------------------------------------------------------------
; 1- "ONE-MINUS" ( n -- n-1 ) 1 byte / 2 cycles
; Subtract 1 from Top of Stack (TOS). Because there is no checking if there is
; actually anything on the Data Stack, this routine will fail silently if the
; stack is empty
xt_one_minus
        .xl
                dey
z_one_minus     rts


; -------------------------------------------------------------------
; 1+ "ONE-PLUS" ( n -- n+1 ) 1 byte / 2 cycles
; Add 1 to TOS. Because there is no checking if there is actually anything on
; the Data Stack, this routine will fail silently if the stack is empty
xt_one_plus
        .xl
                iny
z_one_plus      rts


; -------------------------------------------------------------------
; 2 "TWO" ( -- 2 ) 7 bytes / 12 cycles
; Pushes the number 2 on the Data Stack
xt_two
        .xl
                dex
                dex
                sty $00,x
                ldy #$0002

z_two           rts


; -------------------------------------------------------------------
; 2* "TWO-STAR" ( n -- 2*n ) 3 bytes / 6 cycles
; Multiply Top of Stack (TOS) by 2. This is also used by CELLS
xt_two_star
        .al
        .xl
                tya
                asl a
                tay
                
z_two_star      rts


; -------------------------------------------------------------------
; 2>R "TWOTOR" ( n1 n2 -- )(R: -- n1 n2)  X bytes / X cycles
; Push top two entries to Return Stack. The same as SWAP >R >R except that if we
; jumped here, the return address will be in the way. May not be natively
; compiled
xt_twotor
                ; get the return address out of the way
                pla
                sta tmp3
                ; --- CUT HERE for native compile ---

                lda $00,x ;  NOS stays next on Return Stack
                pha
                phy ;  TOS stays on top

                ldy $02,x ;  clean up data stack
                inx
                inx
                inx
                inx

                ; --- CUT HERE for native compile ---
                lda tmp3
                pha

z_twotor        rts


; -------------------------------------------------------------------
; 2DROP ( n m -- ) 6 bytes / 13 cycles
; Drop first two entries of Data Stack
xt_2drop
                ldy $02,x
                inx
                inx
                inx
                inx

z_2drop         rts


; -------------------------------------------------------------------
; 2DUP ( n m -- n m n m ) 10 bytes / 23 cycles
; Duplicated the top two data stack entries

xt_2dup
        .xl
                dex
                dex
                dex
                dex
                sty $02,x
                lda $04,x
                sta $00,x

z_2dup          rts


; -------------------------------------------------------------------
; 2OVER ( d1 d2 -- d1 d2 d1 ) X bytes / X cycles
; Copy cell pair that is NOS to TOS
xt_2over
                dex
                dex
                dex
                dex
                sty $02,x
                ldy $06,x
                lda $08,x
                sta $00,x

z_2over         rts


; -------------------------------------------------------------------
; 2R> "TWOFROMR" ( -- n1 n2 ) ( R: n1 n2 ) X bytes / X cycles
; Pull top two entries from Return Stack. Is the same as R> R> SWAP
; As with R>, the problem with the is word is that the top value on the Return
; Stack for a STC Forth is the return address, which we need to get out of the
; way first. Uses tmp3
xt_twofromr
                ; get the return address out of the way
                pla
                sta tmp3
                ; --- CUT HERE for native compile ---
                
                dex ;  make room on Data Stack
                dex
                dex
                dex
                sty $02,x

                ply ;  top element stays on top
                pla ;  next element stays below
                sta $00,x

                ; --- CUT HERE for native compile ---
                ; restore return address
                lda tmp3
                pha

z_twofromr      rts


; -------------------------------------------------------------------
; 2R@ ( -- n1 n2 )(R: n1 n2 -- n1 n2 )  X bytes / X cycles
; Copy two words off the Return Stack.  This is R> R> 2DUP >R >R SWAP but we
; can do this a lot faster in assembler This routine may not be natively
; compiled; because it accessed by a JSR, the first element on the Return Stack
; (LDA.S 01) is the return address.
xt_tworfetch
                ; make room on the Data Stack
                dex
                dex
                dex
                dex
                sty $02,x

                lda $03,s ;  get second element of Return Stack
                tay
                lda $05,s ;  get third element on Return Stack
                sta $00,x
                
z_tworfetch     rts


; -------------------------------------------------------------------
; 2SWAP ( d1 d2 -- d2 d1 ) X bytes / X cycles
; Swap two double cell numbers on the Data Stack. 
xt_2swap
                phy ;  hi word of TOS
                ldy $02,x ;  hi word of NOS
                pla
                sta $02,x

                lda $00,x ;  lo word of TOS
                pha
                lda $04,x ;  lo word of NOS
                sta $00,x
                pla
                sta $04,x

z_2swap         rts


; -------------------------------------------------------------------
; 2VARIABLE ( "name" -- ) X bytes / X cycles
; Create a variable with space for a double celled word. This can be realized in
; Forth as either CREATE 2 CELLS ALLOT or just CREATE 0 , 0 , 
; We use the second variant, letting CREATE do the hard work
; TODO see if it is faster to use Y as an index and increase by four
xt_2variable
        .al
                jsr xt_create

                lda #$0000
                sta (cp)
                inc cp
                inc cp
                sta (cp)
                inc cp
                inc cp
                
z_2variable     rts


; -------------------------------------------------------------------
; ' "TICK" ( "string" -- xt ) X bytes / X cycles
; Given a string with the name of a word, return the word's execution token (xt)
; Abort if not found
xt_tick
                jsr xt_parse_name ;  ( -- addr u )

                ; if we got a zero, complain and abort
                tya ;  force flag check
                bne tick_have_word

                lda #es_noname
                jmp error

tick_have_word
                jsr xt_find_name ;  ( addr u -- nt)
                tya ;  force flag check

                ; if we didn't find string in the dictionary, complain and abort
                bne tick_have_nt

                lda #es_syntax
                jmp error
                
tick_have_nt
                jsr xt_name_int ;  ( nt -- xt )
        
z_tick          rts

; -------------------------------------------------------------------
; ABORT" "ABORTQ" ( "string" -- ) X bytes / X cycles
; If flag on TOS is not false, print error message and abort. This a compile_only word
xt_abortq
        .al
                jsr xt_squote ;  save string

                pea abortq_rt ;  compile run-time aspect
                jsr cmpl_subroutine

                rts

abortq_rt
                ; we land here with ( f addr u ) 
                lda $02,x ;  get flag as 3OS
                beq abortq_done ;  if FALSE, we're done

                ; if TRUE, we print string and ABORT
                ; TODO see if we want to inform user we're aborting
                jsr xt_type
                jmp xt_abort ;  not JSR because we never come back
                
abortq_done
                ; drop the three entries from the Data Stack
                ldy $04,x ;  fourth on the stack
                
                ; this is the same size, but three cycles faster than six INX
                ; instructions
                txa
                clc
                adc #$0006
                tax
        
z_abortq        rts


; -------------------------------------------------------------------
; ABS ( n -- u ) 8 bytes / X cycles
; Return the absolute value of a single number
xt_abs
        .al
        .xl
                tya ;  force flag test
                bpl z_abs ;  positive number is easy

                ; negative: Calculate 0-n
                eor #$0ffff
                inc a
                tay
                
z_abs           rts

; -------------------------------------------------------------------
; ACCEPT ( addr n1 -- n2 ) X bytes / X cycles
; Receive a string of at most n1 characters, placing them at addr. Return the
; actual number of characters as n2. Characters are echoed as they are received.
; ACCEPT is called by REFILL these days. 

; Though we're dealing with individual characters, all these actions are
; performed with a 16 bit A register. The only place we switch is in the kernel
; routines themselves
xt_accept
        .al
                ; Set up loop
                tya ;  force flag test
                bne accept_nonzero
                                
                ; if we were told to get zero chars, just quit
                inx ;  NIP, TOS is zero which is also FALSE
                inx

                jmp z_accept ;  no RTS so we can native compile

accept_nonzero
                lda $00,x ;  address of buffer is NOS
                sta tmp1
                inx ;  NIP
                inx

                sty tmp2 ;  Save max number of chars in tmp2
                ldy #$0000 ;  Use Y as counter

accept_loop
                ; We don't need to check for CTRL-l, because a vt100 terminal
                ; clears the screen automatically

                ; This is a rolled-out version of KEY so we don't spend time
                ; fooling around wit the stack
                stx @w tmpdsp    ; tinkerer's put 8e here, tass - 86, now i want exact binaries
                ldx #$0000
                jsr (input,x) ;  JSR (INPUT,X)
                ldx tmpdsp

                ; we quit on both line feed and carriage return
                cmp #AscLF
                beq accept_eol
                cmp #AscCR
                beq accept_eol

                ; BS and DEL do the same thing for the moment
                cmp #AscBS
                beq accept_bs
                cmp #AscDEL
                beq accept_bs

                ; CTRL-c and ESC abort (see if this is too harsh)
                cmp #AscCC
                bne +
                jmp xt_abort
+
                cmp #AscESC
                bne +
                jmp xt_abort
+
                ; CTRL-p will be used for "previous cmd", TODO
                cmp #AscCP
                bne +

                lda #tests_prev_cmd
                jsr print_string

                bra accept_loop
+
                ; CTRL-n will be used for "next cmd", TODO 
                cmp #AscCN
                bne +

                lda #tests_next_cmd
                jsr print_string

                bra accept_loop

+
                ; That's quite enough, echo character. EMIT_A sidesteps all the
                ; fooling around with the Data Stack
                jsr emit_a

                sta (cib),y ;  STA (CIB),Y
                
                iny
                cpy tmp2 ;  reached character limit?
                bne accept_loop ;  fall thru if buffer limit reached

accept_eol
                sty ciblen ;  Y contains number of chars accepted already

                jsr xt_space ;  print final space
                bra z_accept

accept_bs
                cpy #$0000 ;  buffer empty?
                bne +

                lda #AscBELL ;  complain and don't delete beyond the start of line
                jsr emit_a
                iny
+
                dey
                lda #AscBS ;  move back one
                jsr emit_a
                lda #AscSP ;  print a space (rubout)
                jsr emit_a
                lda #AscBS ;  move back over space
                jsr emit_a

                bra accept_loop

z_accept        rts

; -------------------------------------------------------------------
; AGAIN ( addr -- ) 22 bytes / 50 cycles
; Code a backwards branch to an address usually left by BEGIN. We use JMP
; instead of BRA to make sure we have the range.
; TODO see if we should insert a KEY? to make sure we can abort and/or a PAUSE
xt_again

                ; Add the opcode for a JMP 
        .setas
                lda #$4c
                sta (cp) ;  STA (CP)
        .setal
                inc cp

                ; Add the address which should be TOS
                tya
                sta (cp)
                inc cp
                inc cp

                ; drop the address
                ldy $00,x
                inx
                inx

z_again         rts


; -------------------------------------------------------------------
; ALIGN ( -- ) 1 bytes / X cycles
; Make sure CP is aligned. This does nothing on the 65816
xt_align
                nop ;  removed during native compile
z_align         rts


; -------------------------------------------------------------------
; ALIGNED ( addr -- a-addr ) X bytes / X cycles
; Return the next aligned address. With the 65816, this does nothing
xt_aligned
                nop ;  removed during native compile
z_aligned       rts


; -------------------------------------------------------------------
; ALLOT ( n -- ) X bytes / X cycles
; Reserve a certain number of bytes (not cells) or release them. If n = 0, do
; nothing. If n is negative, release n bytes, but only to the beginning of the
; Dictionary. If n is positive (the most common case), reserve n bytes, but not
; past the Dictionary.
; See http://forth-standard.org/standard/core/ALLOT
; TODO test negative values
xt_allot
        .al
                tya ;  force flag check
                beq allot_real_gone ;  zero bytes, don't do anything
                bmi allot_minus ;  free memory instead of reserving it

                ; most common case: reserve n bytes. We've already transfered
                ; TOS to A, so we just have to add the current compile pointer
                clc
                adc cp ;  create new CP
                bcs allot_error ;  oops, we've wrapped

                tay ;  save copy of new CP

                sec
                sbc #cp_end
                bmi allot_done ;  oops, fall thru if beyond max RAM

allot_error
                lda #es_allot
                jmp error

allot_minus
                ; negative value means we're freeing memory 
                sec
                sbc cp
                bcc allot_error ;  oops, we've wrapped

                tay

                sbc #cp0 ;  Carry Flag must still be set
                bmi allot_error ;  oops, gone too far back
                
                ; fall through to allot_done
allot_done
                sty cp ;  new compiler pointer
allot_real_gone
                ldy $00,x ;  DROP
                inx
                inx

z_allot         rts

; -------------------------------------------------------------------
; AND ( n m -- n ) 6 bytes / X cycles
; Logical AND
xt_and
                tya
                and $00,x
                tay

                inx ;  NIP
                inx

z_and           rts


; -------------------------------------------------------------------
; AT-XY ( nx ny -- ) X bytes / X cycles
; Move cursor to coordinates given. ESC[<n>;<m>H Do not use U. to print the
; numbers because the trailing space will not work with xterm (works fine with
; Mac OS X Terminals, though)
; TODO doesn't like hex values, need to get rid of byte_to_ascii
; or call as word with 0 u.r and decimal
xt_at_xy
        .al 
                lda #AscESC ;  ESC
                jsr emit_a
                lda #$5b ;  [
                jsr emit_a
                lda $00,x ;  x
                jsr byte_to_ascii
                lda #$3b ;  semicolon
                jsr emit_a
                tya ;  y
                jsr byte_to_ascii
                lda #$48 ;  H
                jsr emit_a

                ldy $02,x
                inx
                inx
                inx
                inx

z_at_xy         rts


; -------------------------------------------------------------------
; BASE ( -- addr ) X bytes / X cycles
; Get the address of where the radix for number conversion is stored
xt_base
                dex
                dex
                sty $00,x

                ldy #base

z_base          rts

; -------------------------------------------------------------------
; BELL ( -- ) X bytes / X cycles
; Trigger terminal bell on vt100 terminals
xt_bell
        .al
                lda #AscBELL
                jsr emit_a

z_bell          rts

; -------------------------------------------------------------------
; BEGIN ( -- addr ) 6 bytes / 13 cycles
; Mark entry point for a loop. This is just an immediate version of here which
; could just as welle be coded as  : BEGIN HERE ; IMMEDIATE COMPILE-ONLY
; but we code it here for speed
xt_begin
                ; really just the same code as HERE
                dex
                dex
                sty $00,x

                ldy cp

z_begin         rts


; -------------------------------------------------------------------
; BL ( -- u ) 7 bytes / 12 cycles
; Put ASCII char for SPACE on Data Stack
xt_bl
        .xl
                dex
                dex
                sty $00,x
                ldy #AscSP

z_bl            rts


; -------------------------------------------------------------------
; BOUNDS ( addr u -- addr+u addr ) 9 bytes / X cycles
; Given a string, return the correct Data Stack parameters for a DO/LOOP loop
; over its characters. This is realized as OVER + SWAP in Forth, but we do it
; a lot faster in assembler
xt_bounds
        .al
                tya ;  TOS
                clc
                adc $00,x ;  NOS
                ldy $00,x
                sta $00,x
                
z_bounds        rts


; -------------------------------------------------------------------
; BRANCH ( -- ) X bytes / X cycles
; Transfer control to given address. This word was adapted from Tali Forth. It
; uses tmpbranch 
xt_branch
        .al
                ; encode subroutine branch to runtime portion
                pea branch_rt
                jsr cmpl_subroutine

z_branch        rts

branch_rt
                ; The value on the Return Stack determines where we go to
                pla
                sta tmpbranch

                phy ;  avoid using temp variables
                ldy #$0001
                lda (tmpbranch),y ;  LDA (TMPBRANCH),Y
                ply

                dec a
                pha ;  put target address back on Return Stack

                rts

; -------------------------------------------------------------------
; BYE ( -- ) 2 bytes / 7-8 cycles
; Leave Liara Forth, returning to Mensch Monitor
xt_bye
                sei
                cld
                nop ; sec in original - back to emulated
                nop ; xce in original
                jmp ($0fffc)

z_bye           ; never reached


; -------------------------------------------------------------------
; C, "C-COMMA" ( char -- ) 13 bytes / 28 cycles
; Store one character in the Dictionary
xt_c_comma
                tya
        .setas
                sta (cp) ;  STA (CP)
        .setal
                inc cp ;  quick version of 1 ALLOT

                ldy $00,x
                inx
                inx

z_c_comma       rts


; -------------------------------------------------------------------
; C@ "C-FETCH" ( addr -- n ) 11 bytes / 16 cycles
; Get a single byte from the given address
xt_c_fetch
        .setas
                lda $0000,y
        .setal
                and #$00ff
                tay

z_c_fetch       rts


; -------------------------------------------------------------------
; C! "C-STORE" ( n addr -- ) 15 bytes / 29 cycles
; Store LSB of NOS at location given as TOS
xt_c_store
                lda $00,x
        .setas
                sta $0000,y
        .setal
                ldy $02,x
                inx
                inx
                inx
                inx
                
z_c_store       rts


; -------------------------------------------------------------------
; CELL+ ( u -- u+2 ) X bytes / X cycles
; Add the size of one cell to the value on top of the stack. Since this is
; a 16-bit cell size, we add two
xt_cellplus
                iny
                iny

z_cellplus      rts


; -------------------------------------------------------------------
; CELLS ( n -- n ) X bytes / X cycles
; Given a number of cells, return the number of bytes that they will require.
; This is 16 bit cell Forth, so the value returned by this word is the same as
; returned by 2*, see there. 

; -------------------------------------------------------------------
; CHAR ( "c" -- u ) 23 bytes / X cycles
; Convert a character to its ASCII value
xt_char
        .al
                jsr xt_parse_name ;  ( -- addr u )

                ; if we got back a zero, we have a problem
                tya ;  force flag check
                bne char_got_char

                lda #es_noname
                jmp error

char_got_char
                ldy $00,x ;  get addr from NOS
                lda $0000,y ;  LDA 0000,Y - could be C@
                and #$00ff
                tay
                
                inx
                inx
                
z_char          rts


; -------------------------------------------------------------------
; CHARPLUS ( u -- u+1 ) X bytes / X cycles
; Adds the size of a character to the value on top of the stack. Since our
; character size is one, this is the same code as 1+, see there


; -------------------------------------------------------------------
; CHARS ( u -- u ) X bytes / X cycles
; Return the size in bytes of the number of characters on the top of the stack.
; In this case, does nothing
xt_chars

                nop ;  will be removed during native compile
z_chars         rts

; -------------------------------------------------------------------
; CMOVE ( addr1 addr2 u -- ) X bytes / X cycles
; Move characters from a lower to a higher address. Because of the danger of
; overlap, we must start at the end of the source string (addr1+u) and copy
; byte-by-byte to the end of the destination address (addr2+u). This is what the
; MVP instruction is for. Use MOVE if you are not sure what to do.
;       =====* source
;          ====* destination
xt_cmove
                ; We start at the end of the blocks, so we have to increase both
                ; addr1 and addr2 by u
                tya
                clc
                adc $02,x ;  source, goes in X
                dec a ;  convert length to index
                sta $02,x

                tya
                clc
                adc $00,x ;  destination, goes in Y
                dec a ;  convert length to index
                
                stx tmpdsp ;  keep DSP safe

                dey
                phy ;  save number of bytes to transfer

                tay ;  destination now in Y

                lda $02,x ;  get source address
                tax

                pla ;  retrieve number of bytes to transfer
                mvp 0,0

                ldx tmpdsp
                ldy $04,x

                txa ;  It's worth addition for three cells dropped
                clc
                adc #$0006
                tax

z_cmove         rts

; -------------------------------------------------------------------
; CMOVE> ( addr1 addr 2 u -- ) X bytes / X cycles
; Move characters from a higher to a lower address. Because of the danger of
; overlap, we must start at the beginning of the source (addr1) to copy it
; byte-by-byte to the beginning of the destination (addr2). This is what the MVN
; instruction is for. Use MOVE if you are not sure what to do.
;          *==== source
;       *===== destination
xt_cmoveup
                stx tmpdsp ;  keep DSP safe

                dey
                phy ;  save number of bytes to transfer

                lda $00,x ;  get destination address
                tay

                lda $02,x ;  get source address
                tax

                pla ;  retrieve number of bytes to transfer
                mvn 0,0

                ldx tmpdsp
                ldy $04,x

                txa ;  It's worth addition for three cells dropped
                clc
                adc #$0006
                tax

z_cmoveup       rts


; -------------------------------------------------------------------
; COMPILE-ONLY ( -- ) 8 bytes / X cycles
; Mark the most recently defined word as COMPILE-ONLY. The alternative (and
; traditional) way to do this is to include a word ?COMPILE that makes sure
; we're in compile mode
xt_compile_only
.al
                lda #CO
                xba ;  flags are MSB
                ora (dp) ;  ORA (DP)
                sta (dp)

z_compile_only  rts


; -------------------------------------------------------------------
; COMPILE, ( xt -- ) X bytes / X cycles
; Compile a given xt in the current word definition. It is an error if we are
; not in the compile state. Because we are using subroutine threading, we can't
; use , (COMMA) to compile new words the traditional way. By default, native
; compiled is allowed, unless there is a NN (Never Native) flag associated. 
; If not, we use the value NC_LIMIT (from definitions.tasm) to decide if the code 
; is too large to be natively coded: If the size is larger than NC_LIMIT, we silently 
; use subroutine coding. If the AN (Always Native) flag is set, the word is always
; natively compiled
xt_compilecomma
        .al
                ; First, see if this is Always Native compile word by checking
                ; the AN flag. We need the nt for this
                phy ;  save copy of xt

                jsr xt_int_name ;  ( xt -- nt )

                lda $0000,y ;  Get content of nt
                xba ;  flags are MSB
                and #AN ;  mask everything but Compile Only bit
                beq compile_check

                ; We're natively compiling no matter what. Get the length and
                ; compile as code
                jsr xt_wordsize ;  ( nt -- u )
                bra compile_as_code

compile_check
                ; Now see if native compile is even allowed by checking the NN
                ; flag
                lda $0000,y
                xba
                and #NN
                bne compile_as_jump

                ; Native compile is legal, but we have to see what limit the
                ; user set. WORDSIZE takes nt
                jsr xt_wordsize ;  ( nt -- u )
                tya
                clc
                cmp nc_limit
                bcs compile_as_jump ;  if too large, compile as a jump

compile_as_code
                ; We arrive here with the length of the word TOS ( u ) and xt on
                ; top of the return stack. MOVE will need ( xt cp u ) on the
                ; Data Stack
                dex
                dex
                pla
                sta $00,x ;  ( xt u )

                dex
                dex
                lda cp
                sta $00,x ;  ( xt cp u )
                

                ; --- SPECIAL CASES ---

                ; 1. Don't compile NOP instructions: Length of code is 1, and
                ; the instruction is $EA
                tya
                dec a
                bne compile_not_nop

                lda ($02,x)
                and #$00ff
                cmp #$00ea ;  opcode for NOP
                bne compile_not_nop

                ; It's a single NOP. Clear the data stack and return
                ldy $04,x
                txa
                clc
                adc #$0006
                tax

                bra z_compilecomma

compile_not_nop

                ; 2. Strip PLA/PHA off >R and R>
                lda $02,x ;  get xt
                cmp #xt_tor
                beq compile_r
                cmp #xt_fromr
                beq compile_r

                ; 3. Strip off stuff from 2>R and 2R>
                cmp #xt_twotor
                beq compile_2r
                cmp #xt_twofromr
                beq compile_2r

                bra compile_move ;  not a special case
                
compile_r
                ; We have either >R or R>. To simplify, drop the first and last
                ; instruction (one byte). 
                inc $02,x ;  start one byte later
                dey ;  transfer two bytes less
                dey
                bra compile_move
                
compile_2r
                ; We have either 2>R or 2R>. To simplify, drop the first and
                ; last three bytes 
                inc $02,x
                inc $02,x
                inc $02,x
                tya
                sec
                sbc #$0006
                tay ;  fall through to compile_move

compile_move
                ; Enough of this, compile the word already

                phy ;  we need a copy of length for the CP

                jsr xt_move ;  ( xt cp u -- )

                pla
                clc ;  update CP
                adc cp
                sta cp

                bra z_compilecomma

compile_as_jump
                ; Compile xt as a subroutine jump. 
                ply ;  get xt back
        .setas
                lda #$20 ;  opcode for JSR
                sta (cp) ;  STA (CP)
        .setal
                inc cp

                ; There is no "sty.di" instruction, so we have to do this the
                ; hard way
                tya
                sta (cp)
                inc cp
                inc cp

                ldy $00,x
                inx
                inx
                
z_compilecomma  rts


; -------------------------------------------------------------------
; CONSTANT ( "name" n -- ) X bytes / X cycles
; Associate a fixed value with a word. This could be realized as 
; CREATE , DOES> @  as well. We do more in assembler but let CREATE do the heavy
; lifting. 
; See http://www.bradrodriguez.com/papers/moving3.htm for a primer on how
; this works in various Forths. 
xt_constant
                jsr xt_create

                ; CREATE by default installs a subroutine jump to DOVAR, but we
                ; actually want DOCONST this time. Go back two bytes and repace
                ; the subroutine jump target
                lda cp
                dec a
                dec a
                sta tmp1

                lda #doconst
                sta (tmp1) ;  STA (TMP1)

                ; Save TOS in next cell. This is a direct version of COMMA
                tya ;  there is no "sty.di cp"
                sta (cp)
                inc cp
                inc cp

                ldy $00,x ;  DROP
                inx
                inx ;  drop through to adjust_z
                
                ; Now the length of the complete word (z_word) has increased by
                ; two. We need to update that number or else words such as SEE
                ; will ignore the PFA. We use this same routine for VARIABLE,
                ; VALUE and DEFER
adjust_z
                jsr xt_latestnt ;  gives us ( nt )

                ; z_word is kept six bytes further down
                tya
                clc
                adc #$0006
                tay

                lda $0000,y ;  LDA 0000,Y
                inc a
                inc a
                sta $0000,y

                ldy $00,x ;  get rid of nt
                inx
                inx

z_constant      rts


; -------------------------------------------------------------------
; COUNT ( c-addr -- addr u ) 14 bytes / X cycles
; Convert old-style character string to address-length pair. Note that the
; length of the string c-addr ist stored in character length (8 bit), not cell
; length (16 bit). This is rarely used these days, though COUNT can also be used
; to step through a string character by character. 
xt_count
        .al
        .xl
                tya
                inc a ;  String address starts one char later

                dex
                dex
                sta $00,x ;  NOS
                
                lda $0000,y ;  LDA $0000,Y  first byte is length
                and #$00ff ;  get rid of whatever was MSB
                tay ;  TOS
                
z_count         rts


; -------------------------------------------------------------------
; CR ( -- ) X bytes / X cycles
; Cause following output to appear at beginning of next line
xt_cr
                lda #AscLF ;  test with AscCR for emulators
                jsr emit_a

z_cr            rts

; -------------------------------------------------------------------
; CREATE ( "name" -- ) X bytes / X cycles
; Create a Dictionary entry associated with "name", used for various words,
; especially for VARIABLE. When called, this new word will return the associated
; address.
xt_create
        .al
                jsr xt_parse_name ;  ( -- addr u )
                bne create_got_name

                ; if we got a zero-length name string, complain and abort
                lda #es_noname
                jmp error

create_got_name
                ; Remember the first free byte of memory as the start of the new
                ; word
                lda cp
                sta tmp1 ;  save start of new word

                ; Enforce limit on 255 char length names by masking the MSB
                ; of the length of the given string. We arrive here with 
                ; ( addr u ) 
                tya
                and #$00ff
                sta tmp2 ;  save length of name string

                ; We need 8 bytes + the length of the name string for our new
                ; header. This is also the offset for the start of the code
                ; field (the xt_ label) so we need to remember it. Otherwise, we
                ; could just allot the space afterwards. 
                clc
                adc #$0008
                sta tmp3 ;  total bytes required for header

                ; We need to allocate three more bytes for the hardcoded
                ; code field area (CFA), the "payload" of the word which by
                ; default will be a subroutine jump to DOVAR
                inc a
                inc a
                inc a

                ; Instead of jumping to ALLOT, we do things by hand for speed
                ; and so we don't have to fool around with the stack
                clc
                adc cp
                sta cp

                ; Now we walk through the header, using Y as the index. See
                ; drawing of header in headers.tasm file for reference. We
                ; arrive here with ( addr u ) still from PARSE-NAME. We need
                ; that addr later for the name string, so we push it to the
                ; Return Stack. We'll clean up the Data Stack later
                lda $00,x
                pha

                ; HEADER BYTES 0,1: Length byte and flags
                ldy #$0000 ;  Y is now an index, not TOS
                lda tmp2 ;  get length byte
                sta (tmp1),y ;  STA (TMP1),Y
                iny
                iny

                ; BYTES 2,3: Next word in the dictionary (its nt). This is the
                ; current Dictionary Pointer
                lda dp
                sta (tmp1),y
                iny
                iny
                
                ; BYTES 4,5: Start of code field (xt of this word, "xt_" link)
                ; This begins after the header, so we take the length of the
                ; header, which we saved in tmp3, and use it as an offset to 
                ; the address of the start of the word
                lda tmp1 ;  can't use CP, because we've allotted space
                sta dp ;  while we've got it, make old CP the new DP

                clc
                adc tmp3 ;  total header length
                sta (tmp1),y
                iny
                iny
               
                ; BYTES 6,7: End of code ("z_" link)
                ; By default, we execute a jump to the DOVAR routine, so we need
                ; to move three bytes down, and then one more byte so the z_
                ; label points to the (fictional) RTS instruction for correct
                ; compilation. The start of the code field is still in A
                inc a
                inc a
                inc a
                sta (tmp1),y
                iny
                iny

                ; BYTE 8: Start of name string
                ; The addr of the string is on the Return Stack, the length of
                ; the name string is in tmp2. We subtract eight from the address
                ; so we can use the same loop index
                pla ;  get back string address
                sec
                sbc #$0008
                sta tmp3
        .setas
-
                lda (tmp3),y
                sta (tmp1),y
                iny
                dec tmp2
                bne -

                ; After the name string, comes the Code Field (start at xt, that
                ; is, the xt_ label of the word) which is initially a jump to the
                ; subroutine to DOVAR. We're still in 8-bit A-register, which is
                ; good
                lda #$20 ;  opcode of JSR
                sta (tmp1),y
                iny ;  single increase only because we have 8-bit A

                lda #<dovar
                sta (tmp1),y
                iny

                lda #>dovar
                sta (tmp1),y

        .setal
                ; We're done. Restore Data Stack (2DROP)
                ldy $02,x
                inx
                inx
                inx
                inx
                
z_create        rts


; -------------------------------------------------------------------
; DEFER ( "name" -- ) X bytes / X cycles
; Reserve an name that can be linked to various xt by IS. The ANSI reference
; implementation is CREATE ['] ABORT , DOES> @ EXECUTE ; but we use this as
; a low-level word so we can set stuff up earlier and faster
xt_defer
                jsr xt_create
                
                ; CREATE by default installs a subroutine jump to DOVAR, but we
                ; actually want DODEFER this time. Go back two bytes and repace
                ; the subroutine jump target
                lda cp
                dec a
                dec a
                sta tmp1

                lda #dodefer
                sta (tmp1) ;  STA (TMP1)

                ; DODEFER executes the next address it finds after its call. As
                ; a default, we include the error "Defer not defined"
                lda #defer_error
                sta (cp)
                inc cp
                inc cp

                jsr adjust_z ;  adjust the header to the correct length
                
z_defer         rts


; -------------------------------------------------------------------
; DIGIT? ( char -- u f | char f )  X bytes / X cycles
; Convert a single ASCII character to a number in the current radix. Inspired by
; the pForth instruction DIGIT in pForth, see
; https://github.com/philburk/pforth/blob/master/fth/numberio.fth
; Rewritten from DIGIT>NUMBER in Tali Forth. Note in contrast to pForth, we get
; the base (radix) ourselves instead of having the user provide it. There is no
; standard name for this routine, which itself is not ANSI; we use DIGIT?
; following pForth and Gforth. 
xt_digitq
        .al
                tya
                and #$00ff ;  paranoid

        .setas 
                ; Make sure we're not below the ASCII code for '0'
                cmp #'0'
                bcc dq_notdigit

                ; Then see if we are below '9', because that would make this
                ; a normal number
                cmp #'9'+1 ;  This is ':'
                bcc dq_checkbase

                ; Well, then let's see if this is the gap between '9' and 'A' so
                ; we can treat the whole range as a number
                cmp #'A'-1 ;  This is '@'
                bcc dq_notdigit

                ; Probably a letter, so we make sure it is uppercase
                cmp #'a'
                bcc dq_case_done ;  not lower case, too low
                cmp #'z'+1
                bcs dq_case_done ;  not lower case, too high

                clc ;  just right
                adc #$e0 ;  offset to uppercase (wraps)

dq_case_done
                ; Get rid of the gap between '9' and 'A' so we can treat the
                ; whole range as one number
                sec
                sbc #$07 ;  fall through to dq_checkbase

dq_checkbase
                ; We have a number, now see if it inside the range given by BASE
                sec
                sbc #'0' ;  This is also the actual conversion step
                cmp base
                bcc dq_success
                
dq_notdigit
                ; not a digit, add a false flag
                dex
                dex
                sty $00,x ;  keep the offending character in NOS
                ldy #$0000
        .setal
                bra z_digitq

dq_success
                dex
                dex
        .setal
                sta $00,x ;  put the number in NOS
                ldy #$0ffff
                
z_digitq        rts


; -------------------------------------------------------------------
; DPLUS ( d d -- d ) X bytes / X cycles
; Add two double cell numbers
xt_dplus
        .al
                phy ;  save hi word of first number, frees Y
                lda $00,x ;  lo word of first number
                clc
                adc $04,x ;  add lo word of second number
                tay

                pla ;  get hi word of first number
                adc $02,x ;  add hi word of second number

                inx
                inx
                inx
                inx
                
                sty $00,x ;  lo result goes NOS
                tay ;  to result goes TOS

z_dplus         rts

; -------------------------------------------------------------------
; DMINUS ( d d -- d ) X bytes / X cycles
; Subtract two double cell numbers
xt_dminus
        .al
                lda $04,x ;  lo word NOS
                sec
                sbc $00,x ;  lo word TOS
                pha

                sty $00,x ;  use as temp storage for hi word TOS
                lda $02,x ;  hi word, NOS
                sbc $00,x ;  hi word, TOS
                tay ;  result hi word now TOS

                inx
                inx
                inx
                inx

                pla
                sta $00,x ;  result lo word now NOS
                
z_dminus        rts


; -------------------------------------------------------------------
; D>S ( ud -- u ) X bytes / X cycles
; Convert double cell number to single cell. Note this currently does not
; respect the sign, in constrast to Gforth - this is simply DROP
; TODO make this work the way Gforth's does
xt_dtos
        .al
                ldy $00,x
                inx
                inx

z_dtos          rts


; -------------------------------------------------------------------
; DABS ( d -- ud ) X bytes / X cycles
; Return the absolute value of a double number
; TODO recode in assembler
xt_dabs
                ; double cell is TOS 
                tya ;  force flag test
                beq z_dabs ;  already positive, life is good

                jsr xt_dnegate

z_dabs          rts


; -------------------------------------------------------------------
; DECIMAL ( -- ) 7 bytes / X cycles
; Change radix for number conversion to 10
xt_decimal
        .al
                lda #$000a
                sta base

z_decimal       rts


; -------------------------------------------------------------------
; DEPTH ( -- u ) 14 bytes / X cycles
; Push the number of entries in cells (not bytes) on the parameter stack.
; Assumes X is valid as the DSP.
xt_depth
        .al
                ; We've got zero entries when X is dsp0
                stx tmpdsp
                lda #dsp0
                sec
                sbc tmpdsp

                ; now divide by two because each cells is to bytes long
                lsr a

                dex
                dex
                sty $00,x

                ; push result to stack
                tay

z_depth         rts

; -------------------------------------------------------------------
; DNEGATE ( d -- d ) 19 bytes / X cycles
; Change the sign of a double number. This is the double equivalent of NEGATE
xt_dnegate
        .al
                ; start off with LSW (in NOS)
                lda $00,x
                eor #$0ffff

                ; INC doesn't affect the carry flag, so we have to do this the
                ; hard way
                clc
                adc #$0001
                sta $00,x

                ; now MSW (in TOS)
                tya
                eor #$0ffff
                adc #$0000 ;  we are only interested in the carry
                tay
             
z_dnegate       rts



; -------------------------------------------------------------------
; ?DO ( limit start -- )  X bytes / X cycles
; Compile-time part of ?DO. This may not be natively compiled. 
xt_qdo
		; ?DO shares most of its code with DO. Use the tmp1 flag to
                ; decide which is which
                lda #$0ffff
                sta tmp1
                bra do_common ;  continue with do_common

; -------------------------------------------------------------------
; DO ( limit start -- )  X bytes / X cycles
; Compile-time part of DO. ": DO POSTPONE (DO) HERE ; IMMEDIATE COMPILE-ONLY ;"
; To work with LEAVE, we compile a routine that pushes the end address to the
; Return Stack at run time. This is based on a suggestion by Garth Wilson, see
; loops.txt for details. This may not be native compile.
xt_do
                ; DO and ?DO share most of their code, use tmp1 as a flag. 
                stz tmp1 ;  0 is DO, drop through to DO_COMMON

do_common
                ; We start by compiling the opcode for LDA.# ($A9). Because
                ; we're little endian, we don't have to switch registers sizes,
                ; we just have to make sure the MSB will be overwritten
                lda #$00a9
                sta (cp)
                inc cp

                ; We push HERE to the Data Stack so LOOP/+LOOP knows where to
                ; compile the address we need to LDA.# at runtime
                dex
                dex
                sty $00,x
                ldy cp
                
                ; Reserve two bytes for the address
                inc cp
                inc cp

                ; Save the opcode for PHA ($48)
                lda #$0048
                sta (cp)
                inc cp

                ; Make space to compile either (?DO) or (DO)
                dex
                dex
                sty $00,x

                ; compile (?DO) or (DO) 
                lda tmp1
                beq do_do ;  childish, yes

                ldy #xt_pqdo
                bra do_compile

do_do
                ldy #xt_pdo

do_compile
                jsr xt_compilecomma

                ; HERE. We put this on the Data Stack for LOOP/+LOOP. Note this
                ; has nothing to do with the HERE we've saved for LEAVE
                dex
                dex
                sty $00,x
                ldy cp

z_qdo
z_do
                rts

; -------------------------------------------------------------------
; DOES> ( -- ) X bytes / X cycles
; Create the payload for defining new defining words. See the file
; docs/create-does.txt and 
; http://www.bradrodriguez.com/papers/moving3.htm for a discussion of 
; DOES>'s internal workings. This uses tmp1 and tmp2
; TODO see if this creates a correct z_word address
xt_does
                ; compile a subroutine jump to the runtime of DOES>
                pea does_rt
                jsr cmpl_subroutine

                ; compile a subroutine jump to DODOES. In traditional terms,
                ; this is the Code Field Area (CFA) of the new word
                pea dodoes
                jsr cmpl_subroutine
                
z_does          rts

does_rt
                ; Runtime portion of DOES>. This replaces the subroutine jump to
                ; DOVAR that CREATE automatically encodes by a jump to the
                ; address that contains a subroutine jump to DODOES. We don't
                ; jump to DODOES directly because we need to work our magic with
                ; the return addresses
                pla
                inc a ;  increase by one because of RTS mechanics
                sta tmp1

                ; CREATE has also already modified the DP to point to the new
                ; word. We have no idea which instructions followed the CREATE
                ; command if there is a DOES> so the CP could point anywhere by
                ; now.
                lda dp

                ; The address of the word's xt is four bytes down (see
                ; header.tasm for details).
                clc
                adc #$0004
                sta tmp2

                ; Now we get that address and add one byte to skip over the JSR
                ; opcode
                lda (tmp2) ;  LDA (TMP2)
                inc a
                sta tmp2 ;  Points to address to be replaced

                ; Replace the DOVAR address
                lda tmp1
                sta (tmp2) ;  STA (TMP2)

                ; Since we removed the return address that brought us here, we
                ; go back to whatever the main routine was. Otherwise, we we
                ; smash into the subroutine jump to DODOES.
                rts
                

; -------------------------------------------------------------------
; DROP ( n -- ) 4 bytes / 9 cycles
; Drop first entry on Data Stack

xt_drop
                ldy $00,x
                inx
                inx

z_drop          rts


; -------------------------------------------------------------------
; DUP  ( n -- n n ) 4 bytes / 9 cycles
; Duplicate first entry on Data Stack
xt_dup
                dex
                dex
                sty $00,x

z_dup           rts

; -------------------------------------------------------------------
; EMIT ( char -- ) X bytes / X cycles
; Run-time default for EMIT. The user can revector this by changing the value of
; the OUTPUT variable. We ignore the MSB completely, and do not check to see if
; we have been given a valid ASCII character. Note that we keep the A register
; in 16 bit mode all the time - it is up to the kernel routine stored at OUTPUT
; to deal with that. Don't make this native compile
xt_emit
        .al
                ; we put the value in A so we don't have to switch the XY
                ; register size
                tya

                ; we DROP immediately so we can JMP.I to the output routine and
                ; can use its RTS to take us back to the caller
                ldy $00,x
                inx
                inx
emit_a
                ; Lots of times we want to print the character in A without
                ; fooling around with the Data Stack. EMIT_A assumes a 16 bit
                ; wide A register with the character in LSB and does not touch
                ; the Data Stack, but can still be vectored via OUTPUT. Call it
                ; with JSR as you would XT_EMIT
                jmp (output) ;  call to kernel, JSR/RTS

z_emit         ; never reached 


; -------------------------------------------------------------------
; ERASE ( addr u -- ) X bytes / X cycles
; Set a region of memory to zero. Uses tmp2
xt_erase
        .al
                dex
                dex
                sty $00,x

                ldy #$0000 ;  falls through to FILL


; -------------------------------------------------------------------
; EXIT ( -- ) X bytes / X cycles
; Return control to the calling word immediately. If we're in a loop, we need to
; unloop first, and get everything we we might have put on the Return Stack off
; as well. This should be natively compiled
xt_exit
                rts
z_exit                          ; never reached


; -------------------------------------------------------------------
; FILL ( addr u b -- ) X bytes / X cycles
; Fill the given region of memory with the LSB of the TOS. Shares code with
; ERASE
xt_fill
                lda $02,x ;  address is 3OS
                sta tmp2

                tya
                ldy $00,x ;  don't bother with drop, to it later
.setas
erase_loop
                dey
                bmi erase_done

                sta (tmp2),y
                bra erase_loop
	
erase_done
        .setal
                ldy $02,x ;  dump three elements off the sack
                txa
                clc
                adc #$0006
                tax
z_fill
z_erase         rts


; -------------------------------------------------------------------
; EVALUATE ( addr u -- ) X bytes / X cycles
; Execute string. Set SOURCE-ID to -1, make addr u the input source, 
; set >IN to zero. After processing the line, revert to old input source. 
xt_evaluate
                ; We follow pforth's procedure of pushing SOURCE, SOURCE-ID, and
                ; >IN to the Return Stack
                lda toin ;  >IN
                pha
                lda insrc ;  Input Source (SOURCE-ID)
                pha
                lda cib
                pha
                lda ciblen
                pha

                ; set SOURCE-ID to -1
                lda #$0ffff
                sta insrc

                ; set >IN to zero
                stz toin

                ; move TOS and NOS to input buffers
                sty ciblen
                lda $00,x
                sta cib

                ; dump address string from stack
                ldy $02,x
                inx
                inx
                inx
                inx

                jsr interpret

                ; restore state from before evaluate
                pla
                sta ciblen
                pla
                sta cib
                pla
                sta insrc
                pla
                sta toin
                
z_evaluate      rts


; -------------------------------------------------------------------
; EXECUTE ( xt -- ) X bytes / X cycles
; Run a word with help of its xt on the TOS

; Reserve three bytes for the jump - three in case we want to expand to the full
; range
; TODO move this to someplace that is assured to be RAM, not possibly ROM
execute_ip      .byte 00, 00, 00

xt_execute
        .al
        .xl
                ; Store the xt for later use and then drop it off the stack
                sty execute_ip
                ldy $00,x
                inx
                inx

                ; Only JMP has the addressing mode we need. All our Forth
                ; words end with a RTS instruction, so they will take us back to
                ; the original caller of this routine without us having to muck
                ; about with the Return Stack. 
                jmp (execute_ip) ;  JMP (EXECUTE_IP)
  
z_execute       ; empty, no RTS required
                

; -------------------------------------------------------------------
; FALSE ( -- f ) 7 bytes / 12 cycles
; Pushes value $0000 for Forth true on Data Stack. This is the same code as for 
; ZERO, see there. Dictionary entry should have xt_zero/z_zero instead of
; xt_false/z_false


; -------------------------------------------------------------------
; FIND ( cs-addr -- addr 0 | xt 1 | xt -1 ) X bytes / X cycles
; Find word in Dictionary. Included for backwards compatibility, Liara Forth
; follows Gforth by replacing this with FIND-NAME. Counted string either returns
; address with a fail flag if not found in the Dictionary, or the xt with a flag
; to indicate if this is immediate or not. FIND is a wrapper around FIND-NAME.
; See https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/Word-Lists.html
; and https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/Name-token.html
; for better solutions.
xt_find
                ; Convert counted string address to modern format
                jsr xt_count ;  ( addr u )

                ; Save address in case the conversion fails
                lda $00,x
                pha

                jsr xt_find_name ;  ( nt | 0 )

                tya ;  force flag check
                bne find_found
                
                ; No word found. Return the address of the string, leaving 0 as
                ; a false flag TOS
                dex ;  ( <?> 0 )
                dex
                ldy #$0000
                pla
                sta $00,x ;  ( addr 0 )
                bra z_find

find_found
                ; We have a nt. Now we have to convert it to the format that
                ; FIND wants to return Arrive here with ( nt ) 
                pla ;  we won't need the address after all

                ; We will need the nt later
                phy
                
                jsr xt_name_int ;  ( nt -- xt )
                dex
                dex
                sty $00,x ;  ( xt <?> )

                ; If immediate, return 1 (not: zero), else return -1
                ply ;  get nt back
                lda $0000,y
                ldy #$0000 ;  prepare flag

                xba ;  flags are MSB
                and #IM ;  Mask all but IM bit

                bne find_imm ;  IMMEDIATE word, return 1
                dey ;  not emmediate, return -1
                bra z_find

find_imm
                iny

z_find          rts

; -------------------------------------------------------------------
; FIND-NAME ( addr u -- nt | 0 ) 91 bytes / X cycles
; Given a string, find the Name Token (nt) of a word or return zero if the word
; is not in the dictionary. We use this instead of ancient FIND to look up words
; in the Dictionary passed by PARSE-NAME. Note this returns the nt, not the xt
; of a word like FIND. To convert, use NAME>INT. This is a Gforth word. See
; https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/Name-token.html 
; FIND calls this word for the hard word
xt_find_name
                ; We abort when we get an empty string, that is, one with
                ; a length of zero TOS. We could test for this, but it will
                ; happen so rarely that the speed penalty is higher if we run
                ; the test for every single call. Looking for an empty string
                ; does force us to check the whole dictionary, though. The test
                ; would be 3 bytes and 4 to 6 cycles longer: 
                ;       tya                     ; force flag check
                ;       beq find_name_failure
        .al
        .xl
                ; set up loop for the first time
                sty tmptos ;  length of mystery string in tmptos, Y now free

                ldy dp
                sty tmp1 ;  nt of first Dictionary word

                ldy $00,x
                sty tmp2 ;  address of mystery string, was NOS

find_name_loop
                ; First quick test: Are strings the same length?
                lda (tmp1) ;  LSB in first header word is length
                and #$00ff
                cmp tmptos ;  we test LSB
                ; Most of the time, it will not be the same, so we save one
                ; cycle pro loop if we only take the branch when they are the
                ; same
                beq find_name_chars

find_name_next_entry
                ; next header address is two bytes down
                inc tmp1
                inc tmp1
                lda (tmp1) ;  LDA (TMP1)

                ; a zero entry marks the end of the Dictionary
                beq find_name_failure_16

                sta tmp1 ;  new header
                bra find_name_loop

find_name_chars
                ; Yes, same length, so we compare characters

                ; Switch A to 8 bit for this 
        .setas
                ; Second quick test: Check first char, which is 8 bytes into the
                ; header 
                ldy #$0008
                lda (tmp1),y ;  LDA (TMP1),Y - first char of entry
                cmp (tmp2) ;  CMP (TMP2) - first char of mystery string
                beq find_name_all_chars
                
find_name_char_nomatcnt_8
                ; First char is not the same, next entry
        .setal
                bra find_name_next_entry

find_name_all_chars
        .as
                ; String length is the same, and the first character is the
                ; same. If the word is only one character long, we're done
                ldy tmptos
                dey ;  faster and shorter than CPY.# 01
                beq find_name_success
                
                ; No such luck: The strings are the same length and the first
                ; char is the same, but the word is more than one char long. So
                ; we suck it up and compare every single character. We go from
                ; back to front, because words like CELLS and CELL+ would take
                ; longer otherwise. We can also shorten the loop by one because
                ; we've already compared the first char. 

                ; Even worse, we have to add 8 bytes to address of Dictionary
                ; string to allow testing with one loop. We need this like
                ; a hole in the head because we just switched A to 8 bit.
                ; However, staying with an 8-bit A is even slower.
        .setal
                lda tmp1 ;  address of Dictionary string
                clc
                adc #$0008
                sta tmp3
        .setas
                ldy tmptos ;  get length of strings as loop index
                dey ;  first index is length minus 1

-
                lda (tmp2),y ;  LDA (TMP2),Y - last char of mystery string
                cmp (tmp3),y ;  CMP (TMP1),Y - last char of DP string
                bne find_name_char_nomatcnt_8
                dey ;  start of string (Y=0) was already tested
                bne -
                
find_name_success
                ; If we reach here, the strings are the same and we have a match
                ; We get here with an 8 bit A
        .setal    
                ldy tmp1 ;  get the correct DP
                bra find_name_done


find_name_failure_16
                ; Word not found in Dictionary, return zero. Assumes A is 16
                ; bit
                ldy #$0000 ;  fall thru

find_name_done
                inx ;  drop old address (NIP)
                inx

z_find_name     rts


; -------------------------------------------------------------------
; FM/MOD ( d n1 -- n2 n3 ) X bytes / X cycles
; Floored division, compare with SM/REM. We define FM/MOD in terms of UM/MOD,
; see http://git.savannah.gnu.org/cgit/gforth.git/tree/prim We prefer to use
; SM/REM for further words. You could also define FM/MOD in Terms of SM/REM, 
; see http://www.figuk.plus.com/build/arith.htm
; Original Forth: DUP >R DUP 0< IF NEGATE >R DNEGATE R> THEN >R DUP 0< R@ AND + 
; R> UM/MOD R> 0< IF SWAP NEGATE SWAP THEN ;
; TODO this is just a 1:1 list of jumps, optimize once it is working
xt_fmmod
                jsr xt_dup
                jsr xt_tor
                jsr xt_dup

                tya ;  0< IF
                bpl fmmod_1

                ldy $00,x
                inx
                inx

                jsr xt_negate
                jsr xt_tor
                jsr xt_dnegate
                jsr xt_fromr

                bra fmmod_1_1
fmmod_1
                ldy $00,x
                inx
                inx
fmmod_1_1
                jsr xt_tor
                jsr xt_dup
                jsr xt_zero_less
                jsr xt_rfetch
                jsr xt_and
                jsr xt_plus
                jsr xt_fromr
                jsr xt_ummod
                jsr xt_fromr

                tya
                bpl fmmod_2

                ldy $00,x
                inx
                inx

                jsr xt_swap
                jsr xt_negate
                jsr xt_swap

                bra fmmod_2_1
fmmod_2

                ldy $00,x
                inx
                inx

fmmod_2_1

z_fmmod         rts


; -------------------------------------------------------------------
; KEY ( -- char ) X bytes / X cycles
; Get one character from the input, without echoing. 
xt_key
           .al

                dex             ; make room on Data Stack
                dex
                ldy $00,x
                
                ; There is no "jsr.i" instruction, so we have to do this the
                ; hard way
                stx tmpdsp
                ldx #$0000
                jsr (input,x) ;  JSR (INPUT,X) - returns char in A
                ldx tmpdsp

                tay

z_key           rts


; -------------------------------------------------------------------
; KEY? ( -- f ) X bytes / X cycles
; See if there is a character waiting in the input buffer.
xt_keyq
        .al
                dex
                dex
                sty $00,x

                ldy #$0000 ;  default FALSE

                ; have_chr sets the Carry Flag to 1 if there is a character
                ; waiting, else to 0. A is destroyed
                jsr have_chr
                bcc z_keyq

                dey ;  wrap for TRUE
                
z_keyq          rts

; -------------------------------------------------------------------
; I ( -- n )(R: n -- n )  X bytes / X cycles
; Copy loop counter (top of Return Stack) to Data Stack. This is not the same as
; R@ because we use a fudge factor for loop control; see (DO) for more details.
; Native compile for speed. 
xt_i
                dex
                dex
                sty $00,x

                ; get the fudged value of the Return Stack
                sec
                lda $01,s
                sbc $03,s

                tay

z_i             rts


; -------------------------------------------------------------------
; IMMEDIATE ( -- ) X bytes / X cycles
; Mark the most recently defined word as IMMEDIATE. Will only affect the last
; word in the Dictionary. If the words is still in ROM for some reason, this
; will have no effect and will fail without an error message
xt_immediate
        .al
                lda #IM ;  Immediate flag
                xba ;  flags are MSB
                ora (dp) ;  ORA (DP)
                sta (dp)
                
z_immediate     rts


; -------------------------------------------------------------------
; INPUT ( -- addr ) X bytes / X cycles
; Return the address where the jump targeet for KEY is stored
xt_input
                dex
                dex
                sty $00,x

                ldy #input

z_input         rts


; -------------------------------------------------------------------
; INT>NAME ( xt -- nt ) X bytes / X cycles
; Given an execution token (xt), return the name token (nt). This is called
; >NAME in Gforth, but changed to INT>NAME for Liara to fit better with
; NAME>INT.
xt_int_name
                ; Unfortunately, to find the header, we have to walk through the
                ; dictionary
                lda dp ;  nt of first Dictionary word
                sta tmp1

                sty tmptos ;  xt of mystery word
                ldy #$0004 ;  xt in header is two bytes down

in_loop
                lda (tmp1),y ;  LDA (TMP1),Y - get xt of current nt
                cmp tmptos
                beq in_found

                ; no joy, next header address is two bytes down
                inc tmp1
                inc tmp1
                lda (tmp1) ;  LDA (TMP1)

                ; a zero entry marks the end of the Dictionary
                beq in_notfound

                sta tmp1 ;  new header
                bra in_loop

in_notfound
                lda #es_syntax
                jmp error

in_found
                ldy tmp1 ;  replace xt by nt

z_int_name      rts


; -------------------------------------------------------------------
; INVERT ( n -- n ) 5 bytes / X cycles
; Complement of TOS
xt_invert
        .al
                tya
                eor #$0ffff
                tay

z_invert        rts


; -------------------------------------------------------------------
; HERE ( -- u ) 6 bytes / 13 cycles
; Push Compiler Pointer address on the Data Stack
xt_here
        .xl
                dex
                dex
                sty $00,x

                ldy cp

z_here          rts

; -------------------------------------------------------------------
; HEX ( -- ) X bytes / X cycles
; Change radix for number conversion to 16
xt_hex
        .al
                lda #$0010
                sta base

z_hex           rts

; -------------------------------------------------------------------
; HOLD ( char -- ) X bytes / X cycles
; Insert a character at the current position of a pictured numeric output string
; Code based on https://github.com/philburk/pforth/blob/master/fth/numberio.fth
; Forth code is : HOLD  -1 HLD +!  HLD @ C! ;  We use the the internal variable
; tohold instead of HLD.
xt_hold
        .al
                dec tohold ;  -1 HLD +!

                tya
        .setas
                sta (tohold) ;  STA (TOHOLD)
        .setal
                ldy $00,x
                inx
                inx

z_hold          rts


; -------------------------------------------------------------------
; J ( -- n )(R: n -- n )  X bytes / X cycles
; Copy loop counter (top of Return Stack) to Data Stack. This is not the same as
; R@ because we use a fudge factor for loop control; see (DO) for more details.
; Native compile for speed. 
xt_j
                dex
                dex
                sty $00,x

                ; get the fudged value of the Return Stack
                sec
                lda $07,s
                sbc $09,s

                tay

z_j             rts


; -------------------------------------------------------------------
; LATESTNT ( -- nt ) 7 bytes / X cycles
; Return the name token (nt) of the last word in the Dictionary. The Gforth
; version of this word is called LATEST. 
xt_latestnt
        .al
                dex ;  make room on Data Stack
                dex
                sty $00,x

                lda dp
                tay

z_latestnt      rts


; -------------------------------------------------------------------
; LATESTXT ( -- xt ) 11 bytes / X cycles
; Return the name token (xt) of the last word in the Dictionary. This is simply
; LATESTNT but four bytes down and with a FETCH
xt_latestxt
        .al
                dex ;  make room on Data Stack
                dex
                sty $00,x

                lda dp

                clc ;  xt is stored four bytes below nt in header
                adc #$0004
                tay

                lda $0000,y ;  FETCH
                tay

z_latestxt      rts


; -------------------------------------------------------------------
; LEAVE ( -- ) X bytes / X cycles
; Leave DO/LOOP construct. Note that this does not work with anything but
; a DO/LOOP in contrast to other versions such as discussed at
; http://blogs.msdn.com/b/ashleyf/archive/2011/02/06/loopty-do-i-loop.aspx 
; ": LEAVE POSTPONE BRANCH HERE SWAP 0 , ; IMMEDIATE COMPILE-ONLY" 
; See loops.txt on details of how this works. This must be native compile and not 
; IMMEDIATE
xt_leave
        .al
                ; drop limit/start entries off the Return Stack
                pla
                pla

                ; We now have the LEAVE special return address on the top of the
                ; Return Stack. This RTS must come before z_leave so native
                ; compiling doesn't ignore it
                rts

z_leave         ; not reached


; -------------------------------------------------------------------
; LITERAL ( n -- ) X bytes / X cycles
; Compile-only word to store TOS so that it is pushed on stack during runtime.
; This is a immediate, compile_only word. Test it with  : AAA [ 1 ] LITERAL ;
; for instance
xt_literal
                ; During runtime, we call the routine at the bottom by compiling 
                ; JSR LITERAL_RT. Note the cmpl_ routines use tmptos
                pea literal_rt ;  PEA LITERAL_RT
                jsr cmpl_subroutine

                ; compile the value that is to be pushed to the Data Stack at
                ; runtime. There is no "sty.di", so we have to do this the hard
                ; way. This is basically , ("comma") 
                tya
                sta (cp)
                inc cp
                inc cp

                ldy $00,x ;  DROP
                inx
                inx

z_literal       rts

literal_rt
                ; During runtime, we push the value following this word
                ; back on the Data Stack. The subroutine jump that brought us
                ; here put the address to return to on the Return Stack - this
                ; points to the data we need to get

                ; Make room on Data Stack, Y now free to use
                dex
                dex
                sty $00,x

                ; The 65816 stores (<RETURN-ADDRESS> - 1) on the Return Stack
                ; so we have to manipulate the address
                ply
                iny
                lda $0000,y ;  LDA $0000,Y - get value after jump

                iny ;  move return address past data and restore
                phy ;  so we can get back home

                tay ;  Value is now on the Data Stack ( -- n )

                rts


; -------------------------------------------------------------------
; LSHIFT ( n u -- n ) X bytes / X cycles
; Logically shift TOS u times to the left, adding zeros to the right
xt_lshift
                ; We shift at most 16 bits, because anything above that will be
                ; zeros anyway
                tya
                and #$000f
                beq lshift_done ;  if zero shifts, we're done

                tay ;  number of shifts is TOS
                lda $00,x ;  number is in NOS
lshift_loop
                asl a
                dey
                bne lshift_loop

                sta $00,x ;  put NOS, which last step will pull up
                
lshift_done
                ldy $00,x
                inx
                inx

z_lshift        rts


; -------------------------------------------------------------------
; M* "MSTAR" ( n n -- d ) 16*16 -> 32  X bytes / X cycles
; Multiply two 16 bit numbers, producing a 32 bit result. All values are signed.
; This was originally adapted from FIG Forth for Tali Forth. The original Forth
; code is : M* OVER OVER XOR >R ABS SWAP ABS UM* R> D+- ;  with 
; : D+- O< IF DNEGATE THEN ; 
; TODO Test this more once we have the Double words etc all working
xt_mstar
        .al
                ; figure out the sign
                tya
                eor $00,x

                ; um* uses all kinds of tmp stuff so we don't risk a conflict
                ; and just take the cycle hit by pushing this to the stack
                pha

                ; get the absolute value of both numbers so we can feed them to
                ; UM*, which does the real work
                tya
                bpl mstar_abs_nos
              
                ; TOS is negative so we have to ABS it
                eor #$0ffff
                inc a
                tay

mstar_abs_nos
                lda $00,x
                bpl mstar_umstar
                
                ; NOS is negative so we have to ABS it
                eor #$0ffff
                inc a
                sta $00,x

mstar_umstar
                jsr xt_umstar ;  now ( d ) on stack

                ; handle the sign
                pla

                ; postive, we don't have to care
                bpl z_mstar

                jsr xt_dnegate

z_mstar         rts


; -------------------------------------------------------------------
; MARKER ( "name" -- ) X bytes / X cycles
; Create a deletion boundry, restoring the Dictionary to an earlier state. This
; replaces FORGET in earlier Forths. Old entries are not actually deleted, but
; merely overwritten by restoring CP and DP.
xt_marker
                ; This is a defining word
                jsr xt_create

                ; Add the current DP as a payload - the DP of the marker itself
                ; TODO see if it doesn't make more sense to add nt_ of the previous
                ; word
                lda dp
                sta (cp) ;  STA (CP)
                inc cp
                inc cp

                ; DOES> by hand: Add runtime behavior and DODOES routine
                jsr does_rt
                jsr dodoes

                ; DOES> payload 
                jsr xt_fetch ;  ( nt )

                ; We now have the DP of the marker itself on the stack, but we
                ; need the DP of the previous word. That is two bytes down
                sty tmp3
                ldy #$0002 ;  overwrite TOS, won't be needing it
                lda (tmp3),y ;  LDA (TMP3),Y
                sta dp
                
                ; Adjust the CP, which is one byte after the z_ address of the
                ; word we just restored. That address is six bytes down
                ldy #$0006
                lda (dp),y ;  LDA (DP),Y
                inc a ;  first free byte is one byte further down
                sta cp

                ; clean up stack
                ldy $00,x
                inx
                inx

z_marker        rts


; -------------------------------------------------------------------
; MAX ( n m -- n ) 18 bytes / X cycles
; Compare TOS and NOS and keep which one is larger. Adapted from Lance A.
; Leventhal "6502 Assembly Language Subroutines". Negative Flag indicates which
; number is larger. See also http://6502.org/tutorials/compare_instructions.html
; and http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html 
xt_max
                tya
                cmp $00,x
                
                ; If they are the same, life is good. This step also sets the
                ; Carry flag
                beq max_nip ;  Faster than DROP because TOS is in Y

                sbc $00,x
                bvc max_no_ov ;  no overflow, skip ahead

                ; Deal with oveflow because we use signed numbers
                eor #$8000 ;  compliment negative flag

max_no_ov
                bpl max_nip ;  keep TOS
max_drop
                ldy $00,x ;  DROP so NOS is result
max_nip
                inx
                inx
                
z_max           rts


; -------------------------------------------------------------------
; MIN ( n m -- n ) 18 bytes / X cycles
; Compare TOS and NOS and keep which one is smaller Adapted from Lance A.
; Leventhal "6502 Assembly Language Subroutines". Negative Flag indicates which
; number is larger. See also http://6502.org/tutorials/compare_instructions.html
; and http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html 
xt_min
                tya
                cmp $00,x
                
                ; If they are the same, life is good. This step also sets the
                ; Carry flag
                beq min_nip ;  Faster than DROP because TOS is in Y

                sbc $00,x
                bvc min_no_ov ;  no overflow, skip ahead

                ; Deal with oveflow because we use signed numbers
                eor #$8000 ;  compliment negative flag

min_no_ov
                bmi min_nip ;  keep TOS
min_drop
                ldy $00,x ;  DROP so NOS is result
min_nip
                inx
                inx
                
z_min           rts

; -------------------------------------------------------------------
; MOVE ( addr1 addr2 u -- ) X bytes / X cycles
; Move u bytes from addr1 to addr2, so that in the end, addr2 contains exactly
; what was in addr1. This routine calls CMOVE or CMOVE>. Forth verison is
; >R 2DUP U< IF R> CMOVE> ELSE  R> CMOVE THEN ; see 
; https://groups.google.com/forum/#!topic/comp.lang.forth/-l2WlE7pEE0
; Also see CMOVE> and CMOVE and http://forum.6502.org/viewtopic.php?f=2&t=1685
xt_move
       .al 
                ; if u is zero, we just skip all of this 
                tya
                beq z_move

                ; if source and destination are the same, that would be silly as
                ; well
                lda $00,x ;  addr2 (destination)
                cmp $02,x ;  addr1 (source)
                beq z_move

                ; The destination is higher than the source, so use CMOVE, which
                ; calls MVP
                bpl move_cmoveup

                jsr xt_cmove
                bra z_move ;  don't RTS because we might be natively compiling

                ; The source is higher than the destination, use CMOVE>,
                ; which calls MVN
move_cmoveup
                jsr xt_cmoveup

z_move          rts


; -------------------------------------------------------------------
; NAME>INT ( nt -- xt ) 4 bytes / 8 cycles
; Given the Name Token (nt) of a word, return its Execute Token (xt)
; TODO deal with compile_only words, see 
; https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/Name-token.html
xt_name_int
        .al
        .xl
                ; The xt of a word beginns four bytes down from its nt
                iny
                iny
                iny
                iny
                lda $0000,y
                tay
                
z_name_int      rts

; -------------------------------------------------------------------
; NAME>STRING ( nt -- addr u ) 16 bytes / X cycles
; Given a name token (nt) of a word, return its string. This is a Gforth word
; that works with the Dictionary header entries. It is not checked if nt is
; a valid name token. There is no "STRING>NAME" - this is handled by the
; combination of PARSE-NAME and FIND-NAME
xt_name_string
        .al
        .xl
                dex ;  move NOS down one
                dex

                ; the name string of a word begins 8 bytes down from its nt,
                ; which we have as TOS
                tya
                clc
                adc #$0008
                sta $00,x ;  NOS
                
                ; the length of the name string is in the LSB of the first word
                ; of the dictionary entry header (the name token)
                lda $0000,y ;  LDA $0000,Y
                and #$00ff ;  mask all but length byte
                tay
                
z_name_string   rts


; -------------------------------------------------------------------
; NC-LIMIT ( -- addr ) X bytes / X cycles
; Address where the value of the Native Compile size limit is kept
xt_nc_limit
                dex
                dex
                sty $00,x
                ldy #nc_limit

z_nc_limit      rts

; -------------------------------------------------------------------
; NEGATE ( n -- n ) 6 bytes / X cycles
; Two's complement of TOS
xt_negate
                tya
                eor #$0ffff
                inc a
                tay

z_negate        rts

; -------------------------------------------------------------------
; NEVER-COMPILE ( -- ) X bytes / X cycles
; Forbid native compilation for last word in Dictionary
xt_never_compile
        .al
                lda #NN
                xba ;  flags are MSB
                ora (dp) ;  ORA (DP)
                sta (dp)

z_never_compile rts

; -------------------------------------------------------------------
; NIP ( n m -- m ) 2 bytes / 4 cycles
; Delete entry that is NOS
xt_nip
                inx
                inx

z_nip           rts


; -------------------------------------------------------------------
; NUMBER ( addr u -- u | d ) X bytes / X cycles
; Convert a number string to a double or single cell number. This is a wrapper
; for >NUMBER and follows the convention set out in the "Forth Programmer's
; Handbook" (Conklin & Rather) 3rd edition p. 87. Based in part on the "Starting
; Forth" code https://www.forth.com/starting-forth/10-input-output-operators/
; Gforth uses S>NUMBER? and S>UNUMBER? which return the numbers and a flag, see
; https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/Number-Conversion.html
; Another difference to Gforth is that we follow ANSI Forth that the dot to
; signal a double cell number is required to be the last character of the
; string. Number calls >NUMBER which in turn calls UM*, which uses tmp1, tmp2,
; and tmp3, so we can't use them here, which is a pain. 
xt_number
        .al
                ; The flags for sign and double are kept on the stack because
                ; we've run out of temporary variables. MSB is for minus, LSB is
                ; for double
                pea $0000

                sty tmptos ;  save length of string, freeing Y

                ; if the first character is a minus, strip it off and set
                ; a flag
        .setas
                lda ($00,x) ;  get first character
                cmp #'-'
        .setal                    ; zero flag is uneffected
                bne number_dot

                ; We have a minus. 
                pla
                ora #$0ff00 ;  MSB is minus
                pha

                inc $00,x ;  start one character later
                dec tmptos ;  reduce string length by one

number_dot
                ; if the last character is a dot, strip it off and set a flag
                lda tmptos ;  get the string length
                dec a ;  subtract one to convert length to index
                clc
                adc $00,x ;  add length of string
                tay
        .setas
                lda $0000,y ;  get last character
                cmp #'.'
        .setal
                bne number_main
                
                ; we have a dot
                pla ;  get the flag back
                ora #$00ff ;  LSB is double
                pha

                dec tmptos ;  reduce string length by one

number_main
                ; set up stack for subroutine jump to >NUMBER 
                lda $00,x ;  get the string address to safety
                stz $00,x ;  NOS is now zero
                dex
                dex
                stz $00,x ;  3OS and NOS are now zero
                dex
                dex

                sta $00,x ;  address is back as NOS
                ldy tmptos ;  length is back as TOS
        
number_loop
                jsr xt_tonumber ;  ( ud addr u -- ud addr u )

                tya ;  test length of returned string, should be 0
                beq number_ok

                ; Something went wrong during conversion, we still have stuff
                ; left over. Print error string and abort. If number was called
                ; by INTERPRET, we've already checked for words, so we're in
                ; trouble one way or another
                ; TODO print offending string
                lda #es_syntax
                jmp error
                
number_ok
                ; All characters successfully converted. Drop the string info
                ldy $02,x
                inx
                inx
                inx
                inx

                ; We have a double-cell number on the Data Stack that might have
                ; a minus and might actually be single-cell
                pla ;  get copy of the flags
                pha
                and #$00ff ;  only keep the part with the number size (LSB)
                beq number_single
                
                ; This is a double-cell number. If it had a minus, we'll have to
                ; negate it
                pla
                and #$0ff00 ;  only keep part with the sing (MSB)
                beq z_number ;  no minus, all done
                
                lda $00,x ;  DNEGATE, starts with LSW
                eor #$0ffff

                ; INC won't affect the carry flag, so we have to do this the
                ; hard way
                clc
                adc #$0001
                sta $00,x

                ; now MSW (in TOS)
                tya
                eor #$0ffff
                adc #$0000 ;  we are only interested in the carry
                tay
 
                bra z_number

number_single
                ; This is a single cell number, so we just drop the top cell
                ldy $00,x
                inx
                inx
                
                ; If we have a minus, we'll have to negate it. Note this code is
                ; doubled for speed
                pla
                and #$0ff00
                beq z_number ;  no minus, all done
                
                tya ;  NEGATE
                eor #$0ffff
                inc a
                tay ;  fall through to end
               
z_number        rts


; -------------------------------------------------------------------
; OR ( n m -- n ) 6 bytes / X cycles
; Logical OR
xt_or
                tya
                ora $00,x
                tay

                inx
                inx

z_or            rts


; -------------------------------------------------------------------
; OUTPUT ( -- addr ) X bytes / X cycles
; Return the address where the jump target for EMIT is stored. By default, this
; will hold the value of put_chr from the kernel routine, but this can be
; changed by the user
xt_output
                dex
                dex
                sty $00,x

                ldy #output
             
z_output        rts


; -------------------------------------------------------------------
; OVER ( n m -- n m n )  6 bytes / 14 cycles
; Push NOS on Data Stack
xt_over
                dex
                dex
                sty $00,x
                ldy $02,x
                
z_over          rts


; -------------------------------------------------------------------
; PAD ( -- addr ) 11 bytes / X cycles
; Return address to a temporary area in free memory for user. Must be at least 
; 84 bytes in size (says ANSI). It is located relative to the compile area
; pointer (CP) and therefore varies in position. This area is reserved for the
; user and not used by the system
xt_pad
        .al
                dex
                dex
                sty $00,x

                lda cp
                clc
                adc #padoffset
                tay
                
z_pad           rts


; -------------------------------------------------------------------
; PAGE ( -- ) X bytes / X cycles
; Clear the screen on vt-100 terminals by sending the code "ESC[2J". This is
; only useful in interactive scenarios so we don't worry about speed
; TODO rewrite with EMIT
xt_page
                lda #vt100_page
                jsr print_string

                ; In theory, this should have moved the cursor to the top left
                ; corner ("home"), but this doesn't seem to work in practice.
                ; So we send "ESC[H" as well.
                lda #vt100_home
                jsr print_string
                
z_page          rts

; -------------------------------------------------------------------
; PARSE-NAME ( "name" -- addr u ) 41+ bytes / X cycles
; Find next word in input string, skipping leading spaces. This is a special
; form of PARSE and drops through to that word. See PARSE for more detail. We
; use this word internally for the interpreter because it is a lot easier to use
; http://forth-standard.org/standard/core/PARSE-NAME has a Forth implementation
; Roughly, the word is comparable to  BL WORD COUNT in old terms.
xt_parse_name
        .al
        .xl
                ; skip leading spaces, changing >IN, then place SPACE 
                ; character on data stack for PARSE
                phy ;  save TOS for later use
                ldy toin ;  >IN
        .setas
parse_name_loop
                cpy ciblen ;  end of line?
                beq parse_name_empty_line

                lda (cib),y ;  LDA (CIB),Y
                cmp #AscSP
                bne parse_name_found
                iny
                bra parse_name_loop

parse_name_empty_line
        .setal    
                ; The Gforth documentation does not say what address is returned
                ; if a string with only spaces is returned. Experiments with 
                ; the word  : PNT ( "name" -- ) PARSE-NAME SWAP U. U. TYPE ; 
                ; show that it returns the address of the last space in the
                ; input, which is cib+ciblen. So we do that as well. 
                dex
                dex
                dex
                dex

                ply ;  restore old TOS as 3OS
                sty $02,x

                lda cib
                clc
                adc ciblen
                sta $00,x ;  Address as NOS

                ldy #$0000 ;  TOS

                jmp z_parse_name ;  don't have to go through PARSE

parse_name_found
        .xl
        .setal
                sty toin ;  new >IN

                ply ;  recover TOS
                dex
                dex
                sty $00,x

                ldy #AscSP ;  put space on TOS for PARSE

                ; fall thru to PARSE
                
; -------------------------------------------------------------------
; PARSE ( c "name" -- addr u ) 45 bytes / X+ cycles
; Find word in input string delimited by character given. Do not skip leading
; delimiters, this is an important difference to PARSE-NAME. PARSE and
; PARSE-NAME replace WORD in modern systems. See the ANSI documentation at
; http://www.forth200x.org/documents/html3/rationale.html#rat:core:PARSE 
; PARSE-NAME drops through to here
;
;    cib   cib+toin    cib+ciblen
;     v       v             v
;     |#####################|              Length of found string: 
;                                          ciblen - toin
;     +------>|  toin (>IN)
;     +-------------------->|  ciblen
;
; The input string is stored starting at the address in the Current Input Buffer
; (CIB), the length of which is in CIBLEN. While searching for the delimiter,
; TOIN (>IN) points to the where we currently are. Since PARSE does not skip
; leading delimiters, we assume we are on a useful string.
xt_parse
        .al
        .xl
                sty tmp1 ;  save delimiter, char is LSB

                ; save beginning of new word (cib+toin) to NOS. Don't need to
                ; worry about TOS because Y gets clobbered anyway before we
                ; return
                lda toin
                sta tmp3 ;  save >IN for later length calculation
                clc
                adc cib

                dex ;  save addr as NOS
                dex
                sta $00,x

                stz tmp2 ;  offset for EOL/char found adjustment of >IN

                ; prepare loop using Y as index
                ldy toin
        .setas

parse_loop
                cpy ciblen ;  check for EOL first
                beq parse_reached_eol

                lda (cib),y ;  LDA (CIB),Y
                cmp tmp1 ;  found delimiter?
                beq parse_found_delimiter
                iny
                bra parse_loop

parse_found_delimiter
                ; If we haven't reached the end of the line, but found
                ; a delimiter, we want >IN to point to the next character after
                ; the delimiter, not the delimiter itself. This is what the
                ; offset is for
        .setal
                inc tmp2

parse_reached_eol
                ; calculate length of string found (see ascii drawing)
        .xl
        .setal
                tya
                sec
                sbc tmp3 ;  original value for >IN / index of first char
                pha ;  save so we can manipulate Y

                ; calculate new >IN
                tya
                clc
                adc tmp2 ;  offset for EOL vs found delimiter
                sta toin

                ply ;  length of string in TOS

z_parse_name
z_parse         rts


; -------------------------------------------------------------------
; PICK ( n n u -- n n n ) X bytes / X cycles
; Take the u-th element out of the stack and put it on TOS, overwriting the
; current TOS. 0 PICK is equivalent to DUP, 1 PICK to OVER. Note that using PICK
; is considered poor coding form. Also note that FIG Forth has a different
; behavior for PICK than ANS Forth.  
; TODO use DEPTH to check for underflow 
xt_pick
                stx tmpdsp

                tya ;  Y is just an offset to the DSP
                asl a ;  double because of cell size two bytes

                clc
                adc tmpdsp

                tax
                lda $00,x ;  LDA $00,X
                tay ;  Is now TOS

                ldx tmpdsp

z_pick          rts


; -------------------------------------------------------------------
; +! "PLUSSTORE" ( n addr -- ) 15 bytes / X cycles
; Add NOS to address in TOS
xt_plusstore
        .al
                lda $0000,y
                clc
                adc $00,x
                sta $0000,y

                ldy $02,x
                inx
                inx
                inx
                inx

z_plusstore     rts


; -------------------------------------------------------------------
; POSTPONE ( -- ) X bytes / X cycles
; Add the compilation behavior of a word to a new word at compile time. If the
; word that follows it is immediate, include it so that it will be compiled when
; the word being defined is itself used for a new word. Tricky, but very useful.
; Because POSTPONE expects a word (not an xt) in the input stream (not on the
; Data Stack). This means we cannot build words with "jsr xt_postpone, jsr
; <word>" directly. This word uses tmp1
xt_postpone
                ; get name from string
                jsr xt_parse_name ;  ( addr n )

                ; if there is no word in stream, complain and abort
                bne pp_got_word
                lda #es_noname
                jmp error

pp_got_word
                jsr xt_find_name ;  ( nt | 0 )

                ; if word is not in Dictionary, complain and abort
                bne pp_got_nt
                lda #es_syntax

pp_got_nt
                ; Keep nt safe for later use
                sty tmp1

                ; We need the xt instead of the nt for the actual compiling
                jsr xt_name_int ;  NAME>INT ( nt -- xt )

                ; See if this is an immediate word. This is easier with nt than
                ; with xt
                lda (tmp1) ;  LDA (TMP1) - get status byte of word
                xba ;  flags are MSB
                and #IM ;  mask everything but Immediate bit
                beq pp_not_immediate
                
                ; The word is immediate, so instead of executing it right now,
                ; we compile it. xt is on the stack, so this is simple. The RTS
                ; of COMPILE, takes us back to the original caller
                jsr xt_compilecomma
                rts

pp_not_immediate
                ; This is not an immediate word, so we enact "deferred
                ; compilation" by including ' <NAME> COMPILE, which we do by
                ; compiling the run-time routine of LITERAL, the xt itself, and
                ; a subroutine jump to COMPILE,
                pea literal_rt ;  PEA LITERAL_RT
                jsr cmpl_subroutine

                ; The xt is TOS. We can't use COMPILE, here because it might
                ; decided to do something silly like compile it as a native word
                ; and ruin everything
                jsr xt_comma

                ; compile COMPILE, 
                pea xt_compilecomma
                jsr cmpl_subroutine

z_postpone      rts


; -------------------------------------------------------------------
; R@ "RFETCH" ( -- n ) (R: n -- n )  X bytes / X cycles
; Get (not pull) Top of Return Stack. We follow Gforth in that this word is not
; compiled only, because it can be interesting to know what the top of R is in
; an interactive setting. However, this causes all kinds of problems if we try
; to natively compile the word, so it does not get the NC flag even though it is
; actually short enough to make that reasonable
; TODO consider special case in COMPILE, see there
xt_rfetch
                ; get return address that is on top of the return stack
                pla

                dex
                dex
                sty $00,x

                ply ;  get top of return stack and push copy back again
                phy

                pha ;  restore the return address

z_rfetch        rts


; -------------------------------------------------------------------
; R> "FROMR" ( -- n ) (R: n -- )  7 bytes / 23 cycles
; Move Top of Return Stack to Top of Data Stack. Remember we have to move the
; jump address out of the way first.
; TODO consider stripping PHA/PLA if natively compiled (see COMPILE,)
xt_fromr
                ; Rescue the address of the return jump that is currently top of
                ; the Return Stack. If this word is natively compiled, this is
                ; a waste of nine cycles
                pla
                ; --- cut for native coding ---

                dex
                dex
                sty $00,x

                ply ;  the actual work

                ; --- cut for native coding ---
                pha ;  get return address back

z_fromr         rts


; -------------------------------------------------------------------
; RECURSE ( -- ) X bytes / X cycles
; Get the current definition to call itself This may not be native compile. Test
; with " : GCD ( a b -- gcd) ?DUP IF TUCK MOD RECURSE THEN ;" for instance with
; "784 48 GCD ." --> 16 ; example from
; http://galileo.phys.virginia.edu/classes/551.jvn.fall01/primer.htm
xt_recurse
        .al
                ; save JSR instruction
                lda #$0020
                sta (cp)
                inc cp

                ; The temporary variable WORKWORD points to the nt of the word,
                ; not it's xt, which is kept four bytes below
                lda workword
                inc a
                inc a
                inc a
                inc a

                phy
                tay
                lda $0000,y
                ply

                sta (cp)
                inc cp
                inc cp
                
z_recurse       rts

; ------------------------------------------------------------------- 
; REFILL ( -- f ) X bytes / X cycles
; "Attempt to fill the input buffer from the input source, returning a true flag
; if successful. When the input source is the user input device, attempt to
; receive input into the terminal input buffer. If successful, make the result
; the input buffer, set >IN to zero, and return true. Receipt of a line
; containing no characters is considered successful. If there is no input
; available from the current input source, return false. When the input source
; is a string from EVALUATE, return false and perform no other action."
; See https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/The-Input-Stream.html
; and Conklin & Rather p. 156
xt_refill
        .al
        .xl
                ; Get input source from SOURCE-ID. We don't have blocks in this
                ; version, or else we would have to check BLK first. This is an
                ; optimized version of a subroutine jump to SOURCE-ID
                lda insrc
                bne refill_src_not_kbd

                ; SOURCE-ID of zero means we're getting stuff from the keyboard
                ; with ACCEPT. 
                dex
                dex
                dex
                dex
                sty $02,x

                lda cib ;  address of current input buffer NOS
                sta $00,x
                ldy #bsize ;  max number of chars to accept TOS

                jsr xt_accept ;  ( addr n1 -- n2)

                ; ACCEPT returns the number of characters accepted, but we don't
                ; need them. We just overwrite TOS this with the flag
                ldy #$0ffff

                bra z_refill

refill_src_not_kbd
                ; If SOURCE-ID doesn't return a zero, it must be a string in
                ; memory or a file (remember, no blocks in this version)
                inc a
                bne refill_source_is_not_string

                ; Simply return FALSE flag as per specification
                dex
                dex
                sty $00,x
                tay

                bra z_refill

refill_source_is_not_string
                ; Since we don't have blocks, this must mean that we are trying
                ; to read from a file. However, we don't have files yet, so we 
                ; report an error and jump to ABORT.
                lda #es_refill2
                jmp error

z_refill        rts ;  dummy for compiling


; -------------------------------------------------------------------
; ROT ( a b c -- b c a ) X bytes / X cycles
; Rotate the top three entries downwards (third entry becomes first)
; Remember this with the "R" for "revolution": The bottom entry comes up on top! 
xt_rot
        .al
                lda $00,x ;  save b
                sty $00,x ;  move c to NOS
                ldy $02,x ;  move a to TOS
                sta $02,x ;  save b as 3OS
                
z_rot           rts


; -------------------------------------------------------------------
; RSHIFT ( n u -- u ) X bytes / X cycles
; Shift TOS right, filling vacant bits with zero
xt_rshift
                ; We shift at most 16 bits, because anything above that will be
                ; zeros anyway
                tya
                and #$000f
                beq rshift_done ;  if zero shifts, we're done

                tay ;  number of shifts is TOS
                lda $00,x ;  number is in NOS
rshift_loop
                lsr a
                dey
                bne rshift_loop

                sta $00,x ;  put NOS, which last step will pull up
                
rshift_done
                ldy $00,x
                inx
                inx

z_rshift        rts


; -------------------------------------------------------------------
; S" "SQUOTE" ( "string" -- addr u ) X bytes / X cycles
; Store address and length of string given, returning ( addr u ). ANSI core
; claims this is compile_only, but the file set expands it to be interpreted, so
; it is a state-sensitive word, which are evil. This can also be realized as
; : S" [CHAR] " PARSE POSTPONE SLITERAL ; IMMEDIATE  but it is used so much we
; want it in code
xt_squote
                ; we use PARSE to find the end of the sting. If the string is
                ; empty, we don't complain, following Gforth's behavior
                dex
                dex
                sty $00,x

                ldy #$0022 ;  ASCII for " in hex
                jsr xt_parse ;  Returns ( addr u ) of string

                ; What happens now depends on the state. If we are compiling, we
                ; include a subroutine jump to SLITERAL to save the string. If
                ; we are interpreting, we're done
                lda state
                bne squote_compile

		; We copy our string to someplace safe because it lives
                ; dangerously if we leave it in the input buffer. This might
                ; seem like a lot of effort for a few bytes, but MVN is so fast
                ; - 7 cycles per byte - that it is worth it. See 
                ; http://forum.6502.org/viewtopic.php?f=2&t=1685&p=50975#p50975
                ; and http://6502.org/tutorials/65c816opcodes.html#6.6
                dex
                dex
                sty $00,x
                ldy cp ;  HERE  ( addr-s u addr-d )

                lda $00,x ;  SWAP ( addr-s addr-d u )
                sty $00,x
                tay

                phy ;  save copy of u
                lda $00,x ;  save copy of addr-d
                pha

                jsr xt_move

                dex
                dex
                dex
                dex
                sty $02,x

                pla ;  get addr-d back
                sta $00,x ;  put NOS
                pla ;  get u back, put TOS
                tay

                ; update CP
                clc
                adc cp
                sta cp
                
                bra z_squote

squote_compile
                ; We're compiling, so we need SLITERAL
                jsr xt_sliteral

z_squote        rts


; -------------------------------------------------------------------
; S>D ( n -- d ) 15 bytes / X cycles
; Convert a single cell number to double cells, conserving the sign
xt_stod
                dex ;  make room on stack
                dex
                sty $00,x

                tya ;  force flag check
                bpl stod_pos
                
                ; negative number, extend sign
                ldy #$0ffff
                bra z_stod

stod_pos
                ; positive number
                ldy #$0000 ;  fall through

z_stod          rts

; -------------------------------------------------------------------
; SIGN ( n -- ) 13 bytes / X cycles
; If TOS is negative, add a minus sign to the pictured output. Code based on
; https://github.com/philburk/pforth/blob/master/fth/system.fth
; Origin Forth code is  0< IF [CHAR] - HOLD THEN
xt_sign
        .al
                ; See if number is negative
                tya ;  force flag check
                bpl sign_plus

                ; We're negative, overwrite number TOS
                ldy #$002d ;  ASCII for '-'

                jsr xt_hold
                bra z_sign

sign_plus
                ldy $00,x ;  get rid of number and leave
                inx
                inx
                
z_sign          rts


; -------------------------------------------------------------------
; SLITERAL ( addr u -- ) ( -- addr u ) X bytes / X cycles 
; At compile time, store string, at runtime, return address and length of string
; on the Data Stack. Used for S" among other things. This routine uses tmp1,
; tmp2
xt_sliteral
        .al
                ; We can't assume that ( addr u ) of the current string is in
                ; a stable area, so we first have to move them to safety. Since
                ; CP points to where the interpreter expects to be able to
                ; continue in the code, we have to jump over the string. We use
                ; JMP instead of BRA so we can use longer strings
                lda $00,x ;  Address of string is NOS
                sta tmp1
                sty tmp2 ;  keep copy of string length

        .setas     
                lda #$04c ;  opcode for JMP
                sta (cp) ;  STA (CP)
        .setal
                inc cp
                
                ; Our jump target is CP + 2 (for the length of the jump
                ; instruction itself ) + the length of the string
                lda tmp2 ;  string length
                inc a
                inc a

                clc
                adc cp ;  current address
                sta (cp) ;  store jump target

                ; update CP to move past JMP instruction
                inc cp
                inc cp

                ; now we can safely copy the code
                dey ;  last offset is one less than length
        .setas
sl_loop
                lda (tmp1),y ;  LDA (TMP1),Y
                sta (cp),y ;  STA (CP),Y
                dey
                bpl sl_loop
        
        .setal
                ; keep old CP as new address of string
                lda cp
                sta tmp1 ;  overwrites original address

                ; update CP
                clc
                adc tmp2 ;  length of string
                sta cp

                ; Compile a subroutine jump to the runtime of SLITERAL that
                ; pushes the new ( addr u ) pair to the Data Stack. When we're
                ; done, the code will look like this:
                ;
                ; xt -->    jmp a
                ;           <string data bytes>
                ;  a -->    jsr sliteral_rt
                ;           <string address>
                ;           <string length>
                ; rts -->
                ;
                ; This means we'll have to adjust the return address for two
                ; cells, not just one
                pea sliteral_rt
                jsr cmpl_subroutine

                ; We want to have the addr end up as NOS and the length as TOS,
                ; so we store the address first
                lda tmp1 ;  new address of string
                pha
                jsr cmpl_word

                lda tmp2
                pha
                jsr cmpl_word

                ; all done, clean up and leave
                ldy $02,x ;  2DROP
                inx
                inx
                inx
                inx
                
z_sliteral      rts

sliteral_rt
                ; Run time behaviour of SLITERAL: Push ( addr u ) of string to
                ; the Data Stack. We arrive here with the return address as the
                ; top of Return Stack, which points to the address of the string

                ; Make room on stack, which also frees Y for other use
                dex
                dex
                dex
                dex
                sty $02,x
                
                ; Get the address of the string address off the stack and
                ; increase by one because of the RTS mechanics
                ply
                iny

                lda $0000,y ;  LDA $0000,Y
                sta $00,x ;  save string address as NOS
                iny
                iny
                lda $0000,y ;  get length of string, will be TOS ...
                
                iny ;  ... first, though, repair return jump
                phy

                tay ;  TOS is now length of string

                rts

; -------------------------------------------------------------------
; SM/REM ( d n1 -- n2 n3) X bytes / X cycles
; Symmetic signed division. Compare FM/MOD. Code from Gforth, see
; https://groups.google.com/forum/#!topic/comp.lang.forth/_bx4dJFb9R0
; and http://git.savannah.gnu.org/cgit/gforth.git/tree/prim ; see
; http://www.figuk.plus.com/build/arith.htm for variants. Forth is
; SM/REM OVER >R DUP >R ABS -ROT DABS ROT UM/MOD R> 
; R@ XOR 0< IF NEGATE THEN R> 0< IF SWAP NEGATE SWAP THEN ;
; TODO optimize further in assembler
xt_smrem
        .al
                jsr xt_over

                phy		; >R
                ldy $00,x
                inx
                inx

                dex ;  DUP
                dex
                sty $00,x

                phy ;  >R
                ldy $00,x
                inx
                inx

                jsr xt_abs ;  ABS
                jsr xt_mrot ;  -ROT
                jsr xt_dabs ;  DABS
                jsr xt_rot ;  ROT
                jsr xt_ummod ;  UM/MOD

                dex ;  R>
                dex
                sty $00,x
                ply

                dex ;  R@
                dex
                sty $00,x
                ply
                phy

                jsr xt_xor ;  XOR

                tya ;  0< IF
                bpl smrem_1

                ldy $00,x ;  from IF
                inx
                inx

                jsr xt_negate ;  NEGATE
                bra smrem_1_1
smrem_1
                ldy $00,x ;  from IF
                inx
                inx

smrem_1_1
                dex ;  R>
                dex
                sty $00,x
                ply

                tya ;  0< IF
                bpl smrem_2

                ldy $00,x ;  from IF
                inx
                inx

                jsr xt_swap
                jsr xt_negate
                jsr xt_swap
                bra smrem_2_1

smrem_2
                ldy $00,x
                inx
                inx

                
smrem_2_1

z_smrem         rts


; -------------------------------------------------------------------
; SOURCE ( -- addr u ) 12 bytes / X cycles
; Return the address and size of current input buffer. Replaces TIB and #TIB in
; ANSI Forth

xt_source
                dex ;  make room on Data Stack
                dex
                dex
                dex
                sty $02,x

                lda cib ;  address of current input buffer as NOS
                sta $00,x

                ldy ciblen ;  length of current input buffer as TOS
                
z_source        rts

; -------------------------------------------------------------------
; SOURCE-ID ( -- n ) 6 bytes / 13 cycles
; Identify the input source unless it is a block (s. Conklin & Rather p. 156).
; Since we don't have blocks (yet), this will give the input source: 0 is
; keyboard, -1 (0ffff) is character string, and a text file gives the fileid.
xt_source_id
        .xl
                dex
                dex
                sty $00,x
                ldy insrc
                
z_source_id     rts

; -------------------------------------------------------------------
; SPACE ( -- ) X bytes / X cycles
; Print one ASCII space character. We need to leave JSR EMIT_A as a subroutine
; instead of JSR/RTS it to JMP to allow native compile  
; TODO add PAUSE for multitasking
xt_space
                lda #AscSP
                jsr emit_a

z_space         rts


; -------------------------------------------------------------------
; SPACES ( u -- ) 12 bytes / X cycles
; Print u spaces
; TODO add PAUSE for multitasking
xt_spaces
        .al

spaces_loop
                dey ;  this also handles case u=0
                bmi spaces_done

                lda #$0020
                jsr emit_a

                bra spaces_loop

spaces_done
                ldy $00,x ;  DROP
                inx
                inx

z_spaces        rts

; -------------------------------------------------------------------
; STAR ( n n -- n ) 16*16 -> 16  X bytes / X cycles
; Multiply two signed 16 bit numbers, returning a 16 bit result. This is nothing
; more than UM* DROP
xt_star
                jsr xt_umstar

                ldy $00,x ;  DROP
                inx
                inx

z_star          rts


; -------------------------------------------------------------------
; STATE ( -- addr ) 7 bytes / 12 cycles
; Return the address of a cell containing the compilation-state flag. STATE
; is true when in compilation state, false otherwise. STATE should not be 
; changed directly by the user; see
; http://forth.sourceforge.net/standard/dpans/dpans6.htm#6.1.2250
xt_state
        .xl
                dex
                dex
                sty $00,x
                ldy #state
                
z_state         rts


; -------------------------------------------------------------------
; SWAP ( n m -- m n ) 5 bytes / 12 cycles
; Exchange TOS with NOS. We don't check if there are enough elements on the Data
; Stack; underflow errors will go undetected and return garbage.
xt_swap
        .al
        .xl
                lda $00,x
                sty $00,x
                tay

z_swap          rts


; -------------------------------------------------------------------
; TO ( n "name" -- ) X bytes / X cycles
; Change the value of a VALUE. Note that in theory this would work with CONSTANT
; as well, but we frown on this behavior. Note that while it is in violation of
; ANS Forth, we can change the number in a VALUE with <number> ' <value> >BODY
; +!  just as you can with Gforth
; TODO unroll this to assembler
xt_to
                jsr xt_tick ;  '
                jsr xt_tobody ;  >BODY
                jsr xt_store ;  !

z_to            rts


; -------------------------------------------------------------------
; TRUE ( -- f ) 7 bytes / 12 cycles
; Pushes value $FFFF for Forth true on Data Stack
xt_true
        .al
        .xl
                dex
                dex
                sty $00,x
                ldy #$0ffff

z_true          rts

; -------------------------------------------------------------------
; TUCK ( n m -- m n m ) 8 bytes / 19 cycles
; Insert TOS below NOS. We do not check if there are enough elements on the Data
; Stack, underflow will go undetected and return garbage.
xt_tuck
        .al
        .xl
                dex
                dex
                lda $2,x
                sta $0,x
                sty $2,x
                
z_tuck          rts

; -------------------------------------------------------------------
; TYPE  ( addr u -- ) 23+ bytes / X cycles
; Print character string if u is not 0. Works though EMIT and is affect by the
; OUTPUT revectoring
; TODO LATER add PAUSE here for multitasking
xt_type
        .al
        .xl
                ; just leave if u is zero (empty string)
                tya ;  force flag check of TOS
                beq type_done

                lda $00,x ;  get address from NOS
                sta tmp1
                sty tmp2 ;  number of chars is TOS
                ldy #$0000
        .setas
type_loop
                lda (tmp1),y ;  LDA (TMP1),Y
                jsr emit_a
                iny
                cpy tmp2
                bne type_loop
                
        .setal
type_done
                ; clear stack
                ldy $02,x
                inx
                inx
                inx
                inx

z_type          rts


; -------------------------------------------------------------------
; UDOT ( n -- ) X bytes / X cycles
; Print unsigned number. This is based on the Forth word 
; 0 <# #S #> TYPE SPACE but uses the general print_u routine 
; that .S and DUMP use as well. We need to keep JSR EMIT_A instead of JSR/RTS it
; to JMP to allow native compile
xt_udot
                jsr print_u ;  ( n -- )

                lda #$0020 ;  SPACE
                jsr emit_a
                
z_udot          rts



; -------------------------------------------------------------------
; UDMOD ( ud u -- u ud ) 32/16 --> 32  X bytes / X cycles
; Devide double-cell number by single-cell number, producing a double-cell
; result and a single-cell remainder. Based on 
; Gforth  : UD/MOD  >R 0 R@ UM/MOD R> SWAP >R UM/MOD R> ;
; pForth  : UD/MOD  >R 0 R@ UM/MOD ROT ROT R> UM/MOD ROT ; 
; This doesn't seem to be used anywhere else but for # (HASH) in coverting
; pictured numerical output, though pForth claims it uses UM/MOD for that
; At some point, we need to get back to UM/MOD because it's optimized
xt_udmod
                jsr xt_tor
                jsr xt_zero
                jsr xt_rfetch
                jsr xt_ummod
                jsr xt_rot
                jsr xt_rot
                jsr xt_fromr
                jsr xt_ummod
                jsr xt_rot
z_udmod         rts


; -------------------------------------------------------------------
; UM* "UMSTAR" ( u u -- ud ) 16*16 -> 32  X bytes / X cycles
; Multiply two unsigned 16 bit numbers, producing a 32 bit result.This is based
; on modified FIG Forth code by Dr. Jefyll, see
; http://forum.6502.org/viewtopic.php?f=9&t=689 for a detailed discussion. We
; use the system scratch pad (SYSPAD) for temp storage (N in the original code)
; FIG Forth is in the public domain. Note old Forth versions such as FIG Forth
; call this "U*"

; This is currently a brute-force loop based on the 8-bit variant in "6502
; Assembly Language Programming" by Leventhal. Once everything is working,
; consider switching to a table-supported version based on
; http://codebase64.org/doku.php?id=base:seriously_fast_multiplication
; http://codebase64.org/doku.php?id=magazines:chacking16#d_graphics_for_the_masseslib3d_and_cool_world
; http://forum.6502.org/viewtopic.php?p=205#p205
; http://forum.6502.org/viewtopic.php?f=9&t=689 We use tmp1, tmp2, tmp3 for
; this, with the assumption that tmp3 immediately follows tmp2
xt_umstar
        .al
                ; SPECIAL CASE 1: multiplication by zero
                tya
                beq umstar_zero
                lda $00,x
                beq umstar_zero

                ; SPECIAL CASE 2: multiplication by one
                ; This is a different routine than 2* because that instruction
                ; stays inside one cell, whereas UM* produces a Double Cell
                ; answer
                cpy #$0001 ;  non-distructively
                beq umstar_one_tos
                lda $00,x
                dec a ;  don't care about distruction
                beq umstar_one_nos

                ; SPECIAL CASE 3: multiplication by two
                cpy #$0002
                beq umstar_two_tos

                lda $00,x
                cmp #$0002
                beq umstar_two_nos

                ; NO SPECIAL CASE ("The Hard Way") 
                sty tmp1 ;  TOS number  "40"
                sta tmp2 ;  NOS number  "41"
                ldy #16 ;  loop counter

                lda #$0000
                sta tmp3 ;  Most Significat Word (MSW) of result
                
umstar_loop
                asl a ;  useless for first iteration
                rol tmp3 ;  move carry into MSB, useless first iteration
                asl tmp2 ;  move bit of NOS number into carry

                ; if there is no carry bit, we don't have to add and can go to
                ; the next bit
                bcc umstar_counter
                
                clc
                adc tmp1 ;  we have a set bit, so add TOS

                ; if we have a carry, increase the MSW of result
                bcc umstar_counter
                inc tmp3

umstar_counter
                dey
                bne umstar_loop

                ; We're all done, clean up and leave
                sta $00,x ;  store lower cell of number in NOS
                ldy tmp3 ;  store MSB in TOS as double cell
               
                bra z_umstar ;  don't use RTS so we can natively compile
                
umstar_zero
                ; one or both of the numbers is zero, so we got off light
                ldy #$0000
                sty $00,x
                bra z_umstar

umstar_one_tos
                ; TOS is one, life is easy
                dey ;  NOS is LSW, TOS becomes zero
                bra z_umstar
umstar_one_nos
                ; NOS is one, life is easy
                sty $00,x
                ldy #$0000
                bra z_umstar

umstar_two_tos
                ; TOS is two, life is easy
                lda $00,x
                bra umstar_two_common
umstar_two_nos
                ; NOS is two, life is still easy
                tya
umstar_two_common
                asl a ;  multiply by two, top bit in Carry Flag
                sta $00,x ;  Double Cell LSW is NOS

                lda #$0000
                rol a ;  Rotate any Carry Flag into MSW
                tay
                
z_umstar        rts

; -------------------------------------------------------------------
; UM/MOD ( ud u -- u u ) 32/16 -> 16  X bytes / X cycles
; Divide double cell number by single cell number, returning the quotient as TOS
; and any remainder as NOS. All numbers are unsigned. This is the basic division
; operation all others use. Based on Garth Wilson's code at
; http://6502.org/source/integers/ummodfix/ummodfix.htm We use "scratch" for N
; and include a separate detection of division by zero to force an error code
xt_ummod
        .al
        .xl
                ; Move the inputs to the scratchpad to avoid having to fool
                ; around with the Data Stack and for speed. Garth's original
                ; code uses the MVN instruction for this, but our TOS is Y which
                ; makes that harder. When we're done, the setup will look like
                ; this: (S is start of the scratchpad in Direct Page)
                ;
                ;     +-----+-----+-----+-----+-----+-----+-----+-----+
                ;     |  DIVISOR  |        DIVIDEND       | TEMP AREA |
                ;     |           |  hi cell     lo cell  | carry bit |
                ;     |  S    S+1 | S+2   S+3 | S+4   S+5 | S+6   S+7 |
                ;     +-----+-----+-----+-----+-----+-----+-----+-----+
                ;
                ; The divisor is TOS (in Y), high cell of the dividend in NOS,
                ; and low cell in 3OS

                ; Catch division by zero. We could include this in the code as
                ; part of overflow detection (see below), but we want an error
                ; to appear like in Gforth
                tya ;  force flag test
                bne ummod_notzero
                
                lda #es_divzero
                jmp error

ummod_notzero
                sty scratch ;  Y is now free
                lda $00,x ;  high cell of dividend
                sta scratch+2
                lda $02,x ;  low cell of dividend
                sta scratch+4

                ; Drop one entry off of the stack and save the new Data Stack
                ; Pointer, freeing X for index duty
                inx
                inx
                stx tmpdsp
                
                ; Detect overflow. Subtract divisor from high cell of dividend.
                ; If carry flag remains set, divisor was not large enough to
                ; avoid overflow. This also would detect division by zero, but
                ; we did that already in a separate step
                sec
                lda scratch+2
                sbc scratch
                bcs ummod_overflow

                ; If there is no overflow, the carry flag remains clear for
                ; first roll. We loop 16 times, but since we shift the dividend
                ; over at the same time as shifting the answer in, the operation
                ; must start and (!) finish with a shift of the low cell of the
                ; dividend (which ends up holding the quotient), so we start
                ; with 17 times in X. Y is used for temporary storage
                ldx #17

ummod_shift
                ; Move low cell of dividend left one bit, also shifting answer
                ; in. The first rotation brings in a zero, which later gets
                ; pushed off the other end in the last rotation
                rol scratch+4

                ; loop control
                dex
                beq ummod_complete

                ; Shift high cell of divident left one bit, also shifting the
                ; next bit in from high bit of low cell
                rol scratch+2
                lda #$0000
                rol a
                sta scratch+6 ;  store old high bit of dividend

                ; See if divisor will fit into high 17 bits of dividend by
                ; subtracting and then looking at the carry flag. If carry was
                ; cleared, divisor did not fit
                sec
                lda scratch+2
                sbc scratch
                tay ;  save difference in Y until we know if we need it

                ; Bit 0 of S+6 serves as the 17th bit. Complete the subtraction
                ; by doing the 17th bit before determining if the divisor fits
                ; into the high 17 bits of the dividend. If so, the carry flag
                ; remains set
                lda scratch+6
                sbc #$0000
                bcc ummod_shift

                ; Since the divisor fit into high 17 bits, update dividend high
                ; cell to what it would be after subtraction
                sty scratch+2
                bra ummod_shift
                
ummod_overflow
                ; If an overflow condition occurs, put 0ffff
                ; in both the quotient and remainder
                ldx tmpdsp ;  restore DSP
                ldy #$0ffff
                sty $00,x
                bra z_ummod ;  go to end to enable native coding

ummod_complete
                ldx tmpdsp ;  restore DSP
                ldy scratch+4 ;  quotient is TOS
                lda scratch+2 ;  remainder is NOS
                sta $00,x

z_ummod         rts


; -------------------------------------------------------------------
; UNLOOP ( -- ; R: n n n -- ) X bytes / X cycles
; Drop loop control stuff from Return Stack. 
; TODO make this faster
xt_unloop
                ; drop fudge number (limit/start) from DO/?DO off the Return
                ; Stack 
                pla
                pla

                ; Drop the LEAVE address that was below them as well
                pla

z_unloop        rts


; -------------------------------------------------------------------
; UNUSED ( -- u ) 11 bytes / X cycles
; Return amount of memory available for the Dictionary. Does not exclude the
; space for PAD. 
xt_unused
        .al
                lda #cp_end
                sec
                sbc cp ;  current compile pointer
                
                dex
                dex
                sty $00,x

                tay
                
z_unused        rts


; -------------------------------------------------------------------
; VALUE ( n "name" -- ) X bytes / X cycles
; Associate a name with a value (like a constant) that can be changed (like
; a variable) with TO. We use the routines as CONSTANT, see there.


; -------------------------------------------------------------------
; VARIABLE ( "name" -- ) X bytes / X cycles
; Define a word that returns the address for a variable. There are various Forth
; definitions for this word, such as  CREATE 1 CELLS ALLOT  or CREATE 0 ,
; We use a variant of the second one so the variable is initialized to zero
xt_variable
                ; We let CREATE do the heavy lifting
                jsr xt_create

                ; There is no "stz.di cp" so we have to do this the
                ; old way, which is still faster than a subroutine jump to ZERO
                lda #$0000
                sta (cp) ;  STA (CP)

                inc cp ;  direct COMMA
                inc cp

                jsr adjust_z ;  adjust the z_ value by adding 2 bytes

z_variable      rts


; -------------------------------------------------------------------
; WORD ( char "name" -- c-addr ) X bytes / X cycles
; Obsolete parsing word included for backwards compatibility. Do not use this,
; use PARSE or PARSE-NAME. Skips leading delimiters and copies word to storage
; area for a maximum size of 255 bytes. Returns the result as a counted string
; (requires COUNT to convert to modern format), and inserts a space after the
; string. See "Forth Programmer's Handbook" 3rd edition p.159 and 
; http://www.forth200x.org/documents/html/rationale.html#rat:core:PARSE 
; for discussions of why you shouldn't be using WORD anymore. Forth would be
; PARSE DUP BUFFER1 C! OUTPUT 1+ SWAP MOVE BUFFER1
; TODO What about the space?
xt_word
                ; The real work is done by PARSE
                jsr xt_parse ;  ( addr u )

                ; Now we have to convert the modern address to the old form
                sty buffer1 ;  overwrite MSB

                dex
                dex ;  ( addr <?> u )
                lda #buffer1
                inc a
                sta $00,x ;  ( addr buffer1+1 u )

                jsr xt_move

                dex
                dex
                sty $00,x

                ldy #buffer1

z_word          rts


; -------------------------------------------------------------------
; WORDS&SIZES ( -- ) X bytes / X cycles
; Prints all words in the dictionary with the sizes of their code as returned by
; WORDSIZE. Used to test different optimizations of the compiling routines,
; specific to Liara Forth. Uses tmp3
xt_wordsnsizes
        .al
                lda #$0ffff
                sta tmp3 ;  set flag that we want sizes, too

                ; continue with WORDS
                bra words_common

; -------------------------------------------------------------------
; WORDS ( -- ) X bytes / X cycles
; Print list of all Forth words available. This only really makes sense in an
; interactive setting, so we don't have to worry about speed. WORDS&SIZES falls
; through to here. Uses tmp3. Both WORDS and WORDS&SIZES might be better off as
; high-level Forth words, but these routines are left over from early testing
xt_words
                stz tmp3 ;  store flag that we don't want to print sizes

words_common
                ; common routine for WORDS and WORDS&SIZES
                jsr xt_cr ;  start on next line, this is a style choice

                lda dp ;  nt of first entry in Dictionary (last added)
                pha

                dex ;  create room on TOS
                dex
                sty $00,x

words_loop
                tay ;  ( nt )
                jsr xt_name_string ;  ( nt -- addr u )
                jsr xt_type
                jsr xt_space

                ; If the user wants sizes as well, print them
                lda tmp3
                beq words_nosizes

                ; For the moment, just print the size in bytes after the word's
                ; name string. We can decide if we want to get all fancy later
                dex
                dex
                sty $00,x

                ply ;  get nt back again
                phy
                jsr xt_wordsize ;  ( u )
                jsr xt_dot
                jsr xt_space

words_nosizes
                pla ;  get back first entry in Dictionary

                ; The next nt is two bytes below the nt of the current one in
                ; the Dictionary header
                inc a
                inc a

                dex
                dex
                sty $00,x

                tay
                lda $0000,y ;  LDA $0000,Y
                pha
                bne words_loop ;  zero entry signals end of Dictionary

                ; all done, clean up
                pla ;  balance MPU stack, value discarded

                ldy $00,x
                inx
                inx

z_words
z_wordsnsizes   rts

; -------------------------------------------------------------------
; WORDSIZE ( nt -- u ) X bytes / X cycles
; Given an word's name token (nt), return the size of the word's payload (CFA
; plus PFA) in bytes. Does not count the final RTS. Specific to Liara Forth. 
; Uses tmp2, note WORDS and WORDS&SIZES use tmp3
; TODO rewrite so it takes xt and not nt
xt_wordsize
                ; We get the beginning address of the code from the word's
                ; header entry for the execution token (xt, 4 bytes down) and
                ; the pointer to the end of the code (z_word, six bytes down). 
                iny
                iny
                iny
                iny ;  nt+4, location of xt
                lda $0000,y ;  get xt
                sta tmp2

                iny
                iny ;  nt+6, location of z_word
                lda $0000,y
                
                sec ;  (z_word - xt_word)
                sbc tmp2
                tay

z_wordsize      rts


; -------------------------------------------------------------------
; XOR ( n m -- n ) 6 bytes / X cycles
; Logical XOR
xt_xor
                tya
                eor $00,x
                tay

                inx
                inx

z_xor           rts


; ===================================================================
; MIDDLE INCLUDES
        
        .include "headers.asm"

; ===================================================================
; CODE FIELD ROUTINES

; ------------------------------------------------------------------- 
; DOCONST 
; Execute a constant: Push the data in the first two byte of the Data Field onto
; the stack
doconst
        .al
        .xl
                dex ;  make room on Data Stack
                dex
                sty $00,x

                ; The value we need is stored two bytes after the JSR return
                ; address, which in turn is what is on top of the Return Stack
                pla ;  get the return address
                sta tmp1

                ; start Y as index off with 1 instead of zero because of 65816's
                ; address handling
                ldy #$0001
                lda (tmp1),y ;  LDA (TMP1),Y
                tay

                rts ;  takes us to original caller
 

; ------------------------------------------------------------------- 
; DODEFER 
; Execute a DEFER statement at runtime: Execute the address we find after the
; caller in the Data Field
dodefer
                ; the xt we need is stored in the two bytes after the JSR return
                ; address, which is what is on top of the Retun Stack. So all we
                ; have to do is replace our return jump with what we find there
                pla ;  this is the address where we find the xt ...
                inc a ;  ... except one byte later
                sta tmp1
                lda (tmp1) ;  LDA (TMP1)
                dec a ;  Now we need to move one byte back
                pha ;  Return new address

                rts ;  This is actually a jump to the new target

defer_error
                ; if the defer has not been defined with an IS word, we land
                ; here by default
                lda #es_defer
                jmp error


; ------------------------------------------------------------------- 
; DODOES
; Used in combination with DOES>'s runtime portion to actually do the work of
; the new word. See DOES> and docs/create-does.txt for details. Uses tmp3
dodoes
                ; Assumes the address of the CFA of the original defining word
                ; (say, CONSTANT) is on the top of the Return Stack. Save it for
                ; a later jump, adding one byte because of the way the 65816
                ; works
                pla
                inc a
                sta tmp3

                ; Next on the Return Stack should be the address of the PFA of
                ; the calling defined word (say, the name of whatever constant we
                ; just defined). Move this to the Data Stack, again adding one.
                dex
                dex
                sty $00,x

                ply
                iny

                ; This leaves the return address from the original main routine
                ; on top of the Return Stack. We leave that untouched and jump
                ; to the special code of the defining word. It's RTS instruction
                ; will take us back to the main routine
                jmp (tmp3) ;  JMP (TMP3)


; ------------------------------------------------------------------- 
; DOVAR
; Execute a variable: Push the address of the first bytes of the Data Field onto
; the stack. This is called with JSR so we can pick up the address of the
; calling variable off the 65816's Return Stack. The final RTS takes us to the
; original caller of the routine that in turn called DOVAR. This is the default 
; routine installed with CREATE
dovar
        .al
        .xl
                dex ;  make room on Data Stack
                dex
                sty $00,x
 
                ; The address we need is stored in the two bytes after the JSR 
                ; return address, which in turn is what is on top of the Return 
                ; Stack
                ply ;  value is now TOS
                iny ;  add one because of 65816's address handling
                
                rts ;  takes us to original caller


; ===================================================================
; LOW LEVEL HELPER FUNCTIONS


; ------------------------------------------------------------------- 
; INTERPRET
; Core routine for interpreter called by EVALUATE and QUIT. We process one line
; only. Assumes that address of name is in cib and length of whole input 
; string is in ciblen
interpret
interpret_loop
        .al
        .xl
                ; Normally we would use PARSE here with the SPACE character as
                ; a parameter (PARSE replaces WORD in modern Forths). However,
                ; Gforth's PARSE-NAME makes more sense as it uses spaces as
                ; delimiters per default and skips any leading spaces, which
                ; PARSE doesn't
                jsr xt_parse_name ;  ( "string" -- addr u )

                ; If PARSE-NAME returns 0 (empty line), no characters were left
                ; in the line and we need to go get a new line
                tya ;  force flag check
                beq interpret_line_done
                
                ; Go to FIND-NAME to see if this is a word we know. We have to
                ; make a copy of the address in case it isn't a word we know and
                ; we have to go see if it is a number
                jsr xt_2dup ;  TODO convert this to assembler
                jsr xt_find_name ;  ( addr u -- nt | 0 )

                ; a zero signals that we didn't find a word in the Dictionary
                tya
                bne interpret_got_name_token

                ; We didn't get any nt we know of, so let's see if this is
                ; a number. 
                jsr xt_drop ;  TODO convert this to assembler

                ; If the number conversion doesn't work, NUMBER will do the
                ; complaining for us
                jsr xt_number ;  ( addr u -- u | d )

                ; If we're interpreting, we're done
                lda state
                beq interpret_loop

                ; We're compiling, so there is a bit more work. Note this
                ; doesn't work with double-cell numbers, only single-cell
                pea literal_rt ;  LITERAL runtime
                jsr cmpl_subroutine

                ; compile our number
                ; TODO convert this to assembler
                jsr xt_comma
                
                ; That was so much fun, let's do it again!
                bra interpret_loop

interpret_got_name_token
                ; We have a known word's nt as TOS. We're going to need its xt
                ; though, which is four bytes father down. 
                
                ; Arrive here with ( addr u nt ), so we NIP twice, which is
                ; really fast if Y is TOS 
                inx
                inx
                inx
                inx

                ; This is a quicker
                ; version of NAME>INT. But first, save a version of nt for
                ; error handling and compilation stuff.
                sty tmpbranch
                iny
                iny
                iny
                iny
                lda $0000,y ;  LDA $0000,Y
                tay ;  xt is TOS

                ; See if we are in interpret or compile mode
                lda state
                bne interpret_compile
               
                ; We are interpreting, so EXECUTE the xt that is TOS. First,
                ; though, see if this isn't a compile_only word, which would be
                ; illegal.
                lda (tmpbranch)
                xba ;  flags are MSB
                and #CO ;  mask everything but Compile Only bit
                beq interpret_interpret

                ; TODO see if we can print offending word first
                lda #es_componly
                jmp error
               
interpret_interpret
                ; We JSR to EXECUTE instead of calling the xt directly because
                ; the RTS of the word we're executing will bring us back here,
                ; skipping EXECUTE completely during RTS. If we were to execute
                ; xt directly, we have to fool around with the Return Stack
                ; instead, which is actually slightly slower
                jsr xt_execute

                ; That's quite enough for this word, let's get the next one
                jmp interpret_loop

interpret_compile
                ; We're compiling. However, we need to see if this is an
                ; IMMEDIATE word, which would mean we execute it right now even
                ; during compilation mode. Fortunately, we saved the nt so life
                ; is easier
                lda (tmpbranch)
                xba ;  flags are MSB
                and #IM ;  Mask all but IM bit
                bne interpret_interpret ;  IMMEDIATE word, execute right now

                ; Compile the xt into the Dictionary with COMPILE,
                jsr xt_compilecomma
                jmp interpret_loop

interpret_line_done
                ; drop stuff from PARSE_NAME
                ldy $02,x
                inx
                inx
                inx
                inx

                rts
                
; ------------------------------------------------------------------- 
; COMPILE WORDS, JUMPS AND SUBROUTINE JUMPS INTO CODE
; These three routines compile instructions such as "jsr xt_words" into a word
; at compile time so they are available at run time. Use by pushing the word or
; address to be compiled on the Return Stack with
;
;       phe.# <WORD>    ; PEA <WORD>
;
; Followed by a jump to whichever versions we need. Words that use this routine
; may not be natively compiled. We use "cmpl" as not to confuse these routines
; with the COMPILE, word. This routine uses tmptos. Always call this with
; a subroutine jump, which means no combining JSR/RTS to JMP.
; TODO see if we need to add a JSR.L variant at some point

        .al                   ; paranoid
cmpl_word
                lda #$0000 ;  zero value as a flag, compile word only
                bra cmpl_common
cmpl_subroutine
                lda #$0020 ;  compile "JSR" opcode first
                bra cmpl_common
cmpl_jump
                lda #$004c ;  compile "JMP", fall through to cmpl_common
cmpl_common
                ; we're going to need the Y register to get anything done 
                sty tmptos

                tay ;  force flag check
                beq cmpl_body ;  came in through cmpl_word, just compile body

                ; A contains an opcode that must be compiled first. This is an
                ; optimized version of C, ("c_comma")
        .setas
                sta (cp) ;  STA (CP)
        .setal
                inc cp ;  fall through to cmpl_body
cmpl_body
                ply ;  the return address we'll need later

                pla ;  next value on stack is the word to compile
                sta (cp) ;  this is a quicker version of , ("comma")
                inc cp
                inc cp

                phy ;  make sure we can get back home

                ldy tmptos ;  restore Data Stack

                rts


; ------------------------------------------------------------------- 
; FATAL ERROR 
; Take address of error string from A, print it and then call abort
error
                jsr print_string
                jmp xt_abort

; ------------------------------------------------------------------- 
; Print a zero terminated string to the console, adding a CR character. Takes
; the address of the string in 16-bit A register, calls put_chr.  A is
; destroyed. We could probably figure out some way to use TYPE instead, but zero
; terminated strings are easier for the 65816 to use.
print_string
        .al
        .xl
                ; don't use tmpdsp for X because we don't know if the user has
                ; used it for something already
                phx
                tax ;  x16 contains address of string
-
        .setas
                lda @w $0000,x ;  LDA $0000,X - @w to conform with tinkerers asm
                beq print_string_done
                jsr emit_a
                inx
                bra -

print_string_done
                lda #AscLF ;  should be CR on some systems
                jsr emit_a
        .setal
                plx

                rts


; ------------------------------------------------------------------- 
; PRINT UNSIGNED NUMBER
; Is the equivalent to Forth's 0 <# S# #> TYPE or U. without the SPACE at the
; end. TODO convert this to more assembler for speed
print_u
                dex ;  0
                dex
                sty $00,x
                ldy #$0000

                jsr xt_pad ;  <#
                sty tohold
                ldy $00,x
                inx
                inx
 
                jsr xt_hashs ;  #S
                jsr xt_numbermore ;  #>
                jsr xt_type

                rts


; ------------------------------------------------------------------- 
; CONVERT BYTE TO ASCII
; Convert byte in A to two ASCII hex digits and print them. Calls 
; nibble_to_ascii. Assumes A is 8 bit. 
byte_to_ascii
        .al
                pha
                ; convert high nibble first 
                lsr a
                lsr a
                lsr a
                lsr a
                jsr nibble_to_ascii

                pla
        
                ; fall thru to nibble_to_ascii


; ------------------------------------------------------------------- 
; CONVERT NIBBLE TO ASCII
; Converts the lower nibble of a number in A and returns the ASCII character
; number, then prints it. Assumes A is 8 bit
nibble_to_ascii
        .al
                and #$000f
                ora #'0'
                cmp #$003a ;  '9' + 1
                bcc +
                adc #$0006
+
                jsr emit_a
                
                rts

; ===================================================================
; HIGH-LEVEL WORDS 

; These are executed during start up. Remember that we have to put a space at
; the end of the line if there is another line with code following it. No zero
; or CR/LF is required
hi_start
        ; Output and comment words
        .text ": ( [char] ) parse 2drop ; immediate "
        .text ": .( [char] ) parse type ; immediate "

        ; High flow control. Some of these could be realized with CS-ROLL and
        ; CS-PICK instead
        .text ": if postpone 0branch here 0 , ; immediate compile-only "
        .text ": then here swap ! ; immediate compile-only "
        .text ": else postpone branch here 0 , here rot ! ; immediate compile-only "
        .text ": repeat postpone again here swap ! ; immediate compile-only "
        .text ": until postpone 0branch , ; immediate compile-only "
        .text ": while postpone 0branch here 0 , swap ; immediate compile-only "

        ; DEFER's friends. Code taken from ANSI Forth specifications. Many of
        ; these will be moved to assembler code in due course
        .text ": defer! >body ! ; "
        .text ": defer@ >body @ ; "
        .text ": is state @ if postpone ['] postpone defer! else ' defer! then ; immediate "
        .text ": action-of state @ if postpone ['] postpone defer@ else ' defer@ then ; immediate "

        ; High level math definitions. The should be moved to actual 65816 code
        ; for speed at some point. Note we use SM/REM instead of FM/MOD for most
        ; stuff
        .text ": / >r s>d r> sm/rem swap drop ; "
        .text ": /mod >r s>d r> sm/rem ; "
        .text ": mod /mod drop ; "
        .text ": */ >r m* r> sm/rem swap drop ; "
        .text ": */mod >r m* r> sm/rem ; "

        ; Output definitions. Since these usually involve the user, and humans
        ; are slow, these can stay high-level for the moment. Based on
        ; https://github.com/philburk/pforth/blob/master/fth/numberio.fth
        ; . (DOT) and U. are hard-coded because there are used by other words
        .text ": u.r >r 0 <# #s #> r> over - spaces type ; "
        .text ": .r >r dup abs 0 <# #s rot sign #> r> over - spaces type ; "
        .text ": ud. <# #s #> type space ; "
        .text ": ud.r >r <# #s #> r> over - spaces type ; "
        .text ": d. tuck dabs <# #s rot sign #> type space ; "
        .text ": d.r >r tuck dabs <# #s rot sign #> r> over - spaces type ; "

        ; Various words. Convert these to assembler
        .text ": within ( n1 n2 n3 -- f ) rot tuck > -rot > invert and ; "

        ; DUMP is a longish word we'll want to modify for a while until we are
        ; happy with the format
        .text ": dump ( addr u -- ) bounds ?do cr i 4 u.r space "
        .text "16 0 do i j + c@ 0 <# # #s #> type space loop 16 +loop ; "

        ; SEE is a longish word we'll want to modify for a while until we are
        ; happy with the format
        ; TODO replace by code, this is far too long
        .text ": see parse-name find-name dup 0= abort", 34, " No such name", 34, " "
        .text "base @ >r hex dup cr space .", 34, " nt: ", 34, " . "
        .text "dup 4 + @ space .", 34, " xt: ", 34, " . "
        .text "dup 1+ c@ 1 and if space .", 34, " CO", 34, " then "
        .text "dup 1+ c@ 2 and if space .", 34, " AN", 34, " then "
        .text "dup 1+ c@ 4 and if space .", 34, " IM", 34, " then "
        .text "dup 1+ c@ 8 and if space .", 34, " NN", 34, " then "
        .text "dup cr space .", 34, " size (decimal): ", 34, " decimal wordsize dup . "
        .text "swap name>int swap hex cr space dump r> base ! ; "

; ===================================================================
; USER INCLUDES

; Include any Forth words defined by the user in USER.TASM

        .include "user.asm"

; ===================================================================

        ; Splash strings. We leave these as high-level words because they are
        ; generated at the end of the boot process and signal that the other
        ; high-level definitions worked (or at least didn't crash)
        .text ".( Liara Forth for the W65C265SXB )"
        .text "cr .( Version ALPHA 18. September 2017)"
        .text "cr .( Scot W. Stevenson <scot.stevenson@gmail.com>)"
        .text "cr .( Liara Forth comes with absolutely NO WARRANTY)"
        .text "cr .( Type 'bye' to exit) cr"

hi_end

; ===================================================================
; BOTTOM INCLUDES

        .include "strings.asm"


; ===================================================================
; END
        .end
