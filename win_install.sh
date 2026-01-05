#!/bin/bash
#
# DIGITALOCEAN INSTALLER - MULTI-PORT DNS FIX
# Date: 2025-11-25
# Fixes:  DNS configuration for both Ethernet Instance 0 AND 1
# Fixed: Pixeldrain gzip detection
# Fixed: Ethernet Instance numbering (0 and 1, not 0 and 2)
#

# --- LOGGING FUNCTIONS ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS INSTALLER - MULTI-PORT DNS VERSION       "
echo "===================================================="

# --- 1. INSTALL DEPENDENCIES ---
log_step "STEP 1: Installing Dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y ntfs-3g parted psmisc curl wget jq xxd || { log_error "Failed to install tools"; exit 1; }

# --- 2. DOWNLOAD CHROME ---
log_step "STEP 2: Pre-downloading Chrome"
wget -q --show-progress --progress=bar: force -O /tmp/chrome.msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
[ -s "/tmp/chrome.msi" ] && log_success "Chrome downloaded." || { log_error "Chrome download failed. "; exit 1; }

# --- 3. OS SELECTION ---
log_step "STEP 3: Select Operating System"
echo "  1) Windows 2019 (Mediafire Recommended)"
echo "  2) Windows 2019 (Pixeldrain)"
echo "  3) Windows 10 Super Lite SF"
echo "  4) Windows 10 Super Lite MF"
echo "  5) Windows 10 Super Lite CF"
echo "  6) Windows 11 Normal"
echo "  7) Windows 10 Normal"
echo "  8) Custom Link"
read -p "Select [1]:  " PILIHOS

# Store whether this is a known gzip source
IS_GZIP=true

case "$PILIHOS" in
  1|"") PILIHOS="https://download1590.mediafire.com/5e50jbqptcrg93rPAJhpQKNYg6Lokblibjn6n-_LRZ228gYzH1mR7ER9EtWic4gOCLzxjrKWl4mKcFCvmKkkWEyPlgckm3CMiIATwXumk_jVixcs_0-pUFmBLOX3xGBT0NLvQw5lmgQvZRWmksiDsIkoAcc_92Fr-_zBfUGLJR_Di_k/5bnp3aoc7pi7jl9/windows2019DO. gz";;
  2) PILIHOS="https://pixeldrain.com/api/file/Cx29Sb9H";;
  3) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite. gz? viasf=1";;
  4) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  5) PILIHOS="https://umbel.my.id/wedus10lite. gz";;
  6) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  7) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win10_en. gz";;
  8) 
    read -p "Enter Direct Link:  " PILIHOS
    read -p "Is this a . gz compressed image? [Y/n]: " GZIP_ANSWER
    if [[ "$GZIP_ANSWER" =~ ^[Nn] ]]; then
        IS_GZIP=false
    fi
    ;;
  *) log_error "Invalid selection"; exit 1;;
esac

# --- 4. NETWORK DETECTION ---
log_step "STEP 4:  Calculating Network Settings"

# Get the raw IP info (excluding local loopback and internal Docker/Private IPs)
RAW_DATA=$(ip -4 -o addr show | awk '{print $4}' | grep -v "^10\." | grep -v "^127\." | head -n1)
CLEAN_IP=${RAW_DATA%/*}
CLEAN_PREFIX=${RAW_DATA#*/}
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

# Gateway Failsafe
if [ -z "$GW" ] || [[ "$GW" == "0.0.0.0" ]]; then
    log_error "No gateway detected via route."
    IP_BASE=$(echo "$CLEAN_IP" | cut -d.  -f1-3)
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
echo "   Subnet Mask    :  $SUBNET_MASK"
echo "   Gateway        : $GW"
echo "   ---------------------------"

if [[ "$CLEAN_IP" == *"/"* ]] || [ -z "$CLEAN_IP" ]; then
    log_error "IP Detection Failed.  Exiting to prevent bricking."
    exit 1
fi

read -p "Look correct? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then exit 1; fi

# --- 5. GENERATE BATCH FILE (MULTI-PORT DNS FIX) ---
log_step "STEP 5: Generating Windows Setup Script"

cat > /tmp/win_setup.bat << 'EOFBATCH'
@ECHO OFF
SETLOCAL EnableDelayedExpansion

REM ============================================
REM    WINDOWS SETUP - MULTI-PORT DNS FIX
REM    Fixed: Ethernet Instance 0 and 1
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
ECHO [DEBUG] Mask Target:  %MASK%
ECHO [DEBUG] Gateway    : %GW%
ECHO. 

