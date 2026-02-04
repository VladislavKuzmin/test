#!/bin/bash
# scripts/sync-forks.sh - Синхронизация всех форков с оригинальными репозиториями

set -e  # Остановить при любой ошибке

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
ORG="HostmanAppsStage"
UPSTREAM_ORG="timeweb-cloud"
TOKEN="${GITHUB_TOKEN}"

if [ -z "$TOKEN" ]; then
  echo -e "${RED}❌ Ошибка: GITHUB_TOKEN не установлен${NC}"
  exit 1
fi

# Создать временную директорию для работы
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"

# Создать файл отчета
SUMMARY_FILE="$GITHUB_WORKSPACE/sync-summary-$(date +%Y%m%d-%H%M%S).txt"
echo "========================================" >> "$SUMMARY_FILE"
echo "Синхронизация форков - $(date '+%Y-%m-%d %H:%M:%S')" >> "$SUMMARY_FILE"
echo "========================================" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

SUCCESS=0
FAILED=0
NO_CHANGES=0
CONFLICTS=0

# Список репозиториев
REPOS=(
  "app-example-angular"
  "app-example-beego"
  "app-example-celery"
  "app-example-django"
  "app-example-docker-compose"
  "app-example-docker-flask"
  "app-example-ember"
  "app-example-express"
  "app-example-fastapi"
  "app-example-fastify"
  "app-example-flask"
  "app-example-gin"
  "app-example-hapi"
  "app-example-laravel"
  "app-example-nest"
  "app-example-net-core"
  "app-example-next"
  "app-example-nuxt"
  "app-example-phoenix"
  "app-example-preact"
  "app-example-puppeteer"
  "app-example-react"
  "app-example-spring"
  "app-example-svelte"
  "app-example-symfony"
  "app-example-vue"
)

