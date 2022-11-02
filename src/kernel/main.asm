org 0x0
bits 16

%define ENDL 0x0D, 0x0A

start:
    mov si, msg_hello
    call puts
    mov cx, 0

.loop:
    call read_key_blocking

    cmp al, 13
    je .cmd

    mov ah, 0Eh
    mov bh, 0
    int 0x10


    inc cx
    mov [key_entry_buffer + cx], al

    jmp .loop

.cmd:
    call handle_command

    mov al, 0
    mov [key_entry_buffer + cx], 0
    jmp .loop

.halt:
    cli
    hlt

;
; Handle an entered command.
;
handle_command:
    call put_newline

    call run_file

    ret

;
; Prints a string to the screen.
; Params:
;   - ds:si : the string to print
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

panic:
    mov ah, 0Bh
    mov bh, 00h
    mov bl, 1
    int 10h

    mov si, msg_panic
    call puts

    cli
    hlt

msg_hello: db 'Bootloader success, hello from the kernel! You can type!', ENDL, 0
msg_unrecognized_command: db 'Unrecognized command, please try again.', ENDL, 0
msg_endl: db ENDL, 0
msg_panic: db ENDL, ENDL, ENDL, 'KERNEL PANIC', ENDL, '-------------', ENDL, 'A critical internal error occurred.', ENDL, 0

; redefined because reading it again would be an unnecessary pain in the ass

bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
ebr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd, useless
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial number, value doesn't matter
ebr_volume_label:           db 'ROSEHIP  OS'        ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '           ; 8 bytes




; disk

run_file:
    push es
    mov ah, 08h
    int 13h
    jc floppy_error
    pop es

    and cl, 0x3F
    xor ch, ch
    mov [bdb_sectors_per_track], cx

    inc dh
    mov [bdb_heads], dh

    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx
    add ax, [bdb_reserved_sectors]
    push ax

    mov ax, [bdb_sectors_per_fat]
    shl ax, 5
    xor dx, dx
    div word [bdb_bytes_per_sector]

    test dx, dx
    jz .root_dir_after
    inc ax

.root_dir_after:
    mov cl, al
    pop ax
    mov dl, [ebr_drive_number]
    mov bx, buffer
    call disk_read
    
    xor bx, bx
    mov di, buffer

.search_file:
    mov si, [key_entry_buffer]
    mov cx, 11
    push di
    repe cmpsb
    pop di
    je .found_file

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_file

    stc
    ret


.found_file:
    mov ax, [di + 26]
    mov [file_cluster], ax

    ; load FAT

    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    mov bx, FILE_LOAD_SEGMENT
    mov es, bx
    mov bx, FILE_LOAD_OFFSET

.load_kernel_loop:
    mov ax, [kernel_cluster]
    add ax, 31

    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]

    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx

    mov si, buffer
    add si, ax
    mov ax, [ds:si]

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8
    jae .read_finish

    mov [kernel_cluster], ax
    jmp .load_file_loop

.read_finish:
    ; FILE JUMP
    mov dl, [ebr_drive_number]

    mov ax, FILE_LOAD_SEGMENT
    mov ds, ax
    mov es, ax

    jmp FILE_LOAD_SEGMENT:FILE_LOAD_OFFSET

    jmp wait_key_and_reboot

    cli
    hlt


;
; Reads sectors from disk
; Parameters:
;   - ax: LBA address
;   - cl: number of sectors to read (max 128)
;   - dl: drive number
;   - es:bx: output buffer location
;
disk_read:

    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax

    mov ah, 02h
    mov di, 3

.retry:
    pusha
    stc
    int 13h
    jnc .done

    ; failed
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret
;
; Resets disk controller
; Parameters
;   dl: drive number
;
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

;
; Error handlers
;

floppy_error:
    call panic

    cli
    hlt

file_cluster:         dw 0
file_name_bin: db 'FILE    BIN'

FILE_LOAD_SEGMENT     equ 0x4000
FILE_LOAD_OFFSET      equ 0

key_entry_buffer: db '                                                                    ', 0

buffer: