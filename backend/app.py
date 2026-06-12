import subprocess
import uuid
import os
import shutil
from flask import Flask, request, jsonify, send_from_directory

app = Flask(__name__, static_folder="static", static_url_path="")

WORK_DIR = "/tmp/asm-web"
JWASM = "/usr/local/bin/jwasm"
XVFB = "/usr/bin/xvfb-run"
DOSBOX = "/usr/bin/dosbox"

TIMEOUT_COMPILE = 10
TIMEOUT_RUN = 5
MAX_OUTPUT = 64 * 1024

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
    data = request.get_json()
    if not data or "code" not in data:
        return jsonify({"success": False, "error": "请提供代码"}), 400

    code = data["code"]
    stdin = data.get("stdin", "")

    session_id = str(uuid.uuid4())[:8]
    session_dir = os.path.join(WORK_DIR, session_id)
    os.makedirs(session_dir, exist_ok=True)

    try:
        # ---- write source ----
        asm_path = os.path.join(session_dir, "source.asm")
        with open(asm_path, "w", encoding="utf-8") as f:
            f.write(code)

        # ---- compile ----
        compile_result = subprocess.run(
            [JWASM, "-mz", "-nologo", "source.asm"],
            cwd=session_dir,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_COMPILE,
        )

        if compile_result.returncode != 0:
            err = compile_result.stderr or compile_result.stdout or "未知编译错误"
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
            with open(stdin_path, "w", encoding="utf-8") as f:
                f.write(stdin)
            # ensure DOS line ending for proper int 21h buffered input
            if not stdin.endswith("\r\n") and not stdin.endswith("\n"):
                f.write("\r\n")

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
        try:
            run_result = subprocess.run(
                [XVFB, "-a", DOSBOX, "-conf", "dosbox.conf"],
                cwd=session_dir,
                capture_output=True,
                text=True,
                timeout=TIMEOUT_RUN,
            )
        except subprocess.TimeoutExpired:
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
            output = run_result.stdout or ""

        if len(output) > MAX_OUTPUT:
            output = output[:MAX_OUTPUT] + "\n\n--- 输出已截断 (64KB 限制) ---"

        return jsonify({"success": True, "output": output})

    except subprocess.TimeoutExpired:
        return jsonify({
            "success": False,
            "stage": "compile",
            "error": f"编译超时（{TIMEOUT_COMPILE} 秒限制）",
        })
    except Exception as e:
        return jsonify({"success": False, "stage": "system", "error": str(e)})
    finally:
        shutil.rmtree(session_dir, ignore_errors=True)


if __name__ == "__main__":
    missing = check_tools()
    if missing:
        print(f"WARNING: 缺少工具: {', '.join(missing)}")
    app.run(host="0.0.0.0", port=5000, debug=True)
