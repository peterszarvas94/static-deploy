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
    echo "Usage: $0 [ACTION] [--domain=example.com]"
    echo ""
    echo "Actions:"
    echo "  --conf,    -c    Generate HTTP config file only"
    echo "  --copy,    -p    Create directory and copy config to nginx"
    echo "  --enable,  -e    Enable site in nginx"
    echo "  --ssl,     -s    Setup SSL certificate with certbot"
    echo "  --all,     -a    Run all steps (conf + copy + enable + ssl)"
    echo "  --check,   -k    Check domain health (DNS, HTTP, HTTPS, SSL)"
    echo "  --remove,  -r    Remove site completely (webroot + config + SSL cert)"
    echo "  --help,    -h    Show this help"
    echo ""
    echo "Domain Options:"
    echo "  --domain=example.com, -d example.com   Specify domain to work with"
    echo "  (if not provided, you will be prompted to enter it)"
    echo ""
    echo "Examples:"
    echo "  $0 --all --domain=example.com     # Setup complete site"
    echo "  $0 -a -d example.com              # Same as above (short flags)"
    echo "  $0 --check --domain=example.com   # Verify site is working"
    echo "  $0 -k -d example.com              # Same as above (short flags)"
    echo "  $0 --all                          # Will prompt for domain"
    echo "  $0 -a                             # Same as above (short flag)"
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
    
    echo ""
    echo "🎉 SSL enabled for $domain!"
    echo ""
    echo "📁 Your website files go here:"
    echo "   Webroot: /var/www/$domain/"
    echo ""
    echo "   Quick test:"
    echo "   sudo bash -c 'echo \"<h1>Hello $domain! 🚀</h1>\" > /var/www/$domain/index.html'"
    echo ""
    echo "   Upload files:"
    echo "   sudo cp -r /path/to/your/website/* /var/www/$domain/"
    echo "   sudo chown -R www-data:www-data /var/www/$domain/"
    echo "   sudo chmod -R 755 /var/www/$domain/"
    echo ""
    echo "🌐 Visit: https://$domain"
    echo ""
}

remove_site() {
    local domain=$1
    local webroot="/var/www/$domain"
    local config_file="${domain}.conf"
    
    log_warn "⚠️  REMOVING SITE: $domain"
    echo ""
    echo "This will permanently delete:"
    echo "  - Website files: $webroot"
    echo "  - Nginx config: /etc/nginx/sites-available/$config_file"
    echo "  - Nginx symlink: /etc/nginx/sites-enabled/$config_file"
    echo "  - SSL certificate: /etc/letsencrypt/live/$domain"
    echo "  - Local config: $config_file"
    echo ""
    
    # Confirmation prompt
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Removal cancelled"
        exit 0
    fi
    
    log_info "Removing nginx configuration for $domain..."
    
    # Disable site (remove symlink)
    if [ -L "/etc/nginx/sites-enabled/$config_file" ]; then
        sudo rm "/etc/nginx/sites-enabled/$config_file"
        log_success "Disabled nginx site"
    fi
    
    # Remove config file
    if [ -f "/etc/nginx/sites-available/$config_file" ]; then
        sudo rm "/etc/nginx/sites-available/$config_file"
        log_success "Removed nginx config"
    fi
    
    # Remove local config file
    if [ -f "$config_file" ]; then
        rm "$config_file"
        log_success "Removed local config file"
    fi
    
    # Remove SSL certificate
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        log_info "Removing SSL certificate for $domain..."
        sudo certbot delete --cert-name "$domain" --non-interactive
        if [ $? -eq 0 ]; then
            log_success "Removed SSL certificate"
        else
            log_warn "Could not remove SSL certificate automatically"
        fi
    fi
    
    # Remove webroot directory
    if [ -d "$webroot" ]; then
        log_info "Removing website files at $webroot..."
        sudo rm -rf "$webroot"
        log_success "Removed website files"
    fi
    
    # Test and reload nginx
    if sudo nginx -t &> /dev/null; then
        sudo systemctl reload nginx
        log_success "Nginx configuration reloaded"
    else
        log_warn "Nginx configuration test failed - manual fix may be needed"
    fi
    
    echo ""
    log_success "🗑️  Site $domain completely removed!"
    echo ""
}

