# Chrono Shards — ativação do Supabase

O HTML já contém:

- Project URL: `https://favrbugywlamhitktocy.supabase.co`
- Publishable key fornecida pelo projeto.
- Login anônimo.
- Cliente da Edge Function `game-api`.
- Tela de status, migração inicial e sincronização dentro de Configurações.

## 1. Habilitar login anônimo

No painel do Supabase:

`Authentication → Providers → Anonymous Sign-Ins → Enable`

## 2. Criar o banco

Abra `SQL Editor`, crie uma consulta e cole todo o conteúdo de:

`supabase/migrations/20260724_chrono_cloud.sql`

Execute uma única vez.

## 3. Publicar a Edge Function

### Pelo painel

1. Abra `Edge Functions`.
2. Clique em `Deploy a new function` → `Via Editor`.
3. Nome: `game-api`.
4. Cole o conteúdo de `supabase/functions/game-api/index.ts`.
5. Nas configurações da função, desative a verificação JWT da plataforma. A própria função valida o usuário com `withSupabase({ auth: 'user' })`.
6. Publique.

### Pela CLI

```bash
supabase login
supabase link --project-ref favrbugywlamhitktocy
supabase db push
supabase functions deploy game-api --no-verify-jwt
```

## 4. Testar no jogo

Sirva a pasta por HTTP. Não abra somente por `file://`.

Exemplo:

```bash
python -m http.server 5500
```

Abra `http://localhost:5500`, vá em **Configurações** e confira o cartão **Save Online / Supabase**.

## 5. Fazer a migração inicial

No cartão do Supabase, clique em **Migrar save local**. A migração pode ser feita apenas uma vez por usuário anônimo.

O banco começa em `authority_mode = migration`. Isso é intencional: o save do servidor ainda não substitui automaticamente o local enquanto compras, missões e recompensas antigas continuarem sendo calculadas no navegador. O campo `run_results_enabled` também começa como `false`, portanto resumos de partida são registrados sem alterar moedas ou high score oficial.

## 6. Quando ativar o modo autoritativo

Somente depois de migrar as ações permanentes para chamadas de servidor, altere o jogador para:

```sql
update public.chrono_player_state
set authority_mode = 'authoritative',
    run_results_enabled = true
where user_id = 'UUID_DO_JOGADOR';
```

Nesse modo, o HTML carrega o snapshot do servidor e sobrescreve o cache local no boot.

## Segurança

- A Publishable Key pode ficar no HTML.
- Nunca coloque `secret key`, `service_role` ou senha do banco no HTML.
- Não crie políticas de escrita direta para `anon` ou `authenticated` nessas tabelas.
- O sistema de AES local continua apenas como backup antigo; ele não vira fonte oficial do progresso.
