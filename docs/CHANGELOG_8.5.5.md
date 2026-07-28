# Chrono Shards 8.5.5

## Missões autoritativas

- Missões fáceis, médias, difíceis, extremas e a missão secreta agora são atribuídas pelo PostgreSQL.
- O servidor mantém os contratos ativos, baseline, cooldown, reputação e estatísticas oficiais.
- O botão de resgate envia somente o slot da missão; o navegador não escolhe a recompensa.
- Relíquias, Fragmentos Chrono e Reputação são adicionados em uma transação.
- Cada resgate usa `requestId` e não pode ser aplicado duas vezes.
- A interface local recebe os contratos oficiais ao abrir a tela de Missões e depois de cada partida liquidada.

## Códigos autoritativos

- O código digitado é normalizado e convertido em SHA-256 dentro da Edge Function.
- O PostgreSQL decide se o hash existe, qual recompensa pertence a ele e se a conta já o utilizou.
- O cliente não envia quantidade de Relíquias, Fragmentos Chrono, Chaves ou Lágrimas.
- O histórico de códigos resgatados agora também é registrado na tabela `chrono_redeemed_codes`.
- Códigos já marcados como usados no save migrado são importados para a tabela, impedindo resgate duplicado após a atualização.
- O código mestre preserva os desbloqueios locais antigos somente depois de ser validado pelo servidor.

## Estatísticas de missão

- A liquidação de partida agora envia deltas de bosses, elites, habilidades usadas e tipos de inimigos derrotados.
- O servidor valida as contagens e acumula `mission_stats`.
- Progresso de classe é calculado usando a classe vinculada à sessão criada no servidor.

## Supabase

- Novo SQL: `20260724_chrono_missions_codes.sql`.
- Nova fase da Edge Function: `missions-codes-8.5.5`.
- Novas ações: `load_missions`, `claim_mission` e `redeem_code`.
- Usuários que já tinham a carteira oficial recebem `mission_rewards_enabled` e `code_rewards_enabled` automaticamente.

## Compatibilidade

- Não é necessário migrar o save novamente nem reativar a proteção.
- Os contratos locais ativos podem ser substituídos uma única vez pelos contratos oficiais do servidor na primeira abertura da tela de Missões.
- Bestiário, recompensas de Awakening, Loja do Mauro, Loja Infernal e outros resgates permanentes ainda precisam de endpoints próprios.
