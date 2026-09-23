#!/bin/bash

# VPS VPN Proxy Deployment Script
# Deploys HTTP and Telegram proxies with system preparation and Fail2Ban protection

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Enhanced logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

err() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Run command with error checking and logging
run_cmd() {
    local cmd="$*"
    log "Executing: $cmd"
    if eval "$cmd"; then
        log "Command succeeded: $cmd"
        return 0
    else
        local exit_code=$?
        err "Command failed with exit code $exit_code: $cmd"
        return $exit_code
    fi
}

# Rollback functions
rollback_docker_install() {
    warn "Rolling back Docker installation..."
    apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    apt-get autoremove -y || true
    rm -rf /var/lib/docker || true
    rm -rf /etc/docker || true
    log "Docker installation rolled back."
}

rollback_http_proxy() {
    warn "Rolling back HTTP Proxy..."
    cd "$SCRIPT_DIR/http-proxy" 2>/dev/null && docker compose down -v 2>/dev/null || true
    rm -f "$SCRIPT_DIR/http-proxy/3proxy.passwd" 2>/dev/null || true
    log "HTTP Proxy rolled back."
}

rollback_telegram_proxy() {
    warn "Rolling back Telegram Proxy..."
    cd "$SCRIPT_DIR/telegram-proxy" 2>/dev/null && docker compose down -v 2>/dev/null || true
    rm -f "$SCRIPT_DIR/telegram-proxy/nginx/conf.d/ssl.conf" 2>/dev/null || true
    rm -f "$SCRIPT_DIR/telegram-proxy/nginx/conf.d/vpn-panel.conf" 2>/dev/null || true
    log "Telegram Proxy rolled back."
}

rollback_wireguard() {
    warn "Rolling back WireGuard Panel..."
    cd "$SCRIPT_DIR/wireguard-panel" 2>/dev/null && docker compose down -v 2>/dev/null || true
    rm -f "$SCRIPT_DIR/wireguard-panel/.env" 2>/dev/null || true
    log "WireGuard Panel rolled back."
}

# Add the amnezia PPA signing key (official amneziawg docs)
add_amnezia_gpg_key() {
    if command -v apt-key >/dev/null 2>&1; then
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 57290828 || return 1
    else
        curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x57290828" \
            | gpg --dearmor > /etc/apt/trusted.gpg.d/amnezia.gpg || return 1
    fi
}

# Install the AmneziaWG kernel module on the host (required for EXPERIMENTAL_AWG)
# Official method for Debian: https://github.com/amnezia-vpn/amneziawg-linux-kernel-module#debian
install_amneziawg_module() {
    log "Installing AmneziaWG kernel module (amnezia PPA)..."

    if lsmod | grep -q '^amneziawg'; then
        ok "amneziawg module already loaded"
        return 0
    fi

    # Install prerequisites
    if ! apt install -y software-properties-common python3-launchpadlib gnupg2 "linux-headers-$(uname -r)"; then
        warn "Failed to install amneziawg build prerequisites"
        return 1
    fi

    # Add the amnezia PPA repository once
    if [ ! -f /etc/apt/sources.list.d/amnezia-ppa.list ]; then
        if ! add_amnezia_gpg_key; then
            warn "Failed to import amnezia PPA signing key"
            return 1
        fi
        tee /etc/apt/sources.list.d/amnezia-ppa.list > /dev/null <<'EOF'
deb https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu focal main
deb-src https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu focal main
EOF
        apt update || { warn "apt update failed after adding amnezia PPA"; return 1; }
    fi

    # Install the DKMS package (builds the module for the running kernel)
    if ! apt install -y amneziawg; then
        warn "Failed to install amneziawg package"
        return 1
    fi

    if ! modprobe amneziawg; then
        warn "Failed to load amneziawg module"
        return 1
    fi

    ok "AmneziaWG kernel module installed"
}

# Global deployment stage tracking
DEPLOYMENT_STAGE="initial"
set_stage() {
    DEPLOYMENT_STAGE="$1"
    log "Entering deployment stage: $1"
}

# Download repository if running from curl and files are missing
download_repository_if_needed() {
    if [ "$RUNNING_FROM_CURL" = true ]; then
        log "Downloading repository to $PROJECT_DIR..."
        cd "$USER_HOME"
        
        # Remove existing directory if it exists
        if [ -d "$PROJECT_DIR" ]; then
            log "Directory $PROJECT_DIR exists, removing old files..."
            rm -rf "$PROJECT_DIR"
        fi
        
        # Download repository as tarball
        REPO_URL="https://github.com/unton83/VPS_VPN_PROXY/archive/master.tar.gz"
        if ! curl -fsSL "$REPO_URL" -o repository.tar.gz; then
            err "Failed to download repository"
        fi
        
        # Extract archive
        log "Extracting files..."
        if ! tar -xzf repository.tar.gz; then
            err "Failed to extract repository"
        fi
        
        # Move to extracted directory
        mv VPS_VPN_PROXY-master "$PROJECT_DIR"
        rm -f repository.tar.gz
        
        ok "Repository downloaded and extracted to $PROJECT_DIR"
    fi
}

