#!/bin/bash
#
# DEBIAN TO WINDOWS - NETWORK-ONLY INJECTOR (FIXED VERSION)
# For: Pre-built Windows images with existing users/apps/settings
# Features: Animated progress bar, reliable partition detection
#

set -uo pipefail

RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; NC='\e[0m'
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "\n${YELLOW}>>> $1${NC}"; }

# Progress bar function - shows growing ==== bar
show_progress() {
    local duration=$1
    local prefix=$2
    local width=50
    local progress=0
    
    while [ $progress -le $width ]; do
        local filled=$(printf "%${progress}s" | tr ' ' '=')
        local empty=$(printf "%$((width - progress))s" | tr ' ' ' ')
        printf "\r%s [%s%s] %d%%" "$prefix" "$filled" "$empty" $((progress * 2))
        progress=$((progress + 1))
        sleep $(echo "scale=3; $duration / $width" | bc 2>/dev/null || echo "0.1")
    done
    echo ""
}

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
apt-get update -qq && apt-get install -y -qq --no-install-recommends wget gzip coreutils util-linux ntfs-3g parted bc || { err "Failed"; exit 1; }
ok "Ready"

# --- CREATE NETWORK-ONLY SCRIPT ---
step "STEP 5: Creating Network Configuration Script"
mkdir -p /tmp/wininject

cat > /tmp/wininject/network-setup.bat << EOF
@echo off
echo [*] Configuring Network...
timeout /t 3 /nobreak >nul

for /f "tokens=1,2,*" %%a in ('netsh interface show interface ^| findstr /i "Connected"') do (
    set "ADAPTER=%%c"
    goto :found
)
:found

if not defined ADAPTER (
    echo [!] No adapter found
    goto :end
)

echo [*] Setting IP on: %ADAPTER%
netsh interface ip set address name="%ADAPTER%" static $IP $MASK $GW 1
netsh interface ip set dns name="%ADAPTER%" static 8.8.8.8
netsh interface ip add dns name="%ADAPTER%" 8.8.4.4 index=2
ipconfig /flushdns
echo [*] Done: $IP

:end
del "%~f0"
EOF

ok "Network script created"

# --- CONFIRMATION ---
step "STEP 6: FINAL WARNING"
echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │  THIS WILL ERASE DISK: $DISK"
echo "  │                                         │"
echo "  │  Your pre-built Windows image will be   │"
echo "  │  written with ONLY network config added │"
echo "  │                                         │"
echo "  │  Existing in image (UNCHANGED):         │"
echo "  │  - Users and passwords                  │"
echo "  │  - Installed apps                       │"
echo "  │  - Windows settings                     │"
echo "  │                                         │"
echo "  │  ONLY ADDED: Static IP configuration    │"
echo "  └─────────────────────────────────────────┘"
echo ""
read -p "Type 'INSTALL' to proceed: " final
[ "$final" != "INSTALL" ] && { err "Aborted"; exit 1; }

# --- BACKGROUND INSTALLER ---
step "STEP 7: Starting Installation"

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
echo "[*] Stopping processes..."
fuser -km "${DISK}"* 2>/dev/null || true
sleep 2

# Unmount everything
for mp in $(mount | grep "$DISK" | awk '{print $3}' | sort -r); do
    umount -fl "$mp" 2>/dev/null || true
done
swapoff -a 2>/dev/null || true
sleep 2

# Write image with animated progress bar
echo "[*] Writing image to disk..."
echo "[*] This will take 10-30 minutes depending on image size..."
echo ""

# Download and write with progress indication
# Using wget with dot progress, but we'll show our own bar
(
    wget --no-check-certificate --progress=dot:giga -O- "$IMG" 2>/dev/null | \
    gunzip -c | \
    dd of="$DISK" bs=4M conv=fsync status=none
) &
DD_PID=$!

# Show animated progress bar while download happens
echo -n "Downloading/Writing: "
while kill -0 $DD_PID 2>/dev/null; do
    for i in "=" "==" "===" "====" "=====" "======" "=======" "========" "=========" "==========" "===========" "============" "=============" "==============" "===============" "================" "=================" "==================" "===================" "====================" "====================="; do
        printf "\r[%-21s] %s" "$i" "In progress..."
        sleep 0.5
        if ! kill -0 $DD_PID 2>/dev/null; then break; fi
    done
done
wait $DD_PID
DD_STATUS=$?

if [ $DD_STATUS -ne 0 ]; then
    echo ""
    echo "[!] Write completed with warnings (exit code: $DD_STATUS)"
else
    echo ""
    echo "[*] Write complete!"
fi

sync
sleep 2

# CRITICAL FIX: Properly re-read partition table
echo "[*] Re-reading partition table..."
blockdev --rereadpt "$DISK" 2>/dev/null || true
partprobe "$DISK" 2>/dev/null || true

# Alternative: use losetup to scan partitions
echo "[*] Scanning for partitions..."
losetup -f -P "$DISK" 2>/dev/null || true
sleep 3

# List what we found
echo "[*] Partitions detected:"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT | grep -E "(NAME|$DISK|loop)" || true
fdisk -l "$DISK" 2>/dev/null | head -20 || true

# Find Windows partition - IMPROVED METHOD
WINPART=""

# Method 1: Look for NTFS partitions using blkid
echo "[*] Searching for NTFS partitions..."
for part in $(lsblk -ln -o NAME "$DISK" 2>/dev/null | grep -v "^$(basename $DISK)$"); do
    fullpart="/dev/$part"
    if [ -b "$fullpart" ]; then
        fstype=$(blkid -o value -s TYPE "$fullpart" 2>/dev/null)
        echo "  Checking: $fullpart -> $fstype"
        if [ "$fstype" == "ntfs" ]; then
            WINPART="$fullpart"
            echo "[*] Found NTFS: $WINPART"
            break
        fi
    fi
