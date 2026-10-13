# 09/10/2026 — Tĩnh nguyện: excerpt nguyên văn nhưng quá số từ

VERIFIED:4slot05:45/06:00/06:20/06:45 có nguồnRSS923chars và outputJSON, nhưng cùng quote27whitespace tokens;
validator giới hạn8–25 nên exit76. Đầu ra/modelgpt-6-sol trước upgrade06:57; không quy lỗi cho9.9/6.1.

Lesson: đọc đúng session bằng created_at index + session PK, giải nén event_zstd bounded nếu cần;
không FTS/full scan DB live. Nguyên văn nguồn không đồng nghĩa đúng độ dài. Tiếng Việt cần prompt nói rõ
đếm theo khoảng trắng. Chỉ log error class che mất rule; reason phải là whitelist do validator sở hữu.
Catch-up không sửa được cùng lựa chọn lỗi lặp lại; retry có feedback phải bounded và mọi output vẫn validate.
Không nới grounding/quote/voice validator hoặc gửi bù sau07:00.

Localcandidate:50testsPASS, unchangedvalidatorAST, no-network/no-subprocess mainreplay.
Production chưaGO; fresh6.1generation và scheduleddelivery10/10UNVERIFIED.
Evidence: `tools/openclaw-ops/devotional-validation-20261009/README.md`, fixtures, candidate.patch, test-results.txt.
