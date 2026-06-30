#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

APP_NAME="linux-doctor"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$APP_NAME"
FIRST_RUN_STAMP="$STATE_DIR/.welcomed"
DISTRO="Unknown Linux"
DISTRO_ID="unknown"
ID_LIKE=""
PKG_MANAGER="unknown"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
    DISTRO_ID="${ID:-unknown}"
    ID_LIKE="${ID_LIKE:-}"
  else
    DISTRO="$(uname -s 2>/dev/null || echo Linux)"
    DISTRO_ID="unknown"
    ID_LIKE=""
  fi

  case "$DISTRO_ID" in
    ubuntu|debian|linuxmint|pop)
      PKG_MANAGER="apt"
      ;;
    fedora)
      PKG_MANAGER="dnf"
      ;;
    rhel|centos|rocky|almalinux|ol)
      if command_exists dnf; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      ;;
    arch|manjaro|endeavouros)
      PKG_MANAGER="pacman"
      ;;
    opensuse*|sles)
      PKG_MANAGER="zypper"
      ;;
    *)
      if [[ "$ID_LIKE" == *debian* ]]; then
        PKG_MANAGER="apt"
      elif [[ "$ID_LIKE" == *rhel* || "$ID_LIKE" == *fedora* ]]; then
        if command_exists dnf; then
          PKG_MANAGER="dnf"
        else
          PKG_MANAGER="yum"
        fi
      elif [[ "$ID_LIKE" == *arch* ]]; then
        PKG_MANAGER="pacman"
      elif [[ "$ID_LIKE" == *suse* ]]; then
        PKG_MANAGER="zypper"
      else
        PKG_MANAGER="unknown"
      fi
      ;;
  esac
}

show_welcome_if_first_run() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true

  if [[ ! -f "$FIRST_RUN_STAMP" ]]; then
    [[ -t 1 ]] && clear 2>/dev/null || true
    print_banner
    print_center 'Welcome to linux-doctor' "$BOLD$CYAN"
    print_center 'A Bash-based Linux health scanner that finds common issues' "$DIM"
    print_center 'and prints safe, distro-aware fix suggestions.' "$DIM"
    echo
    print_center 'The startup title now shows the tool name in a bold centered style, like your reference.' "$DIM"
    echo
    touch "$FIRST_RUN_STAMP" 2>/dev/null || true
    pause
  fi
}

system_overview() {
  section 'System overview'
  detect_distro
  info "Distro: $DISTRO"
  info "Kernel: $(uname -r 2>/dev/null || echo unknown)"
  info "Architecture: $(uname -m 2>/dev/null || echo unknown)"
  info "Uptime: $(uptime -p 2>/dev/null || uptime 2>/dev/null || echo unknown)"
  info "Load average: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo unknown)"
  info "Logged-in users: $(who 2>/dev/null | wc -l | tr -d ' ')"
  info "Package manager: $PKG_MANAGER"
}

disk_health() {
  section 'Disk health'

  local root_line used avail mount inode_used journal_usage
  root_line=$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5 "|" $4 "|" $6}')

  if [[ -z "$root_line" ]]; then
    warn 'Unable to read disk usage.'
    return
  fi

  IFS='|' read -r used avail mount <<< "$root_line"

  if (( used >= 95 )); then
    issue 'CRIT' "Root filesystem is ${used}% full." \
      'Very low free space can break logs, updates, and services.' \
      'Clean caches, old logs, and large files.' \
      $'sudo du -xh /var /tmp /home 2>/dev/null | sort -h | tail -n 20\nsudo journalctl --vacuum-time=7d\n# Debian/Ubuntu:\nsudo apt clean\n# Fedora/RHEL:\nsudo dnf clean all\n# Arch:\nsudo pacman -Sc'
  elif (( used >= 85 )); then
    issue 'WARN' "Root filesystem is ${used}% full." \
      'Disk pressure may slow the system and block future updates.' \
      'Inspect the largest directories and reclaim space.' \
      'sudo du -xh /var /tmp /home 2>/dev/null | sort -h | tail -n 20'
  else
    issue 'OK' "Root filesystem usage is healthy (${used}% used)." '' '' ''
  fi

  inode_used=$(df -Pi / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  if [[ -n "$inode_used" ]]; then
    if (( inode_used >= 90 )); then
      issue 'WARN' "Inode usage on / is ${inode_used}%." \
        'Many tiny files can exhaust inodes even when disk space remains.' \
        'Find directories with excessive small files and clean them.' \
        'sudo find /var /tmp -xdev -type f 2>/dev/null | wc -l'
    else
      success "Inode usage looks healthy (${inode_used}%)."
    fi
  fi

  if command_exists journalctl; then
    journal_usage=$(journalctl --disk-usage 2>/dev/null | sed 's/^Archived and active journals take up //')
    [[ -n "$journal_usage" ]] && info "Journal usage: $journal_usage"
  fi
}

