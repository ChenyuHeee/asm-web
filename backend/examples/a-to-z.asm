; 输出 A-Z
; 考点：字符输出、循环、cmp/je 条件跳转

code segment
assume cs:code
main:
    mov dl, 'A'
next:
    mov ah, 2
    int 21h

    cmp dl, 'Z'
    je done
    add dl, 1
    jmp next
done:
    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
