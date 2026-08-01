# Atualização de um Edge existente — Live View e Camera Director

Este guia atualiza uma instalação existente do Meu Lance AI Edge para a
arquitetura de Live View:

```text
Portal → Tailscale Funnel → Nginx do Edge → Edge Gateway → MediaMTX → câmera
```

O procedimento preserva o arquivo `/opt/meulanceai/.env` e os volumes Docker.

## Pré-requisitos

- Acesso SSH ao computador Edge.
- Usuário com permissão de `sudo`.
- Docker e Docker Compose instalados.
- Edge já provisionado no Meu Lance AI.
- Valor do `LIVE_VIEW_JWT_SECRET` da API central.
- Conta/Tailnet do Tailscale usada pelos Edges.

> Nunca publique `EDGE_SECRET`, `LIVE_VIEW_JWT_SECRET` ou credenciais do Docker
> em logs, prints, tickets ou repositórios.

## 1. Acessar o Edge e conferir a instalação

```bash
ssh meulanceai@IP_DO_EDGE
cd /opt/meulanceai
sudo docker compose ps
```

Os arquivos existentes normalmente ficam em `/opt/meulanceai`:

```text
.env
docker-compose.yml
nginx.conf
mediamtx.yml
```

## 2. Fazer backup das configurações atuais

```bash
cd /opt/meulanceai
for file in docker-compose.yml nginx.conf mediamtx.yml .env; do
  [ ! -f "$file" ] || sudo cp "$file" "$file.bak"
done
```

O backup permite restaurar rapidamente a configuração anterior se houver algum
problema durante a atualização.

## 3. Atualizar o `.env`

Abra o arquivo:

```bash
sudo nano /opt/meulanceai/.env
```

Garanta que estas variáveis existam uma única vez:

```dotenv
API_URL=https://api.meulanceai.com.br
LIVE_VIEW_JWT_SECRET=COLOQUE_AQUI_O_MESMO_SECRET_DA_API
PORTAL_ORIGIN=https://portal.meulanceai.com.br
BUFFER_DIR=/buffer

# Fase 5 — recomendações passivas; não controla a live
DIRECTOR_SHADOW_ENABLED=true
DIRECTOR_SHADOW_INTERVAL_MS=2000
DIRECTOR_SHADOW_STATUS_HEARTBEAT_MS=10000
DIRECTOR_SHADOW_DIVERGENCE_CAPTURE_INTERVAL_MS=60000
DIRECTOR_AI_DETECTOR=motion
DIRECTOR_AI_MODEL_VERSION=motion-shadow-v1
DIRECTOR_AI_SAMPLE_FPS=5
DIRECTOR_AI_SAMPLE_SECONDS=2

# Fase 7 — piloto automático protegido
DIRECTOR_AUTOMATIC_ENABLED=false
DIRECTOR_AUTOMATIC_MIN_SCORE_MARGIN=0.20
DIRECTOR_AUTOMATIC_CONFIRMATIONS=3
DIRECTOR_AUTOMATIC_MIN_DWELL_MS=5000
DIRECTOR_AUTOMATIC_COOLDOWN_MS=8000
DIRECTOR_AUTOMATIC_MAX_RECOMMENDATION_AGE_MS=4000
DIRECTOR_AUTOMATIC_MAX_CAPTURE_LATENCY_MS=8000
DIRECTOR_AUTOMATIC_MANUAL_OVERRIDE_MS=30000
```

Não altere as variáveis específicas do Edge já provisionado, especialmente:

```dotenv
ESTABLISHMENT_ID=UUID_DO_ESTABELECIMENTO
EDGE_SECRET=SECRET_DESTE_EDGE
```

O `LIVE_VIEW_JWT_SECRET` deve ser exatamente igual ao configurado na API
central. Diferenças de espaços, aspas ou caracteres invalidam os tokens da Live
View. No Nano, salve com `Ctrl + O`, confirme com `Enter` e saia com `Ctrl + X`.

O `BUFFER_DIR` precisa ser `/buffer`. Esse é o volume compartilhado, em modo de
leitura, com o `camera-director-ai`. O caminho legado
`/home/ubuntu/buffer` mantém os clipes isolados dentro do container do Edge e
faz o Shadow Mode responder `buffer_unavailable`.

Para conferir apenas a presença das variáveis sem imprimir os segredos:

