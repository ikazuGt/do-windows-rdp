#!/bin/bash
#
# DIGITALOCEAN INSTALLER - FINAL DEBUG VERSION
# Date: 2025-11-24
# Fixes: Ethernet Instance 0 priority, DNS locking, Verbose Logging
#

# --- LOGGING FUNCTIONS ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS INSTALLER - FINAL LOGGING VERSION        "
echo "===================================================="

# --- 1. INSTALL DEPENDENCIES ---
log_step "STEP 1: Installing Dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y ntfs-3g parted psmisc curl wget jq || { log_error "Failed to install tools"; exit 1; }

# --- 2. DOWNLOAD CHROME ---
log_step "STEP 2: Pre-downloading Chrome"
wget -q --show-progress --progress=bar:force -O /tmp/chrome.msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
[ -s "/tmp/chrome.msi" ] && log_success "Chrome downloaded." || { log_error "Chrome download failed."; exit 1; }

# --- 3. OS SELECTION ---
log_step "STEP 3: Select Operating System"
echo "  1) Windows 2019 (Cloudflare R2 Recommended)"
echo "  2) Windows 2019 (Mediafire [Faster])"
echo "  3) Windows 2016 (Cloudflare R2)"
echo "  4) Windows 2012 (Mediafire)"
echo "  5) Windows 10 Super Lite SF"
echo "  6) Windows 10 Super Lite MF"
echo "  7) Windows 10 Super Lite CF"
echo "  8) Windows 11 Normal"
echo "  9) Windows 10 Normal"
echo "  10) Custom Link"
read -p "Select [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://pub-24c03f7a3eff4fa6936c33e2474d6905.r2.dev/windows2019DO.gz";;
  2) PILIHOS="https://download1590.mediafire.com/azuel5cj7mhgGPHrF3ASzRk9obFoHx3_b-ICHzMjNCT4djMsZYjJROTESlZtyvdFqZsIVLEOG0CRtVRDZBI50a-7PQh03U5ZQnkDqn_EUKsC0e85BbaQLv0F8mZmdUw2fic4GgweHa2DjA1Z6KpmjOWPq64-pWx9ouwDQ59s_4Fx/5bnp3aoc7pi7jl9/windows2019DO.gz";;
  3) PILIHOS="https://pub-4e34d7f04a65410db003c8e1ef00b82a.r2.dev/windows2016.gz";;
  4) PILIHOS="https://download853.mediafire.com/tuef8sbhwspgl_zR6OK3WVrfalwkExPoAVtac6ergZ-7qPAqhpTuMW1HZgilIYT8aPHGCcQT1YcK0twtGdysR-Fb8uM286e4Wh-DBNfnBRHEiP6sjpXGgzCrf554RkATdx9zsFwloJNrlXcG_j2uZJWC-_FzR6Dq2P5gtB2dg7LNZiUD/i2d5cf30xo4ikzz/windows2012.gz";;
  5) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  6) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  7) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  8) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  9) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win10_en.gz";;
  10) read -p "Enter Direct Link: " PILIHOS;;
  *) log_error "Invalid selection"; exit 1;;
esac

# --- 4. NETWORK DETECTION ---
log_step "STEP 4: Calculating Network Settings"

# Get the raw IP info (excluding local loopback and internal Docker/Private IPs)
RAW_DATA=$(ip -4 -o addr show | awk '{print $4}' | grep -v "^10\." | grep -v "^127\." | head -n1)
CLEAN_IP=${RAW_DATA%/*}
CLEAN_PREFIX=${RAW_DATA#*/}
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

# Gateway Failsafe
if [ -z "$GW" ] || [[ "$GW" == "0.0.0.0" ]]; then
    log_error "No gateway detected via route."
    IP_BASE=$(echo "$CLEAN_IP" | cut -d. -f1-3)
    GW="${IP_BASE}.1"
    log_success "Calculated Gateway: $GW"
fi

