; 9×9 乘法表 — 嵌套循环 + 对齐输出
; 考点：嵌套循环、除法拆数字、字符数组模板
; 思路：用 s 数组作为输出模板，动态修改被乘数、乘数和乘积

data segment
    ; 模板：被乘数×乘数=乘积  (1×1= 1的格式，两位对齐)
    s db '1×1=  ', '$'
    cr db 0Dh, 0Ah, '$'
data ends

code segment
assume cs:code, ds:data
main:
    mov ax, data
    mov ds, ax

    mov byte ptr s[0], '1'     ; 被乘数从 1 开始

outer:
    mov al, s[0]
    mov s[2], al                ; 乘数 = 被乘数

inner:
    ; --- 计算乘积 ---
    mov al, s[0]
    sub al, '0'
    mov bl, s[2]
    sub bl, '0'
    mul bl                      ; al = 乘积

    ; --- 拆分十位和个位 ---
    mov ah, 0
    mov bl, 10
    div bl                      ; al = 十位, ah = 个位
    cmp al, 0
    jne tens_exists
    mov s[4], ' '               ; 十位为 0 → 空格占位
    jmp units
tens_exists:
    add al, '0'
    mov s[4], al
units:
    add ah, '0'
    mov s[5], ah

    ; --- 输出算式 ---
    mov ah, 9
    mov dx, offset s
    int 21h
    mov ah, 2
    mov dl, ' '
    int 21h

    ; --- 乘数 +1 ---
    inc byte ptr s[2]
    cmp s[2], '9'
    jbe inner

    ; --- 换行 ---
    mov ah, 9
    mov dx, offset cr
    int 21h

    ; --- 被乘数 +1 ---
    inc byte ptr s[0]
    mov al, s[0]
    mov s[2], al
    cmp s[0], '9'
    jbe outer

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