ECHO [LOG] Waiting 15 seconds for drivers to load...
timeout /t 15 /nobreak >nul

REM --- ADAPTER DETECTION ---
ECHO. 
ECHO [LOG] Detecting Network Adapters... 
ECHO [DEBUG] Listing all adapters: 
netsh interface show interface

SET ADAPTER_NAME=
SET ADAPTER_0_EXISTS=0
SET ADAPTER_1_EXISTS=0
SET ADAPTER_ETH_EXISTS=0

REM Check which adapters exist
netsh interface show interface name="Ethernet Instance 0" >nul 2>&1
if %errorlevel% EQU 0 SET ADAPTER_0_EXISTS=1

netsh interface show interface name="Ethernet Instance 1" >nul 2>&1
if %errorlevel% EQU 0 SET ADAPTER_1_EXISTS=1

netsh interface show interface name="Ethernet" >nul 2>&1
if %errorlevel% EQU 0 SET ADAPTER_ETH_EXISTS=1

ECHO. 
ECHO [DEBUG] Ethernet Instance 0 exists:  %ADAPTER_0_EXISTS%
ECHO [DEBUG] Ethernet Instance 1 exists: %ADAPTER_1_EXISTS%
ECHO [DEBUG] Ethernet exists: %ADAPTER_ETH_EXISTS%

REM --- ADAPTER SELECTION PRIORITY ---
REM Priority 1: Try Ethernet Instance 0 first
if %ADAPTER_0_EXISTS% EQU 1 (
    SET "ADAPTER_NAME=Ethernet Instance 0"
    ECHO [SUCCESS] Selected Primary Adapter: Ethernet Instance 0
    goto :configure_network
)

REM Priority 2: If Instance 0 not found, try Instance 1
if %ADAPTER_1_EXISTS% EQU 1 (
    SET "ADAPTER_NAME=Ethernet Instance 1"
    ECHO [SUCCESS] Selected Secondary Adapter: Ethernet Instance 1
    goto : configure_network
)

REM Priority 3: Try standard "Ethernet"
if %ADAPTER_ETH_EXISTS% EQU 1 (
    SET "ADAPTER_NAME=Ethernet"
    ECHO [SUCCESS] Selected Standard Adapter: Ethernet
    goto :configure_network
)

REM Priority 4: Fallback - scan for any connected adapter
ECHO [DEBUG] No known adapters found.  Scanning for any connected adapter...
for /f "tokens=3*" %%a in ('netsh interface show interface ^| findstr /C:"Connected"') do (
    SET "ADAPTER_NAME=%%b"
    ECHO [DEBUG] Found connected adapter: ! ADAPTER_NAME! 
    goto :configure_network
)

: configure_network
if "%ADAPTER_NAME%"=="" (
    ECHO [CRITICAL ERROR] No network adapter found!
    ECHO [DEBUG] Please check Device Manager for network adapters.
    goto : keep_open
)

ECHO. 
ECHO [LOG] Configuring adapter: "%ADAPTER_NAME%"

REM --- DISABLE OTHER ADAPTERS IF USING INSTANCE 1 ---
REM If we're using Instance 1, disable Instance 0 first to avoid conflicts
if "%ADAPTER_NAME%"=="Ethernet Instance 1" (
    if %ADAPTER_0_EXISTS% EQU 1 (
        ECHO [LOG] Disabling Ethernet Instance 0 to avoid conflicts... 
        netsh interface set interface "Ethernet Instance 0" disable >nul 2>&1
        if %errorlevel% EQU 0 (
            ECHO [SUCCESS] Ethernet Instance 0 disabled. 
        ) else (
            ECHO [WARNING] Could not disable Ethernet Instance 0.
        )
        timeout /t 2 /nobreak >nul
    )
)

REM --- APPLY IP ---
ECHO. 
ECHO [LOG] Applying IP Address to %ADAPTER_NAME%...
netsh interface ip set address name="%ADAPTER_NAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1
if %errorlevel% EQU 0 (
    ECHO [SUCCESS] IP Applied. 
) else (
    ECHO [ERROR] Failed to set IP via netsh.  Retrying with PowerShell...
    powershell -Command "Remove-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -Confirm: $false" >nul 2>&1
    powershell -Command "Remove-NetRoute -InterfaceAlias '%ADAPTER_NAME%' -Confirm:$false" >nul 2>&1
    powershell -Command "New-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -IPAddress %IP% -PrefixLength 24 -DefaultGateway %GW%"
    if %errorlevel% EQU 0 (
        ECHO [SUCCESS] IP Applied via PowerShell. 
    ) else (
        ECHO [ERROR] Failed to set IP.  Manual configuration may be required.
    )
)