```bash
sudo sh -c 'for var in ESTABLISHMENT_ID EDGE_SECRET LIVE_VIEW_JWT_SECRET PORTAL_ORIGIN; do grep -q "^${var}=." /opt/meulanceai/.env && echo "${var}=configurado" || echo "${var}=AUSENTE"; done'
```

Não continue enquanto alguma variável aparecer como `AUSENTE`.

Ative `DIRECTOR_SHADOW_ENABLED=true` somente depois de aplicar na API a
migration `20260719023000_add_camera_director_shadow_recommendations`. Mesmo se
o sidecar estiver desativado ou indisponível, a live e a direção manual continuam
funcionando normalmente.

Mantenha `DIRECTOR_AUTOMATIC_ENABLED=false` durante a atualização. Depois de
validar o Shadow Mode, altere somente no Edge piloto para `true`, recrie o
container `meulanceai-edge` e use o botão **Ativar piloto IA** na live PiP. A
flag apenas libera o recurso: cada live continua iniciando em `MANUAL` e a IA
só assume após confirmação explícita no Admin.

## 4. Baixar os arquivos atualizados do streaming

Os comandos abaixo baixam os arquivos da branch `main` do instalador:

```bash
cd /opt/meulanceai

sudo curl -fsSL \
  https://raw.githubusercontent.com/lucassms9/meulanceai-edge-installer/main/docker-compose.edge.yml \
  -o docker-compose.yml

sudo curl -fsSL \
  https://raw.githubusercontent.com/lucassms9/meulanceai-edge-installer/main/nginx.conf \
  -o nginx.conf

sudo curl -fsSL \
  https://raw.githubusercontent.com/lucassms9/meulanceai-edge-installer/main/mediamtx.yml \
  -o mediamtx.yml
```

Valide o Compose antes de recriar os containers:

```bash
sudo docker compose config -q
```

O comando não apresenta saída quando a configuração é válida. Se ele informar
um erro, não prossiga até corrigir o arquivo ou o `.env`.

Esta versão habilita o RTSP somente na rede interna do Docker. O FFmpeg da live
passa a ler `rtsp://mediamtx:8554/<cameraId>` e o MediaMTX mantém a conexão com
a câmera compartilhada entre a Live View e o YouTube. A porta `8554` não é
publicada no host nem no Tailscale Funnel. Antes de iniciar ou reconstruir o
FFmpeg, o Edge confirma a rota; se o MediaMTX estiver indisponível, usa o RTSP
direto da câmera como fallback e mantém a live operacional.

## 5. Baixar as imagens e recriar os containers

```bash
cd /opt/meulanceai
sudo docker compose pull && sudo docker compose up -d --force-recreate
```

Confira o resultado:

```bash
sudo docker compose ps
sudo docker compose exec nginx nginx -t
```

Os serviços esperados são:

- `meulanceai-edge`
- `mediamtx-edge`
- `nginx-edge`
- `redis-edge`
- `edge-auto-updater`
- `camera-director-ai`

Todos devem permanecer com status `Up` ou `Running`.

Se algum container reiniciar continuamente, consulte os logs:

```bash
sudo docker compose logs --tail=150 meulanceai-edge camera-director-ai mediamtx nginx
```

Ao iniciar uma live, confirme no log do Edge:

```bash
sudo docker compose logs -f meulanceai-edge | grep -E 'relay interno|Adicionando entrada RTSP'
```

O resultado esperado contém `relay interno do MediaMTX` e uma entrada iniciada
por `rtsp://mediamtx:8554/`, sem usuário ou senha da câmera.

## 6. Instalar e conectar o Tailscale

Se o comando `tailscale version` já funcionar, pule a instalação.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Na primeira conexão, o comando exibirá uma URL de autenticação. Abra essa URL,
entre na Tailnet correta e autorize o equipamento. Depois confirme:

```bash
sudo tailscale status
```

## 7. Ativar o Tailscale Funnel

O Nginx do Edge atende na porta local `80`. Para publicar essa porta por HTTPS:

```bash
sudo tailscale funnel --bg 80
```

Na primeira ativação da Tailnet, o Tailscale pode exibir uma URL solicitando que
o Funnel seja habilitado. Abra a URL, autorize o recurso e execute novamente o
comando se necessário.

Confira o endereço público criado:

```bash
sudo tailscale funnel status
```

O retorno esperado é semelhante a:

