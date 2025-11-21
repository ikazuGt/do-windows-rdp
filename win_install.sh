#!/bin/bash
#
# DIGITALOCEAN INSTALLER - OFFLINE CHROME - GUARANTEED INJECTION
# Fixed Version - 2025-11-20
#

set -e  # Exit on any error

# --- 1. INSTALL TOOLS ---
echo "===================================================="
echo "Installing NTFS and Partition tools..."
echo "===================================================="
apt-get update -q
apt-get install -y ntfs-3g parted psmisc

# --- 2. CHOOSE WINDOWS ---
echo "===================================================="
echo "Pilih Versi Windows:"
echo "	1) Windows 2019 (Default - Recommended)"
echo "	2) Windows 10 Super Lite SF"
echo "	3) Windows 10 Super Lite MF"
echo "	4) Windows 10 Super Lite CF"
echo "	5) Windows 11"
echo "	6) Custom Link"
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

# Capture IP details from the Recovery Environment to inject into Windows
echo "===================================================="
echo "Detecting Network Configuration..."
echo "===================================================="
IP4=$(curl -4 -s icanhazip.com || echo "192.168.1.100")
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

if [ -z "$GW" ]; then
    echo "WARNING: Gateway not detected! Using default 192.168.1.1"
    GW="192.168.1.1"
fi

echo "Detected IP: $IP4"
echo "Detected Gateway: $GW"

# --- 3. CREATE STARTUP SCRIPT (Injects into Windows) ---
echo "===================================================="
echo "Creating Windows Setup Script..."
echo "===================================================="
cat >/tmp/win_setup.bat<<EOF
@ECHO OFF
cd.>%windir%\GetAdmin
if exist %windir%\GetAdmin (del /f /q "%windir%\GetAdmin") else (
echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\Admin.vbs"
"%temp%\Admin.vbs"
del /f /q "%temp%\Admin.vbs"
exit /b 2)

REM --- 1. FIX DNS (Using IP detected during install) ---
netsh -c interface ip set address name="Ethernet" source=static address=$IP4 mask=255.255.240.0 gateway=$GW
netsh -c interface ip set dnsservers name="Ethernet" source=static address=8.8.8.8 register=primary validate=no
netsh -c interface ip add dnsservers name="Ethernet" address=8.8.4.4 index=2 validate=no

REM Fallback for other interface names
netsh -c interface ip set address name="Ethernet Instance 0" source=static address=$IP4 mask=255.255.240.0 gateway=$GW 2>nul
netsh -c interface ip set dnsservers name="Ethernet Instance 0" source=static address=8.8.8.8 register=primary validate=no 2>nul

netsh -c interface ip set address name="Ethernet 2" source=static address=$IP4 mask=255.255.240.0 gateway=$GW 2>nul
netsh -c interface ip set dnsservers name="Ethernet 2" source=static address=8.8.8.8 register=primary validate=no 2>nul

REM --- 2. EXTEND DISK ---
ECHO SELECT DISK 0 > C:\diskpart.txt
ECHO LIST PARTITION >> C:\diskpart.txt
ECHO SELECT PARTITION 2 >> C:\diskpart.txt
ECHO EXTEND >> C:\diskpart.txt
ECHO EXIT >> C:\diskpart.txt
DISKPART /S C:\diskpart.txt
del /f /q C:\diskpart.txt

REM --- 3. OPEN RDP PORT 22 (Active after next reboot) ---
netsh advfirewall firewall add rule name="Open Port 22" dir=in action=allow protocol=TCP localport=22
reg add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d 22 /f

REM --- 4. OFFLINE CHROME INSTALL ---
powershell -Command "Invoke-WebRequest -Uri 'https://dl.google.com/tag/s/appguid%%3D%%7B8A69D345-D564-463C-AFF1-A69D9E530F96%%7D%%26iid%%3D%%7B104BF221-10C7-17CD-EB6C-119B16421526%%7D%%26lang%%3Den%%26browser%%3D4%%26usagestats%%3D1%%26appname%%3DGoogle%%20Chrome%%26needsadmin%%3Dprefers%%26ap%%3D-arch_x64-statsdef_1%%26installdataindex%%3Dempty/chrome/install/ChromeStandaloneSetup64.exe' -OutFile 'C:\ChromeStandaloneSetup64.exe'"
start /wait C:\ChromeStandaloneSetup64.exe /silent /install
del /f /q C:\ChromeStandaloneSetup64.exe

REM --- 5. CLEANUP ---
msg * "SETUP COMPLETE. Chrome installed. Use Port 3389 for this session. Port 22 works after next reboot."
cd /d "%ProgramData%/Microsoft/Windows/Start Menu/Programs/Startup"
del /f /q win_setup.bat
exit
EOF

echo "✅ Windows setup script created"

# --- 4. FLASH IMAGE ---
echo "===================================================="
echo "Downloading and writing image..."
echo "This will take several minutes..."
echo "===================================================="
wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress

# --- 5. CRITICAL: FORCE KERNEL TO RELEASE DISK ---
echo "===================================================="
echo "Flushing disk cache..."
echo "===================================================="
sync
sleep 3

echo "Releasing any locks on disk..."
# Kill any process using the disk
fuser -km /dev/vda 2>/dev/null || true
fuser -km /dev/vda1 2>/dev/null || true
fuser -km /dev/vda2 2>/dev/null || true

