// ---- TASM syntax mode for CodeMirror ----
CodeMirror.defineSimpleMode("tasm", {
    start: [
        { regex: /;.*/, token: "comment" },
        { regex: /comment\s*@/, token: "comment", next: "multiline_comment" },
        {
            regex: /\b(mov|add|sub|inc|dec|neg|adc|sbb|mul|imul|div|idiv|and|or|xor|not|test|shl|shr|sal|sar|rol|ror|rcl|rcr|push|pop|pushf|popf|lea|xchg|cbw|cwd|cdq|movzx|jmp|je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jc|jnc|jz|jnz|jo|jno|js|jns|jcxz|loop|loope|loopne|call|ret|retf|iret|int|into|in|out|stosb|stosw|movsb|movsw|lodsb|lodsw|cmpsb|scasb|xlat|cli|sti|nop|hlt|pusha|popa|pushad|popad|movsx|cwde|cdqe|enter|leave|lahf|sahf|daa|das|aaa|aas|aam|aad|bound|bswap|sete|setne|setg|setl|setge|setle|seta|setb|setae|setbe|setc|setnc|setz|setnz|sets|setns|seto|setno|setp|setnp|bt|bts|btr|btc|shld|shrd|cmpxchg|xadd|cpuid|cmov)\b/,
            token: "keyword"
        },
        {
            regex: /\b(ax|ah|al|bx|bh|bl|cx|ch|cl|dx|dh|dl|si|di|bp|sp|cs|ds|es|ss|ip|fl|eax|ebx|ecx|edx|esi|edi|ebp|esp|fs|gs|cr0|cr2|cr3)\b/,
            token: "variable-2"
        },
        {
            regex: /\b(db|dw|dd|dq|dt|dup|equ|org|end|ends|segment|assume|byte\s+ptr|word\s+ptr|dword\s+ptr|qword\s+ptr|far\s+ptr|near\s+ptr|short|offset|seg|ptr|this|type|length|size|width|mask|use16|use32|flat|model|option|public|extrn|proc|endp|macro|endm|local|if|else|endif|repeat|while)\b/,
            token: "def"
        },
        { regex: /\.(386|486|586|mmx|xmm)\b/, token: "def" },
        { regex: /\b[0-9]+\b/, token: "number" },
        { regex: /\b[0-9a-fA-F]+[hH]\b/, token: "number" },
        { regex: /\b[01]+[bB]\b/, token: "number" },
        { regex: /'[^']*'/, token: "string" },
        { regex: /"[^"]*"/, token: "string" },
        { regex: /[a-zA-Z_][a-zA-Z0-9_]*:/, token: "variable" },
        { regex: /[a-zA-Z_][a-zA-Z0-9_]*/, token: "variable" },
    ],
    multiline_comment: [
        { regex: /@/, token: "comment", next: "start" },
        { regex: /./, token: "comment" },
    ],
    meta: {
        dontIndentStates: ["multiline_comment"],
    },
});

// ---- editor setup ----
const editor = CodeMirror(document.getElementById("editor-container"), {
    mode: "tasm",
    theme: "material",
    lineNumbers: true,
    indentUnit: 4,
    tabSize: 4,
    indentWithTabs: false,
    matchBrackets: true,
    autoCloseBrackets: true,
    extraKeys: {
        "Shift-Tab": "indentLess",
        "Ctrl-]": "indentMore"
    },
});

editor.setValue(`data segment
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
`);

// ---- DOM refs ----
const btnRun = document.getElementById("btn-run");
const btnClear = document.getElementById("btn-clear");
const selectExample = document.getElementById("select-example");
const statusEl = document.getElementById("status");
const outputEl = document.getElementById("output");
const inputArea = document.getElementById("input-area");
const inputText = document.getElementById("input-text");

// ---- state ----
let isRunning = false;
let examplesCache = [];

// ---- load examples ----
async function loadExamples() {
    try {
        const res = await fetch("/api/examples");
        const examples = await res.json();
        examplesCache = examples;
        examples.forEach((ex) => {
            const opt = document.createElement("option");
            opt.value = ex.id;
            opt.textContent = ex.name;
            selectExample.appendChild(opt);
        });
    } catch (e) {
        statusEl.textContent = "示例加载失败，请检查服务器连接";
        statusEl.className = "status error";
    }
}

selectExample.addEventListener("change", () => {
    const id = selectExample.value;
    if (!id) return;
    const ex = examplesCache.find(e => e.id === id);
    if (ex) {
        editor.setValue(ex.code);
        statusEl.textContent = "已加载: " + ex.name;
        statusEl.className = "status";
    }
});

// ---- run ----
btnRun.addEventListener("click", async () => {
    if (isRunning) return;
    isRunning = true;

    const code = editor.getValue();
    const stdin = inputText.value;

    btnRun.disabled = true;
    btnClear.disabled = true;
    btnRun.textContent = "编译运行中...";
    statusEl.textContent = "正在执行...";
    statusEl.className = "status running";
    outputEl.textContent = "";
    outputEl.className = "";

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);

    try {
        const res = await fetch("/api/run", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ code, stdin }),
            signal: controller.signal,
        });
        const data = await res.json();

        if (data.success) {
            let outputText = data.output || "(无输出)";
            if (data.warnings && data.warnings.length > 0) {
                const warnText = data.warnings.map(w => "⚠ " + w).join("\n");
                outputText = warnText + "\n\n" + outputText;
            }
            outputEl.textContent = outputText;
            outputEl.className = "";
            statusEl.textContent = "运行完成";
            statusEl.className = "status success";

            // auto-show input area if output suggests program is waiting for input
            if (data.output === "" || data.output === "(无输出)") {
                inputArea.style.display = "block";
            }
        } else {
            let errMsg = "";
            if (data.stage === "compile") {
                errMsg = "=== 编译错误 ===\n" + data.error;
            } else if (data.stage === "runtime") {
                errMsg = "=== 运行时错误 ===\n" + data.error;
            } else {
                errMsg = "=== 系统错误 ===\n" + data.error;
            }
            if (data.warnings && data.warnings.length > 0) {
                errMsg = data.warnings.map(w => "⚠ " + w).join("\n") + "\n\n" + errMsg;
            }
            outputEl.textContent = errMsg;
            outputEl.className = "error-text";
            statusEl.textContent = "失败 (" + (data.stage || "unknown") + ")";
            statusEl.className = "status error";
        }
    } catch (e) {
        outputEl.textContent = "=== 请求失败 ===\n" + e.message + "\n\n请检查后端服务是否正常运行。";
        outputEl.className = "error-text";
        statusEl.textContent = "请求失败";
        statusEl.className = "status error";
    } finally {
        clearTimeout(timeoutId);
        btnRun.disabled = false;
        btnClear.disabled = false;
        btnRun.textContent = "▶ 运行";
        isRunning = false;
    }
});

// ---- clear ----
btnClear.addEventListener("click", () => {
    outputEl.textContent = "";
    outputEl.className = "";
    statusEl.textContent = "";
    statusEl.className = "status";
});

// ---- toggle input area ----
inputText.addEventListener("input", () => {
    if (inputText.value.trim()) {
        inputArea.style.display = "block";
    }
});

// ---- keyboard shortcut ----
document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
        e.preventDefault();
        btnRun.click();
    }
});

// ---- init ----
loadExamples();
