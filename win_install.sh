#!/bin/bash
#
# Fixed Windows Installation Script
#
echo "Pilih titit yang ingin di install"
echo "	1) Windows 2019(Default)"
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
echo "silahkan masukkan password yang lebih aman!"
read -p "Masukkan password untuk akun Administrator (minimal 12 karakter): " PASSADMIN
IP4=$(curl -4 -s icanhazip.com)
GW=$(ip route | awk '/default/ { print $3 }')
cat >/tmp/net.bat<<EOF
@ECHO OFF
cd.>%windir%\GetAdmin
if exist %windir%\GetAdmin (del /f /q "%windir%\GetAdmin") else (
echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\Admin.vbs"
"%temp%\Admin.vbs"
del /f /q "%temp%\Admin.vbs"
exit /b 2)

REM Try both Administrator and administrator usernames
net user Administrator $PASSADMIN 2>nul
if errorlevel 1 (
    net user administrator $PASSADMIN 2>nul
)

REM Get the actual interface name
for /f "tokens=3*" %%i in ('netsh interface show interface ^|findstr /I /R "Connected"') do (set InterfaceName=%%j)

REM Configure network using the detected interface name
netsh -c interface ip set address name="%InterfaceName%" source=static address=$IP4 mask=255.255.240.0 gateway=$GW
netsh -c interface ip set dnsservers name="%InterfaceName%" source=static address=8.8.8.8 register=primary validate=no
netsh -c interface ip add dnsservers name="%InterfaceName%" address=8.8.4.4 index=2 validate=no

REM Also try with common interface names as fallback
netsh -c interface ip set address name="Ethernet" source=static address=$IP4 mask=255.255.240.0 gateway=$GW 2>nul
netsh -c interface ip set dnsservers name="Ethernet" source=static address=8.8.8.8 register=primary validate=no 2>nul
netsh -c interface ip add dnsservers name="Ethernet" address=8.8.4.4 index=2 validate=no 2>nul

netsh -c interface ip set address name="Ethernet Instance 0" source=static address=$IP4 mask=255.255.240.0 gateway=$GW 2>nul
netsh -c interface ip set dnsservers name="Ethernet Instance 0" source=static address=8.8.8.8 register=primary validate=no 2>nul
netsh -c interface ip add dnsservers name="Ethernet Instance 0" address=8.8.4.4 index=2 validate=no 2>nul

REM Wait a bit for network settings to apply
timeout 5 >nul

REM Verify DNS settings were applied
echo Verifying DNS configuration...
netsh interface ip show dnsservers

cd /d "%ProgramData%/Microsoft/Windows/Start Menu/Programs/Startup"
del /f /q net.bat
exit
EOF
cat >/tmp/dpart.bat<<EOF
@ECHO OFF
echo JENDELA INI JANGAN DITUTUP
echo SCRIPT INI AKAN MERUBAH PORT RDP MENJADI 22, SETELAH RESTART UNTUK MENYAMBUNG KE RDP GUNAKAN ALAMAT $IP4:22
echo KETIK YES LALU ENTER!
cd.>%windir%\GetAdmin
if exist %windir%\GetAdmin (del /f /q "%windir%\GetAdmin") else (
echo CreateObject^("Shell.Application"^).ShellExecute "%~s0", "%*", "", "runas", 1 >> "%temp%\Admin.vbs"
"%temp%\Admin.vbs"
del /f /q "%temp%\Admin.vbs"
exit /b 2)
set PORT=22
set RULE_NAME="Open Port %PORT%"
netsh advfirewall firewall show rule name=%RULE_NAME% >nul
if not ERRORLEVEL 1 (
    rem Rule %RULE_NAME% already exists.
    echo Hey, you already got a out rule by that name, you cannot put another one in!
) else (
    echo Rule %RULE_NAME% does not exist. Creating...
    netsh advfirewall firewall add rule name=%RULE_NAME% dir=in action=allow protocol=TCP localport=%PORT%
)
reg add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d 22 /f
REM Extend C: drive to use all unallocated space
ECHO SELECT DISK 0 > "%SystemDrive%\diskpart.extend"
ECHO LIST PARTITION >> "%SystemDrive%\diskpart.extend"
ECHO SELECT PARTITION 2 >> "%SystemDrive%\diskpart.extend"
ECHO EXTEND >> "%SystemDrive%\diskpart.extend"
ECHO EXIT >> "%SystemDrive%\diskpart.extend"
START /WAIT DISKPART /S "%SystemDrive%\diskpart.extend"
del /f /q "%SystemDrive%\diskpart.extend"
REM Download Chrome installer to Desktop
powershell -Command "Invoke-WebRequest -Uri 'https://dl.google.com/tag/s/appguid%%3D%%7B8A69D345-D564-463C-AFF1-A69D9E530F96%%7D%%26iid%%3D%%7BC84811D3-133D-1811-15C6-12EC101711FD%%7D%%26lang%%3Den%%26browser%%3D4%%26usagestats%%3D1%%26appname%%3DGoogle%%2520Chrome%%26needsadmin%%3Dprefers%%26ap%%3D-arch_x64-statsdef_1%%26installdataindex%%3Dempty/chrome/install/ChromeStandaloneSetup64.exe' -OutFile '%PUBLIC%\Desktop\ChromeSetup.exe'"

cd /d "%ProgramData%/Microsoft/Windows/Start Menu/Programs/Startup"
del /f /q dpart.bat
timeout 50 >nul
echo Chrome installer downloaded to Desktop
echo JENDELA INI JANGAN DITUTUP
exit
EOF
wget --no-check-certificate -O- $PILIHOS | gunzip | dd of=/dev/vda bs=3M status=progress
mount.ntfs-3g /dev/vda2 /mnt
cd "/mnt/ProgramData/Microsoft/Windows/Start Menu/Programs/"
cd Start* || cd start*; \
cp -f /tmp/net.bat net.bat
cp -f /tmp/dpart.bat dpart.bat
echo 'Your server will turning off in 3 second'
sleep 3
poweroff