# Force unmount anything mounted
umount -l /dev/vda* 2>/dev/null || true
umount -f /dev/vda* 2>/dev/null || true

sleep 2

echo "Refreshing partition table..."
partprobe /dev/vda 2>&1 | tee /tmp/partprobe.log || true
blockdev --rereadpt /dev/vda 2>/dev/null || true

sleep 5

echo "Checking available partitions..."
ls -la /dev/vda* || { echo "ERROR: No disk found!"; exit 1; }

# --- 6. SMART PARTITION DETECTION ---
echo "===================================================="
echo "Detecting Windows partition..."
echo "===================================================="

TARGET=""
if [ -b "/dev/vda2" ]; then
    TARGET="/dev/vda2"
elif [ -b "/dev/vda1" ]; then
    TARGET="/dev/vda1"
else
    echo "❌ ERROR: No valid partition found!"
    lsblk
    exit 1
fi

echo "✅ Detected Windows Partition: $TARGET"

# --- 7. FORCE CLEAN MOUNT ---
echo "===================================================="
echo "Preparing partition for injection..."
echo "===================================================="

# Make absolutely sure nothing is using it
fuser -km $TARGET 2>/dev/null || true
umount -l $TARGET 2>/dev/null || true
umount -f $TARGET 2>/dev/null || true
sleep 2

echo "Running NTFS fix (may show warnings - ignore them)..."
ntfsfix $TARGET 2>&1 | tee /tmp/ntfsfix.log || echo "⚠️  ntfsfix warnings (continuing anyway)"

# --- 8. MOUNT AND INJECT ---
echo "===================================================="
echo "Mounting Windows partition..."
echo "===================================================="

mkdir -p /mnt/windows
mount.ntfs-3g -o remove_hiberfile,rw $TARGET /mnt/windows || {
    echo "❌ Mount failed! Trying force mount..."
    ntfs-3g $TARGET /mnt/windows -o force || {
        echo "❌ CRITICAL: Cannot mount partition!"
        echo "Partition details:"
        fdisk -l /dev/vda
        exit 1
    }
}

echo "✅ Mount successful!"

# --- 9. VERIFY AND INJECT ---
echo "===================================================="
echo "Injecting startup script..."
echo "===================================================="

DEST="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"

# Try to create the path if it doesn't exist
if [ ! -d "$DEST" ]; then
    echo "⚠️  Standard startup folder not found. Searching..."
    find /mnt/windows -type d -iname "Startup" 2>/dev/null | head -n 5
    
    # Try alternative paths
    ALT1="/mnt/windows/Users/Administrator/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
    ALT2="/mnt/windows/ProgramData/Microsoft/Windows/Start\ Menu/Programs/Startup"
    
    if [ -d "$ALT1" ]; then
        DEST="$ALT1"
    elif [ -d "$ALT2" ]; then
        DEST="$ALT2"
    else
        echo "Creating startup folder..."
        mkdir -p "$DEST" || {
            echo "❌ Cannot create startup folder!"
            exit 1
        }
    fi
fi

# Copy the batch file
cp -f /tmp/win_setup.bat "$DEST/win_setup.bat" || {
    echo "❌ CRITICAL: Failed to copy startup script!"
    ls -la "$DEST"
    exit 1
}

# Verify injection
if [ -f "$DEST/win_setup.bat" ]; then
    echo "✅ INJECTION SUCCESSFUL!"
    echo "   File size: $(stat -c%s "$DEST/win_setup.bat") bytes"
    echo "   Location: $DEST/win_setup.bat"
else
    echo "❌ VERIFICATION FAILED - File not found after copy!"
    exit 1
fi

# --- 10. SAFE UNMOUNT ---
echo "===================================================="
echo "Finalizing installation..."
echo "===================================================="
sync
sleep 2
umount /mnt/windows || umount -l /mnt/windows

# --- 11. FINAL STATUS ---
echo "===================================================="
echo "✅ INSTALLATION COMPLETED SUCCESSFULLY!"
echo "===================================================="
echo ""
echo "Network Configuration Injected:"
echo "  IP Address : $IP4"
echo "  Gateway    : $GW"
echo "  DNS        : 8.8.8.8, 8.8.4.4"
echo ""
echo "The VPS will POWER OFF in 10 seconds."
echo ""
echo "===================================================="
echo "⚠️  CRITICAL NEXT STEPS (DIGITAL OCEAN):"
echo "===================================================="
echo "1. Wait for the VPS to completely power off"
echo "2. Go to DigitalOcean Panel → Recovery"
echo "3. Turn OFF Recovery Mode (Boot from Hard Drive)"
echo "4. Power ON the Droplet"
echo "5. Wait 2-5 minutes for Windows to boot"
echo "6. Connect via RDP to port 3389:"
echo "   - User: Administrator"
echo "   - Pass: Botol123456789!"
echo "7. A CMD window will appear automatically"
echo "8. Wait for Chrome installation to complete"
echo "9. After next reboot, RDP will be on port 22"
echo "===================================================="
echo ""

# Countdown
for i in 10 9 8 7 6 5 4 3 2 1; do
    echo "Powering off in $i..."
    sleep 1
done

poweroff
