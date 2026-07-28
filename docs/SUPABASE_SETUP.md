# Chrono Shards 8.5.12 — login obrigatório no início

Esta versão altera apenas o cliente para bloquear o jogo até uma conta permanente ser autenticada e carregada.

## Atualizar uma instalação 8.5.11

1. Não execute SQL novo.
2. Não é necessário republicar a Edge Function.
3. Substitua o `index.html` pelo arquivo da versão 8.5.12.
4. Reinicie o Live Server e abra:

   `http://127.0.0.1:5500/index.html?v=8512`

5. Pressione `Ctrl + F5`.

## Teste do início obrigatório

### Sem login

1. Clique em `Sair` ou use uma janela anônima.
2. Reabra o jogo.
3. O Chrono ID deve aparecer automaticamente.
4. O menu não deve aparecer por trás nem depois de alguns segundos.
5. Não deve existir a opção `Continuar como convidado`.

### Com login salvo

1. Entre em uma conta.
2. Feche e abra novamente a página.
3. Deve aparecer somente `Carregando...` por um momento.
4. O save deve ser aplicado e o menu deve abrir sem mostrar o formulário de login.

### Sessão expirada

Quando a sessão não puder ser validada, o jogo permanece bloqueado e mostra login ou a tela de conexão. Ele não abre automaticamente um save local antigo.

## Instalação nova

Execute as migrations na ordem numérica, de `20260724000100` até `20260724000900`, e publique a Edge Function mais recente presente em `supabase/functions/game-api/index.ts`.
