#!/bin/bash
#
# DIGITALOCEAN INSTALLER - NETWORK ADAPTER FIX
# Date: 2025-11-24
# Fixes:
#   1. Targets FIRST PHYSICAL adapter only (avoids "Ethernet 0 2" issue)
#   2. Removes old IP config before applying new one
#   3. Fixed DNS: 8.8.8.8 (primary), 8.8.4.4 (alternate)
#   4. Uses -InterfaceIndex instead of pipeline to prevent multi-adapter errors
#

# --- LOGGING ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS INSTALLER - NETWORK ADAPTER FIX          "
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
echo "  1) Windows 2019 (Recommended)"
echo "  2) Windows 10 Super Lite SF"
echo "  3) Windows 10 Super Lite MF"
echo "  4) Windows 10 Super Lite CF"
echo "  5) Windows 11 Normal"
echo "  6) Windows 10 Normal"
echo "  7) Custom Link"
read -p "Select [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://sourceforge.net/projects/nixpoin/files/windows2019DO.gz";;
  2) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  3) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  4) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  5) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  6) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win10_en.gz";;
  7) read -p "Enter Direct Link: " PILIHOS;;
  *) log_error "Invalid selection"; exit 1;;
esac

# --- 4. SURGICAL NETWORK DETECTION ---
log_step "STEP 4: Cleaning Network Variables"

# PRE-CHECK: Dump all network info for debugging
log_info "=== NETWORK DEBUG INFO ==="
echo "All IP addresses:"
ip -4 -o addr show
echo ""
echo "Routing table:"
ip route
echo "=========================="
echo ""

# 1. Get the full line containing the Public IP (Ignore 10.x and 127.x)
RAW_DATA=$(ip -4 -o addr show | awk '{print $4}' | grep -v "^10\." | grep -v "^127\." | head -n1)

# 2. Strip the CIDR to get Pure IP (e.g., "157.245.13.197")
CLEAN_IP=${RAW_DATA%/*}

# 3. Extract the Prefix only (e.g., "20")
CLEAN_PREFIX=${RAW_DATA#*/}

# 4. Get Gateway
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

# 4b. GATEWAY VALIDATION & FALLBACK
if [ -z "$GW" ] || [[ "$GW" == "0.0.0.0" ]]; then
    log_error "No gateway detected!"
    log_info "Attempting to calculate gateway from IP..."
    
    # Extract first 3 octets and assume .1 is gateway
    IP_BASE=$(echo "$CLEAN_IP" | cut -d. -f1-3)
    GW="${IP_BASE}.1"
    log_success "Using calculated gateway: $GW"
    
    # Double-check: Try .254 if .1 doesn't seem right
    if ! ping -c 1 -W 2 "$GW" >/dev/null 2>&1; then
        GW="${IP_BASE}.254"
        log_info "Trying alternate gateway: $GW"
    fi
fi

# 5. SUBNET MASK VALIDATION & AUTO-CORRECTION
# Common DigitalOcean prefixes: /20, /24, /22, /16
# If prefix seems wrong, try to detect it from gateway IP
if [ "$CLEAN_PREFIX" -lt 16 ] || [ "$CLEAN_PREFIX" -gt 30 ]; then
    log_error "Suspicious prefix detected: /$CLEAN_PREFIX"
    log_info "Attempting auto-detection from gateway..."
    
    # Extract first 3 octets of IP and Gateway
    IP_PREFIX=$(echo "$CLEAN_IP" | cut -d. -f1-3)
    GW_PREFIX=$(echo "$GW" | cut -d. -f1-3)
    
    # If they match, likely /24
    if [ "$IP_PREFIX" = "$GW_PREFIX" ]; then
        CLEAN_PREFIX=24
        log_success "Auto-corrected to /24"
    else
        # Default to /20 for DigitalOcean
        CLEAN_PREFIX=20
        log_success "Defaulting to /20 (DigitalOcean standard)"
    fi
fi

# Convert prefix to subnet mask for display
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
    *) SUBNET_MASK="Unknown";;
esac

echo "   ---------------------------"
echo "   Raw Data     : $RAW_DATA"
echo "   Clean IP     : $CLEAN_IP"
echo "   Prefix       : /$CLEAN_PREFIX"
echo "   Subnet Mask  : $SUBNET_MASK"
echo "   Gateway      : $GW"
echo "   ---------------------------"

# Safety check
if [[ "$CLEAN_IP" == *"/"* ]] || [ -z "$CLEAN_IP" ]; then
    log_error "IP Sanitization failed. Raw data was: $RAW_DATA"
    exit 1
