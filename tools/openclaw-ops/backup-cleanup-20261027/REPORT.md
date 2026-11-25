# Precheck hoàn tất — 27/10/2026 10:52 VNT

**COMPLETED / VERIFIED27/10/2026 10:59:52 VNT.** Hưng đã GO riêng bằng phản hồi chọn “GO xóa đúng4backup ngày18/10” + “pls go!”. Đã xóa đúng4paths, không còn original/pending; không xóa thêm. Các phần precheck bên dưới là evidence trước khi thực thi.

## Kết quả thực thi sau GO

- Recheck local/remote source đúng reviewed anchors, staging0700/files0600; backup/restore/financebackup inactive.
- Audit mới ngay trước execute: PASS,4targets740,741,120allocated bytes,10bộ giữ/66checksums PASS; root scan153processes/13namespaces,0refs/0mountmatches/0denials.
- Execute dùng đúng approved spec SHA256 trong report, thành công exit0. Guards trước/sau rename từng target PASS; full progress4/4; không có original/pending còn lại.
- `df used` trước82,153,451,520bytes → sau81,414,307,840bytes: **net thực thu hồi739,143,680bytes =0.739GB / khoảng0.688GiB**. Allocated4targets740,741,120bytes là số khác; không thay net df bằng estimate.
- 10bộ retained recovery và66manifest checksums vẫn PASS sau deletion. Không có full boot restore mới trong lượt này.
- H/S/Nemo readyz200; H PID2749236/restarts0, S PID2940374/restarts0, Hermes PID2905446/restarts1/active giữ nguyên. Config hashes/runtime/protectedcontainers/timers baseline không đổi. Không restart, gửi tin, đổi model/auth/cron/retention.
- `df -h` sau cùng:96G total,76G used,20G available,80% (hiển thị làm tròn nên phần trăm chưa giảm).
- Metadata `du` readable sau cleanup10,647,183,360bytes (~9.92GiB);2thư mục finance ngoài scope không có quyền đọc nên đây không phải chứng nhận tổng root đầy đủ. Sốdu trước10.606GiB cũng là phạm vi đọc được. Net reclaim lấy từdf, không dựa vào phần thiếu quyền này; không đọc/gỡ quyền/xóa thư mụcfinance.
- [result.json](result.json) là bản metadata đã lọc từ kết quả private trên VPS; không có rawconfig/DB/secrets.
- Scope đã hoàn tất; không chạy lạiapply/GOcũ hoặc tự mở sangRAM/cache/backup khác.

## Live audit VERIFIED

- Host `srv1367812`; staging mới owner1001 (`hung`), mode0700, file exclusive0600: `/home/hung/.openclaw-ops/backup-cleanup-20261027-ulozepz_`.
- Audit timestamp `2026-10-27T10:52:22.164795+07:00`.
- 10bộ retained recovery, **66/66 thành phần có SHA256 đúng**, required coverage PASS. Không đồng nhất kết quả này với full boot restore. Daily27/10 archive/config/6critical DB integrity đã kiểm riêng ở [report trước](../backup-review-20261027/REPORT.md).
- Root process/mount scan **156processes / 13mount namespaces**, **matches0 / mountMatches0 / permissionDenials0**. Lượt probe trước đó154processes cũng0/0/0. Điểm thiếu quyền52 ở lượt user-level đã được giải quyết bằng helper metadata có giới hạn.
- Docker mount overlap0, host mount guards PASS, direct-string active script/unit references0. Không chạy script prune cũ.
- Baseline sau audit so với trước: không đổi. H/S core9.34, Nemo10.5; H PID2749236/restarts0, S PID2940374/restarts0, Hermes PID2905446/restarts1. H/S/Nemo readyz200, protected containers/mounts giữ nguyên.
- Các timer backup/restore-check/healthcheck active; official backup/restore units inactive trong audit, finance backup inactive khi đối chiếu cuối. Không chỉnh timer/service/config.
- Không thêm container tồn tại ngoài baseline sau helper. Root helper dùng image có sẵn, không pull/network, không mount backup/hostroot, chỉ đọc metadata.

## Exact 4 paths đề nghị duyệt

Path dưới `/home/hung/backups`:

| Directory                                 | Allocated bytes |                          Inode |
| ----------------------------------------- | --------------: | -----------------------------: |
| `openclaw-hungreo-pre933-20261018-154744` |      41,005,056 |                         626335 |
| `openclaw-suckhoe-pre933-20261018-154622` |      19,668,992 |                         625692 |
| `post933-cleanup-hungreo-20261018-164201` |     350,892,032 |                         887229 |
| `post933-cleanup-suckhoe-20261018-163847` |     329,175,040 |                         887236 |
| Tổng                                      | **740,741,120** | **0.690GiB / 0.741GB dự kiến** |

Fingerprint audit có hash nội dung/metadata + dev/inode; kiểm lại sát lúc chạy. Đây là retirement snapshot maintenance lịch sử18/10, không tuyên bố file trùng byte. Xóa làm mất đúng các snapshot này; không có undo trực tiếp. Giữ current/core rollback9.33, plugin/Node/Nemo recovery và các nhóm khác.

## Review và kiểm thử

Fresh-context reviewer role `reviewer` (`gpt-6.1-sol`, high) đã review code, yêu cầu sửa2P1 và xác nhận bản cuối **READY FOR USER GO về static implementation**, không cấp quyền execute. Reviewer không tự SSH; live evidence do agent chính lấy.

Hai lỗi đã sửa trước audit:

1. Bind source/alias phải được phát hiện qua filesystem coordinates và các mount namespace, không chỉ mountpoint.
2. Verify không được báo thành công nếu thiếu progress hoặc còn original/pending. Root guard chạy lại sau rename; compiled allowlist cũng áp vào audit pins.

- Parent:16Python guard tests PASS;10JS helper scenarios PASS; Bash syntax PASS.
- Reviewer độc lập:10JS scenarios PASS và5Python mock checks PASS.
- Các test dùng temp/mocks local, không xóa dữ liệu VPS.

Anchors final:

```text
cleanup.py   c0ab090d043e417c0043e49e094f418532617346ae9b4af187d05d2465e7998e
root_refs.js 1a80e0833d035fd31b0dc521920de56cab66a78bb1d09ae610440d55adaf7ab1
targets.json f8413e1d1d1fd2bc1d17eb914ded2c234421464b68cf69b9b813079ee5ab8fd2
audit.json   9b2f7d7c3ca054b47003a4722a967a2160fa5e79da61509e1d360c6e7741f1c1
```

Audit raw nằm private trên VPS, không đưa toàn bộ lên repo. Không coi fingerprint/audit là approval vô thời hạn: execute cần audit không quá900giây, source/spec đúng anchor, baseline và mọi guard vẫn PASS. Quá hạn thì audit lại sau GO. Nếu có bảo trì song song hoặc bất kỳ gate đổi/thiếu quyền, dừng trước deletion. Nếu lỗi sau rename, giữ exactpending để reconcile, không retry mù.

## Cơ chế cũ gây tích backup

`~/bin/openclaw-prune-upgrade-backups.sh` mặc định dry-run, KEEP2, nhưng chỉ nhận family `openclaw-upgrade-*` và `lcm-*upgrade-*`. Những tênpre933/post933/pre934/Node/LCM120 hiện dùng không thuộc các family này. Chỉ ghi nhận nguyên nhân; không mở rộng glob hoặc thay retention producer trong đợt này.

Điểm vào sử dụng lại: [danh mục](../BACKUP_CATALOG.md), [README gói](README.md). Gói này không dùng lại GO/targets18/10.
