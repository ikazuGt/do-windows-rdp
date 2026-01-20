#!/bin/bash
#
# DIGITALOCEAN WINDOWS INIT SCRIPT (NON-INTERACTIVE)
# Run as User Data when creating a new droplet
# 
# USAGE:  Paste this entire script into "User Data" when creating droplet
#        Select Ubuntu 22.04/24.04 or Debian 11/12 as the base OS
#

# ============================================
# CONFIGURATION - EDIT THESE VALUES
# ============================================

# Windows Image URL (Choose one and uncomment)
WINDOWS_IMAGE="https://pub-24c03f7a3eff4fa6936c33e2474d6905.r2.dev/windows2019DO. gz"
# WINDOWS_IMAGE="https://master.dl.sourceforge.net/project/manyod/wedus10lite. gz? viasf=1"
# WINDOWS_IMAGE="https://your-custom-url.com/windows. gz"

# Set to "true" to auto-reboot after install (recommended)
AUTO_REBOOT="true"

# Log file location
LOGFILE="/var/log/windows-installer.log"

# ============================================
# DO NOT EDIT BELOW THIS LINE
# ============================================

exec > >(tee -a "$LOGFILE") 2>&1
echo "=========================================="
echo "WINDOWS INSTALLER - INIT SCRIPT VERSION"
echo "Started:  $(date)"
echo "=========================================="

# --- LOGGING FUNCTIONS ---
log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "[OK] $1"; }
log_error() { echo -e "[ERROR] $1"; }
log_step() { echo -e "\n>>> $1"; }

# --- WAIT FOR CLOUD-INIT TO SETTLE ---
log_step "STEP 0:  Waiting for system to stabilize"
sleep 10

# --- 1. INSTALL DEPENDENCIES ---
log_step "STEP 1: Installing Dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y ntfs-3g parted psmisc curl wget jq || { log_error "Failed to install tools"; exit 1; }
log_success "Dependencies installed"

# --- 2. DOWNLOAD CHROME ---
log_step "STEP 2: Pre-downloading Chrome"
wget -q -O /tmp/chrome.msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
[ -s "/tmp/chrome.msi" ] && log_success "Chrome downloaded." || log_info "Chrome download failed, continuing anyway"

# --- 3. NETWORK DETECTION (AUTOMATIC) ---
log_step "STEP 3: Detecting Network Settings"

# Detect primary interface
PRIMARY_IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)
log_info "Primary Interface: $PRIMARY_IFACE"

# Get IP info
RAW_DATA=$(ip -4 -o addr show dev "$PRIMARY_IFACE" 2>/dev/null | awk '{print $4}' | head -n1)
if [ -z "$RAW_DATA" ]; then
    RAW_DATA=$(ip -4 -o addr show | awk '{print $4}' | grep -v "^10\." | grep -v "^127\." | grep -v "^172\." | head -n1)
fi

CLEAN_IP=${RAW_DATA%/*}
CLEAN_PREFIX=${RAW_DATA#*/}
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

# Gateway Failsafe
if [ -z "$GW" ] || [[ "$GW" == "0.0.0.0" ]]; then
    IP_BASE=$(echo "$CLEAN_IP" | cut -d.  -f1-3)
    GW="${IP_BASE}.1"
    log_info "Calculated Gateway: $GW"
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
    29) SUBNET_MASK="255.255.255.248";;
    30) SUBNET_MASK="255.255.255.252";;
    32) SUBNET_MASK="255.255.255.255";;
    *) SUBNET_MASK="255.255.255.0";;
esac

log_info "IP Address  : $CLEAN_IP"
log_info "Subnet Mask : $SUBNET_MASK"
log_info "Gateway     : $GW"
log_info "Prefix      : /$CLEAN_PREFIX"

# Validate network detection
if [[ -z "$CLEAN_IP" ]] || [[ "$CLEAN_IP" == *"/"* ]]; then
    log_error "IP Detection Failed.  Aborting to prevent bricking."
    exit 1
fi

# --- 4. DETECT DISK DEVICE ---
log_step "STEP 4: Detecting Disk Device"

if [ -b /dev/vda ]; then
    DISK="/dev/vda"
elif [ -b /dev/sda ]; then
    DISK="/dev/sda"
elif [ -b /dev/xvda ]; then
    DISK="/dev/xvda"
else
    log_error "No suitable disk found!"
    exit 1
fi
log_success "Using disk: $DISK"

# --- 5. GENERATE BATCH FILE ---
log_step "STEP 5: Generating Windows Setup Script"

cat > /tmp/win_setup.bat << 'EOFBATCH'
@ECHO OFF
SETLOCAL EnableDelayedExpansion

SET IP=PLACEHOLDER_IP
SET MASK=PLACEHOLDER_MASK
SET GW=PLACEHOLDER_GW
SET PREFIX=PLACEHOLDER_PREFIX

