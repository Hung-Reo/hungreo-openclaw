#!/bin/bash
# 99 — trả AGENTS.md + SOUL.md Hungreo về bản trước đề xuất 09/10. Sau đó /new trong DM Rùa.
set -euo pipefail
W=/home/hung/.openclaw-hungreo/workspace; SUF=bak-20261009-pre-admin-suckhoe
for n in AGENTS.md SOUL.md; do [ -f "$W/$n.$SUF" ] && cp -p "$W/$n.$SUF" "$W/.$n.rb.$$" && mv -f "$W/.$n.rb.$$" "$W/$n" && echo "$n restored"; done
sha256sum "$W/AGENTS.md" "$W/SOUL.md"
