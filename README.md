# meulance.ai Edge - Instalador

Script de instalação automatizada do meulance.ai Edge para estabelecimentos.

## 🚀 Instalação Rápida

Execute o comando fornecido pelo painel administrativo:

```bash
curl -fsSL https://raw.githubusercontent.com/lucassms9/meulanceai-edge-installer/main/install.sh | sudo bash -s -- \
  --establishment-id=SEU_UUID_AQUI \
  --secret=SUA_CHAVE_SECRETA \
  --api-url=https://api.meulanceai.com.br \
  --docker-username=SEU_USERNAME \
  --docker-token=SEU_TOKEN
```

## 📋 Pré-requisitos

- **Sistema Operacional**: Ubuntu 20.04+ ou Debian 11+
- **Privilégios**: Acesso root (sudo)
- **Internet**: Conexão estável para download
- **Hardware**: Mini PC com Docker suportado

## 🔧 Parâmetros

| Parâmetro | Obrigatório | Descrição |
|-----------|-------------|-----------|
| `--establishment-id` | ✅ Sim | UUID do estabelecimento (fornecido pelo admin) |
| `--secret` | ✅ Sim | Chave secreta Edge (32+ caracteres) |
| `--docker-username` | ✅ Sim | Usuário do Docker Hub (para imagens privadas) |
| `--docker-token` | ✅ Sim | Token/senha do Docker Hub |
| `--api-url` | ❌ Não | URL da API (padrão: https://api.meulanceai.com.br) |
| `--tailscale-key` | ❌ Não | Auth key do Tailscale para VPN (opcional) |

## 📦 O que o instalador faz?

1. ✅ Valida sistema operacional e privilégios
2. 🐳 Instala Docker (se não estiver instalado)
3. 🔒 Configura Tailscale VPN (se auth key fornecido)
4. 📥 Baixa docker-compose.edge.yml
5. 🔐 Cria arquivo .env com credenciais
6. 🚀 Inicia serviço Edge via Docker Compose
7. ⚙️ Configura systemd para auto-start
8. 📊 Instala Watchtower para auto-updates

## 🔐 Segurança

- ⚠️ **NUNCA** compartilhe o `--secret` publicamente
- 🔒 O secret é armazenado local em `/opt/meulanceai/.env`
- 🛡️ Permissões restritas (root only) são aplicadas automaticamente
- 🔑 Use Tailscale para acesso remoto seguro (recomendado)

## 🐛 Troubleshooting

### Erro: "curl: (22) The requested URL returned error: 404"
- Verifique se o repositório é público
- Certifique-se de usar a URL correta (`lucassms9/meulanceai-edge-installer`)

### Erro: "Docker daemon not running"
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### Logs do Edge
```bash
cd /opt/meulanceai
sudo docker-compose logs -f edge
```

### Reiniciar Edge
```bash
cd /opt/meulanceai
sudo docker-compose restart edge
```

## 📞 Suporte

Para suporte técnico, contate a equipe meulance.ai através do painel administrativo.

---

**meulance.ai** - Transformando quadras em experiências digitais 🎾⚽🏀
