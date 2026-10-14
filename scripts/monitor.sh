#!/usr/bin/env bash
# monitor.sh — check a systemd service and count recent errors in syslog.
#
# Usage: monitor.sh <service> [minutes]
#   service  systemd unit name, with or without ".service" (e.g. docker)
#   minutes  syslog time window, default 60
#
# Exit codes:
#   0  service is active
#   1  service exists but is not active
#   2  usage error
#   3  service not found
#   4  systemctl is not available

set -uo pipefail

LOG_LINES=10
SYSLOG=/var/log/syslog
# Whole words only: "error" matches, "errors_total=0" in a metric name does not
ERROR_PATTERN='\b(error|err|fail(ed|ure)?|crit(ical)?|emerg|alert|panic|fatal)\b'

if [[ -t 1 ]]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; RESET=''
fi

usage() {
  echo "Usage: $(basename "$0") <service> [minutes]" >&2
  echo "Example: $(basename "$0") docker" >&2
}

header() { printf '\n%s== %s ==%s\n' "$BOLD" "$1" "$RESET"; }

# --- arguments -----------------------------------------------------------

if [[ $# -lt 1 || $# -gt 2 || -z "${1:-}" ]]; then
  usage
  exit 2
fi

service="${1%.service}"
minutes="${2:-60}"

# Reject anything that is not a plausible unit name before passing it to systemctl
if [[ ! "$service" =~ ^[A-Za-z0-9@._:-]+$ ]]; then
  echo "${RED}Error:${RESET} invalid service name '$1'" >&2
  exit 2
fi
if [[ ! "$minutes" =~ ^[1-9][0-9]*$ ]]; then
  echo "${RED}Error:${RESET} minutes must be a positive integer, got '$minutes'" >&2
  exit 2
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "${RED}Error:${RESET} systemctl not found (is this a systemd host?)" >&2
  exit 4
fi

unit="${service}.service"

# --- service status ------------------------------------------------------

header "Service: $unit"

# "systemctl cat" fails only when the unit file does not exist; is-active alone
# would print "inactive" for a typo and hide the real problem
if ! systemctl cat -- "$unit" >/dev/null 2>&1; then
  echo "${RED}NOT FOUND${RESET}: unit $unit does not exist on $(hostname)"
  exit 3
fi

state="$(systemctl is-active -- "$unit" 2>/dev/null)"
case "$state" in
  active)
    echo "Status: ${GREEN}${state}${RESET}"
    status_rc=0
    ;;
  *)
    echo "Status: ${RED}${state}${RESET}"
    status_rc=1

    header "Last $LOG_LINES log lines (journalctl -u $unit)"
    # Without root or the adm/systemd-journal group journalctl only shows the user's own logs
    logs="$(journalctl -u "$unit" -n "$LOG_LINES" --no-pager 2>&1)"
    if [[ -z "$logs" || "$logs" == "-- No entries --" ]]; then
      echo "${YELLOW}Log is empty${RESET} (no entries, or no permission: try sudo)"
    else
      echo "$logs"
    fi
    ;;
esac

# --- syslog errors -------------------------------------------------------

header "Errors in $SYSLOG for the last $minutes min"

if [[ ! -e "$SYSLOG" ]]; then
  echo "${YELLOW}Skipped${RESET}: $SYSLOG does not exist (rsyslog not installed?)"
  exit "$status_rc"
fi
if [[ ! -r "$SYSLOG" ]]; then
  echo "${YELLOW}Skipped${RESET}: no permission to read $SYSLOG (need root or the adm group)"
  exit "$status_rc"
fi

# Cutoffs for both rsyslog timestamp formats, in local time like the log itself:
#   RFC3339 (Ubuntu 24.04 default): 2026-10-14T21:05:03.772613+00:00
#   legacy:                         Oct 14 21:05:03
cutoff_iso="$(date -d "$minutes minutes ago" '+%Y-%m-%dT%H:%M:%S')"
cutoff_legacy="$(date -d "$minutes minutes ago" '+%m %d %H:%M:%S')"

# grep picks error lines, awk keeps those inside the time window
# and tallies them per program (field without "[pid]:").
# -a: syslog can contain NUL bytes (e.g. after a crash); without it grep
# prints only "binary file matches" and the count silently becomes 0
grep -aiE "$ERROR_PATTERN" "$SYSLOG" | awk \
  -v cutoff_iso="$cutoff_iso" -v cutoff_legacy="$cutoff_legacy" '
  BEGIN {
    split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " ")
    for (i = 1; i <= 12; i++) month[m[i]] = sprintf("%02d", i)
  }
  {
    # No {n} intervals: older mawk (Ubuntu default awk) does not support them
    if ($1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/) {
      ts = substr($1, 1, 19); cutoff = cutoff_iso; prog = $3
    } else if ($1 in month) {
      ts = sprintf("%s %02d %s", month[$1], $2, $3); cutoff = cutoff_legacy; prog = $5
    } else {
      next
    }
    if (ts < cutoff) next
    sub(/\[[0-9]+\]/, "", prog); sub(/:$/, "", prog)
    total++; by_prog[prog]++
  }
  END {
    printf "Total: %d\n", total
    if (total > 0) {
      print "Top sources:"
      fflush()  # print the header before sort writes its output
      cmd = "sort -rn | head -5"
      for (p in by_prog) printf "  %6d  %s\n", by_prog[p], p | cmd
      close(cmd)
    }
  }'

exit "$status_rc"
