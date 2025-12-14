#!/bin/sh
# Huawei Manager Installer for OpenWrt
# Repository: https://github.com/rdk-i/huawei-manager
# License: MIT

set -e

# Configuration
REPO_OWNER="rdk-i"
REPO_NAME="huawei-manager"
PKG_NAME="huawei-manager"
CONFIG_FILE="/etc/config/huawei-manager"
TEMP_DIR="/tmp/huawei-manager-install"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

# Colors for output (if terminal supports it)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_banner() {
    echo ""
    echo "=========================================="
    echo "   Huawei Manager Installer for OpenWrt"
    echo "=========================================="
    echo ""
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    print_info "Memeriksa dependensi..."
    
    # Check for required commands
    for cmd in opkg wget; do
        if ! command -v $cmd >/dev/null 2>&1; then
            print_error "Command '$cmd' tidak ditemukan. Pastikan Anda menjalankan di OpenWrt."
            exit 1
        fi
    done
    
    # Check for either curl or wget for API calls
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_CMD="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_CMD="wget"
    else
        print_error "curl atau wget diperlukan untuk mengunduh file."
        exit 1
    fi
    
    print_success "Semua dependensi tersedia."
}

get_latest_release_url() {
    print_info "Mendapatkan URL rilis terbaru dari GitHub..."
    
    mkdir -p "$TEMP_DIR"
    
    if [ "$DOWNLOAD_CMD" = "curl" ]; then
        RELEASE_INFO=$(curl -s "$API_URL" 2>/dev/null) || RELEASE_INFO=""
    else
        RELEASE_INFO=$(wget -qO- "$API_URL" 2>/dev/null) || RELEASE_INFO=""
    fi
    
    # Parse JSON to get the IPK download URL
    # Look for .ipk file in assets
    if [ -n "$RELEASE_INFO" ]; then
        IPK_URL=$(echo "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*\.ipk"' | head -1 | cut -d'"' -f4)
        VERSION=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    # Fallback: Try to get from release folder in repository
    if [ -z "$IPK_URL" ]; then
        print_warning "Tidak dapat menemukan file IPK di GitHub Releases."
        print_info "Mencoba mengunduh dari folder release di repository..."
        
        # Try common IPK filename pattern from release folder
        IPK_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/release/${PKG_NAME}_1.0.0-1_all.ipk"
        VERSION="1.0.0"
        
        # Verify the URL is accessible
        if [ "$DOWNLOAD_CMD" = "curl" ]; then
            if ! curl -sfI "$IPK_URL" >/dev/null 2>&1; then
                print_error "Tidak dapat menemukan file IPK."
                print_info "Pastikan file IPK tersedia di GitHub Releases atau folder release/."
                exit 1
            fi
        else
            if ! wget -q --spider "$IPK_URL" 2>/dev/null; then
                print_error "Tidak dapat menemukan file IPK."
                print_info "Pastikan file IPK tersedia di GitHub Releases atau folder release/."
                exit 1
            fi
        fi
    fi
    
    print_success "Ditemukan rilis: $VERSION"
    print_info "URL: $IPK_URL"
}

download_ipk() {
    print_info "Mengunduh paket IPK..."
    
    IPK_FILE="$TEMP_DIR/${PKG_NAME}.ipk"
    
    if [ "$DOWNLOAD_CMD" = "curl" ]; then
        curl -L -o "$IPK_FILE" "$IPK_URL"
    else
        wget -O "$IPK_FILE" "$IPK_URL"
    fi
    
    if [ ! -f "$IPK_FILE" ]; then
        print_error "Gagal mengunduh file IPK."
        exit 1
    fi
    
    print_success "Paket berhasil diunduh."
}

backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        print_info "Membackup konfigurasi..."
        cp "$CONFIG_FILE" "$TEMP_DIR/huawei-manager.config.bak"
        print_success "Konfigurasi dibackup ke $TEMP_DIR/huawei-manager.config.bak"
        return 0
    fi
    return 1
}

restore_config() {
    if [ -f "$TEMP_DIR/huawei-manager.config.bak" ]; then
        print_info "Memulihkan konfigurasi..."
        cp "$TEMP_DIR/huawei-manager.config.bak" "$CONFIG_FILE"
        print_success "Konfigurasi berhasil dipulihkan."
    fi
}

install_package() {
    print_info "Menginstal paket..."
    
    # Install dependencies first
    print_info "Menginstal dependensi..."
    opkg update >/dev/null 2>&1 || true
    opkg install python3 python3-pip luci-base luci-lib-jsonc 2>/dev/null || {
        print_warning "Beberapa dependensi mungkin sudah terinstal atau tidak tersedia."
    }
    
    # Install the package
    opkg install "$TEMP_DIR/${PKG_NAME}.ipk"
    
    if [ $? -eq 0 ]; then
        print_success "Paket berhasil diinstal!"
        
        # Install Python dependency
        print_info "Menginstal huawei-lte-api..."
        pip3 install huawei-lte-api --quiet 2>/dev/null || {
            print_warning "Gagal menginstal huawei-lte-api. Anda mungkin perlu menginstalnya secara manual."
        }
        
        # Clear LuCI cache
        rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
        
        print_success "Instalasi selesai!"
        print_info "Akses Huawei Manager melalui LuCI: Services > Huawei Manager"
    else
        print_error "Gagal menginstal paket."
        exit 1
    fi
}

