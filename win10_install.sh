#!/bin/bash
#
# DIGITALOCEAN INSTALLER - WINDOWS 10 COMPATIBLE (FIXED)
# Date: 2025-12-03
# Fixes: Startup execution + partition detection
#

# --- LOGGING FUNCTIONS ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo " WINDOWS 10/11 INSTALLER - FIXED EXECUTION VERSION "
echo "===================================================="

# --- 1. INSTALL DEPENDENCIES ---
log_step "STEP 1: Installing Dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y ntfs-3g parted psmisc curl wget jq || { log_error "Failed to install tools"; exit 1; }

# --- 2. DOWNLOAD CHROME ---
log_step "STEP 2: Pre-downloading Chrome"
wget -q --show-progress --progress=bar:force -O /tmp/chrome.msi \
  "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
[ -s "/tmp/chrome.msi" ] && log_success "Chrome downloaded." || { log_error "Chrome download failed."; exit 1; }

# --- 3. OS SELECTION ---
log_step "STEP 3: Select Operating System"
echo " 1) Windows 2019 (Recommended)"
echo " 2) Windows 10 Super Lite SF"
echo " 3) Windows 10 Super Lite MF"
echo " 4) Windows 10 Super Lite CF"
echo " 5) Windows 11 Normal"
echo " 6) Windows 10 Normal"
echo " 7) Custom Link"
read -p "Select [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://download1511.mediafire.com/d5cqy0ldw0agEgtd3msbmIERkbPjRp1BQd5Y8PZSo7utKm9EPGto340rG9xkRUAo2H8lQrrL94bD7iHjdTwlVg9vKkJV0sDginBLrRTOSkEibB-ini9mpWie1wkGtsrtOL5ZRZY-qdQmqjys4EMODP41PtMjBbs6Rf5rtb8d_TGzEnRn/5bnp3aoc7pi7jl9/windows2019DO.gz";;
  2) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  3) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  4) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  5) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  6) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win10_en.gz";;
  7) read -p "Enter Direct Link: " PILIHOS;;
  *) log_error "Invalid selection"; exit 1;;
esac

# --- 4. NETWORK DETECTION ---
log_step "STEP 4: Calculating Network Settings"

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
  *) SUBNET_MASK="255.255.255.0";;
esac

echo " ---------------------------"
echo " IP          : $CLEAN_IP"
echo " Subnet Mask : $SUBNET_MASK"
echo " Gateway     : $GW"
echo " ---------------------------"

if [[ "$CLEAN_IP" == *"/"* ]] || [ -z "$CLEAN_IP" ]; then
  log_error "IP Detection Failed. Exiting to prevent bricking."
  exit 1
fi

read -p "Look correct? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
  exit 1
fi

# --- 5. GENERATE BATCH FILE (FIXED FOR AUTO-EXECUTION) ---
log_step "STEP 5: Generating Windows 10 Setup Script"

cat > /tmp/win_setup.bat << 'EOFBATCH'
@ECHO OFF
SETLOCAL EnableDelayedExpansion

REM ============================================
REM WINDOWS 10/11 SETUP - AUTO-EXECUTION FIXED
REM ============================================

SET IP=PLACEHOLDER_IP
SET MASK=PLACEHOLDER_MASK
SET GW=PLACEHOLDER_GW

REM --- CREATE LOG FILE ---
SET LOGFILE=C:\setup_log.txt
ECHO [%DATE% %TIME%] Script started >> %LOGFILE%

REM --- CHECK ADMIN RIGHTS ---
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    ECHO [LOG] Requesting Admin privileges... >> %LOGFILE%
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

ECHO. >> %LOGFILE%
ECHO =========================================== >> %LOGFILE%
ECHO STARTING NETWORK CONFIGURATION >> %LOGFILE%
ECHO =========================================== >> %LOGFILE%
ECHO [DEBUG] IP Target  : %IP% >> %LOGFILE%
ECHO [DEBUG] Mask Target: %MASK% >> %LOGFILE%
ECHO [DEBUG] Gateway    : %GW% >> %LOGFILE%
ECHO. >> %LOGFILE%

