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
cat > /etc/avahi/avahi-daemon.conf << 'EOF'
[server]
host-name=meulanceai
domain-name=local
use-ipv4=yes
use-ipv6=no
allow-interfaces=eth0,wlan0,enp0s3
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

# 5. Habilita e reinicia serviço
echo "🚀 Iniciando serviços..."
systemctl enable avahi-daemon
systemctl restart avahi-daemon

# 6. Aguarda inicialização
sleep 2

# 7. Testa configuração
echo ""
echo "✅ Configuração concluída!"
echo ""
echo "📋 Status do Avahi:"
systemctl status avahi-daemon --no-pager | head -10
echo ""
echo "🔍 Verificando resolução de nomes:"
avahi-resolve -n meulanceai.local || echo "   ⚠️  Aguarde alguns segundos e teste novamente"
echo ""
echo "📝 Teste na ESP32:"
echo "   Configure a ESP32 para enviar requisições para: http://meulanceai.local/event"
echo ""
echo "🧪 Teste manual no terminal:"
echo "   ping meulanceai.local"
echo "   curl http://meulanceai.local/health"
echo ""
