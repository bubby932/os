org 0x0
bits 16

%define ENDL 0x0D, 0x0A

start:
    mov si, msg_hello
    call puts

.halt
    cli
    hlt

;
; Prints a string to the screen.
; Params:
;   - ds:si the string to print
;
puts:
    ; save registers
    push si
    push ax

.loop:
    lodsb 
    or al, al
    jz .done

    mov ah, 0x0e
    mov bh, 0

    int 0x10

    jmp .loop

.done:
    pop ax
    pop si
    ret

msg_hello: db 'Bootloader success, hello from the kernel!', ENDL, 0