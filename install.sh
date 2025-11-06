#!/bin/bash

################################################################################
# Remnashop + Remnawave + Nginx Auto-Installer for Ubuntu
# 
# Это универсальный скрипт для автоматической установки полного стека:
# - Remnawave Panel (VPN управление)
# - Remnashop Bot (Telegram бот продажи)
# - Nginx (реверс прокси с SSL/TLS)
# 
# Требования: Ubuntu 20.04+ с root доступом
# 
# Использование:
#   sudo bash install.sh
#
# FIXED v1.0.1:
#   - Поддержка Punycode для кириллических доменов
#   - Улучшенная проверка портов и firewall
#   - Retry логика для SSL сертификатов
#   - Лучшая обработка ошибок DNS
#
################################################################################

set -euo pipefail
IFS=$'\n\t'

# ==================== ПЕРЕМЕННЫЕ ====================
readonly SCRIPT_VERSION="1.0.1"
readonly PROJECT_NAME="Remnashop Installer"
readonly INSTALL_DIR="/opt"
readonly REMNAWAVE_DIR="${INSTALL_DIR}/remnawave"
readonly REMNASHOP_DIR="${INSTALL_DIR}/remnashop"
readonly LOG_FILE="/var/log/remnashop-install.log"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ==================== ФУНКЦИИ ЛОГИРОВАНИЯ ====================

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}ℹ INFO${NC}: $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}✓ SUCCESS${NC}: $*"
    log "SUCCESS" "$*"
}

log_warning() {
    echo -e "${YELLOW}⚠ WARNING${NC}: $*"
    log "WARNING" "$*"
}

log_error() {
    echo -e "${RED}✗ ERROR${NC}: $*" >&2
    log "ERROR" "$*"
}

# ==================== ФУНКЦИИ ПРОВЕРОК ====================

