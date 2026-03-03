#!/usr/bin/env bash
set -euo pipefail

SERVER_NS="${SERVER_NS:-server_ns}"
CLIENT_NS="${CLIENT_NS:-client_ns}"

EDGE_PORT="${EDGE_PORT:-3063}"
EDGE_MATCH="${EDGE_MATCH:-unleash-edge}"

CLIENT_DIR="${CLIENT_DIR:-/home/simon/dev/test/frontend-streaming-tester}"
CLIENT_PY="${CLIENT_PY:-main.py}"
CLIENT_PYTHON="${CLIENT_PYTHON:-$CLIENT_DIR/venv/bin/python}"

TARGET_URL="${TARGET_URL:-http://10.1.1.1:3063/api/client/stream-frontend}"
AUTH_TOKEN="${AUTH_TOKEN:-*:development.15c9d1ee348d52d154ca17fa1cccd97034fe64b7aa1a034f2a546e4f}"

RESULTS="${RESULTS:-results.csv}"
SETTLE_SECONDS="${SETTLE_SECONDS:-10}"

# Steps: edit to taste
STEPS=(${STEPS:-10 50 200 500 1000})

# Helper: run commands inside server network namespace
ns_server() { sudo ip netns exec "$SERVER_NS" "$@"; }
ns_client() { sudo ip netns exec "$CLIENT_NS" "$@"; }

edge_pid() { pgrep -f "$EDGE_MATCH" | head -n1 || true; }

header() {
  echo "ts,target_conns,edge_pid,edge_rss_kb,edge_fd_count,edge_established_conns,ss_sockets,ss_rbtb_bytes,sockstat_tcp_mem_pages,sockstat_tcp_inuse,host_ulimit_n" > "$RESULTS"
}

sockstat_fields() {
  # Read sockstat INSIDE server_ns (network namespaces have separate /proc/net views)
  ns_server awk '
    $1=="TCP:"{
      for(i=1;i<=NF;i++){
        if($i=="mem"){mem=$(i+1)}
        if($i=="inuse"){inuse=$(i+1)}
      }
      if(mem==""){mem=0}
      if(inuse==""){inuse=0}
      printf "%s,%s", mem, inuse
    }' /proc/net/sockstat
}

measure_line() {
  local target_conns="$1"
  local ts pid rss_kb fd_count est_conns ss_sockets ss_rbtb mem_pages inuse uln

  ts="$(date -Iseconds)"
  pid="$(edge_pid)"

  if [[ -n "$pid" ]]; then
    rss_kb="$(awk '/VmRSS/ {print $2}' /proc/"$pid"/status)"
    fd_count="$(ls /proc/"$pid"/fd | wc -l)"
  else
    rss_kb=""
    fd_count=""
  fi

  # IMPORTANT: sockets live in server_ns, so ss must run there
  est_conns="$(ns_server ss -Htan "sport = :$EDGE_PORT" | wc -l || true)"

  # Sum rb+tb for sockets on EDGE_PORT (rough but very useful)
  local rb_sum=0 tb_sum=0 count=0
  while IFS= read -r line; do
    rb=$(echo "$line" | sed -n 's/.*rb\([0-9]\+\).*/\1/p' | head -n1); [[ -n "$rb" ]] || rb=0
    tb=$(echo "$line" | sed -n 's/.*tb\([0-9]\+\).*/\1/p' | head -n1); [[ -n "$tb" ]] || tb=0
    rb_sum=$((rb_sum + rb))
    tb_sum=$((tb_sum + tb))
    count=$((count + 1))
  done < <(ns_server ss -mHtan "sport = :$EDGE_PORT" || true)

  ss_sockets="$count"
  ss_rbtb="$((rb_sum + tb_sum))"

  # sockstat must also be read from server_ns; guard in case it prints nothing
  IFS=',' read -r mem_pages inuse < <(sockstat_fields || echo "0,0") || true

  uln="$(ulimit -n)"

  echo "$ts,$target_conns,$pid,$rss_kb,$fd_count,$est_conns,$ss_sockets,$ss_rbtb,$mem_pages,$inuse,$uln" | tee -a "$RESULTS"
}

kill_client() {
  # Kill any previous client generator started in client_ns
  ns_client pkill -f "$CLIENT_PY" 2>/dev/null || true
}

start_client() {
  local n="$1"
  # Run client in namespace, using venv python, and set env vars
  ns_client bash -lc "
    cd '$CLIENT_DIR' &&
    export NUM_CONNECTIONS='$n' TARGET_URL='$TARGET_URL' AUTH_TOKEN='$AUTH_TOKEN' &&
    '$CLIENT_PYTHON' '$CLIENT_PY' >/tmp/frontend-stream-client.log 2>&1 &
    echo \$! > /tmp/frontend-stream-client.pid
  "
}

main() {
  echo "STEPS: ${STEPS[@]}"
  header
  echo "Writing $RESULTS"
  kill_client

  for n in "${STEPS[@]}"; do
    echo "=== target connections: $n ==="
    start_client "$n"
    sleep "$SETTLE_SECONDS"
    measure_line "$n"
    # optional: leave it running a bit longer to see creep/leaks
    sleep 2
    kill_client
    sleep 2
  done

  echo "Done. Results in $RESULTS"
}

main