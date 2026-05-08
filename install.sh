#!/bin/bash

# VPS VPN Proxy One-Line Installer
# Downloads the repository and runs the deployment script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if required tools are available
check_requirements() {
    log "Checking requirements..."
    
    if ! command -v curl >/dev/null 2>&1; then
        err "curl is required but not installed"
    fi
    
    if ! command -v tar >/dev/null 2>&1; then
        err "tar is required but not installed"
    fi
    
    ok "All requirements satisfied"
}

# Download and extract repository
download_repository() {
    log "Downloading VPS VPN Proxy repository..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
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
    cd VPS_VPN_PROXY-master
    
    # Cleanup
    rm -f ../repository.tar.gz
    
    ok "Repository downloaded and extracted successfully"
}

# Run deployment
run_deployment() {
    log "Starting deployment..."
    
    # Make deploy script executable
    chmod +x deploy.sh
    
    # Run deployment script interactively
    ./deploy.sh
}

# Cleanup on exit
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log "Cleaning up temporary files..."
        cd /
        rm -rf "$TEMP_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Main execution
main() {
    echo ""
    echo -e "${BLUE}=== VPS VPN Proxy One-Line Installer ===${NC}"
    echo ""
    
    check_requirements
    download_repository
    run_deployment
    
    echo ""
    ok "Installation completed successfully!"
    echo ""
    echo -e "${YELLOW}Note: The temporary files have been cleaned up automatically.${NC}"
}

# Run main function
main "$@"
