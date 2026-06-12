; 字符金字塔 — 输入单个数字，输出 n 层金字塔
; 考点：嵌套循环、字符 I/O、空格/字符公式
; 思路：第 i 行（1-based）有 n-i 个空格 + 2i-1 个字符
;       输入 '5' → 金字塔层数为 5，第 i 行输出数字字符 'i'

code segment
assume cs:code
main:
    ; --- 输入数字 ---
    mov ah, 1
    int 21h              ; al = 输入字符
    sub al, '0'          ; al = n（层数）
    mov cl, al           ; cl = n
    mov ch, 0
    mov bx, 1            ; bx = 当前行号（从 1 开始）
    mov dh, '1'          ; dh = 当前行要输出的字符

next_row:
    push cx              ; 保存总行数 n

    ; --- 输出 n-bx 个空格 ---
    mov al, cl           ; al = n
    mov ah, 0
    sub ax, bx           ; ax = n - bx = 空格数
    mov cx, ax
    jcxz char_part
space_loop:
    mov ah, 2
    mov dl, ' '
    int 21h
    loop space_loop

char_part:
    ; --- 输出 2×bx-1 个字符 ---
    mov cx, bx
    shl cx, 1
    sub cx, 1            ; cx = 2×bx - 1
    mov dl, dh
char_loop:
    mov ah, 2
    int 21h
    loop char_loop

    ; --- 换行 ---
    mov ah, 2
    mov dl, 0Dh
    int 21h
    mov ah, 2
    mov dl, 0Ah
    int 21h

    add bx, 1
    add dh, 1            ; 下一行输出的字符递增
    pop cx
    dec cx
    jnz next_row

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
