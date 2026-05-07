#!/usr/bin/env bash
# =============================================================================
# meulanceai-edge — Script de instalação
# Uso: curl -fsSL https://install.meulanceai.com.br | bash -s -- \
#        --establishment-id=UUID \
#        --secret=EDGE_SECRET \
#        [--api-url=https://api.meulanceai.com.br] \
#        [--tailscale-key=TS_KEY]
#
# Credenciais Docker Hub são buscadas automaticamente da API.
# =============================================================================
set -euo pipefail

# ─── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[meulanceai]${NC} $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error()   { echo -e "${RED}[ERRO]${NC} $*"; exit 1; }

# ─── Defaults ────────────────────────────────────────────────────────────────
ESTABLISHMENT_ID=""
EDGE_SECRET=""
API_URL="https://api.meulanceai.com.br"
TAILSCALE_KEY=""
INSTALL_DIR="/opt/meulanceai"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/lucassms9/meulanceai-edge-installer/main/docker-compose.edge.yml"

# ─── Parse args ──────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --establishment-id=*) ESTABLISHMENT_ID="${arg#*=}" ;;
    --secret=*)           EDGE_SECRET="${arg#*=}" ;;
    --api-url=*)          API_URL="${arg#*=}" ;;
    --tailscale-key=*)    TAILSCALE_KEY="${arg#*=}" ;;
    *) warn "Argumento desconhecido: $arg" ;;
  esac
done

# ─── Validações ──────────────────────────────────────────────────────────────
[[ -z "$ESTABLISHMENT_ID" ]] && error "--establishment-id é obrigatório"
[[ -z "$EDGE_SECRET" ]]      && error "--secret é obrigatório"

