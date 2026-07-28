# Revisão técnica — Chrono Shards 8.5.10

## Causas dos erros observados

### `Cannot read properties of undefined (reading 'toLowerCase')`

Alguns eventos de teclado sintéticos ou de composição não possuem `event.key`. O código base e patches da Fenda chamavam `toLowerCase()` sem verificar o valor. Todos esses pontos foram protegidos.

### `auth/v1/token?grant_type=password 400`

A versão anterior tentava entrar pelo navegador usando um campo `authEmail` que não fazia parte do retorno novo do servidor. O resultado era uma tentativa com e-mail vazio ou desatualizado. O login agora acontece no servidor, pelo nome de usuário, e devolve uma sessão pronta.

### `auth/v1/logout 403`

A conta anônima podia ter sido convertida ou removida enquanto o navegador ainda carregava o token antigo. O logout local tentava revogar esse token no servidor. Agora o logout deste dispositivo remove a sessão local sem depender de uma requisição de revogação inválida.

### `functions/v1/game-api 404`

A função estava publicada, pois outras chamadas ao mesmo endereço retornavam respostas diferentes. O `404` vinha de uma partida pendente cuja sessão já não existia. Esse caso agora retorna um resultado terminal normal e a fila é removida.

### `Soma de inimigos maior que os abates`

Vários patches antigos incrementavam `stats.typeKills` em camadas diferentes. A soma local podia ficar maior que `game.kills`; o PostgreSQL rejeitava a run inteira e nenhuma missão era atualizada. A 8.5.10 mede as mortes diretamente no último `enemyDeath`, evita duplicatas por objeto e aplica um orçamento global antes de enviar.

## Fluxo de autenticação atual

- O cliente mantém uma sessão anônima para acessar a Edge Function.
- `login_account` resolve o nome de usuário e valida a senha no servidor.
- O servidor devolve `access_token` e `refresh_token`.
- O cliente instala a sessão com `setSession`.
- Registro e reparo atualizam o usuário anônimo existente em vez de criar e transferir para outro ID.

## Fluxo de missão atual

- `resetGame` cria uma sessão oficial.
- O rastreador conta eventos reais durante a partida.
- `gameOver` monta um resumo limitado e coerente.
- `chrono_finish_run_server` valida e aplica as estatísticas em uma transação.
- Somente uma resposta `accepted: true` dispara atualização da tela de Missões.

## Limitações mantidas

- O servidor ainda valida plausibilidade; não simula a partida frame a frame.
- Uma partida rejeitada não concede progresso de missão.
- Avisos de Tracking Prevention do CDN são controlados pelo navegador e podem continuar aparecendo sem impedir o funcionamento.
- Sistemas ainda locais continuam no snapshot de compatibilidade até suas migrações autoritativas.
