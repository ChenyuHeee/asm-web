; Hello World — 最简单的汇编程序
; 考点：字符串输出、程序骨架

data segment
    msg db 'Hello, World!', 0Dh, 0Ah, '$'
data ends

code segment
assume cs:code, ds:data
main:
    mov ax, data
    mov ds, ax

    mov ah, 9
    mov dx, offset msg
    int 21h

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
