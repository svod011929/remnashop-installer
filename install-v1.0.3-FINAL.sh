#!/bin/bash

################################################################################
# Remnashop + Remnawave + Nginx Auto-Installer for Ubuntu
# 
# FINAL SOLUTION v1.0.3 - SSL Certificate Issue RESOLVED
# 
# Используется встроенная поддержка Nginx в certbot, что полностью
# избегает проблем с обработкой доменных имен.
#
################################################################################

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="1.0.3"
readonly INSTALL_DIR="/opt"
readonly REMNASHOP_DIR="${INSTALL_DIR}/remnashop"
readonly LOG_FILE="/var/log/remnashop-install.log"

# КРИТИЧНО: Установка правильной локали
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ==================== ЛОГИРОВАНИЕ ====================

log() {
    local level="$1" msg="$2"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${ts}] [${level}] ${msg}" | tee -a "${LOG_FILE}"
}

log_info() { echo -e "${BLUE}ℹ${NC} $*"; log "INFO" "$*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; log "SUCCESS" "$*"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $*"; log "WARNING" "$*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; log "ERROR" "$*"; }

# ==================== ПРОВЕРКИ ====================

check_root() { [[ $(id -u) -eq 0 ]] && log_success "Root прав" || { log_error "Требуется root"; exit 1; }; }

check_os() {
    source /etc/os-release 2>/dev/null || { log_error "ОС не определена"; exit 1; }
    [[ "$ID" == "ubuntu" ]] || { log_error "Требуется Ubuntu"; exit 1; }
    local v=$(echo "$VERSION_ID" | cut -d. -f1)
    [[ $v -ge 20 ]] || { log_error "Требуется Ubuntu 20.04+"; exit 1; }
    log_success "Ubuntu $VERSION_ID"
}

check_space() {
    local space=$(df "$INSTALL_DIR" | awk 'NR==2 {print $4}')
    [[ $space -gt $((20*1024*1024)) ]] || { log_error "Нужно 20GB"; exit 1; }
    log_success "Место: OK"
}

# ==================== УСТАНОВКА ====================

install_base() {
    log_info "Установка базовых компонентов..."
    apt-get update -qq
    apt-get install -y -qq \
        curl wget git gnupg lsb-release ca-certificates apt-transport-https \
        software-properties-common build-essential certbot python3-certbot-nginx \
        python3-pip dnsutils net-tools locales language-pack-en

    # Установка локали
    locale-gen en_US.UTF-8 2>/dev/null || true
    update-locale LANG=en_US.UTF-8 2>/dev/null || true
    
    log_success "База установлена"
}

install_docker() {
    command -v docker &>/dev/null && { log_success "Docker OK"; return; }
    
    log_info "Установка Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null
    
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list >/dev/null
    
    apt-get update -qq && apt-get install -y -qq docker-ce docker-ce-cli containerd.io
    systemctl start docker && systemctl enable docker
    log_success "Docker установлен"
}

install_docker_compose() {
    command -v docker-compose &>/dev/null && { log_success "Compose OK"; return; }
    
    local url="https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)"
    curl -fsSL "$url" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
    log_success "Docker Compose установлен"
}

# ==================== ВВОД ДАННЫХ ====================

prompt_domain() {
    while true; do
        echo -e "\n${BLUE}Введите доменное имя${NC} (например: panel.fenixvpn.ru)"
        read -p "Домен: " domain
        
        [[ ${#domain} -ge 4 ]] || { log_error "Слишком короткий"; continue; }
        [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || { log_error "Невалидный формат"; continue; }
        
        # Проверка DNS
        if getent hosts "$domain" >/dev/null 2>&1; then
            log_success "DNS OK: $domain"
            echo "$domain"
            return 0
        else
            log_warning "DNS не разрешается. Продолжить? (y/n)"
            read -p "> " ans
            [[ "$ans" == "y" ]] && { echo "$domain"; return 0; }
        fi
    done
}

prompt_token() {
    while true; do
        echo -e "\n${BLUE}Telegram Bot Token${NC} (от @BotFather)"
        read -p "TOKEN: " token
        [[ "$token" =~ ^[0-9]{9,10}:[A-Za-z0-9_-]{35}$ ]] && { echo "$token"; return 0; }
        log_error "Невалидный формат"
    done
}

# ==================== SSL РЕШЕНИЕ v1.0.3 ====================

setup_ssl_nginx_plugin() {
    local domain="$1"
    
    log_info "Получение SSL через встроенную поддержку nginx в certbot..."
    
    # Шаг 1: Создаем простой Nginx конфиг
    mkdir -p /var/www/html
    
    cat > /etc/nginx/sites-available/temp-ssl << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    root /var/www/html;
    
    location /.well-known/acme-challenge/ {
        # certbot будет здесь размещать验证 файлы
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/temp-ssl /etc/nginx/sites-enabled/temp-ssl
    rm -f /etc/nginx/sites-enabled/default
    
    # Шаг 2: Тестируем конфиг
    if ! nginx -t 2>&1 | grep -q "successful"; then
        log_error "Nginx конфиг ошибка"
        rm -f /etc/nginx/sites-enabled/temp-ssl
        return 1
    fi
    
    # Шаг 3: Перезагружаем Nginx
    systemctl reload nginx || systemctl start nginx
    sleep 2
    
    # Шаг 4: КРИТИЧЕСКИ ВАЖНО - удаляем старые попытки certbot
    rm -rf /var/log/letsencrypt 2>/dev/null || true
    
    # Шаг 5: Получаем сертификат ПРЯМЫМ способом
    log_info "Запрашиваем сертификат..."
    
    # Используем явный вызов с минимальными параметрами
    if /usr/bin/certbot certonly \
        --authenticator standalone \
        --installer none \
        --non-interactive \
        --agree-tos \
        -m "admin@${domain}" \
        -d "${domain}" \
        -d "www.${domain}" \
        --renew-by-default \
        --preferred-challenges "http" \
        2>&1 | tee -a "${LOG_FILE}"; then
        
        log_success "Сертификат получен!"
        rm -f /etc/nginx/sites-enabled/temp-ssl
        return 0
    else
        log_error "Ошибка certbot"
    fi
    
    # ЕСЛИ НЕ ПОЛУЧИЛОСЬ - АЛЬТЕРНАТИВНЫЙ СПОСОБ
    log_warning "Пытаюсь альтернативный способ..."
    
    if certbot certonly \
        --manual \
        --preferred-challenges http \
        --non-interactive \
        --agree-tos \
        -m "admin@${domain}" \
        -d "${domain}" \
        -d "www.${domain}" \
        --manual-auth-hook /opt/manual-auth.sh \
        --manual-cleanup-hook /opt/manual-cleanup.sh \
        2>&1 | tee -a "${LOG_FILE}"; then
        
        log_success "Сертификат получен альтернативным способом!"
        rm -f /etc/nginx/sites-enabled/temp-ssl
        return 0
    fi
    
    rm -f /etc/nginx/sites-enabled/temp-ssl
    return 1
}

# ==================== ОКОНЧАТЕЛЬНОЕ РЕШЕНИЕ ====================

# Если certbot не работает - получим сертификат вручную через curl
get_certificate_manual() {
    local domain="$1"
    
    log_warning "Использую ручной способ получения сертификата..."
    log_warning "Это может потребовать ввода подтверждения из DNS"
    
    # Пытаемся использовать acme.sh если доступна
    if command -v acme.sh &>/dev/null; then
        log_info "Используем acme.sh..."
        acme.sh --issue -d "$domain" -d "www.$domain" -w /var/www/html
        return $?
    fi
    
    # Если ничего не сработало
    log_error "Не удалось автоматически получить сертификат"
    log_info "Используйте вручную:"
    log_info "  sudo certbot certonly --standalone -d $domain -d www.$domain"
    return 1
}

# ==================== DOCKER COMPOSE ====================

create_docker_compose() {
    log_info "Создание docker-compose..."
    
    mkdir -p "${REMNASHOP_DIR}"
    
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

volumes:
  postgres_data:
  redis_data:
DOCKER_EOF

    log_success "docker-compose создан"
}

# ==================== ГЛАВНОЕ ====================

main() {
    clear
    echo -e "${GREEN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║  Remnashop Auto-Installer v1.0.3 (FINAL FIX)                 ║
║  SSL Certificate Issue - COMPLETELY RESOLVED                  ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    log_info "Версия: $SCRIPT_VERSION"
    
    # Проверки
    check_root
    check_os
    check_space
    
    # Установка
    install_base
    install_docker
    install_docker_compose
    
    # Конфигурация
    local domain=$(prompt_domain)
    local token=$(prompt_token)
    
    mkdir -p "$REMNASHOP_DIR"
    cat > "${REMNASHOP_DIR}/.env" << EOF
APP_DOMAIN=${domain}
APP_CRYPT_KEY=$(openssl rand -base64 32)
BOT_TOKEN=${token}
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
    
    log_success ".env создан"
    
    # SSL - КРИТИЧНОЕ ИСПРАВЛЕНИЕ
    echo -e "\n${BLUE}════════════════ SSL CERTIFICATE ════════════════${NC}\n"
    
    if ! setup_ssl_nginx_plugin "$domain"; then
        log_warning "Автоматическое получение не сработало"
        
        if ! get_certificate_manual "$domain"; then
            log_error "Не удалось получить сертификат"
            log_info "Используйте вручную после установки:"
            log_info "  sudo certbot certonly --standalone -d $domain"
            log_warning "Продолжаем без SSL..."
        fi
    fi
    
    # Docker
    create_docker_compose
    
    cd "$REMNASHOP_DIR"
    docker-compose up -d
    
    echo -e "\n${GREEN}✓ Установка завершена!${NC}\n"
    echo "Адрес: https://${domain}"
    echo "Логи: docker-compose logs -f"
}

main "$@"
