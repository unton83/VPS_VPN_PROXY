# VPS Services Deployment

One-command deployment of proxy services on low-resource VPS (1CPU, 1GB RAM, 5GB Storage).

## Services

- **HTTP Proxy (3proxy)** - HTTP proxy with authentication
- **Telegram Proxy (telemt)** - MTProto proxy with FakeTLS masking and cover website
- **AmneziaWG 2.0** - WireGuard VPN (prepared for future implementation)

## Quick Start

### One-Line Deployment

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/unton83/VPS_VPN_PROXY/master/deploy.sh)
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

- VPS with Ubuntu 20.04+ / Debian 11+
- Docker + Docker Compose v2
- For Telegram Proxy: Domain with A-record pointing to VPS IP
- Open ports: 80, 443 (Telegram), 8080 (HTTP Proxy)

## Service Configuration

### HTTP Proxy (3proxy)
- **HTTP**: `VPS_IP:8080`
- **Authentication**: Auto-generated usernames and passwords
- **Users**: user1, user2, user3 (credentials shown after deployment)

### Telegram Proxy (telemt)
- **Port**: 443 (HTTPS)
- **Protocol**: MTProto with FakeTLS masking
- **Cover Website**: Served on port 80
- **SSL**: Let's Encrypt certificates with auto-renewal
- **Proxy Links**: Generated automatically after deployment

## Deployment Options

The deployment script offers the following options:

1. **HTTP Proxy only** - Deploy just the 3proxy service
2. **Telegram Proxy only** - Deploy just the telemt service  
3. **Both services** - Deploy both HTTP and Telegram proxies
4. **Exit** - Cancel deployment

## Resource Usage

All services are optimized for low-resource VPS:

| Service | CPU Limit | Memory Limit | Network |
|---------|-----------|--------------|---------|
| 3proxy | 0.3 cores | 256MB | proxy-network |
| Nginx (Telegram) | 0.25 cores | 256MB | telegram-network |
| Telemt | 0.4 cores | 256MB | telegram-network |
| Certbot | 0.2 cores | 128MB | telegram-network |

**Total**: ~1.15 cores, ~896MB RAM (well within 1CPU/1GB limits)

## Management Commands

```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f 3proxy      # HTTP Proxy logs
docker compose logs -f telemt      # Telegram Proxy logs
docker compose logs -f web         # Nginx logs

# Restart services
docker compose restart 3proxy
docker compose restart telemt

# Update services
docker compose pull && docker compose up -d
```

## Security Features

- **Authentication**: All proxy services require username/password
- **TLS Encryption**: Telegram proxy uses FakeTLS masking
- **SSL Certificates**: Automatic Let's Encrypt certificates with renewal
- **Fail2Ban Protection**: Automatic IP banning for brute force attacks
- **Resource Limits**: Container resource constraints prevent resource abuse
- **Network Isolation**: Services use separate Docker networks

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
├── telegram-proxy/             # Telemt service files
│   ├── docker-compose.yml     # Telegram proxy compose file
│   ├── telemt/
│   │   └── telemt.toml        # Telemt configuration
│   ├── nginx/
│   │   ├── conf.d/            # Nginx configurations
│   │   └── ssl.conf.template  # SSL config template
│   ├── certbot/               # SSL certificate directories
│   └── website/               # Cover website files
└── .gitignore                 # Git ignore file
```

## Troubleshooting

### Port Conflicts
- Ensure ports 80, 443, 8080 are not in use
- Check firewall settings: `sudo ufw status`

### Docker Issues
- Verify Docker is running: `sudo systemctl status docker`
- Check Docker Compose version: `docker compose version`

### Certificate Issues
- Ensure domain A-record points to VPS IP
- Check certbot logs: `docker compose logs certbot`

### Performance Issues
- Monitor resource usage: `docker stats`
- Check container logs for errors

## Future Development

- **AmneziaWG 2.0** integration for WireGuard VPN
- **Service monitoring** and health checks
- **Configuration management** web interface
- **Backup and restore** functionality

## License

MIT License - feel free to use and modify for your needs.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review container logs for errors
3. Open an issue on GitHub repository
