# 06/11/2026 — Hermes: vấn đề là đi vòng qua Mac, không phải thiếu quyền

Loại: hermes, agents-md, alignment, scope, upgrade, restart

## Catch-up nhanh

- VERIFIED: `~/.hermes/AGENTS.md` do Claude Code soạn, Hưng GO và tự chạy 09/10; không đổi tới 06/11. Sau GO, Hermes vẫn tự chạy cron và restart.
- Claude Code đề xuất "nới 4 quyền" theo kiểu làm trước, báo sau. Đề xuất này ngược ý Hưng: Hưng thích Hermes hỏi, plan, chờ duyệt rồi mới làm.
- Hưng quyết 06/11: việc trong `~/.hermes` thì Hermes hỏi, plan, chờ GO rồi tự làm. Việc lớn thì chủ động tư vấn nhờ Claude Code/Codex kèm lý do. Nâng cấp Hermes: sau GO Hermes tự chạy, rồi nhờ Hưng bấm `/restart` và đề xuất cách test.
- Quyết định này thay kết luận "Claude soạn, Hưng chạy" ở lesson 11/10 và 25/10 cho nâng cấp core. Cài plugin ngoài vẫn tư vấn giao Claude Code.

## Bài học

1. **Hỏi lịch sử trước khi đề xuất đổi quyền.** Đọc backup, handover và hành vi thật cho thấy phần cần sửa nhỏ hơn nhiều.
2. **"Tự chủ" không có nghĩa bỏ duyệt.** Tách hai trục: ai thực hiện và có phải xin phép không.
3. **Ví dụ của chủ có sức nặng hơn suy luận của agent.** Ví dụ nâng cấp rồi bấm `/restart` đã sửa ngoại lệ Claude đề xuất.

## Giới hạn còn lại

- Hermes 0.22.5 có thể để gateway dừng sau `hermes update` (issue NousResearch/hermes-agent#143478, còn mở 06/11); khi đó cần SSH.
- Luật chỉ là văn bản; DM cũ phải `/new` mới nạp. Chưa quan sát Hermes làm theo luật mới.
