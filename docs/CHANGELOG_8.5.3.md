# Chrono Shards 8.5.3

## Correção

- Corrigido travamento ao abrir Configurações após a integração da economia 8.5.2.
- O observador do painel de economia não monitora mais toda a subárvore de `overlayCard`.
- A atualização do painel agora é limitada às trocas diretas da tela e usa debounce.
- Adicionado fallback por clique para reinserir o painel após telas de Configurações serem redesenhadas.

## Supabase

- Nenhuma alteração no SQL.
- Nenhuma alteração na Edge Function `game-api`.
- Não é necessário executar migração ou republicar a função para esta correção.
