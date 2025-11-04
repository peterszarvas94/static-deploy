# Nginx Static Site Setup

## Overview
Single script to setup multiple static websites with:
- HTTP → HTTPS redirects
- www → non-www redirects
- Auto SSL certificate renewal
- Automated nginx configuration

## Quick Start
```bash
# One-liner setup (future):
wget -O - https://raw.githubusercontent.com/user/repo/main/generate-site-config.sh | bash -s -- --all example.com

# Or download and run:
wget https://raw.githubusercontent.com/user/repo/main/generate-site-config.sh
chmod +x generate-site-config.sh
./generate-site-config.sh --all example.com
```

## Manual Installation

### 1. Install Nginx
```bash
sudo apt update && sudo apt install nginx
```

### 2. Run the Script
```bash
# Complete setup for a site
./generate-site-config.sh --all example.com

# Or step by step:
./generate-site-config.sh --conf example.com     # Generate config
./generate-site-config.sh --copy example.com     # Create dir & copy
./generate-site-config.sh --enable example.com   # Enable site
./generate-site-config.sh --ssl example.com      # Setup SSL

# For multiple sites, run separately:
./generate-site-config.sh --all mysite.com
```

### 3. Copy Your Files
```bash
# Copy your static files to webroot (automatically created)
sudo cp -r /path/to/your/site/* /var/www/example.com/
```

### 4. Start Nginx
```bash
sudo nginx -t && sudo systemctl restart nginx && sudo systemctl enable nginx
```

### 2. Copy Main Configuration
```bash
sudo cp nginx.conf /etc/nginx/nginx.conf
```

### 3. Generate Site Configuration
```bash
# View all available options
./generate-site-config.sh --help

# Generate, copy, and enable site in one command
./generate-site-config.sh --all example.com

# Or run steps individually:
./generate-site-config.sh --conf example.com     # Generate config file
./generate-site-config.sh --copy example.com     # Create dir + copy to nginx
./generate-site-config.sh --enable example.com   # Enable site
```

### 4. Setup Files and SSL
```bash
# Create certbot directory
sudo mkdir -p /var/www/certbot

# Copy your static files to webroot (directory created by --copy or --all)
sudo cp -r /path/to/your/site/* /var/www/example.com/
```

### 5. Setup SSL Certificates
```bash
# SSL is included with --all flag, or run separately:
./generate-site-config.sh --ssl example.com
```

### 6. Start Nginx
```bash
sudo nginx -t  # Test configuration
sudo systemctl start nginx
sudo systemctl enable nginx
```

## Script Flags

The script supports these flags:
- `--conf` - Generate config files only
- `--copy` - Create directories and copy configs to nginx
- `--enable` - Enable sites in nginx  
- `--ssl` - Setup SSL certificates with certbot
- `--all` - Run all steps (conf + copy + enable + ssl)
- `--help` - Show usage information

**Examples:**
```bash
./generate-site-config.sh --help           # Show all options
./generate-site-config.sh --all example.com # Complete setup
./generate-site-config.sh --ssl example.com # SSL only

# For multiple sites, run the script multiple times:
./generate-site-config.sh --all site1.com
./generate-site-config.sh --all site2.com
```

### Directory Paths
- Sites: `/var/www/domain.com` (automatically created)
- Certbot challenges: `/var/www/certbot`

### SSL Certificates
Certificates are stored in:
- `/etc/letsencrypt/live/domain.com/fullchain.pem`
- `/etc/letsencrypt/live/domain.com/privkey.pem`

## Auto Renewal
Certificates auto-renew daily at 3 AM via cron job.

Check renewal status:
```bash
sudo certbot certificates
```

Manual renewal:
```bash
sudo certbot renew
sudo systemctl reload nginx
```