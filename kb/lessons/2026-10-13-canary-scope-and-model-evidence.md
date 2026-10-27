# 13/10/2026 — Canary không đại diện plugin chưa bật; bảng model cần đối soát live

Loại: canary, upgrade, lcm, evidence-scope, model-doc-drift, rss, uat

VERIFIED: audit read-only 15:08–15:12 VNT xác nhận Nemo core 10.2 không dùng LCM; Hungreo/Suckhoe core 9.9 + LCM 1.1.0. Bảng Antigravity/LOCAL_CONTEXT 12:30 ghi primary Sol 6 và dễ nhầm sub-agent Luna là fallback, trong khi config live/startup log đều Sol 6.1, main fallback Muse. Nemo running/readyz=200, chưa restart/OOM nhưng có 42 cảnh báo RSS threshold, nên không dùng từ “an toàn tuyệt đối”.

Rules:

- Canary chứng minh phần code/workload thực sự chạy. Nemo không bật LCM → không chứng minh core 10.2 + LCM 1.1.1; cần rehearsal ingest/compact/recall/tool history/grants/restart trên môi trường cách ly trước Production GO.
- Phân biệt configured primary, main fallback, sub-agent model và model thực của lượt. Đối soát config + startup + execution trace phù hợp; không tin model tự nhận hay snapshot cũ.
- Ép `--model` là route smoke, chưa là automatic failover test. HTTP 200/PID/RestartCount/backup checksum chỉ là từng lớp bằng chứng; không thay user UAT/soak/restore rehearsal.
- RSS threshold warning khác cgroup OOM; theo dõi mẫu theo tải trước khi kết luận leak hoặc tăng cap. 48–72h là checkpoint, không tự cấp GO.

Chi tiết/bằng chứng/next: SESSION_HANDOVER.md entry 2026-10-13 15:12.
