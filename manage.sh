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

if docker ps --format "table {{.Names}}" | grep -q "http-proxy"; then
    HTTP_PROXY_RUNNING=true
fi

if docker ps --format "table {{.Names}}" | grep -q "telegram-proxy\|telegram-web\|telegram-certbot"; then
    TELEGRAM_PROXY_RUNNING=true
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
        
        echo "System Resources:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
        ;;
        
    logs)
        echo ""
        echo "Select service to view logs:"
        if [ "$HTTP_PROXY_RUNNING" = true ]; then
            echo "1) HTTP Proxy (3proxy)"
        fi
        if [ "$TELEGRAM_PROXY_RUNNING" = true ]; then
            if [ "$HTTP_PROXY_RUNNING" = true ]; then
                echo "2) Telegram Proxy (telemt)"
                echo "3) Nginx (Telegram)"
                echo "4) Certbot (Telegram)"
            else
                echo "1) Telegram Proxy (telemt)"
                echo "2) Nginx (Telegram)"
                echo "3) Certbot (Telegram)"
            fi
        fi
        echo "0) Back to main menu"
        echo ""
        read -p "Enter choice: " LOG_CHOICE
        
        case $LOG_CHOICE in
            1)
                if [ "$HTTP_PROXY_RUNNING" = true ]; then
                    cd "$SCRIPT_DIR/http-proxy"
                    docker compose logs -f 3proxy
                else
                    cd "$SCRIPT_DIR/telegram-proxy"
                    docker compose logs -f telemt
                fi
                ;;
            2)
                if [ "$HTTP_PROXY_RUNNING" = true ]; then
                    cd "$SCRIPT_DIR/telegram-proxy"
                    docker compose logs -f telemt
                else
                    cd "$SCRIPT_DIR/telegram-proxy"
                    docker compose logs -f web
                fi
                ;;
            3)
                if [ "$HTTP_PROXY_RUNNING" = true ]; then
                    cd "$SCRIPT_DIR/telegram-proxy"
                    docker compose logs -f web
                else
                    cd "$SCRIPT_DIR/telegram-proxy"
                    docker compose logs -f certbot
                fi
                ;;
            4)
                cd "$SCRIPT_DIR/telegram-proxy"
                docker compose logs -f certbot
                ;;
            0)
                exec "$SCRIPT_DIR/manage.sh"
                ;;
            *)
                err "Invalid choice"
                ;;
        esac
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
        ;;
        
    start)
        echo ""
        log "Starting services..."
        
        echo "Select services to start:"
        echo "1) HTTP Proxy only"
        echo "2) Telegram Proxy only"
        echo "3) Both services"
        echo "0) Back to main menu"
        echo ""
        read -p "Enter choice: " START_CHOICE
        
        case $START_CHOICE in
            1)
                cd "$SCRIPT_DIR/http-proxy"
                docker compose up -d
                ok "HTTP Proxy started"
                ;;
            2)
                cd "$SCRIPT_DIR/telegram-proxy"
                docker compose up -d
                ok "Telegram Proxy started"
                ;;
            3)
                cd "$SCRIPT_DIR/http-proxy"
                docker compose up -d
                cd "$SCRIPT_DIR/telegram-proxy"
                docker compose up -d
                ok "Both services started"
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
