# meulance.ai Edge - Instalador

Script de instalação automatizada do meulance.ai Edge para estabelecimentos.

## 🚀 Instalação Rápida

Execute o comando fornecido pelo painel administrativo:

```bash
curl -fsSL https://raw.githubusercontent.com/lucassms9/meulanceai-edge-installer/main/install.sh | sudo bash -s -- \
  --establishment-id=SEU_UUID_AQUI \
  --secret=SUA_CHAVE_SECRETA \
  --live-view-jwt-secret=O_MESMO_LIVE_VIEW_JWT_SECRET_DA_API \
  --api-url=https://api.meulanceai.com.br
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
| `--live-view-jwt-secret` | ✅ Sim | Mesmo `LIVE_VIEW_JWT_SECRET` configurado na API central |
| `--api-url` | ❌ Não | URL da API (padrão: https://api.meulanceai.com.br) |
| `--portal-origin` | ❌ Não | Origem autorizada no CORS (padrão: https://admin.meulanceai.com.br) |

## 📦 O que o instalador faz?

1. ✅ Valida sistema operacional e privilégios
2. 🐳 Instala Docker (se não estiver instalado)
3. 📥 Baixa Compose, Nginx e configuração do MediaMTX
4. 🔐 Cria o `.env` com credenciais e configuração da Live View
5. 🎥 Inicia MediaMTX, Edge, Redis e Nginx via Docker Compose
6. ⚙️ Configura systemd para auto-start
7. 🔁 Configura o auto-updater do Edge

## 🎥 Live View

O MediaMTX não publica portas no host. O acesso segue o fluxo:

```text
Tailscale Funnel → Nginx :80 → Gateway do Edge → MediaMTX interno
```

O `LIVE_VIEW_JWT_SECRET` precisa ser exatamente o mesmo na API e em todos os
Edges. O Nginx publica `/live/`, mas a autorização continua sendo validada pelo
Gateway do Edge.

## 🔄 Atualizar uma instalação existente

Execute novamente o comando de instalação com os mesmos dados. O instalador
preserva o `.env`, adiciona apenas as variáveis ausentes e atualiza Compose,
Nginx e MediaMTX antes de recriar os containers.

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