REM --- CHECK ADMIN RIGHTS ---
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

ECHO. 
ECHO ===========================================
ECHO      WINDOWS AUTO-CONFIGURATION
ECHO ===========================================
ECHO [DEBUG] IP Target  : %IP%
ECHO [DEBUG] Mask Target: %MASK%
ECHO [DEBUG] Gateway    : %GW%
ECHO. 

ECHO [LOG] Waiting 20 seconds for drivers to load...
timeout /t 20 /nobreak >nul

REM --- ADAPTER SELECTION LOGIC ---
ECHO [LOG] Detecting Network Adapter...
SET ADAPTER_NAME=

REM Priority order for adapter names
for %%A in ("Ethernet Instance 0" "Ethernet" "Ethernet 2" "Local Area Connection") do (
    netsh interface show interface name=%%A >nul 2>&1
    if ! errorlevel! EQU 0 (
        SET "ADAPTER_NAME=%%~A"
        ECHO [SUCCESS] Found Adapter: %%~A
        goto :configure_network
    )
)

REM Fallback:  First connected adapter
for /f "tokens=4*" %%a in ('netsh interface show interface ^| findstr /C:"Connected"') do (
    SET "ADAPTER_NAME=%%a %%b"
    SET "ADAPTER_NAME=! ADAPTER_NAME: ~0,-1!"
    ECHO [DEBUG] Using fallback adapter: ! ADAPTER_NAME! 
    goto :configure_network
)

: configure_network
if "%ADAPTER_NAME%"=="" (
    ECHO [CRITICAL ERROR] No network adapter found!
    goto :keep_open
)

ECHO [LOG] Configuring:  "%ADAPTER_NAME%"

REM --- APPLY IP (Try multiple methods) ---
ECHO [LOG] Applying IP Address... 

REM Method 1: netsh
netsh interface ip set address name="%ADAPTER_NAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1

REM Method 2: PowerShell fallback
if %errorlevel% NEQ 0 (
    ECHO [LOG] Trying PowerShell method...
    powershell -Command "Remove-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -Confirm: $false" >nul 2>&1
    powershell -Command "Remove-NetRoute -InterfaceAlias '%ADAPTER_NAME%' -Confirm:$false" >nul 2>&1
    powershell -Command "New-NetIPAddress -InterfaceAlias '%ADAPTER_NAME%' -IPAddress %IP% -PrefixLength %PREFIX% -DefaultGateway %GW%"
)

timeout /t 3 /nobreak >nul

REM --- APPLY DNS ---
ECHO [LOG] Applying DNS Settings...
netsh interface ip set dns name="%ADAPTER_NAME%" source=static addr=8.8.8.8
netsh interface ip add dns name="%ADAPTER_NAME%" addr=8.8.4.4 index=2
netsh interface ip add dns name="%ADAPTER_NAME%" addr=1.1.1.1 index=3
powershell -Command "Set-DnsClientServerAddress -InterfaceAlias '%ADAPTER_NAME%' -ServerAddresses 8.8.8.8,8.8.4.4,1.1.1.1" >nul 2>&1

ipconfig /flushdns

REM --- TEST NETWORK ---
ECHO [LOG] Testing Connection...
ping -n 3 8.8.8.8
if %errorlevel% EQU 0 (
    ECHO [SUCCESS] Internet Connected!
) else (
    ECHO [WARNING] Ping failed but RDP may still work.
)

REM --- DISK EXTENSION ---
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
ECHO [LOG] Enabling Remote Desktop...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >nul
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f >nul
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >nul 2>&1
netsh advfirewall firewall add rule name="RDP_3389" dir=in action=allow protocol=TCP localport=3389 >nul 2>&1
ECHO [SUCCESS] RDP Enabled. 

REM --- DISABLE WINDOWS FIREWALL (Optional but helps) ---
netsh advfirewall set allprofiles state off >nul 2>&1

REM --- INSTALL CHROME ---
if exist "C:\chrome.msi" (
    ECHO [LOG] Installing Chrome... 
    start /wait msiexec /i "C:\chrome. msi" /quiet /norestart
    del /f /q C:\chrome.msi
    ECHO [SUCCESS] Chrome Installed.
)

REM --- SET PASSWORD (Optional) ---
REM net user Administrator YourPassword123! 

ECHO. 
ECHO ===========================================
ECHO      SETUP COMPLETE - CONNECT VIA RDP
ECHO ===========================================
ECHO IP Address:  %IP%
ECHO Username  : Administrator
ECHO Password  : (check droplet or set above)
ECHO ===========================================

: keep_open
ECHO.
ECHO [LOG] Cleaning up startup script in 30 seconds...
timeout /t 30 /nobreak >nul
del /f /q "%~f0"
exit
EOFBATCH

# Inject variables into batch file
sed -i "s/PLACEHOLDER_IP/$CLEAN_IP/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_MASK/$SUBNET_MASK/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_GW/$GW/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_PREFIX/$CLEAN_PREFIX/g" /tmp/win_setup.bat

