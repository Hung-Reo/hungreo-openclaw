# Ghi Chú Local Của Hưng

Tài liệu này là ghi chú vận hành local.
Giữ nguyên `README.md` gốc của upstream làm nguồn chuẩn.

## Bot Đang Chạy

- Bot chính: `Rùa` (general).
- Bot phụ: `Dr Rùa` (health) qua stack `openclaw-suckhoe`.
- Family KB local: `memory/family/*.md`.

## Nhánh Chính

- Nhánh làm việc hiện tại: `main`.
- Remote: `origin https://github.com/openclaw/openclaw.git`.
- Khi sync upstream, luôn kiểm tra lệch commit với `origin/main` trước khi nâng cấp.

## Runbook Nhanh (Dr Rùa)

1. Restart gateway:
   `docker compose --env-file /Users/hungdinh/Development/hungreo-openclaw/.env.suckhoe -p openclaw-suckhoe restart openclaw-gateway`
2. Xem log gần nhất:
   `docker logs --since 10m --tail 200 openclaw-suckhoe-openclaw-gateway-1`
3. Kiểm tra model:
   `docker logs --tail 80 openclaw-suckhoe-openclaw-gateway-1 | grep "agent model"`

## An Toàn Dữ Liệu

- Không commit hồ sơ sức khỏe cá nhân.
- Đã ignore: `memory/family/*.md`.
- Chỉ giữ template trong repo:
  `memory/family/_template.md`
  `memory/family/README.md`

## Quy Trình Cập Nhật Hồ Sơ

- Người nhà gửi thông tin qua chat.
- Bot tóm tắt theo template.
- Hưng cập nhật thủ công vào `memory/family/*.md`.
- Bot chỉ đọc Family KB, không tự ghi hồ sơ.

## Ghi Chú Nâng Cấp

- Ưu tiên update khi changelog có mục `Security`.
- Kiểm tra version local trong `package.json` và version mới trên `origin/main` trước khi nâng cấp.

## Checklist Nâng Cấp An Toàn (Repo Đang Dirty)

1. Chụp trạng thái hiện tại:
   `git status -sb`
   `git rev-parse --short HEAD`
   `git rev-parse --short origin/main`
2. Kiểm tra dữ liệu nhạy cảm chưa bị stage:
   `git diff --name-only --cached`
   `git diff --name-only | grep -E '\\.env|memory/family'`
3. Commit local custom thành các nhóm nhỏ, không trộn với upstream:
   `scripts/committer "chore(local): update health bot soul and family kb flow" suckhoe/SOUL.md memory/family/_template.md Readme-hungreo.md`
   `scripts/committer "chore(local): harden ignore rules for local medical data" .gitignore`
4. Với file local-only không muốn lên git, dùng ignore cục bộ:
   `printf ".env.suckhoe\n" >> .git/info/exclude`
5. Đồng bộ upstream sau khi working tree sạch:
   `git pull --rebase origin main`
6. Nếu conflict:
   `git status`
   `git add <resolved-files>`
   `git rebase --continue`
7. Soát nhanh các thay đổi bảo mật từ upstream:
   `git log --oneline --max-count=80`
   `git show origin/main:CHANGELOG.md | sed -n '1,260p'`
8. Chạy gate tối thiểu trước khi test bot:
   `pnpm build`
   `pnpm check`
9. Verify bot chính `Rùa`:
   `docker logs --since 10m --tail 200 <main-container>`
10. Verify bot phụ `Dr Rùa`:
    `docker compose --env-file /Users/hungdinh/Development/hungreo-openclaw/.env.suckhoe -p openclaw-suckhoe restart openclaw-gateway`
    `docker logs --since 10m --tail 200 openclaw-suckhoe-openclaw-gateway-1`
11. Smoke test chức năng health:

- Nhắn `hi` (không bịa memory).
- Nhắn câu hỏi triệu chứng (có disclaimer).
- Nhắn câu hỏi cần nguồn (có phần `Nguồn tham khảo` cuối câu trả lời).

12. Nếu ổn định mới push:
    `git push origin main`

## Nguyên Tắc Khi Nâng Cấp

- Không dùng `git stash` trong môi trường multi-agent.
- Không sửa trực tiếp `README.md` upstream nếu thay đổi chỉ phục vụ local.
- Luôn giữ tách biệt: logic local của Hưng trong file riêng, logic chung theo upstream.
