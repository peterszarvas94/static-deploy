# TODO - SSL Auto-Renewal Fix

## Problem
SSL auto-renewal is failing because certbot is trying to use standalone mode while nginx is running on port 80.

Error:
```
Could not bind TCP port 80 because it is already in use by another process on this system (such as a web server). Please stop the program in question and then try again.
```

## Root Cause
1. **Initial SSL setup**: Script uses `--standalone` mode, requiring nginx to be stopped temporarily
2. **Auto-renewal cron job**: Uses `certbot renew --quiet` which tries to use the same method (standalone)
3. **Renewal failure**: Cron job can't bind to port 80 because nginx is running

## Solution Required

### 1. Immediate Fix (Manual)
Update existing renewal configurations to use webroot method:

```bash
# Update renewal method for existing certificates
sudo sed -i 's/authenticator = standalone/authenticator = webroot/' /etc/letsencrypt/renewal/*.conf

# Add webroot path to renewal configs  
for conf in /etc/letsencrypt/renewal/*.conf; do
    echo "webroot_path = /var/www/certbot" | sudo tee -a "$conf"
done

# Test renewal
sudo certbot renew --dry-run
```

### 2. Script Updates Needed (generate.sh)

#### A. Update SSL Setup Function (setup_ssl)
Change from single-stage to two-stage approach:

1. **Stage 1**: Create HTTP-only nginx config with `.well-known/acme-challenge/` location
2. **Stage 2**: Get certificates using `--webroot` method (nginx stays running)
3. **Stage 3**: Update to HTTPS config

#### B. Ensure Webroot Directory
Always create `/var/www/certbot` directory and set proper permissions:

```bash
sudo mkdir -p /var/www/certbot
sudo chown -R www-data:www-data /var/www/certbot
sudo chmod -R 755 /var/www/certbot
```

#### C. Use Webroot Method for Initial Certificates
Replace standalone method:

```bash
# OLD (current):
sudo certbot certonly --standalone --cert-name "$domain" -d "$domain" -d "www.$domain"

# NEW (needed):
sudo certbot certonly --webroot -w /var/www/certbot --cert-name "$domain" -d "$domain" -d "www.$domain"
```

#### D. Update Cron Job
Current cron job is fine, but ensure it uses webroot method by default.

### 3. HTTP-Only Config Template
Need temporary HTTP-only nginx config for certificate generation:

```nginx
server {
    listen 80;
    server_name ${domain} www.${domain};
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }
    
    location / {
        return 200 "Certificate generation in progress...";
        add_header Content-Type text/plain;
    }
}
```

### 4. Testing
After implementing changes:

1. Test with a new domain to ensure webroot method works
2. Test renewal: `sudo certbot renew --dry-run`
3. Verify cron job works: manually run the renewal command

## Priority
**HIGH** - SSL certificates will expire if auto-renewal continues to fail.

## Files to Modify
- `generate.sh` - Main script updates
- Update documentation about the two-stage process
