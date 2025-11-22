#!/bin/bash
#
# DIGITALOCEAN INSTALLER - FIXED & ROBUST
# Fixes: TLS 1.2 for Chrome, Read-Write Mounts, Partition Detection
# Date: 2025-11-22
#

# Don't use set -e globally, we want to handle errors manually for mounting
# set -e 

echo "===================================================="
echo "      WINDOWS INSTALLER FOR DIGITALOCEAN            "
echo "===================================================="

# --- 1. Install Dependencies ---
echo "[+] Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -y ntfs-3g parted psmisc curl wget

# --- 2. OS Selection ---
echo "===================================================="
echo "Select Windows Version:"
echo "  1) Windows 2019 (Recommended)"
echo "  2) Windows 10 Super Lite SF"
echo "  3) Windows 10 Super Lite MF"
echo "  4) Windows 10 Super Lite CF"
echo "  5) Windows 11 Normal"
echo "  6) Windows 10 Normal"
echo "  7) Custom Link (GZ/ISO)"
read -p "Select [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://sourceforge.net/projects/nixpoin/files/windows2019DO.gz";;
  2) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  3) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  4) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  5) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  6) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win10_en.gz";;
  7) read -p "Enter Direct Link: " PILIHOS;;
  *) echo "Invalid selection"; exit 1;;
esac

# --- 3. Network Detection ---
echo "===================================================="
echo "[+] Detecting Network..."
IP4=$(curl -4 -s icanhazip.com)
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)
NETMASK="255.255.240.0" # Standard DO Netmask

if [ -z "$IP4" ] || [ -z "$GW" ]; then
    echo "ERROR: Could not detect IP or Gateway."
    echo "Please check your internet connection."
    exit 1
fi

echo "    IP: $IP4"
echo "    GW: $GW"
echo "    NM: $NETMASK"

# --- 4. Create Windows Batch Script ---
# Note: We escape % as %% for the batch file execution
# Note: We force TLS12 for the download to work
echo "[+] Creating Setup Script..."
cat >/tmp/win_setup.bat<<EOF
@ECHO OFF
cd.>%windir%\\GetAdmin
if exist %windir%\\GetAdmin (del /f /q "%windir%\\GetAdmin") else (
  echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\\Admin.vbs"
  "%temp%\\Admin.vbs"
  del /f /q "%temp%\\Admin.vbs"
  exit /b 2
)

REM --- NETWORK CONFIG ---
netsh interface ip set address name="Ethernet" source=static address=$IP4 mask=$NETMASK gateway=$GW
netsh interface ip set dns name="Ethernet" static 8.8.8.8 primary
netsh interface ip add dns name="Ethernet" 8.8.4.4 index=2

netsh interface ip set address name="Ethernet Instance 0" source=static address=$IP4 mask=$NETMASK gateway=$GW 2>nul
netsh interface ip set dns name="Ethernet Instance 0" static 8.8.8.8 primary 2>nul
netsh interface ip add dns name="Ethernet Instance 0" 8.8.4.4 index=2 2>nul

netsh interface ip set address name="Ethernet 2" source=static address=$IP4 mask=$NETMASK gateway=$GW 2>nul
netsh interface ip set dns name="Ethernet 2" static 8.8.8.8 primary 2>nul
netsh interface ip add dns name="Ethernet 2" 8.8.4.4 index=2 2>nul

REM --- DISK EXPANSION ---
ECHO SELECT DISK 0 > C:\\diskpart.txt
ECHO LIST PARTITION >> C:\\diskpart.txt
ECHO SELECT PARTITION 2 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO SELECT PARTITION 1 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO EXIT >> C:\\diskpart.txt
DISKPART /S C:\\diskpart.txt
del /f /q C:\\diskpart.txt

REM --- FIREWALL ---
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes

