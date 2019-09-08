; Basic hardware routines for Liara Forth: Emulator Version fo go65c816,
; taken as-is from code by
; Scot W. Stevenson <scot.stevenson@gmail.com>
; First version: 04. Jan 2017
; This version: 29. Jan 2017

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
                lda #$0000
        .setas
get_chr0
                lda $0df75
                beq get_chr0
        .setal
                plp

                rts

; ===================================================================
; HAVE_CHR?
; Check if the receive buffer contains any data and return C=1 if there is
; some.
; TODO CURRENTLY DOESN'T WORK WITH EMULATION nor in go65c816

have_chr        nop
        .setas
                lda $0df48
                ror a
        .setal
                rts

; END
