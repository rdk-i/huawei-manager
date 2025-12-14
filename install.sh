#!/bin/sh
# Huawei Manager Installer for OpenWrt
# Repository: https://github.com/rdk-i/huawei-manager
# License: MIT
#
# Usage:
#   ./install.sh              # Interactive menu
#   ./install.sh install      # Direct install
#   ./install.sh update       # Direct update
#   ./install.sh remove       # Direct remove
#
# For piped execution:
#   wget -qO- https://raw.githubusercontent.com/rdk-i/huawei-manager/main/install.sh | sh -s -- install

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
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

print_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

print_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install   - Install Huawei Manager"
    echo "  update    - Update to latest version"
    echo "  remove    - Remove Huawei Manager"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive menu"
    echo "  $0 install            # Direct install"
    echo "  wget -qO- URL | sh -s -- install  # Piped install"
}

# Read input - works both in interactive and piped mode
read_input() {
    if [ -t 0 ]; then
        # stdin is a terminal, read normally
        read -r REPLY
    elif [ -e /dev/tty ]; then
        # stdin is piped, try to read from tty
        read -r REPLY </dev/tty
    else
        # No tty available, return empty
        REPLY=""
    fi
    echo "$REPLY"
}

check_dependencies() {
    print_info "Checking dependencies..."
    
    # Check for required commands
    for cmd in opkg wget; do
        if ! command -v $cmd >/dev/null 2>&1; then
            print_error "Command '$cmd' not found. Make sure you are running on OpenWrt."
            exit 1
        fi
    done
    
    # Check for either curl or wget for API calls
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_CMD="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_CMD="wget"
    else
        print_error "curl or wget is required to download files."
        exit 1
    fi
    
    print_success "All dependencies are available."
}

get_latest_release_url() {
    print_info "Getting latest release URL from GitHub..."
    
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
        print_warning "Could not find IPK file in GitHub Releases."
        print_info "Trying to download from release folder in repository..."
        
        # Try common IPK filename pattern from release folder
        IPK_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/release/${PKG_NAME}_1.0.0-1_all.ipk"
        VERSION="1.0.0"
        
        # Verify the URL is accessible
        if [ "$DOWNLOAD_CMD" = "curl" ]; then
            if ! curl -sfI "$IPK_URL" >/dev/null 2>&1; then
                print_error "Could not find IPK file."
                print_info "Make sure IPK file is available in GitHub Releases or release/ folder."
                exit 1
            fi
        else
            if ! wget -q --spider "$IPK_URL" 2>/dev/null; then
                print_error "Could not find IPK file."
                print_info "Make sure IPK file is available in GitHub Releases or release/ folder."
                exit 1
            fi
        fi
    fi
    
    print_success "Found release: $VERSION"
    print_info "URL: $IPK_URL"
}

download_ipk() {
    print_info "Downloading IPK package..."
    
    IPK_FILE="$TEMP_DIR/${PKG_NAME}.ipk"
    
    if [ "$DOWNLOAD_CMD" = "curl" ]; then
        curl -L -o "$IPK_FILE" "$IPK_URL"
    else
        wget -O "$IPK_FILE" "$IPK_URL"
    fi
    
    if [ ! -f "$IPK_FILE" ]; then
        print_error "Failed to download IPK file."
        exit 1
    fi
    
    print_success "Package downloaded successfully."
}

backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        print_info "Backing up configuration..."
        cp "$CONFIG_FILE" "$TEMP_DIR/huawei-manager.config.bak"
        print_success "Configuration backed up to $TEMP_DIR/huawei-manager.config.bak"
        return 0
    fi
    return 1
}

restore_config() {
    if [ -f "$TEMP_DIR/huawei-manager.config.bak" ]; then
        print_info "Restoring configuration..."
        cp "$TEMP_DIR/huawei-manager.config.bak" "$CONFIG_FILE"
        print_success "Configuration restored successfully."
    fi
}

install_package() {
    print_info "Installing package..."
    
    # Install dependencies first
    print_info "Installing dependencies..."
    opkg update >/dev/null 2>&1 || true
    opkg install python3 python3-pip luci-base luci-lib-jsonc 2>/dev/null || {
        print_warning "Some dependencies may already be installed or unavailable."
    }
    
    # Install the package
    opkg install "$TEMP_DIR/${PKG_NAME}.ipk"
    
    if [ $? -eq 0 ]; then
        print_success "Package installed successfully!"
        
        # Install Python dependency
        print_info "Installing huawei-lte-api..."
        pip3 install huawei-lte-api --quiet 2>/dev/null || {
            print_warning "Failed to install huawei-lte-api. You may need to install it manually."
        }
        
        # Clear LuCI cache
        rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
        
        print_success "Installation complete!"
        print_info "Access Huawei Manager via LuCI: Services > Huawei Manager"
    else
        print_error "Failed to install package."
        exit 1
    fi
}

