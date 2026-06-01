#!/usr/bin/env bash
# Downloads the on-device WhisperKit model into Models/ (gitignored — too large for git).
# Usage: ./scripts/download-model.sh [model-folder-name]
# Default: openai_whisper-large-v3-v20240930_turbo_632MB (~646 MB, bundled by the iOS app)
set -eo pipefail

REPO="argmaxinc/whisperkit-coreml"
FOLDER="${1:-openai_whisper-large-v3-v20240930_turbo_632MB}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/Models"

python3 - "$REPO" "$FOLDER" "$DEST" <<'PY'
import sys, os, json, urllib.request, urllib.parse
repo, folder, dest = sys.argv[1], sys.argv[2], sys.argv[3]
api = f"https://huggingface.co/api/models/{repo}/tree/main/{folder}?recursive=true"
res = f"https://huggingface.co/{repo}/resolve/main/"
def get(u): return urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "curl/8"}), timeout=60)
files = [f for f in json.load(get(api)) if f["type"] == "file"]
total = sum(f.get("size", 0) for f in files)
print(f"Downloading {len(files)} files ({total/1e6:.0f} MB) -> {dest}/{folder}")
for f in files:
    p, size = f["path"], f.get("size", 0)
    tgt = os.path.join(dest, p)
    os.makedirs(os.path.dirname(tgt), exist_ok=True)
    if os.path.exists(tgt) and os.path.getsize(tgt) == size:
        print("skip", p); continue
    with get(res + urllib.parse.quote(p)) as r, open(tgt, "wb") as o:
        while True:
            b = r.read(1 << 20)
            if not b: break
            o.write(b)
    print("ok  ", p)
print("done")
PY
