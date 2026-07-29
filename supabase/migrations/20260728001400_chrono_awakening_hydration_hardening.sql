-- Chrono Shards 8.5.19
-- Revisão profunda do Awakening: hidratação autoritativa, posse de personagem,
-- reparo de estados inconsistentes e validação das etapas.
-- Execute uma única vez após a migration 20260728001300.

begin;

create or replace function public.chrono_awakening_character_owned_server(
  p_user_id uuid,
  p_character_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_save jsonb := '{}'::jsonb;
  v_meta jsonb := '{}'::jsonb;
  v_unlocks jsonb := '[]'::jsonb;
begin
  if p_character_key is null or not exists (
    select 1
    from public.chrono_awakening_catalog c
    where c.character_key = p_character_key
  ) then
    return false;
  end if;

  if p_character_key = any(array['assault','sniper']::text[]) then
    return true;
  end if;

  select coalesce(s.save_data, '{}'::jsonb)
  into v_save
  from public.chrono_player_state s
  where s.user_id = p_user_id;

  if not found then
    return false;
  end if;

  v_meta := case
    when jsonb_typeof(v_save -> 'chrono_v4_meta') = 'object'
      then v_save -> 'chrono_v4_meta'
    else '{}'::jsonb
  end;

  if lower(coalesce(v_meta ->> 'allUnlocked', 'false')) = 'true'
     or lower(coalesce(v_meta ->> 'allInUnlocked', 'false')) = 'true' then
    return true;
  end if;

  v_unlocks := case
    when jsonb_typeof(v_save -> 'chrono_v4_meta_class_unlocks_v3') = 'array'
      then v_save -> 'chrono_v4_meta_class_unlocks_v3'
    else '[]'::jsonb
  end;

  return v_unlocks @> jsonb_build_array(p_character_key);
end;
$$;

-- Mantém o catálogo como fonte das métricas e metas, inclusive após alterações futuras.
update public.chrono_player_awakening_active a
set metric = c.metric,
    target = c.target,
    baseline = case when c.metric = 'maxWave' then 0 else greatest(0, a.baseline) end,
    progress = least(greatest(0, a.progress), c.target),
    updated_at = now()
from public.chrono_awakening_catalog c
where c.character_key = a.character_key
  and c.stage = a.stage
  and (
    a.metric is distinct from c.metric
    or a.target is distinct from c.target
    or a.progress < 0
    or a.progress > c.target
    or (c.metric = 'maxWave' and a.baseline <> 0)
  );

-- Toda etapa ativa precisa possuir uma linha de jornada correspondente.
insert into public.chrono_player_awakenings(
  user_id, character_key, journey_unlocked, completed_stages, ultimate_unlocked
)
select a.user_id, a.character_key, true, 0, false
from public.chrono_player_awakening_active a
on conflict (user_id, character_key) do update
set journey_unlocked = true,
    updated_at = now();

-- Uma Ultimate já liberada implica jornada completa.
update public.chrono_player_awakenings
set journey_unlocked = true,
    completed_stages = 5,
    updated_at = now()
where ultimate_unlocked = true
  and (journey_unlocked = false or completed_stages <> 5);

-- Jornadas com progresso também precisam permanecer marcadas como desbloqueadas.
update public.chrono_player_awakenings
set journey_unlocked = true,
    updated_at = now()
where journey_unlocked = false
  and completed_stages > 0;

-- Repara etapas ativas impossíveis. Como a etapa consumiu uma chave, ela é devolvida.
create temporary table chrono_removed_awakening_8519(
  user_id uuid primary key,
  reason text not null
) on commit drop;

insert into chrono_removed_awakening_8519(user_id, reason)
select a.user_id,
       case
         when not public.chrono_awakening_character_owned_server(a.user_id, a.character_key)
           then 'character_not_owned'
         when p.ultimate_unlocked then 'ultimate_already_unlocked'
         when p.completed_stages >= a.stage then 'stage_already_completed'
         when a.stage <> p.completed_stages + 1 then 'stage_out_of_order'
         else 'invalid_active_stage'
       end
from public.chrono_player_awakening_active a
join public.chrono_player_awakenings p
  on p.user_id = a.user_id
 and p.character_key = a.character_key
where not public.chrono_awakening_character_owned_server(a.user_id, a.character_key)
   or p.ultimate_unlocked
   or p.completed_stages >= a.stage
   or a.stage <> p.completed_stages + 1
on conflict (user_id) do nothing;

delete from public.chrono_player_awakening_active a
using chrono_removed_awakening_8519 r
where a.user_id = r.user_id;

update public.chrono_player_state s
set awakening_keys = s.awakening_keys + 1,
    revision = s.revision + 1
from chrono_removed_awakening_8519 r
where s.user_id = r.user_id;

alter table public.chrono_player_awakening_active
  drop constraint if exists chrono_player_awakening_active_progress_target_check;

alter table public.chrono_player_awakening_active
  add constraint chrono_player_awakening_active_progress_target_check
  check (progress between 0 and target);

create or replace function public.chrono_progression_payload_server(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_inf public.chrono_player_infernal%rowtype;
  v_journeys jsonb;
  v_active jsonb;
begin
  insert into public.chrono_player_state(user_id)
  values(p_user_id)
  on conflict(user_id) do nothing;

  v_inf := public.chrono_refresh_infernal_locked_server(p_user_id);

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id;

  select coalesce(
    jsonb_object_agg(
      c.character_key,
      jsonb_build_object(
        'owned', public.chrono_awakening_character_owned_server(p_user_id, c.character_key),
        'journeyUnlocked', coalesce(p.journey_unlocked, false),
        'completedStages', coalesce(p.completed_stages, 0),
        'ultimateUnlocked', coalesce(p.ultimate_unlocked, false),
        'updatedAt', case
          when p.updated_at is null then null
          else floor(extract(epoch from p.updated_at) * 1000)
        end
      )
    ),
    '{}'::jsonb
  )
  into v_journeys
  from (
    select distinct character_key
    from public.chrono_awakening_catalog
  ) c
  left join public.chrono_player_awakenings p
    on p.user_id = p_user_id
   and p.character_key = c.character_key;

  select case
    when a.user_id is null then 'null'::jsonb
    else jsonb_build_object(
      'characterKey', a.character_key,
      'stage', a.stage,
      'metric', a.metric,
      'target', a.target,
      'baseline', a.baseline,
      'progress', least(a.progress, a.target),
      'done', a.progress >= a.target,
      'startedAt', floor(extract(epoch from a.started_at) * 1000),
      'updatedAt', floor(extract(epoch from a.updated_at) * 1000)
    )
  end
  into v_active
  from (select p_user_id as user_id) u
  left join public.chrono_player_awakening_active a
    on a.user_id = u.user_id;

  return jsonb_build_object(
    'serverTime', floor(extract(epoch from clock_timestamp()) * 1000),
    'revision', v_state.revision,
    'awakening', jsonb_build_object(
      'keys', v_state.awakening_keys,
      'journeys', v_journeys,
      'active', v_active
    ),
    'infernal', jsonb_build_object(
      'tears', v_state.sinner_tears,
      'nefalemOwned', v_inf.nefalem_owned,
      'doomUnlocked', v_inf.doom_unlocked,
      'infernalRelics', to_jsonb(v_inf.infernal_relics),
      'legacyLevels', v_inf.legacy_levels,
      'queuedDoomBuffs', to_jsonb(v_inf.queued_doom_buffs),
      'demonSkins', to_jsonb(v_inf.demon_skins),
      'infernalAugments', to_jsonb(v_inf.infernal_augments),
      'doomStats', v_inf.doom_stats,
      'shop', jsonb_build_object(
        'version', 2,
        'created', v_inf.shop_epoch * 600000,
        'next', (v_inf.shop_epoch + 1) * 600000,
        'rotationId', p_user_id::text || ':' || v_inf.shop_epoch::text,
        'offers', v_inf.shop_offers,
        'sold', v_inf.shop_sold,
        'pity', jsonb_build_object(
          'apoc', v_inf.pity_apoc,
          'heretic', v_inf.pity_heretic
        )
      )
    )
  );
end;
$$;

create or replace function public.chrono_start_awakening_stage_server(
  p_user_id uuid,
  p_request_id uuid,
  p_character_key text,
  p_stage integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous jsonb;
  v_state public.chrono_player_state%rowtype;
  v_catalog public.chrono_awakening_catalog%rowtype;
  v_player public.chrono_player_awakenings%rowtype;
  v_response jsonb;
  v_baseline bigint;
begin
  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id
    and request_id = p_request_id;

  if found then
    return v_previous;
  end if;

  if p_character_key is null
     or p_stage is null
     or p_stage < 1
     or p_stage > 5 then
    raise exception 'Etapa de Awakening inválida';
  end if;

  select * into v_catalog
  from public.chrono_awakening_catalog
  where character_key = p_character_key
    and stage = p_stage;

  if not found then
    raise exception 'Etapa de Awakening inválida';
  end if;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if not found or not v_state.initialized then
    raise exception 'Save online não inicializado';
  end if;

  if not v_state.awakening_authority_enabled then
    raise exception 'Awakening autoritativo ainda não foi ativado';
  end if;

  if not public.chrono_awakening_character_owned_server(p_user_id, p_character_key) then
    raise exception 'Adquira este personagem antes de iniciar o Awakening';
  end if;

  if exists(
    select 1
    from public.chrono_player_awakening_active
    where user_id = p_user_id
  ) then
    raise exception 'Já existe uma etapa de Awakening ativa';
  end if;

  insert into public.chrono_player_awakenings(user_id, character_key)
  values(p_user_id, p_character_key)
  on conflict(user_id, character_key) do nothing;

  select * into v_player
  from public.chrono_player_awakenings
  where user_id = p_user_id
    and character_key = p_character_key
  for update;

  if v_player.ultimate_unlocked then
    raise exception 'Ultimate já desbloqueada';
  end if;

  if p_stage <> v_player.completed_stages + 1 then
    raise exception 'Conclua as etapas anteriores primeiro';
  end if;

  if v_state.awakening_keys < 1 then
    raise exception 'Chaves de Awakening insuficientes';
  end if;

  v_baseline := case
    when v_catalog.metric = 'maxWave' then 0
    else public.chrono_metric_value(
      coalesce(v_state.mission_stats, '{}'::jsonb),
      v_catalog.metric
    )
  end;

  update public.chrono_player_awakenings
  set journey_unlocked = true,
      updated_at = now()
  where user_id = p_user_id
    and character_key = p_character_key;

  insert into public.chrono_player_awakening_active(
    user_id, character_key, stage, metric, target, baseline, progress
  )
  values(
    p_user_id, p_character_key, p_stage,
    v_catalog.metric, v_catalog.target, v_baseline, 0
  );

  update public.chrono_player_state
  set awakening_keys = awakening_keys - 1,
      revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  perform public.chrono_sync_progression_save_server(p_user_id);

  v_response := jsonb_build_object(
    'started', true,
    'characterKey', p_character_key,
    'stage', p_stage,
    'progression', public.chrono_progression_payload_server(p_user_id),
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values(p_user_id, p_request_id, 'awakening_start_stage', v_response);

  return v_response;
end;
$$;

create or replace function public.chrono_claim_awakening_stage_server(
  p_user_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous jsonb;
  v_active public.chrono_player_awakening_active%rowtype;
  v_response jsonb;
  v_state public.chrono_player_state%rowtype;
begin
  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id
    and request_id = p_request_id;

  if found then
    return v_previous;
  end if;

  select * into v_active
  from public.chrono_player_awakening_active
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'Nenhuma etapa de Awakening ativa';
  end if;

  if not public.chrono_awakening_character_owned_server(p_user_id, v_active.character_key) then
    raise exception 'O personagem desta jornada não está disponível na conta';
  end if;

  if v_active.progress < v_active.target then
    raise exception 'A etapa ainda não foi concluída';
  end if;

  insert into public.chrono_player_awakenings(
    user_id, character_key, journey_unlocked, completed_stages
  )
  values(p_user_id, v_active.character_key, true, v_active.stage)
  on conflict(user_id, character_key) do update
  set journey_unlocked = true,
      completed_stages = greatest(
        public.chrono_player_awakenings.completed_stages,
        excluded.completed_stages
      ),
      updated_at = now();

  delete from public.chrono_player_awakening_active
  where user_id = p_user_id;

  update public.chrono_player_state
  set revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  perform public.chrono_sync_progression_save_server(p_user_id);

  v_response := jsonb_build_object(
    'claimed', true,
    'characterKey', v_active.character_key,
    'stage', v_active.stage,
    'progression', public.chrono_progression_payload_server(p_user_id),
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values(p_user_id, p_request_id, 'awakening_claim_stage', v_response);

  return v_response;
end;
$$;

create or replace function public.chrono_claim_awakening_ultimate_server(
  p_user_id uuid,
  p_request_id uuid,
  p_character_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous jsonb;
  v_player public.chrono_player_awakenings%rowtype;
  v_response jsonb;
  v_state public.chrono_player_state%rowtype;
begin
  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id
    and request_id = p_request_id;

  if found then
    return v_previous;
  end if;

  if not public.chrono_awakening_character_owned_server(p_user_id, p_character_key) then
    raise exception 'Adquira este personagem antes de resgatar a Ultimate';
  end if;

  select * into v_player
  from public.chrono_player_awakenings
  where user_id = p_user_id
    and character_key = p_character_key
  for update;

  if not found or v_player.completed_stages < 5 then
    raise exception 'Complete as cinco etapas primeiro';
  end if;

  if v_player.ultimate_unlocked then
    raise exception 'Ultimate já resgatada';
  end if;

  update public.chrono_player_awakenings
  set ultimate_unlocked = true,
      journey_unlocked = true,
      completed_stages = 5,
      updated_at = now()
  where user_id = p_user_id
    and character_key = p_character_key;

  update public.chrono_player_state
  set revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  perform public.chrono_sync_progression_save_server(p_user_id);

  v_response := jsonb_build_object(
    'claimed', true,
    'characterKey', p_character_key,
    'progression', public.chrono_progression_payload_server(p_user_id),
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values(p_user_id, p_request_id, 'awakening_claim_ultimate', v_response);

  return v_response;
end;
$$;

create or replace function public.chrono_merge_numeric_jsonb_max_server(
  p_previous jsonb,
  p_incoming jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb := case
    when jsonb_typeof(p_previous) = 'object' then p_previous
    else '{}'::jsonb
  end;
  v_key text;
  v_value jsonb;
  v_previous_text text;
  v_incoming_text text;
  v_previous_value bigint;
  v_incoming_value bigint;
begin
  if jsonb_typeof(p_incoming) <> 'object' then
    return v_result;
  end if;

  for v_key, v_value in
    select key, value from jsonb_each(p_incoming)
  loop
    v_incoming_text := v_value #>> '{}';
    if v_incoming_text is null or v_incoming_text !~ '^[0-9]+$' then
      continue;
    end if;

    v_previous_text := v_result ->> v_key;
    v_previous_value := case
      when v_previous_text ~ '^[0-9]+$' then v_previous_text::bigint
      else 0
    end;
    v_incoming_value := v_incoming_text::bigint;
    v_result := jsonb_set(
      v_result,
      array[v_key],
      to_jsonb(greatest(v_previous_value, v_incoming_value)),
      true
    );
  end loop;

  return v_result;
end;
$$;

create or replace function public.chrono_apply_progression_run_server(
  p_user_id uuid,
  p_session_id uuid,
  p_score bigint,
  p_wave integer,
  p_kills integer,
  p_boss_kills integer,
  p_elite_kills integer,
  p_skills_used integer,
  p_type_kills jsonb,
  p_special_metrics jsonb,
  p_doom_summary jsonb,
  p_final boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.chrono_game_sessions%rowtype;
  v_counter public.chrono_progression_run_counters%rowtype;
  v_active public.chrono_player_awakening_active%rowtype;
  v_metric bigint := 0;
  v_prev bigint := 0;
  v_delta bigint := 0;
  v_state public.chrono_player_state%rowtype;
  v_inf public.chrono_player_infernal%rowtype;
  v_elapsed numeric;
  v_reward integer := 0;
  v_loadout jsonb;
  v_completed integer;
  v_failed integer;
  v_miniboss integer;
  v_dboss integer;
  v_peak integer;
  v_doom_time integer;
  v_emperor boolean;
  v_cap integer;
  v_stats jsonb;
  v_types jsonb;
  v_special jsonb;
  v_doom jsonb;
  v_summary jsonb;
  v_last jsonb;
  v_score bigint;
  v_wave integer;
  v_kills integer;
  v_boss_kills integer;
  v_elite_kills integer;
  v_skills_used integer;
begin
  select * into v_session
  from public.chrono_game_sessions
  where id = p_session_id
    and user_id = p_user_id
  for update;

  if not found then
    raise exception 'Sessão não encontrada';
  end if;

  if not p_final and v_session.status <> 'active' then
    return jsonb_build_object('accepted', false, 'terminal', true);
  end if;

  insert into public.chrono_progression_run_counters(session_id, user_id)
  values(p_session_id, p_user_id)
  on conflict(session_id) do nothing;

  select * into v_counter
  from public.chrono_progression_run_counters
  where session_id = p_session_id
  for update;

  if p_final and v_counter.finalized then
    return jsonb_build_object(
      'accepted', true,
      'replayed', true,
      'doomReward', v_counter.doom_reward,
      'progression', public.chrono_progression_payload_server(p_user_id)
    );
  end if;

  -- Checkpoints podem chegar fora de ordem. Nunca permitimos que um resumo mais
  -- antigo diminua os contadores já observados para a mesma sessão.
  v_last := coalesce(v_counter.last_summary, '{}'::jsonb);
  v_score := greatest(p_score, coalesce((v_last ->> 'score')::bigint, 0));
  v_wave := greatest(p_wave, coalesce((v_last ->> 'wave')::integer, 0));
  v_kills := greatest(p_kills, coalesce((v_last ->> 'kills')::integer, 0));
  v_boss_kills := greatest(p_boss_kills, coalesce((v_last ->> 'bossKills')::integer, 0));
  v_elite_kills := greatest(p_elite_kills, coalesce((v_last ->> 'eliteKills')::integer, 0));
  v_skills_used := greatest(p_skills_used, coalesce((v_last ->> 'skillsUsed')::integer, 0));
  v_types := public.chrono_merge_numeric_jsonb_max_server(
    coalesce(v_last -> 'typeKills', '{}'::jsonb),
    coalesce(p_type_kills, '{}'::jsonb)
  );
  v_special := public.chrono_merge_numeric_jsonb_max_server(
    coalesce(v_last -> 'specialMetrics', '{}'::jsonb),
    coalesce(p_special_metrics, '{}'::jsonb)
  );
  v_doom := public.chrono_merge_numeric_jsonb_max_server(
    coalesce(v_last -> 'doomSummary', '{}'::jsonb),
    coalesce(p_doom_summary, '{}'::jsonb)
  );
  v_doom := jsonb_set(
    v_doom,
    '{emperorDefeated}',
    to_jsonb(
      coalesce((v_last #>> '{doomSummary,emperorDefeated}')::boolean, false)
      or coalesce((p_doom_summary ->> 'emperorDefeated')::boolean, false)
    ),
    true
  );

  v_summary := jsonb_build_object(
    'score', v_score,
    'wave', v_wave,
    'kills', v_kills,
    'bossKills', v_boss_kills,
    'eliteKills', v_elite_kills,
    'skillsUsed', v_skills_used,
    'typeKills', v_types,
    'specialMetrics', v_special,
    'doomSummary', v_doom
  );

  select * into v_active
  from public.chrono_player_awakening_active
  where user_id = p_user_id
  for update;

  -- Uma etapa iniciada no meio de uma partida não herda feitos anteriores.
  if found and v_session.started_at >= v_active.started_at then
    v_metric := public.chrono_progression_metric_for_run(
      v_active.metric,
      v_active.character_key,
      v_session.class_key,
      v_kills,
      v_boss_kills,
      v_elite_kills,
      v_skills_used,
      v_wave,
      v_types,
      v_special
    );

    if v_counter.active_character = v_active.character_key
       and v_counter.active_stage = v_active.stage then
      v_prev := greatest(0, v_counter.metric_value);
    else
      v_prev := 0;
    end if;

    if v_active.metric = 'maxWave' then
      update public.chrono_player_awakening_active
      set progress = greatest(progress, v_metric),
          updated_at = now()
      where user_id = p_user_id;
    else
      v_delta := greatest(0, v_metric - v_prev);
      update public.chrono_player_awakening_active
      set progress = least(target, progress + v_delta),
          updated_at = now()
      where user_id = p_user_id;
    end if;

    -- Mantém o maior valor já processado; isso impede contagem duplicada quando
    -- um checkpoint antigo chega depois de um checkpoint novo.
    v_metric := greatest(v_prev, v_metric);
  end if;

  update public.chrono_progression_run_counters
  set active_character = case
        when v_active.user_id is null then null
        else v_active.character_key
      end,
      active_stage = case
        when v_active.user_id is null then null
        else v_active.stage
      end,
      metric_value = v_metric,
      last_summary = v_summary,
      updated_at = now()
  where session_id = p_session_id;

  update public.chrono_game_sessions
  set server_context = jsonb_set(
    jsonb_set(server_context, '{specialMetrics}', v_special, true),
    '{doomSummary}', v_doom, true
  )
  where id = p_session_id;

  if p_final then
    select * into v_state
    from public.chrono_player_state
    where user_id = p_user_id
    for update;

    v_stats := coalesce(v_state.mission_stats, '{}'::jsonb);
    v_types := coalesce(v_stats -> 'typeKills', '{}'::jsonb);
    v_types := jsonb_set(
      v_types,
      '{riftTick}',
      to_jsonb(
        coalesce((v_types ->> 'riftTick')::bigint, 0)
        + greatest(0, coalesce((v_special ->> 'riftTickKills')::bigint, 0))
      ),
      true
    );
    v_stats := jsonb_set(v_stats, '{typeKills}', v_types, true);
    v_stats := jsonb_set(
      v_stats,
      '{assaultTurboBossKills}',
      to_jsonb(
        coalesce((v_stats ->> 'assaultTurboBossKills')::bigint, 0)
        + greatest(0, coalesce((v_special ->> 'assaultTurboBossKills')::bigint, 0))
      ),
      true
    );
    v_stats := jsonb_set(
      v_stats,
      '{roninParryContacts8427}',
      to_jsonb(
        coalesce((v_stats ->> 'roninParryContacts8427')::bigint, 0)
        + greatest(0, coalesce((v_special ->> 'roninParryContacts')::bigint, 0))
      ),
      true
    );

    if v_session.mode = 'doom' then
      v_elapsed := greatest(
        0,
        extract(epoch from (coalesce(v_session.ended_at, now()) - v_session.started_at))
      );
      v_completed := least(
        greatest(0, coalesce((v_doom ->> 'missionsCompleted')::integer, 0)),
        floor(v_elapsed / 12)::integer + 2
      );
      v_failed := least(
        greatest(0, coalesce((v_doom ->> 'missionsFailed')::integer, 0)),
        floor(v_elapsed / 10)::integer + 3
      );
      v_miniboss := least(
        greatest(0, coalesce((v_doom ->> 'minibossKills')::integer, 0)),
        v_kills
      );
      v_dboss := least(
        greatest(0, coalesce((v_doom ->> 'bossKills')::integer, 0)),
        v_boss_kills + 3
      );
      v_peak := least(100, greatest(0, coalesce((v_doom ->> 'peakValue')::integer, 0)));
      v_doom_time := least(
        floor(v_elapsed)::integer,
        greatest(0, coalesce((v_doom ->> 'timeAtDoom')::integer, 0))
      );
      v_emperor := coalesce((v_doom ->> 'emperorDefeated')::boolean, false)
        and v_dboss > 0;
      v_reward := least(
        500,
        greatest(
          0,
          floor(v_elapsed / 45)::integer
          + v_completed * 10
          + v_miniboss * 3
          + v_dboss * 7
          + case when v_emperor then 20 else 0 end
          + case when v_peak >= 25 then 2 else 0 end
          + case when v_peak >= 50 then 4 else 0 end
          + case when v_peak >= 75 then 7 else 0 end
          + case when v_peak >= 100 then 12 else 0 end
        )
      );
      v_loadout := coalesce(v_session.server_context -> 'doomBuffs', '[]'::jsonb);
      if exists(
        select 1
        from jsonb_array_elements_text(v_loadout) x
        where x = 'greed_seal'
      ) then
        v_reward := floor(v_reward * 1.25)::integer;
      end if;
      v_cap := least(
        500,
        greatest(20, v_kills / 3 + floor(v_elapsed / 20)::integer + 80)
      );
      v_reward := least(v_reward, v_cap);

      update public.chrono_player_state
      set sinner_tears = sinner_tears + v_reward,
          mission_stats = v_stats,
          mission_stats_updated_at = now(),
          revision = revision + 1
      where user_id = p_user_id
      returning * into v_state;

      insert into public.chrono_player_infernal(user_id)
      values(p_user_id)
      on conflict(user_id) do nothing;

      update public.chrono_player_infernal
      set doom_stats = jsonb_build_object(
            'runs', coalesce((doom_stats ->> 'runs')::bigint, 0) + 1,
            'bestPeak', greatest(coalesce((doom_stats ->> 'bestPeak')::integer, 0), v_peak),
            'bestTimeAtDoom', greatest(coalesce((doom_stats ->> 'bestTimeAtDoom')::integer, 0), v_doom_time),
            'missionsCompleted', coalesce((doom_stats ->> 'missionsCompleted')::bigint, 0) + v_completed,
            'bossKills', coalesce((doom_stats ->> 'bossKills')::bigint, 0) + v_dboss,
            'tearsEarned', coalesce((doom_stats ->> 'tearsEarned')::bigint, 0) + v_reward,
            'emperorDefeated', coalesce((doom_stats ->> 'emperorDefeated')::boolean, false) or v_emperor
          ),
          updated_at = now()
      where user_id = p_user_id;
    else
      update public.chrono_player_state
      set mission_stats = v_stats,
          mission_stats_updated_at = now(),
          revision = revision + 1
      where user_id = p_user_id
      returning * into v_state;
    end if;

    update public.chrono_progression_run_counters
    set finalized = true,
        doom_reward = v_reward,
        updated_at = now()
    where session_id = p_session_id;

    perform public.chrono_sync_progression_save_server(p_user_id);
  end if;

  return jsonb_build_object(
    'accepted', true,
    'doomReward', v_reward,
    'progression', public.chrono_progression_payload_server(p_user_id),
    'state', case when p_final then to_jsonb(v_state) else null end
  );
end;
$$;


-- Regrava somente contas que possuem progressão de Awakening, após os reparos.
do $$
declare
  r record;
begin
  for r in
    select distinct user_id
    from (
      select user_id from public.chrono_player_awakenings
      union
      select user_id from public.chrono_player_awakening_active
      union
      select user_id from chrono_removed_awakening_8519
    ) x
  loop
    perform public.chrono_sync_progression_save_server(r.user_id);
  end loop;
end;
$$;

revoke all on function public.chrono_awakening_character_owned_server(uuid, text)
  from public, anon, authenticated;
grant execute on function public.chrono_awakening_character_owned_server(uuid, text)
  to service_role;

revoke all on function public.chrono_progression_payload_server(uuid)
  from public, anon, authenticated;
grant execute on function public.chrono_progression_payload_server(uuid)
  to service_role;

revoke all on function public.chrono_start_awakening_stage_server(uuid, uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.chrono_start_awakening_stage_server(uuid, uuid, text, integer)
  to service_role;

revoke all on function public.chrono_claim_awakening_stage_server(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.chrono_claim_awakening_stage_server(uuid, uuid)
  to service_role;

revoke all on function public.chrono_claim_awakening_ultimate_server(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.chrono_claim_awakening_ultimate_server(uuid, uuid, text)
  to service_role;


revoke all on function public.chrono_merge_numeric_jsonb_max_server(jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.chrono_merge_numeric_jsonb_max_server(jsonb, jsonb)
  to service_role;

revoke all on function public.chrono_apply_progression_run_server(uuid, uuid, bigint, integer, integer, integer, integer, integer, jsonb, jsonb, jsonb, boolean)
  from public, anon, authenticated;
grant execute on function public.chrono_apply_progression_run_server(uuid, uuid, bigint, integer, integer, integer, integer, integer, jsonb, jsonb, jsonb, boolean)
  to service_role;

commit;
