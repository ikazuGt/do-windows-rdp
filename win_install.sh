#!/bin/bash
#
# DIGITALOCEAN INSTALLER - OFFLINE CHROME - CLEAN VERSION
# No RDP port change, no Remote Settings modifications
# Date: 2025-11-21
#

set -e

NETMASK="255.255.240.0"  # Adjust if needed

echo "===================================================="
echo "Installing tools..."
echo "===================================================="
apt-get update -q
apt-get install -y ntfs-3g parted psmisc curl

echo "===================================================="
echo "Pilih Versi Windows:"
echo "  1) Windows 2019 (Default - Recommended)"
echo "  2) Windows 10 Super Lite SF"
echo "  3) Windows 10 Super Lite MF"
echo "  4) Windows 10 Super Lite CF"
echo "  5) Windows 11"
echo "  6) Custom Link"
read -p "Pilih [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://sourceforge.net/projects/nixpoin/files/windows2019DO.gz";;
  2) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  3) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  4) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  5) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  6) read -p "Link GZ: " PILIHOS;;
  *) echo "Salah pilih"; exit 1;;
esac

echo "===================================================="
echo "Detecting Network Configuration..."
echo "===================================================="
IP4=$(curl -4 -s icanhazip.com || echo "192.168.1.100")
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)
[ -z "$GW" ] && GW="192.168.1.1"

echo "IP: $IP4"
echo "Gateway: $GW"
echo "Netmask: $NETMASK"

echo "===================================================="
echo "Creating Windows startup script..."
echo "===================================================="
cat >/tmp/win_setup.bat<<EOF
@ECHO OFF
REM Elevate if needed
cd.>%windir%\\GetAdmin
if exist %windir%\\GetAdmin (del /f /q "%windir%\\GetAdmin") else (
  echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\\Admin.vbs"
  "%temp%\\Admin.vbs"
  del /f /q "%temp%\\Admin.vbs"
  exit /b 2
)

REM --- 1. Static IP & DNS ---
netsh interface ip set address name="Ethernet" source=static address=$IP4 mask=$NETMASK gateway=$GW
netsh interface ip set dns name="Ethernet" static 8.8.8.8 primary
netsh interface ip add dns name="Ethernet" 8.8.4.4 index=2

netsh interface ip set address name="Ethernet Instance 0" source=static address=$IP4 mask=$NETMASK gateway=$GW 2>nul
netsh interface ip set dns name="Ethernet Instance 0" static 8.8.8.8 primary 2>nul
netsh interface ip add dns name="Ethernet Instance 0" 8.8.4.4 index=2 2>nul

netsh interface ip set address name="Ethernet 2" source=static address=$IP4 mask=$NETMASK gateway=$GW 2>nul
netsh interface ip set dns name="Ethernet 2" static 8.8.8.8 primary 2>nul
netsh interface ip add dns name="Ethernet 2" 8.8.4.4 index=2 2>nul

REM --- 2. Extend Disk (attempt partition 2 then 1) ---
ECHO SELECT DISK 0 > C:\\diskpart.txt
ECHO LIST PARTITION >> C:\\diskpart.txt
ECHO SELECT PARTITION 2 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO SELECT PARTITION 1 >> C:\\diskpart.txt
ECHO EXTEND >> C:\\diskpart.txt
ECHO EXIT >> C:\\diskpart.txt
DISKPART /S C:\\diskpart.txt
del /f /q C:\\diskpart.txt

REM --- 3. Ensure RDP (default port 3389) firewall group enabled ---
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes

