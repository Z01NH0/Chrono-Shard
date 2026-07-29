# Revisão técnica — Chrono Shards 8.5.19

## Objetivo

Esta revisão foi feita sobre a versão 8.5.18, com foco no ciclo completo das missões de Awakening e nos mesmos tipos de falha de hidratação que anteriormente afetaram as missões normais.

Foram revisados:

- carregamento inicial da conta;
- hidratação do Awakening pelo servidor;
- troca entre Missões Gerais e Awakening;
- atualização durante checkpoints de partida;
- atualização após o encerramento da partida;
- ativação, conclusão e resgate de etapas;
- recarregamento da página;
- posse do personagem;
- consistência entre catálogo HTML e catálogo SQL;
- ordem das etapas e gasto de Chaves de Awakening;
- concorrência e chegada fora de ordem dos checkpoints;
- integração entre `index.html`, `game-api/index.ts` e migrations.

## Problemas encontrados e corrigidos

### 1. A interface reconstruía o progresso usando dados locais

O servidor já devolvia `progress`, `target`, `done` e `baseline`, mas a função visual ainda podia recalcular o progresso usando `mission_stats` local.

Isso era especialmente perigoso nas métricas:

- `typeKills.riftTick`;
- `assaultTurboBossKills`;
- `roninParryContacts8427`.

A interface agora usa diretamente o progresso autoritativo devolvido pelo Supabase. O cálculo local permanece apenas como compatibilidade para sessões antigas sem autoridade.

### 2. Baseline autoritativo podia ser substituído por um baseline local

O carregamento reconstruía o baseline a partir de estatísticas locais potencialmente desatualizadas. Depois que as estatísticas oficiais chegavam, o cartão podia saltar de progresso ou parecer concluído sem estar.

Agora o baseline, a meta, a métrica, o progresso e o estado concluído são copiados diretamente do payload oficial.

### 3. Abrir a aba de Awakening não forçava a sincronização

A aba podia ser renderizada com o snapshot local e só se corrigir depois de outra mudança de tela. Agora a abertura da aba solicita o payload oficial e redesenha a interface automaticamente.

Também foram adicionadas atualizações ao:

- voltar para a aba do navegador;
- receber um checkpoint;
- concluir uma partida;
- carregar ou reaplicar o save da conta;
- permanecer com a tela de Awakening aberta por mais de alguns segundos.

### 4. Checkpoints atualizavam o servidor, mas não a interface

A resposta do `checkpoint_run` podia conter o novo progresso do Awakening, porém o HTML não aplicava esse payload imediatamente.

Agora cada checkpoint aceito hidrata o estado autoritativo e atualiza o cartão caso a aba esteja aberta.

### 5. Checkpoints fora de ordem podiam duplicar progresso

O servidor guardava o valor do último checkpoint recebido. Se um checkpoint antigo chegasse depois de um novo, esse valor podia diminuir. Um checkpoint posterior poderia então contabilizar novamente parte do progresso já concedido.

A migration 014 corrige isso de duas maneiras:

- o contador da sessão nunca diminui;
- os resumos cumulativos são combinados pelo maior valor observado.

Além disso, a Edge Function passa para o Awakening o mesmo checkpoint já normalizado pelas missões gerais. Assim, as duas abas usam exatamente os mesmos números oficiais de abates, bosses, elites, habilidades, wave e tipos de inimigos.

Isso também protege os dados especiais do DOOM e a validação da derrota do Devorador Infernal.

### 6. Era possível gastar uma chave em personagem não adquirido

A versão 8.5.18 não verificava a posse do personagem dentro da função SQL de ativação do Awakening.

Agora:

- o servidor valida a propriedade usando o save autoritativo;
- a interface identifica personagens não adquiridos;
- o botão de iniciar a jornada não aparece para eles;
- estados ativos inválidos são removidos pela migration;
- a chave consumida por um estado inválido é devolvida.

### 7. O número da etapa era corrigido silenciosamente pela Edge Function

Um valor ausente ou inválido podia ser limitado automaticamente para uma etapa entre 1 e 5. Agora a `game-api` exige um número inteiro válido e recusa o pedido caso contrário.

### 8. Redesenhos podiam provocar solicitações duplicadas

O redesenho da tela chamava a função pública que também iniciava uma nova sincronização. O fluxo foi separado: redesenhos internos usam a função original e a sincronização ocorre apenas nos pontos apropriados.

### 9. Estados antigos inconsistentes não eram reparados

A migration 014 corrige:

- progresso acima da meta;
- métrica ou meta diferente do catálogo atual;
- Ultimate liberada com menos de cinco etapas;
- jornada com progresso, mas marcada como bloqueada;
- etapa ativa já concluída;
- etapa ativa fora de ordem;
- etapa ativa para personagem não adquirido;
- baseline incorreto em objetivos de wave.

Quando uma etapa ativa inválida é removida, uma Chave de Awakening é devolvida à conta.

## Consistência do catálogo

O catálogo final foi extraído do último módulo ativo do HTML e comparado com a migration 013.

Resultado:

- 10 personagens no HTML;
- 10 personagens no SQL;
- 50 etapas no HTML;
- 50 etapas no SQL;
- nenhuma divergência de título;
- nenhuma divergência de descrição;
- nenhuma divergência de métrica;
- nenhuma divergência de meta.

As 38 métricas distintas usadas pelas etapas possuem tratamento correspondente no SQL.

## Arquitetura final do Awakening

O servidor controla:

- Chaves de Awakening;
- posse dos personagens elegíveis;
- jornada desbloqueada;
- etapa ativa;
- ordem da etapa;
- métrica e meta;
- baseline;
- progresso;
- conclusão;
- Ultimate resgatada;
- idempotência das ações;
- atualização por checkpoints;
- consistência após recarregar a página.

O navegador apenas exibe o payload e solicita ações. Ele não define o progresso oficial.

## Limites da revisão

Foi possível executar validações estruturais, sintáticas, comparações de catálogo e testes isolados das funções de hidratação. Não foi possível executar a migration dentro do projeto Supabase do usuário nem disputar uma partida real contra a Edge Function publicada.

O teste final precisa ser feito depois do deploy do SQL, da Edge Function e do HTML.
