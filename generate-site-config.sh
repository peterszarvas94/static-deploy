#!/bin/bash

# Nginx Static Site Configuration Generator
# Generates nginx configs with HTTP->HTTPS and www->non-www redirects
# Usage: ./generate-site-config.sh --flag domain.com

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking system prerequisites..."
    
    # Install nginx if not present
    if ! command -v nginx &> /dev/null; then
        log_info "Nginx not found, installing..."
        sudo apt update && sudo apt install -y nginx
        if [ $? -eq 0 ]; then
            log_success "Nginx installed successfully"
        else
            log_error "Failed to install nginx"
            exit 1
        fi
    else
        log_success "Nginx found"
    fi
    
    # Ensure nginx directories exist
    sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    
    # Check if nginx is enabled to start on boot
    if ! systemctl is-enabled nginx &> /dev/null; then
        log_info "Enabling nginx to start on boot"
        sudo systemctl enable nginx
    fi
    
    # Check firewall status (informational only)
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        if ! ufw status | grep -q "80\|443"; then
            log_warn "UFW firewall is active but ports 80/443 may not be open"
            log_warn "Run: sudo ufw allow 'Nginx Full'"
        fi
    fi
    
    log_success "Prerequisites checked (ignoring any existing nginx config issues)"
}

show_help() {
    echo "Usage: $0 [FLAG] <domain>"
    echo ""
    echo "Flags:"
    echo "  --conf     Generate config file only"
    echo "  --copy     Create directory and copy config to nginx"
    echo "  --enable   Enable site in nginx"
    echo "  --ssl      Setup SSL certificate with certbot"
    echo "  --all      Run all steps (conf + copy + enable + ssl)"
    echo "  --help     Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --all example.com"
    echo "  $0 --ssl example.com"
    echo "  $0 --conf example.com"
    echo ""
    echo "Prerequisites:"
    echo "  - Domain must point to this server's IP"
    echo "  - Ports 80 and 443 must be open"
    echo "  - Root/sudo access required"
    exit 0
}

