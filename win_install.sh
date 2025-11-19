#!/bin/bash
#
# Fixed Windows Installation Script - All-in-One Fix
#

# 1. Install necessary tools to fix the "Bad Message" error
echo "Installing dependencies..."
if ! command -v ntfsfix &> /dev/null; then
    apt-get update && apt-get install -y ntfs-3g
fi

# 2. User Selection
echo "Pilih Versi Windows yang ingin di install"
echo "	1) Windows 2019 (Default)"
echo "	2) Windows 10 Super Lite SF"
echo "	3) Windows 10 Super Lite MF"
echo "	4) Windows 10 Super Lite CF"
echo "	5) Pakai link gz mu sendiri"
read -p "Pilih [1]: " PILIHOS

case "$PILIHOS" in
	1|"") PILIHOS="https://sourceforge.net/projects/nixpoin/files/windows2019DO.gz";;
	2) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
	3) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
	4) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
	5) read -p "Masukkan Link GZ mu : " PILIHOS;;
	*) echo "pilihan salah"; exit;;
esac

echo "--------------------------------------------------"
echo " WARNING: DO NOT LOSE THIS PASSWORD"
echo "--------------------------------------------------"
read -p "Masukkan password BARU untuk Administrator: " PASSADMIN

IP4=$(curl -4 -s icanhazip.com)
GW=$(ip route | awk '/default/ { print $3 }')

# 3. Create a SINGLE Master Batch file (Prevents errors where Chrome tries to download before DNS is ready)
cat >/tmp/setup_all.bat<<EOF
@ECHO OFF
cd.>%windir%\GetAdmin
if exist %windir%\GetAdmin (del /f /q "%windir%\GetAdmin") else (
echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\Admin.vbs"
"%temp%\Admin.vbs"
del /f /q "%temp%\Admin.vbs"
exit /b 2)

REM --- STEP 1: CHANGE PASSWORD ---
net user Administrator "$PASSADMIN"
wmic useraccount where name='Administrator' set PasswordExpires=FALSE

REM --- STEP 2: NETWORK SETUP ---
REM Try to set for generic interface names
netsh -c interface ip set address name="Ethernet" source=static address=$IP4 mask=255.255.240.0 gateway=$GW
netsh -c interface ip set dnsservers name="Ethernet" source=static address=8.8.8.8 register=primary validate=no
netsh -c interface ip add dnsservers name="Ethernet" address=8.8.4.4 index=2 validate=no

REM Fallback for Instance 0
netsh -c interface ip set address name="Ethernet Instance 0" source=static address=$IP4 mask=255.255.240.0 gateway=$GW 2>nul
netsh -c interface ip set dnsservers name="Ethernet Instance 0" source=static address=8.8.8.8 register=primary validate=no 2>nul

REM Wait for Network to stabilize
timeout 10 >nul

REM --- STEP 3: EXTEND DISK ---
ECHO SELECT DISK 0 > C:\diskpart.txt
ECHO LIST PARTITION >> C:\diskpart.txt
ECHO SELECT PARTITION 2 >> C:\diskpart.txt
ECHO EXTEND >> C:\diskpart.txt
ECHO EXIT >> C:\diskpart.txt
DISKPART /S C:\diskpart.txt
del /f /q C:\diskpart.txt

REM --- STEP 4: FIREWALL & RDP PORT 22 ---
netsh advfirewall firewall add rule name="Open Port 22" dir=in action=allow protocol=TCP localport=22
reg add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d 22 /f

REM --- STEP 5: CHROME DOWNLOAD ---
REM Using a simpler, more reliable direct link
powershell -Command "Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile 'C:\chrome_installer.exe'"
start /wait C:\chrome_installer.exe /silent /install

REM --- CLEANUP ---
cd /d "%ProgramData%/Microsoft/Windows/Start Menu/Programs/Startup"
del /f /q setup_all.bat
shutdown /r /t 5
EOF

# 4. Flash the Image
echo "Downloading and writing image to disk..."
wget --no-check-certificate -O- $PILIHOS | gunzip | dd of=/dev/vda bs=3M status=progress

# 5. CRITICAL FIX: Sync and Repair
echo "Flushing data..."
sync
sleep 5

echo "Repairing NTFS partition to prevent 'Bad Message' error..."
# This is the magic command that fixes your issue
ntfsfix /dev/vda2 

# 6. Mount and Inject
echo "Mounting..."
mkdir -p /mnt
mount.ntfs-3g /dev/vda2 /mnt

# Verify Mount Succeeded
if [ $? -eq 0 ]; then
    echo "Mount successful. Injecting script..."
    
    # Handle different naming conventions (ProgramData vs programdata)
    target_dir="/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
    
    if [ -d "$target_dir" ]; then
        cp -f /tmp/setup_all.bat "$target_dir/setup_all.bat"
        echo "Script injected!"
    else
        # Try case insensitive search if specific path fails
        echo "Standard path not found, searching..."
        cp -f /tmp/setup_all.bat "/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup/setup_all.bat"
    fi
    
    echo "Unmounting..."
    umount /mnt
    
    echo "DONE. Server restarting in 5 seconds."
    echo "IMPORTANT: After restart, wait 2-3 minutes."
    echo "If RDP Port 22 fails, try Port 3389 with user: Administrator"
    sleep 5
    reboot
else
    echo "ERROR: Could not mount partition. The downloaded image might be corrupted."
    ls -la /dev/vda*
fi
