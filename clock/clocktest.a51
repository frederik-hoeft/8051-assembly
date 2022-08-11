; ============================================================================
; 								   MACROS
; ============================================================================

#DEFINE STACK_START				#3fh
; macro for direct address containing register bank index
#DEFINE SF_REGISTER_BANK_SELECT #3fh
; macro for direct address of push / pop buffer
#DEFINE SF_DIRECT 				3eh
; macro for direct address of push / pop buffer 2
#DEFINE SF_DIRECT_2				3dh

; ============================================================================
; 								STACK SETUP
; ============================================================================
;
; - internal stack starts at 0x40 and grows to 0x80
; - function SF_STORE is called to store the current stack frame (contents of r0 - r7).
; 		- if possible, this is done by switching register banks.
; 		- if not possible, the contents of r0 - r7 are stored on the stack where the top most entry is r7.
; - function SF_RESTORE is called to restore the stack frame (contents of r0 - r7).
; parameters and return values are also stored on the stack.


#cpu = 89S8252    ; @12 MHz

ajmp Initialisierung

Timer 0:    ; Timer 0 Interrupt
    ajmp OnTick

Initialisierung:
	; setup stack
	mov	SP, STACK_START
	; set REGISTER_BANK_SELECT = 0
	mov r0, SF_REGISTER_BANK_SELECT
	mov @r0, #0h

	orl TMOD, # 02h    ; Timer 0 im 8-Bit Autoreload-Modus. 
	; Die �berlauffrequenz des Timer 0 betr�gt 4000 Hz, die Periodendauer 0,25 ms.
	mov TH0, # 06h    ; Reloadwert

	; Interrupts
	setb ET0    ; Timer 0 Interrupt freigeben
	setb EA    ; globale Interruptfreigabe
	setb TR0    ; Timer 0 l�uft.

	; reset clock tick counter
	lcall ResetClockTicks

	; set all timer vars
	; initialize _hours
	mov DPTR, #_hours
	lcall LoadVariable
	pop SF_DIRECT
	mov r0, SF_DIRECT
	mov @r0, #0h

	; initialize _minutes
	mov DPTR, #_minutes
	lcall LoadVariable
	pop SF_DIRECT
	mov r0, SF_DIRECT
	mov @r0, #0h

	; initialize _seconds
	mov DPTR, #_seconds
	lcall LoadVariable
	pop SF_DIRECT
	mov r0, SF_DIRECT
	mov @r0, #0h

	end
; * * * Hauptprogramm Ende * * *

OnTick:
	; check if _clock_ticks is 0
	mov DPTR, #_clock_ticks		; load clock_ticks** to dptr
	lcall LoadVariable			
	pop SF_DIRECT				; pop clock_ticks* from stack
	mov r0, SF_DIRECT			; load clock_ticks* to r0
	mov A, @r0					; load clock_ticks low byte to A
	inc r0						; increment clock_ticks* to target high byte
	orl A, @r0					; Low byte OR high byte to A
	jnz __OnTick_End			; if clock_ticks is not 0, jump to OnTick_End
	; clock_ticks is 0 (a second has passed)
	; ResetClockTicks is inlibable (no need to store stack frame)
	lcall ResetClockTicks		; reset _clock_ticks to 4000
	lcall OnEachSecond 			; call OnEachSecond
