# Tăng swap VPS 2G → 4G (2026-10-18)

**Vì sao:** swap 1828–1973/2047 MiB, đầy lại chỉ 22h sau reboot 17/10. Hermes lúc nâng cấp từng vọt lên 3,0–3,1 GiB. Còn khoảng 3 GiB RAM available, nhưng gần như hết đệm swap, nên một đợt tăng RAM đột ngột có thể gây OOM cho 3 bot.

**Hiện trạng (VERIFIED 14:35–14:40):** `vmstat` có si/so ≈ 0, tức swap đang chứa trang lạnh, máy không thrash. ext4, disk trống 23G, swappiness 60. User `hung` cần mật khẩu sudo.

**Cách làm:** thêm `/swapfile2` 2 GiB bên cạnh `/swapfile` cũ, không resize file cũ (resize phải swapoff 1,8G đang dùng → rủi ro). File tạo bằng `dd`, không dùng `fallocate` (theo khuyến nghị của man mkswap), quyền 600 root. Dòng fstab có `nofail` để file mất thì máy vẫn boot. Kiểm fstab mới bằng `findmnt --verify --tab-file` trước khi ghi. Không đụng service nào, không restart.

**Chi phí / rủi ro:** disk 23G → 21G. Lệnh `dd` ghi 2 GiB trong vài giây. Nếu có process rò RAM, máy sẽ chậm dần thêm khoảng 2G nữa rồi mới bị OOM → theo dõi `VmSwap` từng process sau khi tăng.

## Các bước (Terminal Mac)

```bash
cd ~/Development/hungreo-openclaw/tools/openclaw-ops/swap-4g-20261018
ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'mkdir -p /home/hung/ops-swap'
scp -i ~/.ssh/hostinger_kvm2 10_swap.sh 99_rollback.sh hung@72.61.123.33:/home/hung/ops-swap/
ssh -t -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/ops-swap/10_swap.sh check'
ssh -t -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/ops-swap/10_swap.sh apply'
```

Kỳ vọng ở `apply`: Hưng gõ mật khẩu sudo → `BACKUP_FSTAB=/etc/fstab.bak-…-pre-swapfile2` → `/proc/swaps` có 2 dòng → `OK 10 — swap tổng 4095 MiB`.

Rollback (nếu cần): `ssh -t … 'bash /home/hung/ops-swap/99_rollback.sh <BACKUP_FSTAB>'`. Script swapoff `/swapfile2` (chỉ chạy khi RAM available > phần đang dùng + 1 GiB), trả fstab về bản backup, rồi xoá `/swapfile2`.

Đã kiểm: chế độ `check` chạy trên VPS 2 lần, PASS (`findmnt` 0 lỗi). Review fresh-context (opus) không có lỗi chặn; đã áp 2 lỗi phụ (fstab thiếu newline cuối, dd thay fallocate) và gợi ý `nofail`.

**Còn có thể sai:** nhánh `apply` chưa chạy thật. Sau reboot, systemd có thể đổi thứ tự priority giữa 2 swap (cùng một đĩa nên không đáng kể). Thêm swap không chữa nguyên nhân RSS Hungreo/Nemo tăng (vẫn UNVERIFIED); việc này chỉ thêm khoảng đệm.
