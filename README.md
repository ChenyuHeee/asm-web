# asm-web

Web-based x86 assembly language practice platform. 

Write TASM-compatible assembly code in the browser, compile and run it on a real DOSBox backend.

## Architecture

- **Frontend**: Single-page app with CodeMirror 6 editor
- **Backend**: Python Flask + JWasm + DOSBox
- **Target**: Ubuntu 22 server

## Setup

See [REQUIREMENTS.md](REQUIREMENTS.md) for full details.

### Quick start

```bash
# Install system dependencies
sudo apt install jwasm dosbox-staging

# Install Python dependencies
cd backend && pip install -r requirements.txt

# Run
python app.py
```
