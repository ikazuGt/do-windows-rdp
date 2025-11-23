#!/bin/bash
#
# DIGITALOCEAN INSTALLER - SANITIZED NETWORK VERSION
# Date: 2025-11-22
# Fixes:
#   1. Strips the "/20" from the IP variable (Fixes "Invalid Parameter" error)
#   2. Filters out 10.x.x.x Private IPs explicitly (Fixes "Command not recognized" error)
#

# --- LOGGING ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS INSTALLER - SYNTAX FIX VERSION           "
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

# 1. Get the full line containing the Public IP (Ignore 10.x and 127.x)
# This specifically filters out the Private IP that was breaking your script.
RAW_DATA=$(ip -4 -o addr show | awk '{print $4}' | grep -v "^10\." | grep -v "^127\." | head -n1)

# 2. Strip the CIDR to get Pure IP (e.g., "157.245.13.197")
CLEAN_IP=${RAW_DATA%/*}

# 3. Extract the Prefix only (e.g., "20")
CLEAN_PREFIX=${RAW_DATA#*/}

# 4. Get Gateway
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

echo "   ---------------------------"
echo "   Raw Data  : $RAW_DATA"
echo "   Clean IP  : $CLEAN_IP"
echo "   Prefix    : $CLEAN_PREFIX"
echo "   Gateway   : $GW"
echo "   ---------------------------"

# Safety check
if [[ "$CLEAN_IP" == *"/"* ]] || [ -z "$CLEAN_IP" ]; then
    log_error "IP Sanitization failed. Raw data was: $RAW_DATA"
    exit 1
fi

# --- 5. GENERATE BATCH FILE ---
log_step "STEP 5: Generating Setup Script"

cat >/tmp/win_setup.bat<<EOF
@ECHO OFF
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

REM --- 3. APPLY IP AND DNS (Retry Loop) ---
FOR /L %%N IN (1,1,5) DO (
  ECHO Attempt %%N...
  
  REM Notice: We use $CLEAN_IP and $CLEAN_PREFIX separately now. No slash in IP.
  powershell -Command "Get-NetAdapter | Where-Object Status -eq 'Up' | New-NetIPAddress -IPAddress $CLEAN_IP -PrefixLength $CLEAN_PREFIX -DefaultGateway $GW -AddressFamily IPv4 -ErrorAction SilentlyContinue"
  
  REM Force DNS on all adapters
  powershell -Command "Get-NetAdapter | Set-DnsClientServerAddress -ServerAddresses ('8.8.8.8','1.1.1.1') -ErrorAction SilentlyContinue"
  
  timeout /t 3 /nobreak >nul
)

REM --- 4. DISK EXTEND ---
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
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes

REM --- 6. INSTALL CHROME ---
if exist "C:\\chrome.msi" (
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
echo "===================================================="
sleep 5
poweroff
