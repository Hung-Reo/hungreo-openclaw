#!/bin/bash
# 99 — trả 3 SOUL.md về bản trước 09/10 (soul4). Sau đó /new.
set -euo pipefail
for f in /home/hung/.openclaw-hungreo/workspace/SOUL.md /home/hung/.openclaw-suckhoe/workspace/SOUL.md /home/hung/.hermes/profiles/vnstock/SOUL.md; do
  [ -f "$f.bak-20261009-pre-soul4" ] && cp -p "$f.bak-20261009-pre-soul4" "$f" && echo "restored $f"
done