# Check if running from curl or local
if [ -t 0 ]; then
    # Running from curl - set target directory
    USER_HOME="$HOME"
    PROJECT_DIR="$USER_HOME/VPS_VPN_PROXY"
    SCRIPT_DIR="$PROJECT_DIR"
    RUNNING_FROM_CURL=true
    
    log "Running from curl - will set up in $PROJECT_DIR"
else
    # Running locally - use script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    RUNNING_FROM_CURL=false
fi

# ── 1. Check if Telegram is accessible via curl ───────────────────────────────

check_telegram_access() {
    log "Testing connection to web.telegram.org..."
    
    # Try to connect to web.telegram.org with a short timeout
    if curl -fsSL --max-time 10 https://web.telegram.org >/dev/null 2>&1; then
        ok "Successfully connected to Telegram"
    else
        # If first attempt fails, try with different UA
        if curl -fsSL --max-time 10 -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" https://web.telegram.org >/dev/null 2>&1; then
            ok "Successfully connected to Telegram with alternative User-Agent"
        else
            err "Cannot connect to Telegram. Please check your network connection and firewall settings."
        fi
    fi
}

check_telegram_access

# ── 2. System Preparation ───────────────────────────────
log "Starting system preparation..."

# Detect OS and version
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$NAME"
        VER="$VERSION_ID"
    else
        err "Cannot detect OS. /etc/os-release not found."
    fi
    
    log "Detected OS: $OS $VER"
    
    # Check if OS is supported
    if [[ "$OS" == *"Debian"* ]]; then
        if [[ "${VER%%.*}" -lt "11" ]]; then
            err "Debian $VER is not supported. Please use Debian 11 or later."
        fi
    else
        err "Unsupported OS: $OS. Please use Debian 11+."
    fi
    
    ok "OS compatibility check passed"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    run_cmd apt update -q
    run_cmd apt upgrade -y -q
    ok "System packages updated"
}

# Install Docker if not present
install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log "Installing Docker..."
        set_stage "docker_install"
        
        # Add Docker's official GPG key
        run_cmd apt update
        run_cmd apt install -y ca-certificates curl
        run_cmd install -m 0755 -d /etc/apt/keyrings
        run_cmd curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        run_cmd chmod a+r /etc/apt/keyrings/docker.asc
        
        # Add repository to Apt sources
        tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
        
        # Install Docker packages
        run_cmd apt update
        if ! run_cmd apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
            rollback_docker_install
            err "Failed to install Docker packages. Rollback completed."
        fi
        
        run_cmd systemctl start docker
        run_cmd systemctl enable docker
        ok "Docker installed and started"
    else
        log "Docker already installed"
    fi
    
    # Check Docker Compose availability
    if ! command -v docker compose >/dev/null 2>&1; then
        log "Docker Compose not available, installing..."
        if ! run_cmd apt install -y docker-compose-plugin; then
            warn "Failed to install Docker Compose plugin, but Docker is already installed. Continuing."
        else
            ok "Docker Compose installed"
        fi
    else
        log "Docker Compose already available"
    fi
}

# Install additional dependencies
install_dependencies() {
    log "Installing additional dependencies..."
    
    # Install openssl if not present
    if ! command -v openssl >/dev/null 2>&1; then
        log "Installing openssl..."
        run_cmd apt install -y openssl
        ok "openssl installed"
    else
        log "openssl already installed"
    fi
    
    # Install curl if not present
    if ! command -v curl >/dev/null 2>&1; then
        log "Installing curl..."
        run_cmd apt install -y curl
        ok "curl installed"
    else
        log "curl already installed"
    fi
    
    # Install dig (dnsutils) if not present
    if ! command -v dig >/dev/null 2>&1; then
        log "Installing dnsutils (dig)..."
        run_cmd apt install -y dnsutils
        ok "dnsutils installed"
    else
        log "dig already installed"
    fi
    
    # Install fail2ban if not present
    if ! command -v fail2ban-server >/dev/null 2>&1; then
        log "Installing fail2ban..."
        run_cmd apt install -y fail2ban
        ok "fail2ban installed"
    else
        log "fail2ban already installed"
    fi
}

