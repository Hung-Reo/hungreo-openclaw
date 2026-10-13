# 12/10/2026 — Nemo 9.8 → 10.1: dry-run chỉ kiểm điều kiện, hai lệnh ghi hỏng giữa chừng

Loại: upgrade, nemo, docker, dry-run-gap, plugin-update, config-path, downtime

VERIFIED (`tools/openclaw-ops/nemo-upgrade-10.1-20261012/`, backup `~/backups/nemo-upgrade-10.1-20261012-134648`):

- `20_cutover.sh` dừng Nemo 13:47, backup OK, rồi STOP ở `plugins install @openclaw/codex@2026.10.1 --pin`:
  "plugin already exists … use `openclaw plugins update`". Nemo đã có codex 9.8 từ 07/10 — biết trước nhưng script vẫn dùng `install`.
- `21_resume.sh` (dùng `plugins update`) STOP ở `config set --dry-run`: path `agents.defaults.models.openai/gpt-6.1-sol.agentRuntime.id`
  bị tách ở dấu chấm của "6.1" (`Unrecognized key: "1-sol"`). Lần 07/10 dùng được dạng chấm vì `gpt-6-sol` không có dấu chấm.
  Đúng: `agents.defaults.models["openai/gpt-6.1-sol"].agentRuntime.id` (đã dry-run PASS, không ghi).
- npm 11.19 trong image node:24.21.0 chặn install-scripts (`npm warn install-scripts`) → postinstall của openclaw 10.1 không chạy;
  chạy tay `node scripts/postinstall-bundled-plugins.mjs` trong runtime staging → rc=0. 9.8 stage không gặp.
- Kết quả cuối: CUTOVER_OK 13:55, Nemo offline ~8 phút (13:47→13:55) thay vì ~2–3 phút. UAT: Muse `UAT_DEFAULT_OK`;
  ép `--model openai/gpt-6.1-sol` → `UAT_SOL61_OK`, rollout codex ghi `"model":"gpt-6.1-sol"`, không gọi OpenRouter.
  Config chỉ đổi 3 khoá (fallbacks, entry 6.1 runtime codex, meta.lastTouchedVersion). 16 plugin y hệt 9.8 (anthropic có sẵn, không có credential).

Lesson: dry-run của script upgrade phải CHẠY THỬ từng lệnh ghi bằng chế độ không ghi của chính công cụ trước khi stop dịch vụ
(`plugins update <spec> --dry-run`, `config set --batch-file … --dry-run`), không chỉ kiểm version/RAM/tên container. Khi đã có
plugin cài sẵn → `update`, không `install`. Tên model có dấu chấm → dùng `["…"]` trong path. Sau `npm install` trong container,
kiểm cảnh báo install-scripts và chạy postinstall tay nếu bị chặn. Script dừng giữa chừng phải giữ trạng thái khôi phục được
(backup chụp lúc đã stop, container cũ chưa đổi tên) — điều này đã đúng và giúp chạy tiếp an toàn bằng script resume.
