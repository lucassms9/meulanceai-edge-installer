#!/bin/bash
#
# Script para configurar mDNS (Avahi) no Ubuntu Server
# Permite que o sistema seja acessível via meulanceai.local na rede local
#
# Uso: sudo ./setup-mdns.sh
#

set -e

echo "🔧 Configurando mDNS/Avahi para meulanceai.local..."

# Verifica se está rodando como root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Este script precisa ser executado como root (sudo)"
   exit 1
fi

# 1. Instala Avahi daemon
echo "📦 Instalando Avahi..."
apt-get update -qq
apt-get install -y avahi-daemon avahi-utils libnss-mdns

# 2. Configura hostname
echo "🏷️  Configurando hostname..."
CURRENT_HOSTNAME=$(hostname)
DESIRED_HOSTNAME="meulanceai"

if [ "$CURRENT_HOSTNAME" != "$DESIRED_HOSTNAME" ]; then
    echo "   Alterando hostname de '$CURRENT_HOSTNAME' para '$DESIRED_HOSTNAME'"
    hostnamectl set-hostname "$DESIRED_HOSTNAME"
    echo "127.0.0.1 localhost" > /etc/hosts
    echo "127.0.1.1 $DESIRED_HOSTNAME.local $DESIRED_HOSTNAME" >> /etc/hosts
else
    echo "   Hostname já está configurado como '$DESIRED_HOSTNAME'"
fi

# 3. Configura Avahi daemon
echo "⚙️  Configurando Avahi daemon..."

# Detecta a interface de rede principal (ignora loopback e docker)
MAIN_INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
echo "   Interface de rede detectada: $MAIN_INTERFACE"

cat > /etc/avahi/avahi-daemon.conf << EOF
[server]
host-name=meulanceai
domain-name=local
use-ipv4=yes
use-ipv6=no
allow-interfaces=${MAIN_INTERFACE}
deny-interfaces=docker0,veth*
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=no

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=yes
publish-domain=yes

[reflector]
enable-reflector=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
EOF

# 4. Cria serviço Avahi para HTTP
echo "📡 Criando serviço HTTP mDNS..."
cat > /etc/avahi/services/http.service << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">MeuLanceAI Edge Server</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <txt-record>path=/</txt-record>
  </service>
</service-group>
EOF

# 5. Configura firewall para permitir mDNS
echo "🔥 Configurando firewall..."
if command -v ufw &>/dev/null; then
    # Permite mDNS (porta 5353 UDP) - CRÍTICO para ESP32 e outros dispositivos descobrirem o edge
    ufw allow 5353/udp comment 'mDNS/Avahi'
    
    # Permite HTTP (porta 80) para ESP32 enviar eventos
    ufw allow 80/tcp comment 'HTTP para ESP32'
    
    echo "   ✅ Regras de firewall configuradas"
else
    echo "   ⚠️  UFW não instalado - firewall não configurado"
fi

# 6. Habilita e reinicia serviço
echo "🚀 Iniciando serviços..."
systemctl enable avahi-daemon
systemctl restart avahi-daemon

# 7. Aguarda inicialização
sleep 3

# 8. Testa configuração
echo ""
echo "✅ Configuração concluída!"
echo ""
echo "📋 Status do Avahi:"
systemctl status avahi-daemon --no-pager | head -10
echo ""

# Obtém IP local
LOCAL_IP=$(ip -4 addr show $MAIN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
echo "🌐 Informações da rede:"
echo "   Interface: $MAIN_INTERFACE"
echo "   IP Local:  $LOCAL_IP"
echo ""

echo "🔍 Testando resolução de nomes:"
if avahi-resolve -n meulanceai.local &>/dev/null; then
    RESOLVED_IP=$(avahi-resolve -n meulanceai.local | awk '{print $2}')
    echo "   ✅ meulanceai.local → $RESOLVED_IP"
else
    echo "   ⚠️  Aguarde alguns segundos e teste novamente"
fi
echo ""

echo "🧪 Comandos de teste:"
echo ""
echo "   No servidor (SSH):"
echo "     ping meulanceai.local"
echo "     curl http://meulanceai.local/health"
echo ""
echo "   No seu Mac/PC (mesma rede Wi-Fi):"
echo "     ping meulanceai.local"
echo "     curl http://meulanceai.local/health"
echo ""
echo "   Se o ping não funcionar do Mac/PC:"
echo "     1. Confirme que está na mesma rede: $LOCAL_IP"
echo "     2. Teste com IP direto: ping $LOCAL_IP"
echo "     3. Verifique firewall do roteador (desabilitar isolamento AP/Client)"
echo "     4. Use IP fixo na ESP32 como fallback: http://$LOCAL_IP/event"
echo ""
echo "📝 Configuração ESP32:"
echo "   Opção 1 (mDNS): http://meulanceai.local/event"
echo "   Opção 2 (IP):   http://$LOCAL_IP/event"
echo ""
