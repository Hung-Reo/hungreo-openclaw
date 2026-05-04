#!/bin/bash
# Session-start hook: set up VPS SSH key from environment variable.
# Silently skips if VPS_SSH_KEY is not set.

set -euo pipefail

if [ -z "${VPS_SSH_KEY:-}" ]; then
  exit 0
fi

mkdir -p ~/.ssh
printf '%s\n' "$VPS_SSH_KEY" > ~/.ssh/hostinger_kvm2
chmod 600 ~/.ssh/hostinger_kvm2
