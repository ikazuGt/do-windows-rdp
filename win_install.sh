#!/bin/bash
#
# DIGITALOCEAN INSTALLER - ENTERPRISE FIX (SetupComplete.cmd)
# Date: 2025-11-26
# Fixes: Uses System Level Injection to bypass OOBE/Login requirements
#

# --- LOGGING ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS 10 ENTERPRISE INSTALLER (SYSTEM LEVEL)   "
echo "===================================================="

# --- 1. INSTALL DEPENDENCIES ---
log_step "STEP 1: Installing Dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y ntfs-3g parted psmisc curl wget jq || { log_error "Failed to install tools"; exit 1; }

# --- 2. DOWNLOAD CHROME ---
log_step "STEP 2: Pre-downloading Chrome"
wget -q --show-progress --progress=bar:force -O /tmp/chrome.msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"

# --- 3. OS SELECTION ---
log_step "STEP 3: Select Operating System"
echo "  1) Windows 2019 (Recommended)"
echo "  2) Windows Server 2016"
echo "  3) Windows 10 Super Lite SF"
echo "  4) Windows 10 Super Lite MF"
echo "  5) Windows 10 Super Lite CF"
echo "  6) Windows 11 Normal"
echo "  7) Windows 10 Normal (Enterprise)"
echo "  8) Custom Link"
read -p "Select [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://download1511.mediafire.com/dfibcx8d27sg10dad69S91EE0WHeAOlyhtI8Z63sQq6-4XeZwIEjKkMQN9fwW_5SflScHihzJvAuPrkYhGhEtuNkk011xRMbKmpU4woIAeYn_o6t9089zvmLxZQhQN81s3xBEdDoQAvrm2Pemfxj1CPht1REGaRrytTFONl7d8BdUrzF/5bnp3aoc7pi7jl9/windows2019DO.gz";;
  2) PILIHOS="https://download1078.mediafire.com/2ti1izymr4sgSszwIT4P7rbGKB-3hzCPsfT4jKXqI9sbP4PkKVPorB4iW64jaaqWxUYd1STLMH_gd844Dy2jfUxui04RnnCH-tGNyo0EYnoC1fyG972e1hg1j5qi6QqTKsy8HewiJiww4dzyJwLUmpP0Dha6AydjupNV8xzLg6fMIaNx/5shsxviym1a1yza/Windows_Server_2016_Datacenter_EVAL_en-us_14393_refresh.ISO.gz";;
  3) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  4) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  5) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  6) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  7) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win10_en.gz";;
  8) read -p "Enter Direct Link: " PILIHOS;;
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
    IP_BASE=$(echo "$CLEAN_IP" | cut -d. -f1-3)
    GW="${IP_BASE}.1"
fi

case "$CLEAN_PREFIX" in
    8) SUBNET_MASK="255.0.0.0";;
    16) SUBNET_MASK="255.255.0.0";;
    20) SUBNET_MASK="255.255.240.0";;
    24) SUBNET_MASK="255.255.255.0";;
    *) SUBNET_MASK="255.255.255.0";;
esac

echo "   ---------------------------"
echo "   IP             : $CLEAN_IP"
echo "   Subnet Mask    : $SUBNET_MASK"
echo "   Gateway        : $GW"
echo "   ---------------------------"

if [[ "$CLEAN_IP" == *"/"* ]] || [ -z "$CLEAN_IP" ]; then
    log_error "IP Detection Failed."
    exit 1
fi

read -p "Look correct? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then exit 1; fi

# --- 5. GENERATE BATCH FILE ---
log_step "STEP 5: Generating System Script"

cat > /tmp/setup.cmd << 'EOFBATCH'
@ECHO OFF
SETLOCAL EnableDelayedExpansion
SET IP=PLACEHOLDER_IP
SET MASK=PLACEHOLDER_MASK
SET GW=PLACEHOLDER_GW

REM Create a log file in C:\ to verify execution
ECHO [START] Script running as %USERNAME% > C:\do_install.log

REM --- 1. DISABLE FIREWALL (CRITICAL FOR RDP) ---
ECHO [LOG] Disabling Firewall... >> C:\do_install.log
netsh advfirewall set allprofiles state off >> C:\do_install.log 2>&1

REM --- 2. WAIT FOR DRIVERS ---
ECHO [LOG] Waiting for drivers... >> C:\do_install.log
timeout /t 10 /nobreak >nul

