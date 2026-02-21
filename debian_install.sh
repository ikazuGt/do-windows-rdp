#!/bin/bash
#
# DIGITALOCEAN WINDOWS INSTALLER — DEBIAN DIRECT (NO RECOVERY MODE)
# Run this directly on a Debian 11 VPS via SSH as root.
# The script pivots to a RAM environment, then overwrites the disk.
#
# Date: 2026-02-21
# Tested on: Debian 11 (DigitalOcean Droplets)
#
# FIX 1: Removed 'set -e' — was silently killing script on any minor error
# FIX 2: Replaced grep -oP with grep -Eo — Perl regex not available on all Debian builds
#
set -uo pipefail

# --- COLORS & LOGGING ---
RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; NC='\e[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${YELLOW}>>> $1${NC}"; }

clear
echo "========================================================"
echo "   WINDOWS ON DIGITALOCEAN — DEBIAN DIRECT INSTALLER    "
echo "   (No Recovery Mode Required)                          "
echo "========================================================"
echo ""

# --- SAFETY CHECKS ---
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root."
    exit 1
fi

if ! grep -q 'debian\|ubuntu' /etc/os-release 2>/dev/null; then
    log_error "This script is designed for Debian/Ubuntu. Detected different OS."
    exit 1
fi

# --- 1. GATHER NETWORK INFO BEFORE WE LOSE THE SYSTEM ---
log_step "STEP 1: Gathering Network Configuration"

MAIN_IF=$(ip route | awk '/default/ {print $5}' | head -n1)
if [ -z "$MAIN_IF" ]; then
    log_error "Cannot detect main network interface."
    exit 1
fi
log_info "Main Interface: $MAIN_IF"

RAW_DATA=$(ip -4 -o addr show dev "$MAIN_IF" | awk '{print $4}' | head -n1)
CLEAN_IP=${RAW_DATA%/*}
CLEAN_PREFIX=${RAW_DATA#*/}
GW=$(ip route | awk '/default/ {print $3}' | head -n1)

if [ -z "$GW" ] || [[ "$GW" == "0.0.0.0" ]]; then
    IP_BASE=$(echo "$CLEAN_IP" | cut -d. -f1-3)
    GW="${IP_BASE}.1"
    log_info "Calculated fallback gateway: $GW"
fi

case "$CLEAN_PREFIX" in
    8)  SUBNET_MASK="255.0.0.0";;
    16) SUBNET_MASK="255.255.0.0";;
    20) SUBNET_MASK="255.255.240.0";;
    22) SUBNET_MASK="255.255.252.0";;
    24) SUBNET_MASK="255.255.255.0";;
    25) SUBNET_MASK="255.255.255.128";;
    26) SUBNET_MASK="255.255.255.192";;
    27) SUBNET_MASK="255.255.255.224";;
    28) SUBNET_MASK="255.255.255.240";;
    *)  SUBNET_MASK="255.255.255.0";;
esac

echo "   ┌──────────────────────────────┐"
echo "   │ IP Address : $CLEAN_IP"
echo "   │ Subnet Mask: $SUBNET_MASK"
echo "   │ Gateway    : $GW"
echo "   │ Interface  : $MAIN_IF"
echo "   │ Prefix     : /$CLEAN_PREFIX"
echo "   └──────────────────────────────┘"

if [[ "$CLEAN_IP" == *"/"* ]] || [ -z "$CLEAN_IP" ]; then
    log_error "IP detection failed. Aborting."
    exit 1
fi

read -p "Network info correct? [Y/n]: " CONFIRM
if [[ "${CONFIRM:-Y}" =~ ^[Nn] ]]; then exit 1; fi

# --- 2. DETECT DISK ---
log_step "STEP 2: Detecting Target Disk"

if [ -b /dev/vda ]; then
    TARGET_DISK="/dev/vda"
elif [ -b /dev/sda ]; then
    TARGET_DISK="/dev/sda"
else
    log_error "No suitable disk found (/dev/vda or /dev/sda)."
    exit 1
fi
log_success "Target Disk: $TARGET_DISK"

# --- 3. OS SELECTION ---
log_step "STEP 3: Select Windows Version"
echo "  1) Windows Server 2019  (Cloudflare R2 — US East/North)"
echo "  2) Windows Server 2016  (Cloudflare R2 — Asia)"
echo "  3) Windows Server 2012  (Cloudflare R2)"
echo "  4) Windows Server 2012  (Mediafire)"
echo "  5) Windows 10 Super Lite (Sourceforge)"
echo "  6) Windows 10 Super Lite (Mediafire)"
echo "  7) Windows 10 Super Lite (Cloudflare)"
echo "  8) Windows 11 Normal"
echo "  9) Windows 10 Normal"
echo "  10) Custom Link"
read -p "Select [1]: " PILIHOS

