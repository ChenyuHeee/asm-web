; 直角三角形星号
; 考点：嵌套循环、push/pop 保护 cx、CR+LF 换行

code segment
assume cs:code
main:
    mov cx, 5           ; 共 5 行

outer_loop:
    push cx             ; 保存外层计数

    mov dl, '*'
inner_loop:
    mov ah, 2
    int 21h
    loop inner_loop

    ; 换行
    mov dl, 0Dh         ; CR
    mov ah, 2
    int 21h
    mov dl, 0Ah         ; LF
    mov ah, 2
    int 21h

    pop cx              ; 恢复外层计数
    loop outer_loop

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
