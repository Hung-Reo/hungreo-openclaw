# VPS resource audit — 18/10/2026

VERIFIED live trên srv1367812. Storage lấy lúc 14:55–14:59 VNT; CPU/RAM lấy cửa sổ sạch **14:58:12–14:59:12 VNT**, sau khi các lượt du đã kết thúc. Chỉ đọc trên VPS; không cleanup/restart/update, không chạy lượt AI hoặc gửi tin.

## Cách đo và phạm vi

- Host 2 vCPU, RAM 8.3266 GB = 7.7547 GiB, swap 2 GiB.
- CPU: chênh usage_usec trong cpu.stat của toàn cgroup, tính cả process con. 100% trong bảng = toàn bộ 2 vCPU; số kiểu top/docker (100%=1 core) lớn gấp đôi.
- RAM: memory.current của cgroup, gồm cả cache/kernel được tính cho cgroup; không phải chỉ RSS tiến trình. Trung bình 7 mẫu cách nhau 10 giây; max trong JSON chỉ là cao nhất của các mẫu này.
- Hungreo gồm gateway và hungreo-suckhoe-handoff.service. VNStock poller được báo riêng, không cộng vào Hermes. Các job VNStock chạy theo lịch chưa hoạt động trong cửa sổ này không nằm trong con số CPU/RAM poller.
- CPU/RAM chỉ đại diện cửa sổ 60 giây này, không phải trung bình 24 giờ hoặc benchmark lúc chạy bản tin/voice/AI.
- Storage dùng du -x -B1 (allocated bytes, không theo symlink); GB = 1,000,000,000 byte. Một lần đo storage, không có trung bình theo thời gian.
- Dung lượng riêng bot bao gồm file lịch sử/runtime/backup nằm bên trong thư mục đó. Backup chung và dependency/runtime dùng chung không phân bổ tùy ý vào từng bot.
- User hung cần mật khẩu sudo. Không đọc được đầy đủ các cây root-owned. Không dùng Docker để vượt qua giới hạn đó.

## Bốn bot chính

| Bot                  | CPU TB, % toàn VPS | RAM TB GiB | Swap cuối GiB | Storage thư mục riêng GB |
| -------------------- | -----------------: | ---------: | ------------: | -----------------------: |
| Hungreo/Rùa          |               4.47 |       1.92 |          0.54 |                     5.67 |
| Sức Khoẻ             |               1.15 |       1.27 |          0.51 |                     2.45 |
| Nemo                 |               1.25 |       1.06 |          0.66 |                     8.23 |
| Hermes               |               0.46 |       0.28 |          0.00 |                     7.00 |
| **Tổng 4 bot**       |           **7.33** |   **4.53** |      **1.71** |                **23.35** |
| **Trung bình / bot** |           **1.83** |   **1.13** |      **0.43** |                 **5.84** |

Storage: Hungreo ~/.openclaw-hungreo; Suckhoe ~/.openclaw-suckhoe; Nemo ~/sandbox-nemo + ~/.openclaw-nemotron (legacy); Hermes ~/.hermes. Các tổng trên chưa bao gồm backup chung, runtime chung, thư viện dùng chung, Docker image/writable layers.

## Ứng dụng phụ và tổng host

| Nhóm           | CPU TB, % toàn VPS |                                   RAM TB MiB | Storage đã xác định                                                                                                                              |
| -------------- | -----------------: | -------------------------------------------: | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| VNStock poller |              0.007 |                                         7.36 | project/work/state khoảng 0.619 GB; chưa tính shared dependency/backup                                                                           |
| n8n            |              0.087 |                                       137.14 | Docker writable layer 2.085 GB; image 1.730 GB; /opt/n8n khoảng 0.161 GB; backup chung 0.184 GB. Docker là số logical, không cộng vào du lần nữa |
| Caddy          |              0.001 |                                        18.35 | writable layer 0.016 GB + image 0.083 GB, một số host files rất nhỏ                                                                              |
| **Toàn VPS**   |           **8.31** | **RAM khả dụng TB 2.98 GiB / tổng 7.75 GiB** | **79.26 GB / 102.89 GB (df 78%)**                                                                                                                |

Host iowait 0.435%, steal 0.209% trong cửa sổ sạch. RAM khả dụng cuối 2.97 GiB; swap gần đầy 2/2 GiB. Các cgroup đo được đều oom_kill=0 từ khi cgroup hiện tại được tạo; không chứng nhận lịch sử trước lần khởi động. Tổng RAM cgroup gồm cache, không nên cộng tiếp toàn bộ page cache của host.

## Đối soát storage không cộng trùng

| Nhóm                                                                                            |         GB |
| ----------------------------------------------------------------------------------------------- | ---------: |
| 4 thư mục bot chính, gồm lịch sử riêng                                                          |     23.352 |
| ~/backups                                                                                       |     12.492 |
| ~/.local, thư viện/công cụ dùng chung                                                           |      9.055 |
| ~/.cache, model/cache dùng chung                                                                |      5.309 |
| Shared OpenClaw runtime generations, 3 thư mục upgrade                                          |      2.900 |
| ~/.openclaw-voice                                                                               |      0.976 |
| VNStock project/work/state đã xác định                                                          |      0.619 |
| hungreo-website                                                                                 |      1.095 |
| Các file/thư mục khác trong home                                                                |      2.076 |
| Hệ thống ngoài home có quyền thống kê, gồm swapfile 2.147 GB                                    |     10.677 |
| **Chênh df - du readable: root-owned/Docker/metadata/file đã unlink còn mở, chưa phân rã được** | **10.705** |
| **Tổng df used**                                                                                | **79.256** |

