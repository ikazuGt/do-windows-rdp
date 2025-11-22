#!/bin/bash
#
# DIGITALOCEAN WINDOWS INSTALLER - VERBOSE/DEBUG MODE
# Date: 2025-11-22
# Features: Pre-downloaded Chrome, Auto-Network Fix, Detailed Logging
#

# Function to print colorful status messages
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS INSTALLER - DETAILED LOGGING VERSION     "
echo "===================================================="

# --- 1. Install Dependencies ---
log_step "STEP 1: Installing System Dependencies"
export DEBIAN_FRONTEND=noninteractive
# Removed -qq to show output, added error check
apt-get update
apt-get install -y ntfs-3g parted psmisc curl wget || { log_error "Failed to install dependencies"; exit 1; }
log_success "Dependencies installed."

# --- 2. Download Chrome (RAM) ---
log_step "STEP 2: Pre-downloading Chrome Enterprise (MSI)"
log_info "Downloading to temporary memory (/tmp/chrome.msi)..."

# Download with progress bar
wget --show-progress -O /tmp/chrome.msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"

if [ -f "/tmp/chrome.msi" ]; then
    FILESIZE=$(du -h /tmp/chrome.msi | cut -f1)
    log_success "Chrome Installer downloaded successfully."
    log_info "File Path: /tmp/chrome.msi"
    log_info "File Size: $FILESIZE"
else
    log_error "Chrome download failed. Check your internet connection."
    exit 1
fi

# --- 3. OS Selection ---
log_step "STEP 3: Operating System Selection"
echo "  1) Windows 2019 (Recommended)"
echo "  2) Windows 10 Super Lite SF"
echo "  3) Windows 10 Super Lite MF"
echo "  4) Windows 10 Super Lite CF"
echo "  5) Windows 11 Normal"
echo "  6) Windows 10 Normal"
echo "  7) Custom Link"
read -p "Select OS [1]: " PILIHOS

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
log_info "Selected URL: $PILIHOS"

# --- 4. Network Detection ---
log_step "STEP 4: Detecting Network Configuration"
IP4=$(curl -4 -s icanhazip.com)
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)
NETMASK="255.255.240.0"

# Fallbacks
[ -z "$IP4" ] && IP4="192.168.0.100"
[ -z "$GW" ] && GW="192.168.0.1"

echo "   ----------------------------"
echo "   IP Address : $IP4"
echo "   Gateway    : $GW"
echo "   Netmask    : $NETMASK"
echo "   ----------------------------"
log_success "Network configuration captured."

# --- 5. Create Startup Script ---
log_step "STEP 5: Generating 'win_setup.bat'"
log_info "Constructing the PowerShell auto-fix script..."

# Note: We use EOF quoted to prevent variable expansion issues if needed, 
# but here we need variables to expand, so we use standard EOF.
cat >/tmp/win_setup.bat<<EOF
@ECHO OFF
REM --- REQUEST ADMIN PRIVILEGES ---
cd.>%windir%\\GetAdmin
if exist %windir%\\GetAdmin (del /f /q "%windir%\\GetAdmin") else (
  echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\\Admin.vbs"
  "%temp%\\Admin.vbs"
  del /f /q "%temp%\\Admin.vbs"
  exit /b 2
)

REM --- LOGGING START ---
ECHO Starting Windows Setup > C:\\setup_log.txt

REM --- PART 1: UNIVERSAL NETWORK FIX (PowerShell) ---
REM This automatically detects the active network card and assigns the IP
ECHO Configuring Network... >> C:\\setup_log.txt
powershell -Command "Get-NetAdapter | Where-Object Status -eq 'Up' | New-NetIPAddress -IPAddress $IP4 -PrefixLength 20 -DefaultGateway $GW -AddressFamily IPv4; Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses ('8.8.8.8','8.8.4.4')"

REM --- PART 2: DISK EXPANSION ---
ECHO Extending Disk... >> C:\\setup_log.txt
ECHO SELECT DISK 0 > C:\\diskpart.txt
ECHO LIST PARTITION >> C:\\diskpart.txt
ECHO SELECT PARTITION 2 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO SELECT PARTITION 1 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO EXIT >> C:\\diskpart.txt
DISKPART /S C:\\diskpart.txt
del /f /q C:\\diskpart.txt

REM --- PART 3: FIREWALL ---
ECHO Opening RDP Ports... >> C:\\setup_log.txt
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes

