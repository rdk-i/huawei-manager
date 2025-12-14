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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Box drawing characters (ASCII compatible)
BOX_TL="+"
BOX_TR="+"
BOX_BL="+"
BOX_BR="+"
BOX_H="-"
BOX_V="|"

# Functions
clear_screen() {
    clear 2>/dev/null || printf "\033c"
}

print_line() {
    printf "${CYAN}"
    printf "%s" "$BOX_TL"
    i=0
    while [ $i -lt 50 ]; do
        printf "%s" "$BOX_H"
        i=$((i + 1))
    done
    printf "%s${NC}\n" "$BOX_TR"
}

print_line_bottom() {
    printf "${CYAN}"
    printf "%s" "$BOX_BL"
    i=0
    while [ $i -lt 50 ]; do
        printf "%s" "$BOX_H"
        i=$((i + 1))
    done
    printf "%s${NC}\n" "$BOX_BR"
}

print_banner() {
    echo ""
    print_line
    printf "${CYAN}${BOX_V}${NC}                                                  ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}  ${BOLD}${WHITE}  _    _                        _  ${NC}             ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}  ${BOLD}${WHITE} | |  | |                      (_) ${NC}             ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}  ${BOLD}${WHITE} | |__| |_   _  __ ___      ___ _ ${NC}              ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}  ${BOLD}${WHITE} |  __  | | | |/ _\` \\ \\ /\\ / / _ \\ |${NC}              ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}  ${BOLD}${WHITE} | |  | | |_| | (_| |\\ V  V /  __/ |${NC}              ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}  ${BOLD}${WHITE} |_|  |_|\\__,_|\\__,_| \\_/\\_/ \\___|_|${NC}              ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}                                                  ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}        ${BOLD}${GREEN}MANAGER INSTALLER${NC}                         ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}        ${DIM}for OpenWrt${NC}                                 ${CYAN}${BOX_V}${NC}\n"
    printf "${CYAN}${BOX_V}${NC}                                                  ${CYAN}${BOX_V}${NC}\n"
    print_line_bottom
    echo ""
}

