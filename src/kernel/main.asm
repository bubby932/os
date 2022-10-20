org 0x0
bits 16

%define ENDL 0x0D, 0x0A

start:
    mov si, msg_hello
    call puts

.loop:
    call read_key_blocking
    mov ah, 0Eh
    mov bh, 0
    int 0x10

    cmp al, 13
    je .cmd

    jmp .loop

.cmd:
    call handle_command
    jmp .loop

.halt:
    cli
    hlt


;
; Handle an entered command.
;
handle_command:
    call put_newline

    mov si, msg_unrecognized_command
    call puts

    ret

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

;
; Prints a newline
;
put_newline:
    mov si, msg_endl
    call puts
    ret

;
; Synchronously waits for a keypress and returns that key in AL.
;
read_key_blocking:
    mov ah, 0
    int 16h
    ret

msg_hello: db 'Bootloader success, hello from the kernel! You can type!', ENDL, 0
msg_unrecognized_command: db 'Unrecognized command, please try again.', ENDL, 0
msg_endl: db ENDL, 0