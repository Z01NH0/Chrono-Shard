# Chrono Shards 8.5.14

- Corrigida a falsa classificação de erros genéricos como “e-mail já registrado”.
- Duplicidade agora é consultada separadamente em `chrono_profiles` e `auth.users`.
- Identidades órfãs de tentativas interrompidas podem ser removidas com critérios restritos.
- Adicionada validação DNS do domínio, sem fingir confirmação da caixa postal.
- Evitada normalização em massa que poderia colidir com índices de versões antigas.
- Corrigido risco de apagar o save caso a transferência de conta terminasse e a nova sessão falhasse.
- Adicionados checkpoints cumulativos de missões durante partidas.
- Checkpoints e liquidação usam orçamento global de tipos de inimigo.
- Adicionada recuperação segura dos feitos de partidas interrompidas, sem moedas.
- Runs antigas são recuperadas/encerradas antes de iniciar outra.
- Corrigidas baselines de missão inconsistentes.
- Adicionada data da última atualização das estatísticas de missão.
- Hooks finais são reinstalados para resistir a patches antigos.
- Adicionadas três tentativas de abertura da sessão da partida e aviso visível em caso de falha.
- Catálogo HTML/SQL conferido: 34 missões com IDs, métricas e metas iguais.
