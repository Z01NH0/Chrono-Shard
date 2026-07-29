# Revisão técnica — Chrono Shards 8.5.18

## Escopo

A revisão cobriu o fluxo completo de Awakening, Loja Infernal, Nefalem e DOOM entre `index.html`, Edge Function e PostgreSQL.

## Arquitetura aplicada

### Awakening

O banco passa a armazenar:

- jornadas desbloqueadas;
- quantidade de etapas concluídas;
- Ultimate resgatada;
- única etapa ativa da conta;
- métrica, meta, progresso e data de ativação.

O navegador apenas solicita ações. Gastar Chave, ativar etapa, concluir e resgatar Ultimate são decididos pelas RPCs.

### Loja Infernal

O banco passa a armazenar:

- propriedade do Nefalem;
- desbloqueio do DOOM;
- Relíquias Infernais;
- níveis de Legado;
- fila de pactos DOOM;
- skins demoníacas;
- ampliações adquiridas pela Loja Infernal;
- época, identificador, ofertas, estoque vendido e pity da rotação;
- estatísticas do DOOM.

A rotação usa época de dez minutos e uma ordenação determinística por usuário. A compra recebe seção, índice e o identificador daquela rotação; o banco rejeita uma tela vencida antes de escolher o item. O cliente não envia preço, item ou recompensa.

### Partidas DOOM

A sessão guarda os pactos consumidos em `server_context`. O resumo final é sanitizado e combinado com duração, kills e limites de plausibilidade antes da concessão de Lágrimas.

## Correções de integração

- `typeKills.riftTick` passou a usar a telemetria especial, já que o sanitizador genérico de tipos não aceita esse inimigo.
- Boss infernal e Imperador DOOM são classificados antes de o objeto do inimigo ser reciclado.
- O Modo Turbo e o Parry recebem contadores cumulativos próprios.
- O estado local deixa de usar `Math.max` para Chaves e Lágrimas quando a autoridade está ativa.
- A rotação local não substitui a rotação oficial ao expirar ou quando o cache ainda está vazio.
- Uma compra aberta no instante da renovação é recusada pelo identificador da rotação, evitando comprar outro item no mesmo índice.
- O identificador `rico` foi corrigido para `ricocheteador` nas skins do servidor.
- Importação usa uma mesclagem do snapshot oficial e de compatibilidade, em vez de ignorar um deles quando o JSON existe mas está vazio.
- Uma etapa de Awakening já ativa preserva o progresso local disponível na migração, limitado pela meta oficial.
- Skins antigas com prefixo `demon_rico_` são normalizadas para `demon_ricocheteador_`.
- Campos antigos inválidos não interrompem toda a migration.

## Limites conhecidos

- O combate permanece executado no cliente. A versão protege persistência, compras, recebimentos e idempotência, mas não é uma simulação de combate server-side.
- Ampliações também podem ser obtidas pela Loja do Mauro, que ainda não é autoritativa. Para evitar apagar compras legítimas desse sistema, o cliente preserva ampliações locais e adiciona as confirmadas pela Loja Infernal. A migração completa da propriedade global de ampliações deve ser feita junto com Mauro.
- A animação antiga dos baús era responsável por sortear a recompensa no navegador. O sorteio agora acontece no servidor; a interface mostra o resultado confirmado sem usar o sorteio local, evitando recompensa duplicada.

## Resultado

O combo solicitado agora possui uma fonte oficial no Supabase e não depende de o navegador informar saldos, preços, itens recebidos ou etapas concluídas.