# Validate domain format
validate_domain() {
    local d="$1"
    if [[ ! "$d" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        err "Invalid domain format: $d"
    fi
}

# Check if required files exist and download repository if needed
check_required_files() {
    local missing_files=()
    local need_download=false
    
    # First check for missing files
    if [ "$DEPLOY_HTTP" = true ]; then
        if [ ! -f "$SCRIPT_DIR/http-proxy/docker-compose.yml" ]; then
            missing_files+=("http-proxy/docker-compose.yml")
            need_download=true
        fi
        if [ ! -f "$SCRIPT_DIR/http-proxy/3proxy.cfg" ]; then
            missing_files+=("http-proxy/3proxy.cfg")
            need_download=true
        fi
    fi
    
    if [ "$DEPLOY_TELEGRAM" = true ]; then
        if [ ! -f "$SCRIPT_DIR/telegram-proxy/docker-compose.yml" ]; then
            missing_files+=("telegram-proxy/docker-compose.yml")
            need_download=true
        fi
        if [ ! -f "$SCRIPT_DIR/telegram-proxy/telemt/telemt.toml" ]; then
            missing_files+=("telegram-proxy/telemt/telemt.toml")
            need_download=true
        fi
        if [ ! -f "$SCRIPT_DIR/telegram-proxy/nginx/ssl.conf.template" ]; then
            missing_files+=("telegram-proxy/nginx/ssl.conf.template")
            need_download=true
        fi
    fi
    
    if [ "$DEPLOY_WIREGUARD" = true ]; then
        if [ ! -f "$SCRIPT_DIR/wireguard-panel/docker-compose.yml" ]; then
            missing_files+=("wireguard-panel/docker-compose.yml")
            need_download=true
        fi
        if [ ! -f "$SCRIPT_DIR/telegram-proxy/nginx/vpn-panel.conf.template" ]; then
            missing_files+=("telegram-proxy/nginx/vpn-panel.conf.template")
            need_download=true
        fi
    fi
    
    if [ ! -f "$SCRIPT_DIR/fail2ban/jail.local" ]; then
        missing_files+=("fail2ban/jail.local")
        need_download=true
    fi
    
    if [ ! -f "$SCRIPT_DIR/fail2ban/docker-nginx.conf" ]; then
        missing_files+=("fail2ban/docker-nginx.conf")
        need_download=true
    fi
    
    # If files are missing and we're running from curl, download repository
    if [ "$need_download" = true ] && [ "$RUNNING_FROM_CURL" = true ]; then
        log "Some required files are missing, downloading repository..."
        download_repository_if_needed
        
        # After download, check again
        missing_files=()
        if [ "$DEPLOY_HTTP" = true ]; then
            if [ ! -f "$SCRIPT_DIR/http-proxy/docker-compose.yml" ]; then
                missing_files+=("http-proxy/docker-compose.yml")
            fi
            if [ ! -f "$SCRIPT_DIR/http-proxy/3proxy.cfg" ]; then
                missing_files+=("http-proxy/3proxy.cfg")
            fi
        fi
        
        if [ "$DEPLOY_TELEGRAM" = true ]; then
            if [ ! -f "$SCRIPT_DIR/telegram-proxy/docker-compose.yml" ]; then
                missing_files+=("telegram-proxy/docker-compose.yml")
            fi
            if [ ! -f "$SCRIPT_DIR/telegram-proxy/telemt/telemt.toml" ]; then
                missing_files+=("telegram-proxy/telemt/telemt.toml")
            fi
            if [ ! -f "$SCRIPT_DIR/telegram-proxy/nginx/ssl.conf.template" ]; then
                missing_files+=("telegram-proxy/nginx/ssl.conf.template")
            fi
        fi
        
        if [ "$DEPLOY_WIREGUARD" = true ]; then
            if [ ! -f "$SCRIPT_DIR/wireguard-panel/docker-compose.yml" ]; then
                missing_files+=("wireguard-panel/docker-compose.yml")
            fi
            if [ ! -f "$SCRIPT_DIR/telegram-proxy/nginx/vpn-panel.conf.template" ]; then
                missing_files+=("telegram-proxy/nginx/vpn-panel.conf.template")
            fi
        fi
        
        if [ ! -f "$SCRIPT_DIR/fail2ban/jail.local" ]; then
            missing_files+=("fail2ban/jail.local")
        fi
        
        if [ ! -f "$SCRIPT_DIR/fail2ban/docker-nginx.conf" ]; then
            missing_files+=("fail2ban/docker-nginx.conf")
        fi
    fi
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        err "Missing required files: ${missing_files[*]}"
    fi
}

# Check for existing configuration and offer clean install option
check_existing_config() {
    local existing_files=()
    
    # Check for existing generated/configured files
    if [ -f "$SCRIPT_DIR/http-proxy/3proxy.passwd" ]; then
        existing_files+=("HTTP Proxy passwords")
    fi
    
    if [ -f "$SCRIPT_DIR/telegram-proxy/telemt/telemt.toml" ] && \
       grep -q "REPLACE_WITH_YOUR_DOMAIN\|REPLACE_WITH_YOUR_SECRET" "$SCRIPT_DIR/telegram-proxy/telemt/telemt.toml"; then
        existing_files+=("Unconfigured Telegram proxy")
    elif [ -f "$SCRIPT_DIR/telegram-proxy/telemt/telemt.toml" ] && \
       ! grep -q "REPLACE_WITH_YOUR_DOMAIN\|REPLACE_WITH_YOUR_SECRET" "$SCRIPT_DIR/telegram-proxy/telemt/telemt.toml"; then
        existing_files+=("Configured Telegram proxy")
    fi
    
    if [ -d "$SCRIPT_DIR/telegram-proxy/certbot/certs/live" ] && \
       [ "$(ls -A "$SCRIPT_DIR/telegram-proxy/certbot/certs/live" 2>/dev/null)" ]; then
        existing_files+=("SSL certificates")
    fi
    
    if [ -f "$SCRIPT_DIR/wireguard-panel/.env" ]; then
        existing_files+=("Configured WireGuard Panel")
    fi
    
    # Note: telemt uses tmpfs, no persistent data to check
    
    # If existing files found, offer clean install option
    if [ ${#existing_files[@]} -gt 0 ]; then
        echo ""
        warn "Existing configuration found:"
        for file in "${existing_files[@]}"; do
            echo "  - $file"
        done
        echo ""
        echo -e "${YELLOW}Choose installation mode:${NC}"
        echo "1) Continue with existing configuration"
        echo "2) Clean install (remove entire VPS_VPN_PROXY directory and start fresh)"
        echo "3) Exit"
        echo ""
        
        # Remove piped input option - it's not supported
        if [ ! -t 0 ]; then
            err "Piped input is not supported. Please run the script interactively."
        fi
        
        read -p "Enter choice [1-3]: " CLEAN_CHOICE
        
        case $CLEAN_CHOICE in
            1)
                log "Continuing with existing configuration..."
                ;;
            2)
                log "Performing clean install (removing entire VPS_VPN_PROXY directory)..."
                clean_existing_config
                ;;
            3)
                echo "Exiting..."
                exit 0
                ;;
            *)
                err "Invalid choice"
                ;;
        esac
    else
        log "No existing configuration found - performing fresh install"
    fi
}