fi

# Final confirmation
read -p "Does this network config look correct? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
    log_error "Installation cancelled by user."
    exit 1
fi

# --- 5. GENERATE BATCH FILE ---
log_step "STEP 5: Generating Setup Script"

cat >/tmp/win_setup.bat<<EOF
@ECHO OFF
REM ==================================================
REM   WINDOWS NETWORK AUTO-CONFIGURATOR v3.0
REM   Multi-Layer Fallback System
REM ==================================================

SET TARGET_IP=$CLEAN_IP
SET TARGET_PREFIX=$CLEAN_PREFIX
SET TARGET_MASK=$SUBNET_MASK
SET TARGET_GW=$GW

REM --- 1. GET ADMIN ---
cd.>%windir%\\GetAdmin
if exist %windir%\\GetAdmin (del /f /q "%windir%\\GetAdmin") else (
  echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\\Admin.vbs"
  "%temp%\\Admin.vbs"
  del /f /q "%temp%\\Admin.vbs"
  exit /b 2
)

REM --- 2. DELAY FOR DRIVERS ---
ECHO Waiting for network drivers...
timeout /t 15 /nobreak >nul

REM --- 2b. DISPLAY NETWORK TARGET ---
ECHO.
ECHO ====================================
ECHO   NETWORK CONFIGURATION TARGET
ECHO ====================================
ECHO   IP Address : %TARGET_IP%
ECHO   Prefix     : /%TARGET_PREFIX%
ECHO   Subnet Mask: %TARGET_MASK%
ECHO   Gateway    : %TARGET_GW%
ECHO   DNS 1      : 8.8.8.8
ECHO   DNS 2      : 8.8.4.4
ECHO ====================================
ECHO.

REM --- 2c. LIST AVAILABLE ADAPTERS ---
ECHO Available Network Adapters:
powershell -Command "Get-NetAdapter | Format-Table Name, Status, LinkSpeed, ifIndex -AutoSize"
ECHO.