TOTAL=${#REPOS[@]}

echo -e "${BLUE}🚀 Начинаю синхронизацию $TOTAL репозиториев...${NC}"
echo -e "${BLUE}Организация: $ORG${NC}"
echo -e "${BLUE}Оригинал: $UPSTREAM_ORG${NC}"
echo "----------------------------------------"

for REPO in "${REPOS[@]}"; do
  REPO_INDEX=$((SUCCESS + FAILED + NO_CHANGES + CONFLICTS + 1))
  echo ""
  echo -e "${BLUE}[$REPO_INDEX/$TOTAL] 📦 Обрабатываю: $REPO${NC}"

  # Клонировать репозиторий
  echo "   → Клонирование..."
  if git clone "https://$TOKEN@github.com/$ORG/$REPO.git" "$REPO" 2>/dev/null; then
    cd "$REPO"

    # Добавить upstream remote
    if ! git remote | grep -q upstream; then
      git remote add upstream "https://github.com/$UPSTREAM_ORG/$REPO.git"
    fi

    # Получить изменения из оригинала
    echo "   → Получение изменений из upstream..."
    git fetch upstream 2>&1 | grep -v "warning:" || true

    # Получить текущую ветку
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    # Проверить, есть ли новые коммиты
    UPSTREAM_COMMIT=$(git rev-parse upstream/$CURRENT_BRANCH 2>/dev/null || echo "")
    LOCAL_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")

    if [ -z "$UPSTREAM_COMMIT" ]; then
      echo -e "   ${YELLOW}⚠️  Ветка $CURRENT_BRANCH не найдена в upstream. Пропускаем.${NC}"
      cd "$WORK_DIR"
      rm -rf "$REPO"
      ((FAILED++))
      echo "[$(date '+%H:%M:%S')] $REPO - Ветка не найдена в upstream" >> "$SUMMARY_FILE"
      continue
    fi

    if [ "$UPSTREAM_COMMIT" = "$LOCAL_COMMIT" ]; then
      echo -e "   ${GREEN}✅ Репозиторий уже актуален. Нет новых коммитов.${NC}"
      cd "$WORK_DIR"
      rm -rf "$REPO"
      ((NO_CHANGES++))
      echo "[$(date '+%H:%M:%S')] $REPO - Уже актуален" >> "$SUMMARY_FILE"
      continue
    fi

    echo "   → Найдены новые коммиты. Синхронизация..."

    # Попробовать быстрый merge
    if git merge-base --is-ancestor upstream/$CURRENT_BRANCH HEAD; then
      echo "   → Выполняется fast-forward merge..."
      git merge --ff-only upstream/$CURRENT_BRANCH

      # Запушить изменения
      if git push origin HEAD:$CURRENT_BRANCH 2>/dev/null; then
        echo -e "   ${GREEN}✅ Успешно синхронизирован!${NC}"
        ((SUCCESS++))
        echo "[$(date '+%H:%M:%S')] $REPO - Успешно синхронизирован (fast-forward)" >> "$SUMMARY_FILE"
      else
        echo -e "   ${RED}❌ Не удалось запушить изменения${NC}"
        ((FAILED++))
        echo "[$(date '+%H:%M:%S')] $REPO - Ошибка при пуше" >> "$SUMMARY_FILE"
      fi
    else
      echo "   → Создание merge commit..."
      if git merge --no-edit upstream/$CURRENT_BRANCH 2>/dev/null; then
        # Запушить изменения
        if git push origin HEAD:$CURRENT_BRANCH 2>/dev/null; then
          echo -e "   ${GREEN}✅ Merge commit создан и запушен!${NC}"
          ((SUCCESS++))
          echo "[$(date '+%H:%M:%S')] $REPO - Успешно синхронизирован (merge commit)" >> "$SUMMARY_FILE"
        else
          echo -e "   ${RED}❌ Не удалось запушить изменения${NC}"
          ((FAILED++))
          echo "[$(date '+%H:%M:%S')] $REPO - Ошибка при пуше merge commit" >> "$SUMMARY_FILE"
        fi
      else
        echo -e "   ${YELLOW}⚠️  Обнаружены конфликты слияния. Пропускаем.${NC}"
        ((CONFLICTS++))
        echo "[$(date '+%H:%M:%S')] $REPO - Конфликты слияния" >> "$SUMMARY_FILE"
      fi
    fi

    cd "$WORK_DIR"
    rm -rf "$REPO"

  else
    echo -e "   ${RED}❌ Не удалось клонировать репозиторий${NC}"
    ((FAILED++))
    echo "[$(date '+%H:%M:%S')] $REPO - Ошибка клонирования" >> "$SUMMARY_FILE"
  fi

  # Пауза между репозиториями
  sleep 2
done

cd "$GITHUB_WORKSPACE"

# Финальный отчет
echo ""
echo "========================================"
echo -e "${BLUE}📊 ФИНАЛЬНЫЙ ОТЧЕТ:${NC}"
echo "========================================"
echo -e "${GREEN}✅ Успешно: $SUCCESS${NC}"
echo -e "${YELLOW}⚠️  Нет изменений: $NO_CHANGES${NC}"
echo -e "${YELLOW}⚠️  Конфликты: $CONFLICTS${NC}"
echo -e "${RED}❌ Ошибки: $FAILED${NC}"
echo -e "${BLUE}📦 Всего: $TOTAL${NC}"
echo "========================================"

# Добавить итоги в файл отчета
echo "" >> "$SUMMARY_FILE"
echo "========================================" >> "$SUMMARY_FILE"
echo "ИТОГО:" >> "$SUMMARY_FILE"
echo "  Успешно: $SUCCESS" >> "$SUMMARY_FILE"
echo "  Нет изменений: $NO_CHANGES" >> "$SUMMARY_FILE"
echo "  Конфликты: $CONFLICTS" >> "$SUMMARY_FILE"
echo "  Ошибки: $FAILED" >> "$SUMMARY_FILE"
echo "  Всего: $TOTAL" >> "$SUMMARY_FILE"
echo "========================================" >> "$SUMMARY_FILE"

# Если были ошибки, выйти с кодом 1
if [ $FAILED -gt 0 ]; then
  exit 1
fi