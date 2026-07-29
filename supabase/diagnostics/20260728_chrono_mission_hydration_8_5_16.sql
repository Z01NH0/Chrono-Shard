-- Chrono Shards 8.5.16 — diagnóstico somente leitura das missões

-- 1. A função instalada precisa mencionar os campos usados pelo cliente.
select
  position('''target''' in pg_get_functiondef('public.chrono_mission_payload(uuid)'::regprocedure)) > 0 as returns_target,
  position('''progress''' in pg_get_functiondef('public.chrono_mission_payload(uuid)'::regprocedure)) > 0 as returns_progress,
  position('''done''' in pg_get_functiondef('public.chrono_mission_payload(uuid)'::regprocedure)) > 0 as returns_done,
  position('''serverTime''' in pg_get_functiondef('public.chrono_mission_payload(uuid)'::regprocedure)) > 0 as returns_server_time;

-- 2. Slots inválidos ou apontando para catálogo inativo.
select pm.user_id, pm.slot_key, pm.difficulty, pm.mission_id
from public.chrono_player_missions pm
left join public.chrono_mission_catalog mc
  on mc.mission_id = pm.mission_id and mc.active
where pm.mission_id is not null
  and (mc.mission_id is null or mc.difficulty <> pm.difficulty)
order by pm.user_id, pm.slot_index;

-- 3. Baselines acima do contador oficial. O resultado esperado é zero linhas.
select
  pm.user_id,
  pm.slot_key,
  pm.mission_id,
  mc.metric,
  pm.baseline,
  public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric) as current_value
from public.chrono_player_missions pm
join public.chrono_mission_catalog mc on mc.mission_id = pm.mission_id and mc.active
join public.chrono_player_state ps on ps.user_id = pm.user_id
where not mc.absolute_progress
  and pm.baseline > public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric)
order by pm.user_id, pm.slot_index;

-- 4. Missões normais duplicadas na mesma conta.
select user_id, mission_id, count(*) as duplicated_slots
from public.chrono_player_missions
where slot_key like 'normal:%' and mission_id is not null
group by user_id, mission_id
having count(*) > 1
order by duplicated_slots desc, user_id;

-- 5. Estado detalhado de todos os contratos ativos.
select
  pm.user_id,
  pm.slot_key,
  pm.slot_index,
  pm.difficulty,
  pm.mission_id,
  mc.title,
  mc.metric,
  pm.baseline,
  public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric) as current_value,
  case
    when mc.absolute_progress then public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric)
    else greatest(0, public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric) - pm.baseline)
  end as progress,
  mc.target,
  case
    when mc.absolute_progress then public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric) >= mc.target
    else greatest(0, public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric) - pm.baseline) >= mc.target
  end as done,
  pm.cooldown_until,
  pm.updated_at
from public.chrono_player_missions pm
join public.chrono_player_state ps on ps.user_id = pm.user_id
left join public.chrono_mission_catalog mc on mc.mission_id = pm.mission_id
order by pm.user_id, pm.slot_index;

-- 6. Partidas ativas com checkpoint muito antigo. Podem indicar queda real.
select
  user_id,
  id as session_id,
  mode,
  class_key,
  started_at,
  to_timestamp(public.chrono_jsonb_bigint(summary -> 'checkpoint', array['savedAt']) / 1000.0) as checkpoint_at,
  summary -> 'checkpoint' as checkpoint
from public.chrono_game_sessions
where status = 'active'
order by started_at;
