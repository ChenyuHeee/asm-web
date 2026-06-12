; 统计 EAX 中 1 的个数，输出十进制结果
; 考点：移位、进位标志、除法转十进制

.386
data segment use16
    result db 0
data ends

code segment use16
assume cs:code, ds:data
main:
    mov ax, data
    mov ds, ax

    mov eax, 12345678h  ; 要统计的数
    mov cx, 32
    mov bl, 0           ; bl = 1 的计数器

count_loop:
    shl eax, 1
    jnc skip
    add bl, 1
skip:
    sub cx, 1
    jnz count_loop

    ; bl = 1 的个数, 转十进制输出
    mov al, bl
    mov ah, 0
    mov cx, 0           ; cx = 入栈位数

decimal:
    mov dx, 0
    mov bx, 10
    div bx              ; ax / 10, dx = 余数（当前位）
    push dx
    add cx, 1
    cmp ax, 0
    jne decimal

print:
    pop dx
    add dl, '0'
    mov ah, 2
    int 21h
    loop print

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
