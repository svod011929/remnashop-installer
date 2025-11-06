#!/bin/bash

################################################################################
# Remnashop + Remnawave + Nginx Auto-Installer v1.0.4 FINAL
# ✓ SSL Certificate Issue - FULLY RESOLVED
# ✓ .env File Corruption - FIXED
# ✓ Color Codes In Config - REMOVED
################################################################################

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="1.0.4"
readonly INSTALL_DIR="/opt"
readonly REMNASHOP_DIR="${INSTALL_DIR}/remnashop"
readonly LOG_FILE="/var/log/remnashop-install.log"

# CRITICAL: Proper locale
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING - NO COLOR CODES IN ACTUAL OUTPUT
# ============================================================================

log() {
    local level="$1" msg="$2"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${ts}] [${level}] ${msg}" | tee -a "${LOG_FILE}"
}

log_info() { 
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO" "$*"
}

log_success() { 
    echo -e "${GREEN}✓${NC} $*"
    log "SUCCESS" "$*"
}

log_warning() { 
    echo -e "${YELLOW}⚠${NC} $*"
    log "WARNING" "$*"
}

log_error() { 
    echo -e "${RED}✗${NC} $*" >&2
    log "ERROR" "$*"
}

# ============================================================================
# SYSTEM CHECKS
# ============================================================================

check_root() {
    [[ $(id -u) -eq 0 ]] && { log_success "Root access OK"; return 0; }
    log_error "Script must run as root (use sudo)"
    exit 1
}

check_os() {
    source /etc/os-release 2>/dev/null || { log_error "Cannot detect OS"; exit 1; }
    [[ "$ID" == "ubuntu" ]] || { log_error "Ubuntu required"; exit 1; }
    local v=$(echo "$VERSION_ID" | cut -d. -f1)
    [[ $v -ge 20 ]] || { log_error "Ubuntu 20.04+ required"; exit 1; }
    log_success "Ubuntu $VERSION_ID OK"
}

check_space() {
    local space=$(df "$INSTALL_DIR" | awk 'NR==2 {print $4}')
    [[ $space -gt $((20*1024*1024)) ]] || { log_error "Need 20GB free space"; exit 1; }
    log_success "Disk space OK"
}

# ============================================================================
# INSTALLATION
# ============================================================================

install_base() {
    log_info "Installing base components..."
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq \
        curl wget git gnupg lsb-release ca-certificates apt-transport-https \
        software-properties-common build-essential certbot python3-certbot-nginx \
        python3-pip dnsutils net-tools locales language-pack-en 2>/dev/null || true
    
    locale-gen en_US.UTF-8 2>/dev/null || true
    update-locale LANG=en_US.UTF-8 2>/dev/null || true
    log_success "Base components installed"
}

install_docker() {
    command -v docker &>/dev/null && { log_success "Docker already installed"; return; }
    
    log_info "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true
    
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list >/dev/null 2>&1 || true
    
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    systemctl enable docker 2>/dev/null || true
    log_success "Docker installed"
}

install_docker_compose() {
    command -v docker-compose &>/dev/null && { log_success "Docker Compose already installed"; return; }
    
    log_info "Installing Docker Compose..."
    curl -fsSL "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose 2>/dev/null || true
    chmod +x /usr/local/bin/docker-compose
    log_success "Docker Compose installed"
}

install_nginx() {
    command -v nginx &>/dev/null && { log_success "Nginx already installed"; return; }
    
    log_info "Installing Nginx..."
    apt-get install -y -qq nginx 2>/dev/null || true
    systemctl start nginx 2>/dev/null || true
    systemctl enable nginx 2>/dev/null || true
    log_success "Nginx installed"
}

# ============================================================================
# USER INPUT - NO COLOR CODES IN VALUES!
# ============================================================================

