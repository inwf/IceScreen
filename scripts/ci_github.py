#!/usr/bin/env python3
"""Select the commit and an unexpired artifact from a successful main build."""

from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import quote


ARTIFACT_NAME = "IceScreen-macOS"


def api(repository: str, path: str, *, paginate: bool = False):
    command = ["gh", "api", f"repos/{repository}/{path}"]
    if paginate:
        command.extend(["--paginate", "--slurp"])
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def paged_items(pages, key: str):
    return [item for page in pages for item in page.get(key, [])]


def reusable_run(repository: str, sha: str) -> str:
    query = f"event=push&branch=main&head_sha={quote(sha, safe='')}&per_page=100"
    runs = paged_items(
        api(repository, f"actions/workflows/release.yml/runs?{query}", paginate=True),
        "workflow_runs",
    )
    candidates = [
        run for run in runs
        if run.get("head_sha") == sha
        and run.get("event") == "push"
        and run.get("head_branch") == "main"
        and (run.get("head_repository") or {}).get("full_name", "").lower() == repository.lower()
    ]
    if not candidates:
        print("No successful main build found; this run will build the commit.", flush=True)
        return ""

    run = max(candidates, key=lambda item: item["id"])
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        print(f"Main build is not reusable ({run.get('html_url', run['id'])}); rebuilding.", flush=True)
        return ""

    artifacts = paged_items(
        api(repository, f"actions/runs/{run['id']}/artifacts?per_page=100", paginate=True),
        "artifacts",
    )
    now = datetime.now(timezone.utc)
    for artifact in artifacts:
        if artifact.get("name") != ARTIFACT_NAME or artifact.get("expired"):
            continue
        if (artifact.get("workflow_run") or {}).get("head_sha") != sha:
            continue
        expires_at = datetime.fromisoformat(artifact["expires_at"].replace("Z", "+00:00"))
        if expires_at <= now + timedelta(minutes=10):
            continue
        print(f"Reusing verified artifact from {run.get('html_url', run['id'])}.", flush=True)
        return str(run["id"])

    print("The successful main artifact is missing or expiring; this run will rebuild.", flush=True)
    return ""


def prepare() -> None:
    repository = os.environ["GITHUB_REPOSITORY"]
    tag = os.environ.get("RELEASE_TAG", "").strip()
    if tag:
        if not tag.startswith("v") or any(char.isspace() for char in tag):
            raise ValueError("发布标签必须以 v 开头且不能包含空白字符")
        commit = api(repository, f"commits/{quote(tag, safe='')}")
        sha = commit["sha"]
        run_id = reusable_run(repository, sha)
    else:
        sha = os.environ.get("GITHUB_SHA", "")
        if not sha:
            sha = subprocess.run(
                ["git", "rev-parse", "HEAD"], check=True, capture_output=True, text=True
            ).stdout.strip()
        run_id = ""

    output = Path(os.environ["GITHUB_OUTPUT"])
    with output.open("a", encoding="utf-8") as stream:
        stream.write(f"sha={sha}\nrun_id={run_id}\n")
    print(f"Selected commit {sha}; artifact run: {run_id or 'current run'}", flush=True)


if __name__ == "__main__":
    if sys.argv[1:] != ["prepare"]:
        raise SystemExit("usage: ci_github.py prepare")
    prepare()
