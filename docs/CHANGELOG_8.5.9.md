# Chrono Shards 8.5.9 — correção de contas, login e recuperação

## Correções críticas

- Corrigida a criação de contas permanentes. A versão 8.5.8 alterava os campos do usuário anônimo, mas podia deixá-lo sem uma identidade de e-mail utilizável pelo login com senha.
- Contas criadas pela 8.5.8 são detectadas e recebem um fluxo obrigatório **Concluir Conta**, preservando todo o progresso.
- O registro agora cria uma identidade permanente válida e transfere, em uma transação, estado, sessões, recibos, missões e códigos resgatados.
- O login por nome de usuário resolve apenas um e-mail técnico interno; o e-mail de contato do jogador não é exposto.
- A chave de recuperação é gerada no navegador, armazenada no banco apenas como hash e mostrada em uma tela obrigatória antes da conclusão do cadastro.
- A chave também é lembrada temporariamente na sessão do navegador caso a tela precise ser reaberta.

## Interface

- Adicionado botão de mostrar/ocultar em todos os campos de senha.
- Adicionado aviso de Caps Lock.
- Dados corretos permanecem preenchidos após um erro.
- Somente o campo inválido é limpo e recebe foco.
- Adicionado indicador de força da nova senha.
- Evitado o acúmulo de listeners de teclado ao alternar entre Login, Registro e Recuperação.

## Partidas pendentes

- A fila de liquidação agora registra a conta proprietária.
- Filas de outra conta, expiradas ou referentes a sessões inexistentes/finalizadas são descartadas com segurança.
- O erro antigo `Sessão não encontrada` deixa de gerar um 500 persistente em toda inicialização.

## Banco e Edge Function

- Nova coluna `chrono_profiles.auth_email` para o identificador interno do Supabase Auth.
- Nova RPC transacional `chrono_transfer_account_server`.
- Erros públicos agora retornam código, campo e status estruturados.
- Adicionadas ações `resolve_login` e `repair_account`.
- Recuperação também corrige automaticamente identidades antigas quando a chave válida está disponível.
