# VPS Services Deployment

One-command deployment of proxy services on low-resource VPS (1CPU, 1GB RAM, 5GB Storage).

## Services

- **HTTP Proxy (3proxy)** - HTTP proxy with authentication
- **Telegram Proxy (telemt)** - MTProto proxy with FakeTLS masking and cover website
- **WireGuard Panel (wg-easy)** - WireGuard VPN with web management panel, optional AmneziaWG

## Quick Start

### Check Telegram accessibility from VPS first

```bash
time curl -v https://api.telegram.org
```

### One-Line Deployment

```bash
bash <(curl -fsSL -H 'Cache-Control: no-cache, no-store' -H 'Pragma: no-cache' https://raw.githubusercontent.com/unton83/VPS_VPN_PROXY/master/deploy.sh)
```

### Manual Deployment

```bash
# Clone the repository
git clone https://github.com/unton83/VPS_VPN_PROXY.git
cd VPS_VPN_PROXY

# Make deploy script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh
```

## Requirements

- VPS with Debian 11+ (kernel 5.6+ for WireGuard)
- Docker + Docker Compose v2
- Domain with A-record pointing to VPS IP (for Telegram Proxy and WireGuard Panel)
- TUN support (/dev/net/tun) — for WireGuard
- Open ports: 80, 443 (Telegram), 8080 (HTTP Proxy), 51820/UDP (WireGuard VPN), 8443/TCP (WireGuard Panel)

## Service Configuration

### HTTP Proxy (3proxy)
- **HTTP**: `VPS_IP:8080`
- **Authentication**: Auto-generated username and password
- **User**: user (credentials shown after deployment)

### Telegram Proxy (telemt)
- **Port**: 443 (HTTPS)
- **Protocol**: MTProto with FakeTLS masking
- **Cover Website**: Served on port 80
- **SSL**: Let's Encrypt certificates with auto-renewal
- **Proxy Links**: Generated automatically after deployment

### WireGuard Panel (wg-easy)
- **Panel**: `https://DOMAIN:8443` (via a single nginx reverse proxy with SSL)
- **Login**: `admin`, password is generated automatically (saved in `deployment_info.txt`)
- **VPN Endpoint**: `VPS_IP:51820/udp`
- **Data**: stored in `wireguard-panel/data/` (client configs, keys)
- **Clients**: created via the web panel (QR codes, .conf download)
- **AmneziaWG (optional)**: protocol obfuscation against DPI — enabled at deployment time; requires the `amneziawg` kernel module (installed automatically via PPA) and AmneziaWG-compatible clients

## Single Reverse Proxy (nginx)

When Telegram Proxy or/and WireGuard Panel is selected, a single nginx gateway
(in the `telegram-proxy/` directory) is deployed:

