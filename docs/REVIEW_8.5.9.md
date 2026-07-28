# Revisão técnica — Chrono Shards 8.5.9

## Causa do login quebrado na 8.5.8

A 8.5.8 tentava converter o usuário anônimo com uma atualização administrativa de e-mail e senha. Isso podia alterar o registro em `auth.users`, mas não garantir uma identidade de autenticação por e-mail. O perfil do jogo era criado, porém `signInWithPassword` não encontrava uma identidade válida e o jogador não conseguia entrar.

A 8.5.9 cria uma nova identidade Auth permanente, usa um UUID definido previamente e move todos os dados públicos em uma transação antes de remover o usuário anônimo antigo.

## Fluxo de reparo

Quando existe `chrono_profiles` para a sessão atual, mas o usuário Auth não possui identidade `email` ou ainda está marcado como anônimo, `load_account` retorna `needsRepair=true`.

O cliente abre **Concluir Conta** e solicita uma nova senha. Uma nova chave de recuperação é criada e exibida. O servidor cria a identidade permanente e transfere:

- `chrono_player_state`
- `chrono_game_sessions`
- `chrono_action_receipts`
- `chrono_player_missions`
- `chrono_redeemed_codes`
- `chrono_profiles`

A função SQL é transacional e só pode ser executada por `service_role` através da Edge Function.

## Erro de liquidação pendente

A fila antiga `chrono_cloud_pending_run_854` não registrava proprietário e podia sobreviver após troca de usuário, atualização ou sessão abandonada. O boot tentava liquidá-la indefinidamente.

Agora a fila contém `ownerUserId`, expira em 72 horas e é removida quando o servidor responde que a sessão não existe, já foi finalizada ou pertence a outra conta.

## Formulários

Foram verificados os fluxos de Login, Registro, Recuperação, Reparo e Gerenciamento:

- botão de mostrar senha em todos os campos;
- aviso de Caps Lock;
- estado separado para cada tela;
- preservação de campos corretos;
- limpeza somente do campo inválido;
- foco e seleção do campo a corrigir;
- confirmação de senha limpa isoladamente quando não coincide;
- usuário preservado quando a senha de login está errada;
- listeners de Enter não se acumulam.

## Chave de recuperação

A chave é gerada com `crypto.getRandomValues`, possui 24 caracteres de um alfabeto sem caracteres ambíguos e é apresentada no formato `CS-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`.

A Edge Function recebe a chave somente para calcular o hash SHA-256 ligado ao nome normalizado. O banco não guarda o valor original.

## Limitações honestas

A validação estática e os smoke tests de interface não substituem uma execução real no projeto Supabase do usuário. A migration 008 e a Edge Function 8.5.9 precisam ser publicadas antes do teste.

Uma conta 8.5.8 que já perdeu a sessão local e nunca recebeu uma chave não pode ser recuperada automaticamente com segurança. Sem a sessão ou a chave, não existe prova confiável de propriedade. Durante a atualização, não se deve limpar os dados do site nem sair da sessão antiga antes de concluir o reparo.