# Clean existing configuration files - complete removal of VPS_VPN_PROXY directory
clean_existing_config() {
    log "Performing clean install - removing entire VPS_VPN_PROXY directory..."
    
    # Determine the directory to remove
    local target_dir=""
    if [ "$RUNNING_FROM_CURL" = true ]; then
        # When running from curl, PROJECT_DIR is set to $HOME/VPS_VPN_PROXY
        target_dir="$PROJECT_DIR"
    else
        # When running locally, use SCRIPT_DIR (current directory of the script)
        target_dir="$SCRIPT_DIR"
    fi
    
    # Safety check: ensure target_dir is not root or home directory
    if [ -z "$target_dir" ] || [ "$target_dir" = "/" ] || [ "$target_dir" = "$HOME" ]; then
        err "Safety check failed: cannot remove directory $target_dir"
    fi
    
    # Check if directory exists
    if [ ! -d "$target_dir" ]; then
        warn "Directory $target_dir does not exist, nothing to remove"
        return 0
    fi
    
    # Stop and remove containers if running
    if command -v docker >/dev/null 2>&1; then
        log "Stopping and removing existing containers..."
        cd "$target_dir/http-proxy" 2>/dev/null && docker compose down -v 2>/dev/null || true
        cd "$target_dir/telegram-proxy" 2>/dev/null && docker compose down -v 2>/dev/null || true
        cd "$target_dir/wireguard-panel" 2>/dev/null && docker compose down -v 2>/dev/null || true
    fi
    
    # Remove the entire directory
    log "Removing directory: $target_dir"
    rm -rf "$target_dir"
    
    # If running from curl, we need to exit because the script files are now gone
    if [ "$RUNNING_FROM_CURL" = true ]; then
        ok "Clean install completed. Directory $target_dir has been removed."
        log "Please run the installation command again to start fresh installation."
        exit 0
    else
        # When running locally, the script is still in memory
        ok "Clean install completed. Directory $target_dir has been removed."
        warn "Script is running from removed directory. Some operations may fail."
        warn "Please restart the script from a fresh copy of the repository."
        exit 0
    fi
}

# Execute system preparation
detect_os
update_system
install_docker
install_dependencies

# Detect server IP after curl/dig are installed
detect_server_ip() {
    SERVER_IP=$(curl -4s ifconfig.me || curl -4s ipinfo.io/ip || curl -4s icanhazip.com)
    [[ -z "$SERVER_IP" ]] && SERVER_IP="YOUR_VPS_IP"
    ok "Server IP: $SERVER_IP"
}

detect_server_ip

ok "System preparation completed"

# ── 3. Service Selection ───────────────────────────────
echo ""
echo -e "${YELLOW}Select services to be deployed:${NC}"
echo "1) HTTP Proxy only (3proxy)"
echo "2) Telegram Proxy only (telemt)"
echo "3) WireGuard Panel only (wg-easy)"
echo "4) HTTP Proxy + Telegram Proxy"
echo "5) Telegram Proxy + WireGuard Panel"
echo "6) HTTP Proxy + WireGuard Panel"
echo "7) All services (HTTP + Telegram + WireGuard)"
echo "8) Exit"
echo ""
# Remove piped input option - it's not supported
if [ ! -t 0 ]; then
    err "Piped input is not supported. Please run the script interactively."
fi

read -p "Enter choice [1-8]: " CHOICE

case $CHOICE in
    1) DEPLOY_HTTP=true; DEPLOY_TELEGRAM=false; DEPLOY_WIREGUARD=false ;;
    2) DEPLOY_HTTP=false; DEPLOY_TELEGRAM=true; DEPLOY_WIREGUARD=false ;;
    3) DEPLOY_HTTP=false; DEPLOY_TELEGRAM=false; DEPLOY_WIREGUARD=true ;;
    4) DEPLOY_HTTP=true; DEPLOY_TELEGRAM=true; DEPLOY_WIREGUARD=false ;;
    5) DEPLOY_HTTP=false; DEPLOY_TELEGRAM=true; DEPLOY_WIREGUARD=true ;;
    6) DEPLOY_HTTP=true; DEPLOY_TELEGRAM=false; DEPLOY_WIREGUARD=true ;;
    7) DEPLOY_HTTP=true; DEPLOY_TELEGRAM=true; DEPLOY_WIREGUARD=true ;;
    8) echo "Exiting..."; exit 0 ;;
    *) err "Invalid choice" ;;