print_section() {
    printf "${CYAN}━━━${NC} ${BOLD}${WHITE}%s${NC} ${CYAN}" "$1"
    # Calculate remaining dashes
    len=${#1}
    remaining=$((44 - len))
    i=0
    while [ $i -lt $remaining ]; do
        printf "━"
        i=$((i + 1))
    done
    printf "${NC}\n"
}

print_info() {
    printf "  ${BLUE}ℹ${NC}  %s\n" "$1"
}

print_success() {
    printf "  ${GREEN}✓${NC}  %s\n" "$1"
}

print_warning() {
    printf "  ${YELLOW}⚠${NC}  %s\n" "$1"
}

print_error() {
    printf "  ${RED}✗${NC}  %s\n" "$1"
}

print_step() {
    printf "  ${MAGENTA}➜${NC}  %s\n" "$1"
}

print_usage() {
    echo ""
    printf "${BOLD}Usage:${NC} %s [command]\n" "$0"
    echo ""
    printf "${BOLD}Commands:${NC}\n"
    printf "  ${GREEN}install${NC}   Install Huawei Manager\n"
    printf "  ${YELLOW}update${NC}    Update to latest version\n"
    printf "  ${RED}remove${NC}    Remove Huawei Manager\n"
    printf "  ${CYAN}help${NC}      Show this help message\n"
    echo ""
    printf "${BOLD}Examples:${NC}\n"
    printf "  %s                    ${DIM}# Interactive menu${NC}\n" "$0"
    printf "  %s install            ${DIM}# Direct install${NC}\n" "$0"
    printf "  wget -qO- URL | sh -s -- install  ${DIM}# Piped install${NC}\n"
    echo ""
}

# Read input - works both in interactive and piped mode
read_input() {
    if [ -t 0 ]; then
        read -r REPLY
    elif [ -e /dev/tty ]; then
        read -r REPLY </dev/tty
    else
        REPLY=""
    fi
    echo "$REPLY"
}

check_dependencies() {
    print_section "Checking Dependencies"
    
    for cmd in opkg wget; do
        if command -v $cmd >/dev/null 2>&1; then
            print_success "$cmd found"
        else
            print_error "$cmd not found. Make sure you are running on OpenWrt."
            exit 1
        fi
    done
    
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_CMD="curl"
        print_success "curl found (will use for downloads)"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_CMD="wget"
        print_success "wget found (will use for downloads)"
    else
        print_error "curl or wget is required to download files."
        exit 1
    fi
    echo ""
}

get_latest_release_url() {
    print_section "Fetching Latest Release"
    print_step "Contacting GitHub API..."
    
    mkdir -p "$TEMP_DIR"
    
    if [ "$DOWNLOAD_CMD" = "curl" ]; then
        RELEASE_INFO=$(curl -s "$API_URL" 2>/dev/null) || RELEASE_INFO=""
    else
        RELEASE_INFO=$(wget -qO- "$API_URL" 2>/dev/null) || RELEASE_INFO=""
    fi
    
    if [ -n "$RELEASE_INFO" ]; then
        IPK_URL=$(echo "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*\.ipk"' | head -1 | cut -d'"' -f4)
        VERSION=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    if [ -z "$IPK_URL" ]; then
        print_warning "Could not find IPK in GitHub Releases"
        print_step "Trying release folder in repository..."
        
        IPK_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/release/${PKG_NAME}_1.0.0-1_all.ipk"
        VERSION="1.0.0"
        
        if [ "$DOWNLOAD_CMD" = "curl" ]; then
            if ! curl -sfI "$IPK_URL" >/dev/null 2>&1; then
                print_error "Could not find IPK file anywhere."
                print_info "Make sure IPK is available in GitHub Releases or release/ folder."
                exit 1
            fi
        else
            if ! wget -q --spider "$IPK_URL" 2>/dev/null; then
                print_error "Could not find IPK file anywhere."
                print_info "Make sure IPK is available in GitHub Releases or release/ folder."
                exit 1
            fi
        fi
    fi
    
    print_success "Found version: ${GREEN}${VERSION}${NC}"
    echo ""
}

download_ipk() {
    print_section "Downloading Package"
    print_step "Downloading IPK file..."
    
    IPK_FILE="$TEMP_DIR/${PKG_NAME}.ipk"
    
    if [ "$DOWNLOAD_CMD" = "curl" ]; then
        curl -L -o "$IPK_FILE" "$IPK_URL" 2>/dev/null
    else
        wget -q -O "$IPK_FILE" "$IPK_URL"
    fi
    
    if [ ! -f "$IPK_FILE" ]; then
        print_error "Failed to download IPK file."
        exit 1
    fi
    
    print_success "Package downloaded successfully"
    echo ""
}

backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        print_step "Backing up configuration..."
        cp "$CONFIG_FILE" "$TEMP_DIR/huawei-manager.config.bak"
        print_success "Configuration backed up"
        return 0
    fi
    return 1
}

restore_config() {
    if [ -f "$TEMP_DIR/huawei-manager.config.bak" ]; then
        print_step "Restoring configuration..."
        cp "$TEMP_DIR/huawei-manager.config.bak" "$CONFIG_FILE"
        print_success "Configuration restored"
    fi
}

install_package() {
    print_section "Installing Package"
    
    print_step "Updating package lists..."
    opkg update >/dev/null 2>&1 || true
    
    print_step "Installing dependencies..."
    opkg install python3 python3-pip luci-base luci-lib-jsonc 2>/dev/null || {
        print_warning "Some dependencies may already be installed"
    }
    
    print_step "Installing Huawei Manager..."
    opkg install "$TEMP_DIR/${PKG_NAME}.ipk"
    
    if [ $? -eq 0 ]; then
        print_success "Package installed!"
        
        print_step "Installing Python dependencies..."
        pip3 install huawei-lte-api --quiet 2>/dev/null || {
            print_warning "Failed to install huawei-lte-api (install manually)"
        }
        
        print_step "Clearing LuCI cache..."
        rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
        print_success "Cache cleared"
        
        echo ""
        print_section "Installation Complete"
        printf "\n"
        printf "  ${GREEN}${BOLD}Huawei Manager has been installed successfully!${NC}\n"
        printf "\n"
        printf "  ${CYAN}Access via:${NC} LuCI > Modem > Huawei Manager\n"
        printf "\n"
    else
        print_error "Failed to install package."
        exit 1
    fi
}

update_package() {
    print_section "Updating Package"
    
    HAS_CONFIG=0
    if backup_config; then
        HAS_CONFIG=1
    fi
    
    print_step "Removing old version..."
    if opkg list-installed | grep -q "^${PKG_NAME} "; then
        opkg remove "$PKG_NAME" 2>/dev/null || true
    fi
    
    print_step "Installing new version..."
    opkg install "$TEMP_DIR/${PKG_NAME}.ipk"
    
    if [ $? -eq 0 ]; then
        if [ $HAS_CONFIG -eq 1 ]; then
            restore_config
        fi
        
        print_step "Updating Python dependencies..."
        pip3 install --upgrade huawei-lte-api --quiet 2>/dev/null || true
        
        print_step "Clearing LuCI cache..."
        rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
        
        print_step "Restarting service..."
        /etc/init.d/huawei-manager restart 2>/dev/null || true
        
        echo ""
        print_section "Update Complete"
        printf "\n"
        printf "  ${GREEN}${BOLD}Huawei Manager has been updated successfully!${NC}\n"
        printf "  ${DIM}Your configuration has been preserved.${NC}\n"
        printf "\n"
    else
        print_error "Failed to update package."
        if [ $HAS_CONFIG -eq 1 ]; then
            restore_config
        fi
        exit 1
    fi
}

remove_package() {
    print_section "Removing Package"
    
    KEEP_CONFIG="1"
    if [ -t 0 ] || [ -e /dev/tty ]; then
        echo ""
        printf "  ${YELLOW}?${NC}  Keep configuration file?\n"
        printf "     ${WHITE}1)${NC} Yes, keep configuration\n"
        printf "     ${WHITE}2)${NC} No, remove everything\n"
        echo ""
        printf "     Choice [1-2]: "
        KEEP_CONFIG=$(read_input)
    fi
    
    case "$KEEP_CONFIG" in
        2)
            if [ -f "$CONFIG_FILE" ]; then
                rm -f "$CONFIG_FILE"
                print_success "Configuration removed"
            fi
            ;;
        *)
            if [ -f "$CONFIG_FILE" ]; then
                cp "$CONFIG_FILE" "/etc/config/huawei-manager.bak"
                print_success "Configuration backed up to /etc/config/huawei-manager.bak"
            fi
            ;;
    esac
    
    print_step "Stopping service..."
    /etc/init.d/huawei-manager stop 2>/dev/null || true
    /etc/init.d/huawei-manager disable 2>/dev/null || true
    
    print_step "Removing package..."
    opkg remove "$PKG_NAME" 2>/dev/null || {
        print_warning "Package not found or already removed"
    }
    
    print_step "Clearing LuCI cache..."
    rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
    
    echo ""
    print_section "Removal Complete"
    printf "\n"
    printf "  ${GREEN}${BOLD}Huawei Manager has been removed.${NC}\n"
    printf "\n"
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
        print_warning "Package is already installed (version $INSTALLED_VERSION)"
        if [ -t 0 ] || [ -e /dev/tty ]; then
            printf "     Continue with reinstall? [y/N]: "
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
    echo ""
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
    echo ""
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
    echo ""
    remove_package
}

