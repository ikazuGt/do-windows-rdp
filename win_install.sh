#!/bin/bash
#
# DIGITALOCEAN WINDOWS INSTALLER - FINAL FIXED VERSION
# Date: 2025-11-27
#

# --- LOGGING ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   UNIVERSAL WINDOWS INSTALLER (FINAL FIX)         "
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
echo "  1) Windows Server 2019 (Recommended)"
echo "  2) Windows Server 2016"
echo "  3) Windows 10 Super Lite SF"
echo "  4) Windows 10 Super Lite MF"
echo "  5) Windows 10 Super Lite CF"
echo "  6) Windows 11 Normal"
echo "  7) Windows 10 Normal (Enterprise)"
echo "  8) Windows Server 2022 (Recommended)"
echo "  9) Custom Link"
read -p "Select [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://download1511.mediafire.com/dfibcx8d27sg10dad69S91EE0WHeAOlyhtI8Z63sQq6-4XeZwIEjKkMQN9fwW_5SflScHihzJvAuPrkYhGhEtuNkk011xRMbKmpU4woIAeYn_o6t9089zvmLxZQhQN81s3xBEdDoQAvrm2Pemfxj1CPht1REGaRrytTFONl7d8BdUrzF/5bnp3aoc7pi7jl9/windows2019DO.gz";;
  2) PILIHOS="https://download1078.mediafire.com/2ti1izymr4sgSszwIT4P7rbGKB-3hzCPsfT4jKXqI9sbP4PkKVPorB4iW64jaaqWxUYd1STLMH_gd844Dy2jfUxui04RnnCH-tGNyo0EYnoC1fyG972e1hg1j5qi6QqTKsy8HewiJiww4dzyJwLUmpP0Dha6AydjupNV8xzLg6fMIaNx/5shsxviym1a1yza/Windows_Server_2016_Datacenter_EVAL_en-us_14393_refresh.ISO.gz";;
  3) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  4) PILIHOS="https://download1582.mediafire.com/lemxvneeredgyBT5P6YtAU5Dq-mikaH29djd8VnlyMcV1iM_vHJzYCiTc8V3PQkUslqgQSG0ftRJ0X2w3t1D7T4a-616-phGqQ2xKCn8894r0fdV9jKMhVYKH8N1dXMvtsZdK6e4t9F4Hg66wCzpXvuD_jcRu9_-i65_Kbr-HeW8Bw/gcxlheshfpbyigg/wedus10lite.gz";;
  5) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  6) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  7) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win10_en.gz";;
  8) PILIHOS="http://167.172.75.15/windows2022.gz";;
  9) read -p "Enter Direct Link: " PILIHOS;;
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

# --- SUBNET MASK CALCULATION FOR DIGITALOCEAN ---
if [ "$CLEAN_PREFIX" -ge 16 ] && [ "$CLEAN_PREFIX" -le 24 ]; then
    THIRD_OCTET=$(( 256 - (1 << (24 - CLEAN_PREFIX)) ))
    SUBNET_MASK="255.255.${THIRD_OCTET}.0"
else
    SUBNET_MASK="255.255.255.0"
fi

# Display network configuration
log_info "Network Configuration Detected:"
echo "   IP Address:    $CLEAN_IP"
echo "   Gateway:       $GW"
echo "   Subnet Mask:   $SUBNET_MASK"
echo "   Prefix Length: $CLEAN_PREFIX"
echo ""
read -p "Press ENTER to continue or CTRL+C to abort..."

# --- 5. GENERATE BATCH FILE (UNIVERSAL COMPATIBILITY) ---
log_step "STEP 5: Generating Universal System Script"

cat > /tmp/setup.cmd << 'EOFBATCH'
@ECHO OFF
SETLOCAL EnableDelayedExpansion
SET IP=PLACEHOLDER_IP
SET GW=PLACEHOLDER_GW
SET MASK=PLACEHOLDER_MASK
SET PREFIX=PLACEHOLDER_PREFIX

REM Create a log file in C:\ to verify execution
ECHO [START] Script running as %USERNAME% at %DATE% %TIME% > C:\do_install.log
ECHO [DEBUG] IP=%IP%, GW=%GW%, MASK=%MASK%, PREFIX=%PREFIX% >> C:\do_install.log

REM --- 1. WAIT FOR DRIVERS ---
ECHO [LOG] Waiting 15 seconds for drivers/services... >> C:\do_install.log
timeout /t 15 /nobreak >nul

REM --- 2. DISABLE FIREWALL & NLA ---
ECHO [LOG] Disabling Firewall and NLA... >> C:\do_install.log
powershell -Command "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False" >> C:\do_install.log 2>&1
netsh advfirewall set allprofiles state off >> C:\do_install.log 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" /f >> C:\do_install.log 2>&1

