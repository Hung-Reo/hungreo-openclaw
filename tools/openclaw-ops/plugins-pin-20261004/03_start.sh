#!/bin/bash
# 03 — HƯNG CHẠY. Khởi động lại theo thứ tự suckhoe → hungreo, chờ "[gateway] ready" từng cái, rồi bật lại healthcheck timer.
# Nếu 1 gateway không ready: KHÔNG bật timer, dừng lại và báo Claude Code (cân nhắc 99_rollback.sh).
# Không dùng pipefail: `journalctl | grep -q` có thể làm journalctl nhận SIGPIPE → pipeline báo fail dù đã thấy "ready".
set -u
export TZ=Asia/Ho_Chi_Minh

wait_ready() { # service since
  local u=$1 since=$2 i
  for i in $(seq 1 48); do
    if journalctl --user -u "$u" --since "$since" --no-pager | grep -q "\[gateway\] ready"; then
      echo "  $u ready sau ~$((i*5))s"; return 0; fi
    if [ "$(systemctl --user is-active "$u")" = "failed" ]; then echo "  $u FAILED"; return 1; fi
    sleep 5
  done
  echo "  $u KHÔNG ready sau 240s"; return 1
}

for s in suckhoe hungreo; do
  u=openclaw-gateway-$s.service
  since=$(date "+%F %T")
  echo "== restart $s ($since)"
  systemctl --user restart "$u"
  if ! wait_ready "$u" "$since"; then
    journalctl --user -u "$u" --since "$since" --no-pager | grep -iE "error|cannot find|invalid" | tail -15
    echo "STOP — healthcheck timer vẫn TẮT. Báo Claude Code."; exit 1
  fi
done

systemctl --user start openclaw-healthcheck.timer
echo "healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer)"
for s in hungreo suckhoe; do echo "$s $(systemctl --user is-active openclaw-gateway-$s.service) pid=$(systemctl --user show openclaw-gateway-$s.service -p MainPID --value)"; done
echo "OK 03 — báo Claude Code chạy 04_verify.sh"
