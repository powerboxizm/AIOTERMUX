#!/data/data/com.termux/files/usr/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

clear
echo -e "${CYAN}${BOLD}"
echo "  ================================"
echo "    AIOStreams Config Updater"
echo "  ================================"
echo -e "${RESET}"

# -- Confirm AIOStreams is actually installed before asking anything --
if ! command -v proot-distro >/dev/null 2>&1; then
  echo -e "${RED}proot-distro not found.${RESET} Run the installer first."
  exit 1
fi

if ! proot-distro login ubuntu -- bash -c "test -f /root/AIOStreams/package.json" >/dev/null 2>&1; then
  echo -e "${RED}AIOStreams not found inside the Ubuntu container.${RESET}"
  echo "Run the installer first, then come back to this script."
  exit 1
fi

echo -e "${GREEN}AIOStreams installation found.${RESET}"
echo ""

# -- Ask what to change --
read -rp "Update dashboard IP address? [Y/n]: " DO_IP
DO_IP=${DO_IP:-Y}

read -rp "Update dashboard username/password? [Y/n]: " DO_AUTH
DO_AUTH=${DO_AUTH:-Y}

if [[ ! "$DO_IP" =~ ^[Yy]$ ]] && [[ ! "$DO_AUTH" =~ ^[Yy]$ ]]; then
  echo ""
  echo "Nothing selected to update. Exiting."
  exit 0
fi

echo ""

# -- IP address --
if [[ "$DO_IP" =~ ^[Yy]$ ]]; then
  DETECTED_IP=""
  if command -v ip >/dev/null 2>&1; then
    DETECTED_IP=$(ip -4 addr show 2>/dev/null | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '127.0.0.1' | head -n1 | awk '{print $2}')
  fi

  if [ -n "$DETECTED_IP" ]; then
    echo "Detected device IP: $DETECTED_IP"
    read -rp "Use this IP for the dashboard address? [Y/n]: " USE_DETECTED
    USE_DETECTED=${USE_DETECTED:-Y}
    if [[ "$USE_DETECTED" =~ ^[Yy]$ ]]; then
      DEVICE_IP="$DETECTED_IP"
    fi
  fi

  if [ -z "$DEVICE_IP" ]; then
    read -rp "Enter the IP address other devices should use to reach this server (e.g. 192.168.1.137): " DEVICE_IP
  fi

  until [[ "$DEVICE_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
    read -rp "That doesn't look like a valid IP. Try again (e.g. 192.168.1.137): " DEVICE_IP
  done

  BASE_URL_VALUE="http://${DEVICE_IP}:3000"
fi

# -- Username/password --
if [[ "$DO_AUTH" =~ ^[Yy]$ ]]; then
  read -rp "Choose a dashboard username: " DASH_USER
  until [ -n "$DASH_USER" ]; do
    read -rp "Username can't be empty. Choose a dashboard username: " DASH_USER
  done

  read -rsp "Choose a dashboard password: " DASH_PASS
  echo ""
  until [ -n "$DASH_PASS" ]; do
    read -rsp "Password can't be empty. Choose a dashboard password: " DASH_PASS
    echo ""
  done
fi

echo ""
echo -e "${GREEN}Applying changes...${RESET}"
echo ""

if [[ "$DO_IP" =~ ^[Yy]$ ]]; then
  printf "  ${CYAN}...${RESET} Setting BASE_URL"
  if proot-distro login ubuntu -- bash -c "cd /root/AIOStreams && grep -q '^BASE_URL=' .env && sed -i 's|^BASE_URL=.*|BASE_URL=${BASE_URL_VALUE}|' .env || echo 'BASE_URL=${BASE_URL_VALUE}' >> .env" > $HOME/aio_cfg.log 2>&1; then
    printf "\r  ${GREEN}OK${RESET}  Setting BASE_URL         \n"
  else
    printf "\r  ${RED}FAIL${RESET} Setting BASE_URL         \n"
    cat $HOME/aio_cfg.log
    exit 1
  fi
fi

if [[ "$DO_AUTH" =~ ^[Yy]$ ]]; then
  printf "  ${CYAN}...${RESET} Setting dashboard credentials"
  if proot-distro login ubuntu -- bash -c "cd /root/AIOStreams && grep -q '^AIOSTREAMS_AUTH=' .env && sed -i 's|^AIOSTREAMS_AUTH=.*|AIOSTREAMS_AUTH=${DASH_USER}:${DASH_PASS}|' .env || echo 'AIOSTREAMS_AUTH=${DASH_USER}:${DASH_PASS}' >> .env" > $HOME/aio_cfg.log 2>&1; then
    printf "\r  ${GREEN}OK${RESET}  Setting dashboard credentials\n"
  else
    printf "\r  ${RED}FAIL${RESET} Setting dashboard credentials\n"
    cat $HOME/aio_cfg.log
    exit 1
  fi
fi

echo ""
echo -e "${GREEN}${BOLD}  Configuration updated!${RESET}"
echo ""
if [[ "$DO_IP" =~ ^[Yy]$ ]]; then
  echo -e "  ${BOLD}Dashboard:${RESET}  $BASE_URL_VALUE"
fi
if [[ "$DO_AUTH" =~ ^[Yy]$ ]]; then
  echo -e "  ${BOLD}Username:${RESET}   $DASH_USER"
fi
echo ""
echo -e "  ${YELLOW}Restart AIOStreams for changes to take effect:${RESET}"
echo "    proot-distro login ubuntu"
echo "    cd /root/AIOStreams && pnpm start"
echo ""
