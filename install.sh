#!/usr/bin/env bash
# =============================================================================
# meulanceai-edge — Script de instalação
# Uso: curl -fsSL https://install.meulanceai.com.br | bash -s -- \
#        --establishment-id=UUID \
#        --secret=EDGE_SECRET \
#        [--api-url=https://api.meulanceai.com.br] \
#        [--tailscale-key=TS_KEY]
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
apt-get install -y -qq curl ca-certificates gnupg lsb-release

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
EOF
  chmod 600 "$ENV_FILE"
  info "✅ .env criado (permissões: 600)"
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

# ─── 8. Pull e start ─────────────────────────────────────────────────────────
info "🚀 Baixando imagem e iniciando containers..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$ENV_FILE" pull
docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$ENV_FILE" up -d

# ─── 9. Aguardar e verificar ─────────────────────────────────────────────────
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
