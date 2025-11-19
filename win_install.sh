#!/bin/bash
#
# DIGITALOCEAN INSTALLER - OFFLINE CHROME - SMART PARTITION
#

# --- 1. INSTALL TOOLS ---
echo "Installing NTFS and Partition tools..."
apt-get update -q
apt-get install -y ntfs-3g parted

# --- 2. CHOOSE WINDOWS ---
echo "------------------------------------------------"
echo "Pilih Versi Windows:"
echo "	1) Windows 2019 (Default - Recommended)"
echo "	2) Windows 10 Super Lite SF"
echo "	3) Windows 10 Super Lite MF"
echo "	4) Windows 10 Super Lite CF"
echo "	5) Custom Link"
read -p "Pilih [1]: " PILIHOS

case "$PILIHOS" in
	1|"") PILIHOS="https://sourceforge.net/projects/nixpoin/files/windows2019DO.gz";;
	2) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
	3) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
	4) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
	5) read -p "Link GZ: " PILIHOS;;
	*) echo "Salah pilih"; exit;;
esac

# Capture IP details from the Recovery Environment to inject into Windows
IP4=$(curl -4 -s icanhazip.com)
GW=$(ip route | awk '/default/ { print $3 }')

# --- 3. CREATE STARTUP SCRIPT (Injects into Windows) ---
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

# --- 4. FLASH IMAGE ---
echo "Downloading and writing image..."
wget --no-check-certificate -O- $PILIHOS | gunzip | dd of=/dev/vda bs=3M status=progress

# --- 5. REFRESH PARTITION TABLE (Fixes 'No such file') ---
echo "Flushing cache..."
sync
echo "Refreshing partitions..."
partprobe /dev/vda
sleep 10

# --- 6. SMART PARTITION DETECTION ---
if [ -b "/dev/vda2" ]; then
    TARGET="/dev/vda2"
    echo "Detected Target: $TARGET"
elif [ -b "/dev/vda1" ]; then
    TARGET="/dev/vda1"
    echo "Detected Target: $TARGET"
else
    echo "ERROR: Disk write failed. No partitions found."
    ls -la /dev/vda*
    exit 1
fi

# --- 7. INJECT ---
echo "Fixing NTFS..."
ntfsfix $TARGET

echo "Mounting and Injecting..."
mkdir -p /mnt
mount.ntfs-3g $TARGET /mnt

DEST="/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
if [ -d "$DEST" ]; then
    cp -f /tmp/win_setup.bat "$DEST/win_setup.bat"
    echo "Injection Successful."
else
    cp -f /tmp/win_setup.bat "/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/win_setup.bat" 2>/dev/null
fi

umount /mnt

# --- 8. SHUTDOWN FOR DO CONFIG ---
echo "------------------------------------------------"
echo "INSTALLATION FINISHED."
echo "The VPS will POWER OFF in 5 seconds."
echo "------------------------------------------------"
echo "NEXT STEPS (DIGITAL OCEAN):"
echo "1. Wait for the VPS to turn off."
echo "2. Go to DO Panel -> Recovery -> Turn OFF Recovery (Boot from Hard Drive)."
echo "3. Turn ON the Droplet."
echo "4. Login RDP 3389 (User: Administrator / Pass: Botol123456789!)."
echo "5. WATCH THE SCREEN: A command prompt will appear to install Chrome."
echo "------------------------------------------------"
sleep 5
poweroff