ECHO [LOG] Waiting 20 seconds for drivers to load... >> %LOGFILE%
timeout /t 20 /nobreak >nul

REM --- ADAPTER SELECTION LOGIC ---
ECHO. >> %LOGFILE%
ECHO [LOG] Detecting Network Adapter... >> %LOGFILE%
SET ADAPTER_NAME=

REM CHECK 1: Ethernet Instance 0
netsh interface show interface name="Ethernet Instance 0" >nul 2>&1
if %errorlevel% EQU 0 (
    SET "ADAPTER_NAME=Ethernet Instance 0"
    ECHO [SUCCESS] Found: Ethernet Instance 0 >> %LOGFILE%
    goto :configure_network
)

REM CHECK 2: Ethernet Instance 2
netsh interface show interface name="Ethernet Instance 2" >nul 2>&1
if %errorlevel% EQU 0 (
    SET "ADAPTER_NAME=Ethernet Instance 2"
    ECHO [SUCCESS] Found: Ethernet Instance 2 >> %LOGFILE%
    goto :configure_network
)

REM CHECK 3: Standard Ethernet
netsh interface show interface name="Ethernet" >nul 2>&1
if %errorlevel% EQU 0 (
    SET "ADAPTER_NAME=Ethernet"
    ECHO [SUCCESS] Found: Ethernet >> %LOGFILE%
    goto :configure_network
)

REM CHECK 4: Red Hat VirtIO Ethernet Adapter (Common in VPS)
for /f "tokens=3*" %%a in ('netsh interface show interface ^| findstr /C:"Connected"') do (
    SET "ADAPTER_NAME=%%b"
    ECHO [DEBUG] Auto-discovered: !ADAPTER_NAME! >> %LOGFILE%
    goto :configure_network
)

:configure_network
if "%ADAPTER_NAME%"=="" (
    ECHO [CRITICAL ERROR] No network adapter found! >> %LOGFILE%
    goto :enable_rdp
)

ECHO [LOG] Selected Adapter: "%ADAPTER_NAME%" >> %LOGFILE%

REM --- APPLY IP ADDRESS ---
ECHO. >> %LOGFILE%
ECHO [LOG] Applying IP Address... >> %LOGFILE%
netsh interface ip set address name="%ADAPTER_NAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1 >> %LOGFILE% 2>&1
if %errorlevel% EQU 0 (
    ECHO [SUCCESS] IP Applied via netsh >> %LOGFILE%
) else (
    ECHO [ERROR] netsh failed. Trying PowerShell... >> %LOGFILE%
    powershell -Command "New-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -IPAddress %IP% -PrefixLength 24 -DefaultGateway %GW% -ErrorAction SilentlyContinue" >> %LOGFILE% 2>&1
)
timeout /t 3 /nobreak >nul

REM --- APPLY DNS ---
ECHO. >> %LOGFILE%
ECHO [LOG] Applying DNS Settings... >> %LOGFILE%
netsh interface ip set dns name="%ADAPTER_NAME%" source=static addr=8.8.8.8 >> %LOGFILE% 2>&1
netsh interface ip add dns name="%ADAPTER_NAME%" addr=8.8.4.4 index=2 >> %LOGFILE% 2>&1
powershell -Command "Set-DnsClientServerAddress -InterfaceAlias '%ADAPTER_NAME%' -ServerAddresses 8.8.8.8,8.8.4.4 -ErrorAction SilentlyContinue" >> %LOGFILE% 2>&1

REM Apply to all Ethernet ports
for %%A in ("Ethernet Instance 0" "Ethernet Instance 2" "Ethernet") do (
    netsh interface show interface name=%%A >nul 2>&1
    if !errorlevel! EQU 0 (
        if NOT "%ADAPTER_NAME%"==%%A (
            netsh interface ip set dns name=%%A source=static addr=8.8.8.8 >nul 2>&1
            netsh interface ip add dns name=%%A addr=8.8.4.4 index=2 >nul 2>&1
        )
    )
)