REM --- PART 4: INSTALL CHROME (FROM C: DRIVE) ---
ECHO Installing Chrome... >> C:\\setup_log.txt
if exist "C:\\chrome.msi" (
    msiexec /i "C:\\chrome.msi" /quiet /norestart
    del /f /q "C:\\chrome.msi"
    ECHO Chrome Installed. >> C:\\setup_log.txt
) else (
    ECHO Chrome MSI not found on C root. >> C:\\setup_log.txt
)

REM --- CLEANUP ---
ECHO Cleanup... >> C:\\setup_log.txt
cd /d "%ProgramData%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup"
del /f /q win_setup.bat
exit
EOF

if [ -f "/tmp/win_setup.bat" ]; then
    log_success "Batch script generated at /tmp/win_setup.bat"
else
    log_error "Failed to generate batch script."
    exit 1
fi

# --- 6. Write Image ---
log_step "STEP 6: Writing Windows Image to Disk"
log_info "Unmounting active partitions..."
umount -f /dev/vda* 2>/dev/null

log_info "Starting Download & Write stream..."
log_info "WARNING: This will take time. Please wait."

if echo "$PILIHOS" | grep -qiE '\.gz($|\?)'; then
  wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
else
  wget --no-check-certificate -O- "$PILIHOS" | dd of=/dev/vda bs=4M status=progress
fi

echo ""
log_info "Syncing disk cache..."
sync
sleep 2

# --- 7. Partition Logic ---
log_step "STEP 7: Partition Detection & Mounting"
log_info "Reloading partition table..."
partprobe /dev/vda
sleep 5

# Loop to find partition
MAX_RETRIES=10
COUNT=1
TARGET=""

while [ $COUNT -le $MAX_RETRIES ]; do
    if [ -b /dev/vda2 ]; then
        TARGET="/dev/vda2"
        break
    elif [ -b /dev/vda1 ]; then
        TARGET="/dev/vda1"
        break
    fi
    echo "   Attempt $COUNT/$MAX_RETRIES: Waiting for Windows partition..."
    sleep 3
    partprobe /dev/vda
    COUNT=$((COUNT+1))
done

if [ -z "$TARGET" ]; then
    log_error "Partition not found after $MAX_RETRIES attempts."
    log_error "The image likely failed to write or is corrupt."
    exit 1
fi

log_success "Windows Partition Found: $TARGET"

log_info "Fixing NTFS Dirty Flags..."
ntfsfix -d "$TARGET"

log_info "Mounting partition..."
mkdir -p /mnt/windows
mount.ntfs-3g -o remove_hiberfile,rw "$TARGET" /mnt/windows

if mountpoint -q /mnt/windows; then
    log_success "Mounted successfully."
else
    log_error "Mount failed."
    exit 1
fi

# --- 8. Injection ---
log_step "STEP 8: Injecting Files"
DEST="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"

# Ensure directory exists
if [ ! -d "$DEST" ]; then
    log_info "Startup folder not found, creating it..."
    mkdir -p "$DEST"
fi

# Inject Batch File
log_info "Copying 'win_setup.bat' to Startup..."
cp -f /tmp/win_setup.bat "$DEST/win_setup.bat"

# Verify Batch File
if [ -f "$DEST/win_setup.bat" ]; then
    log_success "win_setup.bat injected."
else
    log_error "Failed to inject win_setup.bat"
    exit 1
fi

# Inject Chrome MSI
log_info "Copying 'chrome.msi' to C:\ Root..."
cp -f /tmp/chrome.msi /mnt/windows/chrome.msi

# Verify Chrome MSI
if [ -f "/mnt/windows/chrome.msi" ]; then
    SIZE=$(du -h /mnt/windows/chrome.msi | cut -f1)
    log_success "Chrome MSI injected. (Size on disk: $SIZE)"
else
    log_error "Failed to inject Chrome MSI."
    exit 1
fi

# List files for user verification
echo ""
echo "--- VERIFICATION OF C:\ ---"
ls -lh /mnt/windows/chrome.msi
echo "--- VERIFICATION OF STARTUP ---"
ls -lh "$DEST/win_setup.bat"
echo "---------------------------"

# --- 9. Finish ---
log_step "STEP 9: Finalizing"
log_info "Unmounting..."
umount /mnt/windows
sync

echo "===================================================="
echo "   ✅ INSTALLATION COMPLETE "
echo "===================================================="
echo "1. The Droplet will power off in 5 seconds."
echo "2. Go to DigitalOcean -> Turn OFF Recovery Mode."
echo "3. Power ON the Droplet."
echo "4. Wait ~2 minutes."
echo "5. Connect via RDP to: $IP4"
echo "===================================================="

sleep 5
poweroff
