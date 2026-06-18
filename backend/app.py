import subprocess
import uuid
import os
import shutil
import signal
import threading
import re
from flask import Flask, request, jsonify, send_from_directory

app = Flask(__name__, static_folder="static", static_url_path="")

WORK_DIR = "/tmp/asm-web"
JWASM = "/usr/local/bin/jwasm"
XVFB = "/usr/bin/xvfb-run"
DOSBOX = "/usr/bin/dosbox"
BWRAP = "/usr/bin/bwrap"

TIMEOUT_COMPILE = 10
TIMEOUT_RUN = 15
MAX_OUTPUT = 64 * 1024

MAX_CONCURRENT = 4
semaphore = threading.Semaphore(MAX_CONCURRENT)

os.makedirs(WORK_DIR, exist_ok=True)

# 危险代码模式：即使有 bwrap 沙箱也要警告用户
DANGEROUS_PATTERNS = [
    (r'\\\\\.\.\\\\|\\\\\.\.\\b|\\\.\.\\\\', "目录遍历 (..\\) — 尝试访问宿主机文件系统"),
    (r'int\s+13[hH]', "INT 13h — BIOS 磁盘直接操作"),
    (r'int\s+25[hH]', "INT 25h — 绝对磁盘扇区读取"),
    (r'int\s+26[hH]', "INT 26h — 绝对磁盘扇区写入"),
    (r'(?i)format\s+[cCdD]', "FORMAT 命令 — 格式化磁盘"),
    (r'in\s+al,\s*70[hH]', "CMOS 端口读取 (in al, 70h)"),
    (r'out\s+70[hH],\s*al', "CMOS 端口写入 (out 70h, al)"),
]


def check_tools():
    missing = []
    for name, path in [("jwasm", JWASM), ("xvfb-run", XVFB), ("dosbox", DOSBOX), ("bwrap", BWRAP)]:
        if not os.path.exists(path):
            missing.append(name)
    return missing


def has_bwrap():
    return os.path.exists(BWRAP)


def build_sandbox_cmd(session_dir):
    """构建 bwrap 沙箱命令，隔离 DOSBox 的文件系统访问。

    原理：
    - / 整个宿主文件系统以只读方式挂载
    - /tmp 使用独立 tmpfs（程序即使写 /tmp 也无法影响宿主机）
    - 仅 session_dir 可读写
    - 即使 DOS 程序做 ..\\..\\..\\tmp\\poc.txt 也无法穿透

    回退：如果 bwrap 不可用，直接返回无沙箱命令（仅依赖超时+进程组隔离）
    """
    if not has_bwrap():
        return [XVFB, "-a", DOSBOX, "-conf", "dosbox.conf"]

    return [
        BWRAP,
        "--ro-bind", "/", "/",
        "--dev", "/dev",
        "--proc", "/proc",
        "--tmpfs", "/tmp",
        "--bind", session_dir, session_dir,
        "--unshare-all",
        "--die-with-parent",
        XVFB, "-a", DOSBOX, "-conf", "dosbox.conf",
    ]


@app.route("/")
def index():
    return send_from_directory("static", "index.html")


@app.route("/api/health")
def health():
    missing = check_tools()
    if missing:
        return jsonify({"status": "degraded", "missing": missing})
    return jsonify({"status": "ok"})


@app.route("/api/examples")
def examples():
    examples_dir = os.path.join(os.path.dirname(__file__), "examples")
    result = []
    if os.path.exists(examples_dir):
        for f in sorted(os.listdir(examples_dir)):
            if not f.endswith(".asm"):
                continue
            filepath = os.path.join(examples_dir, f)
            with open(filepath, encoding="utf-8", errors="replace") as fh:
                code = fh.read()
            label = f.replace(".asm", "").replace("-", " ").title()
            result.append({"id": f.replace(".asm", ""), "name": label, "code": code})
    return jsonify(result)


