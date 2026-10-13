#!/bin/bash
# 29 — gỡ 2 dòng motto: trả 3 SOUL.md về bản trước bước 20. Sau đó /new.
set -euo pipefail
for f in /home/hung/.openclaw-suckhoe/workspace/SOUL.md /home/hung/.hermes/SOUL.md /home/hung/.hermes/profiles/vnstock/SOUL.md; do
  [ -f "$f.bak-20261009-pre-motto" ] && cp -p "$f.bak-20261009-pre-motto" "$f" && echo "restored $f"
done