ECHO [LOG] Flushing DNS Cache... >> %LOGFILE%
ipconfig /flushdns >nul

REM --- TEST NETWORK ---
ECHO. >> %LOGFILE%
ECHO [LOG] Testing Connection... >> %LOGFILE%
ping -n 2 8.8.8.8 >> %LOGFILE% 2>&1
if %errorlevel% EQU 0 (
    ECHO [SUCCESS] Internet Connected! >> %LOGFILE%
) else (
    ECHO [WARNING] Ping failed. Continuing anyway... >> %LOGFILE%
)

:enable_rdp
REM --- DISABLE POWER SAVING ---
ECHO. >> %LOGFILE%
ECHO [LOG] Disabling Sleep/Hibernation... >> %LOGFILE%
powercfg -change -standby-timeout-ac 0 >> %LOGFILE% 2>&1
powercfg -change -standby-timeout-dc 0 >> %LOGFILE% 2>&1
powercfg -change -hibernate-timeout-ac 0 >> %LOGFILE% 2>&1
powercfg -change -hibernate-timeout-dc 0 >> %LOGFILE% 2>&1
powercfg -h off >nul 2>&1
ECHO [SUCCESS] Power settings configured >> %LOGFILE%

REM --- ENABLE REMOTE DESKTOP ---
ECHO. >> %LOGFILE%
ECHO [LOG] Enabling Remote Desktop... >> %LOGFILE%

reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >> %LOGFILE% 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 1 /f >> %LOGFILE% 2>&1
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >> %LOGFILE% 2>&1
netsh advfirewall firewall add rule name="RDP_TCP_3389" dir=in action=allow protocol=TCP localport=3389 >> %LOGFILE% 2>&1
netsh advfirewall firewall add rule name="RDP_UDP_3389" dir=in action=allow protocol=UDP localport=3389 >> %LOGFILE% 2>&1
sc config TermService start= auto >> %LOGFILE% 2>&1
net start TermService >> %LOGFILE% 2>&1
sc config UmRdpService start= auto >> %LOGFILE% 2>&1
net start UmRdpService >> %LOGFILE% 2>&1
net localgroup "Remote Desktop Users" Administrator /add >> %LOGFILE% 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d 3389 /f >> %LOGFILE% 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f >> %LOGFILE% 2>&1

ECHO [SUCCESS] RDP Enabled >> %LOGFILE%

REM --- DISK EXTENSION ---
ECHO. >> %LOGFILE%
ECHO [LOG] Extending Disk... >> %LOGFILE%
(
    echo select disk 0
    echo list partition
    echo select partition 2
    echo extend
    echo select partition 1
    echo extend
) > C:\diskpart.txt
diskpart /s C:\diskpart.txt >> %LOGFILE% 2>&1
del /f /q C:\diskpart.txt >nul 2>&1
ECHO [SUCCESS] Disk extended >> %LOGFILE%

REM --- INSTALL CHROME ---
ECHO. >> %LOGFILE%
if exist "C:\chrome.msi" (
    ECHO [LOG] Installing Chrome... >> %LOGFILE%
    start /wait msiexec /i "C:\chrome.msi" /quiet /norestart >> %LOGFILE% 2>&1
    del /f /q C:\chrome.msi >nul 2>&1
    ECHO [SUCCESS] Chrome installed >> %LOGFILE%
)

REM --- FINAL STATUS ---
ECHO. >> %LOGFILE%
ECHO =========================================== >> %LOGFILE%
ECHO SETUP COMPLETE >> %LOGFILE%
ECHO =========================================== >> %LOGFILE%
ECHO IP: %IP% >> %LOGFILE%
ECHO User: Administrator >> %LOGFILE%
ECHO Pass: P@ssword64 >> %LOGFILE%
ECHO RDP: 3389 (NLA Enabled) >> %LOGFILE%
ECHO =========================================== >> %LOGFILE%
ECHO [%DATE% %TIME%] Script completed >> %LOGFILE%