memory_health() {
  section 'Memory and swap'

  if ! command_exists free; then
    warn "'free' command not found."
    return
  fi

  local total used avail swap_total swap_used avail_pct
  read -r total used avail <<< "$(free -m | awk '/^Mem:/ {print $2, $3, $7}')"
  read -r swap_total swap_used <<< "$(free -m | awk '/^Swap:/ {print $2, $3}')"
  avail_pct=$(( total > 0 ? (avail * 100 / total) : 0 ))

  info "RAM: total ${total} MiB, used ${used} MiB, available ${avail} MiB"
  info "Swap: total ${swap_total} MiB, used ${swap_used} MiB"

  if (( avail_pct < 10 )); then
    issue 'CRIT' "Available RAM is low (${avail_pct}% free)." \
      'Low memory can trigger swapping, freezes, or OOM kills.' \
      'Inspect top memory users and disable unneeded services.' \
      $'ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 12\nsudo journalctl -k -g "out of memory\\|oom" --no-pager'
  elif (( avail_pct < 20 )); then
    issue 'WARN' "Available RAM is getting low (${avail_pct}% free)." \
      'Sustained memory pressure hurts responsiveness.' \
      'Review memory-heavy processes.' \
      'ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 12'
  else
    success "Memory availability looks healthy (${avail_pct}% free)."
  fi

  if (( swap_total == 0 )); then
    warn 'No swap detected. This is okay on some systems, but risky on low-RAM machines.'
  elif (( swap_used > (swap_total / 2) )); then
    issue 'WARN' "Swap usage is high (${swap_used}/${swap_total} MiB)." \
      'Heavy swap can indicate memory pressure.' \
      'Inspect memory-heavy processes and consider more RAM or swap tuning.' \
      'ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 12'
  else
    success 'Swap usage looks normal.'
  fi
}

cpu_health() {
  section 'CPU and system load'

  local cpus load1 status
  cpus=$(nproc 2>/dev/null || echo 1)
  load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null)

  info "CPU cores: $cpus"
  info "1-minute load average: ${load1:-unknown}"

  if [[ -n "${load1:-}" ]]; then
    status=$(awk -v l="$load1" -v c="$cpus" 'BEGIN { if (l > c*1.5) print "CRIT"; else if (l > c) print "WARN"; else print "OK"; }')

    case "$status" in
      CRIT)
        issue 'CRIT' 'System load is much higher than CPU capacity.' \
          'The machine may feel slow or blocked by CPU, I/O, or stuck tasks.' \
          'Inspect the busiest processes and recent system errors.' \
          $'ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 12\nuptime\njournalctl -p 0..3 -xb --no-pager -n 20'
        ;;
      WARN)
        issue 'WARN' 'System load is higher than the CPU core count.' \
          'The system may be under pressure or experiencing I/O waits.' \
          'Check top CPU consumers and disk/log errors.' \
          'ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 12'
        ;;
      OK)
        success "System load looks reasonable for $cpus core(s)."
        ;;
    esac
  fi

  info 'Top CPU consumers:'
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 8
}

