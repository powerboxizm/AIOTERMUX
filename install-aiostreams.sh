#!/data/data/com.termux/files/usr/bin/bash
set -e

BACKUP_PATH="/sdcard/Download/aiostreams-ubuntu-v2.tar.gz"
BACKUP_URL="https://github.com/powerboxizm/AIOTERMUX/releases/download/v1.0/aiostreams-ubuntu-v2.tar.gz"
LOG_FILE="$HOME/aio_install.log"
TOTAL_STEPS=7
STEP=0

# -- Resume support --
# STATE_FILE remembers the last fully-completed step so re-running the
# script after it gets interrupted skips finished work instead of
# starting over.
STATE_FILE="$HOME/.aio_install_state"
RESUME_STEP=0
[ -f "$STATE_FILE" ] && RESUME_STEP=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
case "$RESUME_STEP" in ''|*[!0-9]*) RESUME_STEP=0 ;; esac

mark_step_done() {
  echo "$1" > "$STATE_FILE"
}

step_already_done() {
  [ "$1" -le "$RESUME_STEP" ]
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
CLEAR_LINE='\033[K'

# Bash-builtin sleep replacement. Avoids depending on the external
# `sleep` binary, which can transiently vanish mid-upgrade if the
# coreutils package (which provides it) is being reinstalled while
# this spinner is still running in the background.
tsleep() {
  if command -v sleep >/dev/null 2>&1; then
    sleep "$1" 2>/dev/null && return 0
  fi
  # Fallback only if the real `sleep` binary is unavailable. This
  # busy-reads /dev/zero one byte at a time (bash reads non-seekable
  # input byte-by-byte), which is CPU-heavy - avoid it when possible.
  read -rt "$1" -N 999999 < /dev/zero 2>/dev/null
  return 0
}
export -f tsleep

export DEBIAN_FRONTEND=noninteractive

term_width() {
  local w
  w=$(tput cols 2>/dev/null || echo 40)
  echo "$w"
}

banner() {
  echo -e "${CYAN}${BOLD}"
  echo "  ================================"
  echo "      AIOStreams Installer"
  echo "  ================================"
  echo -e "${RESET}"
}

progress_bar() {
  local percent=$(( STEP * 100 / TOTAL_STEPS ))
  local width=20
  local filled=$(( percent * width / 100 ))
  local empty=$(( width - filled ))
  local bar
  bar=$(printf "%${filled}s" | tr ' ' '#')
  local rest
  rest=$(printf "%${empty}s" | tr ' ' '-')
  printf "  ${DIM}[%s%s] %d%%${RESET}\n" "$bar" "$rest" "$percent"
}

step_header() {
  STEP=$((STEP+1))
  echo ""
  printf "${BOLD}Step %d/%d${RESET} - %s\n" "$STEP" "$TOTAL_STEPS" "$1"
}

fit_msg() {
  local msg="$1"
  local reserve=10
  local maxw=$(( $(term_width) - reserve ))
  if [ "$maxw" -lt 10 ]; then maxw=10; fi
  if [ "${#msg}" -gt "$maxw" ]; then
    echo "${msg:0:$((maxw-3))}..."
  else
    echo "$msg"
  fi
}

spinner() {
  local pid=$1
  local msg
  msg=$(fit_msg "$2")
  local spin='|/-\'
  local i=0
  local elapsed=0
  local tick=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % ${#spin} ))
    tick=$((tick+1))
    if [ $((tick % 7)) -eq 0 ]; then elapsed=$((elapsed+1)); fi
    printf "\r${CLEAR_LINE}  ${CYAN}%s${RESET} %s (%ds)" "${spin:$i:1}" "$msg" "$elapsed"
    tsleep 0.15
  done
}

run() {
  local msg="$1"
  local cmd="$2"
  bash -c "$cmd" > "$LOG_FILE" 2>&1 &
  local pid=$!
  spinner "$pid" "$msg"
  wait "$pid"
  local status=$?
  local shown
  shown=$(fit_msg "$msg")
  if [ $status -eq 0 ]; then
    printf "\r${CLEAR_LINE}  ${GREEN}OK${RESET}  %s\n" "$shown"
  else
    printf "\r${CLEAR_LINE}  ${RED}FAIL${RESET} %s\n" "$shown"
    echo -e "${RED}--- Error output ---${RESET}"
    tail -n 25 "$LOG_FILE"
    exit 1
  fi
  progress_bar
}

# run_quiet: no background process/spinner. Used for repair steps that
# must work even if sleep/basic binaries are currently broken.
run_quiet() {
  local msg="$1"
  local cmd="$2"
  local allow_fail="${3:-0}"
  local shown
  shown=$(fit_msg "$msg")
  printf "  ${CYAN}...${RESET} %s" "$shown"
  if bash -c "$cmd" > "$LOG_FILE" 2>&1; then
    printf "\r${CLEAR_LINE}  ${GREEN}OK${RESET}  %s\n" "$shown"
  else
    if [ "$allow_fail" = "1" ]; then
      printf "\r${CLEAR_LINE}  ${YELLOW}SKIP${RESET} %s\n" "$shown"
    else
      printf "\r${CLEAR_LINE}  ${RED}FAIL${RESET} %s\n" "$shown"
      echo -e "${RED}--- Error output ---${RESET}"
      tail -n 25 "$LOG_FILE"
      exit 1
    fi
  fi
}

clear
banner

# Prevent Android/Termux from suspending or getting killed by OEM
# battery management while this runs unattended (this is the most
# likely cause of the process dying silently mid-step with no error).
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock
  trap 'termux-wake-unlock >/dev/null 2>&1' EXIT
fi

# -- Step 1: repair Termux base before doing anything else --
# Fixes "CANNOT LINK EXECUTABLE ... library X not found" errors caused
# by an interrupted upgrade leaving core packages in a broken state.
# Reinstalls every known-problematic shared library explicitly, then
# does a generic broken-package repair pass as a catch-all.
step_header "Repairing Termux base packages"
if step_already_done 1; then
  printf "  ${GREEN}OK${RESET}  Already completed (resumed)\n"
else
  run_quiet "Refreshing package index" "pkg update -y" 0
  run_quiet "Reconfiguring pending packages" "dpkg --configure -a" 1
  run_quiet "Reinstalling libpcre2" "pkg install -y pcre2" 1
  run_quiet "Reinstalling libgmp" "pkg install -y libgmp" 1
  run_quiet "Reinstalling libandroid-selinux" "pkg install -y libandroid-selinux" 1
  run_quiet "Reinstalling termux-tools" "pkg install -y --reinstall termux-tools" 1
  run_quiet "Fixing broken package state" "apt --fix-broken install -y" 1
  run_quiet "Verifying core tools work" "tsleep 0.1 && echo ok" 0
  mark_step_done 1
fi
progress_bar

# -- Step 2: prerequisites --
step_header "Installing prerequisites"
if step_already_done 2; then
  printf "  ${GREEN}OK${RESET}  Already completed (resumed)\n"
else
  run "Installing proot-distro" "pkg install -y proot-distro"
  mark_step_done 2
fi

# -- Step 3: storage access --
step_header "Requesting storage access"
termux-setup-storage
printf "  ${YELLOW}!${RESET} Waiting for storage permission...\n"

WAIT_SECS=0
until [ -d ~/storage/shared ] || [ "$WAIT_SECS" -ge 60 ]; do
  printf "\r${CLEAR_LINE}  ${CYAN}...${RESET} Waiting (%ds)" "$WAIT_SECS"
  tsleep 1
  WAIT_SECS=$((WAIT_SECS+1))
done
echo ""

if [ -d ~/storage/shared ]; then
  printf "  ${GREEN}OK${RESET}  Storage permission granted\n"
else
  printf "  ${RED}FAIL${RESET} No permission after 60s\n"
  echo "     Grant it manually, then rerun this script."
  exit 1
fi
progress_bar

# -- Step 4: locate & verify backup --
step_header "Locating backup file"
if [ -f "$BACKUP_PATH" ]; then
  printf "  ${GREEN}OK${RESET}  Found backup file locally\n"
else
  printf "  ${YELLOW}!${RESET} Backup not found locally, downloading...\n"
  mkdir -p "$(dirname "$BACKUP_PATH")"
  run "Downloading backup from GitHub" "curl -fL --retry 3 -o '$BACKUP_PATH' '$BACKUP_URL'"
fi
run "Verifying archive integrity" "gzip -t '$BACKUP_PATH'"

# -- Step 5: copy & restore --
step_header "Restoring AIOStreams container"
if step_already_done 5; then
  printf "  ${GREEN}OK${RESET}  Already completed (resumed)\n"
else
  run "Copying backup to Termux storage" "cp '$BACKUP_PATH' ~/aio-restore-temp.tar.gz"
  run "Restoring Ubuntu container" "proot-distro restore ~/aio-restore-temp.tar.gz"
  mark_step_done 5
fi

# -- Step 6: cleanup --
step_header "Cleaning up unnecessary files"
run "Removing temp backup copy" "rm -f ~/aio-restore-temp.tar.gz"
run "Pruning pnpm store" "proot-distro login ubuntu -- bash -c 'rm -rf /root/.local/share/pnpm/store'"
run "Clearing apt cache" "proot-distro login ubuntu -- bash -c 'apt clean && rm -rf /var/lib/apt/lists/*'"
run "Clearing npm cache" "proot-distro login ubuntu -- bash -c 'npm cache clean --force'"
run "Removing old logs" "proot-distro login ubuntu -- bash -c 'rm -f /root/AIOStreams/install.log /root/AIOStreams/build-*.log'"

# -- Step 7: verify --
step_header "Verifying installation"
run "Checking project files" "proot-distro login ubuntu -- bash -c 'test -f /root/AIOStreams/package.json'"
run "Checking Node.js" "proot-distro login ubuntu -- bash -c 'node -v'"
run "Checking pnpm" "proot-distro login ubuntu -- bash -c 'pnpm -v'"

rm -f "$STATE_FILE"

echo ""
echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
echo ""
echo -e "  ${BOLD}To start AIOStreams:${RESET}"
echo "    proot-distro login ubuntu"
echo "    cd /root/AIOStreams && pnpm start"
echo ""
echo -e "  ${BOLD}To expose it (separate session):${RESET}"
echo "    proot-distro login ubuntu"
echo "    cloudflared tunnel run <your-tunnel-name>"
echo ""
