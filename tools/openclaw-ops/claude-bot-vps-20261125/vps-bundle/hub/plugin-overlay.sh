#!/usr/bin/env bash
# Bản vá plugin telegram của bot Claude VPS: nguồn chuẩn ở ~/collab-hub/plugin-overlay (chép từ repo).
#   plugin-overlay.sh check   → so cache đang chạy với MANIFEST.sha256; lệch thì exit 1.
#   plugin-overlay.sh apply   → backup file trong cache rồi chép overlay vào, kiểm lại hash. Không restart.
# Chạy bằng user claudebot. Không đọc hay in token.
set -euo pipefail
OVERLAY="${PLUGIN_OVERLAY_DIR:-$HOME/collab-hub/plugin-overlay}"
PIN_VERSION="0.0.7"
CACHE="$HOME/.claude/plugins/cache/claude-plugins-official/telegram/$PIN_VERSION"
INSTALLED="$HOME/.claude/plugins/installed_plugins.json"

fail() { echo "plugin-overlay: $*" >&2; exit 1; }

check() {
  [[ -f "$OVERLAY/MANIFEST.sha256" ]] || fail "thiếu $OVERLAY/MANIFEST.sha256"
  [[ -d "$CACHE" ]] || fail "không thấy cache $CACHE (plugin đã đổi version?)"
  local ver
  ver="$(jq -r '.plugins["telegram@claude-plugins-official"][0].version // "none"' "$INSTALLED" 2>/dev/null || echo none)"
  [[ "$ver" == "$PIN_VERSION" ]] || fail "plugin đang cài version=$ver, overlay chỉ dành cho $PIN_VERSION"
  (cd "$CACHE" && sha256sum --quiet -c "$OVERLAY/MANIFEST.sha256") || fail "cache lệch MANIFEST (bản vá mất hoặc bị sửa tay)"
  echo "plugin-overlay: OK ($PIN_VERSION khớp $(wc -l < "$OVERLAY/MANIFEST.sha256") file)"
}

apply() {
  [[ -d "$CACHE" ]] || fail "không thấy cache $CACHE"
  (cd "$OVERLAY" && sha256sum --quiet -c MANIFEST.sha256) || fail "overlay tự lệch MANIFEST, dừng"
  local bk="$HOME/backups/plugin-overlay-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$bk"
  local f
  while read -r _ f; do
    [[ -e "$CACHE/$f" ]] && cp -p "$CACHE/$f" "$bk/$f"
  done < "$OVERLAY/MANIFEST.sha256"
  echo "plugin-overlay: backup → $bk"
  while read -r _ f; do
    install -m 0644 "$OVERLAY/$f" "$CACHE/$f"
  done < "$OVERLAY/MANIFEST.sha256"
  check
}

case "${1:-}" in
  check) check ;;
  apply) apply ;;
  *) echo "Cách dùng: $0 check|apply" >&2; exit 2 ;;
esac