REM --- 4. Offline Chrome Install ---
powershell -Command "Try { Invoke-WebRequest -Uri 'https://dl.google.com/tag/s/appguid%%3D%%7B8A69D345-D564-463C-AFF1-A69D9E530F96%%7D%%26iid%%3D%%7B104BF221-10C7-17CD-EB6C-119B16421526%%7D%%26lang%%3Den%%26browser%%3D4%%26usagestats%%3D1%%26appname%%3DGoogle%%20Chrome%%26needsadmin%%3Dprefers%%26ap%%3D-arch_x64-statsdef_1%%26installdataindex%%3Dempty/chrome/install/ChromeStandaloneSetup64.exe' -OutFile 'C:\\ChromeStandaloneSetup64.exe'; } Catch { Write-Host 'Chrome download failed'; Exit 1 }"
start /wait C:\\ChromeStandaloneSetup64.exe /silent /install
del /f /q C:\\ChromeStandaloneSetup64.exe

REM --- 5. Notify & Cleanup ---
msg * "SETUP COMPLETE. RDP available on port 3389. Chrome installed."
cd /d "%ProgramData%\\Microsoft\\Windows\\Start Menu\\Programs\\Startup"
del /f /q win_setup.bat
exit
EOF

echo "✅ win_setup.bat created"

echo "===================================================="
echo "Writing image to /dev/vda ..."
echo "===================================================="
if echo "$PILIHOS" | grep -qiE '\.gz($|\?)'; then
  wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
else
  wget --no-check-certificate -O- "$PILIHOS" | dd of=/dev/vda bs=4M status=progress
fi

echo "Syncing & releasing locks..."
sync
sleep 2
fuser -km /dev/vda* 2>/dev/null || true
umount -l /dev/vda* 2>/dev/null || true
umount -f /dev/vda* 2>/dev/null || true
sleep 2

echo "Refreshing partition table..."
partprobe /dev/vda || true
blockdev --rereadpt /dev/vda || true
sleep 4

echo "Listing partitions..."
ls -la /dev/vda* || { echo "ERROR: No partitions found"; exit 1; }

echo "Detecting Windows partition..."
if [ -b /dev/vda2 ]; then
  TARGET=/dev/vda2
elif [ -b /dev/vda1 ]; then
  TARGET=/dev/vda1
else
  echo "❌ No partition found"
  lsblk
  exit 1
fi
echo "Using $TARGET"

echo "Preparing partition..."
fuser -km "$TARGET" 2>/dev/null || true
umount -l "$TARGET" 2>/dev/null || true
umount -f "$TARGET" 2>/dev/null || true
sleep 2
ntfsfix "$TARGET" || echo "ntfsfix warnings ignored"

echo "Mounting NTFS..."
mkdir -p /mnt/windows
mount.ntfs-3g -o remove_hiberfile,rw "$TARGET" /mnt/windows || ntfs-3g "$TARGET" /mnt/windows -o force

echo "Injecting startup script..."
DEST="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
if [ ! -d "$DEST" ]; then
  ALT1="/mnt/windows/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
  ALT2="/mnt/windows/ProgramData/Microsoft/Windows/Start\\ Menu/Programs/Startup"
  if [ -d "$ALT1" ]; then DEST="$ALT1"
  elif [ -d "$ALT2" ]; then DEST="$ALT2"
  else mkdir -p "$DEST"; fi
fi

cp -f /tmp/win_setup.bat "$DEST/win_setup.bat"
[ -f "$DEST/win_setup.bat" ] && echo "Injection success ($(stat -c%s "$DEST/win_setup.bat") bytes)" || { echo "Injection failed"; exit 1; }

sync
sleep 1
umount /mnt/windows || umount -l /mnt/windows

echo "===================================================="
echo "✅ Installation finished"
echo "===================================================="
echo "IP: $IP4  Gateway: $GW  Netmask: $NETMASK"
echo "DNS: 8.8.8.8 / 8.8.4.4"
echo "RDP will be on port 3389 (default)."
echo "Next steps:"
echo "  1. Let droplet power off."
echo "  2. Disable recovery mode (boot from hard drive)."
echo "  3. Start droplet, wait a few minutes."
echo "  4. RDP to $IP4:3389 (Administrator / Botol123456789!)."
echo "  5. Script runs, installs Chrome."
for i in 10 9 8 7 6 5 4 3 2 1; do
  echo "Powering off in $i..."
  sleep 1
done
poweroff
