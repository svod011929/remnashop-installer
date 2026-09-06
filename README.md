# Remnashop Auto-Installer

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04+-E95420?logo=ubuntu&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)

> 🚀 **Полностью автоматический скрипт для установки полного стека VPN сервиса на Ubuntu VPS**

Одна команда для развертывания:
- **Remnawave Panel** — мощная панель управления VPN
- **Remnashop Bot** — Telegram бот для продажи подписок
- **Nginx** — реверс прокси с SSL/TLS

## ✨ Особенности

- ✅ **Автоматическая установка** — все зависимости установятся автоматически
- ✅ **Интуитивный интерфейс** — пошаговые подсказки для новичков
- ✅ **SSL/TLS сертификаты** — автоматическое получение от Let's Encrypt
- ✅ **Docker & Docker Compose** — контейнеризация всех сервисов
- ✅ **Безопасность** — строгая валидация входных данных
- ✅ **Логирование** — все действия записываются в лог-файл
- ✅ **Обработка ошибок** — graceful обработка ошибок на каждом этапе
- ✅ **Production-ready** — применены лучшие практики DevOps

## 📋 Требования

| Параметр | Минимум | Рекомендуется |
|----------|---------|--------------|
| ОС | Ubuntu 20.04 | Ubuntu 22.04+ |
| RAM | 2 GB | 4 GB+ |
| CPU | 2 cores | 4 cores+ |
| Disk | 20 GB | 50+ GB |
| Интернет | 50 Mbps | 100+ Mbps |

## 🚀 Быстрый старт

### 1️⃣ Загрузка скрипта

```bash
# Загрузите скрипт на ваш VPS
wget https://raw.githubusercontent.com/svod011929/remnashop-installer/main/install.sh

# Или используйте curl
curl -O https://raw.githubusercontent.com/svod011929/remnashop-installer/main/install.sh
```

### 2️⃣ Запуск установки

```bash
# Дайте права на выполнение
chmod +x install.sh

# Запустите с правами root
sudo bash install.sh
```

### 3️⃣ Следуйте инструкциям

Скрипт попросит вас ввести:
- 🌐 **Доменное имя** (например: example.com)
- 🤖 **Telegram Bot Token** (от @BotFather)
- 👤 **Telegram Dev ID** (от @userinfobot)
- 📧 **Telegram Support Username** (для поддержки)

## 📁 Структура проекта

```
remnashop-installer/
├── install.sh                 # Главный скрипт установки
├── README.md                  # Документация
├── .env.example              # Пример конфигурации
├── setup.md                  # Инструкция по установке
├── LICENSE                   # MIT лицензия
└── .gitignore               # Git конфигурация
```

## ⚙️ Что устанавливается

### Системные компоненты
- Docker & Docker Compose
- Nginx веб-сервер
- Certbot для SSL/TLS
- PostgreSQL
- Redis

### Docker контейнеры
- **Remnashop Bot** — Python приложение для Telegram
- **Remnawave Panel** — Go приложение для управления VPN
- **PostgreSQL** — база данных
- **Redis** — кеш и очередь

## 🔧 Конфигурация

После установки отредактируйте конфигурацию:

```bash
nano /opt/remnashop/.env
```

**Критически важные переменные:**

```env
# Telegram Bot
BOT_TOKEN=your_bot_token_here
BOT_DEV_ID=your_telegram_id

# Домен
APP_DOMAIN=your-domain.com

# Remnawave интеграция
REMNAWAVE_TOKEN=your_api_token
REMNAWAVE_WEBHOOK_SECRET=your_webhook_secret
```

## 📊 Проверка статуса

```bash
# Перейти в директорию проекта
cd /opt/remnashop

# Просмотр статуса контейнеров
docker-compose ps

# Просмотр логов (все контейнеры)
docker-compose logs -f

# Логи конкретного контейнера
docker-compose logs -f bot
docker-compose logs -f postgres
```

## 🔄 Управление сервисами

```bash
# Перезагрузить все контейнеры
cd /opt/remnashop && docker-compose restart

# Остановить сервисы
docker-compose down

# Запустить сервисы
docker-compose up -d

# Обновить и перезагрузить
docker-compose pull && docker-compose up -d
```

## 🛡️ Безопасность

### Выполненные меры
- ✅ Валидация всех входных данных
- ✅ Генерация криптографически стойких ключей
- ✅ SSL/TLS шифрование всех соединений
- ✅ Безопасное хранение паролей в .env
- ✅ Docker изоляция сервисов
- ✅ Firewall настройки

### Рекомендации
1. **Регулярно обновляйте** систему и Docker образы
2. **Используйте VPN** для доступа к панели управления
3. **Создавайте регулярные резервные копии** базы данных
4. **Мониторьте логи** на предмет аномалий
5. **Используйте двухфакторную аутентификацию** где возможно

