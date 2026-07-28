# Changelog 8.5.10

## Login e conta

- Login por nome de usuário agora é processado pela Edge Function.
- O navegador recebe os tokens e abre a sessão com `setSession`, sem chamar diretamente o login por e-mail técnico.
- Registro e reparo convertem a conta anônima no mesmo `user_id`, preservando o progresso.
- Removidas chamadas de logout que geravam `403` em sessões antigas ou inválidas.
- Chave de recuperação é mostrada antes da entrada automática.
- Alteração de senha e rotação da chave validam a senha no servidor.
- Perfis com `auth_email` desatualizado são corrigidos automaticamente.

## Partidas e missões

- Adicionada telemetria direta de mortes, bosses, elites, tipos de inimigo e habilidades.
- Contagens duplicadas criadas por patches antigos não são mais enviadas ao servidor.
- A soma de inimigos por tipo é limitada ao total de abates da partida.
- Filas antigas, sessões inexistentes e runs já finalizadas são descartadas sem erro HTTP.
- Resumos impossíveis são marcados como rejeitados e não ficam sendo reenviados infinitamente.
- Missões passam a receber `totalKills`, classe, bosses, elites, habilidades e tipos somente após uma liquidação aceita.

## Interface e estabilidade

- Todos os acessos a `KeyboardEvent.key.toLowerCase()` agora toleram eventos sintéticos sem `key`.
- Adicionado favicon vazio para eliminar o `404 /favicon.ico`.
- Mantidos botão de mostrar senha, Caps Lock, força de senha e preservação seletiva dos campos.