# Validar formato UUID
if ! [[ "$ESTABLISHMENT_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  error "--establishment-id deve ser um UUID válido (ex: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
fi

# ─── Verificar OS ─────────────────────────────────────────────────────────────
[[ "$(uname -s)" != "Linux" ]] && error "Este script requer Linux (Ubuntu/Debian)"
[[ "$EUID" -ne 0 ]]            && error "Execute como root: sudo bash install.sh ..."

echo ""
info "╔══════════════════════════════════════════╗"
info "║     meulanceai edge — Instalação        ║"
info "╚══════════════════════════════════════════╝"
echo ""
info "Establishment ID : $ESTABLISHMENT_ID"
info "API URL          : $API_URL"
info "Diretório        : $INSTALL_DIR"
[[ -n "$TAILSCALE_KEY" ]] && info "Tailscale        : ativado"
echo ""

# ─── 1. Dependências do sistema ──────────────────────────────────────────────
info "📦 Instalando dependências base..."
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg lsb-release jq

# ─── 2. Docker ───────────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
  info "🐳 Docker já instalado ($(docker --version | cut -d' ' -f3 | tr -d ','))"
else
  info "🐳 Instalando Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  info "✅ Docker instalado"
fi

# ─── 2.1. Configurar rotação de logs (prevenir disco cheio) ──────────────────
info "📝 Configurando rotação de logs Docker..."
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
  systemctl restart docker
  info "✅ Rotação de logs configurada (30MB máx por container)"
else
  info "⚠️  /etc/docker/daemon.json já existe - não sobrescrito"
fi

# ─── 3. Tailscale (VPN mesh para acesso remoto) ───────────────────────────────
if [[ -n "$TAILSCALE_KEY" ]]; then
  if command -v tailscale &>/dev/null; then
    info "🔒 Tailscale já instalado"
  else
    info "🔒 Instalando Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
  fi

  info "🔒 Conectando ao Tailscale..."
  # Hostname = edge-<primeiros 8 chars do UUID>
  TS_HOSTNAME="edge-${ESTABLISHMENT_ID:0:8}"
  tailscale up --authkey="$TAILSCALE_KEY" --hostname="$TS_HOSTNAME" --accept-routes
  info "✅ Tailscale conectado como $TS_HOSTNAME"
else
  warn "Tailscale não configurado (--tailscale-key não fornecido). Acesso remoto desabilitado."
fi

# ─── 4. Diretório de instalação ───────────────────────────────────────────────
info "📁 Criando $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# ─── 5. docker-compose.edge.yml ───────────────────────────────────────────────
info "📥 Baixando docker-compose..."
curl -fsSL "$DOCKER_COMPOSE_URL" -o "$INSTALL_DIR/docker-compose.yml"

# ─── 5.1. nginx.conf ──────────────────────────────────────────────────────────
info "📥 Baixando nginx.conf..."
NGINX_CONF_URL="https://raw.githubusercontent.com/lucassms9/meulanceai-edge-installer/main/nginx.conf"
curl -fsSL "$NGINX_CONF_URL" -o "$INSTALL_DIR/nginx.conf"
info "✅ nginx.conf instalado"

# ─── 6. .env (o único arquivo sensível — nunca sobrescrito em updates) ─────────
ENV_FILE="$INSTALL_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  warn ".env já existe — não será sobrescrito."
  warn "Para reconfigurar, apague manualmente: rm $ENV_FILE"
else
  info "🔑 Criando $ENV_FILE..."
  cat > "$ENV_FILE" << EOF
ESTABLISHMENT_ID=${ESTABLISHMENT_ID}
API_URL=${API_URL}
EDGE_SECRET=${EDGE_SECRET}
BUFFER_DIR=/home/ubuntu/buffer
EOF
  chmod 600 "$ENV_FILE"
  info "✅ .env criado (permissões: 600)"

  # ─── 6.1. Buscar credenciais Docker da API ─────────────────────────────────
  info "🐳 Buscando credenciais Docker Hub da API..."
  DOCKER_CREDS_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "x-edge-secret: ${EDGE_SECRET}" \
    "${API_URL}/edge/docker-credentials")

  HTTP_STATUS=$(echo "$DOCKER_CREDS_RESPONSE" | tail -n1)
  DOCKER_CREDS=$(echo "$DOCKER_CREDS_RESPONSE" | head -n-1)

  if [[ "$HTTP_STATUS" -eq 200 ]] && [[ -n "$DOCKER_CREDS" ]]; then
    DOCKER_USERNAME=$(echo "$DOCKER_CREDS" | jq -r '.username // empty')
    DOCKER_PASSWORD=$(echo "$DOCKER_CREDS" | jq -r '.password // empty')
    
    if [[ -n "$DOCKER_USERNAME" ]] && [[ "$DOCKER_USERNAME" != "null" ]] && \
       [[ -n "$DOCKER_PASSWORD" ]] && [[ "$DOCKER_PASSWORD" != "null" ]]; then
      
      # Adicionar ao .env
      echo "" >> "$ENV_FILE"
      echo "# Docker Hub credentials (auto-configured)" >> "$ENV_FILE"
      echo "DOCKER_USERNAME=${DOCKER_USERNAME}" >> "$ENV_FILE"
      echo "DOCKER_PASSWORD=${DOCKER_PASSWORD}" >> "$ENV_FILE"
      
      info "✅ Credenciais Docker configuradas automaticamente"
    else
      warn "Credenciais Docker não encontradas na API (usando imagem pública)"
    fi
  else
    warn "Erro ao buscar credenciais Docker (HTTP $HTTP_STATUS)"
    warn "Instalação continua usando imagem pública"
  fi
fi

# ─── 7. Systemd service (garante start automático no boot) ───────────────────
info "⚙️  Configurando serviço systemd..."
cat > /etc/systemd/system/meulanceai-edge.service << EOF
[Unit]
Description=meulanceai Edge Agent
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable meulanceai-edge.service

# ─── 8. Tailscale Watchdog (reconexão automática) ────────────────────────────
if [[ -n "$TAILSCALE_KEY" ]]; then
  info "🔁 Configurando Tailscale Watchdog..."

  cat > "$INSTALL_DIR/tailscale-watchdog.sh" << 'WATCHDOG'
#!/bin/bash
# Monitora e reconecta o Tailscale automaticamente
TAILSCALE_KEY_FILE="/opt/meulanceai/.tailscale-key"
LOG_TAG="tailscale-watchdog"

while true; do
  STATUS=$(tailscale status --json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState','Unknown'))" 2>/dev/null \
    || echo "Unknown")

  if [[ "$STATUS" != "Running" ]]; then
    logger -t "$LOG_TAG" "Tailscale desconectado (state: $STATUS). Reconectando..."

    if [[ -f "$TAILSCALE_KEY_FILE" ]]; then
      TS_AUTH_KEY=$(cat "$TAILSCALE_KEY_FILE")
      tailscale up --authkey="$TS_AUTH_KEY" 2>/dev/null \
        || tailscale up 2>/dev/null \
        || logger -t "$LOG_TAG" "ERRO: falha ao reconectar Tailscale"
    else
      tailscale up 2>/dev/null \
        || logger -t "$LOG_TAG" "ERRO: falha ao reconectar Tailscale (sem authkey salva)"
    fi
  fi

  sleep 30
done
WATCHDOG

  chmod +x "$INSTALL_DIR/tailscale-watchdog.sh"

  # Salvar a authkey para reconexões futuras (permissão restrita)
  echo "$TAILSCALE_KEY" > "$INSTALL_DIR/.tailscale-key"
  chmod 600 "$INSTALL_DIR/.tailscale-key"

  cat > /etc/systemd/system/tailscale-watchdog.service << EOF
[Unit]
Description=Tailscale Connection Watchdog
After=network-online.target tailscaled.service
Wants=network-online.target
Requires=tailscaled.service

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/tailscale-watchdog.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable tailscale-watchdog.service
  systemctl start tailscale-watchdog.service
  info "✅ Tailscale Watchdog ativo (verifica a cada 30s)"
else
  warn "Tailscale Watchdog não instalado (Tailscale não configurado)."
fi

# ─── 9. Docker login (se credenciais disponíveis) ────────────────────────────
DOCKER_USERNAME_VAL=$(grep "^DOCKER_USERNAME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || true)
DOCKER_PASSWORD_VAL=$(grep "^DOCKER_PASSWORD=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || true)

if [[ -n "$DOCKER_USERNAME_VAL" ]] && [[ -n "$DOCKER_PASSWORD_VAL" ]]; then
  info "🐳 Autenticando no Docker Hub como $DOCKER_USERNAME_VAL..."
  echo "$DOCKER_PASSWORD_VAL" | docker login -u "$DOCKER_USERNAME_VAL" --password-stdin \
    && info "✅ Docker Hub autenticado" \
    || warn "⚠️  Falha no docker login — pull pode falhar para imagens privadas"
else
  warn "Credenciais Docker não encontradas no .env — tentando pull sem autenticação"
fi

# ─── 10. Pull e start ────────────────────────────────────────────────────────
info "🚀 Baixando imagem e iniciando containers..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$ENV_FILE" pull
docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$ENV_FILE" up -d

# ─── 10.1. Configurar mDNS/Avahi (acesso via meulanceai.local) ───────────────
info "🔍 Configurando mDNS/Avahi para acesso via meulanceai.local..."
if ! command -v avahi-daemon &>/dev/null; then
  apt-get install -y -qq avahi-daemon avahi-utils
fi

# Configurar hostname
CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" != "meulanceai" ]; then
  hostnamectl set-hostname meulanceai
  info "✅ Hostname configurado: meulanceai"
fi

# Habilitar e iniciar Avahi
systemctl enable avahi-daemon
systemctl start avahi-daemon

# Criar serviço HTTP mDNS
cat > /etc/avahi/services/http.service << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
  </service>
</service-group>
EOF

systemctl restart avahi-daemon
info "✅ mDNS configurado - acesso via meulanceai.local"

# ─── 11. Aguardar e verificar ─────────────────────────────────────────────────
info "⏳ Aguardando edge inicializar (30s)..."
sleep 30

CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' meulanceai-edge 2>/dev/null || echo "não encontrado")

echo ""
if [[ "$CONTAINER_STATUS" == "running" ]]; then
  info "╔══════════════════════════════════════════╗"
  info "║  ✅  Edge instalado com sucesso!         ║"
  info "╚══════════════════════════════════════════╝"
  echo ""
  info "Establishment ID : $ESTABLISHMENT_ID"
  info "Container        : running"
  info "Acesso local     : http://meulanceai.local"
  docker compose -f "$INSTALL_DIR/docker-compose.yml" logs meulanceai-edge --tail 10
else
  warn "Container status: $CONTAINER_STATUS"
  warn "Verifique os logs:"
  warn "  docker compose -f $INSTALL_DIR/docker-compose.yml logs"
fi

echo ""
info "Comandos úteis:"
echo "  Ver logs:      docker compose -f $INSTALL_DIR/docker-compose.yml logs -f meulanceai-edge"
echo "  Reiniciar:     systemctl restart meulanceai-edge"
echo "  Status:        systemctl status meulanceai-edge"
echo "  Atualizar:     docker compose -f $INSTALL_DIR/docker-compose.yml pull && systemctl restart meulanceai-edge"
echo "  Tailscale WD:  systemctl status tailscale-watchdog"
echo ""
info "Acesso ESP32:"
echo "  URL: http://meulanceai.local/event"