```text
https://nome-do-edge.tailnet.ts.net (Funnel on)
|-- / proxy http://127.0.0.1:80
```

O uso de `--bg` mantém a configuração do Funnel ativa após reinicializações do
equipamento ou do Tailscale.

> O Funnel torna o Nginx do Edge acessível pela internet. A reprodução das
> câmeras continua protegida pelo JWT validado no Edge, portanto nunca remova a
> validação de token da rota `/live/`.

## 8. Testar o endereço público

Substitua a URL pelo endereço informado no passo anterior:

```bash
curl -i https://nome-do-edge.tailnet.ts.net/health
```

Teste também o preflight CORS usado pelo Portal:

```bash
curl -sS -D - -o /dev/null -X OPTIONS \
  -H 'Origin: https://portal.meulanceai.com.br' \
  -H 'Access-Control-Request-Method: GET' \
  https://nome-do-edge.tailnet.ts.net/live/test
```

O preflight deve responder `HTTP 204` e conter:

```text
access-control-allow-origin: https://portal.meulanceai.com.br
access-control-allow-credentials: true
```

## 9. Cadastrar a URL no Admin

No Admin, abra a tela **Frota de Edges**, localize o Edge atualizado e grave no
campo de Live View apenas a URL base retornada pelo Tailscale:

```text
https://nome-do-edge.tailnet.ts.net
```

Não adicione `/live`, ID da câmera, token ou outros caminhos. Depois salve e
abra uma câmera cadastrada no estabelecimento para validar a reprodução.

## 10. Verificação final

```bash
cd /opt/meulanceai
sudo docker compose ps
sudo tailscale status
sudo tailscale funnel status
sudo docker compose logs --tail=100 meulanceai-edge camera-director-ai nginx mediamtx
```

Checklist:

- [ ] Todos os containers estão ativos.
- [ ] `LIVE_VIEW_JWT_SECRET` está configurado e coincide com a API.
- [ ] `PORTAL_ORIGIN` aponta para `https://portal.meulanceai.com.br`.
- [ ] O Funnel aponta para `http://127.0.0.1:80`.
- [ ] A URL HTTPS do Funnel foi cadastrada no Edge correto no Admin.
- [ ] Uma câmera abre no Portal sem erro de CORS, `404` ou `502`.
- [ ] `camera-director-ai` aparece como `healthy` no `docker compose ps`.
- [ ] Em uma live com duas câmeras, o Admin mostra `IA Shadow` como pronta.
- [ ] A IA apenas recomenda e não troca a câmera automaticamente.
- [ ] O log da live mostra `rtsp://mediamtx:8554/<cameraId>` como entrada.

## Rollback

Se a atualização falhar, restaure os arquivos salvos no passo 2:

```bash
cd /opt/meulanceai
sudo cp docker-compose.yml.bak docker-compose.yml
sudo cp nginx.conf.bak nginx.conf
sudo cp mediamtx.yml.bak mediamtx.yml
sudo cp .env.bak .env
sudo docker compose up -d --force-recreate
```

Confira novamente o status e os logs antes de tentar outra atualização.

Para desabilitar somente o novo relay da live, sem desfazer os demais arquivos:

```bash
sudo sed -i '/^MEDIAMTX_STREAM_PROXY_ENABLED=/d' /opt/meulanceai/.env
echo 'MEDIAMTX_STREAM_PROXY_ENABLED=false' | sudo tee -a /opt/meulanceai/.env
cd /opt/meulanceai
sudo docker compose up -d --force-recreate meulanceai-edge
```

Com a flag desativada, o FFmpeg volta a consumir diretamente a URL RTSP de cada
câmera.

## Comandos úteis do Funnel

Ver o status:

```bash
sudo tailscale funnel status
```

Reaplicar a publicação da porta 80:

```bash
sudo tailscale funnel --bg 80
```

Desativar a publicação HTTPS:

```bash
sudo tailscale funnel --https=443 off
```

Limpar toda a configuração do Funnel neste Edge:

```bash
sudo tailscale funnel reset
```

Use `reset` somente quando quiser remover todas as publicações configuradas no
equipamento.

## Referências do Tailscale

- [Instalar o Tailscale no Linux](https://tailscale.com/docs/install/linux)
- [Referência do comando `tailscale funnel`](https://tailscale.com/docs/reference/tailscale-cli/funnel)
