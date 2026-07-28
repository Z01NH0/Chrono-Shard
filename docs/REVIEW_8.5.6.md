# Relatório de revisão — Chrono Shards 8.5.6

## Resultado

A divergência observada nas missões era uma combinação de dois comportamentos:

1. **Erro real de interface:** a UI exibia temporariamente o estado antigo do `localStorage` antes da resposta do Supabase.
2. **Mudança de autoridade:** contratos concluídos antes da versão autoritativa não haviam sido convertidos em contratos oficiais do servidor.

A interface agora espera a resposta do servidor, e uma reconciliação única reaproveita contratos concluídos que constavam no snapshot de migração aceito pelo Supabase.

## Fluxos revisados

- Inicialização e autenticação anônima.
- Carregamento e migração do save.
- Economia e compra de personagens.
- Criação e liquidação de partidas.
- Acúmulo de estatísticas de missão.
- Geração, progresso, cooldown e resgate de contratos.
- Códigos de recompensa e bloqueio de reutilização.
- Atualização de `revision` e recibos idempotentes.
- CORS e reutilização do cliente Supabase.
- Abertura da tela de Configurações e observadores de DOM.

## Garantias adicionadas

- A UI não cria mais um botão de resgate usando apenas o progresso local.
- O servidor devolve `current`, `progress`, `target` e `done` para cada slot.
- O cliente checa o último payload oficial antes de pedir um resgate.
- O PostgreSQL repete a validação dentro da transação.
- Contratos inválidos são anulados e recriados pelo catálogo oficial.
- Códigos antigos usados são importados antes da verificação de duplicidade.
- Operações com o mesmo `requestId` continuam idempotentes.

## O que não pode ser garantido por revisão estática

Não é possível afirmar literalmente 100% sem testes end-to-end no projeto Supabase do usuário, com partidas reais, falhas de internet, troca de dispositivo e todas as telas. A versão foi preparada e validada para esses testes, e inclui uma consulta de auditoria somente leitura.

## Risco de progresso histórico

Um contrato local que nunca apareceu no snapshot já aceito pelo servidor não possui prova confiável. Aceitá-lo livremente permitiria fabricar uma missão concluída pelo DevTools. Por isso, a migração automática preserva apenas o histórico que o próprio servidor já armazenava.

## Pendências arquiteturais

- Vincular a conta anônima a e-mail ou outro login recuperável.
- Migrar recompensas de Bestiário.
- Migrar Awakening e suas chaves/recompensas.
- Migrar Loja do Mauro e Relíquias permanentes.
- Migrar Loja Infernal, Nefalem e Lágrimas.
- Migrar Maestria e baús fora de partidas.
- Recuperar ou remover a referência ao arquivo ausente `multiplayer.js`.
