# Revisão profunda 8.5.15

## Escopo revisado

Foram revisados o HTML completo, os 175 blocos JavaScript, a Edge Function, as 11 migrations existentes, o catálogo final de missões, o fluxo de login obrigatório, logout, troca de conta, save automático, checkpoints e liquidação de partidas.

## Problemas encontrados e corrigidos

### Observador de armazenamento duplicado

O cliente instalava um wrapper em `Storage.prototype.setItem/removeItem` no carregamento e instalava outro após `DOMContentLoaded`. Cada gravação do save podia agendar a sincronização duas vezes. A instalação agora é marcada e idempotente, preservando wrappers externos sem empilhar novamente o próprio patch.

### Tipo do inimigo lido depois da reciclagem

A telemetria consultava `enemy.type`, `enemy.elite` e indicadores de boss depois de executar a função original de morte. Como o jogo possui pools e patches que podem reciclar ou alterar o objeto, o total de abates podia subir enquanto a categoria específica não era registrada. Os dados necessários agora são congelados antes da chamada original.

### Habilidades subcontadas ou duplicadas

O contador dependia principalmente do aumento do cooldown ou da redução do foco. Algumas habilidades iniciam carga, mudam modo ou criam entidades sem alterar esses dois valores imediatamente. Foi adicionado um token leve de mutação do estado e uma trava de profundidade para impedir contagem duplicada quando wrappers antigos chamam outro wrapper.

### Retry criando mais de uma sessão

As três tentativas de `start_run` podiam criar sessões diferentes quando a primeira requisição chegava ao servidor, mas a resposta se perdia. Agora o navegador gera um UUID uma única vez e o servidor usa esse UUID como ID da sessão. Repetições legítimas devolvem a sessão já aberta.

### Logout apenas local

O logout continua limpando totalmente `localStorage`, `sessionStorage`, memória e filas do jogo, mas agora também tenta revogar a sessão atual no Supabase. Uma falha de rede não impede a limpeza local nem deixa o save da conta anterior visível.

## Missões

O catálogo final do HTML possui 34 contratos oficiais e corresponde aos 34 registros ativos definidos no SQL quanto a ID, métrica e meta. Catálogos antigos continuam fisicamente presentes em patches históricos do HTML, mas a interface final e o interceptador de resgate utilizam o catálogo mais recente e a autoridade do servidor.

As missões oficiais recebem progresso somente após uma run com sessão válida. Os checkpoints são cumulativos e não concedem moedas; a liquidação final aplica recompensas e estatísticas uma vez. A recuperação de uma run abandonada aplica apenas os feitos de missão.

As missões de Awakening ainda incluem algumas métricas locais e específicas de personagem, como Parry do Ronin e bosses durante Modo Turbo. Elas ficam no snapshot automático, mas não possuem a mesma autoridade antifraude das 34 missões oficiais.

## Limitações confirmadas

- A caixa postal de e-mail não é comprovada sem OTP, link de confirmação ou login social. A revisão não tenta fingir essa confirmação.
- O teste real de RPCs depende da aplicação correta das migrations e da publicação da Edge Function no projeto Supabase.
- Sistemas permanentes ainda mantidos em `client_save_data` continuam menos seguros do que moedas, personagens protegidos, códigos, runs e missões oficiais.