esac

check_existing_config
check_required_files

# ── 3.1. Port Availability Check (service-specific) ───────────────────────────────
log "Checking port availability for selected services..."

check_port() {
    local port="$1"
    if ss -tlnp | grep -q ":${port} " || ss -ulnp | grep -q ":${port} "; then
        err "Port $port is already in use. Please free it and try again."
    fi
}

if [ "$DEPLOY_HTTP" = true ]; then
    check_port 8080
fi

if [ "$DEPLOY_TELEGRAM" = true ]; then
    check_port 80
    check_port 443
fi

if [ "$DEPLOY_WIREGUARD" = true ]; then
    check_port 51820
    check_port 51821
    check_port 8443
    
    # Check TUN device availability
    if [ ! -c /dev/net/tun ]; then
        warn "/dev/net/tun not found - attempting to create it"
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 600 /dev/net/tun 2>/dev/null || true
    fi
    if [ ! -c /dev/net/tun ]; then
        err "/dev/net/tun is unavailable. Enable TUN on your VPS (modprobe tun or enable in panel)."
    fi
    
    # Check kernel version for WireGuard support (>= 5.6)
    KERNEL_MAJOR=$(uname -r | cut -d. -f1)
    KERNEL_MINOR=$(uname -r | cut -d. -f2)
    if [ "$KERNEL_MAJOR" -lt 5 ] || { [ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -lt 6 ]; }; then
        warn "Kernel $(uname -r) is older than 5.6. WireGuard may require wireguard-dkms or a kernel upgrade."
    else
        ok "Kernel $(uname -r) supports WireGuard"
    fi
fi

ok "Selected ports are available"

# ── 4. HTTP Proxy Setup ─────────────────────────────────
if [ "$DEPLOY_HTTP" = true ]; then
    echo ""
    log "Setting up HTTP Proxy (3proxy)..."
    
    # Generate a single secure password
    log "Generating secure password..."
    USER_PASS=$(openssl rand -base64 16)
    
    # Create password file for 3proxy
    cat > "$SCRIPT_DIR/http-proxy/3proxy.passwd" << EOF
user:CL:$USER_PASS
EOF

    ok "HTTP Proxy configured"
fi

# ── 5. Telegram Proxy Setup ─────────────────────────────────
if [ "$DEPLOY_TELEGRAM" = true ]; then
    echo ""
    log "Setting up Telegram Proxy (telemt)..."
    
    echo -e "${YELLOW}Enter your domain (e.g. example.com).${NC}"
    echo -e "${YELLOW}DNS A record must already point to this server's IP.${NC}"
    read -r DOMAIN
    [[ -z "$DOMAIN" ]] && err "Domain cannot be empty."
    validate_domain "$DOMAIN"
    
    echo ""
    echo -e "${YELLOW}Enter your email for Let's Encrypt expiry notifications:${NC}"
    read -r EMAIL
    [[ -z "$EMAIL" ]] && err "Email cannot be empty."
    
    # Generate secret
    log "Generating 32-char hex secret..."
    SECRET=$(openssl rand -hex 16)
    [[ -z "$SECRET" ]] && err "Failed to generate secret."
    ok "Secret: $SECRET"
    
    # Patch telemt config
    log "Patching telemt config..."
    sed -i "s|REPLACE_WITH_YOUR_DOMAIN|$DOMAIN|g" "$SCRIPT_DIR/telegram-proxy/telemt/telemt.toml"
    sed -i "s|REPLACE_WITH_YOUR_SECRET|$SECRET|g" "$SCRIPT_DIR/telegram-proxy/telemt/telemt.toml"
    
    # Prepare directories
    mkdir -p "$SCRIPT_DIR/telegram-proxy/certbot/www"
    mkdir -p "$SCRIPT_DIR/telegram-proxy/certbot/certs"
    mkdir -p "$SCRIPT_DIR/telegram-proxy/certbot/logs"
    rm -f "$SCRIPT_DIR/telegram-proxy/nginx/conf.d/ssl.conf"
    
    # Set proper ownership and permissions for certbot directories
    chown -R root:root "$SCRIPT_DIR/telegram-proxy/certbot/www"
    chown -R root:root "$SCRIPT_DIR/telegram-proxy/certbot/certs"
    chown -R root:root "$SCRIPT_DIR/telegram-proxy/certbot/logs"
    chmod 755 "$SCRIPT_DIR/telegram-proxy/certbot/www"
    chmod 700 "$SCRIPT_DIR/telegram-proxy/certbot/certs"
    chmod 755 "$SCRIPT_DIR/telegram-proxy/certbot/logs"
    
    ok "Telegram Proxy configured"
fi

