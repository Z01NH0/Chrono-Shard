# Revisão técnica — Chrono Shards 8.5.12

## Objetivo

A interface principal do jogo agora só é liberada depois que o Supabase confirma uma conta permanente válida. A tela de login não depende mais de o jogador entrar nas Configurações.

## Fluxo de inicialização

### Conta permanente já conectada

1. O jogo exibe somente `Carregando...` enquanto valida a sessão.
2. O save oficial é baixado e aplicado.
3. O menu principal é liberado.
4. A tela de login não aparece.

### Nenhuma sessão salva

1. O jogo detecta a ausência do token local antes de carregar o SDK do Supabase.
2. O Chrono ID é aberto imediatamente.
3. O menu principal permanece oculto e sem interação.
4. O jogador precisa entrar, criar conta ou recuperar uma conta.

### Sessão anônima de uma versão anterior

1. O jogo mantém o progresso local atrás da tela bloqueada.
2. O Chrono ID é aberto obrigatoriamente.
3. O jogador pode entrar em outra conta ou criar uma conta usando o progresso atual.
4. Não existe mais o botão `Continuar como convidado`.

### Conta antiga que precisa de reparo

A tela obrigatória `Concluir Conta` continua sendo aberta. O menu só é liberado depois que a identidade permanente e a nova chave de recuperação forem concluídas.

### Conexão indisponível

O jogo não abre um save antigo silenciosamente. É exibida a tela de conexão com `Tentar novamente`, mantendo o menu bloqueado para evitar jogar com uma conta ou estado incorretos.

## Proteção visual e lógica

- A classe `chrono-auth-locked8512` mantém o overlay principal invisível mesmo que algum patch antigo tente abri-lo.
- Foram removidos os timeouts que liberavam o menu depois de 1,4 ou 3,5 segundos independentemente do login.
- A função pública de revelar a interface também verifica `ChronoCloud.isAuthenticated()`.
- O evento `chrono-account-ready` só é disparado após sessão, perfil e save estarem prontos.
- O modal obrigatório não pode ser fechado por botão, clique externo ou tecla Escape.
- Logout, token expirado e logout em outra aba voltam ao mesmo bloqueio obrigatório.

## Arquivos de servidor

Esta versão não altera banco de dados nem Edge Function. As mudanças estão no cliente e na documentação. A `game-api` da versão 8.5.11 permanece compatível.