Home /home/hung = **57.874 GB**; root du readable = **68.551 GB**. Chênh 10.705 GB là số dư đối soát, không phải một thư mục đã đo, không chứng minh tất cả thuộc Docker. Các phép đo không nguyên tử; df cuối 79.2635 GB, chênh khoảng 7 MB do hệ thống vẫn chạy.

## Chi tiết từng bot

### Hungreo/Rùa — 5.671 GB

- agents: 2.191 GB; trong đó main/agent/codex-home 1.101 GB, main/sessions 0.335 GB, main/session-sqlite-import-archive 0.220 GB. Các dòng con đã nằm trong agents.
- tmp/plugin-captures: 1.067 GB.
- npm: 0.621 GB.
- memory: 0.495 GB.
- workspace: 0.489 GB, gồm workspace/tmp 0.286 GB.
- Phần còn lại gồm DB/file trực tiếp ở root profile, state, cache/media và thư mục nhỏ; không mở nội dung DB.

### Sức Khoẻ — 2.449 GB

- tmp/plugin-captures: 0.995 GB.
- npm: 0.615 GB.
- agents: 0.542 GB, gồm codex-home 0.400 GB.
- cache: 0.073 GB; workspace 0.036 GB.
- Phần còn lại gồm DB và dữ liệu khác.

### Nemo — 8.233 GB, gồm sandbox 7.254 + legacy 0.980

Trong sandbox:

- config đang dùng: 0.936 GB; runtime-10.3: 0.643 GB.
- config.failed-10.3-lcm-20261014-211943: 1.341 GB.
- ops-10.3-lcm-20261014: 1.187 GB, gồm rehearsal-config 0.860 GB và stage-home 0.327 GB.
- .npm cache: 1.083 GB.
- runtime-9.8/10.1/10.2: tổng 2.055 GB.
- Các thư mục còn lại nhỏ. Không coi các bản giữ lại là rác hoặc tự cấp phép xóa.
- Docker writable layer serving: 0.089 GB; 4 container Nemo đã dừng tổng 0.298 GB, không nhân bản image chung Node 0.332 GB thành 5 bản.

### Hermes — 6.999 GB

- hermes-agent: 2.310 GB, gồm .git 0.794 GB, venv 0.741 GB, node_modules 0.441 GB.
- tools: 1.722 GB, gồm ffmpeg 0.459 GB, Python 0.420 GB, Chromium 0.381 GB, Node 0.238 GB.
- installs: 1.069 GB.
- backups nội bộ: 0.722 GB.
- node: 0.213 GB; state-snapshots 0.179 GB; cache 0.153 GB.
- Không kết luận unused chỉ từ việc có cả source và installs; chưa audit runtime references.

## Shared dependencies và cache

- ~/.local/lib/python3.12: 7.756 GB. Riêng nvidia **4.592 GB**, torch **1.896 GB**, triton **0.674 GB**; tổng ba nhóm **7.161 GB**. Đây là package dependencies, không suy ra có thể xóa khi VPS không có GPU.
- ~/.cache/whisper **2.322 GB**; huggingface **2.165 GB**; ms-playwright **0.652 GB**; electron **0.115 GB**.
- Dung lượng model trên đĩa khác RAM đang nạp model.

## Backup chung — 12.492 GB

- backups/openclaw (nhóm backup định kỳ): 3.236 GB.
- hungreo-upgrade-pre-9.8-20261003-153601: 1.508 GB.
- openclaw-hungreo-pre99-20261008: 1.493 GB.
- suckhoe-upgrade-pre-9.8-20261003-151311: 0.981 GB.
- Nemo 10.1/10.2/10.3 hai lần backup + pre9.8: tổng khoảng 2.627 GB.
- lcm-111-hungreo: 0.627 GB; lcm-111-suckhoe: 0.112 GB.
- hungreo-embeddings: 0.409 GB; openclaw-suckhoe-pre99: 0.332 GB.
- n8n: 0.184 GB; phần còn lại là nhiều bộ nhỏ.
- Không xác minh restore/retention từng bộ trong audit này.

## Giới hạn và bước tiếp theo

VERIFIED: phần lớn storage nằm trong home (57.87/79.26 GB), với dependency/model, backup và nhiều runtime/rehearsal/history. Không đủ snapshot cùng phương pháp ngày 12/10 để quy chính xác toàn bộ tăng trưởng cho một thay đổi.

UNVERIFIED: chi tiết phần chênh 10.705 GB, file bị xóa còn mở, usage theo 24h, peak cron/voice/AI và thứ gì thực sự có thể xóa.

Nếu cần đối soát hết phần chênh, operator chạy read-only root du cho /var/lib/docker, /var/lib/containerd, /root và kiểm file đã unlink còn mở. Không cần restart hay dọn. Mọi cleanup phải có inventory/reference/retention/rollback riêng và GO target cụ thể; không rerun cleanup đã hoàn thành.

## Git và phạm vi ghi local

Nhánh codex/sync-origin-main-20260222, HEAD abcace43cdb7663f4483509ba7b64c7e0428a9c6. Giữ WIP; chỉ thêm báo cáo/metrics/lesson và entry tracking local cho audit này, không commit/push.
