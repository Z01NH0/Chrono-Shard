-- Chrono Shards 8.5.16 — hidratação autoritativa e renderização consistente das missões
--
-- Corrige a divergência em que chrono_mission_payload devolvia a atribuição e o
-- baseline, mas não devolvia target/progress/done. O cliente autoritativo esperava
-- esses campos e acabava redesenhando cartões corretos como 0/1. Ao alternar para
-- Awakening e voltar, o redesenho local escondia o problema temporariamente.

create or replace function public.chrono_mission_payload(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_slots jsonb;
  v_extreme jsonb;
  v_secret jsonb;
  v_invalid_missions integer := 0;
  v_duplicate_missions integer := 0;
  v_impossible_baselines integer := 0;
begin
  perform public.chrono_prepare_missions_server(p_user_id);

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id;

  if not found then
    raise exception 'Save online não inicializado';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'slotKey', pm.slot_key,
      'slotIndex', pm.slot_index,
      'difficulty', pm.difficulty,
      'missionId', pm.mission_id,
      'baseline', pm.baseline,
      'cooldownUntil', case when pm.cooldown_until is null then 0 else floor(extract(epoch from pm.cooldown_until) * 1000)::bigint end,
      'claimed', pm.claimed,
      'lastMissionId', pm.last_mission_id,
      'metric', c.metric,
      'target', coalesce(c.target, 0),
      'current', public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric),
      'progress', case
        when c.mission_id is null then 0
        when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric)
        else greatest(0, public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) - pm.baseline)
      end,
      'done', case
        when c.mission_id is null then false
        when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) >= c.target
        else greatest(0, public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) - pm.baseline) >= c.target
      end,
      'absoluteProgress', coalesce(c.absolute_progress, false),
      'title', c.title,
      'description', c.description,
      'rewardRelics', coalesce(c.reward_relics, 0),
      'rewardChrono', coalesce(c.reward_chrono, 0),
      'rewardReputation', coalesce(c.reward_reputation, 0)
    ) order by pm.slot_index
  ), '[]'::jsonb)
  into v_slots
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c
    on c.mission_id = pm.mission_id and c.active
  where pm.user_id = p_user_id and pm.slot_key like 'normal:%';

  select jsonb_build_object(
      'slotKey', pm.slot_key,
      'slotIndex', pm.slot_index,
      'difficulty', pm.difficulty,
      'missionId', pm.mission_id,
      'baseline', pm.baseline,
      'cooldownUntil', case when pm.cooldown_until is null then 0 else floor(extract(epoch from pm.cooldown_until) * 1000)::bigint end,
      'claimed', pm.claimed,
      'lastMissionId', pm.last_mission_id,
      'metric', c.metric,
      'target', coalesce(c.target, 0),
      'current', public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric),
      'progress', case
        when c.mission_id is null then 0
        when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric)
        else greatest(0, public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) - pm.baseline)
      end,
      'done', case
        when c.mission_id is null then false
        when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) >= c.target
        else greatest(0, public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) - pm.baseline) >= c.target
      end,
      'absoluteProgress', coalesce(c.absolute_progress, false),
      'title', c.title,
      'description', c.description,
      'rewardRelics', coalesce(c.reward_relics, 0),
      'rewardChrono', coalesce(c.reward_chrono, 0),
      'rewardReputation', coalesce(c.reward_reputation, 0)
    )
  into v_extreme
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c
    on c.mission_id = pm.mission_id and c.active
  where pm.user_id = p_user_id and pm.slot_key = 'extreme';

  select jsonb_build_object(
      'slotKey', pm.slot_key,
      'slotIndex', pm.slot_index,
      'difficulty', pm.difficulty,
      'missionId', pm.mission_id,
      'baseline', pm.baseline,
      'cooldownUntil', 0,
      'claimed', pm.claimed,
      'lastMissionId', pm.last_mission_id,
      'metric', c.metric,
      'target', coalesce(c.target, 0),
      'current', public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric),
      'progress', case
        when c.mission_id is null then 0
        when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric)
        else greatest(0, public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) - pm.baseline)
      end,
      'done', case
        when c.mission_id is null then false
        when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) >= c.target
        else greatest(0, public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric) - pm.baseline) >= c.target
      end,
      'absoluteProgress', coalesce(c.absolute_progress, false),
      'title', c.title,
      'description', c.description,
      'rewardRelics', coalesce(c.reward_relics, 0),
      'rewardChrono', coalesce(c.reward_chrono, 0),
      'rewardReputation', coalesce(c.reward_reputation, 0)
    )
  into v_secret
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c
    on c.mission_id = pm.mission_id and c.active
  where pm.user_id = p_user_id and pm.slot_key = 'secret';

  select count(*)::integer
  into v_invalid_missions
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c
    on c.mission_id = pm.mission_id and c.active
  where pm.user_id = p_user_id
    and pm.mission_id is not null
    and (c.mission_id is null or c.difficulty <> pm.difficulty);

  select coalesce(sum(x.amount - 1), 0)::integer
  into v_duplicate_missions
  from (
    select count(*)::integer as amount
    from public.chrono_player_missions pm
    where pm.user_id = p_user_id
      and pm.slot_key like 'normal:%'
      and pm.mission_id is not null
    group by pm.mission_id
    having count(*) > 1
  ) x;

  select count(*)::integer
  into v_impossible_baselines
  from public.chrono_player_missions pm
  join public.chrono_mission_catalog c
    on c.mission_id = pm.mission_id and c.active
  where pm.user_id = p_user_id
    and not c.absolute_progress
    and pm.baseline > public.chrono_metric_value(coalesce(v_state.mission_stats, '{}'::jsonb), c.metric);

  return jsonb_build_object(
    'enabled', v_state.mission_rewards_enabled,
    'reputation', v_state.mission_reputation,
    'stats', coalesce(v_state.mission_stats, '{}'::jsonb),
    'slots', v_slots,
    'extreme', coalesce(v_extreme, '{}'::jsonb),
    'secret', coalesce(v_secret, '{}'::jsonb),
    'serverTime', floor(extract(epoch from now()) * 1000)::bigint,
    'revision', v_state.revision,
    'audit', jsonb_build_object(
      'invalidMissions', v_invalid_missions,
      'duplicateMissions', v_duplicate_missions,
      'impossibleBaselines', v_impossible_baselines
    ),
    'state', to_jsonb(v_state)
  );
end;
$$;

-- Repara baselines antigos que ficaram acima do contador oficial. Sem isso a
-- missão só começaria a progredir depois de o jogador alcançar novamente um
-- número impossível.
update public.chrono_player_missions pm
set baseline = public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric),
    updated_at = now()
from public.chrono_player_state ps,
     public.chrono_mission_catalog mc
where ps.user_id = pm.user_id
  and mc.mission_id = pm.mission_id
  and not mc.absolute_progress
  and pm.baseline > public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric);

revoke all on function public.chrono_mission_payload(uuid) from public, anon, authenticated;
grant execute on function public.chrono_mission_payload(uuid) to service_role;

comment on function public.chrono_mission_payload(uuid) is
  'Retorna atribuições e progresso autoritativo completo das missões, incluindo target/progress/done e relógio do servidor.';
