#!/bin/bash

# VPS VPN Proxy Deployment Script
# Deploys HTTP and Telegram proxies with system preparation and Fail2Ban protection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running from curl or local
if [ -t 0 ]; then
    # Running from curl - download to user home
    USER_HOME="$HOME"
    PROJECT_DIR="$USER_HOME/VPS_VPN_PROXY"
    SCRIPT_DIR="$PROJECT_DIR"
    
    log "Running from curl - setting up in $PROJECT_DIR"
    
    # Download and extract to user home
    if [ ! -d "$PROJECT_DIR" ]; then
        cd "$USER_HOME"
        
        # Download repository as tarball
        REPO_URL="https://github.com/unton83/VPS_VPN_PROXY/archive/master.tar.gz"
        log "Downloading repository to $PROJECT_DIR..."
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
else
    # Running locally - use script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Logging functions
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

# ── 1. System Preparation ───────────────────────────────────────
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
    if [[ "$OS" == *"Ubuntu"* ]]; then
        if [[ "${VER%%.*}" -lt "20" ]]; then
            err "Ubuntu $VER is not supported. Please use Ubuntu 20.04 or later."
        fi
    elif [[ "$OS" == *"Debian"* ]]; then
        if [[ "${VER%%.*}" -lt "11" ]]; then
            err "Debian $VER is not supported. Please use Debian 11 or later."
        fi
    else
        err "Unsupported OS: $OS. Please use Ubuntu 20.04+ or Debian 11+."
    fi
    
    ok "OS compatibility check passed"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    ok "System packages updated"
}

# Install Docker if not present
install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log "Installing Docker..."
        sudo apt install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
        ok "Docker installed and started"
    else
        log "Docker already installed"
    fi
    
    # Install Docker Compose if not present
    if ! command -v docker compose >/dev/null 2>&1; then
        log "Installing Docker Compose..."
        sudo apt install -y docker-compose-plugin
        ok "Docker Compose installed"
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
        sudo apt install -y openssl
        ok "openssl installed"
    else
        log "openssl already installed"
    fi
    
    # Install curl if not present
    if ! command -v curl >/dev/null 2>&1; then
        log "Installing curl..."
        sudo apt install -y curl
        ok "curl installed"
    else
        log "curl already installed"
    fi
}

ok "System preparation completed"

# ── 2. Service Selection ───────────────────────────────────────
echo ""
echo -e "${YELLOW}Select services to deploy:${NC}"
echo "1) HTTP Proxy only (3proxy)"
echo "2) Telegram Proxy only (telemt)"
echo "3) Both HTTP Proxy and Telegram Proxy"
echo "4) Exit"
echo ""
# Only read input if no piped input is available
if [ -t 0 ]; then
    read -p "Enter choice [1-4]: " CHOICE
else
    # Input is piped, use it
    CHOICE="3"
fi

case $CHOICE in
    1) DEPLOY_HTTP=true; DEPLOY_TELEGRAM=false ;;
    2) DEPLOY_HTTP=false; DEPLOY_TELEGRAM=true ;;
    3) DEPLOY_HTTP=true; DEPLOY_TELEGRAM=true ;;
    4) echo "Exiting..."; exit 0 ;;
    *) err "Invalid choice" ;;
esac

# ── 3. HTTP Proxy Setup ─────────────────────────────────────────
if [ "$DEPLOY_HTTP" = true ]; then
    echo ""
    log "Setting up HTTP Proxy (3proxy)..."
    
    # Generate secure passwords for users
    log "Generating secure passwords..."
    USER1_PASS=$(openssl rand -base64 16)
    USER2_PASS=$(openssl rand -base64 16)
    USER3_PASS=$(openssl rand -base64 16)
    
    # Create password file for 3proxy
    cat > "$SCRIPT_DIR/http-proxy/3proxy.passwd" << EOF
user1:CL:$USER1_PASS
user2:CL:$USER2_PASS
user3:CL:$USER3_PASS
EOF
    
    ok "HTTP Proxy configured"
fi

# ── 4. Telegram Proxy Setup ─────────────────────────────────────────
if [ "$DEPLOY_TELEGRAM" = true ]; then
    echo ""
    log "Setting up Telegram Proxy (telemt)..."
    
    echo -e "${YELLOW}Enter your domain (e.g. example.com).${NC}"
    echo -e "${YELLOW}DNS A record must already point to this server's IP.${NC}"
    read -r DOMAIN
    [[ -z "$DOMAIN" ]] && err "Domain cannot be empty."
    
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
    mkdir -p "$SCRIPT_DIR/telegram-proxy/telemt/data/tlsfront"
    rm -f "$SCRIPT_DIR/telegram-proxy/nginx/conf.d/ssl.conf"
    
    ok "Telegram Proxy configured"
