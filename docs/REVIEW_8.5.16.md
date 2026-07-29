# Investigação profunda das missões — 8.5.16

## Sintoma reproduzido pelo código

A tela de Missões podia abrir com contratos que pareciam não progredir. Ao entrar em **Awakening** e voltar para **Missões Gerais**, o progresso correto aparecia.

A causa não era simplesmente o save guardar uma rotação antiga. As atribuições oficiais ficam em `chrono_player_missions`, separadas do snapshot geral. O problema estava na ligação entre essa tabela e a interface:

1. `chrono_mission_payload` devolvia `missionId`, `baseline` e cooldown, mas não devolvia `target`, `progress` nem `done`.
2. O HTML carregava as estatísticas oficiais e calculava corretamente os cartões.
3. Logo depois, o decorador autoritativo esperava aqueles campos ausentes e sobrescrevia os cartões como `0/1`, removendo o botão de resgate.
4. Trocar para Awakening e voltar redesenhava a tela pelo cálculo local, sem executar novamente o decorador defeituoso. Por isso parecia que a aba de Awakening “puxava” as missões.

## Correções

- A RPC agora retorna `current`, `progress`, `target`, `done`, métrica, recompensas e `serverTime` para cada slot.
- O cliente não sobrescreve mais um cartão quando recebe uma resposta antiga sem progresso completo.
- A conta hidrata as atribuições oficiais assim que o estado do Chrono Cloud fica disponível, antes mesmo de o jogador abrir Missões.
- Alternar entre Missões Gerais e Awakening reaplica o estado oficial e sincroniza novamente quando o cache estiver antigo.
- Depois que `serverAuthority856` é ativado, o navegador não sorteia contratos novos sozinho. Cooldowns vencidos são renovados pelo servidor.
- O vencimento de cooldown chama `load_missions` em vez de gerar uma rotação local.
- A aplicação visual é repetida após um pequeno atraso para sobreviver a patches históricos que redesenham o mesmo painel.
- A recuperação automática de checkpoints foi ampliada de 45 para 180 segundos, reduzindo o risco de uma aba em segundo plano ser tratada como partida abandonada.

## Arquitetura final

- `chrono_player_missions`: fonte oficial das atribuições, baselines, cooldowns e resgates.
- `chrono_player_state.mission_stats`: fonte oficial dos feitos acumulados.
- `save_data/client_save_data`: snapshot de compatibilidade e sistemas ainda locais; não decide quais contratos oficiais estão ativos.
- `localStorage`: cache temporário da sessão aberta, hidratado pelo servidor.

## Limitações

A validação estrutural não substitui uma partida real no projeto Supabase do usuário. O teste final precisa ocorrer depois da migration e do deploy da Edge Function.
