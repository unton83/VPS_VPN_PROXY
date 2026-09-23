#!/bin/bash

# VPS Services Management Script
# Manage deployed proxy services

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[info]${NC} $1"; }
ok()   { echo -e "${GREEN}[ok]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
err()  { echo -e "${RED}[error]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  VPS Services Management"
echo "  ─────────────────────────────────────────────────────────────"
echo ""

# ── 1. Check what services are running ───────────────────────────────────
HTTP_PROXY_RUNNING=false
TELEGRAM_PROXY_RUNNING=false
WIREGUARD_RUNNING=false

if docker ps --format "table {{.Names}}" | grep -q "http-proxy"; then
    HTTP_PROXY_RUNNING=true
fi

if docker ps --format "table {{.Names}}" | grep -q "telegram-proxy\|telegram-web\|telegram-certbot"; then
    TELEGRAM_PROXY_RUNNING=true
fi

if docker ps --format "table {{.Names}}" | grep -q "wg-easy"; then
    WIREGUARD_RUNNING=true
fi

# ── 2. Show menu ────────────────────────────────────────────────────────
echo "Running services:"
if [ "$HTTP_PROXY_RUNNING" = true ]; then
    echo "  ✓ HTTP Proxy (3proxy)"
else
    echo "  ✗ HTTP Proxy (3proxy)"
fi

if [ "$TELEGRAM_PROXY_RUNNING" = true ]; then
    echo "  ✓ Telegram Proxy (telemt)"
else
    echo "  ✗ Telegram Proxy (telemt)"
fi

if [ "$WIREGUARD_RUNNING" = true ]; then
    echo "  ✓ WireGuard Panel (wg-easy)"
else
    echo "  ✗ WireGuard Panel (wg-easy)"
fi

echo ""
echo "Available actions:"
echo "1) Status - Show detailed service status"
echo "2) Logs - View service logs"
echo "3) Restart - Restart services"
echo "4) Stop - Stop all services"
echo "5) Start - Start services"
echo "6) Update - Update service images"
echo "7) Cleanup - Remove stopped containers and unused images"
echo "8) Exit"
echo ""
read -p "Enter choice [1-8]: " CHOICE

case $CHOICE in
    1) ACTION="status" ;;
    2) ACTION="logs" ;;
    3) ACTION="restart" ;;
    4) ACTION="stop" ;;
    5) ACTION="start" ;;
    6) ACTION="update" ;;
    7) ACTION="cleanup" ;;
    8) echo "Exiting..."; exit 0 ;;
    *) err "Invalid choice" ;;
esac