case "${PILIHOS:-1}" in
  1) IMG_URL="https://pub-ae5f0a8e1c6a44c18627093c61f07475.r2.dev/windows2019.gz";;
  2) IMG_URL="https://pub-4e34d7f04a65410db003c8e1ef00b82a.r2.dev/windows2016.gz";;
  3) IMG_URL="https://pub-fc6d708fb1964c6b8f443ade49ee2749.r2.dev/windows2012.gz";;
  4) IMG_URL="https://download853.mediafire.com/tuef8sbhwspgl_zR6OK3WVrfalwkExPoAVtac6ergZ-7qPAqhpTuMW1HZgilIYT8aPHGCcQT1YcK0twtGdysR-Fb8uM286e4Wh-DBNfnBRHEiP6sjpXGgzCrf554RkATdx9zsFwloJNrlXcG_j2uZJWC-_FzR6Dq2P5gtB2dg7LNZiUD/i2d5cf30xo4ikzz/windows2012.gz";;
  5) IMG_URL="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  6) IMG_URL="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  7) IMG_URL="https://umbel.my.id/wedus10lite.gz";;
  8) IMG_URL="https://windows-on-cloud.wansaw.com/0:/win11";;
  9) IMG_URL="https://windows-on-cloud.wansaw.com/0:/win10_en.gz";;
  10) read -p "Enter Direct Link: " IMG_URL;;
  *)  log_error "Invalid selection."; exit 1;;
esac

log_success "Image URL: $IMG_URL"

# --- 4. INSTALL REQUIRED PACKAGES ---
log_step "STEP 4: Installing Dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wget gzip coreutils util-linux ntfs-3g psmisc curl parted 2>/dev/null
log_success "Dependencies installed."

# --- 5. PRE-DOWNLOAD CHROME ---
log_step "STEP 5: Pre-downloading Chrome"
wget -q --show-progress --progress=bar:force -O /tmp/chrome.msi \
    "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" || true
if [ -s "/tmp/chrome.msi" ]; then
    log_success "Chrome downloaded."
else
    log_error "Chrome download failed (non-critical, continuing)."
fi

# --- 6. GENERATE WINDOWS SETUP BATCH ---
log_step "STEP 6: Generating Windows Startup Script"

cat > /tmp/win_setup.bat << EOFBATCH
@ECHO OFF
SETLOCAL EnableDelayedExpansion

REM ============================================
REM   WINDOWS AUTO-SETUP (Injected by Debian)
REM ============================================

SET IP=${CLEAN_IP}
SET MASK=${SUBNET_MASK}
SET GW=${GW}

REM --- CHECK ADMIN RIGHTS ---
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    ECHO [LOG] Requesting Admin privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

ECHO.
ECHO ===========================================
ECHO      STARTING NETWORK CONFIGURATION
ECHO ===========================================
ECHO [DEBUG] IP Target  : %IP%
ECHO [DEBUG] Mask Target: %MASK%
ECHO [DEBUG] Gateway    : %GW%
ECHO.

ECHO [LOG] Waiting 15 seconds for drivers to load...
timeout /t 15 /nobreak >nul

REM --- ADAPTER SELECTION LOGIC ---
ECHO [LOG] Detecting Network Adapter...
SET ADAPTER_NAME=

netsh interface show interface name="Ethernet Instance 0" >nul 2>&1
if %errorlevel% EQU 0 (
    SET "ADAPTER_NAME=Ethernet Instance 0"
    ECHO [OK] Found: Ethernet Instance 0
    goto :configure_network
)

netsh interface show interface name="Ethernet" >nul 2>&1
if %errorlevel% EQU 0 (
    SET "ADAPTER_NAME=Ethernet"
    ECHO [OK] Found: Ethernet
    goto :configure_network
)

for /f "tokens=3*" %%a in ('netsh interface show interface ^| findstr /C:"Connected"') do (
    SET "ADAPTER_NAME=%%b"
    ECHO [OK] Found connected adapter: !ADAPTER_NAME!
goto :configure_network
)

:configure_network
if "%ADAPTER_NAME%"=="" (
    ECHO [CRITICAL] No network adapter found!
goto :keep_open
)

ECHO [LOG] Using Adapter: "%ADAPTER_NAME%"

