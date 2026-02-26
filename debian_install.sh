#!/bin/bash
#
# DEBIAN TO WINDOWS - NETWORK-ONLY INJECTOR
# For: Pre-built Windows images with existing users/apps/settings
# Does NOT modify: Users, Passwords, Apps, Registry settings
# ONLY injects: Network configuration for first boot
#

set -uo pipefail

RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; NC='\e[0m'
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "\n${YELLOW}>>> $1${NC}"; }

clear
echo "=================================================="
echo "  LINUX TO WINDOWS - NETWORK-ONLY INJECTOR        "
echo "  (Preserves all existing users, apps, settings)  "
echo "=================================================="
echo ""

[ "$(id -u)" -ne 0 ] && { err "Must run as root"; exit 1; }

# --- NETWORK INFO ---
step "STEP 1: Network Configuration"
MAIN_IF=$(ip route | awk '/default/ {print $5}' | head -n1)
[ -z "$MAIN_IF" ] && { err "Cannot detect network interface"; exit 1; }

IP_CIDR=$(ip -4 -o addr show dev "$MAIN_IF" | awk '{print $4}' | head -n1)
IP=${IP_CIDR%/*}
PREFIX=${IP_CIDR#*/}
GW=$(ip route | awk '/default/ {print $3}' | head -n1)

[ -z "$GW" ] && GW="$(echo "$IP" | cut -d. -f1-3).1"

case "$PREFIX" in
    8)  MASK="255.0.0.0";; 16) MASK="255.255.0.0";;
    20) MASK="255.255.240.0";; 22) MASK="255.255.252.0";;
    24) MASK="255.255.255.0";; 25) MASK="255.255.255.128";;
    26) MASK="255.255.255.192";; 27) MASK="255.255.255.224";;
    28) MASK="255.255.255.240";; *)  MASK="255.255.255.0";;
esac

echo "  Interface: $MAIN_IF"
echo "  IP:        $IP/$PREFIX"
echo "  Gateway:   $GW"
echo "  Mask:      $MASK"
read -p "Correct? [Y/n]: " confirm
[[ "${confirm:-Y}" =~ ^[Nn] ]] && exit 1

# --- DISK DETECTION ---
step "STEP 2: Target Disk"
if [ -b /dev/vda ]; then DISK="/dev/vda"
elif [ -b /dev/sda ]; then DISK="/dev/sda"
elif [ -b /dev/nvme0n1 ]; then DISK="/dev/nvme0n1"
else err "No disk found"; exit 1; fi
ok "Target: $DISK"

# --- IMAGE SELECTION ---
step "STEP 3: Windows Image Source"
echo "  1) Windows Server 2019 (Cloudflare R2)"
echo "  2) Windows Server 2016 (Cloudflare R2)"  
echo "  3) Windows Server 2012 (Cloudflare R2)"
echo "  4) Custom URL (your .gz image link)"
read -p "Select [4]: " choice

case "${choice:-4}" in
  1) IMG="https://pub-ae5f0a8e1c6a44c18627093c61f07475.r2.dev/windows2019.gz" ;;
  2) IMG="https://pub-4e34d7f04a65410db003c8e1ef00b82a.r2.dev/windows2016.gz" ;;
  3) IMG="https://pub-fc6d708fb1964c6b8f443ade49ee2749.r2.dev/windows2012.gz" ;;
  4) read -p "Enter direct .gz URL: " IMG ;;
  *) err "Invalid"; exit 1 ;;
esac
ok "Image: $IMG"

# --- INSTALL DEPS ---
step "STEP 4: Installing Tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq --no-install-recommends wget gzip coreutils util-linux ntfs-3g parted || { err "Failed"; exit 1; }
ok "Ready"

# --- CREATE NETWORK-ONLY SCRIPT ---
step "STEP 5: Creating Network Configuration Script"
mkdir -p /tmp/wininject

# This script ONLY sets IP/DNS - no user/password changes
cat > /tmp/wininject/network-setup.bat << EOF
@echo off
echo [*] Configuring Network...
timeout /t 3 /nobreak >nul

:: Find first connected adapter
for /f "tokens=1,2,*" %%a in ('netsh interface show interface ^| findstr /i "Connected"') do (
    set "ADAPTER=%%c"
    goto :found
)
:found

if not defined ADAPTER (
    echo [!] No adapter found - check drivers
    goto :end
)

echo [*] Setting static IP on: %ADAPTER%
netsh interface ip set address name="%ADAPTER%" static $IP $MASK $GW 1
if errorlevel 1 (
    echo [!] Failed to set IP - may already be configured
)

netsh interface ip set dns name="%ADAPTER%" static 8.8.8.8
netsh interface ip add dns name="%ADAPTER%" 8.8.4.4 index=2

ipconfig /flushdns
echo [*] Network configured: $IP

:end
del "%~f0"
EOF

ok "Network script created (no user/password changes)"

