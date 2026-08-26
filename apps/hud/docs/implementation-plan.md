# Plano de implementação do primeiro HUD

## Estado encontrado

- Repositório Git novo, sem arquivos de aplicação ou commits.
- Python 3.13, ffmpeg, `whisper-cli`, Ollama, Codex CLI, Claude Code e `say` disponíveis.
- Ollama local acessível; modelos locais já cadastrados.
- Modelo Whisper encontrado em `/Users/faustobdls/Library/Application Support/Alfredo/models/whisper/ggml-small.bin`.
- Nenhuma CLI ou SDK programático do Antigravity foi confirmado.

## Decisões

- Uma aplicação FastAPI serve a API e o HUD estático na mesma origem.
- Provedores compartilham um contrato normalizado; processos usam listas de argumentos, stdin e nunca `shell=True`.
- O modo Auto usa regras locais transparentes. Fallback só ocorre quando o cliente o autoriza e fica explícito na resposta.
- Busca de memória é textual e limitada. Escritas usam propostas temporárias no runtime, aprovação explícita e substituição atômica.
- Áudio fica exclusivamente no runtime local e é removido em bloco `finally`.

## Fases

1. Configuração, schemas, provedores e roteamento.
2. Memória segura, transcrição e fala.
3. Endpoints FastAPI e HUD responsivo.
4. Testes unitários, smoke tests e documentação.

## Riscos

- CLIs autenticadas podem mudar formatos ou exigir interação; diagnósticos devem continuar acionáveis.
- `MediaRecorder` produz MIME diferente conforme o navegador; ffmpeg normaliza formatos aceitos.
- Permissões do macOS podem bloquear microfone ou fala.
- Arquivos do iCloud podem estar apenas sob demanda; buscas ignoram falhas individuais de leitura.

## Critérios de verificação

- Suíte pytest sem dependência de serviços externos.
- HUD e health check carregam em `127.0.0.1:8765`.
- Consulta real ao Ollama e smoke tests dos endpoints.
- Validação de traversal, aprovação de memória, limites de upload e limpeza de temporários.
