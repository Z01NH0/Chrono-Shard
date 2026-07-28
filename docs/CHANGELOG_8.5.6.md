# Chrono Shards 8.5.6 — revisão geral e consistência de missões

## Erro principal corrigido

A tela de Missões era renderizada primeiro a partir do `localStorage` e só depois recebia os contratos do Supabase. Isso permitia que um contrato antigo aparecesse como concluído e exibisse o botão de resgate, mesmo quando o slot oficial do servidor era outro.

A partir desta versão:

- A tela mostra um estado de carregamento antes de renderizar os contratos.
- O botão de resgate só aparece depois de `load_missions` confirmar `done: true`.
- Progresso, alvo, cooldown e conclusão exibidos vêm do servidor.
- Em falha de rede, contratos locais não são apresentados como resgatáveis.
- Após uma recusa, a tela sincroniza novamente antes de ser redesenhada.

## Migração de contratos antigos

Foi adicionada uma reconciliação única para contratos que já estavam concluídos no snapshot de migração armazenado no servidor. Somente IDs do catálogo oficial e objetivos confirmados pelas estatísticas oficiais podem ser reaproveitados.

Contratos locais históricos que nunca fizeram parte do snapshot aceito pelo servidor não podem ser comprovados com segurança e não são importados cegamente.

## Outras correções

- Histórico de códigos usados passou a ser importado de forma idempotente para contas que migraram depois da instalação da versão 8.5.5.
- Linhas de missão inválidas ou com dificuldade incompatível são reparadas automaticamente.
- Cooldowns usam o relógio do servidor, reduzindo divergências por horário incorreto no computador.
- O payload de missões inclui auditoria de slots, IDs inválidos e duplicatas.
- Foi incluído `supabase/diagnostics/20260724_chrono_review.sql`, que apenas consulta os dados e não os altera.

## Validações executadas

- 176 blocos JavaScript verificados individualmente com `node --check`.
- Edge Function verificada pelo compilador TypeScript em modo de transpilação.
- 34 contratos comparados entre HTML e PostgreSQL: IDs, métricas e alvos coincidem.
- Todas as ações chamadas pelo HTML existem na Edge Function.
- Todas as RPCs chamadas pela Edge Function existem nas migrações.
- Estrutura de delimitadores das funções PostgreSQL verificada.
- Arquivo ZIP verificado após a criação.

## Limites conhecidos

A revisão estática e os testes locais reduzem bastante a chance de regressões, mas não equivalem a executar todas as rotas no projeto Supabase real. Também permanecem fora da autoridade do servidor: Bestiário, Awakening, Loja do Mauro, Loja Infernal, Maestria e algumas recompensas especiais.

O `index.html` ainda referencia `multiplayer.js`, porém esse arquivo não está presente no pacote recebido; por isso o multiplayer externo não pôde ser validado nesta revisão.