REM --- 3. APPLY IP AND DNS (MULTI-LAYER FALLBACK SYSTEM) ---
FOR /L %%N IN (1,1,5) DO (
  ECHO.
  ECHO ========================================
  ECHO    ATTEMPT %%N: Network Configuration
  ECHO ========================================
  
  REM === STRATEGY 1: Target by Name Pattern (Highest Priority) ===
  ECHO [STRATEGY 1] Trying by name pattern (Ethernet 0 / Ethernet)...
  powershell -Command "\$adapter = Get-NetAdapter | Where-Object {\$_.Name -match '^Ethernet( 0)?\

REM --- 4. DISK EXTEND ---
ECHO Extending disk partitions...
ECHO SELECT DISK 0 > C:\\diskpart.txt
ECHO LIST PARTITION >> C:\\diskpart.txt
ECHO SELECT PARTITION 2 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO SELECT PARTITION 1 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO EXIT >> C:\\diskpart.txt
DISKPART /S C:\\diskpart.txt
del /f /q C:\\diskpart.txt

REM --- 5. FIREWALL ---
ECHO Enabling Remote Desktop...
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes

REM --- 6. INSTALL CHROME ---
if exist "C:\\chrome.msi" (
    ECHO Installing Chrome...
    msiexec /i "C:\\chrome.msi" /quiet /norestart
    del /f /q "C:\\chrome.msi"
)

REM --- 7. CLEANUP ---
del /f /q "%~f0"
exit
EOF

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
    echo "   Waiting for partition... ($i/10)"
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

# --- 9. FINISH ---
log_step "STEP 9: Cleaning Up"
sync
umount /mnt/windows

echo "===================================================="
echo "      INSTALLATION SUCCESSFUL!                      "
echo "===================================================="
echo " 1. Droplet is powering off."
echo " 2. Go to DigitalOcean -> Turn OFF Recovery."
echo " 3. Power ON."
echo " 4. Connect RDP: $CLEAN_IP"
echo "    Username: Administrator"
echo "===================================================="
sleep 5
poweroff -and \$_.Status -eq 'Up'} | Select-Object -First 1; if (\$adapter) { Write-Host \"SUCCESS: Using \$(\$adapter.Name) [ifIndex: \$(\$adapter.ifIndex)]\"; Remove-NetIPAddress -InterfaceIndex \$adapter.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; Remove-NetRoute -InterfaceIndex \$adapter.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; New-NetIPAddress -InterfaceIndex \$adapter.ifIndex -IPAddress $CLEAN_IP -PrefixLength $CLEAN_PREFIX -DefaultGateway $GW -AddressFamily IPv4 -ErrorAction SilentlyContinue; Set-DnsClientServerAddress -InterfaceIndex \$adapter.ifIndex -ServerAddresses ('8.8.8.8','8.8.4.4') -ErrorAction SilentlyContinue; exit 0 } else { Write-Host \"FAILED: No adapter matching pattern.\"; exit 1 }"
  
  if %ERRORLEVEL% EQU 0 (
    ECHO [SUCCESS] Strategy 1 worked!
    goto network_success
  )
  
  REM === STRATEGY 2: Lowest ifIndex (Primary Adapter) ===
  ECHO [STRATEGY 2] Trying lowest ifIndex...
  powershell -Command "\$adapter = Get-NetAdapter | Where-Object {\$_.Status -eq 'Up'} | Sort-Object -Property ifIndex | Select-Object -First 1; if (\$adapter) { Write-Host \"SUCCESS: Using \$(\$adapter.Name) [ifIndex: \$(\$adapter.ifIndex)]\"; Remove-NetIPAddress -InterfaceIndex \$adapter.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; Remove-NetRoute -InterfaceIndex \$adapter.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; New-NetIPAddress -InterfaceIndex \$adapter.ifIndex -IPAddress $CLEAN_IP -PrefixLength $CLEAN_PREFIX -DefaultGateway $GW -AddressFamily IPv4 -ErrorAction SilentlyContinue; Set-DnsClientServerAddress -InterfaceIndex \$adapter.ifIndex -ServerAddresses ('8.8.8.8','8.8.4.4') -ErrorAction SilentlyContinue; exit 0 } else { Write-Host \"FAILED: No active adapters.\"; exit 1 }"
  
  if %ERRORLEVEL% EQU 0 (
    ECHO [SUCCESS] Strategy 2 worked!
    goto network_success
  )
  
  REM === STRATEGY 3: Highest Link Speed (Best Adapter) ===
  ECHO [STRATEGY 3] Trying adapter with highest link speed...
  powershell -Command "\$adapter = Get-NetAdapter | Where-Object {\$_.Status -eq 'Up'} | Sort-Object -Property LinkSpeed -Descending | Select-Object -First 1; if (\$adapter) { Write-Host \"SUCCESS: Using \$(\$adapter.Name) [Speed: \$(\$adapter.LinkSpeed)]\"; Remove-NetIPAddress -InterfaceIndex \$adapter.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; Remove-NetRoute -InterfaceIndex \$adapter.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; New-NetIPAddress -InterfaceIndex \$adapter.ifIndex -IPAddress $CLEAN_IP -PrefixLength $CLEAN_PREFIX -DefaultGateway $GW -AddressFamily IPv4 -ErrorAction SilentlyContinue; Set-DnsClientServerAddress -InterfaceIndex \$adapter.ifIndex -ServerAddresses ('8.8.8.8','8.8.4.4') -ErrorAction SilentlyContinue; exit 0 } else { exit 1 }"
  
  if %ERRORLEVEL% EQU 0 (
    ECHO [SUCCESS] Strategy 3 worked!
    goto network_success
  )
  
  REM === STRATEGY 4: Exclude Secondary Adapters by Name ===
  ECHO [STRATEGY 4] Trying to exclude secondary adapters...
  powershell -Command "\$adapter = Get-NetAdapter | Where-Object {\$_.Status -eq 'Up' -and \$_.Name -notmatch '0 2|#2|secondary'} | Select-Object -First 1; if (\$adapter) { Write-Host \"SUCCESS: Using \$(\$adapter.Name)\"; Remove-NetIPAddress -InterfaceIndex \$adapter.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; Remove-NetRoute -InterfaceIndex \$adapter.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; New-NetIPAddress -InterfaceIndex \$adapter.ifIndex -IPAddress $CLEAN_IP -PrefixLength $CLEAN_PREFIX -DefaultGateway $GW -AddressFamily IPv4 -ErrorAction SilentlyContinue; Set-DnsClientServerAddress -InterfaceIndex \$adapter.ifIndex -ServerAddresses ('8.8.8.8','8.8.4.4') -ErrorAction SilentlyContinue; exit 0 } else { exit 1 }"
  
  if %ERRORLEVEL% EQU 0 (
    ECHO [SUCCESS] Strategy 4 worked!
    goto network_success
  )
  
  REM === STRATEGY 5: NUCLEAR OPTION - Configure ALL Adapters ===
  ECHO [STRATEGY 5] NUCLEAR: Configuring ALL active adapters...
  powershell -Command "Get-NetAdapter | Where-Object {\$_.Status -eq 'Up'} | ForEach-Object { Write-Host \"Configuring: \$(\$_.Name)\"; Remove-NetIPAddress -InterfaceIndex \$_.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; Remove-NetRoute -InterfaceIndex \$_.ifIndex -Confirm:\$false -ErrorAction SilentlyContinue; New-NetIPAddress -InterfaceIndex \$_.ifIndex -IPAddress $CLEAN_IP -PrefixLength $CLEAN_PREFIX -DefaultGateway $GW -AddressFamily IPv4 -ErrorAction SilentlyContinue; Set-DnsClientServerAddress -InterfaceIndex \$_.ifIndex -ServerAddresses ('8.8.8.8','8.8.4.4') -ErrorAction SilentlyContinue }"
  
  ECHO [COMPLETE] Nuclear option executed.
  
  :network_success
  ECHO [WAITING] 3 seconds before next attempt...
  timeout /t 3 /nobreak >nul
)