REM --- SELF-DELETE AFTER 30 SECONDS ---
timeout /t 30 /nobreak >nul
del /f /q "%~f0" >nul 2>&1
exit
EOFBATCH

# Inject Variables
sed -i "s/PLACEHOLDER_IP/$CLEAN_IP/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_MASK/$SUBNET_MASK/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_GW/$GW/g" /tmp/win_setup.bat

log_success "Batch script generated with logging."

# --- 6. WRITE IMAGE ---
log_step "STEP 6: Writing OS to Disk (this takes 5-15 minutes)"
umount -f /dev/vda* 2>/dev/null
killall -9 dd 2>/dev/null

if echo "$PILIHOS" | grep -qiE '\.gz($|\?)'; then
  wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
else
  wget --no-check-certificate -O- "$PILIHOS" | dd of=/dev/vda bs=4M status=progress
fi

sync
sleep 5

# --- 7. PARTITION DETECTION (SIMPLIFIED) ---
log_step "STEP 7: Detecting Windows Partition"
partprobe /dev/vda
sleep 5

TARGET=""
for attempt in {1..10}; do
  log_info "Scan attempt $attempt/10..."
  
  # Try vda2 first (usually Windows C:)
  if [ -b /dev/vda2 ]; then
    TARGET="/dev/vda2"
    log_success "Found partition: /dev/vda2"
    break
  fi
  
  # Try vda1 as fallback
  if [ -b /dev/vda1 ]; then
    TARGET="/dev/vda1"
    log_success "Found partition: /dev/vda1"
    break
  fi
  
  sleep 2
  partprobe /dev/vda
done

if [ -z "$TARGET" ]; then
  log_error "Windows partition not found after 10 attempts!"
  log_info "Available partitions:"
  lsblk /dev/vda
  fdisk -l /dev/vda
  exit 1
fi

log_success "Using Windows partition: $TARGET"

# --- 8. MOUNT WITH VERIFICATION ---
log_step "STEP 8: Mounting Windows Partition"

log_info "Repairing NTFS filesystem..."
ntfsfix -d "$TARGET" 2>&1 | tee /tmp/ntfsfix.log

mkdir -p /mnt/windows

log_info "Attempting mount..."
if mount.ntfs-3g -o remove_hiberfile,rw "$TARGET" /mnt/windows; then
  log_success "Mount successful (remove_hiberfile)"
elif mount.ntfs-3g -o force,rw "$TARGET" /mnt/windows; then
  log_success "Mount successful (force)"
else
  log_error "Mount failed! Checking filesystem..."
  ntfsinfo "$TARGET" | head -20
  exit 1
fi

# Verify mount
if [ ! -d "/mnt/windows/Windows" ]; then
  log_error "Mount succeeded but Windows directory not found!"
  log_info "Mounted contents:"
  ls -la /mnt/windows/
  exit 1
fi

log_success "Windows directory verified at /mnt/windows/Windows"

# --- 9. INJECT FILES WITH VERIFICATION ---
log_step "STEP 9: Injecting Setup Files (MULTIPLE LOCATIONS)"

# Define all possible startup locations
declare -a STARTUP_PATHS=(
  "/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
  "/mnt/windows/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
  "/mnt/windows/Users/Default/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
  "/mnt/windows/Windows/System32/GroupPolicy/Machine/Scripts/Startup"
)

# Create all directories
for path in "${STARTUP_PATHS[@]}"; do
  mkdir -p "$path"
  log_info "Created: $path"
done

# Copy Chrome
log_info "Copying Chrome installer..."
cp -v /tmp/chrome.msi /mnt/windows/chrome.msi
[ -f "/mnt/windows/chrome.msi" ] && log_success "Chrome copied" || log_error "Chrome copy failed!"