# --- CONFIRMATION ---
step "STEP 6: FINAL WARNING"
echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │  THIS WILL ERASE DISK: $DISK"
echo "  │                                         │"
echo "  │  Your pre-built Windows image will be   │"
echo "  │  written with ONLY network config added │"
echo "  │                                         │"
echo "  │  Existing in image:                     │"
echo "  │  - Users and passwords (UNCHANGED)      │"
echo "  │  - Installed apps (UNCHANGED)           │"
echo "  │  - Windows settings (UNCHANGED)         │"
echo "  │                                         │"
echo "  │  ONLY ADDED: Static IP configuration    │"
echo "  │                                         │"
echo "  │  After reboot, use YOUR existing        │"
echo "  │  credentials from the pre-built image   │"
echo "  └─────────────────────────────────────────┘"
echo ""
read -p "Type 'INSTALL' to proceed: " final
[ "$final" != "INSTALL" ] && { err "Aborted"; exit 1; }

# --- BACKGROUND INSTALLER ---
step "STEP 7: Starting Background Installation"

cat > /tmp/installer.sh << 'INSTALLER'
#!/bin/bash
DISK="${TARGET_DISK}"
IMG="${TARGET_IMG}"

exec > /tmp/install.log 2>&1

force_reboot() {
    sync; sleep 2
    echo b > /proc/sysrq-trigger 2>/dev/null || reboot -f
    sleep 999
}

echo "=========================================="
echo "  INSTALLER STARTED: $(date)"
echo "=========================================="

# Kill disk usage
fuser -km "${DISK}"* 2>/dev/null || true
sleep 2

# Unmount everything
for mp in $(mount | grep "$DISK" | awk '{print $3}' | sort -r); do
    umount -fl "$mp" 2>/dev/null || true
done
swapoff -a 2>/dev/null || true
sleep 2

# Write image
echo "[*] Writing image to disk..."
if ! wget --no-check-certificate --progress=dot:giga -O- "$IMG" 2>/dev/null | gunzip -c | dd of="$DISK" bs=4M status=progress conv=fsync; then
    echo "[!] Write completed with possible errors"
fi
sync
echo "[*] Write complete"

# Probe partitions
partprobe "$DISK" 2>/dev/null || true
sleep 5

# Find Windows partition
WINPART=""
for try in 1 2 3 4 5; do
    for part in "${DISK}2" "${DISK}p2" "${DISK}1" "${DISK}p1"; do
        if [ -b "$part" ] && blkid "$part" 2>/dev/null | grep -qi ntfs; then
            WINPART="$part"
            break 2
        fi
    done
    sleep 3
    partprobe "$DISK" 2>/dev/null || true
done

[ -z "$WINPART" ] && { echo "[!] No Windows partition, rebooting..."; force_reboot; }

echo "[*] Found: $WINPART"

# Mount and inject ONLY network script
mkdir -p /mnt/win
mount.ntfs-3g -o remove_hiberfile,rw "$WINPART" /mnt/win 2>/dev/null || {
    echo "[!] Cannot mount, rebooting anyway..."
    force_reboot
}

# Try multiple startup locations
INJECTED=0
for dir in "/mnt/win/ProgramData/Microsoft/Windows/Start Menu/Programs/StartUp" \
           "/mnt/win/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup" \
           "/mnt/win/Users/Default/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"; do
    if mkdir -p "$dir" 2>/dev/null; then
        cp -f /tmp/wininject/network-setup.bat "$dir/" 2>/dev/null && {
            echo "[*] Injected to: $dir"
            INJECTED=1
        }
    fi
done

# Also try Setup\Scripts for OOBE
if [ -d "/mnt/win/Windows/Setup/Scripts" ]; then
    cp -f /tmp/wininject/network-setup.bat "/mnt/win/Windows/Setup/Scripts/" 2>/dev/null && {
        echo "[*] Injected to Setup\Scripts"
        INJECTED=1
    }
fi

[ $INJECTED -eq 0 ] && echo "[!] Warning: Could not inject startup script"

sync
umount /mnt/win 2>/dev/null || true

echo "[*] Done! Rebooting..."
force_reboot
INSTALLER

# Set variables
sed -i "s|\${TARGET_DISK}|$DISK|g" /tmp/installer.sh
sed -i "s|\${TARGET_IMG}|$IMG|g" /tmp/installer.sh
chmod +x /tmp/installer.sh

# Execute with nohup
nohup bash /tmp/installer.sh > /dev/null 2>&1 &
PID=$!
disown $PID 2>/dev/null || true

sleep 2

if kill -0 $PID 2>/dev/null; then
    ok "Installer running (PID: $PID)"
    echo ""
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │  INSTALLATION IN PROGRESS               │"
    echo "  │                                         │"
    echo "  │  Log: tail -f /tmp/install.log          │"
    echo "  │                                         │"
    echo "  │  Disconnect SSH and wait ~15 minutes    │"
    echo "  │                                         │"
    echo "  │  Then connect RDP to: $IP"
    echo "  │  Use YOUR existing credentials          │"
    echo "  │  from the pre-built image               │"
    echo "  └─────────────────────────────────────────┘"
    echo ""
    sleep 3
    tail -f /tmp/install.log 2>/dev/null || sleep 10
else
    err "Failed to start"
    exit 1
fi
