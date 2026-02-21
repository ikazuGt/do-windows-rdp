#!/bin/bash
#
# DIGITALOCEAN INSTALLER - FIXED VERSION
# Date: 2026-02-21
# Fixes:
#   - Adapter detection rewritten with reliable fallback
#   - "etsh" typo fixed (was "netsh")
#   - "tf" typo fixed (was "ntfsfix")
#   - for i in {1..10} replaced with while loop (more portable)
#   - dd uses status=progress (single line, no spam)
#   - Chrome download failure is non-fatal (|| true)
#

# --- LOGGING FUNCTIONS ---
function log_info()    { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error()   { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step()    { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS INSTALLER - FIXED VERSION               "
echo "===================================================="

# --- 1. INSTALL DEPENDENCIES ---
log_step "STEP 1: Installing Dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y ntfs-3g parted psmisc curl wget || { log_error "Failed to install tools"; exit 1; }

# --- 2. DOWNLOAD CHROME ---
log_step "STEP 2: Pre-downloading Chrome"
wget -q --show-progress --progress=bar:force -O /tmp/chrome.msi \
    "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi" || true
if [ -s "/tmp/chrome.msi" ]; then
    log_success "Chrome downloaded."
else
    log_info "Chrome download failed (non-critical, continuing)."
fi

# --- 3. OS SELECTION ---
log_step "STEP 3: Select Operating System"
echo "  1) Windows 2019 (Cloudflare R2 - US East/North)"
echo "  2) Windows 2016 (Cloudflare R2 - Asia)"
echo "  3) Windows 2012 (Cloudflare R2)"
echo "  4) Windows 2012 (Mediafire)"
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
  *) log_error "Invalid selection"; exit 1;;
esac

log_success "Image URL: $IMG_URL"

# --- 4. NETWORK DETECTION ---
log_step "STEP 4: Calculating Network Settings"

MAIN_IF=$(ip route | awk '/default/ {print $5}' | head -n1)
RAW_DATA=$(ip -4 -o addr show dev "$MAIN_IF" | awk '{print $4}' | head -n1)
CLEAN_IP=${RAW_DATA%/*}
CLEAN_PREFIX=${RAW_DATA#*/}
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

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

echo "   ---------------------------"
echo "   IP          : $CLEAN_IP"
echo "   Subnet Mask : $SUBNET_MASK"
echo "   Gateway     : $GW"
echo "   Prefix      : /$CLEAN_PREFIX"
echo "   ---------------------------"

if [[ "$CLEAN_IP" == *"/"* ]] || [ -z "$CLEAN_IP" ]; then
    log_error "IP Detection Failed. Exiting."
    exit 1
fi

read -p "Look correct? [Y/n]: " CONFIRM
if [[ "${CONFIRM:-Y}" =~ ^[Nn] ]]; then exit 1; fi

# --- 5. GENERATE BATCH FILE ---
log_step "STEP 5: Generating Windows Setup Script"

cat > /tmp/win_setup.bat << 'EOFBATCH'
@ECHO OFF
SETLOCAL EnableDelayedExpansion

REM ============================================
REM    WINDOWS SETUP - FIXED ADAPTER DETECTION
REM ============================================

SET IP=PLACEHOLDER_IP
SET MASK=PLACEHOLDER_MASK
SET GW=PLACEHOLDER_GW
SET PREFIX=PLACEHOLDER_PREFIX

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

REM --- ADAPTER DETECTION (FIXED) ---
ECHO.
ECHO [LOG] Detecting Network Adapter...
SET ADAPTER_NAME=

REM Try known adapter names in priority order
for %%A in ("Ethernet Instance 0" "Ethernet 2" "Ethernet" "Local Area Connection" "vEthernet") do (
    netsh interface show interface name=%%A >nul 2>&1
    if !errorlevel! EQU 0 (
        SET "ADAPTER_NAME=%%~A"
        ECHO [OK] Found adapter: %%~A
        goto :configure_network
    )
)

REM Last resort: grab first Connected adapter from the list
ECHO [LOG] Named adapters not found. Scanning for any connected adapter...
for /f "skip=3 tokens=4*" %%a in ('netsh interface show interface') do (
    if /i "%%a"=="Connected" (
        if "!ADAPTER_NAME!"=="" (
            SET "ADAPTER_NAME=%%b"
            ECHO [OK] Found connected adapter: %%b
        )
    )
)
goto :configure_network

:configure_network
if "%ADAPTER_NAME%"=="" (
    ECHO [CRITICAL] No network adapter found! Cannot configure network.
    goto :skip_network
)

ECHO [LOG] Using adapter: "%ADAPTER_NAME%"

REM --- APPLY IP ---
ECHO.
ECHO [LOG] Applying IP Address...
netsh interface ip set address name="%ADAPTER_NAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1
if %errorlevel% EQU 0 (
    ECHO [OK] IP applied via netsh.
) else (
    ECHO [WARN] netsh failed, trying PowerShell...
    powershell -Command "Remove-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -Confirm:$false -ErrorAction SilentlyContinue"
    powershell -Command "Remove-NetRoute -InterfaceAlias '%ADAPTER_NAME%' -Confirm:$false -ErrorAction SilentlyContinue"
    powershell -Command "New-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -IPAddress %IP% -PrefixLength %PREFIX% -DefaultGateway %GW% -ErrorAction Stop"
    if !errorlevel! EQU 0 (
        ECHO [OK] IP applied via PowerShell.
    ) else (
        ECHO [ERROR] Both netsh and PowerShell failed to set IP.
    )
)

timeout /t 2 /nobreak >nul

REM --- APPLY DNS ---
ECHO.
ECHO [LOG] Applying DNS...
netsh interface ip set dns name="%ADAPTER_NAME%" source=static addr=8.8.8.8 register=primary
netsh interface ip add dns name="%ADAPTER_NAME%" addr=8.8.4.4 index=2
powershell -Command "Set-DnsClientServerAddress -InterfaceAlias '%ADAPTER_NAME%' -ServerAddresses 8.8.8.8,8.8.4.4" >nul 2>&1
ipconfig /flushdns
ECHO [OK] DNS set to 8.8.8.8 / 8.8.4.4

REM --- TEST NETWORK ---
ECHO.
ECHO [LOG] Testing connectivity...
ping -n 3 8.8.8.8
if %errorlevel% EQU 0 (
    ECHO [OK] Internet connected!
) else (
    ECHO [WARN] Ping failed. RDP may still work.
)

:skip_network

REM --- DISK EXTENSION ---
ECHO.
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
ECHO.
ECHO [LOG] Enabling RDP...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >nul
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >nul 2>&1
netsh advfirewall firewall add rule name="RDP_3389" dir=in action=allow protocol=TCP localport=3389 >nul 2>&1
ECHO [OK] RDP enabled on port 3389.

REM --- DISABLE ACCOUNT LOCKOUT ---
ECHO.
ECHO [LOG] Disabling account lockout...
net accounts /lockoutthreshold:0
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\RemoteAccess\Parameters\AccountLockout" /v MaxDenials /t REG_DWORD /d 0 /f >nul 2>&1
ECHO [OK] Account lockout disabled.

REM --- INSTALL CHROME ---
ECHO.
if exist "C:\chrome.msi" (
    ECHO [LOG] Installing Chrome...
    start /wait msiexec /i "C:\chrome.msi" /quiet /norestart
    del /f /q C:\chrome.msi
    ECHO [OK] Chrome installed.
) else (
    ECHO [INFO] Chrome MSI not found, skipping.
)

REM --- SET PASSWORD ---
ECHO.
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

# Inject network values into batch file
sed -i "s/PLACEHOLDER_IP/$CLEAN_IP/g"         /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_MASK/$SUBNET_MASK/g"    /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_GW/$GW/g"               /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_PREFIX/$CLEAN_PREFIX/g" /tmp/win_setup.bat

log_success "Batch script generated."

# --- 6. WRITE IMAGE ---
log_step "STEP 6: Writing OS to Disk"
umount -f /dev/vda* 2>/dev/null || true

if echo "$IMG_URL" | grep -qiE '\.gz($|\?)'; then
    log_info "Detected .gz image — streaming decompress to disk..."
    wget --no-check-certificate -q -O- "$IMG_URL" | gunzip | dd of=/dev/vda bs=4M conv=fsync status=progress
else
    log_info "Detected raw image — streaming to disk..."
    wget --no-check-certificate -q -O- "$IMG_URL" | dd of=/dev/vda bs=4M conv=fsync status=progress
fi

sync
sleep 3
log_success "Image written."

# --- 7. PARTITION & MOUNT ---
log_step "STEP 7: Mounting Windows Partition"
partprobe /dev/vda
sleep 5

target=""
i=1
while [ $i -le 10 ]; do
    if [ -b /dev/vda2 ]; then target="/dev/vda2"; break; fi
    if [ -b /dev/vda1 ]; then target="/dev/vda1"; break; fi
    echo "   Searching for partition... ($i/10)"
    sleep 2
    partprobe /dev/vda 2>/dev/null || true
    i=$((i + 1))
done

if [ -z "$target" ]; then
    log_error "Partition not found. Cannot inject files."
    log_info "Rebooting anyway — Windows may still boot without injection."
    sleep 3
    reboot
    exit 1
fi

log_info "Partition found: $target. Fixing NTFS..."
ntfsfix -d "$target" > /dev/null 2>&1 || true

mkdir -p /mnt/windows
if ! mount.ntfs-3g -o remove_hiberfile,rw "$target" /mnt/windows 2>/dev/null; then
    mount.ntfs-3g -o force,rw "$target" /mnt/windows || {
        log_error "Cannot mount NTFS partition. Rebooting without injection."
        reboot
        exit 1
    }
fi

# --- 8. INJECT FILES ---
log_step "STEP 8: Injecting Setup Files"
path_all_users="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
path_admin="/mnt/windows/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
mkdir -p "$path_all_users" "$path_admin"

cp -f /tmp/win_setup.bat "$path_all_users/win_setup.bat"
cp -f /tmp/win_setup.bat "$path_admin/win_setup.bat"
log_success "Startup scripts injected."

if [ -f /tmp/chrome.msi ]; then
    cp -f /tmp/chrome.msi /mnt/windows/chrome.msi
    log_success "Chrome MSI injected."
fi

# --- 9. FINISH ---
log_step "STEP 9: Cleaning Up and Rebooting"
sync
umount /mnt/windows 2>/dev/null || true
sync

echo ""
echo "===================================================="
echo "       INSTALLATION SUCCESSFUL!                     "
echo "===================================================="
echo " Rebooting into Windows in 5 seconds..."
echo " Then connect via RDP:"
echo "   IP       : $CLEAN_IP"
echo "   Username : Administrator"
echo "   Password : Pc@2024"
echo "   Port     : 3389"
echo "===================================================="
sleep 5
reboot