service_health() {
  section 'Failed services'

  if ! command_exists systemctl; then
    info 'systemd is not available; skipping service health.'
    return
  fi

  local failed count
  failed=$(systemctl --failed --no-legend 2>/dev/null | sed '/^[[:space:]]*$/d')
  count=$(printf '%s\n' "$failed" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')

  if [[ -z "$failed" || "$count" == '0' ]]; then
    success 'No failed systemd units detected.'
  else
    issue 'WARN' "$count failed systemd unit(s) detected." \
      'Failed services can explain missing functionality or repeated errors.' \
      'Inspect each unit status and journal logs.' \
      $'systemctl --failed\nsystemctl status <unit>\njournalctl -u <unit> --no-pager -n 50'
    printf '%s\n\n' "$failed" | head -n 10
  fi
}

log_health() {
  section 'Critical logs'

  if command_exists journalctl; then
    local recent
    recent=$(journalctl -p 0..3 -xb --no-pager -n 12 2>/dev/null)

    if [[ -n "$recent" && "$recent" != '-- No entries --' ]]; then
      issue 'WARN' 'Recent high-priority log entries were found.' \
        'Critical or error-level log messages often point to hardware, driver, service, or filesystem problems.' \
        'Review the entries below and investigate the related component.' \
        $'journalctl -p 0..3 -xb --no-pager\ndmesg --level=err,warn'
      printf '%s\n\n' "$recent"
    else
      success 'No recent high-priority journal entries found.'
    fi
  elif [[ -r /var/log/syslog ]]; then
    info 'journalctl not available; inspect /var/log/syslog manually.'
  else
    info 'No supported log source was found.'
  fi
}

network_health() {
  section 'Network basics'

  if ! command_exists ip; then
    warn "'ip' command not found."
    return
  fi

  local default_route dns_ok ping_ip ping_dns
  default_route=$(ip route show default 2>/dev/null | head -n 1)

  if [[ -n "$default_route" ]]; then
    success "Default route detected: $default_route"
  else
    issue 'WARN' 'No default route detected.' \
      'The system may not have internet access.' \
      'Check interface state and network manager.' \
      $'ip a\nip route\nsystemctl status NetworkManager\nsystemctl status systemd-networkd'
  fi

  if getent hosts example.com >/dev/null 2>&1; then
    dns_ok=1
    success 'DNS resolution works.'
  else
    dns_ok=0
    warn 'DNS resolution failed for example.com.'
  fi

  if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    ping_ip=1
    success 'External IP connectivity looks okay.'
  else
    ping_ip=0
    warn 'Could not reach 1.1.1.1.'
  fi

  if ping -c 1 -W 1 example.com >/dev/null 2>&1; then
    ping_dns=1
    success 'External DNS+network access looks okay.'
  else
    ping_dns=0
    if (( dns_ok == 1 )); then
      warn 'DNS resolves, but network reachability by name failed.'
    fi
  fi

  if (( ping_ip == 0 && dns_ok == 1 )); then
    dim 'Suggestion: inspect firewall, proxy, VPN, or upstream connectivity.'
  fi
}

update_health() {
  section 'Updates and package health'
  detect_distro

  case "$PKG_MANAGER" in
    apt)
      if command_exists apt; then
        local count
        count=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        if (( count > 0 )); then
          issue 'WARN' "$count package(s) can be upgraded." \
            'Pending updates may include bug fixes and security patches.' \
            'Review and apply updates when appropriate.' \
            $'sudo apt update\nsudo apt upgrade'
        else
          success 'No upgradable packages detected.'
        fi
      else
        warn 'apt not available.'
      fi
      ;;
    dnf)
      if command_exists dnf; then
        local out count
        out=$(dnf check-update --refresh 2>/dev/null || true)
        count=$(printf '%s\n' "$out" | awk 'NF && $1 !~ /^(Last|Obsoleting|Security:)/ {count++} END {print count+0}')
        if (( count > 0 )); then
          issue 'WARN' "$count package(s) appear to have updates." \
            'Pending updates may fix bugs and stability issues.' \
            'Review and apply updates.' \
            'sudo dnf upgrade --refresh'
        else
          success 'No obvious package updates detected.'
        fi
      else
        warn 'dnf not available.'
      fi
      ;;
    yum)
      warn 'yum support can be expanded next; basic distro detection is already working.'
      ;;
    pacman)
      if command_exists pacman; then
        local count
        count=$(pacman -Qu 2>/dev/null | wc -l | tr -d ' ')
        if (( count > 0 )); then
          issue 'WARN' "$count package(s) can be upgraded." \
            'Pending updates may fix bugs and stability issues.' \
            'Review and apply updates.' \
            'sudo pacman -Syu'
        else
          success 'No upgradable packages detected.'
        fi
      else
        warn 'pacman not available.'
      fi
      ;;
    zypper)
      if command_exists zypper; then
        local count
        count=$(zypper lu 2>/dev/null | awk 'BEGIN{c=0} /^v / {c++} END{print c+0}')
        if (( count > 0 )); then
          issue 'WARN' "$count package(s) can be upgraded." \
            'Pending updates may fix bugs and stability issues.' \
            'Review and apply updates.' \
            $'sudo zypper refresh\nsudo zypper update'
        else
          success 'No obvious package updates detected.'
        fi
      else
        warn 'zypper not available.'
      fi
      ;;
    *)
      info 'Package manager not recognized automatically on this system.'
      ;;
  esac
}