REM === FINAL VERIFICATION ===
ECHO.
ECHO ========================================
ECHO    VERIFYING NETWORK CONFIGURATION
ECHO ========================================
powershell -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object {\$_.IPAddress -notmatch '^127\.|^169\.254\.'} | Format-Table -AutoSize"
powershell -Command "Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {\$_.ServerAddresses -ne \$null} | Format-Table -AutoSize"
ECHO ========================================

REM === PLAN Z: NETSH FALLBACK (If PowerShell completely failed) ===
ECHO.
ECHO Checking if configuration succeeded...
ping -n 1 8.8.8.8 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  ECHO [WARNING] Network not responding. Trying NETSH fallback...
  
  REM Get adapter name using netsh
  for /f "tokens=3*" %%a in ('netsh interface show interface ^| findstr /i "connected"') do (
    set ADAPTER_NAME=%%b
    ECHO Trying adapter: %%b
    
    REM Configure IP using variables
    netsh interface ip set address name="%%b" static %TARGET_IP% %TARGET_MASK% %TARGET_GW% 1
    
    REM Configure DNS
    netsh interface ip set dns name="%%b" static 8.8.8.8 primary
    netsh interface ip add dns name="%%b" 8.8.4.4 index=2
    
    timeout /t 2 /nobreak >nul
    
    REM Test connectivity
    ping -n 1 8.8.8.8 >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
      ECHO [SUCCESS] NETSH fallback worked on adapter: %%b
      goto netsh_success
    )
  )
  
  :netsh_success
  ECHO NETSH configuration complete.
) else (
  ECHO [SUCCESS] Network is responding. Configuration successful!
)

REM --- FINAL CONNECTIVITY TEST ---
ECHO.
ECHO ========================================
ECHO    FINAL CONNECTIVITY TEST
ECHO ========================================
ECHO Testing DNS resolution...
nslookup google.com 8.8.8.8
ECHO.
ECHO Testing internet connectivity...
ping -n 3 8.8.8.8
ECHO.
ECHO Testing external connectivity...
ping -n 2 google.com
ECHO ========================================
ECHO If all tests passed, network is configured correctly!
ECHO ========================================

REM --- 4. DISK EXTEND ---
ECHO Extending disk partitions...
ECHO SELECT DISK 0 > C:\\diskpart.txt
ECHO LIST PARTITION >> C:\\diskpart.txt
ECHO SELECT PARTITION 2 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO SELECT PARTITION 1 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO EXIT >> C:\\diskpart.txt
DISKPART /S C:\\diskpart.txt
del /f /q C:\\diskpart.txt

REM --- 5. FIREWALL ---
ECHO Enabling Remote Desktop...
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes

REM --- 6. INSTALL CHROME ---
if exist "C:\\chrome.msi" (
    ECHO Installing Chrome...
    msiexec /i "C:\\chrome.msi" /quiet /norestart
    del /f /q "C:\\chrome.msi"
)

REM --- 7. CLEANUP ---
del /f /q "%~f0"
exit
EOF

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
    echo "   Waiting for partition... ($i/10)"
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

# --- 9. FINISH ---
log_step "STEP 9: Cleaning Up"
sync
umount /mnt/windows

echo "===================================================="
echo "      INSTALLATION SUCCESSFUL!                      "
echo "===================================================="
echo " 1. Droplet is powering off."
echo " 2. Go to DigitalOcean -> Turn OFF Recovery."
echo " 3. Power ON."
echo " 4. Connect RDP: $CLEAN_IP"
echo "    Username: Administrator"
echo "===================================================="
sleep 5
poweroff
