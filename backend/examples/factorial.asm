; 计算 n 的阶乘（n = 5，结果 = 120）
; 考点：乘法、loop 指令、32位寄存器

.386
code segment use16
assume cs:code
main:
    mov eax, 1
    mov cx, 5           ; 计算 5!

fact_loop:
    mul ecx             ; eax = eax * ecx
    loop fact_loop

    ; 此时 eax = 120 (0x78)
    ; 没有输出，可以在调试器中查看 eax 的值

    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