show_menu() {
    clear_screen
    print_banner
    
    # Status section
    print_section "Status"
    if check_installed; then
        printf "  ${GREEN}●${NC}  Installed ${DIM}(version %s)${NC}\n" "$INSTALLED_VERSION"
    else
        printf "  ${RED}○${NC}  Not installed\n"
    fi
    echo ""
    
    # Check if we can read input
    if [ ! -t 0 ] && [ ! -e /dev/tty ]; then
        print_error "Interactive mode not available"
        print_info "Use command line arguments instead:"
        print_usage
        exit 1
    fi
    
    # Menu section
    print_section "Menu"
    echo ""
    printf "     ${WHITE}${BOLD}1)${NC} ${GREEN}Install${NC}    Install Huawei Manager\n"
    printf "     ${WHITE}${BOLD}2)${NC} ${YELLOW}Update${NC}     Update to latest version\n"
    printf "     ${WHITE}${BOLD}3)${NC} ${RED}Remove${NC}     Remove Huawei Manager\n"
    printf "     ${WHITE}${BOLD}4)${NC} ${DIM}Exit${NC}       Exit installer\n"
    echo ""
    printf "     Choice [1-4]: "
    CHOICE=$(read_input)
    echo ""
    
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
        4|exit|quit|q)
            printf "  ${CYAN}Goodbye!${NC}\n\n"
            exit 0
            ;;
        *)
            print_error "Invalid choice."
            exit 1
            ;;
    esac
}

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

# Main execution
trap cleanup EXIT

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    clear_screen
    print_banner
    print_error "This script must be run as root."
    printf "  ${DIM}Try: sudo %s${NC}\n\n" "$0"
    exit 1
fi

# Parse command line arguments
case "${1:-}" in
    install)
        clear_screen
        print_banner
        do_install
        ;;
    update)
        clear_screen
        print_banner
        do_update
        ;;
    remove)
        clear_screen
        print_banner
        do_remove
        ;;
    help|--help|-h)
        clear_screen
        print_banner
        print_usage
        exit 0
        ;;
    "")
        show_menu
        ;;
    *)
        clear_screen
        print_banner
        print_error "Unknown command: $1"
        print_usage
        exit 1
        ;;
esac

exit 0