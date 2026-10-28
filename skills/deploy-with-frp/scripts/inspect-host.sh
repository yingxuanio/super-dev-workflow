#!/usr/bin/env bash
set -u

primary_config="/opt/homebrew/etc/frp/frpc.toml"
secondary_config="/opt/homebrew/etc/frp/frpc-new.toml"

section() {
  printf '\n[%s]\n' "$1"
}

command_version() {
  command_name="$1"
  shift
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '%s: ' "$command_name"
    "$@" 2>/dev/null | head -n 1
  else
    printf '%s: not found\n' "$command_name"
  fi
}

summarize_frpc_config() {
  config_path="$1"
  if [ ! -r "$config_path" ]; then
    printf '%s: missing or unreadable\n' "$config_path"
    return
  fi

  printf '%s\n' "$config_path"
  awk '
    function clean(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      return value
    }
    /^serverAddr[[:space:]]*=/ { split($0, a, "="); print "  server: " clean(a[2]); next }
    /^serverPort[[:space:]]*=/ { split($0, a, "="); print "  server port: " clean(a[2]); next }
    /^\[\[proxies\]\]/ {
      if (name != "") print "  proxy: " name " | " type " | local=" local_ip ":" local_port " | remote=" remote_port domain
      name=type=local_ip=local_port=remote_port=domain=""
      next
    }
    /^name[[:space:]]*=/ { split($0, a, "="); name=clean(a[2]); next }
    /^type[[:space:]]*=/ { split($0, a, "="); type=clean(a[2]); next }
    /^localIP[[:space:]]*=/ { split($0, a, "="); local_ip=clean(a[2]); next }
    /^localPort[[:space:]]*=/ { split($0, a, "="); local_port=clean(a[2]); next }
    /^remotePort[[:space:]]*=/ { split($0, a, "="); remote_port=clean(a[2]); next }
    /^customDomains[[:space:]]*=/ {
      value=$0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      domain=" | domains=" value
      next
    }
    END {
      if (name != "") print "  proxy: " name " | " type " | local=" local_ip ":" local_port " | remote=" remote_port domain
    }
  ' "$config_path"
}

section "host"
uname -a
if command -v sw_vers >/dev/null 2>&1; then
  sw_vers
fi

section "tools"
command_version docker docker --version
if command -v docker >/dev/null 2>&1; then
  printf 'docker compose: '
  docker compose version 2>/dev/null | head -n 1 || true
fi
command_version frpc /opt/homebrew/bin/frpc --version

section "frpc processes"
ps -axo pid=,args= | awk '$2 ~ /(^|\/)frpc$/ { print }'

section "frpc launch agents"
launchctl list 2>/dev/null | awk 'tolower($0) ~ /frpc/ { print }' || true

section "frpc proxy inventory (secrets omitted)"
summarize_frpc_config "$primary_config"
summarize_frpc_config "$secondary_config"

section "docker compose projects"
if command -v docker >/dev/null 2>&1; then
  docker compose ls 2>/dev/null || true
fi

section "tcp listeners"
if command -v lsof >/dev/null 2>&1; then
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null || true
fi

if [ "${1:-}" = "--port" ]; then
  candidate="${2:-}"
  section "remote port hint"
  case "$candidate" in
    ''|*[!0-9]*)
      printf 'Usage: %s [--port numeric-port]\n' "$0"
      exit 2
      ;;
  esac

  if awk -v port="$candidate" '$1 == "remotePort" && $3 == port { found=1 } END { exit !found }' "$primary_config" "$secondary_config" 2>/dev/null; then
    printf 'Port %s already appears in a local frpc config.\n' "$candidate"
  elif command -v nc >/dev/null 2>&1 && nc -G 3 -z frp.linktion.cn "$candidate" >/dev/null 2>&1; then
    printf 'frp.linktion.cn:%s accepts TCP connections and is probably in use.\n' "$candidate"
  else
    printf 'Port %s is absent locally and did not accept a TCP probe. Confirm availability on frps before using it.\n' "$candidate"
  fi
fi