__OnTick_End:
	; decrement _clock_ticks
	mov DPTR, #_clock_ticks		; load clock_ticks** to dptr
	; NOT inlinable (but don't need to preserve registers here)
	lcall DecrementWord			; decrement clock_ticks by 1
	reti

OnEachSecond:
	; IncrementSeconds is NOT inlibable (but don't need to preserve registers here)
	lcall IncrementSeconds		; increment _seconds
	ret

IncrementSeconds:
	; increment _seconds
	mov DPTR, #_seconds			; load _seconds** to dptr
	lcall LoadVariable
	pop SF_DIRECT				; pop _seconds* from stack
	mov r0, SF_DIRECT			; load _seconds* to r0
	; check if _seconds is 59
	mov A, #59d					; load 59 to A
	xrl A, @r0					; compare _seconds with 59
	jnz __IncrementSeconds_End	; if _seconds is not 59, jump to IncrementSeconds_End
	; _seconds is 59
	; reset _seconds to 0xFF (generate overflow to 0 in increment)
	mov @r0, #FFh				; load 0xFF to _seconds
	; increment _minutes
	lcall SF_STORE
	lcall IncrementMinutes
	lcall SF_RESTORE
__IncrementSeconds_End:
	inc @r0						; increment _seconds
	ret

IncrementMinutes:
	; increment _minutes
	mov DPTR, #_minutes			; load _minutes** to dptr
	lcall LoadVariable
	pop SF_DIRECT				; pop _minutes* from stack
	mov r0, SF_DIRECT			; load _minutes* to r0
	; check if _minutes is 59
	mov A, #59d					; load 59 to A
	xrl A, @r0					; compare _minutes with 59
	jnz __IncrementMinutes_End	; if _minutes is not 59, jump to IncrementMinutes_End
	; _minutes is 59
	; reset _minutes to 0xFF (generate overflow to 0 in increment)
	mov @r0, #FFh				; load 0xFF to _minutes
	; increment _hours 
	lcall SF_STORE				; store stack frame
	lcall IncrementHours
	lcall SF_RESTORE			; restore stack frame
__IncrementMinutes_End:
	inc @r0						; increment _minutes
	ret

IncrementHours:
	; increment _hours
	mov DPTR, #_hours			; load _hours** to dptr
	lcall LoadVariable			
	pop SF_DIRECT				; pop _hours* from stack
	mov r0, SF_DIRECT			; load _hours* to r0
	; check if _hours is 23
	mov A, #23d					; load 23 to A
	xrl A, @r0					; compare _hours with 23
	jnz __IncrementHours_End	; if _hours is not 23, jump to IncrementHours_End
	; _hours is 23
	; reset _hours to 0xFF (generate overflow to 0 in increment)
	mov @r0, #FFh				; load 0xFF to _hours
__IncrementHours_End:
	inc @r0						; increment _hours
	ret

; INLINEABLE
; set clock ticks to 4000d
ResetClockTicks:
	; prepare parameters
	mov DPTR, #_clock_ticks	; _clock_ticks** must be passed in dptr register
	; pass target value via stack
	mov SF_DIRECT, #0Fh		; high byte of target value 0x0FA0 (4000)
	push SF_DIRECT
	mov SF_DIRECT, #A0h		; low byte of target value 0x0FA0 (4000)
	push SF_DIRECT
	lcall SetWord
	ret

; the address of LE 16bit integer is stored in DPTR
DecrementWord:
	lcall LoadVariable 		; load address of variable to stack
	pop SF_DIRECT			; pop return value from LoadVariable
	mov r0, SF_DIRECT		; load variable pointer to r0
	mov A, @r0				; load low byte of variable to A
	dec A					; decrement low byte of variable
	mov @r0, A				; save low byte of variable
	xrl A, #FFh				; check if A is 255 (0xFF)
	jnz __DecrementWord_End	; if not, jump to end (no underflow)
	inc r0					; set r0 to high byte of variable address
	dec @r0					; decrement high byte of variable
__DecrementWord_End:
	ret

; the address of target LE 16bit integer is stored in DPTR
; 16 bit integer value is stored on the stack as big endian (top is low byte)
SetWord:
	lcall LoadVariable		; load address of variable to stack
	pop SF_DIRECT			; pop returned value from stack to DIRECT buffer
	mov r0, SF_DIRECT		; load low byte pointer to r0
	pop SF_DIRECT			; pop our own return addres high byte from the stack to access parameters
	mov A, SF_DIRECT		; save our return address high byte to A
	pop SF_DIRECT_2			; pop our own return address low byte from the stack to access parameters
	pop SF_DIRECT			; pop low byte of target value from parameter stack
	mov @r0, SF_DIRECT		; assign low byte of target value to low byte of variable
	inc r0					; increment r0 to high byte of variable address
	pop SF_DIRECT			; pop high byte of target value from parameter stack
	mov @r0, SF_DIRECT		; assign high byte of target value to high byte of variable
	; restore 16 bit return address
	push SF_DIRECT_2		; push our own return address low byte FIRST to stack
	mov SF_DIRECT, A		; ... followed by the high byte
	push SF_DIRECT			; push our own return address to the stack
	ret

; loads the variable address provided in DPTR from memory and returns it on the stack
; INLINEABLE -> we can't use r0 - r7 here 
LoadVariable:
	clr A				; wipe Acc
	movc A, @A+DPTR		; load variable address from memory
	pop SF_DIRECT		; save return address high byte to DIRECT
	pop SF_DIRECT_2		; save return address low byte to DIRECT_2 buffer
	xch A, SF_DIRECT	; swap variable address with return address high byte
	push SF_DIRECT		; save variable address to stack
	push SF_DIRECT_2	; push return address low byte on stack
	mov SF_DIRECT, A	; load return address high byte to DIRECT
	push SF_DIRECT		; restore full 16bit return address on stack
	ret

; stores the current execution context (r0 - r7) to the stack
; or switches register banks if possible
SF_STORE:
	; we can't change r0, so store it in B for now
	mov A, r0						; save r0 to A
	mov B, A						; move r0 to B
	; now load the current register bank index
	mov r0, SF_REGISTER_BANK_SELECT	; move REGISTER_BANK_SELECT* to r0
	mov A, @r0						; load REGISTER_BANK_SELECT to A
	inc @r0							; *REGISTER_BANK_SELECT++;
	; check if we can just switch register banks (REGISTER_BANK_SELECT < 3)
	; REGISTER_BANK_SELECT - 3 < 0 ? switch bank : store context on stack
	clr C							; wipe carry
	subb A, #3						;  REGISTER_BANK_SELECT - 3
	jnc __SF_STORE_StoreContext		; if REGISTER_BANK_SELECT - 3 < 0, jump to StoreContext
	; we can use another bank to store the stack context :)
	mov A, @r0						; load new REGISTER_BANK_SELECT to A
	rl A							; shift REGISTER_BANK_SELECT to the left by 3 bits
	rl A
	rl A
	mov r0, A						; move mask to r0
	mov A, PSW						; move PSW to A
	anl A, #E7h						; clear bits 3 and 4 (RS0 and RS1)
	orl A, r0						; set bits 3 and 4 (RS0 and RS1) depending on REGISTER_BANK_SELECT
	; before switching register banks restore r0 from B
	xch A, B						; swap B to A
	mov r0, A						; move A to r0, DONE!
	mov A, B						; move B to A
	; now switch register banks
	mov PSW, A						; move PSW back to memory
	ljmp __SF_STORE_End
__SF_STORE_StoreContext:
	; we need to manually store contents of r0 - r7 on the stack
	; we can't use r1 - r7 here, r0 is stored in B
	; first restore r0 from B and save our return address from the stack to B
	pop SF_DIRECT_2					; store return address high byte to DIRECT_2
	mov A, SF_DIRECT_2				; move return address high byte to A
	xch A, B						; swap B to A, B is now our return address high byte
	pop SF_DIRECT_2					; store return address low byte to DIRECT_2
	; now store r0 - r7 on the stack
	mov SF_DIRECT, A				; instead of restoring r0, move it directly to the stack
	push SF_DIRECT					; push r0
	mov SF_DIRECT, r1				; move r1 to the stack
	push SF_DIRECT					; push r1
	mov SF_DIRECT, r2				; move r2 to the stack
	push SF_DIRECT					; push r2
	mov SF_DIRECT, r3				; move r3 to the stack
	push SF_DIRECT					; push r3
	mov SF_DIRECT, r4				; move r4 to the stack
	push SF_DIRECT					; push r4
	mov SF_DIRECT, r5				; move r5 to the stack
	push SF_DIRECT					; push r5
	mov SF_DIRECT, r6				; move r6 to the stack
	push SF_DIRECT					; push r6
	mov SF_DIRECT, r7				; move r7 to the stack
	push SF_DIRECT					; push r7
	; now we need to restore our return address from B
	push SF_DIRECT_2				; push return address low byte
	mov A, B
	mov SF_DIRECT_2, A				; move return address high byte to DIRECT_2
	push SF_DIRECT_2				; push return address high byte
__SF_STORE_End:
	ret

; restores the current execution context (r0 - r7) from the stack
; or switches back to previous register banks if possible
SF_RESTORE:
	; we can use all registers here :)
	mov r0, SF_REGISTER_BANK_SELECT	; move REGISTER_BANK_SELECT* to r0
	dec @r0							; *REGISTER_BANK_SELECT--
	mov A, @r0						; load REGISTER_BANK_SELECT to A
	; if REGISTER_BANK_SELECT < 3 we can just switch register banks
	; otherwise we need to restore the context from the stack
	; REGISTER_BANK_SELECT - 3 < 0 ? switch bank : store context on stack
	clr C							; wipe carry
	subb A, #3						;  REGISTER_BANK_SELECT - 3
	jnc __SF_RESTORE_RestoreContext	; if REGISTER_BANK_SELECT - 3 < 0, jump to RestoreContext
	; we still have the context on another bank, so restore it
	mov A, @r0						; load new REGISTER_BANK_SELECT to A
	rl A							; shift REGISTER_BANK_SELECT to the left by 3 bits
	rl A
	rl A
	mov r0, A						; move mask to r0
	mov A, PSW						; move PSW to A
	anl A, #E7h						; clear bits 3 and 4 (RS0 and RS1)
	orl A, r0						; set bits 3 and 4 (RS0 and RS1) depending on REGISTER_BANK_SELECT
	; now switch register banks
	mov PSW, A						; move PSW back to memory
	ljmp __SF_RESTORE_End
