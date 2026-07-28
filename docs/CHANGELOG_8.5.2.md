# Chrono Shards 8.5.2 — Economia e personagens

## Adicionado

- Colunas de ativação da autoridade de carteira e compras.
- RPC transacional `chrono_enable_economy_server`.
- RPC transacional `chrono_purchase_character_server`.
- Ações `enable_economy` e `purchase_character` na Edge Function.
- Validação de propriedade do personagem ao iniciar uma sessão.
- Painel de ativação da proteção dentro do cartão Supabase.
- Interceptação dos botões de compra da seleção final.
- Sincronização do saldo oficial e dos personagens adquiridos.
- Bloqueio visual e funcional de personagens não reconhecidos pelo servidor.
- Idempotência por `requestId`, evitando cobrança duplicada.

## Mantido em migração

- Recompensas de partidas.
- Missões.
- Bestiário.
- Baús.
- Loja do Mauro.
- Loja Infernal/Nefalem.
- Skins, Awakening e maestrias.

`authority_mode` continua em `migration` e `run_results_enabled` continua desativado.