REM --- 3. CONFIGURE NETWORK (MULTI-METHOD APPROACH) ---
ECHO [LOG] Configuring Network (Universal Mode)... >> C:\do_install.log

REM METHOD A: Modern PowerShell
ECHO [LOG] Trying PowerShell method... >> C:\do_install.log
powershell -Command "try { $Adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }; foreach ($Adapter in $Adapters) { Write-Host 'Configuring adapter:' $Adapter.Name; Remove-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue; Remove-NetRoute -InterfaceIndex $Adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue; New-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -IPAddress %IP% -PrefixLength %PREFIX% -DefaultGateway %GW% -ErrorAction Stop; Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses ('8.8.8.8', '8.8.4.4') -ErrorAction Stop; Write-Host 'PowerShell method succeeded for' $Adapter.Name; exit 0 } } catch { Write-Host 'PowerShell method failed:' $_.Exception.Message; exit 1 }" >> C:\do_install.log 2>&1

IF %ERRORLEVEL% NEQ 0 (
    ECHO [LOG] PowerShell failed, trying NetSh method... >> C:\do_install.log
    
    REM METHOD B: NetSh
    FOR /F "tokens=*" %%A IN ('netsh interface show interface ^| findstr /I "Connected Ethernet"') DO (
        FOR /F "tokens=3*" %%B IN ("%%A") DO (
            SET IFACE=%%C
            ECHO [LOG] Found interface: !IFACE! >> C:\do_install.log
            netsh interface ip set address name="!IFACE!" static %IP% %MASK% %GW% >> C:\do_install.log 2>&1
            netsh interface ip set dns name="!IFACE!" static 8.8.8.8 primary >> C:\do_install.log 2>&1
            netsh interface ip add dns name="!IFACE!" 8.8.4.4 index=2 >> C:\do_install.log 2>&1
            ECHO [LOG] NetSh configured: !IFACE! >> C:\do_install.log
        )
    )
)

REM --- 4. EXTEND DISK ---
ECHO [LOG] Extending Disk... >> C:\do_install.log
(
echo select disk 0
echo list partition
echo select partition 2
echo extend
) > C:\diskpart.txt
diskpart /s C:\diskpart.txt >> C:\do_install.log 2>&1
del /f /q C:\diskpart.txt

REM --- 5. ENABLE RDP ---
ECHO [LOG] Enabling RDP... >> C:\do_install.log
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >> C:\do_install.log 2>&1
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f >> C:\do_install.log 2>&1
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >> C:\do_install.log 2>&1

REM --- 6. ENABLE ADMINISTRATOR ACCOUNT ---
ECHO [LOG] Enabling Administrator account... >> C:\do_install.log
net user Administrator /active:yes >> C:\do_install.log 2>&1

REM --- 7. INSTALL CHROME ---
if exist "C:\chrome.msi" (
    ECHO [LOG] Installing Chrome... >> C:\do_install.log
    msiexec /i "C:\chrome.msi" /quiet /norestart >> C:\do_install.log 2>&1
)

REM --- 8. ADDITIONAL COMPATIBILITY FIXES ---
ECHO [LOG] Applying compatibility fixes... >> C:\do_install.log
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f >> C:\do_install.log 2>&1
reg add "HKLM\SOFTWARE\Microsoft\ServerManager" /v DoNotOpenServerManagerAtLogon /t REG_DWORD /d 1 /f >> C:\do_install.log 2>&1
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >> C:\do_install.log 2>&1

REM --- 9. VERIFY NETWORK ---
ECHO [LOG] Network Verification... >> C:\do_install.log
ipconfig /all >> C:\do_install.log 2>&1
ping -n 2 8.8.8.8 >> C:\do_install.log 2>&1

ECHO ============================================ >> C:\do_install.log
ECHO [DONE] Setup Complete at %DATE% %TIME% >> C:\do_install.log
ECHO ============================================ >> C:\do_install.log
EOFBATCH

# Inject Variables
sed -i "s/PLACEHOLDER_IP/$CLEAN_IP/g" /tmp/setup.cmd
sed -i "s/PLACEHOLDER_GW/$GW/g" /tmp/setup.cmd
sed -i "s/PLACEHOLDER_MASK/$SUBNET_MASK/g" /tmp/setup.cmd
sed -i "s/PLACEHOLDER_PREFIX/$CLEAN_PREFIX/g" /tmp/setup.cmd

# --- 6. WRITE IMAGE ---
log_step "STEP 6: Writing OS to Disk"
umount -f /dev/vda* 2>/dev/null

# CHECK IF COMPRESSED AND DOWNLOAD ACCORDINGLY
if echo "$PILIHOS" | grep -qiE '\.gz($|\?)'; then
  log_info "Detected Compressed Image (.gz). Unzipping on the fly..."
  wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
else
  log_info "Detected Raw Image. Writing directly..."
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

if [ -z "$TARGET" ]; then
    log_error "Partition not found. The image write might have failed or the image is corrupt."
    exit 1
