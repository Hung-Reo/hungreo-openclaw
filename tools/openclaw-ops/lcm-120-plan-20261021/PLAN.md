# Plan nâng cấp bot VPS — từ 21/10/2026 (Claude Code, chưa GO)

## Quyết định đề xuất

| Thành phần           | Hiện tại (VERIFIED 21/10 06:54)                                                | Đề xuất                                                            |
| -------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| Core Hungreo/Suckhoe | 2026.9.33 (`extended-stable`), runtime `openclaw-upgrade-20261018-933`         | **Giữ.** Không lên 10.5                                            |
| Core Nemo            | 2026.10.4, Up 2 ngày, 0 restart, 0 OOM                                         | **Giữ** cho soak 10.4. Không chồng thêm 10.5 cùng lúc với LCM      |
| LCM (cả 3 bot)       | 1.1.1                                                                          | **Lên 1.2.0 theo pha** (Nemo → rehearsal 9.33 → Suckhoe → Hungreo) |
| Hermes               | v0.22.2                                                                        | Giữ; job nghiệm thu cron chạy tới 25/10                            |
| Swap                 | 4 GiB (đã tăng 18/10), dùng 2,87 GiB; `/swapfile` đầy, `/swapfile2` dùng 0,84G | Theo dõi; đây là ràng buộc RAM cho rehearsal                       |

**Vì sao LCM trước core:** 1.2.0 thay cách ingest. Bản cũ đọc và đối chiếu lại toàn bộ transcript mỗi lượt (0,3–28,5 s với phiên lớn). Bản mới chỉ đọc phần transcript mới (theo release note). Hungreo có DB lớn nhất (≈50k messages) và vẫn **263 cảnh báo rss_threshold/24h trên 9.33**, tức 9.33 không chữa được. Đây là ứng viên hợp lý nhất cho RSS/độ trễ, nhưng **chưa chứng minh** (ASSUMPTION), nên phải đo trước và sau.

**Vì sao không lên core 10.5:** `extended-stable` vẫn là 9.33. #178804 (P1, OPEN 20/10): process codex app-server tích tụ trên 10.5 khi bật `sessionCatalog`. H/S đang tắt sessionCatalog và số codex app-server ít, ổn định (VERIFIED), nên chưa áp vào máy này, nhưng không có lý do kéo rủi ro đó về. #172605 (10.3 treo gateway khi agent chạy) vẫn OPEN.

## Rủi ro LCM 1.2.0 cần chặn

- **Mới ra 21/10 03:42 VN**, compat `tested: 2026.9.4, 2026.9.5`, chưa test với 9.33 hay 10.4. → Chờ ≥72h xem issue tracker / bản vá 1.2.x.
- **Migration một lần lúc dùng lần đầu:** chuyển sang cursor mode và resync hàng loạt. DB Hungreo lớn, nên lượt đầu có thể nặng CPU/RAM trong khi swap đã 70% → phải đo trong rehearsal.
- **Rollback:** release ghi `rollback-version: 1.1.1`, nhưng 1.1.1 chạy trên DB đã migrate (bảng mới `conversation_transcript_gaps`, entry id) thì chưa kiểm (UNVERIFIED) → phải thử trong rehearsal.
- Trùng lặp lịch sử khi resync: release nói restamp chứ không nhập trùng; phải đếm messages trước/sau.

## Quyết định Hưng 21/10

1. Core: **Nemo lên 10.5** (bộ script `nemo-upgrade-10.5-20261021/`), giữ H/S 9.33.
2. LCM 1.2.0: **proceed theo pha dưới**, mốc sớm nhất ≥24/10. Nemo chỉ nhận LCM 1.2.0 khi soak 10.5 đã đủ ≥48h, để không đổi 2 biến cùng lúc.

Lịch dự kiến (dời nếu gate chưa đạt): 21/10 Nemo 10.5 → 23/10 hết soak 48h → 24/10 kiểm issue tracker LCM, soạn rehearsal → 24–25/10 Nemo LCM 1.2.0 + rehearsal clone Hungreo → 25/10 kiểm OAuth Suckhoe tự refresh (17:26) + restore-check 03:00 → 26/10 Suckhoe → 27/10 Hungreo.

**Cập nhật 21/10 21:15:** Nemo đã lên core 10.5 (20:42, UAT PASS). Hưng chọn PA1: Nemo lên LCM 1.2.0 **tối 22/10** sau `30_verify` +24h (sớm hơn mốc 48h/24-10 cũ — Hưng quyết, vì Nemo là canary ít dùng). Script: `tools/openclaw-ops/nemo-lcm-120-20261022/`. Mốc ≥24/10 + rehearsal bản sao Rùa vẫn giữ cho Suckhoe/Hungreo.

