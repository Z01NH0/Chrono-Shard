-- Chrono Shards 8.5.14 — diagnóstico somente leitura
-- Execute após instalar a migration 011 e publicar a game-api atualizada.

-- 1) E-mails repetidos nos perfis, considerando caixa e espaços.
-- Resultado esperado: zero linhas.
select lower(btrim(contact_email_normalized)) as email_normalized, count(*) as total,
       array_agg(user_id order by created_at) as users
from public.chrono_profiles
group by lower(btrim(contact_email_normalized))
having count(*) > 1;

-- 2) E-mails repetidos no Supabase Auth.
-- Resultado esperado: zero linhas.
select lower(btrim(email)) as email_normalized, count(*) as total,
       array_agg(id order by created_at) as users
from auth.users
where email is not null
group by lower(btrim(email))
having count(*) > 1;

-- 3) Divergência entre perfil e identidade Auth.
-- Resultado esperado: zero linhas.
select
  p.user_id,
  p.username,
  lower(btrim(p.contact_email_normalized)) as profile_email,
  lower(btrim(u.email)) as auth_email,
  p.email_domain_validated,
  p.email_ownership_verified
from public.chrono_profiles p
left join auth.users u on u.id = p.user_id
where u.id is null
   or lower(btrim(coalesce(u.email, ''))) <> lower(btrim(p.contact_email_normalized))
order by p.created_at desc;

-- 4) Contas técnicas antigas que ainda precisam ser reparadas.
-- Resultado esperado: zero linhas.
select p.user_id, p.username, p.contact_email_normalized, u.email as auth_email
from public.chrono_profiles p
join auth.users u on u.id = p.user_id
where lower(coalesce(u.email, '')) like '%@chrono-shards.invalid';

-- 5) Estado agregado das estatísticas de missão.
select
  user_id,
  revision,
  mission_stats_updated_at,
  public.chrono_jsonb_bigint(coalesce(mission_stats, '{}'::jsonb), array['totalKills']) as total_kills,
  public.chrono_jsonb_bigint(coalesce(mission_stats, '{}'::jsonb), array['bossKills']) as boss_kills,
  public.chrono_jsonb_bigint(coalesce(mission_stats, '{}'::jsonb), array['eliteKills']) as elite_kills,
  public.chrono_jsonb_bigint(coalesce(mission_stats, '{}'::jsonb), array['skillsUsed']) as skills_used,
  public.chrono_jsonb_bigint(coalesce(mission_stats, '{}'::jsonb), array['classKills','assault']) as assault_kills,
  updated_at
from public.chrono_player_state
order by updated_at desc;

-- 6) Sessões e checkpoints recentes. Uma partida ativa deve atualizar savedAt.
-- checkpointRecovered=true indica que os feitos de uma partida interrompida
-- foram preservados sem conceder moedas.
select
  id,
  user_id,
  status,
  class_key,
  started_at,
  ended_at,
  summary -> 'checkpoint' as checkpoint,
  summary ->> 'checkpointRecovered' as checkpoint_recovered,
  summary ->> 'checkpointRecoveredAt' as checkpoint_recovered_at
from public.chrono_game_sessions
order by started_at desc
limit 50;

-- 7) Sessões ativas com checkpoint parado há mais de 45 segundos.
-- Elas serão recuperadas ao abrir Missões ou iniciar uma nova partida.
select
  id,
  user_id,
  class_key,
  started_at,
  to_timestamp(public.chrono_jsonb_bigint(summary -> 'checkpoint', array['savedAt']) / 1000.0) as checkpoint_at,
  summary -> 'checkpoint' as checkpoint
from public.chrono_game_sessions
where status = 'active'
  and public.chrono_jsonb_bigint(summary -> 'checkpoint', array['savedAt']) > 0
  and to_timestamp(public.chrono_jsonb_bigint(summary -> 'checkpoint', array['savedAt']) / 1000.0) <= now() - interval '45 seconds'
order by started_at;

-- 8) Baselines de missão impossíveis. Resultado esperado: zero linhas.
select
  pm.user_id,
  pm.slot_key,
  pm.mission_id,
  pm.baseline,
  mc.metric,
  public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric) as current_value
from public.chrono_player_missions pm
join public.chrono_player_state ps on ps.user_id = pm.user_id
join public.chrono_mission_catalog mc on mc.mission_id = pm.mission_id
where pm.baseline > public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric);

-- 9) Contratos inválidos ou em dificuldade errada. Resultado esperado: zero linhas.
select pm.user_id, pm.slot_key, pm.mission_id, pm.difficulty, mc.difficulty as catalog_difficulty
from public.chrono_player_missions pm
left join public.chrono_mission_catalog mc on mc.mission_id = pm.mission_id
where mc.mission_id is null or pm.difficulty <> mc.difficulty;

-- 10) Exemplo da missão “Linha de Frente”. Ela exige 24 abates COM Assault.
select
  ps.user_id,
  public.chrono_jsonb_bigint(ps.mission_stats, array['classKills','assault']) as assault_kills,
  pm.baseline,
  greatest(0, public.chrono_jsonb_bigint(ps.mission_stats, array['classKills','assault']) - pm.baseline) as progress,
  mc.target,
  greatest(0, public.chrono_jsonb_bigint(ps.mission_stats, array['classKills','assault']) - pm.baseline) >= mc.target as done
from public.chrono_player_missions pm
join public.chrono_player_state ps on ps.user_id = pm.user_id
join public.chrono_mission_catalog mc on mc.mission_id = pm.mission_id
where pm.mission_id = 'e_assault24';

-- 11) Recibos duplicados não devem existir por causa da chave primária.
select user_id, request_id, count(*) as total
from public.chrono_action_receipts
group by user_id, request_id
having count(*) > 1;

-- 12) Identidades Auth órfãs criadas por tentativas interrompidas.
-- A nova game-api remove automaticamente apenas candidatas marcadas pelo Chrono.
select
  u.id,
  u.email,
  u.created_at,
  u.raw_user_meta_data,
  u.raw_app_meta_data
from auth.users u
left join public.chrono_profiles p on p.user_id = u.id
left join public.chrono_player_state ps on ps.user_id = u.id
where p.user_id is null
  and ps.user_id is null
  and u.is_anonymous is not true
  and (
    coalesce((u.raw_app_meta_data ->> 'chrono_account_pending')::boolean, false)
    or (
      coalesce((u.raw_app_meta_data ->> 'chrono_email_ownership_verified')::boolean, false) is false
      and u.raw_user_meta_data ? 'username'
      and u.raw_user_meta_data ? 'contact_email'
    )
  )
order by u.created_at desc;
