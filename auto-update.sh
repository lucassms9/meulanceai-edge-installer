#!/bin/bash
# Auto-update script para meulanceai-edge
# Verifica se há nova imagem e atualiza automaticamente

COMPOSE_FILE="/opt/meulanceai/docker-compose.yml"
CONTAINER_NAME="meulanceai-edge"
IMAGE_NAME="lucassms9/meulanceai-edge:latest"
LOG_FILE="/var/log/edge-auto-update.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Login no Docker Hub se credenciais estiverem configuradas
if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
  echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin >> "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
    log "❌ Erro ao fazer login no Docker Hub"
    exit 1
  fi
fi

log "🔍 Verificando atualizações para $IMAGE_NAME..."

# Pegar digest da imagem atual
CURRENT_DIGEST=$(docker inspect --format='{{.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")

# Puxar nova imagem com log de erro
if ! docker pull "$IMAGE_NAME" >> "$LOG_FILE" 2>&1; then
  log "❌ Erro ao fazer pull da imagem"
  exit 1
fi

# Pegar digest da nova imagem
NEW_DIGEST=$(docker inspect --format='{{.Id}}' "$IMAGE_NAME" 2>/dev/null || echo "none")

# Comparar digests
if [ "$CURRENT_DIGEST" = "$NEW_DIGEST" ]; then
  log "✅ Já está na versão mais recente"
  exit 0
fi

log "🆕 Nova versão detectada! Atualizando..."
log "   Current: ${CURRENT_DIGEST:0:12}"
log "   New:     ${NEW_DIGEST:0:12}"

# Atualizar container
cd /opt/meulanceai
if ! docker compose up -d "$CONTAINER_NAME" >> "$LOG_FILE" 2>&1; then
  log "❌ Erro ao atualizar container"
  exit 1
fi

log "✅ Container atualizado com sucesso!"

# Aguardar 10s e verificar se está rodando
sleep 10
if docker ps | grep -q "$CONTAINER_NAME"; then
  log "✅ Container está rodando normalmente"
else
  log "❌ ERRO: Container não está rodando após update!"
  exit 1
fi
