# Revisão geral — Chrono Shards 8.5.7

## Correções aplicadas

- Textos de carregamento simplificados para `Carregando…`.
- Removidos `• SERVIDOR` e outros avisos técnicos dos cards de missão.
- O estado `EM PROGRESSO` voltou a ter apresentação normal; apenas missões prontas recebem destaque verde.
- A tela de missões só usa a camada online quando carteira, missões e códigos estão realmente ativados no estado carregado.
- Removidas as referências mortas a `PeerJS` e ao arquivo ausente `multiplayer.js`. Nenhum código do pacote utilizava essas dependências.
- A Edge Function agora rejeita modos e classes desconhecidos antes de criar uma sessão.
- O reconhecimento de propriedade considera desbloqueio mestre e flags históricas de personagens.
- Foi adicionada proteção contra duas sessões ativas simultâneas para a mesma conta.
- As migrações foram renomeadas com timestamps ordenados. A ordem anterior por nome colocava `missions_codes` antes de `run_rewards`, embora a primeira dependesse de colunas criadas pela segunda.
- `.gitignore`, README e instruções do Supabase foram corrigidos.

## Verificações estáticas

- Todos os scripts inline foram analisados individualmente com `node --check`.
- Todos os scripts inline também foram concatenados e analisados juntos, detectando possíveis declarações globais duplicadas.
- IDs HTML duplicados: nenhum encontrado.
- Referências locais ausentes após a correção: nenhuma.
- Ações chamadas pelo HTML foram comparadas com as ações existentes na Edge Function.
- RPCs chamadas pela Edge Function foram comparadas com as funções presentes nas migrações.
- Catálogo de missões, compras e chaves de personagem foram comparados entre cliente e servidor.
- RLS, revogações e uso de `service_role` foram revisados nas sete tabelas do Chrono.

## Arquitetura ainda parcial

O banco já é autoritativo para carteira usada em compras, personagens suportados, partidas, missões e códigos. O jogo ainda contém sistemas permanentes que vivem no `localStorage`; eles estão listados em `SERVER_MIGRATION_ROADMAP_8.5.7.md`.

## Performance e manutenção

O HTML continua muito grande e baseado em patches sequenciais. Existem dezenas de `MutationObserver` e tarefas de interface. O núcleo de performance já bloqueia observers globais durante a partida e distribui timers entre frames, o que reduz o custo no gameplay. Mesmo assim, a melhoria estrutural mais importante será dividir o HTML em módulos e consolidar patches antigos, evitando reescrever essa parte durante uma atualização de segurança do save.

## Limites da revisão

A revisão estática encontra inconsistências de código, referências ausentes e falhas arquiteturais, mas não substitui testes end-to-end no projeto Supabase real, incluindo perda de conexão, troca de dispositivo, partidas longas e todos os caminhos de recompensa.
