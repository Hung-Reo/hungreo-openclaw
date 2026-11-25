# Nâng `lossless-claw` (LCM) `1.1.1 → 1.2.0` trên Core `2026.9.33` — Rehearsal + Suckhoe + Hungreo (2026-10-25)

**GO:** Hưng (25/10/2026 13:48 VNT) chọn **Phương án 1**: Giữ nguyên Core `openclaw@2026.9.33` (`extended-stable`), nâng riêng plugin `@martian-engineering/lossless-claw` từ `1.1.1 → 1.2.0` theo lộ trình:

- **Pha 2 (`05_rehearsal_hungreo.sh`):** Rehearsal cô lập (0 downtime Production) trên bản sao DB thật của `hungreo` (`lcm.db` `658 MiB`, `openclaw-agent.sqlite` `538 MiB`) với core `2026.9.33`.
- **Pha 3 (`10_upgrade.sh suckhoe` + `20_verify.sh suckhoe`):** Nâng `lossless-claw` `1.1.1 → 1.2.0` cho `suckhoe` (`:18795`).
- **Pha 4 (`10_upgrade.sh hungreo` + `20_verify.sh hungreo`):** Nâng `lossless-claw` `1.1.1 → 1.2.0` cho `hungreo` (`:18789`).

---

## 1. Kết quả Thực thi (`VERIFIED` 25/10/2026 14:17–14:31 VNT)

| Pha                                   | Hạng mục                                                                                                             | Kết quả (`VERIFIED`)                                                                                                                                                                                                                                                    |
| :------------------------------------ | :------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pha 0 (`00_precheck.sh`)**          | Kiểm hàm delta transcript trên `2026.9.33` + `--dry-run` 2 bot                                                       | `readSessionTranscriptVisibleMessageDelta=true`, `readSessionTranscriptRawDelta=true`; `Would update lossless-claw: 1.1.1 -> 1.2.0`, config hash giữ nguyên                                                                                                             |
| **Pha 2 (`05_rehearsal_hungreo.sh`)** | Clone `hungreo` ra `/tmp/rh-lcm120-hungreo` (`:18799`), migrate `top_cid=1980` (`9,514` msgs) + thử rollback `1.1.1` | `BOOT_120_OK`, lượt migrate + trả lời `31s`, `msgs 52909 -> 52911 (+2)`, `cursors=1`, `gaps=0`, `dup_entry_id=0`, `VmHWM(peak)=1725 MiB`, `VmSwap=0 MiB`, `GATE_ROLLBACK_111_ON_MIGRATED_DB_PASS`, live `hungreo` nguyên vẹn 100%                                       |
| **Pha 3 (`suckhoe`)**                 | `10_upgrade.sh suckhoe` + `20_verify.sh suckhoe`                                                                     | `lossless-claw@1.2.0`, peer `openclaw -> 2026.9.33`, `config changed keys: 0`, `readyz=200` sau `45s`, `rss_MiB=1122`, `swap_MiB=0`, `has_120_tables=True`, `@hungreo_suckhoe_bot` probe `works`. Backup: `/home/hung/backups/lcm-120-suckhoe-20261025-142410` (`111M`) |
| **Pha 4 (`hungreo`)**                 | `10_upgrade.sh hungreo` + `20_verify.sh hungreo`                                                                     | `lossless-claw@1.2.0`, peer `openclaw -> 2026.9.33`, `config changed keys: 0`, `readyz=200` sau `60s`, `rss_MiB=1393`, `swap_MiB=0`, `has_120_tables=True`, `@hungreo_openbot` probe `works`. Backup: `/home/hung/backups/lcm-120-hungreo-20261025-142747` (`701M`)     |

---

## 2. Bộ Script trong `tools/openclaw-ops/lcm-120-20261025/`

- `00_precheck.sh`: Read-only kiểm tra điều kiện tiên quyết + `--dry-run`.
- `05_rehearsal_hungreo.sh`: Rehearsal cô lập trên bản sao dữ liệu `hungreo` tại `/tmp/rh-lcm120-hungreo` (tự dọn sạch trong `trap cleanup EXIT`).
- `10_upgrade.sh <suckhoe|hungreo>`: Stop-first upgrade `1.1.1 → 1.2.0`, backup SQLite (không chép `-shm`), relink peerDependency `openclaw`, kiểm tra diff config và `/readyz`.
- `20_verify.sh <suckhoe|hungreo>`: Read-only verify sau nâng cấp (dùng `oc_profile` chống env pollution).
- `99_rollback.sh <suckhoe|hungreo> <soft|hard> [BACKUP_DIR]`:
  - `soft`: Hạ `lossless-claw` về `1.1.1`, giữ nguyên `lcm.db` hiện tại (đã chứng minh tương thích ngược ở bước `[e]` của `05_rehearsal_hungreo.sh`).
  - `hard`: Khôi phục toàn bộ `openclaw.json`, `state/openclaw.sqlite`, `lcm.db`, và thư mục npm `1.1.1` từ `BACKUP_DIR`.

---

## 3. Soak read-only `30_soak.sh` (Claude Code, 25/10 20:30)

`ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 30_soak.sh` — chỉ đọc (sqlite `mode=ro`, không mở backup có `-wal`), in PASS/WARN/FAIL + `KẾT`. Kiểm: active/readyz/NRestarts, có restart sau mốc nâng không, RSS/HWM/swap, rss_threshold/ngày, capability_error, lỗi lcm, session-rebound, installedIndex 1.2.0, quick_check, dup_entry_id, msgs mới, cursors, gaps (theo source), hạn OAuth, cron 19:30 Suckhoe.

- Cron 19:30 Suckhoe gửi thẳng qua `message.action`, **không qua agent/LCM** (cả trên 1.1.1) → không dùng làm mốc migrate. Gate LCM tính theo inbound.
- Lần chạy 20:30: FAIL 0, WARN 1 (OAuth Suckhoe quá hạn 17:26, chưa có lượt model nào để refresh). Rùa: cursor 1, +122 msgs, 8 gaps `generation_mismatch` (5.457 entry, conv DM chính) — rehearsal báo 0, chưa giải thích.
