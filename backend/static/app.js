// ---- TASM syntax mode for CodeMirror ----
CodeMirror.defineSimpleMode("tasm", {
    start: [
        { regex: /;.*/, token: "comment" },
        { regex: /comment\s+@/, token: "comment", next: "multiline_comment" },
        {
            regex: /\b(mov|add|sub|inc|dec|neg|adc|sbb|mul|imul|div|idiv|and|or|xor|not|test|shl|shr|sal|sar|rol|ror|rcl|rcr|push|pop|pushf|popf|lea|xchg|cbw|cwd|cdq|movzx|jmp|je|jne|jg|jl|jge|jle|ja|jb|jae|jbe|jc|jnc|jz|jnz|jo|jno|js|jns|jcxz|loop|loope|loopne|call|ret|retf|iret|int|into|in|out|stosb|stosw|movsb|movsw|lodsb|lodsw|cmpsb|scasb|xlat|cli|sti|nop|hlt)\b/,
            token: "keyword"
        },
        {
            regex: /\b(ax|ah|al|bx|bh|bl|cx|ch|cl|dx|dh|dl|si|di|bp|sp|cs|ds|es|ss|ip|fl|eax|ebx|ecx|edx|esi|edi|ebp|esp|fs|gs|cr0|cr2|cr3)\b/,
            token: "variable-2"
        },
        {
            regex: /\b(db|dw|dd|dq|dt|dup|equ|org|end|ends|segment|ends|assume|byte\s+ptr|word\s+ptr|dword\s+ptr|qword\s+ptr|far\s+ptr|near\s+ptr|short|offset|seg|ptr|this|type|length|size|width|mask|\.386|\.486|\.586|\.mmx|\.xmm|use16|use32|flat|model|option|public|extrn|proc|endp|macro|endm|local|if|else|endif|repeat|while)\b/,
            token: "def"
        },
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
    extraKeys: { Tab: (cm) => cm.execCommand("insertSoftTab") },
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

// ---- load examples ----
async function loadExamples() {
    try {
        const res = await fetch("/api/examples");
        const examples = await res.json();
        examples.forEach((ex) => {
            const opt = document.createElement("option");
            opt.value = ex.id;
            opt.textContent = ex.name;
            selectExample.appendChild(opt);
        });
    } catch (e) {
        console.warn("加载示例失败:", e);
    }
}

selectExample.addEventListener("change", () => {
    const id = selectExample.value;
    if (!id) return;
    fetch("/api/examples")
        .then((r) => r.json())
        .then((examples) => {
            const ex = examples.find((e) => e.id === id);
            if (ex) {
                editor.setValue(ex.code);
                statusEl.textContent = "已加载: " + ex.name;
                statusEl.className = "status";
            }
        });
    selectExample.value = "";
});

// ---- run ----
btnRun.addEventListener("click", async () => {
    const code = editor.getValue();
    const stdin = inputText.value;

    btnRun.disabled = true;
    btnRun.textContent = "编译运行中...";
    statusEl.textContent = "编译中...";
    statusEl.className = "status running";
    outputEl.textContent = "";
    outputEl.className = "";

    try {
        const res = await fetch("/api/run", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ code, stdin }),
        });
        const data = await res.json();

        if (data.success) {
            outputEl.textContent = data.output || "(无输出)";
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
        btnRun.disabled = false;
        btnRun.textContent = "▶ 运行";
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
