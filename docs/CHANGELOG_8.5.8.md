# Chrono Shards 8.5.8

## Contas

- Tela Chrono ID com login, registro, convidado e recuperação.
- Login por nome de usuário e senha.
- Nome de usuário e e-mail de contato únicos.
- Conversão da sessão anônima em conta permanente sem trocar o `user_id`.
- Chave criptograficamente aleatória de recuperação; somente o hash fica no banco.
- Troca de senha, rotação da chave e logout.
- Limite de tentativas de recuperação por sessão solicitante.

## Save

- Remoção completa da interface antiga de arquivos JSON.
- Migração, carregamento e salvamento automáticos.
- Snapshot de compatibilidade separado do save autoritativo.
- Cache local por conta para reduzir risco de perda em falhas temporárias.
- Sincronização agrupada e adiada durante a partida.
- Inclusão do progresso dos módulos de tutorial no save.

## Segurança e correções

- Contas novas não podem importar moedas, High Score, códigos ou personagens protegidos do navegador.
- Snapshot limitado a 512 KB.
- Correção do fluxo de troca de senha.
- Correção da troca entre contas para impedir mistura de saves.
- Remoção do painel técnico antigo da economia e do observador correspondente.
- Textos técnicos da interface substituídos por mensagens naturais.
