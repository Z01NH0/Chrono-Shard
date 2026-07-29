# Changelog 8.5.19

- Corrigida a hidratação autoritativa das missões de Awakening.
- Progresso, meta, baseline e conclusão agora vêm diretamente do servidor.
- A aba de Awakening sincroniza ao abrir, voltar à página, receber checkpoint e finalizar partida.
- Respostas de checkpoint agora atualizam a interface imediatamente.
- Corrigida contagem duplicada causada por checkpoints fora de ordem.
- Resumos cumulativos da sessão nunca regridem.
- Adicionada validação de propriedade do personagem no SQL.
- Personagens não adquiridos aparecem bloqueados na tela de Awakening.
- Etapas inválidas antigas são reparadas e a chave consumida é devolvida.
- Adicionadas validações de ordem das etapas e consistência da Ultimate.
- Edge Function agora rejeita números de etapa ausentes, fracionários ou fora de 1–5.
- Respostas autenticadas da `game-api` passaram a usar `Cache-Control: no-store`.
- Removidas solicitações duplicadas provocadas pelo redesenho da aba.
- Payload de progressão agora inclui revisão, propriedade e horários de atualização.
- Adicionado diagnóstico SQL específico do Awakening.
- Awakening e Missões Gerais agora consomem o mesmo checkpoint cumulativo oficial da partida.