check_site() {
    local domain=$1
    local webroot="/var/www/$domain"
    local config_file="${domain}.conf"
    
    echo "🔍 CHECKING DOMAIN HEALTH: $domain"
    echo ""
    
    local issues=0
    
    # Check DNS resolution
    log_info "Checking DNS resolution..."
    if dig +short "$domain" &> /dev/null || nslookup "$domain" &> /dev/null; then
        local ip=$(dig +short "$domain" 2>/dev/null | head -1)
        if [ -n "$ip" ]; then
            log_success "DNS resolves to: $ip"
        else
            log_success "DNS resolution working"
        fi
    else
        log_error "DNS resolution failed"
        ((issues++))
    fi
    
    # Check www DNS resolution
    log_info "Checking www DNS resolution..."
    if dig +short "www.$domain" &> /dev/null || nslookup "www.$domain" &> /dev/null; then
        log_success "www.$domain DNS working"
    else
        log_warn "www.$domain DNS not configured"
    fi
    
    # Check nginx config exists
    log_info "Checking nginx configuration..."
    if [ -f "/etc/nginx/sites-available/$config_file" ]; then
        log_success "Nginx config exists"
        
        if [ -L "/etc/nginx/sites-enabled/$config_file" ]; then
            log_success "Nginx site is enabled"
        else
            log_error "Nginx site not enabled"
            ((issues++))
        fi
    else
        log_error "Nginx config missing"
        ((issues++))
    fi
    
    # Check webroot exists
    log_info "Checking webroot directory..."
    if [ -d "$webroot" ]; then
        log_success "Webroot exists: $webroot"
        
        if [ -f "$webroot/index.html" ]; then
            log_success "index.html found"
        else
            log_warn "No index.html found in webroot"
        fi
    else
        log_error "Webroot directory missing"
        ((issues++))
    fi
    
    # Check SSL certificate
    log_info "Checking SSL certificate..."
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        log_success "SSL certificate exists"
        
        # Check certificate expiry
        if command -v openssl &> /dev/null; then
            local expiry=$(sudo openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/cert.pem" 2>/dev/null | cut -d= -f2)
            if [ -n "$expiry" ]; then
                log_success "Certificate expires: $expiry"
            fi
        fi
    else
        log_warn "No SSL certificate found"
    fi
    
    # Check nginx service
    log_info "Checking nginx service..."
    if systemctl is-active --quiet nginx; then
        log_success "Nginx service is running"
    else
        log_error "Nginx service not running"
        ((issues++))
    fi
    
    # Check nginx config validity
    log_info "Testing nginx configuration..."
    if sudo nginx -t &> /dev/null; then
        log_success "Nginx configuration is valid"
    else
        log_error "Nginx configuration has errors"
        ((issues++))
    fi
    
    # Check HTTP response
    log_info "Testing HTTP connection..."
    if command -v curl &> /dev/null; then
        local http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$domain" --max-time 10 2>/dev/null)
        if [ "$http_status" = "301" ] || [ "$http_status" = "302" ]; then
            log_success "HTTP redirects properly (status: $http_status)"
        elif [ "$http_status" = "200" ]; then
            log_success "HTTP responds (status: $http_status)"
        else
            log_error "HTTP connection failed (status: $http_status)"
            ((issues++))
        fi
    else
        log_warn "curl not available - cannot test HTTP"
    fi
    
    # Check HTTPS response
    log_info "Testing HTTPS connection..."
    if command -v curl &> /dev/null; then
        local https_status=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain" --max-time 10 2>/dev/null)
        if [ "$https_status" = "200" ]; then
            log_success "HTTPS responds correctly (status: $https_status)"
        else
            log_error "HTTPS connection failed (status: $https_status)"
            ((issues++))
        fi
    else
        log_warn "curl not available - cannot test HTTPS"
    fi
    
    # Check SSL certificate validity via online test
    log_info "Testing SSL certificate validity..."
    if command -v curl &> /dev/null; then
        if curl -s --max-time 5 "https://$domain" > /dev/null 2>&1; then
            log_success "SSL certificate is valid and trusted"
        else
            log_warn "SSL certificate may have issues"
        fi
    fi
    
    echo ""
    echo "📊 HEALTH CHECK SUMMARY:"
    echo "========================"
    
    if [ $issues -eq 0 ]; then
        log_success "🎉 $domain is healthy! All checks passed."
        echo ""
        echo "🌐 URLs to test:"
        echo "   http://$domain (should redirect to HTTPS)"
        echo "   https://$domain (should work)"
        echo "   https://www.$domain (should redirect to non-www)"
    else
        log_error "❌ $domain has $issues issue(s) that need attention."
        echo ""
        echo "💡 Common fixes:"
        echo "   - DNS not pointing to server: Update A records"
        echo "   - Nginx not running: sudo systemctl start nginx"
        echo "   - Config errors: sudo nginx -t"
        echo "   - Missing SSL: $0 --ssl $domain"
    fi
    
    echo ""
}

get_domain_input() {
    echo ""
    echo "🌐 Enter domain name (e.g., example.com):"
    read -p "> " domain_input
    
    # Remove http:// or https:// if present
    domain_input=$(echo "$domain_input" | sed 's|https\?://||')
    # Remove trailing slash if present
    domain_input=$(echo "$domain_input" | sed 's|/$||')
    # Remove www. if present (we'll handle www separately)
    domain_input=$(echo "$domain_input" | sed 's|^www\.||')
    
    if [ -z "$domain_input" ]; then
        log_error "Domain cannot be empty"
        exit 1
    fi
    
    # Basic domain validation
    if [[ ! "$domain_input" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$ ]]; then
        log_error "Invalid domain format: $domain_input"
        exit 1
    fi
    
    echo "$domain_input"
}

# Parse arguments
FLAG=""
DOMAIN=""

# Check if no arguments or help requested
if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
    show_help
fi

# Parse all arguments
i=0
while [ $i -lt $# ]; do
    i=$((i + 1))
    arg=${!i}
    
    case $arg in
        --domain=*)
            DOMAIN="${arg#*=}"
            ;;
        -d)
            # Next argument should be domain
            i=$((i + 1))
            if [ $i -le $# ]; then
                DOMAIN=${!i}
            else
                log_error "-d flag requires domain argument"
                show_help
            fi
            ;;
        --conf|-c)
            if [ -n "$FLAG" ]; then
                log_error "Multiple action flags not allowed"
                show_help
            fi
            FLAG="--conf"
            ;;
        --copy|-p)
            if [ -n "$FLAG" ]; then
                log_error "Multiple action flags not allowed"
                show_help
            fi
            FLAG="--copy"
            ;;
        --enable|-e)
            if [ -n "$FLAG" ]; then
                log_error "Multiple action flags not allowed"
                show_help
            fi
            FLAG="--enable"
            ;;
        --ssl|-s)
            if [ -n "$FLAG" ]; then
                log_error "Multiple action flags not allowed"
                show_help
            fi
            FLAG="--ssl"
            ;;
        --all|-a)
            if [ -n "$FLAG" ]; then
                log_error "Multiple action flags not allowed"
                show_help
            fi
            FLAG="--all"
            ;;
        --check|-k)
            if [ -n "$FLAG" ]; then
                log_error "Multiple action flags not allowed"
                show_help
            fi
            FLAG="--check"
            ;;
        --remove|-r)
            if [ -n "$FLAG" ]; then
                log_error "Multiple action flags not allowed"
                show_help
            fi
            FLAG="--remove"
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown argument: $arg"
            show_help
            ;;
    esac
