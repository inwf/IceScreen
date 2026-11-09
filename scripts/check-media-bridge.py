import argparse
import json
import pathlib
import selectors
import subprocess
import time

parser = argparse.ArgumentParser(description="检查真实系统媒体服务与打包后的辅助进程")
parser.add_argument("app", type=pathlib.Path)
args = parser.parse_args()
resources = args.app / "Contents" / "Resources"
library = args.app / "Contents" / "Frameworks" / "libIceMediaBridge.dylib"
assert library.is_file(), "Missing media bridge library"
process = subprocess.Popen(
    ["/usr/bin/perl", str(resources / "media-bridge.pl"), str(library)],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=None, text=True,
)
try:
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 10
    while True:
        assert time.monotonic() < deadline, "System media service did not return a snapshot"
        if not selector.select(timeout=0.5):
            assert process.poll() is None, "Media helper exited before responding"
            continue
        line = process.stdout.readline()
        assert line, "Media helper closed its output"
        response = json.loads(line)
        assert "error" not in response, response.get("error")
        if "snapshots" not in response:
            continue
        snapshots = response["snapshots"]
        assert isinstance(snapshots, list)
        identifiers = [item["id"] for item in snapshots]
        assert len(set(identifiers)) == len(identifiers), "Media clients must have unique identifiers"
        print(f"Media bridge loaded and queried the system: {len(snapshots)} active clients")
        break
    process.stdin.close()
    assert process.wait(timeout=5) == 0, "Media helper must exit when its parent closes the pipe"
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)
