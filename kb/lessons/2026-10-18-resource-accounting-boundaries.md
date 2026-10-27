# 18/10/2026 — Đối soát tài nguyên VPS cần cùng phạm vi và cửa sổ đo

Loại: resource-audit, storage, cpu, cgroup, shared-dependencies, permission-boundary

- Đo CPU bằng delta cpu.stat của cgroup để gồm process con; ghi rõ 100% = 1 core hay cả VPS. Đo lại sau khi du kết thúc để không gọi I/O audit là tải nền của bot.
- RAM memory.current gồm cache/kernel; không trộn Docker working set đã trừ cache với systemd MemoryCurrent, không coi swap đầy là RSS leak.
- Storage riêng bot, shared runtime/model/dependency, backup và Docker bind mounts phải tách; subdirectory không cộng lần nữa vào parent. Docker logical image/writable bytes không tự bằng du physical.
- df - du readable còn chênh khi thiếu quyền root, metadata hoặc file đã unlink còn mở; phải ghi số dư UNVERIFIED thay vì gán hết cho Docker hoặc “rác”.
- Runtime/rehearsal/cache/backup cũ và NVIDIA dependency chưa là quyền xóa. Inventory read-only khác cleanup GO.

Evidence: tools/openclaw-ops/resource-audit-20261018/REPORT.md và metrics.json.
