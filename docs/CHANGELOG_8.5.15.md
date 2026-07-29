# Changelog 8.5.15

## Contas e sessão

- Logout tenta revogar a sessão no Supabase e, mesmo em falha de rede, executa a limpeza local completa.
- A tela de login obrigatório continua bloqueando o menu até existir uma conta permanente válida.
- Nenhuma chave `service_role` ou segredo foi adicionada ao cliente.

## Save automático

- Corrigida a instalação duplicada do observador de `Storage.prototype.setItem/removeItem`.
- Evita dois agendamentos de save para a mesma alteração e impede o acúmulo de wrappers ao longo do boot.
- Mantida a separação entre estado oficial e snapshot de compatibilidade do cliente.

## Partidas e missões

- A telemetria captura tipo, boss e elite antes de `enemyDeath`, impedindo perda de informação quando o objeto do inimigo é reciclado pelo pool.
- Uso de habilidade ganhou proteção contra wrappers aninhados e um detector de alteração síncrona para habilidades que não consomem foco ou não aplicam cooldown imediatamente.
- `start_run` agora usa um UUID estável por tentativa. Os três retries reutilizam o mesmo ID.
- A Edge Function devolve a mesma sessão quando recebe novamente a mesma tentativa, evitando sessões paralelas por perda de resposta.
- Mantidos checkpoints, liquidação idempotente e recuperação de runs interrompidas.

## Servidor

- Adicionado limite preventivo de tamanho da requisição.
- Validação explícita do UUID usado para abrir a partida.
- Tratamento de corrida entre duas requisições idênticas de início de run.
