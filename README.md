# Nginx Static Site Setup

## Overview

Single script to setup static websites with:
- **Two-stage SSL deployment** - HTTP first, HTTPS after certificate generation
- **HTTP → HTTPS redirects** - Automatic HTTPS enforcement
- **Optional www → non-www redirects** - Use --www flag when needed
- **Auto SSL certificate renewal** - Let's Encrypt with cron
- **Automated nginx configuration** - Zero-config setup
- **Fresh Ubuntu compatible** - Auto-installs dependencies

## Quick Start

One-liner (non-www only):

```bash
wget -O - "https://raw.githubusercontent.com/peterszarvas94/static-deploy/refs/heads/master/generate.sh?$(date +%s)" | bash -s -- -a
```

One-liner with www redirect:

```bash
wget -O - "https://raw.githubusercontent.com/peterszarvas94/static-deploy/refs/heads/master/generate.sh?$(date +%s)" | bash -s -- -a -w
```

Or clone and run locally:

```bash
git clone https://github.com/peterszarvas94/static-deploy.git
cd static-deploy
chmod +x generate.sh
./generate.sh -a                    # non-www only
./generate.sh -a -w                 # with www redirect
```

Or clone and run locally:

```bash
git clone https://github.com/peterszarvas94/static-deploy.git
cd static-deploy
chmod +x generate.sh
./generate.sh -a
```

## How It Works

The script uses a **two-stage approach** to avoid SSL certificate chicken-and-egg problems:

1. **Stage 1 - HTTP Setup**: Creates HTTP-only config, enables site
2. **Stage 2 - SSL Setup**: Gets certificates, updates to HTTPS config

## Prerequisites

- Ubuntu/Debian server with root/sudo access
- Domain pointing to your server's IP address
- Ports 80 and 443 open (script will warn about firewall issues)

_Note: The script auto-installs nginx and certbot if missing_

## Manual Setup (Step by Step)

### 1. Download and Run

```bash
# Complete setup (non-www only):
./generate.sh --all --domain=example.com
# Or with short flags:
./generate.sh -a -d example.com

# Complete setup with www redirect (www→non-www):
./generate.sh --all --www --domain=example.com
# Or with short flags:
./generate.sh -a -w -d example.com

# Interactive mode (will prompt for domain):
./generate.sh --all
./generate.sh -a

# Step by step:
./generate.sh --conf --domain=example.com     # Generate config
./generate.sh --copy --domain=example.com     # Create dir & copy to nginx
./generate.sh --enable --domain=example.com   # Enable site
./generate.sh --ssl --domain=example.com      # Get SSL & update config
```

### 2. Deploy Your Website Files

After running the script, your nginx + SSL setup is complete! Now add your website files:

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

```bash
# Run the script separately for each domain:
./generate.sh --all --domain=site1.com
./generate.sh --all --domain=site2.com
./generate.sh --all --domain=site3.com

# Or with short flags:
./generate.sh -a -d site1.com
./generate.sh -a -d site2.com
./generate.sh -a -d site3.com

# Or run multiple times in interactive mode:
./generate.sh -a  # Will prompt: enter site1.com
./generate.sh -a  # Will prompt: enter site2.com
./generate.sh -a  # Will prompt: enter site3.com
```

## Script Flags

```bash
./generate.sh [ACTION] [--domain=example.com]
```

**Available actions:**

| Long Flag  | Short | Description                                          |
| ---------- | ----- | ---------------------------------------------------- |
| `--conf`   | `-c`  | Generate HTTP config file only                       |
| `--copy`   | `-p`  | Create directory and copy config to nginx            |
| `--enable` | `-e`  | Enable site in nginx (tests config first)            |
| `--ssl`    | `-s`  | Get SSL certificate and update to HTTPS config       |
| `--all`    | `-a`  | Run all steps: conf → copy → enable → ssl            |
| `--check`  | `-k`  | Check domain health (DNS, HTTP, HTTPS, SSL)          |
| `--remove` | `-r`  | Remove site completely (webroot + config + SSL cert) |
| `--help`   | `-h`  | Show usage and prerequisites                         |

**Domain options:**
- `--domain=example.com` or `-d example.com` - Specify domain
- `--www` or `-w` - Redirect www to non-www (optional)
- If no domain provided, script will prompt for input

**Examples:**
```bash
# Show help
./generate.sh --help
./generate.sh -h

# Complete setup (non-www only)
./generate.sh --all --domain=example.com
./generate.sh -a -d example.com

# Complete setup with www redirect
./generate.sh --all --www --domain=example.com
./generate.sh -a -w -d example.com

# Interactive mode
./generate.sh --all    # Will prompt for domain
./generate.sh -a       # Same, with short flag

# Health check
./generate.sh --check --domain=example.com
./generate.sh -k -d example.com

# Remove site
./generate.sh --remove --domain=example.com
./generate.sh -r -d example.com
```

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
