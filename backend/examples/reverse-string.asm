; 字符串反转 — 双指针交换法
; 考点：双指针、字符交换、条件循环
; 注意：本文件使用 comment @...@ 语法，测试 -zt0 标志兼容性

comment @
    算法：si 指向首字符，di 指向末字符
    当 si < di 时交换 s[si] 和 s[di]
    si 后移、di 前移，直到相遇
@

data segment
    s db 'Hello, ASM World!', 0
data ends

code segment
assume cs:code, ds:data
main:
    mov ax, data
    mov ds, ax

    ; --- 先找到字符串末尾 ---
    mov si, offset s
    mov di, si
find_end:
    cmp byte ptr ds:[di], 0
    je found_end
    add di, 1
    jmp find_end
found_end:
    sub di, 1            ; di 指向最后一个字符

    ; --- 双指针交换 ---
swap_loop:
    cmp si, di
    jge output           ; si >= di → 交换完成
    mov al, ds:[si]
    mov ah, ds:[di]
    mov ds:[si], ah
    mov ds:[di], al
    add si, 1
    sub di, 1
    jmp swap_loop

    ; --- 输出反转后的字符串 ---
output:
    mov si, offset s
print_loop:
    mov al, ds:[si]
    cmp al, 0
    je done
    mov dl, al
    mov ah, 2
    int 21h
    add si, 1
    jmp print_loop

done:
    ; 换行
    mov dl, 0Dh
    mov ah, 2
    int 21h
    mov dl, 0Ah
    mov ah, 2
    int 21h

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
