# Instalação — Chrono Shards 8.5.19

Esta versão exige a migration 014 e a nova Edge Function.

## Antes de atualizar

Faça backup das tabelas abaixo pelo painel do Supabase:

- `chrono_player_state`;
- `chrono_player_awakenings`;
- `chrono_player_awakening_active`;
- `chrono_progression_run_counters`;
- `chrono_action_receipts`.

## 1. Execute somente a migration nova

Abra **Supabase → SQL Editor → New query** e execute todo o arquivo:

```text
supabase/migrations/20260728001400_chrono_awakening_hydration_hardening.sql
```

A migration 013 precisa ter sido instalada anteriormente.

Não execute novamente as migrations 001–013.

A migration 014:

- repara estados antigos inconsistentes;
- devolve uma chave quando precisa remover uma etapa ativa inválida;
- adiciona validação de posse do personagem;
- corrige a hidratação do payload;
- impede regressão e dupla contagem de checkpoints.

## 2. Atualize a Edge Function

Abra **Edge Functions → game-api → Edit**.

Apague completamente o código atual e cole o conteúdo de:

```text
supabase/functions/game-api/index.ts
```

Clique em **Deploy updates**.

## 3. Atualize o jogo

Substitua o projeto pelo pacote 8.5.19 ou, no mínimo, substitua o `index.html`.

Abra usando um parâmetro de versão para evitar cache:

```text
index.html?v=8519
```

Depois pressione `Ctrl + F5`.

## 4. Execute o diagnóstico

No SQL Editor, execute:

```text
supabase/diagnostics/20260728_chrono_awakening_review_8_5_19.sql
```

As consultas de inconsistência numeradas de 2 a 10 devem retornar zero linhas. A primeira deve indicar 50 etapas e 10 personagens.

## Teste funcional recomendado

1. Entre em uma conta existente.
2. Abra Missões → Awakening.
3. Anote a etapa ativa e o progresso.
4. Atualize a página.
5. Abra diretamente a aba de Awakening.
6. Confirme que a etapa e o progresso aparecem sem alternar para outra aba.
7. Jogue uma partida com o personagem correto.
8. Realize parte do objetivo e mantenha a tela aberta após a partida.
9. Confirme que o progresso é atualizado automaticamente.
10. Complete a etapa e resgate.
11. Atualize a página e confirme que a próxima etapa continua correta.
12. Selecione um personagem não adquirido e confirme que a jornada aparece bloqueada.

## Observação

Não limpe os dados do navegador antes do primeiro carregamento após a atualização. O servidor continuará sendo a fonte oficial, mas preservar a sessão evita a necessidade de entrar novamente durante o teste.
