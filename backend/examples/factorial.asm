; 计算 n 的阶乘并输出十进制结果（n = 5, 5! = 120）
; 考点：乘法、loop 指令、32位寄存器、除法转十进制输出

.386
data segment use16
    msg db '5! = $'
data ends

code segment use16
assume cs:code, ds:data
main:
    mov ax, data
    mov ds, ax

    ; --- 输出提示 "5! = " ---
    mov ah, 9
    mov dx, offset msg
    int 21h

    ; --- 计算 5! ---
    mov eax, 1
    mov cx, 5

fact_loop:
    mul ecx             ; eax = eax × ecx
    loop fact_loop      ; 此时 eax = 120

    ; --- 转十进制输出 ---
    mov ecx, 0          ; ecx = 入栈位数计数器
push_digits:
    mov edx, 0
    mov ebx, 10
    div ebx             ; eax / 10 → eax=商, edx=余数
    push dx             ; 保存余数（当前最低位）
    inc cx
    cmp eax, 0
    jne push_digits

pop_digits:
    pop dx
    add dl, '0'
    mov ah, 2
    int 21h
    loop pop_digits

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