REM --- CHROME INSTALL (FIXED TLS & URL) ---
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Try { Invoke-WebRequest -Uri 'https://dl.google.com/tag/s/appguid%%3D%%7B8A69D345-D564-463C-AFF1-A69D9E530F96%%7D%%26iid%%3D%%7BD8B6B20A-C037-C71E-AFA0-33475D286188%%7D%%26lang%%3Den-GB%%26browser%%3D3%%26usagestats%%3D0%%26appname%%3DGoogle%%2520Chrome%%26needsadmin%%3Dprefers%%26ap%%3Dx64-statsdef_1%%26installdataindex%%3Dempty/chrome/install/ChromeStandaloneSetup64.exe' -OutFile 'C:\\ChromeStandaloneSetup64.exe'; } Catch { Write-Host 'Download Failed'; Exit 1 }"

if exist C:\\ChromeStandaloneSetup64.exe (
    start /wait C:\\ChromeStandaloneSetup64.exe /silent /install
    del /f /q C:\\ChromeStandaloneSetup64.exe
)

REM --- CLEANUP ---
cd /d "%ProgramData%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup"
del /f /q win_setup.bat
exit
EOF

# --- 5. Write Image to Disk ---
echo "===================================================="
echo "[+] Writing System to Disk (This takes time)..."
echo "===================================================="

# Unmount anything just in case
umount -f /dev/vda* 2>/dev/null

if echo "$PILIHOS" | grep -qiE '\.gz($|\?)'; then
  wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
else
  wget --no-check-certificate -O- "$PILIHOS" | dd of=/dev/vda bs=4M status=progress
fi

echo ""
echo "[+] Syncing disks..."
sync

# --- 6. Partition Refresh & Detection ---
echo "[+] Refreshing Partition Table..."
partprobe /dev/vda
sleep 5

# Wait loop for partition
MAX_RETRIES=10
COUNT=0
TARGET=""

while [ $COUNT -lt $MAX_RETRIES ]; do
    if [ -b /dev/vda2 ]; then
        TARGET="/dev/vda2"
        break
    elif [ -b /dev/vda1 ]; then
        TARGET="/dev/vda1"
        break
    fi
    echo "    Waiting for partitions... ($COUNT)"
    sleep 2
    partprobe /dev/vda
    COUNT=$((COUNT+1))
done

if [ -z "$TARGET" ]; then
    echo "❌ ERROR: No Windows partition found after writing."
    echo "The image might be corrupt or download failed."
    exit 1
fi

echo "[+] Target Partition Found: $TARGET"

# --- 7. Mounting & Injection ---
echo "[+] Preparing Mount..."
ntfsfix -d "$TARGET" 2>/dev/null # Clear dirty flag

mkdir -p /mnt/windows
# Try force mounting RW
mount.ntfs-3g -o remove_hiberfile,rw "$TARGET" /mnt/windows || mount.ntfs-3g -o force,rw "$TARGET" /mnt/windows

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Could not mount Windows partition."
    exit 1
fi

echo "[+] Injecting Startup Script..."
DEST="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"

# Fallback if ProgramData doesn't exist (Rare but possible)
if [ ! -d "$DEST" ]; then
    mkdir -p "$DEST"
fi

cp -f /tmp/win_setup.bat "$DEST/win_setup.bat"

if [ -f "$DEST/win_setup.bat" ]; then
    echo "✅ INJECTION SUCCESSFUL!"
else
    echo "❌ ERROR: File copy failed. Partition might be Read-Only."
    exit 1
fi

# --- 8. Finish ---
echo "[+] Unmounting..."
sync
umount /mnt/windows

echo "===================================================="
echo "       INSTALLATION COMPLETE - REBOOTING            "
echo "===================================================="
echo "1. Droplet will power off."
echo "2. Go to DigitalOcean Control Panel."
echo "3. Turn OFF Recovery Mode (Set to Hard Drive)."
echo "4. Power ON the droplet."
echo "5. Wait 3-5 mins, then RDP to $IP4"
echo "===================================================="

sleep 3
poweroff
