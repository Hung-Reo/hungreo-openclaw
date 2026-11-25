# 09/10/2026 — Token Anthropic cũ: gỡ config chưa đủ, plaintext lan khắp state/backup

VERIFIED: tool pdf/image 9.9 tự chọn mọi provider có auth (`resolveImageCandidateRefs`) → `anthropic:manual`
(OAuth gói Claude `sk-ant-oat01`, từ sự cố 05/08) lọt vào chuỗi với `claude-opus-5-5`; chỉ được chặn vì
`plugins.allow` không có `anthropic`. Token thật nằm ở kho auth cấp máy `state/openclaw.sqlite`
`config_machine_state.authProfiles.store`, không phải agent store hay openclaw.json.

Gỡ đúng (09/10, Hưng chạy): `config unset auth.profiles.anthropic:manual` (hot reload) → `models auth logout
anthropic:manual --yes` (gateway tự `models.authRefresh`, không restart) → UAT attempts=1. Script:
`tools/openclaw-ops/anthropic-removal-20261009/`.

Lesson:

- `models auth list` vẫn thấy profile sau khi gỡ config = credential còn ở kho cấp máy; kiểm bằng đếm
  `sk-ant` trong `config_machine_state`, không in giá trị.
- Token từng được dán vào chat/CLI sẽ nằm trong `lcm.db`, transcript, backup sqlite/tar (≥38 file 09/10).
  Xoá tay không hết → biện pháp thật là revoke ở nhà cung cấp; gỡ khỏi runtime để không bị dùng.
- CLI 9.9 từ chối ghi khi state dir khác service đang chạy → không dry-run được trên bản sao; bù bằng
  backup + diff đúng 1 key + auto-rollback.
- Rủi ro "provider tự bật" phải kiểm cả nguồn auth, không chỉ model/fallback list.
- Nguồn lan chính tháng 3/2026: bot chạy `exec`/`read` thẳng vào `auth-profiles.json` → token vào transcript + lcm.db.
  Kiểm secret chỉ bằng đếm/tiền tố/độ dài, không đọc nguyên file credential.
- Token OAuth `sk-ant-oat01` (claude setup-token) KHÔNG hiện trong console API keys; key bị disable trên console
  không chứng minh token này đã chết.
- 09/10 ~15:05 dọn 13 mục plaintext (auth .bak, agent mồ côi `research`, backup rollback) — `20_cleanup_plaintext.sh`.