# ── 5.5. WireGuard Panel Setup ─────────────────────────────────
if [ "$DEPLOY_WIREGUARD" = true ]; then
    echo ""
    log "Setting up WireGuard Panel (wg-easy)..."
    
    # The panel uses the same domain as the other services (single-domain setup).
    # If Telegram was not selected, ask for the domain here.
    if [ "$DEPLOY_TELEGRAM" != true ] || [ -z "${DOMAIN:-}" ]; then
        echo -e "${YELLOW}Enter your domain (e.g. example.com).${NC}"
        echo -e "${YELLOW}DNS A record must already point to this server's IP.${NC}"
        read -r DOMAIN
        [[ -z "$DOMAIN" ]] && err "Domain cannot be empty."
        validate_domain "$DOMAIN"
    fi
    
    # Request email if not already collected for Telegram
    if [ "$DEPLOY_TELEGRAM" != true ] || [ -z "${EMAIL:-}" ]; then
        echo ""
        echo -e "${YELLOW}Enter your email for Let's Encrypt expiry notifications:${NC}"
        read -r EMAIL
        [[ -z "$EMAIL" ]] && err "Email cannot be empty."
    fi
    
    # Ask about experimental AmneziaWG
    echo ""
    echo -e "${YELLOW}Enable AmneziaWG (experimental obfuscation against DPI)?${NC}"
    echo "  1) No, standard WireGuard (recommended)"
    echo "  2) Yes, AmneziaWG (installs the amneziawg kernel module on the host)"
    read -p "Enter choice [1-2]: " AWG_CHOICE
    case $AWG_CHOICE in
        1) ENABLE_AWG=false ;;
        2) ENABLE_AWG=true ;;
        *) err "Invalid choice" ;;
    esac
    
    if [ "$ENABLE_AWG" = true ]; then
        if ! install_amneziawg_module; then
            warn "AmneziaWG module unavailable - falling back to standard WireGuard"
            ENABLE_AWG=false
        fi
    fi
    
    # Generate admin password
    log "Generating admin password..."
    WG_ADMIN_PASSWORD=$(openssl rand -hex 16)
    [[ -z "$WG_ADMIN_PASSWORD" ]] && err "Failed to generate admin password."
    
    # Prepare data directory
    mkdir -p "$SCRIPT_DIR/wireguard-panel/data"
    
    # Create .env file with unattended setup credentials
    cat > "$SCRIPT_DIR/wireguard-panel/.env" << EOF
INIT_ENABLED=true
INIT_USERNAME=admin
INIT_PASSWORD=$WG_ADMIN_PASSWORD
INIT_HOST=$SERVER_IP
INIT_PORT=51820
INIT_DNS=1.1.1.1,8.8.8.8
EXPERIMENTAL_AWG=$([ "$ENABLE_AWG" = true ] && echo "true" || echo "false")
INSECURE=true
TZ=Europe/Moscow
EOF
    chmod 600 "$SCRIPT_DIR/wireguard-panel/.env"
    
    ok "WireGuard Panel configured"
fi

# ── 6. Deploy Services ─────────────────────────────────
echo ""
log "Deploying services..."

# Deploy HTTP Proxy
if [ "$DEPLOY_HTTP" = true ]; then
    log "Starting HTTP Proxy..."
    (
        cd "$SCRIPT_DIR/http-proxy"
        if ! docker compose up -d; then
            err "Failed to start HTTP Proxy"
        fi
    )
    ok "HTTP Proxy started on port 8080 (HTTP)"
fi

# Deploy reverse proxy gateway (nginx) — used by Telegram Proxy and/or WireGuard Panel
if [ "$DEPLOY_TELEGRAM" = true ] || [ "$DEPLOY_WIREGUARD" = true ]; then
    log "Starting reverse proxy gateway (nginx)..."
    (
        cd "$SCRIPT_DIR/telegram-proxy"
        
        # Start nginx (HTTP-only) first
        if ! docker compose up -d web; then
            err "Failed to start nginx web service"
        fi
        
        log "Waiting for nginx to be ready..."
        for i in $(seq 1 20); do
            if curl -sf "http://localhost/health" >/dev/null 2>&1 || \
               wget -qO- "http://localhost/health" >/dev/null 2>&1; then
                ok "nginx is ready"
                break
            fi
            if [ "$i" -eq 20 ]; then
                if ss -tlnp | grep -q ':80 '; then
                    ok "Port 80 is open — continuing"
                else
                    docker compose logs web
                    err "nginx does not appear to be running. See logs above."
                fi
            fi
            sleep 2
        done
        
        # Check DNS resolution for the domain
        log "Checking DNS resolution for $DOMAIN ..."
        DOMAIN_IP=$(dig +short "$DOMAIN" | head -n1)
        if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
            err "DNS A record for $DOMAIN ($DOMAIN_IP) does not match server IP ($SERVER_IP)"
        fi
        ok "DNS resolution verified: $DOMAIN -> $SERVER_IP"

        # Obtain Let's Encrypt certificate using existing nginx
        log "Requesting Let's Encrypt certificate for $DOMAIN ..."
        if ! docker compose run --rm --entrypoint certbot certbot certonly \
            --webroot \
            --webroot-path /var/www/certbot \
            --email "$EMAIL" \
            --agree-tos \
            --no-eff-email \
            --domain "$DOMAIN"; then
            err "Failed to obtain Let's Encrypt certificate :("
        fi
        
        # Enable SSL on nginx (cover site for telemt, internal port 8444)
        if [ "$DEPLOY_TELEGRAM" = true ]; then
            log "Enabling nginx SSL config (port 8444 for cover site)..."
            sed "s|{{DOMAIN}}|$DOMAIN|g" "$SCRIPT_DIR/telegram-proxy/nginx/ssl.conf.template" \
                > "$SCRIPT_DIR/telegram-proxy/nginx/conf.d/ssl.conf"
        fi
        
        # Enable reverse proxy for WireGuard Panel (public port 8443, https://$DOMAIN:8443)
        if [ "$DEPLOY_WIREGUARD" = true ]; then
            log "Enabling nginx config for WireGuard Panel (https://$DOMAIN:8443)..."
            sed "s|{{DOMAIN}}|$DOMAIN|g" "$SCRIPT_DIR/telegram-proxy/nginx/vpn-panel.conf.template" \
                > "$SCRIPT_DIR/telegram-proxy/nginx/conf.d/vpn-panel.conf"
        fi
        
        if ! docker compose exec -T web nginx -s reload; then
            err "Failed to reload nginx configuration"
        fi
        
        # Start remaining services
        if [ "$DEPLOY_TELEGRAM" = true ]; then
            if ! docker compose up -d; then
                err "Failed to start Telegram Proxy services"
            fi
        else
            # WireGuard-only: start web + certbot renewal (no telemt)
            if ! docker compose up -d web certbot; then
                err "Failed to start reverse proxy services"
            fi
        fi
    )
    if [ "$DEPLOY_TELEGRAM" = true ]; then
        ok "Telegram Proxy started on port 443"
    fi
    if [ "$DEPLOY_WIREGUARD" = true ]; then
        ok "Reverse proxy for WireGuard Panel started on port 8443"
    fi
    
    cd "$SCRIPT_DIR"