timeout /t 2 /nobreak >nul

REM --- APPLY DNS TO ACTIVE ADAPTER ---
ECHO. 
ECHO [LOG] Applying DNS Settings to %ADAPTER_NAME%...
netsh interface ip set dns name="%ADAPTER_NAME%" source=static addr=8.8.8.8
netsh interface ip add dns name="%ADAPTER_NAME%" addr=8.8.4.4 index=2
powershell -Command "Set-DnsClientServerAddress -InterfaceAlias '%ADAPTER_NAME%' -ServerAddresses 8.8.8.8,8.8.4.4" >nul 2>&1
ECHO [SUCCESS] DNS configured on %ADAPTER_NAME%

REM --- CONFIGURE DNS ON OTHER ENABLED ADAPTERS (FALLBACK) ---
ECHO.
ECHO [LOG] Configuring DNS on other enabled adapters as fallback... 

REM Configure Ethernet Instance 0 if it exists and is not the primary
if %ADAPTER_0_EXISTS% EQU 1 (
    if NOT "%ADAPTER_NAME%"=="Ethernet Instance 0" (
        REM Check if it's still enabled
        netsh interface show interface name="Ethernet Instance 0" | findstr /C:"Enabled" >nul 2>&1
        if %errorlevel% EQU 0 (
            ECHO [DEBUG] Configuring DNS for Ethernet Instance 0...
            netsh interface ip set dns name="Ethernet Instance 0" source=static addr=8.8.8.8 >nul 2>&1
            netsh interface ip add dns name="Ethernet Instance 0" addr=8.8.4.4 index=2 >nul 2>&1
            powershell -Command "Set-DnsClientServerAddress -InterfaceAlias 'Ethernet Instance 0' -ServerAddresses 8.8.8.8,8.8.4.4" >nul 2>&1
        )
    )
)

REM Configure Ethernet Instance 1 if it exists and is not the primary
if %ADAPTER_1_EXISTS% EQU 1 (
    if NOT "%ADAPTER_NAME%"=="Ethernet Instance 1" (
        ECHO [DEBUG] Configuring DNS for Ethernet Instance 1... 
        netsh interface ip set dns name="Ethernet Instance 1" source=static addr=8.8.8.8 >nul 2>&1
        netsh interface ip add dns name="Ethernet Instance 1" addr=8.8.4.4 index=2 >nul 2>&1
        powershell -Command "Set-DnsClientServerAddress -InterfaceAlias 'Ethernet Instance 1' -ServerAddresses 8.8.8.8,8.8.4.4" >nul 2>&1
    )
)

REM Configure standard Ethernet if it exists and is not the primary
if %ADAPTER_ETH_EXISTS% EQU 1 (
    if NOT "%ADAPTER_NAME%"=="Ethernet" (
        ECHO [DEBUG] Configuring DNS for Ethernet...
        netsh interface ip set dns name="Ethernet" source=static addr=8.8.8.8 >nul 2>&1
        netsh interface ip add dns name="Ethernet" addr=8.8.4.4 index=2 >nul 2>&1
        powershell -Command "Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 8.8.8.8,8.8.4.4" >nul 2>&1
    )
)

ECHO [LOG] Flushing DNS Cache...
ipconfig /flushdns

REM --- DISPLAY FINAL CONFIGURATION ---
ECHO. 
ECHO [LOG] Current IP Configuration:
ipconfig /all | findstr /C:"IPv4" /C:"Subnet" /C:"Gateway" /C:"DNS"

REM --- TEST NETWORK ---
ECHO. 
ECHO [LOG] Testing Connection... 
ECHO [DEBUG] Pinging Gateway %GW%...
ping -n 2 %GW%
if %errorlevel% EQU 0 (
    ECHO [SUCCESS] Gateway reachable! 
) else (
    ECHO [WARNING] Gateway ping failed. 
)

