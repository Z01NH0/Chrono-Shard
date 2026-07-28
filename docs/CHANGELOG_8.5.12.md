# Chrono Shards 8.5.12

- Login obrigatório ao iniciar o jogo quando não há conta permanente conectada.
- Removido o botão `Continuar como convidado` da entrada inicial.
- Adicionada tela curta e natural de `Carregando...` durante a validação de uma sessão existente.
- Menu principal e overlay bloqueados até o save oficial terminar de carregar.
- Removidos timeouts antigos que podiam revelar a interface sem autenticação.
- Sessões anônimas antigas são direcionadas ao login ou cadastro sem perder o progresso local antes da escolha.
- Contas já conectadas entram automaticamente e não veem o formulário de login.
- Sessões expiradas, logout em outra aba e falhas de conexão mantêm o jogo bloqueado corretamente.
- Nenhuma migration SQL ou alteração da Edge Function é necessária.