# Netmask Calculation
case "$CLEAN_PREFIX" in
    8) SUBNET_MASK="255.0.0.0";;
    16) SUBNET_MASK="255.255.0.0";;
    20) SUBNET_MASK="255.255.240.0";;
    22) SUBNET_MASK="255.255.252.0";;
    24) SUBNET_MASK="255.255.255.0";;
    25) SUBNET_MASK="255.255.255.128";;
    26) SUBNET_MASK="255.255.255.192";;
    27) SUBNET_MASK="255.255.255.224";;
    28) SUBNET_MASK="255.255.255.240";;
    *) SUBNET_MASK="255.255.255.0";; # Default fallback
esac

echo "   ---------------------------"
echo "   IP             : $CLEAN_IP"
echo "   Subnet Mask    : $SUBNET_MASK"
echo "   Gateway        : $GW"
echo "   ---------------------------"

if [[ "$CLEAN_IP" == *"/"* ]] || [ -z "$CLEAN_IP" ]; then
    log_error "IP Detection Failed. Exiting to prevent bricking."
    exit 1
fi

read -p "Look correct? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then exit 1; fi

# --- 5. GENERATE BATCH FILE (THE FIX) ---
log_step "STEP 5: Generating Windows Setup Script"

cat > /tmp/win_setup.bat << 'EOFBATCH'
@ECHO OFF
SETLOCAL EnableDelayedExpansion

REM ============================================
REM    WINDOWS SETUP - VERBOSE LOGGING
REM ============================================

SET IP=PLACEHOLDER_IP
SET MASK=PLACEHOLDER_MASK
SET GW=PLACEHOLDER_GW

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
ECHO.
ECHO [LOG] Detecting Network Adapter...
SET ADAPTER_NAME=

REM CHECK 1: Look specifically for "Ethernet Instance 0" (The one that works)
netsh interface show interface name="Ethernet Instance 0" >nul 2>&1
if %errorlevel% EQU 0 (
    SET "ADAPTER_NAME=Ethernet Instance 0"
    ECHO [SUCCESS] Found Priority Adapter: Ethernet Instance 0
    goto :configure_network
)

REM CHECK 2: Look specifically for just "Ethernet"
netsh interface show interface name="Ethernet" >nul 2>&1
if %errorlevel% EQU 0 (
    SET "ADAPTER_NAME=Ethernet"
    ECHO [SUCCESS] Found Standard Adapter: Ethernet
    goto :configure_network
)

REM CHECK 3: Fallback Loop (Take the FIRST connected one and STOP)
ECHO [DEBUG] Specific names not found. Scanning list...
for /f "tokens=3*" %%a in ('netsh interface show interface ^| findstr /C:"Connected"') do (
    SET "ADAPTER_NAME=%%b"
    ECHO [DEBUG] Discovered Adapter: !ADAPTER_NAME!
    goto :configure_network
)

:configure_network
if "%ADAPTER_NAME%"=="" (
    ECHO [CRITICAL ERROR] No network adapter found!
    goto :keep_open
)

ECHO [LOG] Selected Adapter: "%ADAPTER_NAME%"

REM --- APPLY IP ---
ECHO.
ECHO [LOG] Applying IP Address...
netsh interface ip set address name="%ADAPTER_NAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1
if %errorlevel% EQU 0 (
    ECHO [SUCCESS] IP Applied.
) else (
    ECHO [ERROR] Failed to set IP. Retrying with PowerShell...
    powershell -Command "New-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -IPAddress %IP% -PrefixLength 24 -DefaultGateway %GW%"
)

timeout /t 2 /nobreak >nul

REM --- APPLY DNS ---
ECHO.
ECHO [LOG] Applying DNS Settings...
netsh interface ip set dns name="%ADAPTER_NAME%" source=static addr=8.8.8.8
netsh interface ip add dns name="%ADAPTER_NAME%" addr=8.8.4.4 index=2

REM Double check with PowerShell (Force it)
powershell -Command "Set-DnsClientServerAddress -InterfaceAlias '%ADAPTER_NAME%' -ServerAddresses 8.8.8.8,8.8.4.4" >nul 2>&1

ECHO [LOG] Flushing DNS Cache...
ipconfig /flushdns