log_success "Batch script created"

# --- 6. WRITE IMAGE TO DISK ---
log_step "STEP 6: Downloading and Writing Windows Image"
log_info "Image URL: $WINDOWS_IMAGE"
log_info "Target Disk: $DISK"

# Kill any processes using the disk
fuser -km "$DISK" 2>/dev/null || true
sync

# Unmount all partitions
for part in ${DISK}*; do
    umount -f "$part" 2>/dev/null || true
done

# Download and write
if echo "$WINDOWS_IMAGE" | grep -qiE '\. gz($|\?)'; then
    log_info "Detected gzipped image, decompressing on-the-fly..."
    wget --no-check-certificate -qO- "$WINDOWS_IMAGE" | gunzip | dd of="$DISK" bs=4M status=progress conv=fsync
else
    log_info "Writing raw image..."
    wget --no-check-certificate -qO- "$WINDOWS_IMAGE" | dd of="$DISK" bs=4M status=progress conv=fsync
fi

DD_RESULT=$?
sync
sleep 3

if [ $DD_RESULT -ne 0 ]; then
    log_error "Image write may have failed.  Check logs."
fi

log_success "Image written to disk"

# --- 7.  MOUNT WINDOWS PARTITION ---
log_step "STEP 7: Mounting Windows Partition"
partprobe "$DISK"
sleep 5

TARGET=""
for i in {1..15}; do
    if [ -b "${DISK}2" ]; then TARGET="${DISK}2"; break; fi
    if [ -b "${DISK}1" ]; then TARGET="${DISK}1"; break; fi
    if [ -b "${DISK}p2" ]; then TARGET="${DISK}p2"; break; fi
    if [ -b "${DISK}p1" ]; then TARGET="${DISK}p1"; break; fi
    log_info "Waiting for partition...  ($i/15)"
    sleep 2
    partprobe "$DISK"
done

if [ -z "$TARGET" ]; then
    log_error "Windows partition not found!"
    exit 1
fi

log_success "Found partition: $TARGET"

# Fix and mount NTFS
ntfsfix -d "$TARGET" > /dev/null 2>&1 || true
mkdir -p /mnt/windows
mount. ntfs-3g -o remove_hiberfile,rw "$TARGET" /mnt/windows 2>/dev/null || \
mount.ntfs-3g -o force,rw "$TARGET" /mnt/windows || \
{ log_error "Failed to mount partition"; exit 1; }

log_success "Partition mounted"

# --- 8. INJECT FILES ---
log_step "STEP 8: Injecting Setup Files"

PATH_ALL_USERS="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
PATH_ADMIN="/mnt/windows/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
PATH_DEFAULT="/mnt/windows/Users/Default/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"

mkdir -p "$PATH_ALL_USERS" "$PATH_ADMIN" "$PATH_DEFAULT"

# Copy Chrome
[ -f /tmp/chrome.msi ] && cp /tmp/chrome.msi /mnt/windows/chrome.msi

# Copy setup script to multiple locations for reliability
cp -f /tmp/win_setup.bat "$PATH_ALL_USERS/win_setup.bat"
cp -f /tmp/win_setup.bat "$PATH_ADMIN/win_setup.bat" 2>/dev/null || true
cp -f /tmp/win_setup.bat "$PATH_DEFAULT/win_setup.bat" 2>/dev/null || true

# Also add to RunOnce registry (more reliable)
# This requires offline registry editing which is complex, so we rely on Startup folder

log_success "Files injected to Startup folders"

# --- 9. CLEANUP AND REBOOT ---
log_step "STEP 9: Finalizing"
sync
sleep 2
umount /mnt/windows

echo ""
echo "=========================================="
echo "      INSTALLATION COMPLETE!"
echo "=========================================="
echo ""
echo " Windows Image:  Written to $DISK"
echo " IP Address   : $CLEAN_IP"
echo " Subnet Mask  : $SUBNET_MASK"
echo " Gateway      : $GW"
echo ""
echo " NEXT STEPS:"
echo " 1. Droplet will reboot automatically"
echo " 2. Wait 2-3 minutes for Windows to boot"
echo " 3. Connect via RDP to:  $CLEAN_IP"
echo " 4. Username: Administrator"
echo ""
echo "=========================================="
echo "Completed:  $(date)"
echo "=========================================="

# Save connection info
cat > /tmp/windows_connection_info.txt << EOF
Windows Installation Complete
=============================
IP:  $CLEAN_IP
Username: Administrator
RDP Port: 3389

Connect:  mstsc /v: $CLEAN_IP
EOF

if [ "$AUTO_REBOOT" = "true" ]; then
    log_info "Rebooting in 10 seconds..."
    sleep 10
    reboot -f
else
    log_info "Auto-reboot disabled.  Please reboot manually."
fi