**Cập nhật 22/10 06:45:** Nemo đã lên LCM 1.2.0 (UAT PASS, migrate `legacy-migration` OK, không re-import). Pha 1 (canary Nemo) xong. Tiếp: Pha 2 rehearsal bản sao Rùa ≥24/10.

## Các pha

| Pha                     | Việc                                                                                                                                                                                                                                                                                   | Ai                     | Gate để sang pha sau                                                       |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | -------------------------------------------------------------------------- |
| 0 (read-only, 21–23/10) | Baseline Hungreo/Suckhoe/Nemo: rss_threshold/ngày, RSS, thời gian lượt (log assemble/LCM nếu có), số messages/summaries, quick_check. Đọc diff v1.1.1…v1.2.0 (`src/db/migration.ts`) xem rollback 1.1.1 có chạy trên schema mới. Kiểm 9.33 có visible-delta reader. Theo dõi issue LCM | Claude                 | Không có regression P1 cho 1.2.0 tới ≥24/10; migration chỉ thêm, không phá |
| 1 (canary, ~24/10, phụ) | Nemo: `plugins update …@1.2.0` (dry-run trước). Pha 0 cho thấy Nemo chỉ có 126 msgs và 0 summary → chỉ chứng minh plugin load được và ingest tin mới; **không thay được Pha 2**                                                                                                        | Hưng chạy, Claude soạn | 24h: 0 lỗi lossless, ingest tin mới đủ                                     |
| 2 (rehearsal, 24–25/10) | Clone Hungreo từ backup daily vào profile cách ly (transport/cron OFF, không port public), core 9.33. Đo migration lần đầu (thời gian, RAM), ingest/compact/recall, `/lcm doctor` gaps, đếm duplicates, restart, **rollback 1.1.1 trên DB đã migrate**                                 | Hưng chạy, Claude soạn | PASS hết; RAM đỉnh khi migrate < phần còn trống                            |
| 3 (Prod 1, ~26/10)      | Suckhoe (chờ OAuth tự refresh sau 25/10 17:26 xong), ngoài khung 19:30 và 04:10–07:00                                                                                                                                                                                                  | Hưng                   | UAT Telegram + soak 24h qua nhắc thuốc và tĩnh nguyện                      |
| 4 (Prod 2, ~27/10)      | Hungreo, ngoài 05:35–07:20 và 16:35–16:55                                                                                                                                                                                                                                              | Hưng                   | UAT 5 lượt; so baseline rss_threshold/RSS sau 48h                          |

Mỗi pha Prod dùng lại khung `tools/openclaw-ops/lcm-111-20261015/` (00 precheck + dry-run thật → 10 stop-first, backup không chép `-shm`, update, readback → 20 verify → 99 soft/hard), kèm review fresh-context (opus) trước khi giao.

## Không đổi

Model/auth/fallback, core version, Hermes, `nativeSkills=false` của Rùa, retention backup.

## Cần biết thêm (VERIFIED 21/10)

- Backup daily 02:15 (H/S) có `lcm.db`, `openclaw-agent.sqlite`, `state/openclaw.sqlite` và `openclaw.json` trong tgz; SHA256SUMS có, retention 2. **Chưa thử restore**; restore-check kế tiếp 25/10 03:00.
- OAuth: Hungreo 30/10, Nemo 27/10, **Suckhoe 25/10 17:26** (đã tự refresh các lần trước).
- systemd H/S có 4–7 drop-in. `override.conf` vẫn ghi `OPENCLAW_SERVICE_VERSION=2026.9.8` và ExecStart cũ, nhưng drop-in sau cùng (`zzzzz-upgrade-99.conf`) mới quyết định runtime 9.33 → **lần nâng core sau phải sửa drop-in cuối, không phải override.conf** (runbook trong CLAUDE.md đang ghi override.conf).
- Service H/S vẫn chạy kèm patch cục bộ từ 03/10 (`live-gates/patch-binding-loader-hook.mjs`, ExecStartPre `verify-command-registry-98.mjs`, test `plugin-binding-decline-fallback`). Rehearsal LCM phải chạy với đúng các patch này.
- Nemo không có trong backup daily; rollback hiện chỉ là container 10.3 và backup 18/10.
