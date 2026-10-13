#!/bin/bash
# 99 — trả 4 SOUL.md về bản trước 10/10 (soul-final). Sau đó /new.
set -euo pipefail
for f in /home/hung/.openclaw-hungreo/workspace/SOUL.md /home/hung/.openclaw-suckhoe/workspace/SOUL.md /home/hung/.hermes/SOUL.md /home/hung/.hermes/profiles/vnstock/SOUL.md; do
  [ -f "$f.bak-20261010-pre-soul-final" ] && cp -p "$f.bak-20261010-pre-soul-final" "$f" && echo "restored $f"
done
