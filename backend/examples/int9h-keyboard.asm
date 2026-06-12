; 键盘中断 int 9h — IVT 钩子机制演示
; 考点：IVT 钩子与恢复、in al, 60h 读取扫描码、EOI、iret、cli/sti
; 说明：无头模式下无真实键盘，本程序通过 int 9h 指令手动触发中断处理
;       函数来演示 IVT 钩子的完整生命周期（安装 → 触发 → 恢复）

data segment
    old_9h dw 0, 0      ; 保存原始 int 9h 向量
    scan_code db 0       ; 保存读取到的扫描码
    msg_hook  db 'IVT hooked. Triggering int 9h...', 0Dh, 0Ah, '$'
    msg_scan  db 'Scan code from port 60h: $'
    msg_up    db ' (Key Up)', 0Dh, 0Ah, '$'
    msg_down  db ' (Key Down)', 0Dh, 0Ah, '$'
    msg_eoi   db 'EOI sent to PIC.', 0Dh, 0Ah, '$'
    msg_done  db 'IVT restored. Done.', 0Dh, 0Ah, '$'
    hex_tbl   db '0123456789ABCDEF'
data ends

code segment
assume cs:code, ds:data

; ---- 自定义 int 9h 中断处理函数 ----
int_9h:
    push ax
    push bx
    push ds

    mov ax, data
    mov ds, ax          ; 中断处理中必须重设 DS

    in al, 60h          ; 从键盘控制器端口读取扫描码
    mov [scan_code], al

    ; ---- 分析扫描码 ----
    ; bit7=1: 键释放 (KeyUp)
    ; bit7=0: 键按下 (KeyDown)
    test al, 80h
    jnz show_up

    ; 键按下 — 输出扫描码
    mov ah, 9
    mov dx, offset msg_scan
    int 21h
    mov al, [scan_code]
    call print_hex
    mov ah, 9
    mov dx, offset msg_down
    int 21h
    jmp send_eoi

show_up:
    mov ah, 9
    mov dx, offset msg_scan
    int 21h
    mov al, [scan_code]
    call print_hex
    mov ah, 9
    mov dx, offset msg_up
    int 21h

send_eoi:
    ; EOI — 通知 8259A PIC 当前中断已处理完毕
    mov ah, 9
    mov dx, offset msg_eoi
    int 21h
    mov al, 20h
    out 20h, al

    pop ds
    pop bx
    pop ax
    iret                ; 中断返回

; ---- 以十六进制输出 AL 的值 ----
print_hex:
    push ax
    push bx
    mov bx, offset hex_tbl
    push ax
    mov cl, 4
    shr al, cl          ; 取高 4 位
    xlat                ; al = hex_tbl[al]
    mov dl, al
    mov ah, 2
    int 21h
    pop ax
    and al, 0Fh         ; 取低 4 位
    xlat
    mov dl, al
    mov ah, 2
    int 21h
    pop bx
    pop ax
    ret

; ---- 主程序 ----
main:
    mov ax, data
    mov ds, ax

    ; 1. 钩住 int 9h：保存原始向量 + 安装新向量
    xor ax, ax
    mov es, ax          ; es = 0（IVT 基址）
    mov bx, 9*4         ; int 9h 向量地址 = 0:24h

    mov ax, es:[bx]
    mov dx, es:[bx+2]
    mov old_9h[0], ax
    mov old_9h[2], dx

    cli
    mov word ptr es:[bx], offset int_9h
    mov word ptr es:[bx+2], seg int_9h
    sti

    mov ah, 9
    mov dx, offset msg_hook
    int 21h

    ; 2. 手动触发 int 9h（模拟一次键按下 + 一次键释放）
    ;    因为无头模式下没有真实键盘，用 int 指令直接调用 ISR
    ;    端口 60h 会返回 DOSBox 模拟的上次扫描码
    int 9h              ; 模拟键按下
    int 9h              ; 模拟键释放

    ; 3. 恢复原始 int 9h 向量
    mov ax, old_9h[0]
    mov dx, old_9h[2]
    cli
    mov es:[bx], ax
    mov es:[bx+2], dx
    sti

    mov ah, 9
    mov dx, offset msg_done
    int 21h

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
