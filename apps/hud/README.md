# Alfredo HUD

HUD local-first para macOS com texto, push-to-talk, provedores locais/remotos controlados e memória Markdown sujeita a aprovação.

## O que funciona

- HUD responsivo servido pela mesma aplicação FastAPI.
- Seleção manual ou roteamento Auto transparente entre Ollama, Codex, Claude Code e Antigravity.
- Ollama pela API em `127.0.0.1`, sem download automático e com modelos permitidos explícitos.
- Tool calling local no Ollama com ciclo de agente limitado e ferramentas somente leitura para disco, sistema, arquivos do projeto e Git.
- Codex não interativo, efêmero e em sandbox somente leitura; Claude não interativo, sem persistência e em modo de planejamento.
- Gravação no navegador, normalização por ffmpeg e transcrição local com whisper.cpp.
- Fala com uma voz instalada do comando `say`.
- Busca textual limitada em Markdown, seleção explícita dos trechos enviados ao chat e escrita atômica apenas depois da aprovação do usuário.

Antigravity aparece no painel, mas permanece indisponível enquanto não houver uma CLI ou SDK programático oficial confirmado. A disponibilidade do Claude também considera `claude auth status`. A falha de qualquer provedor é exibida; fallback local só acontece se a opção for marcada.

## Segurança e privacidade

O servidor escuta apenas em `127.0.0.1` no comando recomendado. Processos são chamados sem shell, respostas de modelos nunca são executadas e prompts completos não são registrados. Temporários de áudio e propostas ficam no runtime local, nunca no iCloud. A busca consulta apenas `.md`, ignora diretórios ocultos e retorna pequenos trechos. Só notas escolhidas pelo usuário devem ser incluídas manualmente em solicitações remotas.

O Ollama não recebe um terminal genérico. Ele pode chamar apenas `get_disk_usage`, `get_system_info`, `list_project_files`, `read_project_file`, `search_project`, `git_status` e `git_diff`. Caminhos ficam presos ao projeto, arquivos binários e grandes são recusados, comandos usam argumentos fixos sem shell e cada conversa aceita no máximo seis chamadas. O HUD mostra as ferramentas efetivamente utilizadas.

Por padrão, novas notas só podem ser criadas sob `Alfredo/` no cofre. Mude `ALFREDO_MEMORY_DIRS` para uma lista de diretórios separados por vírgula. Arquivos existentes não são sobrescritos.

## Voz e permissões

- Autorize o microfone quando o navegador solicitar. Em caso de bloqueio, confira **Ajustes do Sistema → Privacidade e Segurança → Microfone**.
- Pressione e segure **Pressione para falar**; ao soltar, a gravação é enviada localmente.
- `WHISPER_MODEL_PATH` deve apontar para um modelo STT válido do whisper.cpp.
- `ALFREDO_TTS_VOICE` deve corresponder exatamente a uma voz exibida por `say -v '?'`. `Luciana` é o padrão em português; altere se ela não estiver instalada.
- Safari e Chromium podem escolher contêineres diferentes para `MediaRecorder`; ffmpeg faz a conversão para WAV mono a 16 kHz.

## API

Os endpoints são `GET /api/health`, `GET /api/providers`, `POST /api/chat`, `POST /api/transcribe`, `POST /api/speak`, `GET /api/memory/search`, `POST /api/memory/propose` e `POST /api/memory/approve`. A documentação interativa fica em `/api/docs`.

## Solução de problemas

- **Ollama offline:** inicie o aplicativo/serviço Ollama e confira `curl http://127.0.0.1:11434/api/tags`.
- **Modelo ausente:** escolha um modelo já instalado. O Alfredo nunca baixa modelos por conta própria.
- **Codex ou Claude falha:** confira a autenticação diretamente nas respectivas CLIs. O painel exibe um diagnóstico e o retorno normalizado.
- **Whisper falha:** confirme `command -v whisper-cli`, o caminho do `.bin` e a leitura do arquivo.
- **Nota não gravada:** confirme que o caminho termina em `.md`, começa por um diretório permitido e ainda não existe.

## Desenvolvimento e testes

```bash
../../.venv/bin/python -m pytest -q
```

## Instalação e execução

```bash
cd "$HOME/Workspace/alfredo"
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install -e "apps/hud[dev]"
cp apps/hud/.env.example apps/hud/.env
```

Revise `.env`, especialmente os caminhos do cofre, runtime e modelo Whisper. Depois:

```bash
cd apps/hud
uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload
open http://127.0.0.1:8765
```
