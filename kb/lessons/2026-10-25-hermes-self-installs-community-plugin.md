# 25/10/2026 — Hermes tự cài plugin community khi được nhờ "plugin chính thống", rồi kẹt vì không tự restart được

Loại: hermes, plugin, provenance, self-modification, agent-scope, verify-before-report

VERIFIED (`tools/openclaw-ops/hermes-lcmx-remove-20261025/`):

- Hưng nhờ Hermes "cài plug-in chính thống (100% safe), cộng đồng khuyến nghị" để có LCM. Hermes tự update core v0.22.2→v0.22.5 (không backup riêng), cài `hermes-lcm-x` (catalog **tier: community**, maintainer bên thứ ba; commit cài 77b2b4f khác pin catalog 709099b3), bật `context.engine: lcm-x`, rồi thử tự restart gateway → Hermes chặn ("cannot restart … from inside the gateway process") → task kéo dài, lượt model 1,6 MB phải retry.
- Claude đọc nhầm `.update_exit_code` (kích thước 1 byte ≠ giá trị 1) → báo sai "update dở dang"; `update.log` cho thấy update hoàn tất. Đính chính trong phiên.
- Gỡ bằng CLI chính thống, rehearsal trên bản sao `HERMES_HOME` (ngoài `profiles/`, không chép socket) + hash live trước/sau; thứ tự unset engine TRƯỚC disable để reload không trỏ engine đã mất.

Lesson:

- "Chính thống/official" phải kiểm `tier` trong catalog + repo/maintainer + SHA so với pin, không tin lời agent. Agent không được tự nâng cấp/cài plugin rồi tự restart chính nó (đã có từ 11/10) — giao việc cài cho Claude soạn script, Hưng chạy.
- Đọc giá trị file trạng thái bằng `cat`, đừng suy từ kích thước.
- CLI không có --dry-run → rehearsal trên bản sao home + kiểm hash live là bằng chứng không đụng live.
