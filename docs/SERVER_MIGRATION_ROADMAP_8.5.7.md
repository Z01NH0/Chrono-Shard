# Sistemas que ainda precisam ir para o banco

## Prioridade 1 — moedas e compras permanentes

1. **Loja Infernal e Nefalem**
   - `sinnerTears830` / `doomFragments`.
   - Compra do Nefalem.
   - Relíquias, buffs, legado, baús e skins da loja.
   - Hoje esses dados ainda podem ser alterados localmente.

2. **Loja do Mauro**
   - Rotação oficial baseada no relógio do servidor.
   - Compra de relíquias, augments, skins e baús.
   - Controle de estoque e recibos idempotentes.

3. **Awakening**
   - Chaves, contratos, etapas concluídas, ultimate resgatada e recompensa.
   - O saldo de chaves já existe no banco, mas o consumo e o desbloqueio ainda não são totalmente autoritativos.

## Prioridade 2 — recompensas de progressão

4. **Bestiário**
   - Contagem oficial por inimigo.
   - Recompensa resgatada por entrada.
   - Bloqueio de resgate duplicado.

5. **Maestria de personagens**
   - XP, nível, trilha, estatísticas e recompensas.
   - O servidor deve derivar XP das sessões aceitas, não receber o nível final do navegador.

6. **Relíquias, augments, skins e catálogo de power-ups**
   - Propriedade permanente.
   - Seleção pode continuar em cache local, mas a posse precisa vir do servidor.

7. **Baús fora de partidas**
   - Criação da recompensa no servidor.
   - Seed/resultado oficial e recibo único.

## Prioridade 3 — desbloqueios e modos

8. **Fissura secreta e requisitos de personagens**
   - Derrota do Lost Emperor.
   - Shadow Child, Moon Slayer e Stellar Emperor.

9. **DOOM**
   - Recorde, lágrimas, marcos, minibosses e recompensas permanentes.

10. **Códigos mestre e desbloqueios globais**
    - O código mestre já registra moedas e flags básicas no banco.
    - Skins, bestiário, Awakening, relíquias e power-ups liberados localmente pelo código ainda precisam ser gravados em tabelas oficiais.

## Dados que podem permanecer locais

- Volume, qualidade gráfica e controles.
- Mira e preferências visuais.
- Tutoriais já vistos.
- Cache da interface.

Esses dados não afetam economia, ranking ou propriedade de conteúdo.
