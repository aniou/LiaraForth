; Basic hardware routines for Liara Forth: Emulator Version
; Scot W. Stevenson <scot.stevenson@gmail.com>
; First version: 04. Jan 2017
; This version: 29. Jan 2017
;
; converted to 64tass format by Piotr Meyer <aniou@smutek.pl>, Aug 2019

; ===================================================================
; EMULATOR HOOKS
; Liara Forth only uses two hardware routines to make porting the code to
; other systems easier: put_chr and get_chr. These addresses are set up for use
; with the crude65816 emulator.


reset_hardware
                nop
                jmp start


; ===================================================================
; PUT_CHR
put_chr
                php
        .setas
                sta $0df77
        .setal
                plp
                rts

; ===================================================================
; GET_CHR
get_chr
                php
		lda #$0000  ; clears A
        .setas
                lda $0df75
        .setal
                plp

                rts

; ===================================================================
; HAVE_CHR?
; Check if the receive buffer contains any data and return C=1 if there is
; some.
; TODO CURRENTLY DOESN'T WORK WITH EMULATION

have_chr
                nop
                rts

; END