done

# Ensure we have an action flag
if [ -z "$FLAG" ]; then
    log_error "Action flag required (--all, --check, etc.)"
    show_help
fi

# Get domain if not provided
if [ -z "$DOMAIN" ]; then
    DOMAIN=$(get_domain_input)
fi

log_info "Processing domain: $DOMAIN"

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
        echo ""
        log_success "🎉 $DOMAIN is fully configured with nginx + SSL!"
        echo ""
        echo "📁 NEXT STEP: Add your website files"
        echo "   Webroot: /var/www/$DOMAIN/"
        echo ""
        echo "   Quick test:"
        echo "   sudo bash -c 'echo \"<h1>Hello World! 🚀</h1>\" > /var/www/$DOMAIN/index.html'"
        echo ""
        echo "   Upload files:"
        echo "   sudo cp -r /path/to/your/website/* /var/www/$DOMAIN/"
        echo "   sudo chown -R www-data:www-data /var/www/$DOMAIN/"
        echo "   sudo chmod -R 755 /var/www/$DOMAIN/"
        echo ""
        echo "🌐 Visit: https://$DOMAIN"
        echo ""
        ;;
    --check)
        check_site "$DOMAIN"
        ;;
    --remove)
        remove_site "$DOMAIN"
        ;;
    *)
        log_error "Unknown flag $FLAG"
        show_help
        ;;
esac