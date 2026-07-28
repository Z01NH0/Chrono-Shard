-- Chrono Shards 8.5.9 — auditoria somente leitura
-- Não altera nenhuma tabela.

-- 1. Perfis e identidades inconsistentes. O resultado esperado após os reparos é 0 linhas.
select
  p.username,
  p.user_id,
  p.auth_email as profile_auth_email,
  u.email as auth_user_email,
  u.is_anonymous,
  exists (
    select 1
    from auth.identities i
    where i.user_id = p.user_id
      and i.provider = 'email'
  ) as has_email_identity
from public.chrono_profiles p
join auth.users u on u.id = p.user_id
where u.is_anonymous is true
   or not exists (
     select 1
     from auth.identities i
     where i.user_id = p.user_id
       and i.provider = 'email'
   )
   or lower(coalesce(u.email, '')) <> lower(coalesce(p.auth_email, ''));

-- 2. Perfis órfãos. Esperado: 0.
select count(*) as orphan_profiles
from public.chrono_profiles p
left join auth.users u on u.id = p.user_id
where u.id is null;

-- 3. Estados sem usuário Auth. Esperado: 0.
select count(*) as orphan_player_states
from public.chrono_player_state s
left join auth.users u on u.id = s.user_id
where u.id is null;

-- 4. Contas permanentes sem estado de jogo. Esperado: 0.
select p.username, p.user_id
from public.chrono_profiles p
left join public.chrono_player_state s on s.user_id = p.user_id
where s.user_id is null;

-- 5. Sessões de partida ativas antigas. Revise qualquer linha retornada.
select id, user_id, mode, class_key, started_at
from public.chrono_game_sessions
where status = 'active'
  and started_at < now() - interval '24 hours'
order by started_at;

-- 6. Duplicidades lógicas. Todas devem retornar 0 linhas.
select username_normalized, count(*)
from public.chrono_profiles
group by username_normalized
having count(*) > 1;

select contact_email_normalized, count(*)
from public.chrono_profiles
group by contact_email_normalized
having count(*) > 1;

select lower(auth_email), count(*)
from public.chrono_profiles
where auth_email is not null
group by lower(auth_email)
having count(*) > 1;

-- 7. Resumo de contas.
select
  count(*) as total_profiles,
  count(*) filter (where u.is_anonymous is false) as permanent_auth_users,
  count(*) filter (where u.is_anonymous is true) as profiles_still_anonymous
from public.chrono_profiles p
join auth.users u on u.id = p.user_id;