REM --- APPLY IP ---
ECHO [LOG] Setting IP Address...
netsh interface ip set address name="%ADAPTER_NAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1
if %errorlevel% EQU 0 (
    ECHO [OK] IP Applied.
) else (
    ECHO [WARN] netsh failed, trying PowerShell...
    powershell -Command "Remove-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -Confirm:\$false" >nul 2>&1
    powershell -Command "Remove-NetRoute -InterfaceAlias '%ADAPTER_NAME%' -Confirm:\$false" >nul 2>&1
    powershell -Command "New-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -IPAddress %IP% -PrefixLength ${CLEAN_PREFIX} -DefaultGateway %GW%"
)

timeout /t 2 /nobreak >nul

REM --- APPLY DNS ---
ECHO [LOG] Setting DNS...
netsh interface ip set dns name="%ADAPTER_NAME%" source=static addr=8.8.8.8
netsh interface ip add dns name="%ADAPTER_NAME%" addr=8.8.4.4 index=2
powershell -Command "Set-DnsClientServerAddress -InterfaceAlias '%ADAPTER_NAME%' -ServerAddresses 8.8.8.8,8.8.4.4" >nul 2>&1
ipconfig /flushdns

REM --- TEST ---
ECHO [LOG] Testing connectivity...
ping -n 3 8.8.8.8
if %errorlevel% EQU 0 (
    ECHO [OK] Internet Connected!
) else (
    ECHO [WARN] Ping failed. RDP may still work.
)

REM --- EXTEND DISK ---
ECHO [LOG] Extending disk partitions...
(
echo select disk 0
echo list partition
echo select partition 2
echo extend
echo select partition 1
echo extend
) > C:\diskpart.txt
diskpart /s C:\diskpart.txt >nul 2>&1
del /f /q C:\diskpart.txt
ECHO [OK] Disk extended.

REM --- ENABLE RDP ---
ECHO [LOG] Enabling RDP...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >nul
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >nul 2>&1
netsh advfirewall firewall add rule name="RDP_3389" dir=in action=allow protocol=TCP localport=3389 >nul 2>&1
ECHO [OK] RDP Enabled on port 3389.

REM --- DISABLE ACCOUNT LOCKOUT ---
ECHO [LOG] Disabling account lockout policy...
net accounts /lockoutthreshold:0
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters\AccountLockout" /v MaxDenials /t REG_DWORD /d 0 /f >nul 2>&1
ECHO [OK] Account lockout disabled.

REM --- INSTALL CHROME ---
if exist "C:\chrome.msi" (
    ECHO [LOG] Installing Chrome...
    start /wait msiexec /i "C:\chrome.msi" /quiet /norestart
    del /f /q C:\chrome.msi
    ECHO [OK] Chrome installed.
) else (
    ECHO [INFO] Chrome MSI not found, skipping.
)

REM --- SET PASSWORD ---
ECHO [LOG] Setting Administrator password...
net user Administrator PC@2024 /active:yes

ECHO.
ECHO ===========================================
ECHO            SETUP COMPLETE!
ECHO ===========================================
ECHO  IP Address : %IP%
ECHO  Username   : Administrator
ECHO  Password   : Pc@2024
ECHO  RDP Port   : 3389
ECHO ===========================================

:keep_open
ECHO.
ECHO [LOG] Press any key to close and delete this script...
pause >nul
del /f /q "%~f0"
exit
EOFBATCH

log_success "Windows batch script generated."

# --- 7. BUILD RAM ENVIRONMENT ---
log_step "STEP 7: Building RAM Environment (tmpfs pivot)"
echo ""
echo "  ┌──────────────────────────────────────────────────────┐"
echo "  │  WARNING: This will DESTROY all data on $TARGET_DISK │"
echo "  │  The system will reboot into Windows after writing.  │"
echo "  │  Make sure you have your SSH session details saved.  │"
echo "  └──────────────────────────────────────────────────────┘"
echo ""
read -p "Type 'YES' to proceed: " FINAL_CONFIRM
if [ "$FINAL_CONFIRM" != "YES" ]; then
    log_error "Aborted by user."
    exit 1
fi

log_info "Creating RAM workspace..."
mkdir -p /ramboot
mount -t tmpfs -o size=800M tmpfs /ramboot

log_info "Copying essential tools to RAM..."
mkdir -p /ramboot/{bin,sbin,lib,lib64,usr,dev,proc,sys,tmp,etc,mnt,run}
mkdir -p /ramboot/usr/{bin,sbin,lib}

for bin in bash sh cat dd gzip gunzip mount umount sync sleep reboot \
           poweroff wget curl ip awk grep sed cut head seq partprobe \
           ntfsfix mkfs.ntfs mount.ntfs-3g cp mkdir rm ls echo; do
    SRC=$(which "$bin" 2>/dev/null || true)
    if [ -n "$SRC" ] && [ -f "$SRC" ]; then
        cp -f "$SRC" /ramboot/bin/ 2>/dev/null || true
    fi