REM --- 3. CONFIGURE NETWORK (PRIORITY ORDER) ---
ECHO [LOG] Configuring Network... >> C:\do_install.log

REM Try Priority 1: Ethernet Instance 0 (The good one)
netsh interface ip set address name="Ethernet Instance 0" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1 >> C:\do_install.log 2>&1
netsh interface ip set dns name="Ethernet Instance 0" source=static addr=8.8.8.8 >> C:\do_install.log 2>&1
netsh interface ip add dns name="Ethernet Instance 0" addr=8.8.4.4 index=2 >> C:\do_install.log 2>&1

REM Try Priority 2: Ethernet (Standard)
netsh interface ip set address name="Ethernet" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1 >> C:\do_install.log 2>&1
netsh interface ip set dns name="Ethernet" source=static addr=8.8.8.8 >> C:\do_install.log 2>&1

REM Try Priority 3: Ethernet Instance 2 (The backup)
netsh interface ip set address name="Ethernet Instance 2" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1 >> C:\do_install.log 2>&1
netsh interface ip set dns name="Ethernet Instance 2" source=static addr=8.8.8.8 >> C:\do_install.log 2>&1

REM --- 4. ENABLE RDP ---
ECHO [LOG] Enabling RDP... >> C:\do_install.log
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >> C:\do_install.log 2>&1
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >> C:\do_install.log 2>&1

REM --- 5. EXTEND DISK ---
(
echo select disk 0
echo list partition
echo select partition 2
echo extend
echo select partition 1
echo extend
) > C:\diskpart.txt
diskpart /s C:\diskpart.txt >> C:\do_install.log 2>&1

REM --- 6. INSTALL CHROME ---
if exist "C:\chrome.msi" (
    ECHO [LOG] Installing Chrome... >> C:\do_install.log
    msiexec /i "C:\chrome.msi" /quiet /norestart
)

REM --- 7. CREATE USER (IF NEEDED) ---
REM Some Enterprise ISOs have disabled Admin accounts. We force one just in case.
net user Administrator /active:yes >> C:\do_install.log 2>&1
net user Administrator "Admin123!" >> C:\do_install.log 2>&1

ECHO [DONE] Setup Complete >> C:\do_install.log
EOFBATCH

# Inject Bash Variables
sed -i "s/PLACEHOLDER_IP/$CLEAN_IP/g" /tmp/setup.cmd
sed -i "s/PLACEHOLDER_MASK/$SUBNET_MASK/g" /tmp/setup.cmd
sed -i "s/PLACEHOLDER_GW/$GW/g" /tmp/setup.cmd

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

# --- 8. INJECT FILES (DUAL INJECTION) ---
log_step "STEP 8: Injecting System Scripts"

# Define Paths
PATH_SETUP="/mnt/windows/Windows/Setup/Scripts"
PATH_STARTUP="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
PATH_ADMIN_STARTUP="/mnt/windows/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"

# Create Directories
mkdir -p "$PATH_SETUP"
mkdir -p "$PATH_STARTUP"
mkdir -p "$PATH_ADMIN_STARTUP"

# Copy Chrome
cp -v /tmp/chrome.msi /mnt/windows/chrome.msi

# INJECTION 1: SetupComplete.cmd (The Enterprise Fix)
# This file is executed by Windows SYSTEM process before login.
cp -f /tmp/setup.cmd "$PATH_SETUP/SetupComplete.cmd"
log_success "Injected into Windows/Setup/Scripts/SetupComplete.cmd"

# INJECTION 2: Normal Startup (Backup)
cp -f /tmp/setup.cmd "$PATH_STARTUP/win_setup.bat"
cp -f /tmp/setup.cmd "$PATH_ADMIN_STARTUP/win_setup.bat"
log_success "Injected into Startup Folders"

# --- 9. FINISH ---
log_step "STEP 9: Cleaning Up"
sync
umount /mnt/windows

echo "===================================================="
echo "       INSTALLATION SUCCESSFUL!                     "
echo "===================================================="
echo " 1. Droplet is powering off NOW"
echo " 2. Turn OFF Recovery Mode"
echo " 3. Power ON the droplet"
echo " 4. IMPORTANT: Wait 3-5 minutes for OOBE to finish"
echo " 5. Connect RDP to: $CLEAN_IP"
echo "    Username: Administrator"
echo "    Password: Admin123! (If reset by script)"
echo "===================================================="
sleep 5
poweroff