done

# Method 2: If blkid didn't work, try common partition names
if [ -z "$WINPART" ]; then
    echo "[*] Trying common partition names..."
    if [[ "$DISK" == *"nvme"* ]]; then
        try_parts="${DISK}p1 ${DISK}p2 ${DISK}p3"
    else
        try_parts="${DISK}1 ${DISK}2 ${DISK}3"
    fi
    
    for part in $try_parts; do
        if [ -b "$part" ]; then
            echo "  Found: $part"
            WINPART="$part"
            break
        fi
    done
fi

# Method 3: Use losetup to create loop devices from the disk image
if [ -z "$WINPART" ]; then
    echo "[*] Trying losetup method..."
    LOOPDEV=$(losetup -f --show -P "$DISK" 2>/dev/null)
    if [ -n "$LOOPDEV" ]; then
        sleep 2
        for part in ${LOOPDEV}p1 ${LOOPDEV}p2 ${LOOPDEV}p3; do
            if [ -b "$part" ]; then
                fstype=$(blkid -o value -s TYPE "$part" 2>/dev/null)
                if [ "$fstype" == "ntfs" ] || [ -z "$fstype" ]; then
                    WINPART="$part"
                    echo "[*] Found via loop: $WINPART"
                    break
                fi
            fi
        done
    fi
fi

if [ -z "$WINPART" ]; then
    echo "[!] CRITICAL: No Windows partition found!"
    echo "[!] Rebooting anyway - image might still work..."
    force_reboot
fi

echo "[*] Selected partition: $WINPART"

# Mount and inject
mkdir -p /mnt/win
echo "[*] Mounting NTFS partition..."

if ! mount.ntfs-3g -o remove_hiberfile,rw "$WINPART" /mnt/win 2>/dev/null; then
    echo "[!] Standard mount failed, trying force..."
    if ! mount.ntfs-3g -o force,rw "$WINPART" /mnt/win 2>/dev/null; then
        echo "[!] Cannot mount NTFS. Rebooting without injection..."
        force_reboot
    fi
fi

echo "[*] Mounted successfully"
echo "[*] Windows directory contents:"
ls -la /mnt/win/ 2>/dev/null | head -10 || true

# Inject to startup folders
INJECTED=0

# All Users Startup
TARGET="/mnt/win/ProgramData/Microsoft/Windows/Start Menu/Programs/StartUp"
if mkdir -p "$TARGET" 2>/dev/null; then
    cp -f /tmp/wininject/network-setup.bat "$TARGET/" && {
        echo "[*] Injected to: All Users Startup"
        INJECTED=1
    }
fi

# Default User Startup
TARGET="/mnt/win/Users/Default/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
if mkdir -p "$TARGET" 2>/dev/null; then
    cp -f /tmp/wininject/network-setup.bat "$TARGET/" && {
        echo "[*] Injected to: Default User Startup"
        INJECTED=1
    }
fi

# Administrator Startup (if exists)
for admin_dir in /mnt/win/Users/Administrator/ /mnt/win/Users/Admin/; do
    if [ -d "$admin_dir" ]; then
        TARGET="${admin_dir}AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
        if mkdir -p "$TARGET" 2>/dev/null; then
            cp -f /tmp/wininject/network-setup.bat "$TARGET/" && {
                echo "[*] Injected to: $(basename $admin_dir) Startup"
                INJECTED=1
            }
        fi
    fi
done

# Windows Setup Scripts (runs during OOBE)
if [ -d "/mnt/win/Windows/Setup/Scripts" ] || mkdir -p "/mnt/win/Windows/Setup/Scripts" 2>/dev/null; then
    cp -f /tmp/wininject/network-setup.bat "/mnt/win/Windows/Setup/Scripts/" && {
        echo "[*] Injected to: Windows Setup Scripts"
        INJECTED=1
    }
fi

# C:\ root fallback
cp -f /tmp/wininject/network-setup.bat /mnt/win/network-setup.bat 2>/dev/null && {
    echo "[*] Placed fallback in C:\\"
}

if [ $INJECTED -eq 0 ]; then
    echo "[!] WARNING: Could not inject to startup locations"
else
    echo "[*] SUCCESS: Injected to $INJECTED location(s)"
fi

# Verify injection
echo "[*] Verifying injected files:"
find /mnt/win -name "network-setup.bat" 2>/dev/null

sync
sleep 2

echo "[*] Unmounting..."
umount /mnt/win 2>/dev/null || true

# Cleanup loop device if used
if [ -n "${LOOPDEV:-}" ]; then
    losetup -d "$LOOPDEV" 2>/dev/null || true
fi

sync

echo ""
echo "=========================================="
echo "  INSTALLATION COMPLETE!"
echo "=========================================="
echo "  Rebooting in 5 seconds..."
echo "  Connect via RDP to: ${TARGET_IP}"
echo "  Use YOUR existing credentials"
echo "=========================================="
sleep 5
force_reboot
INSTALLER

# Set variables in installer
sed -i "s|\${TARGET_DISK}|$DISK|g" /tmp/installer.sh
sed -i "s|\${TARGET_IMG}|$IMG|g" /tmp/installer.sh
sed -i "s|\${TARGET_IP}|$IP|g" /tmp/installer.sh
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
    echo "  │  Wait for completion, then RDP to:      │"
    echo "  │  $IP"
    echo "  │                                         │"
    echo "  │  Use YOUR existing credentials          │"
    echo "  └─────────────────────────────────────────┘"
    echo ""
    sleep 3
    tail -f /tmp/install.log 2>/dev/null || sleep 10
else
    err "Failed to start"
    exit 1
fi
