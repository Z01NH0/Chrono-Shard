# Revisão técnica — Chrono Shards 8.5.11

## Problema confirmado

A versão 8.5.10 removia somente as chaves conhecidas do save. Ela deixava no navegador:

- caches completos por `user_id`;
- marcadores de sincronização;
- possíveis chaves legadas de patches antigos;
- dados em memória até a interface ser reconstruída.

Também havia uma rota de saída de sessão pelo listener do Supabase que mostrava o login sem limpar o progresso local.

## Correção aplicada

### Logout explícito

1. Liquida qualquer partida pendente.
2. Envia o snapshot automático mais recente.
3. encerra o refresh da autenticação;
4. remove todas as chaves do `localStorage` e do `sessionStorage`;
5. zera estado, telemetria, timers e rascunhos em memória;
6. recarrega a página sem sessão, abrindo a tela de login.

### Sessão encerrada inesperadamente

O evento `SIGNED_OUT` agora executa a mesma limpeza. Isso também cobre logout em outra aba e token invalidado.

### Troca de conta

Após receber a sessão da conta de destino, o jogo preserva somente as chaves internas de autenticação do Supabase, apaga todos os outros dados do navegador e carrega o save oficial do servidor.

### Cache de conta

O cache `chrono_cloud_account_cache_858:<user_id>` foi removido. Ele duplicava o save no dispositivo e podia restaurar dados antigos. Caches existentes são eliminados no boot.

### Migração defensiva

Uma conta permanente não recebe automaticamente um snapshot local quando falta o marcador de usuário. Esse fallback permanece apenas para convidados, onde é necessário preservar o progresso anterior à criação da conta.

### Usuários anônimos temporários

O servidor remove o usuário anônimo usado apenas como credencial para `login_account` ou `recover_account` depois que a sessão permanente de destino foi criada com sucesso.

## Limites

O logout só é concluído depois que o save atual foi enviado. Se a conexão falhar, o jogo mantém a sessão e os dados locais para evitar perda silenciosa de progresso.