update_package() {
    print_info "Updating package..."
    
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
        print_info "Updating huawei-lte-api..."
        pip3 install --upgrade huawei-lte-api --quiet 2>/dev/null || true
        
        # Clear LuCI cache
        rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
        
        # Restart service
        /etc/init.d/huawei-manager restart 2>/dev/null || true
        
        print_success "Update complete!"
    else
        print_error "Failed to update package."
        # Try to restore config anyway
        if [ $HAS_CONFIG -eq 1 ]; then
            restore_config
        fi
        exit 1
    fi
}

remove_package() {
    print_info "Removing package..."
    
    # Ask about config preservation (default: keep config)
    KEEP_CONFIG="1"
    if [ -t 0 ] || [ -e /dev/tty ]; then
        echo ""
        echo "Do you want to keep the configuration file?"
        echo "  1) Yes, keep configuration"
        echo "  2) No, remove everything"
        echo ""
        printf "Choice [1-2]: "
        KEEP_CONFIG=$(read_input)
    fi
    
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
                print_info "Configuration backed up to /etc/config/huawei-manager.bak"
            fi
            ;;
    esac
    
    # Stop service first
    /etc/init.d/huawei-manager stop 2>/dev/null || true
    /etc/init.d/huawei-manager disable 2>/dev/null || true
    
    # Remove package
    opkg remove "$PKG_NAME" 2>/dev/null || {
        print_warning "Package not found or already removed."
    }
    
    # Clear LuCI cache
    rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
    
    print_success "Removal complete!"
}

check_installed() {
    if opkg list-installed | grep -q "^${PKG_NAME} "; then
        INSTALLED_VERSION=$(opkg list-installed | grep "^${PKG_NAME} " | cut -d' ' -f3)
        return 0
    fi
    return 1
}

do_install() {
    if check_installed; then
        print_warning "Package is already installed (version $INSTALLED_VERSION)."
        if [ -t 0 ] || [ -e /dev/tty ]; then
            printf "Continue with reinstall? [y/N]: "
            CONFIRM=$(read_input)
            case "$CONFIRM" in
                [yY]|[yY][eE][sS])
                    ;;
                *)
                    exit 0
                    ;;
            esac
        else
            print_info "Non-interactive mode: proceeding with reinstall..."
        fi
    fi
    check_dependencies
    get_latest_release_url
    download_ipk
    install_package
}

do_update() {
    if ! check_installed; then
        print_warning "Package is not installed. Use 'install' first."
        exit 1
    fi
    check_dependencies
    get_latest_release_url
    download_ipk
    update_package
}

do_remove() {
    if ! check_installed; then
        print_warning "Package is not installed."
        exit 0
    fi
    remove_package
}

show_menu() {
    print_banner
    
    # Check if package is already installed
    if check_installed; then
        print_info "Status: Installed (version $INSTALLED_VERSION)"
    else
        print_info "Status: Not installed"
    fi
    
    # Check if we can read input
    if [ ! -t 0 ] && [ ! -e /dev/tty ]; then
        print_error "Interactive mode not available (stdin not available)."
        print_info "Use command line arguments:"
        print_usage
        exit 1
    fi
    
    echo ""
    echo "Select an action:"
    echo ""
    echo "  1) Install    - Install Huawei Manager"
    echo "  2) Update     - Update to latest version"
    echo "  3) Remove     - Remove Huawei Manager"
    echo "  4) Exit       - Exit installer"
    echo ""
    printf "Choice [1-4]: "
    CHOICE=$(read_input)
    
    case "$CHOICE" in
        1|install)
            do_install
            ;;
        2|update)
            do_update
            ;;
        3|remove)
            do_remove
            ;;
        4|exit|quit)
            print_info "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid choice."
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
    print_error "This script must be run as root."
    exit 1
fi

# Parse command line arguments
case "${1:-}" in
    install)
        print_banner
        do_install
        ;;
    update)
        print_banner
        do_update
        ;;
    remove)
        print_banner
        do_remove
        ;;
    help|--help|-h)
        print_usage
        exit 0
        ;;
    "")
        # No argument, show interactive menu
        show_menu
        ;;
    *)
        print_error "Unknown command: $1"
        print_usage
        exit 1
        ;;
esac

exit 0