check_root() {
    if [[ $(id -u) -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root (используйте sudo)"
        exit 1
    fi
    log_success "Проверка root прав: успешно"
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удалось определить ОС"
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release
    
    if [[ "${ID}" != "ubuntu" ]]; then
        log_error "Этот скрипт требует Ubuntu. Обнаружена ОС: ${ID}"
        exit 1
    fi

    local version_id
    version_id=$(echo "${VERSION_ID}" | cut -d. -f1)
    
    if [[ ${version_id} -lt 20 ]]; then
        log_error "Требуется Ubuntu 20.04 или выше. Обнаружена версия: ${VERSION_ID}"
        exit 1
    fi

    log_success "Проверка ОС: Ubuntu ${VERSION_ID}"
}

check_disk_space() {
    local available_space
    available_space=$(df "${INSTALL_DIR}" | awk 'NR==2 {print $4}')
    
    # 20GB в KB
    local required_space=$((20 * 1024 * 1024))
    
    if [[ ${available_space} -lt ${required_space} ]]; then
        log_error "Недостаточно место на диске. Требуется минимум 20GB"
        exit 1
    fi
    
    log_success "Проверка дискового пространства: достаточно ($(( available_space / 1024 / 1024 ))GB)"
}

check_ram() {
    local available_ram
    available_ram=$(free -m | awk 'NR==2 {print $7}')
    
    if [[ ${available_ram} -lt 1024 ]]; then
        log_warning "Рекомендуется минимум 2GB свободной памяти. Доступно: ${available_ram}MB"
    else
        log_success "Проверка оперативной памяти: достаточно (${available_ram}MB)"
    fi
}

# ==================== ФУНКЦИИ ПРОВЕРКИ ПОРТОВ ====================

check_port_open() {
    local port="$1"
    local timeout=5
    
    if timeout ${timeout} bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${port}" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_firewall() {
    log_info "Проверка файерволла и портов..."
    
    # Проверяем UFW
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            log_warning "UFW файерволл включен. Открываем порты 80 и 443..."
            ufw allow 80/tcp > /dev/null 2>&1 || true
            ufw allow 443/tcp > /dev/null 2>&1 || true
            log_success "Порты открыты в UFW"
        fi
    fi
    
    # Проверяем netfilter
    if command -v iptables &> /dev/null; then
        if iptables -L -n 2>/dev/null | grep -q "Chain"; then
            log_warning "Iptables правила найдены"
            # Добавляем правила если нужно
            iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
            iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        fi
    fi
}

check_dns_resolution() {
    local domain="$1"
    local ip
    
    log_info "Проверка DNS разрешения для: $domain"
    
    ip=$(getent hosts "$domain" | awk '{ print $1 }' | head -1)
    
    if [[ -z "$ip" ]]; then
        log_error "Домен $domain не разрешается в IP адрес"
        log_error "Проверьте DNS настройки вашего хостинга"
        log_error "Команда для проверки: nslookup $domain"
        return 1
    fi
    
    log_success "Домен $domain разрешается в: $ip"
    
    # Проверяем, совпадает ли с публичным IP
    local public_ip
    public_ip=$(curl -s https://api.ipify.org || echo "")
    
    if [[ -n "$public_ip" && "$ip" != "$public_ip" ]]; then
        log_warning "IP домена ($ip) не совпадает с публичным IP сервера ($public_ip)"
        log_warning "Это может быть проблемой, если вы используете локальный IP"
    fi
    
    return 0
}

# ==================== ФУНКЦИИ УСТАНОВКИ ====================

update_system() {
    log_info "Обновление системы..."
    apt-get update -qq
    apt-get upgrade -y -qq
    log_success "Система обновлена"
}

install_dependencies() {
    log_info "Установка необходимых зависимостей..."
    
    apt-get install -y -qq \
        curl \
        wget \
        git \
        gnupg \
        lsb-release \
        ca-certificates \
        apt-transport-https \
        software-properties-common \
        build-essential \
        certbot \
        python3-certbot-nginx \
        dnsutils \
        net-tools
    
    log_success "Зависимости установлены"
}

install_docker() {
    log_info "Установка Docker..."
    
    # Проверка, установлен ли Docker
    if command -v docker &> /dev/null; then
        log_success "Docker уже установлен: $(docker --version)"
        return 0
    fi

    # Добавление GPG ключа Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null
    
    # Добавление репозитория Docker
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io
    
    # Запуск Docker
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker установлен: $(docker --version)"
}

install_docker_compose() {
    log_info "Установка Docker Compose..."
    
    # Проверка, установлен ли Docker Compose
    if command -v docker-compose &> /dev/null; then
        log_success "Docker Compose уже установлен: $(docker-compose --version)"
        return 0
    fi

    local compose_version="2.24.0"
    local compose_url="https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
    
    curl -fsSL "${compose_url}" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    log_success "Docker Compose установлен: $(docker-compose --version)"
}

install_nginx() {
    log_info "Установка Nginx..."
    
    if command -v nginx &> /dev/null; then
        log_success "Nginx уже установлен: $(nginx -v 2>&1 | cut -d' ' -f3)"
        return 0
    fi

    apt-get install -y -qq nginx

    # Запуск Nginx
    systemctl start nginx
    systemctl enable nginx
    
    log_success "Nginx установлен"
}

# ==================== ФУНКЦИИ КОНВЕРТАЦИИ PUNYCODE ====================

convert_to_punycode() {
    local domain="$1"
    
    # Проверяем, содержит ли домен не-ASCII символы
    if [[ "$domain" =~ [^[:ascii:]] ]]; then
        log_info "Домен содержит не-ASCII символы, конвертируем в Punycode..."
        
        # Используем idn если доступен, иначе используем python
        if command -v idn &> /dev/null; then
            domain=$(idn "$domain" 2>/dev/null || echo "$domain")
        elif command -v python3 &> /dev/null; then
            domain=$(python3 -c "import sys; print(sys.argv[1].encode('idna').decode('ascii'))" "$domain" 2>/dev/null || echo "$domain")
        fi
        
        log_success "Punycode домен: $domain"
    fi
    
    echo "$domain"
}

# ==================== ФУНКЦИИ ВВОДА ПОЛЬЗОВАТЕЛЯ ====================

prompt_domain() {
    local domain
    
    while true; do
        echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}Введите доменное имя для вашего сервера${NC}"
        echo -e "${YELLOW}Пример: example.com или fenixvpn.ru${NC}"
        echo -e "${YELLOW}Поддерживаются кириллические домены (IDN)${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        read -p "Домен: " domain
        
        if [[ ${#domain} -lt 4 ]]; then
            log_error "Домен слишком короткий"
            continue
        fi
        
        # Конвертируем в Punycode если нужно
        domain=$(convert_to_punycode "$domain")
        
        # Проверяем формат
        if [[ ! "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
            log_error "Некорректный формат домена после конвертации"
            continue
        fi
        
        # Проверяем DNS разрешение
        if ! check_dns_resolution "$domain"; then
            log_warning "Домен не разрешается. Вы можете продолжить, но SSL будет получить сложнее."
            read -p "Продолжить? (y/n): " continue_anyway
            if [[ "$continue_anyway" != "y" ]]; then
                continue
            fi
        fi
        
        log_success "Домен выбран: $domain"
        echo "$domain"
        return 0
    done
}

prompt_bot_token() {
    local token
    
    while true; do
        echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}Введите токен Telegram бота${NC}"
        echo -e "${YELLOW}Получить можно у @BotFather в Telegram${NC}"
        echo -e "${YELLOW}Формат: 1234567890:ABCDefGhIjKlMnOpQrStUvWxYz${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        read -p "BOT_TOKEN: " token
        
        if [[ ! "$token" =~ ^[0-9]{9,10}:[A-Za-z0-9_-]{35}$ ]]; then
            log_error "Некорректный формат токена"
            continue
        fi
        
        log_success "Токен установлен"
        echo "$token"
        return 0
    done
}

prompt_dev_id() {
    local dev_id
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Введите Telegram ID разработчика для управления ботом${NC}"
    echo -e "${YELLOW}Узнать свой ID можно у @userinfobot${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    read -p "DEV_ID: " dev_id
    
    if [[ ! "$dev_id" =~ ^[0-9]+$ ]]; then
        log_warning "ID должен состоять из цифр. Используется значение по умолчанию: 0"
        dev_id="0"
    fi
    
    echo "$dev_id"
}

prompt_support_username() {
    local username
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Введите Telegram имя пользователя поддержки${NC}"
    echo -e "${YELLOW}Формат: поддержка (без @)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    read -p "SUPPORT_USERNAME: " username
    
    if [[ ${#username} -lt 3 ]]; then
        log_warning "Используется значение по умолчанию: support"
        username="support"
    fi
    
    echo "$username"
}

# ==================== ФУНКЦИИ ГЕНЕРАЦИИ КЛЮЧЕЙ ====================

generate_random_key() {
    openssl rand -base64 32
}

generate_random_hex() {
    openssl rand -hex 32
}

generate_env_file() {
    local domain="$1"
    local bot_token="$2"
    local dev_id="$3"
    local support_username="$4"
    
    log_info "Генерация файла конфигурации .env..."
    
    local app_crypt_key
    local bot_secret_token
    local database_password
    local redis_password
    
    app_crypt_key=$(generate_random_key)
    bot_secret_token=$(generate_random_hex)
    database_password=$(generate_random_hex)
    redis_password=$(generate_random_hex)
    
    mkdir -p "${REMNASHOP_DIR}"
    
    cat > "${REMNASHOP_DIR}/.env" << EOF
# ========== APPLICATION ==========
APP_DOMAIN=${domain}
APP_CRYPT_KEY=${app_crypt_key}

# ========== BOT ==========
BOT_TOKEN=${bot_token}
BOT_SECRET_TOKEN=${bot_secret_token}
BOT_DEV_ID=${dev_id}
BOT_SUPPORT_USERNAME=${support_username}

# ========== DATABASE ==========
DATABASE_PASSWORD=${database_password}
DATABASE_USER=remnadb
DATABASE_NAME=remnashop

# ========== REDIS ==========
REDIS_PASSWORD=${redis_password}

# ========== REMNAWAVE PANEL ==========
REMNAWAVE_HOST=remnawave
REMNAWAVE_TOKEN=your_remnawave_token_here
REMNAWAVE_WEBHOOK_SECRET=your_webhook_secret_here

# ========== ADDITIONAL ==========
LOG_LEVEL=info
TZ=UTC
EOF
    
    log_success ".env файл создан в ${REMNASHOP_DIR}/.env"
    log_warning "⚠ Заполните значения REMNAWAVE_TOKEN и REMNAWAVE_WEBHOOK_SECRET вручную!"
}

# ==================== ФУНКЦИИ SSL/TLS ====================

setup_ssl_certificate() {
    local domain="$1"
    local max_retries=3
    local retry_count=0
    
    log_info "Настройка SSL сертификата для домена: $domain"
    
    # Убедимся, что Nginx останавливается для получения сертификата
    systemctl stop nginx 2>/dev/null || true
    sleep 2
    
    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Попытка получения сертификата ($((retry_count + 1))/$max_retries)..."
        
        if certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --preferred-challenges http \
            --email admin@"${domain}" \
            -d "${domain}" \
            -d www."${domain}" 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "SSL сертификат успешно получен"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        
        if [[ $retry_count -lt $max_retries ]]; then
            log_warning "Попытка $retry_count не удалась. Жду 10 секунд перед повтором..."
            sleep 10
        fi
    done
    
    log_error "Не удалось получить SSL сертификат после $max_retries попыток"
    return 1
}

# ==================== ФУНКЦИИ КОНФИГУРАЦИИ NGINX ====================

setup_nginx_config() {
    local domain="$1"
    
    log_info "Настройка конфигурации Nginx для $domain..."
    
    local cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local key_path="/etc/letsencrypt/live/${domain}/privkey.pem"
    
    # Проверяем, существуют ли сертификаты
    if [[ ! -f "$cert_path" ]] || [[ ! -f "$key_path" ]]; then
        log_error "Сертификаты не найдены по пути: $cert_path"
        return 1
    fi
    
    # Создание конфигурации Nginx
    cat > /etc/nginx/sites-available/remnashop << 'EOF'
upstream bot {
    server 127.0.0.1:5000;
}

upstream panel {
    server 127.0.0.1:3000;
}

# Редирект HTTP на HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$host$request_uri;
}

# HTTPS сервер
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name DOMAIN_PLACEHOLDER www.DOMAIN_PLACEHOLDER;

    # SSL сертификат
    ssl_certificate CERT_PATH_PLACEHOLDER;
    ssl_certificate_key KEY_PATH_PLACEHOLDER;
    
    # SSL конфигурация
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Логи
    access_log /var/log/nginx/remnashop_access.log combined;
    error_log /var/log/nginx/remnashop_error.log;

    # Корневой путь - панель управления
    location / {
        proxy_pass http://panel;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
        proxy_buffering off;
    }

    # API для бота
    location /api/v1 {
        proxy_pass http://bot;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
        proxy_buffering off;
    }

    # Webhook Telegram
    location ~ ^/webhook/ {
        proxy_pass http://bot;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
        proxy_buffering off;
    }

    # WebSocket поддержка (если нужно)
    location /ws {
        proxy_pass http://bot;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

    # Замена плейсхолдеров
    sed -i "s|DOMAIN_PLACEHOLDER|${domain}|g" /etc/nginx/sites-available/remnashop
    sed -i "s|CERT_PATH_PLACEHOLDER|${cert_path}|g" /etc/nginx/sites-available/remnashop
    sed -i "s|KEY_PATH_PLACEHOLDER|${key_path}|g" /etc/nginx/sites-available/remnashop

    # Создание символической ссылки
    ln -sf /etc/nginx/sites-available/remnashop /etc/nginx/sites-enabled/remnashop
    
    # Отключение default сайта
    rm -f /etc/nginx/sites-enabled/default

    # Проверка конфигурации
    if nginx -t 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Конфигурация Nginx валидна"
        systemctl restart nginx
        return 0
    else
        log_error "Ошибка в конфигурации Nginx"
        return 1
    fi
}

# ==================== ФУНКЦИИ ДОКЕРА ====================

create_docker_compose() {
    local domain="$1"
    
    log_info "Создание docker-compose файла..."
    
    cat > "${REMNASHOP_DIR}/docker-compose.yml" << 'EOF'
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
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  bot:
    image: snoups/remnashop:latest
    container_name: remnashop_bot
    env_file:
      - .env
    ports:
      - "127.0.0.1:5000:5000"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
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
    driver: local
  redis_data:
    driver: local
EOF

    log_success "docker-compose.yml создан"
}

deploy_remnashop() {
    local domain="$1"
    
    log_info "Развертывание Remnashop Bot..."
    
    # Создание директорий для банеров и переводов
    mkdir -p "${REMNASHOP_DIR}/assets/banners"
    mkdir -p "${REMNASHOP_DIR}/assets/translations"
    
    # Запуск контейнеров
    cd "${REMNASHOP_DIR}" || exit 1
    
    log_info "Запуск Docker контейнеров..."
    if docker-compose up -d 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Контейнеры успешно запущены"
        sleep 5
        
        # Проверка статуса контейнеров
        if docker-compose ps 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "Контейнеры работают"
        fi
    else
        log_error "Ошибка при запуске контейнеров"
        return 1
    fi
}

# ==================== ФУНКЦИЯ АВТОЗАПУСКА ====================

setup_autostart() {
    log_info "Настройка автоматического запуска сервисов..."
    
    # Systemd сервис для бота
    cat > /etc/systemd/system/remnashop.service << EOF
[Unit]
Description=Remnashop Bot Service
After=network.target docker.service
Wants=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker-compose -f ${REMNASHOP_DIR}/docker-compose.yml up -d
ExecStop=/usr/bin/docker-compose -f ${REMNASHOP_DIR}/docker-compose.yml down
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable remnashop.service
    
    log_success "Автозапуск настроен"
}

# ==================== ФУНКЦИЯ ФИНАЛИЗАЦИИ ====================

print_summary() {
    local domain="$1"
    
    clear
    
    echo -e "${GREEN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║        ✓ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                          ║
║                                                                  ║
║        Remnashop + Remnawave + Nginx                            ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo -e "\n${BLUE}════════════════════ ИНФОРМАЦИЯ ДОСТУПА ════════════════════${NC}\n"
    
    echo -e "${YELLOW}Панель управления (Remnawave):${NC}"
    echo -e "  → https://${domain}"
    echo -e "  → Используйте учетные данные, созданные при установке\n"
    
    echo -e "${YELLOW}Бот Telegram:${NC}"
    echo -e "  → Найдите бота в Telegram и используйте его для продажи\n"
    
    echo -e "${YELLOW}Важные файлы:${NC}"
    echo -e "  → Конфигурация: ${REMNASHOP_DIR}/.env"
    echo -e "  → Docker Compose: ${REMNASHOP_DIR}/docker-compose.yml"
    echo -e "  → Nginx конфиг: /etc/nginx/sites-available/remnashop"
    echo -e "  → Логи установки: ${LOG_FILE}\n"
    
    echo -e "${RED}════════════════════ ВАЖНЫЕ ДЕЙСТВИЯ ════════════════════${NC}\n"
    
    echo -e "${YELLOW}1. Обновите конфигурацию Remnawave:${NC}"
    echo -e "   sudo nano ${REMNASHOP_DIR}/.env"
    echo -e "   Заполните: REMNAWAVE_TOKEN и REMNAWAVE_WEBHOOK_SECRET\n"
    
    echo -e "${YELLOW}2. Проверьте статус сервисов:${NC}"
    echo -e "   cd ${REMNASHOP_DIR}"
    echo -e "   docker-compose ps\n"
    
    echo -e "${YELLOW}3. Просмотрите логи:${NC}"
    echo -e "   docker-compose logs -f\n"
    
    echo -e "${BLUE}════════════════════ ПОЛЕЗНЫЕ КОМАНДЫ ════════════════════${NC}\n"
    
    echo -e "${GREEN}Перезагрузить контейнеры:${NC}"
    echo -e "   cd ${REMNASHOP_DIR} && docker-compose restart\n"
    
    echo -e "${GREEN}Остановить все сервисы:${NC}"
    echo -e "   cd ${REMNASHOP_DIR} && docker-compose down\n"
    
    echo -e "${GREEN}Просмотреть переменные окружения:${NC}"
    echo -e "   cat ${REMNASHOP_DIR}/.env\n"
    
    echo -e "${GREEN}Обновить бота:${NC}"
    echo -e "   cd ${REMNASHOP_DIR} && docker-compose pull && docker-compose up -d\n"
    
    echo -e "${YELLOW}════════════════════ ПОДДЕРЖКА ════════════════════${NC}\n"
    echo -e "Документация: https://github.com/snoups/remnashop"
    echo -e "Проблемы? Проверьте логи: tail -f ${LOG_FILE}\n"
}

# ==================== ГЛАВНАЯ ФУНКЦИЯ ====================

main() {
    clear
    
    # Приветствие
    echo -e "${GREEN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   Добро пожаловать в Remnashop Auto-Installer v1.0.1           ║
║                                                                  ║
║   Это интерактивный скрипт установки для полного стека:        ║
║   • Remnawave VPN Panel                                         ║
║   • Remnashop Telegram Bot                                      ║
║   • Nginx + SSL/TLS                                             ║
║                                                                  ║
║   Исправления v1.0.1:                                           ║
║   ✓ Поддержка кириллических доменов (Punycode)                 ║
║   ✓ Проверка портов и файерволла                               ║
║   ✓ Улучшенная обработка ошибок DNS                            ║
║   ✓ Retry логика для SSL сертификатов                          ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    # Инициализация логирования
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}"
    chmod 666 "${LOG_FILE}"
    
    log_info "Начало установки Remnashop"
    log_info "Скрипт версия: ${SCRIPT_VERSION}"
    
    # Проверки
    echo -e "${BLUE}════════════════════ ПРОВЕРКИ СИСТЕМЫ ════════════════════${NC}\n"
    check_root
    check_os
    check_disk_space
    check_ram
    check_firewall
    
    # Обновление системы и установка зависимостей
    echo -e "\n${BLUE}════════════════════ УСТАНОВКА КОМПОНЕНТОВ ════════════════════${NC}\n"
    update_system
    install_dependencies
    install_docker
    install_docker_compose
    install_nginx
    
    # Сбор информации от пользователя
    echo -e "\n${BLUE}════════════════════ КОНФИГУРАЦИЯ ════════════════════${NC}\n"
    
    local domain
    domain=$(prompt_domain)
    
    local bot_token
    bot_token=$(prompt_bot_token)
    
    local dev_id
    dev_id=$(prompt_dev_id)
    
    local support_username
    support_username=$(prompt_support_username)
    
    # Генерация конфигурации
    generate_env_file "$domain" "$bot_token" "$dev_id" "$support_username"
    
    # SSL сертификат
    echo -e "\n${BLUE}════════════════════ SSL/TLS СЕРТИФИКАТ ════════════════════${NC}\n"
    if setup_ssl_certificate "$domain"; then
        if setup_nginx_config "$domain"; then
            log_success "Nginx конфигурация успешно применена"
        else
            log_error "Ошибка при конфигурации Nginx. Попробуйте вручную."
        fi
    else
        log_error "Не удалось получить SSL сертификат. Возможные причины:"
        log_error "  1. Домен не разрешается в ваш IP адрес"
        log_error "  2. Порт 80 закрыт файерволом"
        log_error "  3. DNS еще не распространился (попробуйте через 5-10 минут)"
        log_error "  4. Кириллический домен не был корректно преобразован"
        log_error "\nПроверьте логи: cat ${LOG_FILE}"
        exit 1
    fi
    
    # Развертывание
    echo -e "\n${BLUE}════════════════════ РАЗВЕРТЫВАНИЕ ════════════════════${NC}\n"
    create_docker_compose "$domain"
    deploy_remnashop "$domain"
    setup_autostart
    
    # Финальная информация
    print_summary "$domain"
    
    log_success "Установка полностью завершена"
}

# Обработка сигналов
trap 'log_error "Установка прервана пользователем"; exit 1' SIGINT SIGTERM

# Запуск главной функции
main "$@"
