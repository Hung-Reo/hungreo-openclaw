#!/usr/bin/env bash
# Isolated runner for the dry-run copy. NET=bridge only for npm plugin downloads.
net=${NET:-none}; offline=true; [[ $net == bridge ]] && offline=false
exec docker run --rm --network "$net" --user 1001:1001 --memory 3g --cpus 1.5 --pids-limit 512 \
  -v /home/hung/claude-dryrun-117-20261124/chome:/home/hung -v /home/hung/claude-dryrun-117-20261124/ctmp:/tmp \
  -v /home/hung/claude-dryrun-117-20261124/profile:/home/hung/.openclaw-hungreo \
  -v /home/hung/openclaw-upgrade-hungreo-20261123-117/runtime:/home/hung/openclaw-upgrade-hungreo-20261123-117/runtime:ro \
  -v /home/hung/openclaw-upgrade-hungreo-20261123-117/npm-cache:/home/hung/openclaw-upgrade-hungreo-20261123-117/npm-cache \
  -v /home/hung/openclaw-node-24.22.1:/home/hung/openclaw-node-24.22.1:ro \
  -v /home/hung/claude-dryrun-117-20261124/ops:/home/hung/ops:ro -v /home/hung/claude-dryrun-117-20261124/out:/home/hung/out \
  -e NODE_OPTIONS=--max-old-space-size=2048 -e NPM_OFFLINE=$offline -e HOME=/home/hung -e TZ=Asia/Ho_Chi_Minh --name claude-dryrun-117 \
  node:24.21.0-bookworm-slim bash /home/hung/ops/inner.sh "$@"