fi

# Deploy WireGuard Panel
if [ "$DEPLOY_WIREGUARD" = true ]; then
    log "Starting WireGuard Panel..."
    (
        cd "$SCRIPT_DIR/wireguard-panel"
        if ! docker compose up -d; then
            err "Failed to start WireGuard Panel"
        fi
        
        # Wait for the panel to respond
        log "Waiting for WireGuard Panel to be ready..."
        for i in $(seq 1 30); do
            if curl -sf "http://localhost:51821" >/dev/null 2>&1; then
                ok "WireGuard Panel is ready"
                break
            fi
            if [ "$i" -eq 30 ]; then
                docker compose logs --tail=50 wg-easy
                warn "WireGuard Panel did not respond yet. See logs above."
            fi
            sleep 2
        done
        
        # Remove initial credentials from .env (unattended setup has already applied them)
        if grep -q '^INIT_PASSWORD=' .env; then
            sed -i '/^INIT_PASSWORD=/d' .env
            sed -i '/^INIT_USERNAME=/d' .env
            log "Removed initial admin credentials from .env (saved in deployment_info.txt)"
        fi
    )
    ok "WireGuard Panel started (VPN on UDP 51820)"
    cd "$SCRIPT_DIR"
fi

# ── 7. Configure Fail2Ban ─────────────────────────────────
log "Configuring Fail2Ban after service deployment..."

# Configure fail2ban (now that containers are running)
log "Setting up Fail2Ban with systemd backend..."

# Create fail2ban configuration directory
mkdir -p /etc/fail2ban

# Copy configuration files
cp "$SCRIPT_DIR/fail2ban/jail.local" /etc/fail2ban/jail.local
mkdir -p /etc/fail2ban/filter.d
cp "$SCRIPT_DIR/fail2ban/docker-nginx.conf" /etc/fail2ban/filter.d/

# Set proper permissions
chmod 644 /etc/fail2ban/jail.local
chmod 644 /etc/fail2ban/filter.d/docker-nginx.conf

# Restart and enable fail2ban service
systemctl start fail2ban
systemctl enable fail2ban

# Check fail2ban status
if systemctl is-active --quiet fail2ban; then
    ok "Fail2Ban is running and configured"
else
    warn "Fail2Ban service is not running - manual check may be needed"
fi

# Show fail2ban status
log "Fail2Ban jails status:"
fail2ban-client status 2>/dev/null || log "Fail2Ban client not available, using systemctl status instead"
systemctl status fail2ban --no-pager -l

ok "Fail2Ban configuration completed"

# ── 8. Display Results ─────────────────────────────────
echo ""
echo "  ✅ Deployment complete!"
echo "  ─────────────────────────────────────────────"
echo ""

# Create deployment info file
INFO_FILE="$SCRIPT_DIR/deployment_info.txt"
cat > "$INFO_FILE" << EOF
========================================
VPS VPN Proxy Deployment Information
========================================
Deployment Date: $(date)
========================================

EOF

if [ "$DEPLOY_HTTP" = true ]; then
    echo -e "  HTTP Proxy (3proxy):"
    echo -e "    HTTP:   ${GREEN}${SERVER_IP}:8080${NC}"
    echo -e ""
    echo -e "    ${GREEN}user:${USER_PASS}@${SERVER_IP}:8080${NC}"
    echo ""
    
    # Add to info file
    cat >> "$INFO_FILE" << EOF
