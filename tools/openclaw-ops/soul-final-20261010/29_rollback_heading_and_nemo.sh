#!/bin/bash
# 29 — trả 5 SOUL.md về bản trước bước 20 (4nguyentac). Sau đó /new.
set -euo pipefail
for f in /home/hung/.openclaw-hungreo/workspace/SOUL.md /home/hung/.openclaw-suckhoe/workspace/SOUL.md /home/hung/.hermes/SOUL.md /home/hung/.hermes/profiles/vnstock/SOUL.md /home/hung/sandbox-nemo/workspace/SOUL.md; do
  [ -f "$f.bak-20261010-pre-4nguyentac" ] && cp -p "$f.bak-20261010-pre-4nguyentac" "$f" && echo "restored $f"
done