fi

# ── 5. Deploy Services ─────────────────────────────────────────
echo ""
log "Deploying services..."

# Deploy HTTP Proxy
if [ "$DEPLOY_HTTP" = true ]; then
    log "Starting HTTP Proxy..."
    cd "$SCRIPT_DIR/http-proxy"
    docker compose up -d
    ok "HTTP Proxy started on port 8080 (HTTP)"
fi

# Deploy Telegram Proxy
if [ "$DEPLOY_TELEGRAM" = true ]; then
    log "Starting Telegram Proxy..."
    cd "$SCRIPT_DIR/telegram-proxy"
    
    # Start nginx (HTTP-only) first
    docker compose up -d web
    
    log "Waiting for nginx to be ready..."
    for i in $(seq 1 20); do
        if curl -sf http://localhost/health >/dev/null 2>&1 || \
           wget -qO- http://localhost/health >/dev/null 2>&1; then
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
    
    # Obtain Let's Encrypt certificate
    log "Requesting Let's Encrypt certificate for $DOMAIN ..."
    docker compose run --rm --entrypoint certbot certbot certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domain "$DOMAIN"
    
    # Enable SSL on nginx
    log "Enabling nginx SSL config (port 8443 for cover site)..."
    sed "s/{{DOMAIN}}/$DOMAIN/g" "$SCRIPT_DIR/telegram-proxy/nginx/ssl.conf.template" \
        > "$SCRIPT_DIR/telegram-proxy/nginx/conf.d/ssl.conf"
    
    docker compose exec -T web nginx -s reload
    
    # Start all telegram proxy services
    docker compose up -d
    ok "Telegram Proxy started on port 443"
    
    cd "$SCRIPT_DIR"
fi

# ── 6. Configure Fail2Ban ─────────────────────────────────────────
log "Configuring Fail2Ban after service deployment..."

# Configure fail2ban (now that containers are running)
log "Setting up Fail2Ban with systemd backend..."

# Create fail2ban configuration directory
sudo mkdir -p /etc/fail2ban

# Copy configuration files
sudo cp "$SCRIPT_DIR/fail2ban/jail.local" /etc/fail2ban/jail.local
sudo mkdir -p /etc/fail2ban/filter.d
sudo cp "$SCRIPT_DIR/fail2ban/docker-nginx.conf" /etc/fail2ban/filter.d/

# Set proper permissions
sudo chmod 644 /etc/fail2ban/jail.local
sudo chmod 644 /etc/fail2ban/filter.d/docker-nginx.conf

# Restart and enable fail2ban service
sudo systemctl restart fail2ban
sudo systemctl enable fail2ban

# Check fail2ban status
if sudo systemctl is-active --quiet fail2ban; then
    ok "Fail2Ban is running and configured"
else
    warn "Fail2Ban service is not running - manual check may be needed"
fi

# Show fail2ban status
log "Fail2Ban jails status:"
sudo fail2ban-client status 2>/dev/null || log "Fail2Ban client not available, using systemctl status instead"
sudo systemctl status fail2ban --no-pager -l

ok "Fail2Ban configuration completed"

# ── 7. Display Results ─────────────────────────────────────────
echo ""
echo "  ✅ Deployment complete!"
echo "  ─────────────────────────────────────────────────────"
echo ""

if [ "$DEPLOY_HTTP" = true ]; then
    echo "  HTTP Proxy (3proxy):"
    echo "    HTTP:   YOUR_VPS_IP:8080"
    echo "    Username: user1"
    echo "    Password: $USER1_PASS"
    echo "    Other users: user2 ($USER2_PASS), user3 ($USER3_PASS)"
    echo ""
fi

if [ "$DEPLOY_TELEGRAM" = true ]; then
    # Build ee-prefix FakeTLS proxy link
    TLS_HEX=$(printf '%s' "$DOMAIN" | od -An -tx1 | tr -d ' \n')
    FULL_SECRET="ee${SECRET}${TLS_HEX}"
    
    echo "  Telegram Proxy (telemt):"
    echo "    Domain: $DOMAIN"
    echo "    Secret: $SECRET"
    echo ""
    echo "    Telegram proxy links:"
    echo "    tg://proxy?server=$DOMAIN&port=443&secret=$FULL_SECRET"
    echo "    https://t.me/proxy?server=$DOMAIN&port=443&secret=$FULL_SECRET"
    echo ""
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

echo ""
echo "  Fail2Ban management:"
echo "    sudo fail2ban-client status"
echo "    sudo fail2ban-client status nginx-http-auth"
echo "    sudo fail2ban-client set sshd unbanip IP_ADDRESS"
echo ""