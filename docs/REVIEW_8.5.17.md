# Revisão 8.5.17 — liquidação silenciosa e mapa de autoridade do servidor

## Alteração visual

A notificação de sucesso **PARTIDA LIQUIDADA** foi removida. A liquidação, as recompensas, os checkpoints, a atualização das missões e o evento interno `chrono-run-settled` continuam funcionando. O evento ainda sincroniza a tela de missões; somente o toast verde foi eliminado.

O aviso **PARTIDA NÃO VALIDADA** foi preservado porque indica perda real de progresso e exige ação do jogador.

## Sistemas já autoritativos no servidor

- Conta, nome de usuário, identidade de autenticação, senha e chave de recuperação em hash.
- Estado oficial de Relíquias e Fragmentos Chrono.
- High Score oficial.
- Compra e propriedade dos personagens protegidos.
- Sessões de partida, checkpoints, liquidação idempotente e limites básicos de recompensa.
- Estatísticas utilizadas pelas 34 missões oficiais.
- Atribuições, baselines, cooldowns, resgate, reputação e recompensas das missões oficiais.
- Resgate de códigos e prevenção de uso repetido.
- Chaves de Awakening e Lágrimas dos Pecadores existem como colunas oficiais e podem ser concedidas por códigos/missões, mas seus sistemas de gasto ainda não são totalmente autoritativos.

## Sistemas ainda guardados como snapshot de compatibilidade

O Supabase armazena uma cópia em `client_save_data`, porém o navegador ainda decide o conteúdo. Isso serve como save entre dispositivos, não como proteção contra DevTools.

- Missões de Awakening, etapa ativa, progresso específico, resgates e Ultimates liberadas.
- Loja Infernal: compra do Nefalem, legados, relíquias infernais, ampliações, baús, rotações, skins demoníacas e buffs de DOOM.
- Gasto e obtenção geral de Lágrimas dos Pecadores fora das rotas oficiais já existentes.
- Gasto de Chaves de Awakening.
- Skins normais, skins épicas, seleção de skin e compras da Loja do Mauro.
- Maestria de personagens e upgrades permanentes.
- Augments Chrono e catálogo de poderes.
- Bestiário: abates próprios do bestiário, registros resgatados e recompensas.
- Relíquias permanentes desbloqueadas e recompensas vinculadas ao bestiário/coleções.
- Progressão e desbloqueios específicos dos modos Rift e DOOM que não passam por código ou compra oficial.
- Tutoriais concluídos e preferências de pular tutorial.
- Configurações pessoais, controles, gráficos e volume. Estes devem continuar locais por não terem valor econômico.

## Prioridade recomendada

1. **Awakening e suas Chaves** — há gasto de recurso e desbloqueio de Ultimates.
2. **Loja Infernal/Nefalem/Lágrimas** — maior superfície econômica ainda controlada pelo cliente.
3. **Bestiário e recompensas de Relíquias** — hoje pode conceder recompensa local fora de uma ação oficial.
4. **Mauro, skins e inventário cosmético** — propriedade permanente deve ficar por conta.
5. **Maestria, upgrades e Augments** — afetam poder permanente e precisam de validação.
6. **Desbloqueios de modos e segredos** — migrar cada conquista para ações verificáveis.
7. **Tutoriais** — apenas sincronização de conveniência, baixa prioridade.

## Arquitetura recomendada para as próximas fases

Criar tabelas e RPCs específicas em vez de tornar todo `client_save_data` confiável:

- `chrono_player_awakenings`
- `chrono_player_inventory`
- `chrono_player_skins`
- `chrono_player_mastery`
- `chrono_player_bestiary`
- `chrono_shop_receipts`

Cada ganho ou gasto deve ser uma ação idempotente com `request_id`, validada pela Edge Function. O cliente solicita a ação; o servidor calcula saldo, propriedade, limites e resultado.