## 📝 Логирование

Все действия скрипта логируются в файл:

```bash
# Просмотр логов установки
tail -f /var/log/remnashop-install.log

# Просмотр логов Docker
docker-compose logs -f
```

## 🐛 Решение проблем

### Проблема: "Недостаточно прав"
```bash
# Решение: используйте sudo
sudo bash install.sh
```

### Проблема: "Домен не разрешается"
```bash
# Решение: убедитесь, что DNS правильно настроен
nslookup your-domain.com
```

### Проблема: "Порт 443 занят"
```bash
# Решение: найдите процесс, использующий порт
sudo lsof -i :443

# Остановите его
sudo kill -9 <PID>
```

### Проблема: "Docker не запускается"
```bash
# Решение: перезагрузите Docker daemon
sudo systemctl restart docker

# Проверьте статус
sudo systemctl status docker
```

## 📖 Документация

### Дополнительные ресурсы

| Ресурс | Описание |
|--------|---------|
| [Remnashop Repo](https://github.com/snoups/remnashop) | Официальный репозиторий бота |
| [Remnawave Docs](https://remna.st/docs/) | Документация панели |
| [Docker Docs](https://docs.docker.com/) | Документация Docker |
| [Nginx Docs](https://nginx.org/en/docs/) | Документация Nginx |

## 🤝 Контрибьютинг

Вклад в проект приветствуется!

1. Fork репозитория
2. Создайте ветку (`git checkout -b feature/AmazingFeature`)
3. Коммитьте изменения (`git commit -m 'Add some AmazingFeature'`)
4. Отправьте на GitHub (`git push origin feature/AmazingFeature`)
5. Создайте Pull Request

## 📄 Лицензия

Этот проект распределяется под лицензией **MIT**. Смотрите [LICENSE](LICENSE) для подробностей.

## 💬 Поддержка

Если у вас есть вопросы или проблемы:

1. **Проверьте логи**: `/var/log/remnashop-install.log`
2. **Откройте Issue** на GitHub
3. **Свяжитесь с автором** через Telegram

## 📞 Контакты

- GitHub: [@svod011929](https://github.com/svod011929)
- Telegram: [@KodoDrive](https://t.me/KodoDrive)

## 🌟 Если помогло, не забудьте поставить ⭐

## 📋 История изменений

### v1.0.0 (2025-11-06)
- 🎉 Первый релиз
- ✅ Полная автоматическая установка
- ✅ SSL/TLS сертификаты
- ✅ Интеграция с Remnawave
- ✅ Поддержка Docker Compose

---

**Создано с ❤️ для DevOps энтузиастов**

<!-- kododrive-projects-block -->

## Проекты KodoDrive

Другие проекты автора: [профиль @svod011929](https://github.com/svod011929) · [сайт](https://kododrive.ru) · [Telegram](https://t.me/KodoDrive)

### VPN и инфраструктура

- [BuryatVPN — VPN-сервис + Telegram](https://github.com/svod011929/buryatvpn)
- [VPN Server Installer — VLESS + TLS](https://github.com/svod011929/vpn-server-installer)
- [3X-UI Auto Installer](https://github.com/svod011929/3x-ui-auto-installer)
- [AWG Bot Installer — AmneziaWG](https://github.com/svod011929/awg-bot-installer)
- **RemnaShop Installer** ← ты здесь
- [VPN Auto Installer — панели](https://github.com/svod011929/vpn-auto-installer)
- [VPNHubBot — Telegram VPN-бот](https://github.com/svod011929/VPNHubBot)

### Telegram и автоматизация

- [KDS Server Panel — SSH из Telegram](https://github.com/svod011929/KDS_Server_Panel)
- [Telegram → VK Poster](https://github.com/svod011929/telegram-to-vk-poster)
- [KDS Parser CryptoBot](https://github.com/svod011929/kds_parser_cryptobot)
- [Auction Bot](https://github.com/svod011929/auction-bot)
- [Invest Bot](https://github.com/svod011929/invest-bot)
- [Crypto Check Bot](https://github.com/svod011929/crypto-check-bot)
- [KodoRefStarsBot](https://github.com/svod011929/KodoRefStarsBot)

### Магазины и финансы

- [KodoCashFlow](https://github.com/svod011929/KodoCashFlow)
- [Telegram Crypto Shop](https://github.com/svod011929/telegram-crypto-shop)
- [TalkProfit](https://github.com/svod011929/talkprofit)

### Сайты

- [KodoDrive Portfolio](https://github.com/svod011929/kododrive-portfolio)
- [kododrive.github.io](https://github.com/svod011929/kododrive.github.io)

<!-- /kododrive-projects-block -->