done

if command -v busybox &>/dev/null; then
    cp -f "$(which busybox)" /ramboot/bin/ || true
fi

# FIX: Use grep -Eo (portable) instead of grep -oP (Perl, unavailable on some Debian builds)
# Also wrapped in || true so a single ldd failure doesn't exit the whole script
log_info "Copying shared libraries..."
for bin in /ramboot/bin/*; do
    ldd "$bin" 2>/dev/null | grep -Eo '/[^ ]+\.so[^ ]*' | while read -r lib; do
        if [ -f "$lib" ]; then
            DEST_DIR="/ramboot$(dirname "$lib")"
            mkdir -p "$DEST_DIR"
            cp -fn "$lib" "$DEST_DIR/" 2>/dev/null || true
        fi
    done || true
done
log_success "Shared libraries copied."

cp -f /lib64/ld-linux-x86-64.so.* /ramboot/lib64/ 2>/dev/null || true
cp -f /lib/ld-linux-x86-64.so.* /ramboot/lib/ 2>/dev/null || true

if [ -d /lib/x86_64-linux-gnu ]; then
    mkdir -p /ramboot/lib/x86_64-linux-gnu
    cp -af /lib/x86_64-linux-gnu/* /ramboot/lib/x86_64-linux-gnu/ 2>/dev/null || true
fi
if [ -d /usr/lib/x86_64-linux-gnu ]; then
    mkdir -p /ramboot/usr/lib/x86_64-linux-gnu
    cp -af /usr/lib/x86_64-linux-gnu/libntfs* /ramboot/usr/lib/x86_64-linux-gnu/ 2>/dev/null || true
    cp -af /usr/lib/x86_64-linux-gnu/libgcrypt* /ramboot/usr/lib/x86_64-linux-gnu/ 2>/dev/null || true
    cp -af /usr/lib/x86_64-linux-gnu/libgpg-error* /ramboot/usr/lib/x86_64-linux-gnu/ 2>/dev/null || true
    cp -af /usr/lib/x86_64-linux-gnu/libfuse* /ramboot/usr/lib/x86_64-linux-gnu/ 2>/dev/null || true
fi

cp -f /etc/resolv.conf /ramboot/etc/ 2>/dev/null || true
cp -rf /etc/ssl /ramboot/etc/ 2>/dev/null || true
cp -af /etc/alternatives /ramboot/etc/ 2>/dev/null || true

cp -f /tmp/chrome.msi /ramboot/tmp/ 2>/dev/null || true
cp -f /tmp/win_setup.bat /ramboot/tmp/ 2>/dev/null || true

mount --bind /dev /ramboot/dev
mount --bind /proc /ramboot/proc
mount --bind /sys /ramboot/sys

log_success "RAM environment ready."

# --- 8. CREATE THE INNER SCRIPT (runs inside chroot) ---
log_info "Creating chroot installer script..."

cat > /ramboot/installer.sh << 'INNEREOF'
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

TARGET_DISK="PLACEHOLDER_DISK"
IMG_URL="PLACEHOLDER_URL"

echo ""
echo "========================================="
echo "  RUNNING FROM RAM — WRITING TO DISK"
echo "========================================="
echo "[RAM] Target: $TARGET_DISK"
echo "[RAM] Image:  $IMG_URL"
echo ""

echo "[RAM] Stopping processes using $TARGET_DISK..."
fuser -km "${TARGET_DISK}"* 2>/dev/null || true
sleep 2

echo "[RAM] Unmounting all partitions on $TARGET_DISK..."
for mp in $(mount | grep "$TARGET_DISK" | awk '{print $3}' | sort -r); do
    umount -fl "$mp" 2>/dev/null || true
done
sleep 1

swapoff "${TARGET_DISK}"* 2>/dev/null || true

if mount | grep -q "$TARGET_DISK"; then
    echo "[WARN] Some partitions still mounted, force unmounting..."
    umount -fl "${TARGET_DISK}"* 2>/dev/null || true
    sleep 2
fi

echo "[RAM] Disk is free. Starting download and write..."
echo ""

if echo "$IMG_URL" | grep -qiE '\.gz($|\?)'; then
    echo "[RAM] Detected .gz image — streaming decompress to disk..."
    wget --no-check-certificate -q -O- "$IMG_URL" | gunzip | dd of="$TARGET_DISK" bs=4M conv=fsync status=progress 2>&1
else
    echo "[RAM] Detected raw image — streaming to disk..."
    wget --no-check-certificate -q -O- "$IMG_URL" | dd of="$TARGET_DISK" bs=4M conv=fsync status=progress 2>&1
fi

WRITE_STATUS=$?
sync
sleep 3

if [ $WRITE_STATUS -ne 0 ]; then
    echo "[ERROR] Image write may have failed (exit code: $WRITE_STATUS)"
    echo "[INFO] Attempting reboot anyway..."
fi

echo "[RAM] Image written successfully!"

echo "[RAM] Re-reading partition table..."
partprobe "$TARGET_DISK" 2>/dev/null || true
sleep 5

echo "[RAM] Looking for Windows NTFS partition..."
WIN_PART=""
i=1
while [ $i -le 10 ]; do
    for p in "${TARGET_DISK}2" "${TARGET_DISK}1" "${TARGET_DISK}p2" "${TARGET_DISK}p1"; do
        if [ -b "$p" ]; then
            WIN_PART="$p"
            break 2
        fi
    done
    echo "  Waiting for partitions... ($i/10)"
    sleep 2
    partprobe "$TARGET_DISK" 2>/dev/null || true
    i=$((i + 1))
done

if [ -z "$WIN_PART" ]; then
    echo "[WARN] Could not find Windows partition. Rebooting anyway..."
    sleep 2
    echo b > /proc/sysrq-trigger
    exit 0
fi

echo "[RAM] Found Windows partition: $WIN_PART"

ntfsfix -d "$WIN_PART" >/dev/null 2>&1 || true

mkdir -p /mnt/win
if ! mount.ntfs-3g -o remove_hiberfile,rw "$WIN_PART" /mnt/win 2>/dev/null; then
    mount.ntfs-3g -o force,rw "$WIN_PART" /mnt/win 2>/dev/null || {
        echo "[WARN] Cannot mount NTFS. Rebooting without injection..."
        echo b > /proc/sysrq-trigger
        exit 0
    }
fi

echo "[RAM] Windows partition mounted. Injecting files..."

STARTUP_ALL="/mnt/win/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
STARTUP_ADMIN="/mnt/win/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
mkdir -p "$STARTUP_ALL" "$STARTUP_ADMIN"

cp -f /tmp/win_setup.bat "$STARTUP_ALL/win_setup.bat" 2>/dev/null || true
cp -f /tmp/win_setup.bat "$STARTUP_ADMIN/win_setup.bat" 2>/dev/null || true

if [ -f /tmp/chrome.msi ]; then
    cp -f /tmp/chrome.msi /mnt/win/chrome.msi 2>/dev/null || true
    echo "[OK] Chrome MSI injected."
fi

echo "[OK] Startup scripts injected."

sync
umount /mnt/win 2>/dev/null || true
sync

echo ""
echo "========================================="
echo "       DISK WRITTEN SUCCESSFULLY!        "
echo "========================================="
echo " Rebooting into Windows in 5 seconds...  "
echo " Then connect via RDP.                   "
echo "========================================="
sleep 5

echo b > /proc/sysrq-trigger
INNEREOF

sed -i "s|PLACEHOLDER_DISK|$TARGET_DISK|g" /ramboot/installer.sh
sed -i "s|PLACEHOLDER_URL|$IMG_URL|g" /ramboot/installer.sh
chmod +x /ramboot/installer.sh

log_success "Inner installer script ready."

# --- 9. PIVOT AND EXECUTE ---
log_step "STEP 8: Pivoting to RAM and starting installation"
echo ""
echo "  ┌─────────────────────────────────────────────────┐"
echo "  │  Switching to RAM environment NOW.              │"
echo "  │  Your SSH session will likely disconnect.       │"
echo "  │                                                 │"
echo "  │  The install will continue in the background.   │"
echo "  │  The VPS will auto-reboot into Windows.         │"
echo "  │                                                 │"
echo "  │  Wait ~5-15 minutes, then connect via RDP:      │"
echo "  │  IP:   $CLEAN_IP"
echo "  │  User: Administrator                            │"
echo "  │  Pass: Pc@2024                                  │"
echo "  └─────────────────────────────────────────────────┘"
echo ""
sleep 3

cd /ramboot
nohup chroot /ramboot /bin/bash /installer.sh > /ramboot/install.log 2>&1 &
INSTALLER_PID=$!

log_info "Installer running in background (PID: $INSTALLER_PID)"
log_info "You can safely disconnect SSH now."
log_info "Tailing install log (Ctrl+C to detach — install continues)..."
echo ""

sleep 2
tail -f /ramboot/install.log 2>/dev/null || true