ECHO [DEBUG] Pinging Google DNS 8.8.8.8...
ping -n 2 8.8.8.8
if %errorlevel% EQU 0 (
    ECHO [SUCCESS] Internet Connected!
) else (
    ECHO [WARNING] Internet ping failed.  RDP might still work if local IP is set correctly.
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
if exist "C:\chrome. msi" (
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
ECHO IP Address :  %IP%
ECHO Subnet Mask:  %MASK%
ECHO Gateway    : %GW%
ECHO Adapter    : %ADAPTER_NAME%
ECHO Username   : Administrator
ECHO. 

: keep_open
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

log_success "Batch script created with multi-port DNS support."

# --- 6. WRITE IMAGE ---
log_step "STEP 6: Writing OS to Disk"
umount -f /dev/vda* 2>/dev/null

# Function to check if content is gzip compressed
is_gzip_content() {
    local URL="$1"
    local TMPFILE=$(mktemp)
    local IS_GZ=false
    
    # Try to get first 2 bytes to check magic number
    wget --no-check-certificate -q -O "$TMPFILE" --header="Range: bytes=0-1" "$URL" 2>/dev/null
    
    if [ -f "$TMPFILE" ] && [ -s "$TMPFILE" ]; then
        # Check for gzip magic bytes (1f 8b)
        MAGIC=$(xxd -p -l 2 "$TMPFILE" 2>/dev/null)
        if [ "$MAGIC" = "1f8b" ]; then
            IS_GZ=true
        fi
    fi
    
    rm -f "$TMPFILE"
    
    if $IS_GZ; then
        return 0  # true - is gzip
    else
        return 1  # false - not gzip
    fi
}

# Determine if we need to decompress
NEED_GUNZIP=false

# Check 1: URL pattern
if echo "$PILIHOS" | grep -qiE '\. gz($|\?)'; then
    log_info "URL indicates gzip compression"
    NEED_GUNZIP=true
fi

# Check 2: Known gzip sources (Pixeldrain, etc.)
if echo "$PILIHOS" | grep -qiE 'pixeldrain\. com|sourceforge\. net'; then
    log_info "Known gzip source detected"
    NEED_GUNZIP=true
fi

# Check 3: Magic byte detection (most reliable)
log_info "Checking file headers..."
if is_gzip_content "$PILIHOS"; then
    log_info "Gzip magic bytes detected (1f 8b)"
    NEED_GUNZIP=true
fi

# Write the image
if $NEED_GUNZIP; then
    log_info "Downloading and decompressing gzip image..."
    wget --no-check-certificate --show-progress -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
else
    log_info "Downloading raw image..."
    wget --no-check-certificate --show-progress -O- "$PILIHOS" | dd of=/dev/vda bs=4M status=progress
fi

# Check if dd was successful
if [ ${PIPESTATUS[0]} -ne 0 ] || [ ${PIPESTATUS[1]} -ne 0 ]; then
    log_error "Image write failed!"
    exit 1
fi

log_success "Image written successfully"
sync
sleep 3

# --- 7. PARTITION & MOUNT ---
log_step "STEP 7: Mounting Windows Partition"
partprobe /dev/vda
sleep 5

TARGET=""
for i in {1..10}; do
    # Check for common partition layouts
    if [ -b /dev/vda3 ]; then TARGET="/dev/vda3"; break; fi
    if [ -b /dev/vda2 ]; then TARGET="/dev/vda2"; break; fi
    if [ -b /dev/vda1 ]; then TARGET="/dev/vda1"; break; fi
    echo "   Searching for partition...  ($i/10)"
    sleep 2
    partprobe /dev/vda
done

# If still not found, try to list what we have
if [ -z "$TARGET" ]; then
    log_error "Partition not found.  Checking disk layout..."
    fdisk -l /dev/vda
    lsblk /dev/vda
    exit 1
fi

log_info "Partition Found: $TARGET"

# Detect filesystem type
FSTYPE=$(blkid -o value -s TYPE "$TARGET" 2>/dev/null)
log_info "Filesystem type: $FSTYPE"

if [ "$FSTYPE" = "ntfs" ]; then
    log_info "Fixing NTFS filesystem..."
    ntfsfix -d "$TARGET" > /dev/null 2>&1
    
    mkdir -p /mnt/windows
    log_info "Mounting NTFS partition..."
    if !  mount. ntfs-3g -o remove_hiberfile,rw "$TARGET" /mnt/windows 2>/dev/null; then
        log_info "Trying force mount..."
        mount. ntfs-3g -o force,rw "$TARGET" /mnt/windows || {
            log_error "Failed to mount NTFS partition"
            exit 1
        }
    fi
elif [ "$FSTYPE" = "vfat" ] || [ "$FSTYPE" = "fat32" ]; then
    mkdir -p /mnt/windows
    mount -t vfat "$TARGET" /mnt/windows || {
        log_error "Failed to mount FAT partition"
        exit 1
    }
else
    log_error "Unknown or unsupported filesystem:  $FSTYPE"
    exit 1
fi

log_success "Partition mounted successfully"

# --- 8. INJECT FILES ---
log_step "STEP 8: Injecting Setup Files"

# Check if Windows filesystem is accessible
if [ ! -d "/mnt/windows/Windows" ]; then
    log_error "Windows directory not found!  Mount might have failed."
    log_error "Contents of /mnt/windows:"
    ls -la /mnt/windows/
    exit 1
fi

PATH_ALL_USERS="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
PATH_ADMIN="/mnt/windows/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"

# Create directories with error checking
log_info "Creating startup directories..."
mkdir -p "$PATH_ALL_USERS" || { log_error "Failed to create All Users startup folder"; exit 1; }
mkdir -p "$PATH_ADMIN" || { log_error "Failed to create Administrator startup folder"; exit 1; }

# Copy files with verification
log_info "Copying Chrome installer..."
if cp -v /tmp/chrome. msi /mnt/windows/chrome.msi; then
    if [ -f "/mnt/windows/chrome.msi" ]; then
        CHROME_SIZE=$(stat -c%s "/mnt/windows/chrome.msi" 2>/dev/null || echo "0")
        if [ "$CHROME_SIZE" -gt 1000000 ]; then
            log_success "Chrome installer copied successfully ($CHROME_SIZE bytes)"
        else
            log_error "Chrome installer copy failed - file too small"
            exit 1
        fi
    else
        log_error "Chrome installer not found after copy"
        exit 1
    fi
else
    log_error "Failed to copy chrome.msi"
    exit 1
fi

log_info "Copying setup script to All Users startup..."
if cp -f /tmp/win_setup.bat "$PATH_ALL_USERS/win_setup.bat"; then
    [ -f "$PATH_ALL_USERS/win_setup.bat" ] && log_success "✓ All Users startup" || { log_error "Copy verification failed"; exit 1; }
else
    log_error "Failed to copy to All Users startup"
    exit 1
fi

log_info "Copying setup script to Administrator startup..."
if cp -f /tmp/win_setup.bat "$PATH_ADMIN/win_setup.bat"; then
    [ -f "$PATH_ADMIN/win_setup.bat" ] && log_success "✓ Administrator startup" || { log_error "Copy verification failed"; exit 1; }
else
    log_error "Failed to copy to Administrator startup"
    exit 1
fi

# Final verification
log_info "Verifying all files..."
MISSING=0
[ -f "/mnt/windows/chrome.msi" ] || { log_error "Missing:  chrome.msi"; MISSING=1; }
[ -f "$PATH_ALL_USERS/win_setup.bat" ] || { log_error "Missing: All Users startup script"; MISSING=1; }
[ -f "$PATH_ADMIN/win_setup.bat" ] || { log_error "Missing: Administrator startup script"; MISSING=1; }

if [ $MISSING -eq 0 ]; then
    log_success "All files injected and verified successfully!"
else
    log_error "Some files are missing.  Installation may fail."
    exit 1
fi

# --- 9. FINISH ---
log_step "STEP 9: Cleaning Up"

log_info "Syncing all filesystem changes..."
sync
sync
log_info "Waiting for sync to complete..."
sleep 3

log_info "Unmounting Windows partition..."
if umount /mnt/windows; then
    log_success "Unmounted successfully"
else
    log_error "Unmount failed, forcing..."
    umount -f /mnt/windows 2>/dev/null || true
    sleep 2
fi

# Final sync
sync

echo "===================================================="
echo "       INSTALLATION SUCCESSFUL!                      "
echo "===================================================="
echo " 1. Droplet is powering off NOW"
echo " 2. Turn OFF Recovery Mode in DigitalOcean Panel"
echo " 3. Power ON the droplet"
echo " 4. Open Recovery Console (VNC) to see logs"
echo " 5. Connect RDP to:  $CLEAN_IP"
echo " "
echo " NOTES:"
echo " - Default Username: Administrator"
echo " - Check VNC console for setup progress"
echo "===================================================="
sleep 5
poweroff
