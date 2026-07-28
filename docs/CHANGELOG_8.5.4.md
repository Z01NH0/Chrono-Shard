# Chrono Shards 8.5.4

## Correção da carteira online

- Corrigida a situação em que o jogador ganhava recursos localmente, mas o saldo oficial permanecia parado no valor da migração.
- Adicionada liquidação de recursos ao encerrar uma partida válida.
- A conversão de ouro para Relíquias agora é calculada pelo PostgreSQL.
- Relíquias e Fragmentos Chrono observados durante a run são enviados como deltas, nunca como um novo saldo total.
- O servidor limita os deltas com base em duração, wave e abates.

## Confiabilidade

- Adicionada fila local `chrono_cloud_pending_run_854` para repetir liquidações interrompidas.
- Cada liquidação usa `requestId` estável e não pode ser aplicada duas vezes.
- A sessão da run é vinculada ao usuário autenticado.
- O estado retornado pelo servidor atualiza imediatamente o painel e o saldo local.
- Adicionado aviso visual com os recursos aceitos após a liquidação.

## Supabase

- Novo SQL: `20260724_chrono_run_rewards.sql`.
- Atualizada a Edge Function `game-api` para a fase `run-rewards-8.5.4`.
- `run_results_enabled` é ativado automaticamente para jogadores que já possuem `wallet_authority_enabled`.
- A função `chrono_finish_run_server` recebeu uma nova assinatura com ouro e deltas de recursos.

## Limite conhecido

- Missões, Bestiário, códigos, lojas permanentes, Maestria, Awakening e Loja Infernal ainda precisam de ações específicas no servidor.
- Não foi criada sincronização livre de saldo, pois isso permitiria falsificar recursos pelo DevTools.