REM --- TEST NETWORK ---
ECHO.
ECHO [LOG] Testing Connection to Google...
ping -n 2 8.8.8.8
if %errorlevel% EQU 0 (
    ECHO [SUCCESS] Internet Connected!
) else (
    ECHO [WARNING] Ping failed. RDP might still work if IP is set.
)

REM --- DISK EXTENSION ---
ECHO.
ECHO [LOG] Extending Disk Partitions...
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
ECHO [SUCCESS] Disk Extended.

REM --- ENABLE RDP ---
ECHO.
ECHO [LOG] Enabling Remote Desktop (RDP)...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >nul
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >nul
netsh advfirewall firewall add rule name="RDP_3389" dir=in action=allow protocol=TCP localport=3389 >nul
ECHO [SUCCESS] RDP Enabled on Port 3389.

REM --- INSTALL CHROME ---
ECHO.
if exist "C:\chrome.msi" (
    ECHO [LOG] Installing Google Chrome...
    start /wait msiexec /i "C:\chrome.msi" /quiet /norestart
    del /f /q C:\chrome.msi
    ECHO [SUCCESS] Chrome Installed.
) else (
    ECHO [INFO] Chrome installer not found, skipping.
)

ECHO.
ECHO ===========================================
ECHO      SETUP COMPLETE
ECHO ===========================================
ECHO IP Address: %IP%
ECHO Username  : Administrator
ECHO.

:keep_open
ECHO [LOG] This window will stay open for debugging.
ECHO Press any key to close and delete this script...
pause >nul
del /f /q "%~f0"
exit
EOFBATCH

# Inject Bash Variables into Batch File
sed -i "s/PLACEHOLDER_IP/$CLEAN_IP/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_MASK/$SUBNET_MASK/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_GW/$GW/g" /tmp/win_setup.bat

log_success "Batch script created with debug logs."

# --- 6. WRITE IMAGE ---
log_step "STEP 6: Writing OS to Disk"
umount -f /dev/vda* 2>/dev/null
if echo "$PILIHOS" | grep -qiE '\.gz($|\?)'; then
  wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
else
  wget --no-check-certificate -O- "$PILIHOS" | dd of=/dev/vda bs=4M status=progress
fi
sync
sleep 3

# --- 7. PARTITION & MOUNT ---
log_step "STEP 7: Mounting Windows Partition"
partprobe /dev/vda
sleep 5

TARGET=""
for i in {1..10}; do
    if [ -b /dev/vda2 ]; then TARGET="/dev/vda2"; break; fi
    if [ -b /dev/vda1 ]; then TARGET="/dev/vda1"; break; fi
    echo "   Searching for partition... ($i/10)"
    sleep 2
    partprobe /dev/vda
done
[ -z "$TARGET" ] && { log_error "Partition not found."; exit 1; }

log_info "Partition Found: $TARGET. Fixing NTFS..."
ntfsfix -d "$TARGET" > /dev/null 2>&1

mkdir -p /mnt/windows
mount.ntfs-3g -o remove_hiberfile,rw "$TARGET" /mnt/windows || mount.ntfs-3g -o force,rw "$TARGET" /mnt/windows

# --- 8. INJECT FILES ---
log_step "STEP 8: Injecting Setup Files"
PATH_ALL_USERS="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
PATH_ADMIN="/mnt/windows/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
mkdir -p "$PATH_ALL_USERS" "$PATH_ADMIN"

cp -v /tmp/chrome.msi /mnt/windows/chrome.msi
cp -f /tmp/win_setup.bat "$PATH_ALL_USERS/win_setup.bat"
cp -f /tmp/win_setup.bat "$PATH_ADMIN/win_setup.bat"

log_success "Files injected"

# --- 9. FINISH ---
log_step "STEP 9: Cleaning Up"
sync
umount /mnt/windows

echo "===================================================="
echo "       INSTALLATION SUCCESSFUL!                     "
echo "===================================================="
echo " 1. Droplet is powering off NOW"
echo " 2. Turn OFF Recovery Mode in DigitalOcean Panel"
echo " 3. Power ON the droplet"
echo " 4. Open Recovery Console (VNC) to see logs"
echo " 5. Connect RDP to: $CLEAN_IP"
echo "===================================================="
sleep 5
poweroff