# Copy batch script to ALL startup locations
SUCCESS_COUNT=0
for path in "${STARTUP_PATHS[@]}"; do
  if cp -f /tmp/win_setup.bat "$path/win_setup.bat" 2>/dev/null; then
    log_success "Copied to: $path"
    ((SUCCESS_COUNT++))
  else
    log_error "Failed to copy to: $path"
  fi
done

# CRITICAL: Also copy to root and Desktop for manual execution
cp -f /tmp/win_setup.bat /mnt/windows/win_setup.bat
log_success "Backup copy at C:\\win_setup.bat"

# Copy to Administrator Desktop
DESKTOP_PATH="/mnt/windows/Users/Administrator/Desktop"
mkdir -p "$DESKTOP_PATH"
if cp -f /tmp/win_setup.bat "$DESKTOP_PATH/win_setup.bat" 2>/dev/null; then
  log_success "Desktop backup at Administrator Desktop"
else
  log_error "Could not copy to Desktop (may not exist yet)"
fi

# Copy to Public Desktop (accessible to all users)
PUBLIC_DESKTOP="/mnt/windows/Users/Public/Desktop"
mkdir -p "$PUBLIC_DESKTOP"
if cp -f /tmp/win_setup.bat "$PUBLIC_DESKTOP/win_setup.bat" 2>/dev/null; then
  log_success "Desktop backup at Public Desktop"
fi

# Verify at least one copy succeeded
if [ $SUCCESS_COUNT -eq 0 ]; then
  log_error "CRITICAL: Failed to copy batch file to ANY startup location!"
  exit 1
fi

log_success "Batch file copied to $SUCCESS_COUNT locations"

# Create autorun registry entry (alternative method)
log_info "Creating registry autorun entry..."
cat > /tmp/autorun.reg << 'EOFREGISTRY'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run]
"WinSetup"="C:\\win_setup.bat"
EOFREGISTRY

cp /tmp/autorun.reg /mnt/windows/autorun.reg
log_success "Registry file created for manual import if needed"

# List all injected files
log_info "Verification - Files in Windows partition:"
ls -lh /mnt/windows/*.bat /mnt/windows/*.msi /mnt/windows/*.reg 2>/dev/null

# --- 10. FINISH ---
log_step "STEP 10: Unmounting and Finalizing"
sync
sync
sleep 3

umount /mnt/windows
log_success "Partition unmounted"

# Final verification
partprobe /dev/vda
sleep 2

echo ""
echo "===================================================="
echo "     ✓ INSTALLATION COMPLETE!                      "
echo "===================================================="
echo ""
echo " NEXT STEPS:"
echo " 1. This droplet will power off in 10 seconds"
echo " 2. Go to DigitalOcean Control Panel"
echo " 3. Turn OFF Recovery Mode"
echo " 4. Power ON the droplet"
echo " 5. Open 'Recovery Console' (VNC) immediately"
echo " 6. You should see batch file logs in console"
echo " 7. Wait 3-5 minutes for setup to complete"
echo " 8. Check C:\\setup_log.txt via VNC if issues occur"
echo ""
echo " RDP CONNECTION INFO:"
echo " ---------------------------------------------------"
echo "  IP Address : $CLEAN_IP"
echo "  Username   : Administrator"
echo "  Password   : P@ssword64"
echo "  Port       : 3389"
echo "  NLA        : Enabled"
echo " ---------------------------------------------------"
echo ""
echo " TROUBLESHOOTING:"
echo "  - If batch doesn't run: Login via VNC and manually"
echo "    double-click C:\\win_setup.bat"
echo "  - Check C:\\setup_log.txt for detailed logs"
echo "  - Batch file is in multiple Startup folders"
echo ""
echo "===================================================="
echo ""

for i in {10..1}; do
  echo -ne "\rPowering off in $i seconds... "
  sleep 1
done
echo ""

poweroff