full_scan() {
  [[ -t 1 ]] && clear 2>/dev/null || true
  print_banner
  system_overview
  disk_health
  memory_health
  cpu_health
  service_health
  log_health
  network_health
  update_health
}

show_help() {
  cat <<'EOF'
linux-doctor - Bash-based Linux health scanner

Usage:
  ./linux-doctor.sh            Start interactive menu
  ./linux-doctor.sh --full     Run full scan
  ./linux-doctor.sh --disk     Run disk checks
  ./linux-doctor.sh --memory   Run memory checks
  ./linux-doctor.sh --cpu      Run CPU/load checks
  ./linux-doctor.sh --services Run failed service checks
  ./linux-doctor.sh --logs     Run log checks
  ./linux-doctor.sh --network  Run network checks
  ./linux-doctor.sh --updates  Run package/update checks
EOF
}

menu_loop() {
  while true; do
    [[ -t 1 ]] && clear 2>/dev/null || true
    print_banner
    echo '1) Full system scan'
    echo '2) System overview'
    echo '3) Disk health'
    echo '4) Memory & swap'
    echo '5) CPU & load'
    echo '6) Failed services'
    echo '7) Critical logs'
    echo '8) Network basics'
    echo '9) Updates / package health'
    echo '0) Exit'
    echo

    read -r -p 'Choose an option: ' choice || exit 0

    case "$choice" in
      1) full_scan; pause ;;
      2) [[ -t 1 ]] && clear 2>/dev/null || true; print_banner; system_overview; pause ;;
      3) [[ -t 1 ]] && clear 2>/dev/null || true; print_banner; disk_health; pause ;;
      4) [[ -t 1 ]] && clear 2>/dev/null || true; print_banner; memory_health; pause ;;
      5) [[ -t 1 ]] && clear 2>/dev/null || true; print_banner; cpu_health; pause ;;
      6) [[ -t 1 ]] && clear 2>/dev/null || true; print_banner; service_health; pause ;;
      7) [[ -t 1 ]] && clear 2>/dev/null || true; print_banner; log_health; pause ;;
      8) [[ -t 1 ]] && clear 2>/dev/null || true; print_banner; network_health; pause ;;
      9) [[ -t 1 ]] && clear 2>/dev/null || true; print_banner; update_health; pause ;;
      0) exit 0 ;;
      *) warn 'Invalid option.'; sleep 1 ;;
    esac
  done
}

main() {
  detect_distro

  case "${1:-}" in
    --full)
      full_scan
      ;;
    --disk)
      [[ -t 1 ]] && clear 2>/dev/null || true
      print_banner
      disk_health
      ;;
    --memory)
      [[ -t 1 ]] && clear 2>/dev/null || true
      print_banner
      memory_health
      ;;
    --cpu)
      [[ -t 1 ]] && clear 2>/dev/null || true
      print_banner
      cpu_health
      ;;
    --services)
      [[ -t 1 ]] && clear 2>/dev/null || true
      print_banner
      service_health
      ;;
    --logs)
      [[ -t 1 ]] && clear 2>/dev/null || true
      print_banner
      log_health
      ;;
    --network)
      [[ -t 1 ]] && clear 2>/dev/null || true
      print_banner
      network_health
      ;;
    --updates)
      [[ -t 1 ]] && clear 2>/dev/null || true
      print_banner
      update_health
      ;;
    -h|--help)
      show_help
      ;;
    '')
      show_welcome_if_first_run
      menu_loop
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
}

main "$@"