HTTP Proxy (3proxy):
- HTTP: ${SERVER_IP}:8080
- Connection:
  * user:${USER_PASS}@${SERVER_IP}:8080

EOF
fi

if [ "$DEPLOY_TELEGRAM" = true ]; then
    # Build ee-prefix FakeTLS proxy link
    TLS_HEX=$(printf '%s' "$DOMAIN" | od -An -tx1 | tr -d ' \n')
    FULL_SECRET="ee${SECRET}${TLS_HEX}"
    
    echo -e "  Telegram Proxy (telemt):"
    echo -e "    Domain: ${GREEN}$DOMAIN${NC}"
    echo -e "    Secret: ${GREEN}$SECRET${NC}"
    echo ""
    echo -e "    Telegram proxy links:"
    echo -e "    ${GREEN}tg://proxy?server=$DOMAIN&port=443&secret=$FULL_SECRET${NC}"
    echo -e "    ${GREEN}https://t.me/proxy?server=$DOMAIN&port=443&secret=$FULL_SECRET${NC}"
    echo ""
    
    # Add to info file
    cat >> "$INFO_FILE" << EOF
Telegram Proxy (telemt):
- Domain: $DOMAIN
- Secret: $SECRET
- Proxy links:
  * tg://proxy?server=$DOMAIN&port=443&secret=$FULL_SECRET
  * https://t.me/proxy?server=$DOMAIN&port=443&secret=$FULL_SECRET

EOF
fi

if [ "$DEPLOY_WIREGUARD" = true ]; then
    echo -e "  WireGuard Panel (wg-easy):"
    echo -e "    Panel URL: ${GREEN}https://$DOMAIN:8443${NC}"
    echo -e "    Username:  ${GREEN}admin${NC}"
    echo -e "    Password:  ${GREEN}$WG_ADMIN_PASSWORD${NC}"
    echo ""
    echo -e "    VPN Endpoint: ${GREEN}${SERVER_IP}:51820/udp${NC}"
    if [ "$ENABLE_AWG" = true ]; then
        echo -e "    Mode: ${YELLOW}AmneziaWG (experimental)${NC} — use AmneziaWG-compatible clients"
    fi
    echo ""
    
    # Add to info file
    cat >> "$INFO_FILE" << EOF
WireGuard Panel (wg-easy):
- Panel URL: https://${DOMAIN}:8443
- Username: admin
- Password: ${WG_ADMIN_PASSWORD}
- VPN Endpoint: ${SERVER_IP}:51820/udp
- Mode: $([ "$ENABLE_AWG" = true ] && echo "AmneziaWG (experimental)" || echo "Standard WireGuard")

EOF
fi

echo "  Useful commands:"
if [ "$DEPLOY_HTTP" = true ]; then
    echo "    cd $SCRIPT_DIR/http-proxy && docker compose ps"
    echo "    cd $SCRIPT_DIR/http-proxy && docker compose logs -f 3proxy"
fi
if [ "$DEPLOY_TELEGRAM" = true ]; then
    echo "    cd $SCRIPT_DIR/telegram-proxy && docker compose ps"
    echo "    cd $SCRIPT_DIR/telegram-proxy && docker compose logs -f telemt"
fi
if [ "$DEPLOY_WIREGUARD" = true ]; then
    echo "    cd $SCRIPT_DIR/wireguard-panel && docker compose ps"
    echo "    cd $SCRIPT_DIR/wireguard-panel && docker compose logs -f wg-easy"
fi

echo ""
echo "  Fail2Ban management:"
echo "    fail2ban-client status"
echo "    fail2ban-client status nginx-http-auth"
echo "    fail2ban-client set sshd unbanip IP_ADDRESS"
echo ""

# Add commands to info file
cat >> "$INFO_FILE" << EOF
Useful Commands:
EOF

if [ "$DEPLOY_HTTP" = true ]; then
    cat >> "$INFO_FILE" << EOF
- HTTP Proxy:
  * cd $SCRIPT_DIR/http-proxy && docker compose ps
  * cd $SCRIPT_DIR/http-proxy && docker compose logs -f 3proxy
EOF
fi

if [ "$DEPLOY_TELEGRAM" = true ]; then
    cat >> "$INFO_FILE" << EOF
- Telegram Proxy:
  * cd $SCRIPT_DIR/telegram-proxy && docker compose ps
  * cd $SCRIPT_DIR/telegram-proxy && docker compose logs -f telemt
EOF
fi

if [ "$DEPLOY_WIREGUARD" = true ]; then
    cat >> "$INFO_FILE" << EOF
- WireGuard Panel:
  * cd $SCRIPT_DIR/wireguard-panel && docker compose ps
  * cd $SCRIPT_DIR/wireguard-panel && docker compose logs -f wg-easy
EOF
fi

cat >> "$INFO_FILE" << EOF

Fail2Ban Management:
- fail2ban-client status
- fail2ban-client status nginx-http-auth
- fail2ban-client set sshd unbanip IP_ADDRESS

========================================
To read this information later: cat $INFO_FILE
========================================
EOF

echo -e "Deployment info saved to: ${GREEN}$INFO_FILE${NC}"
echo -e "To read later: ${GREEN}cat $INFO_FILE${NC}"
echo ""
