; 1+2 求和 — 第一个汇编程序
; 考点：赋值、加法、字符输出

code segment
assume cs:code
main:
    mov ax, 1
    mov bx, 2
    add ax, bx          ; ax = 3
    add al, '0'         ; 转成字符 '3'
    mov dl, al
    mov ah, 2
    int 21h

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
