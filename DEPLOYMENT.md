# DEPLOYMENT.md - Инструкция по публикации на GitHub и развертыванию

## 📋 Содержание
1. [Инициализация репозитория](#инициализация-репозитория)
2. [Структура проекта](#структура-проекта)
3. [Публикация на GitHub](#публикация-на-github)
4. [CI/CD Pipeline](#cicd-pipeline)
5. [Обновления и версионирование](#обновления-и-версионирование)

## Инициализация репозитория

### Шаг 1: Инициализируйте Git

```bash
cd /path/to/remnashop-installer
git init
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

### Шаг 2: Создайте первоначальный коммит

```bash
git add -A
git commit -m "🎉 Initial commit: Remnashop Auto-Installer v1.0.0"
```

### Шаг 3: Создайте репозиторий на GitHub

1. Перейдите на [github.com/new](https://github.com/new)
2. Заполните:
   - **Repository name**: `remnashop-installer`
   - **Description**: Fully automated setup script for Remnashop + Remnawave + Nginx on Ubuntu VPS
   - **Visibility**: Public
   - **Add .gitignore**: Уже есть в проекте
   - **Choose a license**: MIT (уже есть в проекте)

3. Нажмите "Create repository"

### Шаг 4: Подключите удаленный репозиторий

```bash
git remote add origin https://github.com/YOUR_USERNAME/remnashop-installer.git
git branch -M main
git push -u origin main
```

## Структура проекта

```
remnashop-installer/
├── install.sh                    # Главный скрипт установки (700+ строк)
├── README.md                     # Документация проекта
├── setup.md                      # Детальное руководство
├── DEPLOYMENT.md                 # Этот файл
├── .env.example                  # Пример конфигурации
├── .gitignore                    # Git конфигурация
├── LICENSE                       # MIT лицензия
├── .github/
│   ├── workflows/
│   │   ├── test.yml             # Тестирование скрипта
│   │   ├── security.yml         # Проверка безопасности
│   │   └── release.yml          # Автоматический релиз
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md        # Шаблон для багов
│       └── feature_request.md   # Шаблон для фич
└── scripts/
    ├── validate.sh              # Валидация скрипта
    └── test.sh                  # Тестирование
```

## Публикация на GitHub

### Шаг 1: Создайте необходимые директории

```bash
mkdir -p .github/workflows
mkdir -p .github/ISSUE_TEMPLATE
mkdir -p scripts
```

### Шаг 2: Создайте GitHub Actions для CI/CD

Создайте файл `.github/workflows/test.yml`:

```yaml
name: Test Installation Script

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run ShellCheck
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck
          shellcheck install.sh scripts/*.sh
```

### Шаг 3: Создайте шаблон для issues

Файл `.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug Report
about: Сообщить об ошибке
title: '[BUG] '
labels: bug
assignees: ''
---

## Описание проблемы
Четкое описание того, что не работает.

## Шаги воспроизведения
1. Запустите скрипт с...
2. Введите...
3. Получите ошибку...

## Ожидаемое поведение
Что должно было произойти.

## Логи
```
Вставьте содержимое /var/log/remnashop-install.log
```

## Информация о системе
- OS: Ubuntu 22.04
- RAM: 4GB
- Docker версия: ...

## Дополнительный контекст
Любая другая информация...
```

### Шаг 4: Добавьте скрипты валидации

Файл `scripts/validate.sh`:

```bash
#!/bin/bash
set -euo pipefail

echo "🔍 Validating installation script..."

# Check syntax
bash -n ../install.sh
echo "✓ Bash syntax OK"

# Check for common issues
grep -n "^\s*$" ../install.sh | wc -l > /dev/null || true
echo "✓ Blank line check OK"

# Check for TODO/FIXME
if grep -r "TODO\|FIXME" ../install.sh; then
    echo "⚠ Found TODO/FIXME comments"
else
    echo "✓ No TODO/FIXME comments"
fi

echo "✅ Validation passed!"
```

### Шаг 5: Загрузите на GitHub

```bash
git add -A
git commit -m "📝 Add GitHub workflows and templates"
git push
```

## CI/CD Pipeline

### GitHub Actions для автоматического тестирования

Создайте файл `.github/workflows/security.yml`:

```yaml
name: Security Checks

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run security checks
        run: |
          # Check for hardcoded credentials
          ! grep -r "password=" install.sh | grep -v "^\s*#"
          ! grep -r "token=" install.sh | grep -v "^\s*#"
          echo "✓ No hardcoded credentials found"
```

### Автоматический релиз

Создайте файл `.github/workflows/release.yml`:

```yaml
name: Create Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            install.sh
            README.md
            setup.md
          body: |
            ## What's New in ${{ github.ref_name }}
            
            See CHANGELOG for details.
```

## Обновления и версионирование

### Semantic Versioning

Используем формат: `v{MAJOR}.{MINOR}.{PATCH}`

```
v1.0.0  - Первый релиз
v1.1.0  - Добавлена новая функция
v1.0.1  - Исправлена ошибка
v2.0.0  - Несовместимые изменения
```

### Процесс обновления

```bash
# 1. Обновите версию в install.sh
SCRIPT_VERSION="1.1.0"

# 2. Обновите README и документацию
# 3. Создайте коммит
git add -A
git commit -m "🚀 Release v1.1.0: Add feature X and fix bug Y"

# 4. Создайте тег
git tag -a v1.1.0 -m "Release v1.1.0"

# 5. Загрузите на GitHub
git push origin main
git push origin v1.1.0
```

## Документация в README

### Badge'ы для GitHub

Добавьте в начало README.md:

```markdown
![GitHub release](https://img.shields.io/github/v/release/YOUR_USERNAME/remnashop-installer?sort=semver)
![GitHub license](https://img.shields.io/github/license/YOUR_USERNAME/remnashop-installer)
![GitHub issues](https://img.shields.io/github/issues/YOUR_USERNAME/remnashop-installer)
![GitHub pull requests](https://img.shields.io/github/issues-pr/YOUR_USERNAME/remnashop-installer)
![GitHub last commit](https://img.shields.io/github/last-commit/YOUR_USERNAME/remnashop-installer)
```

## Поддержка и сообщение об ошибках

### Инструкции для пользователей

Добавьте в README раздел:

```markdown
## 🐛 Сообщение об ошибках

Нашли баг? 🐞 Помогите нам его исправить!

1. **Проверьте существующие issues** на GitHub
2. **Посмотрите логи**: `/var/log/remnashop-install.log`
3. **Откройте новый issue** с описанием:
   - Версия Ubuntu
   - Результат логов
   - Точные шаги воспроизведения

[Открыть issue](https://github.com/YOUR_USERNAME/remnashop-installer/issues/new)
```

## Бэкап и восстановление

### Инструкция по восстановлению

```bash
# Если что-то пошло не так, можете использовать:
cd /opt/remnashop
docker-compose down -v
rm -rf .env docker-compose.yml

# И запустить скрипт еще раз
sudo bash install.sh
```

## Лучшие практики

### ✅ DO

- Всегда использовать `set -euo pipefail` в shell скриптах
- Проверять входные данные пользователя
- Логировать все важные действия
- Тестировать скрипт перед публикацией
- Использовать descriptive коммит сообщения

### ❌ DON'T

- Не использовать хардкод для паролей/токенов
- Не удалять/перезаписывать existing конфигурации без запроса
- Не запускать опасные команды без подтверждения
- Не игнорировать ошибки
- Не забывать обновлять документацию

## Контакты и поддержка

Если у вас есть вопросы:

1. 📖 Проверьте документацию: `README.md`, `setup.md`
2. 🔍 Посмотрите существующие issues
3. 💬 Создайте новый issue с вопросом
4. 📧 Свяжитесь с разработчиком

---

**Готово к публикации! 🎉**