__SF_RESTORE_RestoreContext:
	; we need to manually restore contents of r0 - r7 from the stack
	; unless restored, we can use all registers here :)
	; first save our return address to B though
	pop SF_DIRECT_2					; store 16 bit return address high byte to DIRECT_2
	mov A, SF_DIRECT_2				; move return address to A
	xch A, B						; swap B to A, B is now our return address high byte
	pop SF_DIRECT_2					; store 16 bit return address low byte to DIRECT_2
	; now restore r0 - r7 from the stack
	pop SF_DIRECT					; restore r7 from the stack
	mov r7, SF_DIRECT
	pop SF_DIRECT					; restore r6 from the stack
	mov r6, SF_DIRECT
	pop SF_DIRECT					; restore r5 from the stack
	mov r5, SF_DIRECT
	pop SF_DIRECT					; restore r4 from the stack
	mov r4, SF_DIRECT
	pop SF_DIRECT					; restore r3 from the stack
	mov r3, SF_DIRECT
	pop SF_DIRECT					; restore r2 from the stack
	mov r2, SF_DIRECT
	pop SF_DIRECT					; restore r1 from the stack
	mov r1, SF_DIRECT
	pop SF_DIRECT					; restore r0 from the stack
	mov r0, SF_DIRECT
	; now restore our 16 bit return address from B and DIRECT_2
	push SF_DIRECT_2				; push return address low byte
	mov A, B
	mov SF_DIRECT_2, A				; move return address high byte back to DIRECT_2
	push SF_DIRECT_2				; push return address high byte
__SF_RESTORE_End:
	ret

_hours:
	db 30h
_minutes:
	db 31h
_seconds:
	db 32h
_clock_ticks:
	db 33h ; 16 bit integer starting at RAM addr 0x33
