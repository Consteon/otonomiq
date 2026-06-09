#!/usr/bin/env python3
"""Stamp synced markdown files with source-commit provenance and update SOURCES.json.

Usage:
    stamp_provenance.py <target_folder_path> <sources_json_path>

Env:
    SRC_REPO, SRC_SHA, SRC_SERVER, SRC_TS, TARGET_FOLDER

Provenance is written as an HTML comment block at the top of each file so it
never collides with the author's own YAML front-matter and stays invisible in
the GitHub-rendered view. The block is deterministic per source commit, so an
unchanged commit produces an identical stamp (no churn).
"""
import json
import os
import re
import sys
import pathlib

target_dir = pathlib.Path(sys.argv[1])
sources_json = pathlib.Path(sys.argv[2])

repo = os.environ["SRC_REPO"]
sha = os.environ["SRC_SHA"]
server = os.environ.get("SRC_SERVER", "https://github.com")
folder = os.environ["TARGET_FOLDER"]
ts = os.environ.get("SRC_TS", "")

short = sha[:8]
url = f"{server}/{repo}/commit/{sha}"

block = (
    "<!-- SYNC-PROVENANCE\n"
    f"source_repo: {repo}\n"
    f"source_commit: {sha}\n"
    f"source_url: {url}\n"
    f"synced_at: {ts}\n"
    "-->\n\n"
)

# Strip a previously-stamped block (only at file start).
prov_re = re.compile(r"\A<!-- SYNC-PROVENANCE.*?-->\n\n?", re.DOTALL)

count = 0
for md in target_dir.rglob("*.md"):
    text = md.read_text(encoding="utf-8")
    text = prov_re.sub("", text, count=1)
    md.write_text(block + text, encoding="utf-8")
    count += 1

# Update the per-source manifest at the docs-repo root.
data = {}
if sources_json.exists():
    data = json.loads(sources_json.read_text(encoding="utf-8"))

data[folder] = {
    "source_repo": repo,
    "last_commit": sha,
    "last_commit_short": short,
    "source_url": url,
    "synced_at": ts,
}

sources_json.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"Stamped {count} file(s) in {folder} <- {repo}@{short}")