# ── 3. Execute action ────────────────────────────────────────────────────
case $ACTION in
    status)
        echo ""
        log "Service Status:"
        echo ""
        
        if [ "$HTTP_PROXY_RUNNING" = true ]; then
            echo "HTTP Proxy (3proxy):"
            cd "$SCRIPT_DIR/http-proxy"
            docker compose ps
            echo ""
        fi
        
        if [ "$TELEGRAM_PROXY_RUNNING" = true ]; then
            echo "Telegram Proxy (telemt):"
            cd "$SCRIPT_DIR/telegram-proxy"
            docker compose ps
            echo ""
        fi
        
        if [ "$WIREGUARD_RUNNING" = true ]; then
            echo "WireGuard Panel (wg-easy):"
            cd "$SCRIPT_DIR/wireguard-panel"
            docker compose ps
            echo ""
        fi
        
        echo "System Resources:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
        ;;
        
    logs)
        echo ""
        echo "Select service to view logs:"
        i=1
        LOG_OPTIONS=()
        if [ "$HTTP_PROXY_RUNNING" = true ]; then
            LOG_OPTIONS+=("HTTP Proxy (3proxy)|http-proxy|3proxy")
            echo "$i) HTTP Proxy (3proxy)"
            i=$((i+1))
        fi
        if [ "$TELEGRAM_PROXY_RUNNING" = true ]; then
            LOG_OPTIONS+=("Telegram Proxy (telemt)|telegram-proxy|telemt")
            echo "$i) Telegram Proxy (telemt)"
            i=$((i+1))
            LOG_OPTIONS+=("Nginx (Telegram)|telegram-proxy|web")
            echo "$i) Nginx (Telegram)"
            i=$((i+1))
            LOG_OPTIONS+=("Certbot (Telegram)|telegram-proxy|certbot")
            echo "$i) Certbot (Telegram)"
            i=$((i+1))
        fi
        if [ "$WIREGUARD_RUNNING" = true ]; then
            LOG_OPTIONS+=("WireGuard Panel (wg-easy)|wireguard-panel|wg-easy")
            echo "$i) WireGuard Panel (wg-easy)"
            i=$((i+1))
        fi
        echo "0) Back to main menu"
        echo ""
        read -p "Enter choice: " LOG_CHOICE
        
        if [ "$LOG_CHOICE" = "0" ]; then
            exec "$SCRIPT_DIR/manage.sh"
        fi
        
        idx=$((LOG_CHOICE - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#LOG_OPTIONS[@]}" ]; then
            IFS='|' read -r _log_name _log_dir _log_svc <<< "${LOG_OPTIONS[$idx]}"
            cd "$SCRIPT_DIR/$_log_dir"
            docker compose logs -f "$_log_svc"
        else
            err "Invalid choice"
        fi
        ;;
        
    restart)
        echo ""
        log "Restarting services..."
        
        if [ "$HTTP_PROXY_RUNNING" = true ]; then
            log "Restarting HTTP Proxy..."
            cd "$SCRIPT_DIR/http-proxy"
            docker compose restart
            ok "HTTP Proxy restarted"
        fi
        
        if [ "$TELEGRAM_PROXY_RUNNING" = true ]; then
            log "Restarting Telegram Proxy..."
            cd "$SCRIPT_DIR/telegram-proxy"
            docker compose restart
            ok "Telegram Proxy restarted"
        fi
        
        if [ "$WIREGUARD_RUNNING" = true ]; then
            log "Restarting WireGuard Panel..."
            cd "$SCRIPT_DIR/wireguard-panel"
            docker compose restart
            ok "WireGuard Panel restarted"
        fi
        ;;
        
    stop)
        echo ""
        log "Stopping services..."
        
        if [ "$HTTP_PROXY_RUNNING" = true ]; then
            log "Stopping HTTP Proxy..."
            cd "$SCRIPT_DIR/http-proxy"
            docker compose down
            ok "HTTP Proxy stopped"
        fi
        
        if [ "$TELEGRAM_PROXY_RUNNING" = true ]; then
            log "Stopping Telegram Proxy..."
            cd "$SCRIPT_DIR/telegram-proxy"
            docker compose down
            ok "Telegram Proxy stopped"
        fi
        
        if [ "$WIREGUARD_RUNNING" = true ]; then
            log "Stopping WireGuard Panel..."
            cd "$SCRIPT_DIR/wireguard-panel"
            docker compose down
            ok "WireGuard Panel stopped"
        fi
        ;;
        
    start)
        echo ""
        log "Starting services..."
        
        echo "Select services to start:"
        echo "1) HTTP Proxy only"
        echo "2) Telegram Proxy only"
        echo "3) WireGuard Panel only"
        echo "4) HTTP + Telegram"
        echo "5) HTTP + WireGuard"
        echo "6) Telegram + WireGuard"
        echo "7) All services"
        echo "0) Back to main menu"
        echo ""
        read -p "Enter choice: " START_CHOICE
        
        start_http() {
            cd "$SCRIPT_DIR/http-proxy"
            docker compose up -d
        }
        start_telegram() {
            cd "$SCRIPT_DIR/telegram-proxy"
            docker compose up -d
        }
        start_wireguard() {
            cd "$SCRIPT_DIR/wireguard-panel"
            docker compose up -d
        }
        
        case $START_CHOICE in
            1)
                start_http
                ok "HTTP Proxy started"
                ;;
            2)
                start_telegram
                ok "Telegram Proxy started"
                ;;
            3)
                start_wireguard
                ok "WireGuard Panel started"
                ;;
            4)
                start_http
                start_telegram
                ok "HTTP + Telegram started"
                ;;
            5)
                start_http
                start_wireguard
                ok "HTTP + WireGuard started"
                ;;
            6)
                start_telegram
                start_wireguard
                ok "Telegram + WireGuard started"
                ;;
            7)
                start_http
                start_telegram
                start_wireguard
                ok "All services started"
                ;;
            0)
                exec "$SCRIPT_DIR/manage.sh"
                ;;
            *)
                err "Invalid choice"
                ;;
        esac
        ;;
        
    update)
        echo ""
        log "Updating service images..."
        
        if [ "$HTTP_PROXY_RUNNING" = true ]; then
            log "Updating HTTP Proxy..."
            cd "$SCRIPT_DIR/http-proxy"
            docker compose pull
            docker compose up -d
            ok "HTTP Proxy updated"
        fi
        
        if [ "$TELEGRAM_PROXY_RUNNING" = true ]; then
            log "Updating Telegram Proxy..."
            cd "$SCRIPT_DIR/telegram-proxy"
            docker compose pull
            docker compose up -d
            ok "Telegram Proxy updated"
        fi
        
        if [ "$WIREGUARD_RUNNING" = true ]; then
            log "Updating WireGuard Panel..."
            cd "$SCRIPT_DIR/wireguard-panel"
            docker compose pull
            docker compose up -d
            ok "WireGuard Panel updated"
        fi
        ;;
        
    cleanup)
        echo ""
        log "Cleaning up Docker resources..."
        
        # Remove stopped containers
        docker container prune -f
        
        # Remove unused images
        docker image prune -f
        
        # Remove unused networks
        docker network prune -f
        
        ok "Cleanup completed"
        ;;
esac

echo ""
echo "  ✅ Action completed!"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