fi

log_info "Partition Found: $TARGET. Fixing NTFS..."
ntfsfix -d "$TARGET" > /dev/null 2>&1

mkdir -p /mnt/windows
mount.ntfs-3g -o remove_hiberfile,rw "$TARGET" /mnt/windows || mount.ntfs-3g -o force,rw "$TARGET" /mnt/windows

# --- 8. INJECT FILES (SYSTEM SCRIPTS) ---
log_step "STEP 8: Injecting System Scripts"

PATH_SETUP="/mnt/windows/Windows/Setup/Scripts"
mkdir -p "$PATH_SETUP"

# Copy Chrome to the root C:\
cp -v /tmp/chrome.msi /mnt/windows/chrome.msi

# INJECTION: SetupComplete.cmd (Universal Script)
cp -f /tmp/setup.cmd "$PATH_SETUP/SetupComplete.cmd"
log_success "Injected Universal script into SetupComplete.cmd"

# Create a secondary recovery script in Startup folder
log_info "Creating recovery script for Startup folder..."
cat > /tmp/recovery.cmd << 'EOFRECOVERY'
@ECHO OFF
REM Secondary recovery script - runs on user login
ECHO [RECOVERY] Recovery script started at %DATE% %TIME% > C:\recovery.log

IF NOT EXIST "C:\do_install.log" (
    ECHO [RECOVERY] SetupComplete.cmd may not have run >> C:\recovery.log
    ECHO [RECOVERY] Attempting manual configuration... >> C:\recovery.log
    IF EXIST "C:\Windows\Setup\Scripts\SetupComplete.cmd" (
        ECHO [RECOVERY] Running SetupComplete.cmd... >> C:\recovery.log
        call "C:\Windows\Setup\Scripts\SetupComplete.cmd"
    ) ELSE (
        ECHO [RECOVERY] SetupComplete.cmd not found >> C:\recovery.log
    )
) ELSE (
    ECHO [RECOVERY] Setup already completed successfully >> C:\recovery.log
)

REM Self-delete after successful run
IF EXIST "C:\do_install.log" (
    ECHO [RECOVERY] Deleting recovery script... >> C:\recovery.log
    timeout /t 3 /nobreak
    del "%~f0"
)
EOFRECOVERY

# Inject recovery script into startup
mkdir -p "/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/StartUp"
cp -f /tmp/recovery.cmd "/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/StartUp/recovery.cmd" 2>/dev/null

# Also create a manual configuration script on Desktop
log_info "Creating manual configuration helper..."
cat > /tmp/manual_config.cmd << 'EOFMANUAL'
@ECHO OFF
TITLE Manual Network Configuration Helper
ECHO ================================================
ECHO   MANUAL NETWORK CONFIGURATION TOOL
ECHO ================================================
ECHO.
ECHO If automatic configuration failed, use this tool.
ECHO.
ECHO Current Network Adapters:
netsh interface show interface
ECHO.
ECHO ================================================
PAUSE

SET /P ADAPTER="Enter adapter name (e.g., Ethernet): "
SET /P IP="Enter IP Address: "
SET /P MASK="Enter Subnet Mask (e.g., 255.255.255.0): "
SET /P GATEWAY="Enter Gateway: "

ECHO.
ECHO Configuring %ADAPTER%...
netsh interface ip set address name="%ADAPTER%" static %IP% %MASK% %GATEWAY%
netsh interface ip set dns name="%ADAPTER%" static 8.8.8.8
netsh interface ip add dns name="%ADAPTER%" 8.8.4.4 index=2

ECHO.
ECHO Configuration complete! Testing connection...
ping -n 4 8.8.8.8

ECHO.
ECHO Current IP Configuration:
ipconfig /all

PAUSE
EOFMANUAL

cp -f /tmp/manual_config.cmd /mnt/windows/Users/Public/Desktop/ManualNetworkConfig.cmd 2>/dev/null || \
cp -f /tmp/manual_config.cmd /mnt/windows/Users/Default/Desktop/ManualNetworkConfig.cmd 2>/dev/null

# --- 9. FINISH ---
log_step "STEP 9: Cleaning Up"
sync
umount /mnt/windows

echo "===================================================="
echo "       INSTALLATION COMPLETE (UNIVERSAL)            "
echo "===================================================="
echo " Supports: Windows Server 2016/2019/2022, Win10/11 "
echo "===================================================="
echo " 1. Droplet is powering off NOW"
echo " 2. Turn OFF Recovery Mode in DigitalOcean panel"
echo " 3. Power ON the droplet"
echo " 4. Wait 3-5 minutes for Windows to boot"
echo " 5. Check C:\do_install.log via VNC for details"
echo " 6. Connect RDP to: $CLEAN_IP"
echo " 7. Use the default credentials from your Windows image"
echo "===================================================="
sleep 5
poweroff
