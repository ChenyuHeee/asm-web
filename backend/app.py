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

TIMEOUT_COMPILE = 10
TIMEOUT_RUN = 15
MAX_OUTPUT = 64 * 1024

MAX_CONCURRENT = 4
semaphore = threading.Semaphore(MAX_CONCURRENT)

os.makedirs(WORK_DIR, exist_ok=True)


def check_tools():
    missing = []
    for name, path in [("jwasm", JWASM), ("xvfb-run", XVFB), ("dosbox", DOSBOX)]:
        if not os.path.exists(path):
            missing.append(name)
    return missing


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

    # Check for unsupported output methods
    warnings = []
    if re.search(r'0[bB]800[hH]', code) or re.search(r'0[aA]000[hH]', code):
        warnings.append("检测到视频内存写入 (B800/A000)，此类输出无法被捕获，结果可能为空")
    if re.search(r'int\s+10[hH]', code):
        warnings.append("检测到 INT 10h BIOS 调用，此类输出无法被重定向捕获")
    if re.search(r'int\s+8[hH]\b|int\s+9[hH]\b', code):
        warnings.append("检测到硬件中断处理 (INT 8h/9h)，程序可能需要硬件支持或更长的运行时间")
    if re.search(r'mov\s+ah,\s*31[hH]', code):
        warnings.append("检测到 TSR (终止并驻留) 调用，在隔离环境中无法观察效果")

    if not semaphore.acquire(blocking=False):
        return jsonify({"success": False, "error": "服务器繁忙，请稍后重试（最多同时运行 4 个程序）"}), 429

    session_id = str(uuid.uuid4())[:8]
    session_dir = os.path.join(WORK_DIR, session_id)
    os.makedirs(session_dir, exist_ok=True)

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

        # ---- execute ----
        proc = subprocess.Popen(
            [XVFB, "-a", DOSBOX, "-conf", "dosbox.conf"],
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

        # ---- collect output ----
        output = ""
        output_txt = os.path.join(session_dir, "output.txt")
        if os.path.exists(output_txt):
            with open(output_txt, encoding="utf-8", errors="replace") as f:
                output = f.read()

        if not output:
            output = "(程序没有产生输出。如果使用了 INT 10h 或直接写入视频内存 (B800/A000)，这些输出无法被捕获。)"

        if len(output) > MAX_OUTPUT:
            output = output[:MAX_OUTPUT] + "\n\n--- 输出已截断 (64KB 限制) ---"

        result = {"success": True, "output": output}
        if warnings:
            result["warnings"] = warnings
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
            pass  # best-effort cleanup; cron job handles leftovers
        semaphore.release()


if __name__ == "__main__":
    missing = check_tools()
    if missing:
        print(f"WARNING: 缺少工具: {', '.join(missing)}")
    app.run(host="0.0.0.0", port=5000, debug=False)
