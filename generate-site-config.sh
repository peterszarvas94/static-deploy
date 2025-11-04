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
    
    # Check if running as root or with sudo
    if [ "$EUID" -eq 0 ]; then
        log_warn "Running as root - consider using sudo instead"
    fi
    
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
    
    # Check firewall status (informational)
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        if ! ufw status | grep -q "80\|443"; then
            log_warn "UFW firewall is active but ports 80/443 may not be open"
            log_warn "Run: sudo ufw allow 'Nginx Full'"
        fi
    fi
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
    
    log_info "Generating config for $domain"
    
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
    log_success "Generated ${config_file}"
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
    
    # Test nginx configuration
    if sudo nginx -t &> /dev/null; then
        log_success "Nginx configuration test passed"
    else
        log_error "Nginx configuration test failed"
        sudo nginx -t
        exit 1
    fi
}

setup_ssl() {
    local domain=$1
    
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
    
    # Ensure nginx is running
    if ! systemctl is-active --quiet nginx; then
        log_info "Starting nginx for SSL verification"
        sudo systemctl start nginx
    fi
    
    # Get certificate for domain
    log_info "Getting SSL certificate for $domain"
    sudo certbot certonly --webroot -w /var/www/certbot -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email admin@"$domain"
    if [ $? -eq 0 ]; then
        log_success "SSL certificate obtained for $domain"
        # Reload nginx to use new certificates
        sudo systemctl reload nginx
    else
        log_error "Failed to get SSL certificate for $domain"
        log_error "Check that:"
        log_error "  1. Domain points to this server"
        log_error "  2. Ports 80/443 are open"
        log_error "  3. No other service is using port 80"
        exit 1
    fi
    
    # Setup auto-renewal cron job
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        log_info "Setting up SSL auto-renewal"
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | sudo crontab -
        log_success "SSL auto-renewal configured"
    fi
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