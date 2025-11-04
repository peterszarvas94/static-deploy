# static-deploy

Nginx Static Site Setup Generator

## Overview

Single script to setup static websites with:

- **One-command SSL deployment** - Automatic SSL certificate generation and HTTPS configuration
- **HTTP → HTTPS redirects** - Automatic HTTPS enforcement
- **Optional www → non-www redirects** - Use --www flag when needed
- **Auto SSL certificate renewal** - Let's Encrypt with cron
- **Automated nginx configuration** - Zero-config setup
- **Fresh Ubuntu compatible** - Auto-installs dependencies

## Quick Start

Clone the repo to the server:

```bash
git clone https://github.com/peterszarvas94/static-deploy.git
cd static-deploy
chmod +x generate.sh
sudo ./generate.sh --all --www
```

## How It Works

The script handles SSL certificates and HTTPS configuration automatically in a single command:

1. **SSL Certificate**: Gets Let's Encrypt certificates using standalone mode
2. **HTTPS Configuration**: Generates nginx config with SSL and HTTP→HTTPS redirects
3. **Site Activation**: Copies config to nginx and enables the site

## Prerequisites

- Ubuntu/Debian server with root/sudo access
- Domain pointing to your server's IP address
- Ports 80 and 443 open (script will warn about firewall issues)

_Note: The script auto-installs nginx and certbot if missing_

## Usage

### 1. Run the Script

Most users should use the `--all` flag for complete setup:

```bash
sudo ./generate.sh --all --domain=yourdomain.com
```

### 2. Deploy Your Website Files

After running the script, your nginx + SSL setup is complete! The script handles everything automatically. Now just add your website files:

```bash
# The script creates your webroot at: /var/www/yourdomain.com/

# Option 1: Copy files directly on server
sudo cp -r /path/to/your/website/* /var/www/example.com/

# Option 2: Upload from local machine via SCP
scp -r /local/website/* user@server:/tmp/website/
sudo mv /tmp/website/* /var/www/example.com/

# Option 3: Upload from local machine via rsync
rsync -avz /local/website/ user@server:/tmp/website/
sudo mv /tmp/website/* /var/www/example.com/

# Option 4: Quick test page
sudo bash -c 'cat > /var/www/example.com/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>My Site</title></head>
<body>
    <h1>Welcome to my site! </h1>
    <p>Nginx + SSL working perfectly!</p>
</body>
</html>
EOF'

# Set proper permissions
sudo chown -R www-data:www-data /var/www/example.com/
sudo chmod -R 755 /var/www/example.com/
```

**Visit your site:** `https://example.com` - should show your content with SSL!

### 3. Multiple Sites

Run the script separately for each domain:

```bash
sudo ./generate.sh --all --domain=site1.com
sudo ./generate.sh --all --domain=site2.com
sudo ./generate.sh --all --domain=site3.com
```

## Script Flags

```bash
./generate.sh [ACTION] [--domain=example.com]
```

**Available actions:**

| Long Flag  | Short | Description                                            |
| ---------- | ----- | ------------------------------------------------------ |
| `--conf`   | `-c`  | Generate HTTPS config file (requires SSL certificates) |
| `--copy`   | `-p`  | Create directory and copy config to nginx              |
| `--enable` | `-e`  | Enable site in nginx (tests config first)              |
| `--ssl`    | `-s`  | Get SSL certificate using Let's Encrypt                |
| `--all`    | `-a`  | Run all steps: ssl → conf → copy → enable              |
| `--check`  | `-k`  | Check domain health (DNS, HTTP, HTTPS, SSL)            |
| `--remove` | `-r`  | Remove site completely (webroot + config + SSL cert)   |
| `--help`   | `-h`  | Show usage and prerequisites                           |

**Options:**

| Long Flag              | Short            | Description                        |
| ---------------------- | ---------------- | ---------------------------------- |
| `--domain=example.com` | `-d example.com` | Specify domain to work with        |
| `--www`                | `-w`             | Redirect www to non-www (optional) |

**Note:** If no domain provided, script will prompt for input

## File Structure

**Created automatically:**

- `/var/www/example.com/` - Your website files go here
- `/etc/nginx/sites-available/example.com.conf` - Nginx config
- `/etc/nginx/sites-enabled/example.com.conf` - Symlink to enabled config
- `/var/www/certbot/` - Let's Encrypt challenge directory

**SSL certificates stored at:**

- `/etc/letsencrypt/live/example.com/fullchain.pem`
- `/etc/letsencrypt/live/example.com/privkey.pem`

## SSL Auto-Renewal

- **Automatic daily renewal** at 3 AM via cron job
- **Nginx auto-reload** after renewal
- **90-day Let's Encrypt certificates** renewed at 30 days

**Check certificate status:**

```bash
sudo certbot certificates
sudo certbot renew --dry-run  # Test renewal
```

## Troubleshooting

**Common issues:**

1. **"Domain not resolving"** - Make sure DNS points to your server
2. **"Port 80/443 blocked"** - Check firewall: `sudo ufw allow 'Nginx Full'`
3. **"SSL certificate failed"** - Ensure domain resolves and no other service uses port 80
4. **"Permission denied"** - Run with `sudo` or as root user

**Check everything is working:**

```bash
sudo nginx -t                    # Test nginx config
sudo systemctl status nginx      # Check nginx status
sudo certbot certificates        # Check SSL certificates
curl -I https://example.com      # Test HTTPS redirect
```

## Examples

### Complete Setup

```bash
# Basic setup (non-www domain only)
sudo ./generate.sh --all --domain=example.com
sudo ./generate.sh -a -d example.com                    # Short flags

# Setup with www redirect (www.example.com → example.com)
sudo ./generate.sh --all --www --domain=example.com
sudo ./generate.sh -a -w -d example.com                 # Short flags

# Interactive mode (will prompt for domain)
sudo ./generate.sh --all
sudo ./generate.sh -a                                   # Short flag
```

### Health Checks

```bash
# Check domain health (DNS, HTTP, HTTPS, SSL)
sudo ./generate.sh --check --domain=example.com
sudo ./generate.sh -k -d example.com                    # Short flags
```

### Site Management

```bash
# Remove site completely (webroot + config + SSL cert)
sudo ./generate.sh --remove --domain=example.com
sudo ./generate.sh -r -d example.com                    # Short flags

# Show help
./generate.sh --help
./generate.sh -h                                        # Short flag
```

### Advanced: Manual Step-by-Step

```bash
# If you need granular control over each step:
sudo ./generate.sh --ssl --domain=example.com          # Get SSL certificate
sudo ./generate.sh --conf --domain=example.com         # Generate HTTPS config
sudo ./generate.sh --copy --domain=example.com         # Create dir & copy to nginx
sudo ./generate.sh --enable --domain=example.com       # Enable site
```

### Multiple Sites

```bash
# Set up multiple domains
sudo ./generate.sh --all --domain=blog.example.com
sudo ./generate.sh --all --domain=shop.example.com
sudo ./generate.sh --all --domain=api.example.com

# Or with www redirects
sudo ./generate.sh --all --www --domain=blog.example.com
sudo ./generate.sh --all --www --domain=shop.example.com
```

---

This project created with the assistance of [Claude](https://claude.ai) and [OpenCode](https://opencode.ai)
