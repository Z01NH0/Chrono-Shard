-- Chrono Shards 8.5.15 — diagnóstico não destrutivo
-- Este arquivo somente consulta. Não altera contas, saves ou missões.

-- 1. Resumo geral
select
  (select count(*) from auth.users) as auth_users,
  (select count(*) from public.chrono_profiles) as profiles,
  (select count(*) from public.chrono_player_state) as player_states,
  (select count(*) from public.chrono_game_sessions) as game_sessions,
  (select count(*) from public.chrono_player_missions) as mission_slots;

-- 2. Usuários Auth sem perfil ou perfil sem estado
select 'auth_without_profile' as issue, u.id as user_id, u.email
from auth.users u
left join public.chrono_profiles p on p.user_id = u.id
where p.user_id is null and coalesce(u.is_anonymous, false) = false
union all
select 'profile_without_state', p.user_id, p.contact_email
from public.chrono_profiles p
left join public.chrono_player_state s on s.user_id = p.user_id
where s.user_id is null;

-- 3. Nomes de usuário ou e-mails duplicados após normalização
select 'duplicate_username' as issue, username_normalized as value, count(*) as total
from public.chrono_profiles
group by username_normalized
having count(*) > 1
union all
select 'duplicate_profile_email', lower(btrim(contact_email_normalized)), count(*)
from public.chrono_profiles
group by lower(btrim(contact_email_normalized))
having count(*) > 1
union all
select 'duplicate_auth_email', lower(btrim(coalesce(email, ''))), count(*)
from auth.users
where coalesce(email, '') <> ''
group by lower(btrim(email))
having count(*) > 1;

-- 4. Divergência entre e-mail do perfil e do Supabase Auth
select
  p.user_id,
  p.username,
  p.contact_email_normalized as profile_email,
  lower(btrim(coalesce(u.email, ''))) as auth_email,
  p.email_ownership_verified,
  p.email_domain_validated
from public.chrono_profiles p
join auth.users u on u.id = p.user_id
where lower(btrim(coalesce(p.contact_email_normalized, '')))
   <> lower(btrim(coalesce(u.email, '')));

-- 5. Estado JSON malformado
select user_id, jsonb_typeof(mission_stats) as mission_stats_type,
       jsonb_typeof(save_data) as save_data_type,
       jsonb_typeof(client_save_data) as client_save_data_type
from public.chrono_player_state
where jsonb_typeof(mission_stats) is distinct from 'object'
   or jsonb_typeof(save_data) is distinct from 'object'
   or (client_save_data is not null and jsonb_typeof(client_save_data) is distinct from 'object');

-- 6. Mais de uma sessão ativa para o mesmo usuário
select user_id, count(*) as active_sessions, array_agg(id order by started_at) as session_ids
from public.chrono_game_sessions
where status = 'active'
group by user_id
having count(*) > 1;

-- 7. Sessões ativas antigas, possivelmente abandonadas
select id, user_id, mode, class_key, started_at,
       extract(epoch from (now() - started_at))::bigint as age_seconds,
       summary -> 'checkpoint' as checkpoint
from public.chrono_game_sessions
where status = 'active'
  and started_at < now() - interval '10 minutes'
order by started_at;

-- 8. Baselines de missão acima da estatística oficial
select
  pm.user_id,
  pm.slot_key,
  pm.mission_id,
  mc.metric,
  pm.baseline,
  public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric) as current_value
from public.chrono_player_missions pm
join public.chrono_player_state ps on ps.user_id = pm.user_id
join public.chrono_mission_catalog mc on mc.mission_id = pm.mission_id
where pm.baseline > public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric);

-- 9. Slots com missão inexistente, dificuldade divergente ou slot duplicado
select pm.*
from public.chrono_player_missions pm
left join public.chrono_mission_catalog mc on mc.mission_id = pm.mission_id
where pm.mission_id is not null
  and (mc.mission_id is null or mc.difficulty <> pm.difficulty);

-- 10. Integridade básica das estatísticas oficiais
select user_id, mission_stats
from public.chrono_player_state
where public.chrono_jsonb_bigint(mission_stats, array['totalKills']) < 0
   or public.chrono_jsonb_bigint(mission_stats, array['bossKills']) < 0
   or public.chrono_jsonb_bigint(mission_stats, array['eliteKills']) < 0
   or public.chrono_jsonb_bigint(mission_stats, array['skillsUsed']) < 0
   or public.chrono_jsonb_bigint(mission_stats, array['bossKills'])
        > public.chrono_jsonb_bigint(mission_stats, array['totalKills'])
   or public.chrono_jsonb_bigint(mission_stats, array['eliteKills'])
        > public.chrono_jsonb_bigint(mission_stats, array['totalKills']);

-- 11. Catálogo ativo por dificuldade
select difficulty, count(*) as active_missions
from public.chrono_mission_catalog
where active = true
group by difficulty
order by difficulty;
