#!/bin/bash
# 11 — HƯNG CHẠY, TƯƠNG TÁC (ssh -t). Đăng nhập ChatGPT/Codex RIÊNG cho Nemo (không chép token của Hungreo/Suckhoe).
# Màn hình sẽ hiện link + mã: mở link trên điện thoại/máy, đăng nhập đúng tài khoản subscription, nhập mã.
set -euo pipefail
S=/home/hung/sandbox-nemo
docker run --rm -it --user 1001:1001 --env-file "$S/nemo.env" \
  -v "$S/.npm:/sandbox/.npm" -v "$S/runtime-9.8:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" \
  node:24.21.0-bookworm-slim node /sandbox/runtime/node_modules/openclaw/dist/entry.js \
  models auth login --provider openai --device-code
echo "== auth list (không in token)"
docker run --rm --user 1001:1001 --env-file "$S/nemo.env" \
  -v "$S/.npm:/sandbox/.npm" -v "$S/runtime-9.8:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" \
  node:24.21.0-bookworm-slim node /sandbox/runtime/node_modules/openclaw/dist/entry.js models auth list 2>&1 |
  sed -E 's/(ey[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]+)/<R>/g' | grep -E "Profiles|openai|anthropic|openrouter|none"
echo "OK 11 — chạy tiếp 12_config_start.sh"
