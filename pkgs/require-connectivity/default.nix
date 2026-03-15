{ writeShellApplication
, lib
, iputils
, curl
, socat
, systemd
}:
writeShellApplication {
  name = "require-connectivity";

  runtimeInputs = [
    iputils
    curl
    socat
    systemd
  ];

  text = ''
    #!/usr/bin/env bash
    set -euo pipefail

    CHECK_INTERVAL_SECONDS="''${CHECK_INTERVAL_SECONDS:-15}"
    DOWN_FOR_SECONDS="''${DOWN_FOR_SECONDS:-300}"
    ICMP_TARGETS="''${ICMP_TARGETS:-8.8.8.8 1.1.1.1 8.8.4.4}"
    HTTP_TARGETS="''${HTTP_TARGETS:-https://google.com}"
    STATE_DIR="''${STATE_DIR:-/var/lib/require-connectivity}"
    METRICS_ENABLED="''${METRICS_ENABLED:-0}"
    METRICS_LISTEN_ADDRESS="''${METRICS_LISTEN_ADDRESS:-127.0.0.1}"
    METRICS_PORT="''${METRICS_PORT:-9955}"

    REBOOT_STATE_FILE="$STATE_DIR/reboot-state"
    PENDING_REBOOT_FILE="$STATE_DIR/pending-connectivity-reboot"
    METRICS_FILE="$STATE_DIR/metrics.prom"

    log_info() {
      echo "[require-connectivity] $*"
    }

    log_shout() {
      echo "[require-connectivity][SHOUT] $*"
    }

    write_state() {
      cat >"$REBOOT_STATE_FILE" <<EOF
CONNECTIVITY_REBOOT_COUNT=$connectivity_reboot_count
LAST_REBOOT_WAS_CONNECTIVITY=$last_reboot_was_connectivity
EOF
    }

    write_metrics() {
      local down_seconds="0"

      if [[ -n "$down_since" ]]; then
        down_seconds="$((now - down_since))"
      fi

      cat >"$METRICS_FILE" <<EOF
# HELP require_connectivity_seconds_since_connectivity_lost Seconds since all connectivity checks started failing continuously.
# TYPE require_connectivity_seconds_since_connectivity_lost gauge
require_connectivity_seconds_since_connectivity_lost $down_seconds
# HELP require_connectivity_last_reboot_was_connectivity Whether the last reboot happened due to connectivity loss (1=yes, 0=no).
# TYPE require_connectivity_last_reboot_was_connectivity gauge
require_connectivity_last_reboot_was_connectivity $last_reboot_was_connectivity
# HELP require_connectivity_connectivity_reboots_total Total number of reboots triggered by connectivity loss.
# TYPE require_connectivity_connectivity_reboots_total counter
require_connectivity_connectivity_reboots_total $connectivity_reboot_count
EOF
    }

    start_metrics_server() {
      while true; do
        {
          printf 'HTTP/1.1 200 OK\r\n'
          printf 'Content-Type: text/plain; version=0.0.4; charset=utf-8\r\n'
          printf 'Connection: close\r\n\r\n'
          cat "$METRICS_FILE"
        } | socat - "TCP-LISTEN:$METRICS_PORT,bind=$METRICS_LISTEN_ADDRESS,reuseaddr,fork"
      done
    }

    is_reachable() {
      local target

      for target in $ICMP_TARGETS; do
        if ping -n -c 1 -W 1 "$target" >/dev/null 2>&1; then
          return 0
        fi
      done

      for target in $HTTP_TARGETS; do
        if curl --silent --show-error --fail --max-time 3 --output /dev/null "$target" >/dev/null 2>&1; then
          return 0
        fi
      done

      return 1
    }

    down_since=""
    now="$(date +%s)"

    mkdir -p "$STATE_DIR"

    connectivity_reboot_count=0
    last_reboot_was_connectivity=0

    if [[ -f "$REBOOT_STATE_FILE" ]]; then
      # shellcheck source=/dev/null
      . "$REBOOT_STATE_FILE"
      connectivity_reboot_count="''${CONNECTIVITY_REBOOT_COUNT:-0}"
      last_reboot_was_connectivity="''${LAST_REBOOT_WAS_CONNECTIVITY:-0}"
    fi

    if [[ -f "$PENDING_REBOOT_FILE" ]]; then
      last_reboot_was_connectivity=1
      rm -f "$PENDING_REBOOT_FILE"
    else
      last_reboot_was_connectivity=0
    fi

    write_state
    write_metrics

    if [[ "$METRICS_ENABLED" == "1" ]]; then
      log_info "metrics endpoint enabled at http://$METRICS_LISTEN_ADDRESS:$METRICS_PORT/"
      start_metrics_server &
      metrics_server_pid="$!"
      trap 'kill "$metrics_server_pid" 2>/dev/null || true' EXIT
    fi

    log_info "starting watchdog with interval=''${CHECK_INTERVAL_SECONDS}s, threshold=''${DOWN_FOR_SECONDS}s"
    log_info "ICMP targets: ''${ICMP_TARGETS}"
    log_info "HTTP targets: ''${HTTP_TARGETS}"

    while true; do
      now="$(date +%s)"

      if is_reachable; then
        if [[ -n "$down_since" ]]; then
          elapsed="$((now - down_since))"
          log_info "connectivity restored after ''${elapsed}s of total failure"
          down_since=""
        fi
      else
        if [[ -z "$down_since" ]]; then
          down_since="$now"
          log_info "connectivity seems gone: all targets currently unreachable"
        else
          elapsed="$((now - down_since))"
          if (( elapsed >= DOWN_FOR_SECONDS )); then
            connectivity_reboot_count="$((connectivity_reboot_count + 1))"
            touch "$PENDING_REBOOT_FILE"
            write_state
            write_metrics
            log_shout "rebooting machine: all connectivity checks failed for ''${elapsed}s (threshold ''${DOWN_FOR_SECONDS}s)"
            exec systemctl reboot
          fi
        fi
      fi

      write_metrics

      sleep "$CHECK_INTERVAL_SECONDS"
    done
  '';

  meta = {
    description = "Reboot host when all configured connectivity checks fail continuously";
    homepage = "https://github.com/NixOS/nixpkgs";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "require-connectivity";
  };
}
