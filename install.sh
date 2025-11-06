#!/bin/bash

################################################################################
# Remnashop + Remnawave + Nginx Auto-Installer
# Simple, reliable, production-ready
################################################################################

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly INSTALL_DIR="/opt"
readonly REMNASHOP_DIR="${INSTALL_DIR}/remnashop"
readonly LOG_FILE="/var/log/remnashop-install.log"

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Simple logging
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; exit 1; }

# Checks
check_root() { [[ $(id -u) -eq 0 ]] || log_error "Run with sudo"; }
check_os() { 
    [[ -f /etc/os-release ]] || log_error "Cannot detect OS"
    source /etc/os-release
    [[ "$ID" == "ubuntu" ]] || log_error "Ubuntu required"
}

# Install Docker
install_docker() {
    command -v docker &>/dev/null && { log_success "Docker already installed"; return; }
    
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | bash >/dev/null 2>&1
    systemctl start docker && systemctl enable docker
    log_success "Docker installed"
}

# Install Docker Compose
install_docker_compose() {
    command -v docker-compose &>/dev/null && { log_success "Docker Compose already installed"; return; }
    
    log_info "Installing Docker Compose..."
    curl -fsSL "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
    log_success "Docker Compose installed"
}

# Install Nginx
install_nginx() {
    command -v nginx &>/dev/null && { log_success "Nginx already installed"; return; }
    
    log_info "Installing Nginx..."
    apt-get update -qq && apt-get install -y -qq nginx
    systemctl start nginx && systemctl enable nginx
    log_success "Nginx installed"
}

# Get user input
prompt_domain() {
    read -p "Domain (example: panel.fenixvpn.ru): " domain
    [[ -z "$domain" ]] && log_error "Domain cannot be empty"
    echo "$domain"
}

prompt_token() {
    read -p "Telegram Bot Token: " token
    [[ -z "$token" ]] && log_error "Token cannot be empty"
    echo "$token"
}

# Create .env
create_env() {
    local domain=$1
    local token=$2
    
    log_info "Creating .env file..."
    mkdir -p "$REMNASHOP_DIR"
    
    cat > "$REMNASHOP_DIR/.env" << EOF
APP_DOMAIN=$domain
APP_CRYPT_KEY=$(openssl rand -base64 32)
BOT_TOKEN=$token
BOT_SECRET_TOKEN=$(openssl rand -hex 64)
BOT_DEV_ID=0
BOT_SUPPORT_USERNAME=support
DATABASE_PASSWORD=$(openssl rand -hex 24)
DATABASE_USER=remnadb
DATABASE_NAME=remnashop
REDIS_PASSWORD=$(openssl rand -hex 24)
REMNAWAVE_HOST=remnawave
REMNAWAVE_TOKEN=your_token_here
REMNAWAVE_WEBHOOK_SECRET=your_secret_here
LOG_LEVEL=info
TZ=UTC
EOF
    
    log_success ".env file created"
}

# Create docker-compose
create_docker_compose() {
    log_info "Creating docker-compose.yml..."
    
    mkdir -p "$REMNASHOP_DIR/assets/banners"
    mkdir -p "$REMNASHOP_DIR/assets/translations"
    
    cat > "$REMNASHOP_DIR/docker-compose.yml" << 'EOF'
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

volumes:
  postgres_data:
  redis_data:
EOF
    
    log_success "docker-compose.yml created"
}

# Setup Nginx (HTTP only for now)
setup_nginx() {
    local domain=$1
    
    log_info "Configuring Nginx..."
    
    cat > /etc/nginx/sites-available/remnashop << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
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
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/remnashop /etc/nginx/sites-enabled/remnashop
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t >/dev/null 2>&1 && systemctl reload nginx
    log_success "Nginx configured"
}

# Deploy containers
deploy() {
    log_info "Starting Docker containers..."
    cd "$REMNASHOP_DIR"
    docker-compose up -d
    sleep 3
    docker-compose ps
    log_success "Containers running"
}

# Main
main() {
    clear
    echo -e "${GREEN}"
    cat << 'BANNER'
╔════════════════════════════════════════════════════════════════╗
║     Remnashop Auto-Installer - Simple & Reliable             ║
║     Ready for production deployment                           ║
╚════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}\n"
    
    # Checks
    log_info "System checks"
    check_root
    check_os
    log_success "System OK\n"
    
    # Installation
    log_info "Installation"
    apt-get update -qq
    apt-get install -y -qq curl certbot python3-certbot-nginx
    install_docker
    install_docker_compose
    install_nginx
    echo ""
    
    # Configuration
    log_info "Configuration"
    local domain=$(prompt_domain)
    local token=$(prompt_token)
    create_env "$domain" "$token"
    create_docker_compose
    echo ""
    
    # Nginx setup
    log_info "Web server"
    setup_nginx "$domain"
    echo ""
    
    # Deploy
    log_info "Deployment"
    deploy
    echo ""
    
    # Summary
    echo -e "${GREEN}"
    cat << SUMMARY
╔════════════════════════════════════════════════════════════════╗
║                   INSTALLATION COMPLETE                       ║
╚════════════════════════════════════════════════════════════════╝

Your setup:
  Directory: $REMNASHOP_DIR
  Domain: $domain
  Status: Running (HTTP)

IMPORTANT - GET SSL CERTIFICATE:

1. Stop Nginx:
   sudo systemctl stop nginx

2. Get certificate:
   sudo certbot certonly --standalone \\
     -d $domain \\
     -d www.$domain

3. Start Nginx:
   sudo systemctl start nginx

4. Update Nginx config:
   sudo nano /etc/nginx/sites-available/remnashop
   (Add SSL directives, see below)

5. Reload Nginx:
   sudo systemctl reload nginx

SAMPLE HTTPS CONFIG (add to /etc/nginx/sites-available/remnashop):

server {
    listen 443 ssl http2;
    server_name $domain www.$domain;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

MANAGE:
  Status: cd $REMNASHOP_DIR && docker-compose ps
  Logs: docker-compose logs -f
  Stop: docker-compose down
  Start: docker-compose up -d

CONFIGURE:
  Edit: nano $REMNASHOP_DIR/.env
  (Add REMNAWAVE_TOKEN and REMNAWAVE_WEBHOOK_SECRET)
  Restart: docker-compose restart

SUMMARY
    echo -e "${NC}"
}

main "$@"
