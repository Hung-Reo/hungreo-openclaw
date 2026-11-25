#!/bin/bash
# 99 — trả SOUL.md Hermes về bản trước 09/10 và gỡ AGENTS.md (lưu lại bản đã gỡ). Không restart.
set -euo pipefail
H=/home/hung/.hermes; SUF=bak-20261009-pre-companion
[ -f "$H/SOUL.md.$SUF" ] && cp -p "$H/SOUL.md.$SUF" "$H/.SOUL.md.rb.$$" && mv -f "$H/.SOUL.md.rb.$$" $H/SOUL.md && echo "SOUL.md restored"
[ -f $H/AGENTS.md ] && mv -f $H/AGENTS.md "$H/AGENTS.md.removed-$(date +%Y%m%d-%H%M)" && echo "AGENTS.md moved aside"
sha256sum $H/SOUL.md
