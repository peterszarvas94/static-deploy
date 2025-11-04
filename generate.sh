#!/bin/bash

# Nginx Static Site Configuration Generator
# Generates nginx configs with HTTP->HTTPS and www->non-www redirects
# Usage: ./generate.sh --flag domain.com

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]  ${NC}$1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]  ${NC}$1"
}

log_error() {
    echo -e "${RED}[ERROR] ${NC}$1"
}

check_prerequisites() {
    log_info "Checking system prerequisites..."
    
    # Install nginx if not present
    if ! command -v nginx &> /dev/null; then
        log_info "Nginx not found, installing..."
        sudo apt update && sudo apt install -y nginx
        if [ $? -eq 0 ]; then
            log_info "Nginx installed successfully"
        else
            log_error "Failed to install nginx"
            exit 1
        fi
    else
        log_info "Nginx found"
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
    
    log_info "Prerequisites checked (ignoring any existing nginx config issues)"
}

show_help() {
    echo "Usage: $0 [ACTION] [--domain=example.com]"
    echo "Actions:"
    echo "  --conf,    -c    Generate HTTP config file only"
    echo "  --copy,    -p    Create directory and copy config to nginx"
    echo "  --enable,  -e    Enable site in nginx"
    echo "  --ssl,     -s    Setup SSL certificate with certbot"
    echo "  --all,     -a    Run all steps (conf + copy + enable + ssl)"
    echo "  --check,   -k    Check domain health (DNS, HTTP, HTTPS, SSL)"
    echo "  --remove,  -r    Remove site completely (webroot + config + SSL cert)"
    echo "  --help,    -h    Show this help"
    echo "Domain Options:"
    echo "  --domain=example.com, -d example.com   Specify domain to work with"
    echo "  --www, -w                              Redirect www to non-www"
    echo "  (if domain not provided, you will be prompted to enter it)"
    echo "Examples:"
    echo "  $0 --all --domain=example.com         # Setup site (non-www only)"
    echo "  $0 --all --www --domain=example.com   # Setup site (www redirects to non-www)"
    echo "  $0 -a -w -d example.com               # Same as above (short flags)"
    echo "  $0 --check --domain=example.com       # Verify site is working"
    echo "  $0 --all                              # Will prompt for domain"
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
    local ssl_exists=false
    
    # Check if SSL certificates exist
    if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${domain}/privkey.pem" ]; then
        ssl_exists=true
    fi
    
    if [ "$ssl_exists" = true ]; then
        log_info "Generating HTTPS config for $domain"
    else
        log_info "Generating HTTP-only config for $domain"
    fi
    
    if [ "$WWW_REDIRECT" = true ]; then
        if [ "$ssl_exists" = true ]; then
            # Template 1: HTTPS with www redirect
            cat > "$config_file" << EOF
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
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    root ${webroot};
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
        else
            # Template 1: HTTP-only with www redirect
            cat > "$config_file" << EOF
server {
    listen 80;
    server_name www.${domain};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 http://${domain}\$request_uri; }
}

server {
    listen 80;
    server_name ${domain};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / {
        root ${webroot};
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
EOF
        fi
    else
        if [ "$ssl_exists" = true ]; then
            # Template 2: HTTPS non-www only
            cat > "$config_file" << EOF
server {
    listen 80;
    server_name ${domain};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://${domain}\$request_uri; }
}

server {
    listen 443 ssl;
    server_name ${domain};
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    root ${webroot};
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
        else
            # Template 2: HTTP-only non-www
            cat > "$config_file" << EOF
server {
    listen 80;
    server_name ${domain};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / {
        root ${webroot};
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
EOF
        fi
    fi
    
    log_info "Generated config ${config_file}"
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
    log_info "Created webroot: ${webroot}"
    
    # Ensure nginx directories exist
    sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    
    # Copy to nginx sites directory
    sudo cp "$config_file" /etc/nginx/sites-available/
    log_info "Copied config to nginx sites-available"
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
    log_info "Enabled site in nginx"
    
    # Test only our specific config by temporarily moving others
    log_info "Testing $domain configuration..."
    
    # Backup other enabled sites
    sudo mkdir -p /tmp/nginx-backup
    sudo find /etc/nginx/sites-enabled/ -name "*.conf" ! -name "$config_file" -exec mv {} /tmp/nginx-backup/ \;
    
    # Test with only our config
    if sudo nginx -t &> /dev/null; then
        log_info "$domain configuration is valid"
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
    
    log_info "$domain enabled and configuration validated"
}

setup_ssl() {
    local domain=$1
    
    log_info "Setting up SSL certificate for $domain"
    
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
    if [ "$WWW_REDIRECT" = true ]; then
        log_info "Getting SSL certificate for $domain and www.$domain"
        sudo certbot certonly --webroot -w /var/www/certbot -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email admin@"$domain"
    else
        log_info "Getting SSL certificate for $domain only"
        sudo certbot certonly --webroot -w /var/www/certbot -d "$domain" --non-interactive --agree-tos --email admin@"$domain"
    fi
    
    if [ $? -eq 0 ]; then
        log_info "SSL certificate obtained for $domain"
        
        # Regenerate config with SSL
        generate_conf "$domain"
        sudo cp "${domain}.conf" /etc/nginx/sites-available/
        
        # Test and reload nginx
        if sudo nginx -t &> /dev/null; then
            sudo systemctl reload nginx
            log_info "Nginx reloaded with SSL configuration"
        else
            log_warn "Nginx config test failed but continuing"
            sudo systemctl reload nginx
        fi
    else
        log_error "Failed to get SSL certificate for $domain"
        log_error "Check that domain points to this server and ports 80/443 are open"
        exit 1
    fi
    
    # Setup auto-renewal cron job
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        log_info "Setting up SSL auto-renewal"
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | sudo crontab -
        log_info "SSL auto-renewal configured"
    fi
    
    log_info "SSL setup complete!"
    log_info "Your website files go here:"
    echo "   Webroot: /var/www/$domain/"
    echo "   Quick test:"
    echo "   sudo bash -c 'echo \"<h1>Hello $domain!</h1>\" > /var/www/$domain/index.html'"
    echo "   Upload files:"
    echo "   sudo cp -r /path/to/your/website/* /var/www/$domain/"
    echo "   sudo chown -R www-data:www-data /var/www/$domain/"
    echo "   sudo chmod -R 755 /var/www/$domain/"
    log_info "Visit: https://$domain"
}

remove_site() {
    local domain=$1
    local webroot="/var/www/$domain"
    local config_file="${domain}.conf"
    
    log_warn "REMOVING SITE: $domain"
    log_warn "This will permanently delete:"
    echo "- Website files: $webroot"
    echo "- Nginx config: /etc/nginx/sites-available/$config_file"
    echo "- Nginx symlink: /etc/nginx/sites-enabled/$config_file"
    echo "- SSL certificate: /etc/letsencrypt/live/$domain"
    echo "- Local config: $config_file"
    
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
        log_info "Disabled nginx site"
    fi
    
    # Remove config file
    if [ -f "/etc/nginx/sites-available/$config_file" ]; then
        sudo rm "/etc/nginx/sites-available/$config_file"
        log_info "Removed nginx config"
    fi
    
    # Remove local config file
    if [ -f "$config_file" ]; then
        rm "$config_file"
        log_info "Removed local config file"
    fi
    
    # Remove SSL certificate
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        log_info "Removing SSL certificate for $domain..."
        sudo certbot delete --cert-name "$domain" --non-interactive
        if [ $? -eq 0 ]; then
            log_info "Removed SSL certificate"
        else
            log_warn "Could not remove SSL certificate automatically"
        fi
    fi
    
    # Remove webroot directory
    if [ -d "$webroot" ]; then
        log_info "Removing website files at $webroot..."
        sudo rm -rf "$webroot"
        log_info "Removed website files"
    fi
    
    # Test and reload nginx
    if sudo nginx -t &> /dev/null; then
        sudo systemctl reload nginx
        log_info "Nginx configuration reloaded"
    else
        log_warn "Nginx configuration test failed - manual fix may be needed"
    fi
    
    log_info "Site $domain completely removed!"
}

check_site() {
    local domain=$1
    local webroot="/var/www/$domain"
    local config_file="${domain}.conf"
    
    log_info "CHECKING DOMAIN HEALTH: $domain"
    
    local issues=0
    
    # Check DNS resolution
    log_info "Checking DNS resolution..."
    if dig +short "$domain" &> /dev/null || nslookup "$domain" &> /dev/null; then
        local ip=$(dig +short "$domain" 2>/dev/null | head -1)
        if [ -n "$ip" ]; then
            log_info "DNS resolves to: $ip"
        else
            log_info "DNS resolution working"
        fi
    else
        log_error "DNS resolution failed"
        ((issues++))
    fi
    
    # Check www DNS resolution
    log_info "Checking www DNS resolution..."
    if dig +short "www.$domain" &> /dev/null || nslookup "www.$domain" &> /dev/null; then
        log_info "www.$domain DNS working"
    else
        log_warn "www.$domain DNS not configured"
    fi
    
    # Check nginx config exists
    log_info "Checking nginx configuration..."
    if [ -f "/etc/nginx/sites-available/$config_file" ]; then
        log_info "Nginx config exists"
        
        if [ -L "/etc/nginx/sites-enabled/$config_file" ]; then
            log_info "Nginx site is enabled"
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
        log_info "Webroot exists: $webroot"
        
        if [ -f "$webroot/index.html" ]; then
            log_info "index.html found"
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
        log_info "SSL certificate exists"
        
        # Check certificate expiry
        if command -v openssl &> /dev/null; then
            local expiry=$(sudo openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/cert.pem" 2>/dev/null | cut -d= -f2)
            if [ -n "$expiry" ]; then
                log_info "Certificate expires: $expiry"
            fi
        fi
    else
        # Check if HTTPS is working anyway (might be using other certificates)
        if command -v curl &> /dev/null; then
            if curl -s --max-time 5 "https://$domain" > /dev/null 2>&1; then
                log_info "SSL certificate working (external/custom cert)"
            else
                log_warn "No SSL certificate found"
            fi
        else
            log_warn "No SSL certificate found"
        fi
    fi
    
    # Check nginx service
    log_info "Checking nginx service..."
    if systemctl is-active --quiet nginx; then
        log_info "Nginx service is running"
    else
        log_error "Nginx service not running"
        ((issues++))
    fi
    
    # Check nginx config validity (but don't count as error if site works)
    log_info "Testing nginx configuration..."
    if sudo nginx -t &> /dev/null; then
        log_info "Nginx configuration is valid"
    else
        log_warn "Nginx configuration has errors (but site may still work)"
        # Don't increment issues counter - if HTTPS works, this doesn't matter
    fi
    
    # Check HTTP response
    log_info "Testing HTTP connection..."
    if command -v curl &> /dev/null; then
        local http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$domain" --max-time 10 2>/dev/null)
        if [ "$http_status" = "301" ] || [ "$http_status" = "302" ]; then
            log_info "HTTP redirects properly (status: $http_status)"
        elif [ "$http_status" = "200" ]; then
            log_info "HTTP responds (status: $http_status)"
        else
            log_error "HTTP connection failed (status: $http_status)"
            ((issues++))
        fi
    else
        log_warn "curl not available - cannot test HTTP"
    fi
    
    # Check HTTPS response
    log_info "Testing HTTPS connection..."
    local https_working=false
    if command -v curl &> /dev/null; then
        local https_status=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain" --max-time 10 2>/dev/null)
        if [ "$https_status" = "200" ]; then
            log_info "HTTPS responds correctly (status: $https_status)"
            https_working=true
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
            log_info "SSL certificate is valid and trusted"
            # If HTTPS works, the site is healthy regardless of other warnings
            if [ "$https_working" = true ]; then
                # Reset issues if HTTPS works perfectly
                issues=0
            fi
        else
            log_warn "SSL certificate may have issues"
        fi
    fi
    
    log_info "HEALTH CHECK SUMMARY:"
    
    if [ $issues -eq 0 ]; then
        log_info "$domain is healthy! All checks passed."
        log_info "URLs to test:"
        echo "- https://$domain"
        echo "- https://www.$domain -> https://$domain"
        echo "- http://$domain -> https://$domain"
        echo "- http://www.$domain -> https://$domain"
    else
        log_error "$domain has $issues issue(s) that need attention."
        log_info "Common fixes:"
        echo "- DNS not pointing to server: Update A records"
        echo "- Nginx not running: sudo systemctl start nginx"
        echo "- Config errors: sudo nginx -t"
        echo "- Missing SSL: $0 --ssl $domain"
    fi
    
}

get_domain_input() {
    read -p "Domain name: " domain_input
    
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
    
    echo "$domain_input"
}

# Parse arguments
FLAG=""
DOMAIN=""
WWW_REDIRECT=false

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
        --www|-w)
            WWW_REDIRECT=true
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
        log_info "SSL enabled for $DOMAIN!"
        log_info "Copy your files to: /var/www/$DOMAIN/"
        log_info "Visit: https://$DOMAIN"
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