@app.route("/api/run", methods=["POST"])
def run():
    if not request.is_json:
        return jsonify({"success": False, "error": "Content-Type 必须为 application/json"}), 415

    data = request.get_json()
    if not data or "code" not in data:
        return jsonify({"success": False, "error": "请提供代码"}), 400

    code = data["code"]
    stdin = data.get("stdin", "")

    MAX_CODE_SIZE = 100 * 1024  # 100KB
    MAX_STDIN_SIZE = 4 * 1024   # 4KB

    if len(code) > MAX_CODE_SIZE:
        return jsonify({"success": False, "error": f"代码超过大小限制 ({MAX_CODE_SIZE // 1024}KB)"}), 400
    if len(stdin) > MAX_STDIN_SIZE:
        return jsonify({"success": False, "error": f"输入超过大小限制 ({MAX_STDIN_SIZE // 1024}KB)"}), 400

    # ---- 安全扫描 ----
    warnings = []
    security_warnings = []

    for pattern, desc in DANGEROUS_PATTERNS:
        if re.search(pattern, code):
            security_warnings.append(f"[安全警告] {desc}")

    # 视频/中断输出方式检测
    if re.search(r'0[bB]800[hH]', code) or re.search(r'0[aA]000[hH]', code):
        warnings.append("检测到视频内存写入 (B800/A000)，此类输出无法被捕获，结果可能为空")
    if re.search(r'int\s+10[hH]', code):
        warnings.append("检测到 INT 10h BIOS 调用，此类输出无法被重定向捕获")
    if re.search(r'int\s+9[hH]\b', code):
        warnings.append("检测到键盘中断处理 (INT 9h)，无头模式下无法注入键盘扫描码，程序可能无法正常交互")
    elif re.search(r'int\s+8[hH]\b', code):
        warnings.append("检测到时钟中断处理 (INT 8h)，DOSBox 支持定时器模拟，但程序运行时间可能较长")
    if re.search(r'mov\s+ah,\s*31[hH]', code):
        warnings.append("检测到 TSR (终止并驻留) 调用，在隔离环境中无法观察效果")

    # 如果 bwrap 不可用且代码有危险模式，拒绝执行
    if not has_bwrap() and security_warnings:
        return jsonify({
            "success": False,
            "stage": "security",
            "error": "代码包含潜在危险操作，且服务器缺少 bwrap 沙箱保护，已拒绝执行：\n"
                     + "\n".join(security_warnings),
        }), 403

    all_warnings = security_warnings + warnings

    if not semaphore.acquire(blocking=False):
        return jsonify({"success": False, "error": "服务器繁忙，请稍后重试（最多同时运行 4 个程序）"}), 429

    session_id = str(uuid.uuid4())[:8]
    session_dir = os.path.join(WORK_DIR, session_id)
    os.makedirs(session_dir, exist_ok=True)

    # 记录运行前 session 目录外的文件状态（用于事后审计）
    files_before = set(os.listdir(WORK_DIR))

    try:
        # ---- write source ----
        asm_path = os.path.join(session_dir, "source.asm")
        with open(asm_path, "w", encoding="utf-8") as f:
            f.write(code)

        # ---- compile ----
        proc = subprocess.Popen(
            [JWASM, "-mz", "-zt0", "-nologo", "source.asm"],
            cwd=session_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            compile_stdout, compile_stderr = proc.communicate(timeout=TIMEOUT_COMPILE)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            proc.wait()
            return jsonify({
                "success": False,
                "stage": "compile",
                "error": f"编译超时（{TIMEOUT_COMPILE} 秒限制）",
            })

        if proc.returncode != 0:
            err = compile_stderr or compile_stdout or "未知编译错误"
            return jsonify({"success": False, "stage": "compile", "error": err})

        # ---- locate executable ----
        exe_path = None
        for name in os.listdir(session_dir):
            if name.lower().endswith((".exe", ".com")):
                exe_path = os.path.join(session_dir, name)
                break

        if not exe_path:
            return jsonify({
                "success": False,
                "stage": "compile",
                "error": "编译未生成可执行文件，请检查代码",
            })

        # ---- prepare stdin ----
        stdin_path = None
        if stdin:
            stdin_path = os.path.join(session_dir, "input.txt")
            content = stdin.replace("\r\n", "\n").replace("\n", "\r\n")
            if not content.endswith("\r\n"):
                content += "\r\n"
            with open(stdin_path, "w", encoding="utf-8") as f:
                f.write(content)

        # ---- dosbox config ----
        conf_path = os.path.join(session_dir, "dosbox.conf")
        with open(conf_path, "w") as f:
            f.write("[sdl]\noutput=surface\nfullscreen=false\n\n")
            f.write("[dosbox]\nmemsize=16\n\n")
            f.write("[autoexec]\n")
            f.write(f"mount c {session_dir}\n")
            f.write("c:\n")
            if stdin_path:
                f.write("source.exe < input.txt > output.txt\n")
            else:
                f.write("source.exe > output.txt\n")
            f.write("exit\n")

        # ---- execute (with bwrap sandbox) ----
        sandbox_cmd = build_sandbox_cmd(session_dir)

        proc = subprocess.Popen(
            sandbox_cmd,
            cwd=session_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            run_stdout, run_stderr = proc.communicate(timeout=TIMEOUT_RUN)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            proc.wait()
            return jsonify({
                "success": False,
                "stage": "runtime",
                "error": f"程序运行超时（{TIMEOUT_RUN} 秒限制），可能存在死循环",
            })

        # ---- 事后审计：检查是否有文件泄露到 session 目录外 ----
        files_after = set(os.listdir(WORK_DIR))
        leaked = files_after - files_before - {session_id}
        if leaked:
            # 清理泄露的文件
            for leaked_name in leaked:
                leaked_path = os.path.join(WORK_DIR, leaked_name)
                try:
                    if os.path.isfile(leaked_path):
                        os.remove(leaked_path)
                    elif os.path.isdir(leaked_path):
                        shutil.rmtree(leaked_path)
                except Exception:
                    pass
            security_warnings.append(
                f"[已拦截] 程序尝试在沙箱外创建文件: {', '.join(leaked)}"
            )

        # ---- collect output ----
        output = ""
        for fname in ("output.txt", "OUTPUT.TXT", "Output.txt"):
            output_txt = os.path.join(session_dir, fname)
            if os.path.exists(output_txt):
                with open(output_txt, encoding="utf-8", errors="replace") as f:
                    output = f.read()
                break

        if not output:
            output = "(程序没有产生输出。如果使用了 INT 10h 或直接写入视频内存 (B800/A000)，这些输出无法被捕获。)"

        if len(output) > MAX_OUTPUT:
            output = output[:MAX_OUTPUT] + "\n\n--- 输出已截断 (64KB 限制) ---"

        result = {"success": True, "output": output}
        if all_warnings:
            result["warnings"] = all_warnings
        return jsonify(result)

    except subprocess.TimeoutExpired:
        return jsonify({
            "success": False,
            "stage": "compile",
            "error": f"编译超时（{TIMEOUT_COMPILE} 秒限制）",
        })
    except Exception as e:
        return jsonify({"success": False, "stage": "system", "error": str(e)})
    finally:
        try:
            shutil.rmtree(session_dir)
        except Exception:
            pass
        semaphore.release()


if __name__ == "__main__":
    missing = check_tools()
    if missing:
        print(f"WARNING: 缺少工具: {', '.join(missing)}")
    if not has_bwrap():
        print("WARNING: bwrap 未安装，DOSBox 将无文件系统沙箱运行！")
        print("  安装: sudo apt install bubblewrap")
    app.run(host="0.0.0.0", port=5000, debug=False)
