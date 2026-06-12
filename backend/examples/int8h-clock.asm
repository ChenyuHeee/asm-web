; 时钟中断 int 8h 实战 — 每 1 秒输出一个字母
; 考点：IVT 钩子、硬件中断处理、EOI、iret、cli/sti
; 说明：DOSBox 完整模拟了 8253 定时器，int 8h 会以 ~18.2Hz 自动触发

code segment
assume cs:code
ticks dw 0              ; 定时器滴答计数器
old_8h dw 0, 0          ; 保存原始 int 8h 向量

; ---- 自定义 int 8h 中断处理函数 ----
int_8h:
    cmp [ticks], 0
    je skip              ; ticks=0 时不减
    dec [ticks]          ; ticks > 0，减 1
skip:
    push ax              ; 保护寄存器
    mov al, 20h          ; EOI 信号（通知 8259A PIC 中断已处理）
    out 20h, al          ; 写入 PIC 控制端口
    pop ax
    iret                 ; 中断返回（pop ip + pop cs + popf）

; ---- 延迟约 1 秒（等待 18 次 int 8h ≈ 1 秒） ----
delay_1s:
    mov [ticks], 18      ; 18 次滴答 ≈ 1 秒
wait_a_while:
    cmp [ticks], 0
    jne wait_a_while
    ret

; ---- 主程序 ----
main:
    ; 1. 保存原始 int 8h 向量（IVT 位置：0:8*4）
    xor ax, ax
    mov es, ax           ; es = 0
    mov bx, 8*4          ; int 8h 向量地址 = 0:20h
    mov ax, es:[bx]      ; 读取原偏移
    mov dx, es:[bx+2]    ; 读取原段地址
    mov cs:old_8h[0], ax
    mov cs:old_8h[2], dx

    ; 2. 安装新的 int 8h 处理函数
    cli                  ; 关中断，防止安装过程被打断
    mov word ptr es:[bx], offset int_8h
    mov word ptr es:[bx+2], seg int_8h
    sti                  ; 开中断

    ; 3. 输出 'A'~'J'，每字符间隔 1 秒
    mov cx, 10
    mov dl, 'A'
again:
    mov ah, 2
    int 21h              ; 输出 dl 中的字符
    call delay_1s         ; 延迟 1 秒
    inc dl               ; 下一个字母
    dec cx
    jnz again

    ; 4. 恢复原始 int 8h 向量
    mov ax, old_8h[0]
    mov dx, old_8h[2]
    cli
    mov es:[bx], ax
    mov es:[bx+2], dx
    sti

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
