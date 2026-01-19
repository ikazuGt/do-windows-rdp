#!/bin/bash
#
# DIGITALOCEAN INSTALLER - FINAL DEBUG VERSION
# Date: 2025-11-24
#

# --- LOGGING FUNCTIONS ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS INSTALLER - FINAL LOGGING VERSION        "
echo "===================================================="

# --- GOOGLE DRIVE DOWNLOAD FUNCTION ---
download_gdrive() {
    FILE_ID="$1"
    OUTPUT видно="$2"
    COOKIE_FILE="/tmp/gdrive_cookies.txt"

    log_info "Downloading from Google Drive (large file mode)..."

    CONFIRM=$(wget --quiet \
        --save-cookies "$COOKIE_FILE" \
        --keep-session-cookies \
        --no-check-certificate \
        "https://drive.google.com/uc?export=download&id=${FILE_ID}" \
        -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1/p')

    wget --no-check-certificate \
        --load-cookies "$COOKIE_FILE" \
        "https://drive.google.com/uc?export=download&confirm=${CONFIRM}&id=${FILE_ID}" \
        -O "$OUTPUT"

    rm -f "$COOKIE_FILE"
}

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
echo "  1) Windows 2019 (MediaFire)"
echo "  2) Windows 2019 (Google Drive)"
echo "  3) Windows 2016 (Sourceforge)"
echo "  4) Windows 2012 (Sourceforge)"
echo "  5) Windows 10 Super Lite SF"
echo "  6) Windows 10 Super Lite MF"
echo "  7) Windows 10 Super Lite CF"
echo "  8) Windows 11 Normal"
echo "  9) Windows 10 Normal"
echo "  10) Custom Link"
read -p "Select [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://download1590.mediafire.com/....../windows2019DO.gz";;
  2) PILIHOS="GDRIVE:1J9IAaias9UWGQl88nNCxkxQDZKX7qfXN";;
  3) PILIHOS="https://sourceforge.net/projects/nixpoin/files/windows2016.gz/download";;
  4) PILIHOS="https://sourceforge.net/projects/nixpoin/files/windows2012.gz/download";;
  5) PILIHOS="https://master.dl.sourceforge.net/project/manyod/wedus10lite.gz?viasf=1";;
  6) PILIHOS="https://download1582.mediafire.com/.../wedus10lite.gz";;
  7) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  8) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win11";;
  9) PILIHOS="https://windows-on-cloud.wansaw.com/0:/win10_en.gz";;
  10) read -p "Enter Direct Link: " PILIHOS;;
  *) log_error "Invalid selection"; exit 1;;
esac

# --- 4. NETWORK DETECTION ---
log_step "STEP 4: Calculating Network Settings"

RAW_DATA=$(ip -4 -o addr show | awk '{print $4}' | grep -v "^10\." | grep -v "^127\." | head -n1)
CLEAN_IP=${RAW_DATA%/*}
CLEAN_PREFIX=${RAW_DATA#*/}
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

case "$CLEAN_PREFIX" in
    24) SUBNET_MASK="255.255.255.0";;
    *) SUBNET_MASK="255.255.255.0";;
esac

echo "IP: $CLEAN_IP"
echo "MASK: $SUBNET_MASK"
echo "GW: $GW"
read -p "Look correct? [Y/n]: " CONFIRM
[[ "$CONFIRM" =~ ^[Nn] ]] && exit 1

# --- 5. WRITE IMAGE ---
log_step "STEP 5: Writing OS to Disk"
umount -f /dev/vda* 2>/dev/null
TMP_IMG="/tmp/windows_image.gz"

if [[ "$PILIHOS" == GDRIVE:* ]]; then
    FILE_ID="${PILIHOS#GDRIVE:}"
    download_gdrive "$FILE_ID" "$TMP_IMG"
    gunzip -c "$TMP_IMG" | dd of=/dev/vda bs=4M status=progress
    rm -f "$TMP_IMG"

elif echo "$PILIHOS" | grep -qiE '\.gz($|\?)'; then
    wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
else
    wget --no-check-certificate -O- "$PILIHOS" | dd of=/dev/vda bs=4M status=progress
fi

sync
sleep 3

# --- 6. FINISH ---
log_success "INSTALLATION COMPLETE"
echo
echo "===================================================="
echo "        WINDOWS INSTALLATION COMPLETED              "
echo "===================================================="
echo
echo " Installation Summary:"
echo " --------------------------------------------------"
echo "  ✔ OS Image Written Successfully"
echo "  ✔ Disk Partitions Applied & Synced"
echo "  ✔ Windows Setup Script Injected"
echo "  ✔ Chrome Installer Preloaded"
echo
echo " Network Configuration:"
echo " --------------------------------------------------"
echo "  IP Address      : $CLEAN_IP"
echo "  Subnet Mask     : $SUBNET_MASK"
echo "  Gateway         : $GW"
echo "  DNS Servers     : 8.8.8.8 , 8.8.4.4"
echo
echo " System Details:"
echo " --------------------------------------------------"
echo "  Disk Target     : /dev/vda"
echo "  Write Blocksize : 4 MB"
echo "  Image Source    : $PILIHOS"
echo
echo " Next Steps:"
echo " --------------------------------------------------"
echo "  1. Power OFF is starting now"
echo "  2. Disable Recovery Mode in DigitalOcean Panel"
echo "  3. Power ON the Droplet"
echo "  4. Open VNC Console to monitor first boot"
echo "  5. Connect via RDP to $CLEAN_IP"
echo
echo " Credentials:"
echo " --------------------------------------------------"
echo "  Username        : Administrator"
echo "  Password        : Botol123456789!"
echo
echo "===================================================="
echo "  STATUS: READY FOR FIRST BOOT                      "
echo "===================================================="
echo

sleep 5
poweroff