update_package() {
    print_info "Memperbarui paket..."
    
    # Backup config before update
    HAS_CONFIG=0
    if backup_config; then
        HAS_CONFIG=1
    fi
    
    # Remove old package (but opkg will preserve conffiles by default)
    if opkg list-installed | grep -q "^${PKG_NAME} "; then
        opkg remove "$PKG_NAME" 2>/dev/null || true
    fi
    
    # Install new package
    opkg install "$TEMP_DIR/${PKG_NAME}.ipk"
    
    if [ $? -eq 0 ]; then
        # Restore config if it was backed up and got overwritten
        if [ $HAS_CONFIG -eq 1 ]; then
            restore_config
        fi
        
        # Update Python dependency
        print_info "Memperbarui huawei-lte-api..."
        pip3 install --upgrade huawei-lte-api --quiet 2>/dev/null || true
        
        # Clear LuCI cache
        rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
        
        # Restart service
        /etc/init.d/huawei-manager restart 2>/dev/null || true
        
        print_success "Pembaruan selesai!"
    else
        print_error "Gagal memperbarui paket."
        # Try to restore config anyway
        if [ $HAS_CONFIG -eq 1 ]; then
            restore_config
        fi
        exit 1
    fi
}

remove_package() {
    print_info "Menghapus paket..."
    
    # Ask about config preservation
    echo ""
    echo "Apakah Anda ingin menyimpan file konfigurasi?"
    echo "  1) Ya, simpan konfigurasi"
    echo "  2) Tidak, hapus semuanya"
    echo ""
    printf "Pilihan [1-2]: "
    read -r KEEP_CONFIG
    
    case "$KEEP_CONFIG" in
        2)
            # Remove completely including config
            if [ -f "$CONFIG_FILE" ]; then
                rm -f "$CONFIG_FILE"
            fi
            ;;
        *)
            # Backup config
            if [ -f "$CONFIG_FILE" ]; then
                cp "$CONFIG_FILE" "/etc/config/huawei-manager.bak"
                print_info "Konfigurasi dibackup ke /etc/config/huawei-manager.bak"
            fi
            ;;
    esac
    
    # Stop service first
    /etc/init.d/huawei-manager stop 2>/dev/null || true
    /etc/init.d/huawei-manager disable 2>/dev/null || true
    
    # Remove package
    opkg remove "$PKG_NAME" 2>/dev/null || {
        print_warning "Paket tidak ditemukan atau sudah dihapus."
    }
    
    # Clear LuCI cache
    rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
    
    print_success "Penghapusan selesai!"
}

check_installed() {
    if opkg list-installed | grep -q "^${PKG_NAME} "; then
        INSTALLED_VERSION=$(opkg list-installed | grep "^${PKG_NAME} " | cut -d' ' -f3)
        return 0
    fi
    return 1
}

show_menu() {
    print_banner
    
    # Check if package is already installed
    if check_installed; then
        print_info "Status: Terinstal (versi $INSTALLED_VERSION)"
    else
        print_info "Status: Belum terinstal"
    fi
    
    echo ""
    echo "Pilih aksi yang ingin dilakukan:"
    echo ""
    echo "  1) Install    - Instal Huawei Manager"
    echo "  2) Update     - Perbarui ke versi terbaru"
    echo "  3) Remove     - Hapus Huawei Manager"
    echo "  4) Exit       - Keluar"
    echo ""
    printf "Pilihan [1-4]: "
    read -r CHOICE
    
    case "$CHOICE" in
        1)
            if check_installed; then
                print_warning "Paket sudah terinstal. Gunakan opsi Update untuk memperbarui."
                echo ""
                printf "Lanjutkan instalasi ulang? [y/N]: "
                read -r CONFIRM
                case "$CONFIRM" in
                    [yY]|[yY][eE][sS])
                        ;;
                    *)
                        exit 0
                        ;;
                esac
            fi
            check_dependencies
            get_latest_release_url
            download_ipk
            install_package
            ;;
        2)
            if ! check_installed; then
                print_warning "Paket belum terinstal. Gunakan opsi Install terlebih dahulu."
                exit 1
            fi
            check_dependencies
            get_latest_release_url
            download_ipk
            update_package
            ;;
        3)
            if ! check_installed; then
                print_warning "Paket belum terinstal."
                exit 0
            fi
            remove_package
            ;;
        4)
            print_info "Keluar..."
            exit 0
            ;;
        *)
            print_error "Pilihan tidak valid."
            exit 1
            ;;
    esac
}

cleanup() {
    # Clean up temporary files
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

# Main execution
trap cleanup EXIT

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    print_error "Script ini harus dijalankan sebagai root."
    exit 1
fi

# Show menu
show_menu

exit 0