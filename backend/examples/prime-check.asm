; 素数判断 — 判断 CX 中的数是否为素数，输出 'Y' 或 'N'
; 考点：除法、循环、余数判断、标志位

code segment
assume cs:code
main:
    mov cx, 17          ; 要判断的数（可改成其他值）

    cmp cx, 2
    jb not_prime

    mov bx, 2
again:
    cmp bx, cx
    jae is_prime

    mov ax, cx
    mov dx, 0
    div bx              ; dx = cx % bx
    cmp dx, 0
    je not_prime

    add bx, 1
    jmp again

is_prime:
    mov dl, 'Y'
    jmp output
not_prime:
    mov dl, 'N'
output:
    mov ah, 2
    int 21h

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
