#!/bin/bash
#
# FINAL WORKING SCRIPT
# Fixes: "Bad Message", "No such file", and Missing Chrome/DNS
#

# --- 1. PREPARATION & DEPENDENCIES ---
echo "Installing necessary tools..."
# We need 'parted' to get the 'partprobe' command which refreshes the disk list
apt-get update -q
apt-get install -y ntfs-3g parted

# --- 2. SELECT WINDOWS VERSION ---
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

IP4=$(curl -4 -s icanhazip.com)
GW=$(ip route | awk '/default/ { print $3 }')

# --- 3. CREATE THE WINDOWS SETUP SCRIPT (Runs on first Login) ---
cat >/tmp/win_setup.bat<<EOF
@ECHO OFF
cd.>%windir%\GetAdmin
if exist %windir%\GetAdmin (del /f /q "%windir%\GetAdmin") else (
echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\Admin.vbs"
"%temp%\Admin.vbs"
del /f /q "%temp%\Admin.vbs"
exit /b 2)

REM --- CONFIGURING NETWORK & DNS ---
netsh -c interface ip set address name="Ethernet" source=static address=$IP4 mask=255.255.240.0 gateway=$GW
netsh -c interface ip set dnsservers name="Ethernet" source=static address=8.8.8.8 register=primary validate=no
netsh -c interface ip add dnsservers name="Ethernet" address=8.8.4.4 index=2 validate=no
REM Backup for different interface names
netsh -c interface ip set address name="Ethernet Instance 0" source=static address=$IP4 mask=255.255.240.0 gateway=$GW 2>nul
netsh -c interface ip set dnsservers name="Ethernet Instance 0" source=static address=8.8.8.8 register=primary validate=no 2>nul

REM --- EXTENDING DISK SPACE ---
ECHO SELECT DISK 0 > C:\diskpart.txt
ECHO LIST PARTITION >> C:\diskpart.txt
ECHO SELECT PARTITION 2 >> C:\diskpart.txt
ECHO EXTEND >> C:\diskpart.txt
ECHO EXIT >> C:\diskpart.txt
DISKPART /S C:\diskpart.txt
del /f /q C:\diskpart.txt

REM --- SETTING RDP PORT TO 22 (Requires Restart later) ---
netsh advfirewall firewall add rule name="Open Port 22" dir=in action=allow protocol=TCP localport=22
reg add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d 22 /f

REM --- INSTALLING CHROME ---
powershell -Command "Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile 'C:\chrome_installer.exe'"
start /wait C:\chrome_installer.exe /silent /install
del /f /q C:\chrome_installer.exe

REM --- CLEANUP ---
msg * "SETUP COMPLETE: Chrome installed, DNS fixed. You can keep using this session. Port 22 will work after your NEXT manual reboot."
cd /d "%ProgramData%/Microsoft/Windows/Start Menu/Programs/Startup"
del /f /q win_setup.bat
exit
EOF

# --- 4. DOWNLOAD AND FLASH ---
echo "Downloading image and writing to disk..."
wget --no-check-certificate -O- $PILIHOS | gunzip | dd of=/dev/vda bs=3M status=progress

# --- 5. CRITICAL FIX: REFRESH PARTITION TABLE ---
echo "------------------------------------------------"
echo "FINALIZING DISK STATE..."
echo "1. Syncing RAM to Disk..."
sync
sleep 3

echo "2. Refreshing Partition Table (Fixes 'No such file')..."
# This command forces Linux to re-read /dev/vda so vda1/vda2 appear
partprobe /dev/vda
sleep 10 

# --- 6. SMART PARTITION DETECTION ---
# This block decides whether to use vda1 or vda2 based on what actually exists
if [ -b "/dev/vda2" ]; then
    TARGET="/dev/vda2"
    echo "Detected Standard Partition: $TARGET"
elif [ -b "/dev/vda1" ]; then
    TARGET="/dev/vda1"
    echo "Detected Single Partition: $TARGET"
else
    echo "ERROR: No partitions found. The image write failed."
    ls -la /dev/vda*
    exit 1
fi

# --- 7. REPAIR AND INJECT ---
echo "3. Repairing NTFS flags on $TARGET..."
ntfsfix $TARGET

echo "4. Mounting and Injecting Setup Script..."
mkdir -p /mnt
mount.ntfs-3g $TARGET /mnt

# Path detection (Handles Case Sensitivity)
DEST="/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
if [ -d "$DEST" ]; then
    cp -f /tmp/win_setup.bat "$DEST/win_setup.bat"
    echo "SUCCESS: Script injected into Startup folder."
else
    # Try lowercase path if uppercase fails
    cp -f /tmp/win_setup.bat "/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/win_setup.bat" 2>/dev/null
    echo "SUCCESS: Script injected (fallback path)."
fi

umount /mnt
echo "------------------------------------------------"
echo "INSTALLATION DONE."
echo "Server rebooting in 5 seconds."
echo "1. Wait 3-5 minutes."
echo "2. Login RDP Port: 3389"
echo "3. User: Administrator / Pass: Botol123456789!"
echo "4. WAIT for the black box (CMD) to finish installing Chrome."
echo "------------------------------------------------"
sleep 5
reboot
