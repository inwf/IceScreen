import os
import selectors
import signal
import subprocess
import sys
from pathlib import Path

executable = str(Path(sys.argv[1]).resolve())
environment = dict(os.environ, ICESCREEN_EVENT="change", ICESCREEN_APP="App ' Name; $(literal)")
result = subprocess.run(
    [executable, "--run-detection-command", 'printf "%s\\n%s" "$ICESCREEN_EVENT" "$ICESCREEN_APP"'],
    env=environment, text=True, capture_output=True, timeout=10, check=True,
)
assert result.stdout == "change\nApp ' Name; $(literal)", result.stdout
result = subprocess.run([executable, "--run-detection-command", "exit 7"], timeout=10)
assert result.returncode == 7

# 使用真实 shell 子进程检查进程组隔离及整组终止。
process = subprocess.Popen(
    [executable, "--run-detection-command", 'sleep 30 & printf "%s\\n" "$!"; wait'],
    stdout=subprocess.PIPE, text=True,
)
try:
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        assert selector.select(timeout=10), "命令启动超时"
        child = int(process.stdout.readline().strip())
    assert os.getpgid(process.pid) == process.pid
    assert os.getpgid(child) == process.pid
    assert process.pid != os.getpgrp()
    os.killpg(process.pid, signal.SIGKILL)
    process.wait(timeout=5)
    assert process.returncode == -signal.SIGKILL
    state = subprocess.run(["ps", "-o", "stat=", "-p", str(child)], text=True, capture_output=True, check=False)
    assert not state.stdout.strip() or state.stdout.strip().startswith("Z"), state.stdout
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)
    process.stdout.close()

print("检测命令检查通过：环境变量、退出状态、独立进程组和子进程终止。")
