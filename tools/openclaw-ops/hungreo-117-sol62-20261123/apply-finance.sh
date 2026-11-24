#!/usr/bin/env bash
# Hưng GO 24/11 17:20: replace live hungreo-finance (TS source) with the tested esbuild bundle.
set -Eeuo pipefail; umask 077
P=/home/hung/.openclaw-hungreo; U=/home/hung/openclaw-upgrade-hungreo-20261123-117
NODE=/home/hung/openclaw-node-24.22.1/node/bin/node; ENTRY=$U/runtime/node_modules/openclaw/dist/index.js
UNIT=openclaw-gateway-hungreo.service; TIMER=openclaw-healthcheck.timer
X=$P/extensions/hungreo-finance; J=/home/hung/claude-finance-117/finance-js
BK=/home/hung/backups/hungreo-finance-ts-20261124
ready() { curl -sS --max-time 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/readyz 2>/dev/null; }
oc() (
  for item in $(compgen -v OPENCLAW_ || true); do unset "$item"; done
  unset TELEGRAM_BOT_TOKEN OPENAI_API_KEY
  set -a; source "$P/gateway.systemd.env"; set +a; unset OPENAI_API_KEY
  export OPENCLAW_PROFILE=hungreo OPENCLAW_STATE_DIR="$P" OPENCLAW_CONFIG_PATH="$P/openclaw.json" OPENCLAW_GATEWAY_PORT=18789 OPENCLAW_SYSTEMD_UNIT=$UNIT
  export PATH="${NODE%/*}:/usr/bin:/bin" DBUS_SESSION_BUS_ADDRESS="unix:path=$U/missing-user-bus"
  cd "$P/workspace"; timeout --kill-after=30 300 "$NODE" "$ENTRY" --profile hungreo "$@" </dev/null
)
start_back() { systemctl --user start "$UNIT"; for i in $(seq 1 60); do [[ "$(ready)" == 200 ]] && break; sleep 3; done; systemctl --user start "$TIMER"; }
restore() {
  trap - ERR; echo "RESTORE_BEGIN"
  systemctl --user stop "$UNIT" || true
  if [[ -d "$BK/hungreo-finance" ]]; then
    [[ -d "$X" ]] && mv -T "$X" "$BK/failed-bundle.$(date +%H%M%S)"
    cp -a "$BK/hungreo-finance" "$X"
  fi
  oc plugins registry --refresh || true
  start_back; echo "RESTORED readyz=$(ready)"; exit 1
}
[[ -f "$J/dist/index.js" && -d "$X" && ! -e "$BK" ]]
python3 -I "$U/ops/profile-check.py" idle
mkdir -p -m 700 "$BK"; cp -a "$X" "$BK/hungreo-finance"; echo "BACKUP=$BK/hungreo-finance"
trap restore ERR
systemctl --user stop "$TIMER" openclaw-healthcheck.service
systemctl --user stop "$UNIT"; echo "$(date +%T) stopped"
mv -T "$X" "$BK/moved-live"; cp -a "$J" "$X"
oc plugins registry --refresh 2>&1 | tail -2
start_back
echo "$(date +%T) readyz=$(ready)"
sleep 5
line=$(journalctl --user -u "$UNIT" --since "-4 min" --no-pager | grep "http server listening" | tail -1)
echo "$line" | cut -c1-260
grep -q "hungreo-finance" <<<"$line"
journalctl --user -u "$UNIT" --since "-4 min" --no-pager | grep -c "webhook advertised"
echo "TIMER=$(systemctl --user is-active $TIMER) SUCKHOE=$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:18795/readyz)"
echo APPLY_OK
