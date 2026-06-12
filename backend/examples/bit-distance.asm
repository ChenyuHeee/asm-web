; 位位置差 — EAX 中最左侧 1 和最右侧 1 的位号之差
; 考点：移位、位运算、十进制输出、32位寄存器
; 思路：用移位掩码分别从高位扫描（找最左1）和从低位扫描（找最右1）

.386
code segment use16
assume cs:code
main:
    mov eax, 12345678h   ; 要测试的数（可改成其他值）

    ; --- 找最左侧的 1 ---
    mov ecx, 31
find_left:
    mov ebx, 1
    shl ebx, cl         ; ebx = 1 << ecx（掩码移到当前位）
    test eax, ebx
    jnz found_left
    sub ecx, 1
    jge find_left
    ; ecx < 0 → 没找到 1 → 输出 0
    mov dl, '0'
    mov ah, 2
    int 21h
    jmp done

found_left:
    mov esi, ecx        ; esi = 最左侧 1 的位号

    ; --- 找最右侧的 1 ---
    mov ecx, 0
find_right:
    mov ebx, 1
    shl ebx, cl         ; ebx = 1 << ecx
    test eax, ebx
    jnz found_right
    add ecx, 1
    cmp ecx, 31
    jle find_right
    ; 没找到 1
    mov dl, '0'
    mov ah, 2
    int 21h
    jmp done

found_right:
    mov edi, ecx        ; edi = 最右侧 1 的位号

    ; --- 计算差值并输出 ---
    mov eax, esi
    sub eax, edi        ; eax = 位号之差

    ; --- 转十进制输出 ---
    mov ecx, 0
push_loop:
    mov edx, 0
    mov ebx, 10
    div ebx             ; eax / 10 → eax=商, edx=余数
    push edx
    inc ecx
    cmp eax, 0
    jne push_loop

pop_loop:
    pop edx
    add dl, '0'
    mov ah, 2
    int 21h
    loop pop_loop

    ; 换行
    mov dl, 0Dh
    mov ah, 2
    int 21h
    mov dl, 0Ah
    mov ah, 2
    int 21h

done:
    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
