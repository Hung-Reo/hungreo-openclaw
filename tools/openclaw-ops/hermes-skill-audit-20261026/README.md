# Audit Hermes tự sửa skill (curator ledger) — 26/10/2026

**GO:** Hưng 26/10 "soạn script read-only audit ledger curator Hermes (7 ngày, diff, gắn cờ luật mới về cài đặt/exec/gửi tin/credential/URL), chạy thử và báo".

## Vì sao

Hermes có background review + curator tự ghi skill của chính nó (`💾 Self-improvement review: … patched`). Ledger `~/.hermes/skills/.curator_ledger.jsonl` có 220 entry (tháng 10: vnstock 72, hermes-agent 22), không ai duyệt. Rủi ro: agent tự viết luật cho mình; nội dung đọc từ web có thể thành chỉ dẫn bền trong skill. Lưới an toàn có sẵn: mỗi entry có hash trước/sau + blob ở `~/.hermes/.curator_backups/blobs/`, hoàn tác bằng `hermes curator rollback <id>`.

## Dùng

```
ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 00_audit.sh       # 7 ngày
ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s 30' < 00_audit.sh    # 30 ngày
```

Chỉ đọc: không ghi file, không gọi CLI Hermes. In dòng **thêm mới** có cờ (cắt 200 ký tự, ẩn secret/email/số dài):

| Mức  | Cờ                                      | Ý nghĩa                                                                                                            |
| ---- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| HIGH | `noi_quyen`                             | bỏ hỏi / tự động làm / bypass / override (không có phủ định)                                                       |
| HIGH | `credential`, `url`                     | nhắc token/key/.env/transcript; URL ngoài allowlist                                                                |
| MED  | `cai_dat`, `exec`, `gui_tin`, `chi_phi` | lệnh cài, systemctl/cron/restart, gửi tin, phí/model trả tiền                                                      |
| SIET | (mọi cờ trừ url/chi_phi)                | dòng có phủ định ("do not", "không được", "phải hỏi") = Hermes tự siết luật — vẫn liệt kê vì là luật agent tự viết |

Toàn vẹn: file hiện tại ≠ `after` cuối trong ledger (`drift`), file skill đổi mà không có entry (`ngoài_ledger`; trừ file đổi ±15 phút quanh `hermes update`).

## Lần chạy đầu 26/10 11:10 (7 ngày) — xem báo cáo trong SESSION_HANDOVER

33 entry, HIGH 4, drift 0, ngoài ledger 0, thiếu blob 0.

## Giới hạn

- Regex thô → có nhiễu; đọc dòng, đừng chỉ nhìn số.
- Không bắt được thay đổi đã bị GC blob (báo `thiếu_blob`), hay chỉ dẫn diễn đạt khéo không chứa từ khoá.
- Không xem memory (`MEMORY.md`/`USER.md`) — chỉ skill.
