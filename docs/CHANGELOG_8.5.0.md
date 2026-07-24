# Chrono Shards 8.5.0 — Supabase Cloud Foundation

## Alterações no HTML

- Configuração do Project URL e da Publishable Key.
- Carregamento assíncrono e não bloqueante do `supabase-js`.
- Login anônimo persistente.
- Cliente da Edge Function `game-api`.
- Carregamento do snapshot autoritativo no boot quando habilitado no banco.
- Cartão de Save Online dentro de Configurações.
- Migração única do save local.
- Sincronização manual do snapshot do servidor.
- Registro de início e fim de partidas, sem aplicar recompensas enquanto `run_results_enabled` estiver desligado.
- Preservação da sessão Supabase ao excluir o save local.
- Fallback para o save local quando o servidor ou a biblioteca estiverem indisponíveis.

## Arquivos de servidor

- `supabase/migrations/20260724_chrono_cloud.sql`
- `supabase/functions/game-api/index.ts`
- `supabase/config.toml`

## Estado de segurança

Esta atualização cria a base correta, mas ainda não torna toda a economia autoritativa. Compras, missões, lojas, códigos e recompensas permanentes precisam ser migrados individualmente para ações calculadas no servidor antes de ativar `authority_mode = authoritative` e `run_results_enabled = true`.
