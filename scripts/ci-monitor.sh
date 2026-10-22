#!/usr/bin/env bash
# Samples a CI runner's memory, swap, disk and busiest processes every
# INTERVAL seconds while COMMAND runs, for the test jobs (ci.yml): a job
# whose runner dies mid-test, out of memory or disk, shows in its live log
# what it was running out of. Each sample is one line, printed and appended
# to FILE, which the job's diagnostics step reads back:
#
#   monitor 01:23:45 avail 6.1 GB of 15.6, swap 0.0/4.0 GB, load 7.9, disk free 52 GB, 31 pep-build, top: pep-build 1.4 GB, ...
#
#   scripts/ci-monitor.sh <interval> <file> <dir> -- <command>...
#   scripts/ci-monitor.sh --report <file> [dir]
#
# It exits with COMMAND's status. dir is the folder whose disk is reported.
# Samples from several commands can go to one file. The
# first line describes the machine: CPUs, and on Linux whether
# systemd-oomd, which kills whole services under memory pressure, runs.
#
# --report, for the diagnostics step of a failed, cancelled or timed-out
# job, prints the samples with the least memory free and the last few,
# then the state now: every process with its age and size (a hung test or
# build is the old one), the disks, and on Linux the kernel's
# out-of-memory kills.
set -euo pipefail
os="$(uname -s)"

if [ "$1" = --report ]; then
  file="$2"
  dir="${3:-.}"
  set +e
  if [ -f "$file" ]; then
    echo "=== samples with the least memory available"
    grep '^monitor [0-9]' "$file" | sort -n -k4 | head -3
    echo "=== last samples"
    tail -5 "$file"
  else
    echo "=== no samples in $file"
  fi
  echo "=== processes, with their age (etime) or start, and size"
  case "$os" in
    MINGW*|MSYS*|CYGWIN*)
      powershell -NoProfile -Command 'Get-CimInstance Win32_Process | Sort-Object CreationDate | Format-Table -AutoSize -Wrap ProcessId, ParentProcessId, CreationDate, @{n="MB"; e={[int]($_.WorkingSetSize / 1MB)}}, CommandLine | Out-String -Width 400'
      ;;
    # By process id, which is near enough to age.
    Darwin) ps -A -o pid,ppid,etime,rss,args ;;
    *) ps -e --sort=start_time -o pid,ppid,etime,rss,args ;;
  esac
  echo "=== disks"
  df -h "$dir" "${TMPDIR:-/tmp}"
  echo "=== memory"
  case "$os" in
    Darwin) vm_stat; sysctl vm.swapusage ;;
    *) cat /proc/meminfo ;;
  esac
  if [ "$os" = Linux ]; then
    echo "=== out-of-memory kills"
    sudo dmesg -T | grep -iE 'out of memory|oom|killed process'
    journalctl -u systemd-oomd --no-pager 2>/dev/null | tail -20
  fi
  exit 0
fi

interval="$1"
file="$2"
dir="$3"
[ "${4:-}" = -- ] || { echo "usage: ci-monitor.sh <interval> <file> <dir> -- <command>..." >&2; exit 2; }
shift 4

gb() { awk -v k="$1" 'BEGIN { printf "%.1f", k / 1048576 }'; }

# Kilobytes: total and available memory, total and free swap.
memory() {
  case "$os" in
    Darwin)
      local page total avail swap
      page="$(sysctl -n hw.pagesize)"
      total=$(($(sysctl -n hw.memsize) / 1024))
      avail="$(vm_stat | awk -v p="$page" '/Pages (free|inactive|speculative)/ { gsub(/\./, "", $NF); n += $NF } END { print int(n * p / 1024) }')"
      # "total = 2048.00M  used = 1024.00M  free = 1024.00M  ...", or G
      swap="$(sysctl -n vm.swapusage | awk 'function kb(v) { return int(v * (v ~ /G/ ? 1048576 : 1024)) } { print kb($3), kb($9) }')"
      echo "$total $avail $swap"
      ;;
    *)
      # MSYS's /proc/meminfo, on Windows, has no MemAvailable.
      awk '/^MemTotal:/ { t = $2 } /^MemFree:/ { f = $2 } /^MemAvailable:/ { a = $2 }
           /^SwapTotal:/ { st = $2 } /^SwapFree:/ { sf = $2 }
           END { print t, (a ? a : f), st, sf }' /proc/meminfo
      ;;
  esac
}

# "rss-kilobytes name" for every process.
processes() {
  case "$os" in
    MINGW*|MSYS*|CYGWIN*)
      # "pep-build.exe","1234","Console","1","123,456 K"
      tasklist //fo csv //nh | awk -F'","' '{ gsub(/[^0-9]/, "", $5); sub(/^"/, "", $1); sub(/\.exe$/, "", $1); print $5, $1 }'
      ;;
    *)
      ps -A -o rss= -o comm= | awk '{ n = split($2, p, "/"); print $1, p[n] }'
      ;;
  esac
}

load() {
  case "$os" in
    Linux) cut -d' ' -f1 /proc/loadavg ;;
    Darwin) sysctl -n vm.loadavg | awk '{ print $2 }' ;;
    *) echo "-" ;;
  esac
}

sample() {
  case "$os" in
    Linux)
      oomd="$(systemctl is-active systemd-oomd 2>/dev/null || true)"
      echo "monitor: $(nproc) CPUs ($(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')), systemd-oomd ${oomd:-absent}" | tee -a "$file"
      ;;
    Darwin) echo "monitor: $(sysctl -n hw.ncpu) CPUs ($(sysctl -n machdep.cpu.brand_string))" | tee -a "$file" ;;
    *) echo "monitor: $(nproc) CPUs" | tee -a "$file" ;;
  esac

  while true; do
    # A probe that fails leaves its field empty rather than ending the monitor.
    read -r total avail swap_total swap_free < <(memory || true) || true
    list="$(processes || true)"
    builds="$(printf '%s\n' "$list" | awk '$2 == "pep-build" { n++ } END { print n + 0 }')"
    top="$(printf '%s\n' "$list" | sort -rn | head -3 | awk '{ printf "%s%s %.1f GB", (NR > 1 ? ", " : ""), $2, $1 / 1048576 }' || true)"
    disk="$(df -Pk "$dir" 2>/dev/null | awk 'NR == 2 { printf "%d", $4 / 1048576 }' || true)"
    echo "monitor $(date -u +%H:%M:%S) avail $(gb "${avail:-0}") GB of $(gb "${total:-0}"), swap $(gb $((${swap_total:-0} - ${swap_free:-0})))/$(gb "${swap_total:-0}") GB, load $(load || true), disk free ${disk:-?} GB, $builds pep-build, top: $top" | tee -a "$file"
    sleep "$interval"
  done
}

sample &
sampler=$!
status=0
"$@" || status=$?
kill "$sampler" 2>/dev/null || true
exit "$status"