| Port | Purpose |
|------|---------|
| 80 | Cover website + HTTP-01 challenge for Let's Encrypt |
| 443 | telemt (FakeTLS MTProto) |
| 8443 | WireGuard Panel (https://DOMAIN:8443) |
| 8444 | Internal: cover site for telemt (not exposed publicly) |

If only one of the services is selected, nginx is deployed for it. If none — nginx is not deployed.

## Deployment Options

The deployment script offers the following options:

1. **HTTP Proxy only** - Deploy just the 3proxy service
2. **Telegram Proxy only** - Deploy just the telemt service
3. **WireGuard Panel only** - Deploy just wg-easy (nginx for the panel is deployed automatically)
4. **HTTP + Telegram** - Deploy both proxies
5. **Telegram + WireGuard** - Deploy telegram proxy and the WireGuard panel
6. **HTTP + WireGuard** - Deploy HTTP proxy and the WireGuard panel
7. **All services** - Deploy all services
8. **Exit** - Cancel deployment

## Resource Usage

All services are optimized for low-resource VPS:

| Service | CPU Limit | Memory Limit | Network |
|---------|-----------|--------------|---------|
| 3proxy | 0.3 cores | 256MB | proxy-network |
| Nginx (Telegram) | 0.25 cores | 256MB | telegram-network |
| Telemt | 0.4 cores | 256MB | telegram-network |
| Certbot | 0.2 cores | 128MB | telegram-network |
| wg-easy | 0.5 cores | 512MB | default |

**Total with all services**: ~1.65 cores, ~1.4GB RAM (limits; actual usage is lower).
On a 1CPU/1GB VPS it is recommended not to deploy all services at once.

## Management Commands

```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f 3proxy      # HTTP Proxy logs
docker compose logs -f telemt      # Telegram Proxy logs
docker compose logs -f web         # Nginx logs
docker compose logs -f wg-easy     # WireGuard Panel logs

# Restart services
docker compose restart 3proxy
docker compose restart telemt
docker compose restart wg-easy

# Update services
docker compose pull && docker compose up -d
```

An interactive management script is also available: `./manage.sh`

## Security Features

- **Authentication**: All proxy services require username/password
- **TLS Encryption**: Telegram proxy uses FakeTLS masking; WireGuard Panel is behind nginx with SSL
- **SSL Certificates**: Automatic Let's Encrypt certificates with renewal
- **Fail2Ban Protection**: Automatic IP banning for brute force attacks
- **Resource Limits**: Container resource constraints prevent resource abuse
- **Network Isolation**: Services use separate Docker networks
- **WireGuard Panel**: accessible only via HTTPS reverse proxy, port 51821 bound to localhost

### Fail2Ban Configuration

The deployment script automatically installs and configures Fail2Ban with the following protections:

- **SSH Protection**: Blocks brute force SSH attempts (3 retries, 1 hour ban)
- **HTTP Authentication**: Blocks failed proxy authentication attempts
- **Rate Limiting**: Prevents excessive requests to web services
- **Bot Protection**: Blocks malicious bot traffic

**Fail2Ban Management Commands:**
```bash
# Check Fail2Ban status
sudo fail2ban-client status

# Check specific jail status
sudo fail2ban-client status sshd
sudo fail2ban-client status nginx-http-auth

# Unban an IP
sudo fail2ban-client set sshd unbanip IP_ADDRESS

# View banned IPs
sudo fail2ban-client banned
```

## Error Handling Improvements

The deployment script now includes enhanced error handling and rollback mechanisms:

- **Command execution with error checking**: All critical commands are executed via `run_cmd` which logs each step and validates exit codes.
- **Automatic rollback on failure**: If Docker installation fails, the script attempts to clean up partially installed packages.
- **Service deployment rollback**: If any service deployment fails, the script attempts to stop and remove any created containers.
- **Strict mode**: The script uses `set -euo pipefail` to catch unset variables, pipeline errors, and command failures early.
- **Detailed logging**: Each step is logged with timestamps and status indicators for easier debugging.

These improvements make the deployment process more robust and easier to troubleshoot.

## File Structure

```
VPS_VPN_PROXY/
├── deploy.sh                    # One-line deployment script
├── README.md                    # This file
├── README_RU.md                 # Russian documentation
├── manage.sh                    # Service management script
├── fail2ban/                   # Fail2Ban configuration
│   ├── jail.local              # Main jail configuration
│   └── docker-nginx.conf      # Docker nginx filter
├── http-proxy/                  # 3proxy service files
│   ├── 3proxy.cfg              # 3proxy configuration
│   ├── 3proxy.passwd           # Generated passwords
│   └── docker-compose.yml     # HTTP proxy compose file
├── telegram-proxy/             # Telemt service files and nginx gateway
│   ├── docker-compose.yml     # Telegram proxy compose file
│   ├── telemt/
│   │   └── telemt.toml        # Telemt configuration
│   ├── nginx/
│   │   ├── conf.d/            # Nginx configurations
│   │   ├── ssl.conf.template  # SSL config template (cover site, port 8444)
│   │   └── vpn-panel.conf.template  # Reverse proxy template for the panel (port 8443)
│   ├── certbot/               # SSL certificate directories
│   └── website/               # Cover website files
├── wireguard-panel/            # wg-easy service files
│   ├── docker-compose.yml     # WireGuard panel compose file
│   ├── .env.example           # Example environment variables
│   ├── .env                   # Generated by deploy.sh (admin password)
│   └── data/                  # WireGuard data (configs, keys)
└── .gitignore                 # Git ignore file
```

## Troubleshooting

### Port Conflicts
- Ensure ports 80, 443, 8080, 51820, 51821, 8443 are not in use
- Check firewall settings: `sudo ufw status`

### Docker Issues
- Verify Docker is running: `sudo systemctl status docker`
- Check Docker Compose version: `docker compose version`

### Certificate Issues
- Ensure domain A-record points to VPS IP
- Check certbot logs: `docker compose logs certbot`

### WireGuard doesn't work
- Check TUN availability: `ls -la /dev/net/tun`
- Make sure UDP 51820 is open in the firewall
- Check interface status: `docker exec wg-easy wg show`
- With AmneziaWG: verify the kernel module is loaded: `lsmod | grep amneziawg`

### Performance Issues
- Monitor resource usage: `docker stats`
- Check container logs for errors

## Future Development

- **Service monitoring** and health checks
- **Single port 443** for all services (ssl_preread SNI routing)
- **Backup and restore** functionality

## License

MIT License - feel free to use and modify for your needs.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review container logs for errors
3. Open an issue on GitHub repository
