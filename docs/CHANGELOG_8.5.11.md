# Chrono Shards 8.5.11

## Contas e isolamento local

- O logout agora salva o progresso pendente, encerra a sessão, limpa completamente `localStorage` e `sessionStorage` e recarrega o jogo na tela de login.
- Saídas de sessão inesperadas, inclusive em outra aba, executam a mesma limpeza e não deixam o save anterior visível no dispositivo.
- A troca de conta remove todos os dados locais que não pertencem à autenticação antes de carregar o save oficial da conta escolhida.
- Caches completos por usuário no `localStorage` foram removidos. O Supabase passa a ser a única fonte para restaurar o save de uma conta.
- Caches legados das versões 8.5.8–8.5.10 são apagados automaticamente na inicialização.
- O jogo não importa automaticamente dados locais para uma conta permanente apenas porque o marcador de usuário está ausente. Migração automática sem marcador só é permitida em sessão anônima.
- Dados em memória do jogo, filas pendentes e rascunhos sensíveis do formulário são zerados durante o logout.

## Servidor

- Sessões anônimas temporárias criadas apenas para entrar ou recuperar outra conta são removidas após a autenticação bem-sucedida, evitando usuários convidados órfãos no Supabase.

## Compatibilidade

- Nenhuma migration SQL nova é necessária.
- É necessário substituir o `index.html` e republicar a Edge Function `game-api`.
