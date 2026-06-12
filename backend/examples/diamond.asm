; 菱形星号 — 正奇数 n 行星号菱形
; 考点：除法、绝对值、嵌套循环、函数调用
; 思路：行号 i 从 -(n/2) 到 (n/2)，空格 = |i|，星号 = n - 2×|i|

code segment
assume cs:code
main:
    mov bx, 5           ; 总行数（必须是正奇数）
    mov dx, 0
    mov ax, bx
    mov bp, 2
    div bp              ; ax = bx/2（向下取整）
    mov si, 0
    sub si, ax          ; si = -(n/2)，行号从负数开始
    mov di, ax          ; di = n/2，行号上限

row_loop:
    cmp si, di
    jg done

    ; --- 计算空格数 = |si| ---
    mov bp, si
    cmp bp, 0
    jge spaces_ok
    neg bp              ; bp = abs(si) = 空格数
spaces_ok:
    push cx
    mov cx, bp
    jcxz stars          ; 空格数为 0 则直接输出星号
space_loop:
    mov ah, 2
    mov dl, ' '
    int 21h
    loop space_loop

stars:
    ; --- 计算星号数 = n - 2×|si| ---
    mov bp, si
    cmp bp, 0
    jge calc_stars
    neg bp
calc_stars:
    add bp, bp          ; bp = 2×|si|
    mov ax, bx
    sub ax, bp          ; ax = n - 2×|si|
    mov cx, ax          ; cx = 星号数
star_loop:
    mov ah, 2
    mov dl, '*'
    int 21h
    loop star_loop

    ; 换行
    mov ah, 2
    mov dl, 0Dh
    int 21h
    mov ah, 2
    mov dl, 0Ah
    int 21h

    pop cx
    add si, 1
    jmp row_loop

done:
    mov ah, 4Ch
    mov al, 0
    int 21h
code ends
end main
