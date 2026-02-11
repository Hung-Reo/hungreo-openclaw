#!/bin/sh
set -eu

DOCKER_SOCKET="${DOCKER_SOCKET:-/var/run/docker.sock}"
DEFAULT_GATEWAYS="hungreo-openclaw-openclaw-gateway-1 openclaw-suckhoe-openclaw-gateway-1"

docker_api() {
  /usr/bin/curl --silent --show-error --fail --unix-socket "$DOCKER_SOCKET" "$@"
}

print_status() {
  docker_api "http://localhost/containers/json?all=0" \
    | /usr/local/bin/node -e '
const chunks = [];
process.stdin.on("data", (c) => chunks.push(c));
process.stdin.on("end", () => {
  const rows = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  console.log("NAME\tSTATUS");
  for (const row of rows) {
    const name = (row.Names?.[0] ?? "").replace(/^\//, "");
    const status = row.Status ?? "";
    console.log(`${name}\t${status}`);
  }
});
'
}

restart_containers() {
  if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2086
    set -- $DEFAULT_GATEWAYS
  fi

  for name in "$@"; do
    docker_api -X POST "http://localhost/containers/${name}/restart" >/dev/null
    echo "restarted ${name}"
  done
}

usage() {
  cat <<'EOF'
Usage:
  openclaw-docker-api.sh status
  openclaw-docker-api.sh restart [container ...]
EOF
}

action="${1:-status}"
shift || true

case "$action" in
  status)
    print_status
    ;;
  restart)
    restart_containers "$@"
    ;;
  *)
    usage
    exit 2
    ;;
esac