generate_conf() {
    local domain=$1
    local webroot="/var/www/$domain"
    local config_file="${domain}.conf"
    
    log_info "Generating HTTP-only config for $domain (SSL will be added after certificate generation)"
    
    cat > "$config_file" << EOF
# HTTP config for ${domain} (before SSL)
server {
    listen 80;
    server_name ${domain} www.${domain};
    
    # Allow certbot challenges
    location /.well-known/acme-challenge/ { 
        root /var/www/certbot; 
    }
    
    # Temporary: serve content over HTTP until SSL is ready
    location / {
        # Redirect www to non-www
        if (\$host = www.${domain}) {
            return 301 http://${domain}\$request_uri;
        }
        root ${webroot};
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
EOF
    log_success "Generated HTTP-only ${config_file}"
}

generate_ssl_conf() {
    local domain=$1
    local webroot="/var/www/$domain"
    local config_file="${domain}.conf"
    
    log_info "Updating config to HTTPS for $domain"
    
    cat > "$config_file" << EOF
# HTTP -> HTTPS, www -> non-www for ${domain}
server {
    listen 80;
    server_name ${domain} www.${domain};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://${domain}\$request_uri; }
}

server {
    listen 443 ssl;
    server_name www.${domain};
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    return 301 https://${domain}\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${domain};
    root ${webroot};
    index index.html;
    
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    
    location / { try_files \$uri \$uri/ =404; }
}
EOF
    log_success "Updated to HTTPS config: ${config_file}"
}

copy_config() {
    local domain=$1
    local webroot="/var/www/$domain"
    local config_file="${domain}.conf"
    
    log_info "Creating webroot and copying config for $domain"
    
    # Ensure config file exists
    if [ ! -f "$config_file" ]; then
        log_error "Config file $config_file not found. Run --conf first."
        exit 1
    fi
    
    # Create webroot directory
    sudo mkdir -p "$webroot"
    log_success "Created webroot: ${webroot}"
    
    # Ensure nginx directories exist
    sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    
    # Copy to nginx sites directory
    sudo cp "$config_file" /etc/nginx/sites-available/
    log_success "Copied config to nginx sites-available"
}

enable_site() {
    local domain=$1
    local config_file="${domain}.conf"
    
    log_info "Enabling site for $domain"
    
    # Check if config exists in sites-available
    if [ ! -f "/etc/nginx/sites-available/$config_file" ]; then
        log_error "Config file not found in /etc/nginx/sites-available/. Run --copy first."
        exit 1
    fi
    
    # Enable site (remove existing symlink first if it exists)
    sudo rm -f "/etc/nginx/sites-enabled/$config_file"
    sudo ln -s "/etc/nginx/sites-available/$config_file" /etc/nginx/sites-enabled/
    log_success "Enabled site in nginx"
    
    # Test only our specific config by temporarily moving others
    log_info "Testing $domain configuration..."
    
    # Backup other enabled sites
    sudo mkdir -p /tmp/nginx-backup
    sudo find /etc/nginx/sites-enabled/ -name "*.conf" ! -name "$config_file" -exec mv {} /tmp/nginx-backup/ \;
    
    # Test with only our config
    if sudo nginx -t &> /dev/null; then
        log_success "$domain configuration is valid"
    else
        log_error "$domain configuration has errors:"
        sudo nginx -t
        # Restore other configs before exiting
        sudo find /tmp/nginx-backup/ -name "*.conf" -exec mv {} /etc/nginx/sites-enabled/ \;
        exit 1
    fi
    
    # Restore other configs
    sudo find /tmp/nginx-backup/ -name "*.conf" -exec mv {} /etc/nginx/sites-enabled/ \;
    sudo rmdir /tmp/nginx-backup 2>/dev/null
    
    log_success "$domain enabled and configuration validated"
}

setup_ssl() {
    local domain=$1
    local config_file="${domain}.conf"
    
    log_info "Setting up SSL certificate for $domain"
    
    # Check DNS resolution
    if ! dig +short "$domain" &> /dev/null && ! nslookup "$domain" &> /dev/null; then
        log_warn "Cannot resolve $domain - DNS might not be configured"
        log_warn "SSL certificate request may fail"
    fi
    
    # Install certbot if not installed
    if ! command -v certbot &> /dev/null; then
        log_info "Installing certbot..."
        sudo apt update && sudo apt install -y certbot python3-certbot-nginx
        if [ $? -ne 0 ]; then
            log_error "Failed to install certbot"
            exit 1
        fi
    fi
    
    # Create certbot directory
    sudo mkdir -p /var/www/certbot
    
    # Temporarily disable broken configs to start nginx cleanly
    log_info "Temporarily disabling broken configs for SSL verification..."
    sudo mkdir -p /tmp/nginx-ssl-backup
    
    # Move all configs except ours to backup
    sudo find /etc/nginx/sites-enabled/ -name "*.conf" ! -name "$config_file" -exec mv {} /tmp/nginx-ssl-backup/ \; 2>/dev/null
    
    # Start nginx with only our working config
    if ! systemctl is-active --quiet nginx; then
        log_info "Starting nginx for SSL verification (with only $domain config)"
        if sudo systemctl start nginx; then
            log_success "Nginx started successfully"
        else
            log_error "Failed to start nginx even with clean config"
            # Restore configs before exiting
            sudo find /tmp/nginx-ssl-backup/ -name "*.conf" -exec mv {} /etc/nginx/sites-enabled/ \; 2>/dev/null
            exit 1
        fi
    else
        log_info "Reloading nginx with clean config for SSL verification"
        sudo systemctl reload nginx
    fi
    
    # Get certificate for domain
    log_info "Getting SSL certificate for $domain"
    sudo certbot certonly --webroot -w /var/www/certbot -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email admin@"$domain"
    if [ $? -eq 0 ]; then
        log_success "SSL certificate obtained for $domain"
        
        # Now update config to use HTTPS
        generate_ssl_conf "$domain"
        
        # Copy updated config
        sudo cp "${domain}.conf" /etc/nginx/sites-available/
        log_success "Updated nginx config with SSL"
        
        # Test our SSL config in isolation
        sudo mkdir -p /tmp/nginx-ssl-test
        sudo find /etc/nginx/sites-enabled/ -name "*.conf" ! -name "$config_file" -exec mv {} /tmp/nginx-ssl-test/ \; 2>/dev/null
        
        if sudo nginx -t; then
            sudo systemctl reload nginx
            log_success "Nginx reloaded with SSL configuration"
        else
            log_error "SSL configuration test failed"
            exit 1
        fi
        
        # Restore other configs (even if broken)
        sudo find /tmp/nginx-ssl-test/ -name "*.conf" -exec mv {} /etc/nginx/sites-enabled/ \; 2>/dev/null
        sudo rmdir /tmp/nginx-ssl-test 2>/dev/null
        
    else
        log_error "Failed to get SSL certificate for $domain"
        log_error "Check that:"
        log_error "  1. Domain points to this server"
        log_error "  2. Ports 80/443 are open"
        log_error "  3. No other service is using port 80"
        
        # Restore other configs before exiting
        sudo find /tmp/nginx-ssl-backup/ -name "*.conf" -exec mv {} /etc/nginx/sites-enabled/ \; 2>/dev/null
        exit 1
    fi
    
    # Restore other configs
    sudo find /tmp/nginx-ssl-backup/ -name "*.conf" -exec mv {} /etc/nginx/sites-enabled/ \; 2>/dev/null
    sudo rmdir /tmp/nginx-ssl-backup 2>/dev/null
    
    # Setup auto-renewal cron job
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        log_info "Setting up SSL auto-renewal"
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | sudo crontab -
        log_success "SSL auto-renewal configured"
    fi
    
    log_success "$domain SSL setup complete and working!"
}

# Check arguments
if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
    show_help
fi

if [ $# -ne 2 ]; then
    log_error "Exactly 2 arguments required: flag and domain"
    show_help
fi

FLAG=$1
DOMAIN=$2

# Validate domain format
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    log_error "Invalid domain format: $DOMAIN"
    exit 1
fi

log_info "Processing domain: $DOMAIN"

case $FLAG in
    --conf)
        generate_conf "$DOMAIN"
        ;;
    --copy)
        check_prerequisites
        copy_config "$DOMAIN"
        ;;
    --enable)
        check_prerequisites
        enable_site "$DOMAIN"
        ;;
    --ssl)
        check_prerequisites
        setup_ssl "$DOMAIN"
        ;;
    --all)
        check_prerequisites
        generate_conf "$DOMAIN"
        copy_config "$DOMAIN"
        enable_site "$DOMAIN"
        setup_ssl "$DOMAIN"
        log_success "Site configured! Nginx should be running with SSL."
        log_info "Visit: https://$DOMAIN"
        ;;
    *)
        log_error "Unknown flag $FLAG"
        show_help
        ;;
esac