# Changelog 8.5.18

## Awakening

- Catálogo oficial com 50 etapas e 10 personagens.
- Chaves, jornada iniciada, etapa ativa, progresso, resgate e Ultimate persistidos no servidor.
- Apenas uma etapa pode ficar ativa por conta.
- A etapa deve seguir a ordem correta e consome a Chave no servidor.
- Uma etapa ativada no meio de uma run não herda os feitos anteriores daquela partida.
- Métricas especiais adicionadas: Carrapatos Cronais, bosses no Modo Turbo e contatos de Parry.
- A interface deixa de concluir etapas localmente.

## Loja Infernal

- Rotação determinística de dez minutos por conta, com identificador obrigatório em cada compra.
- Estoque vendido e pity persistidos no banco.
- Preços, descontos e saldos calculados no servidor.
- Compras idempotentes com `requestId`.
- Relíquias, Fragmentos Chrono, Relíquias Infernais, pactos DOOM, skins, baús, Legado e Nefalem passam pela Edge Function.
- Identificador de skin do Ricocheteador normalizado para `ricocheteador`.

## DOOM

- Desbloqueio exige uma sessão normal registrada e a morte validada do guardião infernal.
- Entrada no DOOM é bloqueada quando o servidor não reconhece o desbloqueio.
- Pactos preparados são consumidos no começo da sessão DOOM e anexados ao contexto da run.
- Recompensa de Lágrimas calculada no servidor com limites de plausibilidade.
- Estatísticas persistentes do DOOM adicionadas.
- Nefalem é bloqueado no início da partida quando não pertence à conta.

## Migração e consistência

- Progresso anterior importado uma única vez.
- Valores antigos malformados são sanitizados durante a importação.
- Estado oficial é reaplicado exatamente para Chaves, Lágrimas, Nefalem e DOOM.
- O progresso de uma etapa ativa é importado uma única vez e limitado pela meta oficial.
- Compras em uma rotação vencida são recusadas antes de debitar a conta.
- O cliente não gera uma rotação Infernal paralela quando a autoridade está ativa.