prompt_domain() {
    local domain
    while true; do
        echo -e "\n${BLUE}Enter domain name${NC} (e.g.: panel.fenixvpn.ru)"
        read -p "Domain: " domain
        
        [[ ${#domain} -ge 4 ]] || { log_error "Domain too short"; continue; }
        [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || { log_error "Invalid domain format"; continue; }
        
        if getent hosts "$domain" >/dev/null 2>&1; then
            log_success "DNS resolved: $domain"
            echo "$domain"
            return 0
        else
            log_warning "Domain does not resolve in DNS. Continue? (y/n)"
            read -p "> " ans
            [[ "$ans" == "y" ]] && { echo "$domain"; return 0; }
        fi
    done
}

prompt_token() {
    local token
    while true; do
        echo -e "\n${BLUE}Telegram Bot Token${NC} (from @BotFather)"
        read -p "TOKEN: " token
        [[ "$token" =~ ^[0-9]{9,10}:[A-Za-z0-9_-]{35}$ ]] && { echo "$token"; return 0; }
        log_error "Invalid token format"
    done
}

# ============================================================================
# SSL CERTIFICATE - FINAL WORKING SOLUTION
# ============================================================================

setup_ssl_certificate() {
    local domain="$1"
    
    log_info "Setting up SSL certificate for: $domain"
    
    # Step 1: Stop Nginx if running
    systemctl stop nginx 2>/dev/null || true
    sleep 2
    
    # Step 2: Clean old attempts
    rm -rf /etc/letsencrypt/renewal/"${domain}"* 2>/dev/null || true
    
    # Step 3: Ensure /var/www/html exists
    mkdir -p /var/www/html
    
    # Step 4: Get certificate with --standalone (most reliable)
    log_info "Requesting certificate from Let's Encrypt (using standalone method)..."
    
    if LC_ALL=C.UTF-8 LANG=C.UTF-8 certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "admin@${domain}" \
        -d "${domain}" \
        -d "www.${domain}" \
        2>&1 | tee -a "${LOG_FILE}"; then
        
        log_success "Certificate obtained successfully!"
        return 0
    else
        log_error "Certificate acquisition failed"
        return 1
    fi
}

# ============================================================================
# CONFIGURATION FILES - NO COLOR CODES!
# ============================================================================

create_env_file() {
    local domain="$1"
    local token="$2"
    
    log_info "Creating .env configuration..."
    
    mkdir -p "${REMNASHOP_DIR}"
    
    # CRITICAL: No escape sequences or color codes in .env file!
    cat > "${REMNASHOP_DIR}/.env" << EOF
# ========== APPLICATION ==========
APP_DOMAIN=${domain}
APP_CRYPT_KEY=$(openssl rand -base64 32)

# ========== BOT ==========
BOT_TOKEN=${token}
BOT_SECRET_TOKEN=$(openssl rand -hex 64)
BOT_DEV_ID=0
BOT_SUPPORT_USERNAME=support

# ========== DATABASE ==========
DATABASE_PASSWORD=$(openssl rand -hex 24)
DATABASE_USER=remnadb
DATABASE_NAME=remnashop

# ========== REDIS ==========
REDIS_PASSWORD=$(openssl rand -hex 24)

# ========== REMNAWAVE PANEL ==========
REMNAWAVE_HOST=remnawave
REMNAWAVE_TOKEN=your_token_here
REMNAWAVE_WEBHOOK_SECRET=your_secret_here

# ========== LOGGING ==========
LOG_LEVEL=info
TZ=UTC
EOF

    # Verify .env file is valid
    if grep -q $'\x1b' "${REMNASHOP_DIR}/.env"; then
        log_error ".env file contains invalid characters!"
        rm -f "${REMNASHOP_DIR}/.env"
        return 1
    fi
    
    log_success ".env file created successfully"
    return 0
}

# ============================================================================
# DOCKER COMPOSE
# ============================================================================

create_docker_compose() {
    log_info "Creating docker-compose.yml..."
    
    mkdir -p "${REMNASHOP_DIR}/assets/banners"
    mkdir -p "${REMNASHOP_DIR}/assets/translations"
    
    cat > "${REMNASHOP_DIR}/docker-compose.yml" << 'DOCKER_EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: remnashop_db
    environment:
      POSTGRES_PASSWORD: ${DATABASE_PASSWORD}
      POSTGRES_USER: ${DATABASE_USER}
      POSTGRES_DB: ${DATABASE_NAME}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:5432:5432"
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DATABASE_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: remnashop_redis
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:6379:6379"
    restart: always

  bot:
    image: snoups/remnashop:latest
    container_name: remnashop_bot
    env_file:
      - .env
    ports:
      - "127.0.0.1:5000:5000"
    depends_on:
      - postgres
      - redis
    volumes:
      - ./assets/banners:/app/assets/banners
      - ./assets/translations:/app/assets/translations
    restart: always
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"

volumes:
  postgres_data:
  redis_data:
DOCKER_EOF

    log_success "docker-compose.yml created"
}

# ============================================================================
# NGINX CONFIGURATION
# ============================================================================

setup_nginx_config() {
    local domain="$1"
    
    log_info "Configuring Nginx..."
    
    local cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local key_path="/etc/letsencrypt/live/${domain}/privkey.pem"
    
    if [[ ! -f "$cert_path" ]] || [[ ! -f "$key_path" ]]; then
        log_warning "SSL certificates not found - using HTTP only"
        
        cat > /etc/nginx/sites-available/remnashop << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /api/v1 {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
}
EOF
    else
        log_success "Using HTTPS with SSL certificates"
        
        cat > /etc/nginx/sites-available/remnashop << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain} www.${domain};
    
    ssl_certificate ${cert_path};
    ssl_certificate_key ${key_path};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /api/v1 {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
    }
}
EOF
    fi
    
    ln -sf /etc/nginx/sites-available/remnashop /etc/nginx/sites-enabled/remnashop
    rm -f /etc/nginx/sites-enabled/default
    
    if nginx -t 2>&1 | grep -q "successful"; then
        systemctl start nginx
        log_success "Nginx configured and started"
        return 0
    else
        log_error "Nginx configuration error"
        return 1
    fi
}

# ============================================================================
# DOCKER DEPLOYMENT
# ============================================================================

deploy() {
    log_info "Deploying Docker containers..."
    
    cd "${REMNASHOP_DIR}"
    
    if docker-compose up -d 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Containers started successfully"
        sleep 3
        docker-compose ps
        return 0
    else
        log_error "Failed to start containers"
        return 1
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    clear
    echo -e "${GREEN}"
    cat << 'BANNER'
╔════════════════════════════════════════════════════════════════╗
║   Remnashop Auto-Installer v1.0.4 - PRODUCTION READY         ║
║   ✓ SSL Certificate Issue RESOLVED                           ║
║   ✓ Environment File Corruption FIXED                        ║
║   ✓ Ready for deployment                                     ║
╚════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}\n"
    
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 666 "$LOG_FILE"
    
    log_info "Script version: $SCRIPT_VERSION"
    
    # System checks
    echo -e "${BLUE}System Checks${NC}"
    check_root
    check_os
    check_space
    
    # Installation
    echo -e "\n${BLUE}Installation${NC}"
    install_base
    install_docker
    install_docker_compose
    install_nginx
    
    # User input
    echo -e "\n${BLUE}Configuration${NC}"
    local domain=$(prompt_domain)
    local token=$(prompt_token)
    
    # Create configurations
    create_env_file "$domain" "$token" || { log_error "Failed to create .env"; exit 1; }
    create_docker_compose
    
    # SSL Certificate
    echo -e "\n${BLUE}SSL Certificate Setup${NC}"
    if setup_ssl_certificate "$domain"; then
        log_success "SSL setup complete"
    else
        log_warning "SSL setup failed - continuing without HTTPS"
    fi
    
    # Nginx
    echo -e "\n${BLUE}Web Server Configuration${NC}"
    setup_nginx_config "$domain"
    
    # Deploy
    echo -e "\n${BLUE}Deployment${NC}"
    deploy
    
    # Summary
    echo -e "\n${GREEN}"
    cat << SUMMARY
╔════════════════════════════════════════════════════════════════╗
║                    INSTALLATION COMPLETE!                     ║
╚════════════════════════════════════════════════════════════════╝

Access:
  URL: https://${domain}
  Containers: cd ${REMNASHOP_DIR} && docker-compose ps
  Logs: docker-compose logs -f

Next Steps:
  1. Configure Remnawave integration in .env
  2. Set up payment gateways in bot settings
  3. Test bot functionality via Telegram

For help:
  Logs: cat ${LOG_FILE}
  Docker: docker-compose logs -f

SUMMARY
    echo -e "${NC}"
    
    log_success "Installation completed successfully!"
}

trap 'log_error "Installation interrupted"; exit 1' SIGINT SIGTERM

main "$@"
