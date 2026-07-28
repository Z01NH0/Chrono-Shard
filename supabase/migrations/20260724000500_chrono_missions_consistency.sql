-- Chrono Shards Cloud Save — fase 5 / revisão de consistência
-- Corrige divergências entre a interface local e as missões autoritativas.
-- Execute UMA VEZ depois da migração 20260724_chrono_missions_codes.sql.

alter table public.chrono_player_state
  add column if not exists mission_legacy_reconciled_at timestamptz,
  add column if not exists mission_legacy_imported_count integer not null default 0
    check (mission_legacy_imported_count >= 0);

-- Importa de forma idempotente os códigos que já constavam como usados no
-- snapshot de migração. Diferente do INSERT da migração 8.5.5, esta função
-- também funciona para usuários que migraram o save depois que o SQL foi
-- instalado.
create or replace function public.chrono_prepare_redeemed_codes_server(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted integer := 0;
begin
  insert into public.chrono_redeemed_codes(user_id, code_id)
  select ps.user_id, codes.code_id
  from public.chrono_player_state ps
  cross join lateral jsonb_array_elements_text(
    case
      when jsonb_typeof(ps.save_data -> 'chrono_v4_meta_redeemed_codes_v1') = 'array'
        then ps.save_data -> 'chrono_v4_meta_redeemed_codes_v1'
      else '[]'::jsonb
    end
  ) as used(code_hash)
  join public.chrono_reward_codes codes
    on codes.code_hash = lower(used.code_hash)
  where ps.user_id = p_user_id
  on conflict (user_id, code_id) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

-- Reaproveita uma única vez contratos que já estavam concluídos no snapshot
-- original. O navegador não envia valores novos: a função lê somente o
-- save_data já armazenado no servidor e concede, no máximo, os contratos do
-- catálogo oficial. Contratos antigos incompletos não são importados.
create or replace function public.chrono_reconcile_legacy_missions_server(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_legacy jsonb;
  v_slot jsonb;
  v_catalog public.chrono_mission_catalog%rowtype;
  v_index integer;
  v_diff text;
  v_slot_key text;
  v_mission_id text;
  v_baseline bigint;
  v_current bigint;
  v_progress bigint;
  v_imported integer := 0;
  v_extreme jsonb;
begin
  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('reconciled', false, 'imported', 0);
  end if;

  if not v_state.initialized or v_state.legacy_imported_at is null then
    return jsonb_build_object('reconciled', false, 'imported', 0, 'reason', 'legacy_not_imported');
  end if;

  if v_state.mission_legacy_reconciled_at is not null then
    return jsonb_build_object(
      'reconciled', true,
      'imported', v_state.mission_legacy_imported_count,
      'at', v_state.mission_legacy_reconciled_at
    );
  end if;

  v_legacy := coalesce(v_state.save_data #> '{chrono_v4_meta,missions39}', '{}'::jsonb);

  if jsonb_typeof(v_legacy) = 'object' then
    for v_index in 0..5 loop
      v_diff := case
        when v_index <= 2 then 'easy'
        when v_index <= 4 then 'medium'
        else 'hard'
      end;
      v_slot_key := 'normal:' || v_index::text;
      v_slot := v_legacy #> array['slots', v_index::text];

      if jsonb_typeof(v_slot) = 'object' then
        v_mission_id := nullif(v_slot ->> 'missionId', '');
        v_baseline := public.chrono_jsonb_bigint(v_slot, array['baseline']);

        select * into v_catalog
        from public.chrono_mission_catalog
        where mission_id = v_mission_id
          and difficulty = v_diff
          and active;

        if found then
          v_current := public.chrono_metric_value(v_state.mission_stats, v_catalog.metric);
          v_progress := case
            when v_catalog.absolute_progress then v_current
            else greatest(0, v_current - v_baseline)
          end;

          if v_progress >= v_catalog.target and not exists (
            select 1
            from public.chrono_player_missions current_pm
            join public.chrono_mission_catalog current_c
              on current_c.mission_id = current_pm.mission_id and current_c.active
            where current_pm.user_id = p_user_id
              and current_pm.slot_key = v_slot_key
              and (
                current_pm.claimed
                or current_pm.cooldown_until > now()
                or case
                  when current_c.absolute_progress then public.chrono_metric_value(v_state.mission_stats, current_c.metric)
                  else greatest(0, public.chrono_metric_value(v_state.mission_stats, current_c.metric) - current_pm.baseline)
                end >= current_c.target
              )
          ) then
            insert into public.chrono_player_missions(
              user_id, slot_key, slot_index, difficulty, mission_id,
              baseline, cooldown_until, claimed, updated_at
            ) values (
              p_user_id, v_slot_key, v_index, v_diff, v_mission_id,
              v_baseline, null, false, now()
            )
            on conflict (user_id, slot_key) do update set
              slot_index = excluded.slot_index,
              difficulty = excluded.difficulty,
              mission_id = excluded.mission_id,
              baseline = excluded.baseline,
              cooldown_until = null,
              claimed = false,
              updated_at = now();
            v_imported := v_imported + 1;
          end if;
        end if;
      end if;
    end loop;

    v_extreme := coalesce(v_legacy -> 'extreme489', v_legacy -> 'extreme');
    if jsonb_typeof(v_extreme) = 'object' then
      v_mission_id := nullif(v_extreme ->> 'missionId', '');
      v_baseline := public.chrono_jsonb_bigint(v_extreme, array['baseline']);

      select * into v_catalog
      from public.chrono_mission_catalog
      where mission_id = v_mission_id
        and difficulty = 'extreme'
        and active;

      if found then
        v_current := public.chrono_metric_value(v_state.mission_stats, v_catalog.metric);
        v_progress := case
          when v_catalog.absolute_progress then v_current
          else greatest(0, v_current - v_baseline)
        end;

        if v_progress >= v_catalog.target and not exists (
          select 1
          from public.chrono_player_missions current_pm
          join public.chrono_mission_catalog current_c
            on current_c.mission_id = current_pm.mission_id and current_c.active
          where current_pm.user_id = p_user_id
            and current_pm.slot_key = 'extreme'
            and (
              current_pm.claimed
              or current_pm.cooldown_until > now()
              or case
                when current_c.absolute_progress then public.chrono_metric_value(v_state.mission_stats, current_c.metric)
                else greatest(0, public.chrono_metric_value(v_state.mission_stats, current_c.metric) - current_pm.baseline)
              end >= current_c.target
            )
        ) then
          insert into public.chrono_player_missions(
            user_id, slot_key, slot_index, difficulty, mission_id,
            baseline, cooldown_until, claimed, last_mission_id, updated_at
          ) values (
            p_user_id, 'extreme', 6, 'extreme', v_mission_id,
            v_baseline, null, false, nullif(v_extreme ->> 'lastMissionId', ''), now()
          )
          on conflict (user_id, slot_key) do update set
            slot_index = 6,
            difficulty = 'extreme',
            mission_id = excluded.mission_id,
            baseline = excluded.baseline,
            cooldown_until = null,
            claimed = false,
            last_mission_id = coalesce(excluded.last_mission_id, public.chrono_player_missions.last_mission_id),
            updated_at = now();
          v_imported := v_imported + 1;
        end if;
      end if;
    end if;
  end if;

  update public.chrono_player_state
  set mission_legacy_reconciled_at = now(),
      mission_legacy_imported_count = v_imported,
      revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  return jsonb_build_object(
    'reconciled', true,
    'imported', v_imported,
    'at', v_state.mission_legacy_reconciled_at
  );
end;
$$;

-- A preparação passa a reconciliar o snapshot legado antes de sortear novos
-- contratos. Depois disso, o fluxo segue totalmente autoritativo.
create or replace function public.chrono_prepare_missions_server(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_slot public.chrono_player_missions%rowtype;
  v_catalog public.chrono_mission_catalog%rowtype;
  v_slot_key text;
  v_diff text;
  v_index integer;
  v_mission_id text;
  v_old_secret boolean := false;
begin
  insert into public.chrono_player_state(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if v_state.mission_stats = '{}'::jsonb then
    update public.chrono_player_state
    set mission_stats = coalesce(save_data #> '{chrono_v4_meta,stats}', '{}'::jsonb),
        mission_reputation = greatest(
          mission_reputation,
          public.chrono_jsonb_bigint(
            coalesce(save_data -> 'chrono_v4_meta', '{}'::jsonb),
            array['missionReputation489']
          )
        )
    where user_id = p_user_id
    returning * into v_state;
  end if;

  perform public.chrono_prepare_redeemed_codes_server(p_user_id);
  perform public.chrono_reconcile_legacy_missions_server(p_user_id);

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  -- Repara linhas antigas que apontem para uma missão removida ou para uma
  -- dificuldade incompatível com o slot. Isso evita cards vazios e resgates
  -- impossíveis após mudanças de catálogo.
  update public.chrono_player_missions pm
  set mission_id = null,
      baseline = 0,
      cooldown_until = null,
      claimed = false,
      updated_at = now()
  where pm.user_id = p_user_id
    and pm.mission_id is not null
    and not exists (
      select 1
      from public.chrono_mission_catalog c
      where c.mission_id = pm.mission_id
        and c.difficulty = pm.difficulty
        and c.active
    );

  for v_index in 0..5 loop
    v_diff := case
      when v_index <= 2 then 'easy'
      when v_index <= 4 then 'medium'
      else 'hard'
    end;
    v_slot_key := 'normal:' || v_index::text;

    insert into public.chrono_player_missions(
      user_id,slot_key,slot_index,difficulty,mission_id,baseline,claimed
    ) values (
      p_user_id,v_slot_key,v_index,v_diff,null,0,false
    ) on conflict (user_id,slot_key) do nothing;

    select * into v_slot
    from public.chrono_player_missions
    where user_id = p_user_id and slot_key = v_slot_key
    for update;

    if v_slot.difficulty <> v_diff then
      update public.chrono_player_missions
      set difficulty = v_diff, mission_id = null, baseline = 0,
          cooldown_until = null, claimed = false, updated_at = now()
      where user_id = p_user_id and slot_key = v_slot_key
      returning * into v_slot;
    end if;

    if v_slot.mission_id is null
       and (v_slot.cooldown_until is null or v_slot.cooldown_until <= now()) then
      select c.mission_id into v_mission_id
      from public.chrono_mission_catalog c
      where c.difficulty = v_diff and c.active
        and not exists (
          select 1 from public.chrono_player_missions pm
          where pm.user_id = p_user_id and pm.mission_id = c.mission_id
        )
      order by random()
      limit 1;

      if v_mission_id is null then
        select c.mission_id into v_mission_id
        from public.chrono_mission_catalog c
        where c.difficulty = v_diff and c.active
        order by random()
        limit 1;
      end if;

      select * into v_catalog
      from public.chrono_mission_catalog
      where mission_id = v_mission_id;

      update public.chrono_player_missions
      set mission_id = v_mission_id,
          baseline = public.chrono_metric_value(v_state.mission_stats, v_catalog.metric),
          cooldown_until = null,
          claimed = false,
          updated_at = now()
      where user_id = p_user_id and slot_key = v_slot_key;
    end if;
  end loop;

  insert into public.chrono_player_missions(
    user_id,slot_key,slot_index,difficulty,mission_id,baseline,claimed
  ) values (
    p_user_id,'extreme',6,'extreme',null,0,false
  ) on conflict (user_id,slot_key) do nothing;

  select * into v_slot
  from public.chrono_player_missions
  where user_id = p_user_id and slot_key = 'extreme'
  for update;

  if v_slot.mission_id is null
     and (v_slot.cooldown_until is null or v_slot.cooldown_until <= now()) then
    select c.mission_id into v_mission_id
    from public.chrono_mission_catalog c
    where c.difficulty = 'extreme' and c.active
      and c.mission_id is distinct from v_slot.last_mission_id
    order by random()
    limit 1;

    if v_mission_id is null then
      select c.mission_id into v_mission_id
      from public.chrono_mission_catalog c
      where c.difficulty = 'extreme' and c.active
      order by random()
      limit 1;
    end if;

    select * into v_catalog
    from public.chrono_mission_catalog
    where mission_id = v_mission_id;

    update public.chrono_player_missions
    set mission_id = v_mission_id,
        baseline = public.chrono_metric_value(v_state.mission_stats, v_catalog.metric),
        cooldown_until = null,
        claimed = false,
        updated_at = now()
    where user_id = p_user_id and slot_key = 'extreme';
  end if;

  v_old_secret := coalesce(v_state.save_data #>> '{chrono_v4_meta,moonMissionClaimed}', 'false') = 'true';

  insert into public.chrono_player_missions(
    user_id,slot_key,slot_index,difficulty,mission_id,baseline,claimed
  ) values (
    p_user_id,'secret',7,'secret','s_moon',0,v_old_secret
  ) on conflict (user_id,slot_key) do update set
    mission_id = 's_moon',
    difficulty = 'secret',
    claimed = public.chrono_player_missions.claimed or excluded.claimed,
    updated_at = now();
end;
$$;

-- Payload com progresso calculado no próprio servidor. A interface não precisa
-- mais inferir se uma missão está concluída usando números locais antigos.
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
  v_duplicate_count integer := 0;
  v_invalid_count integer := 0;
begin
  perform public.chrono_prepare_missions_server(p_user_id);

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'slotKey', q.slot_key,
      'slotIndex', q.slot_index,
      'difficulty', q.difficulty,
      'missionId', q.mission_id,
      'baseline', q.baseline,
      'cooldownUntil', q.cooldown_until_ms,
      'claimed', q.claimed,
      'current', q.current_value,
      'progress', q.progress_value,
      'target', q.target,
      'done', q.done,
      'title', q.title,
      'description', q.description,
      'metric', q.metric
    ) order by q.slot_index
  ), '[]'::jsonb)
  into v_slots
  from (
    select pm.*,
      case when pm.cooldown_until is null then 0 else floor(extract(epoch from pm.cooldown_until) * 1000)::bigint end as cooldown_until_ms,
      coalesce(c.title, '') as title,
      coalesce(c.description, '') as description,
      coalesce(c.metric, '') as metric,
      coalesce(c.target, 0) as target,
      public.chrono_metric_value(v_state.mission_stats, coalesce(c.metric, '')) as current_value,
      case
        when c.mission_id is null then 0
        when c.absolute_progress then public.chrono_metric_value(v_state.mission_stats, c.metric)
        else greatest(0, public.chrono_metric_value(v_state.mission_stats, c.metric) - pm.baseline)
      end as progress_value,
      case
        when c.mission_id is null then false
        when c.absolute_progress then public.chrono_metric_value(v_state.mission_stats, c.metric) >= c.target
        else greatest(0, public.chrono_metric_value(v_state.mission_stats, c.metric) - pm.baseline) >= c.target
      end as done
    from public.chrono_player_missions pm
    left join public.chrono_mission_catalog c on c.mission_id = pm.mission_id and c.active
    where pm.user_id = p_user_id and pm.slot_key like 'normal:%'
  ) q;

  select jsonb_build_object(
      'slotKey', q.slot_key,
      'slotIndex', q.slot_index,
      'difficulty', q.difficulty,
      'missionId', q.mission_id,
      'baseline', q.baseline,
      'cooldownUntil', q.cooldown_until_ms,
      'claimed', q.claimed,
      'lastMissionId', q.last_mission_id,
      'current', q.current_value,
      'progress', q.progress_value,
      'target', q.target,
      'done', q.done,
      'title', q.title,
      'description', q.description,
      'metric', q.metric
    )
  into v_extreme
  from (
    select pm.*,
      case when pm.cooldown_until is null then 0 else floor(extract(epoch from pm.cooldown_until) * 1000)::bigint end as cooldown_until_ms,
      coalesce(c.title, '') as title,
      coalesce(c.description, '') as description,
      coalesce(c.metric, '') as metric,
      coalesce(c.target, 0) as target,
      public.chrono_metric_value(v_state.mission_stats, coalesce(c.metric, '')) as current_value,
      case
        when c.mission_id is null then 0
        when c.absolute_progress then public.chrono_metric_value(v_state.mission_stats, c.metric)
        else greatest(0, public.chrono_metric_value(v_state.mission_stats, c.metric) - pm.baseline)
      end as progress_value,
      case
        when c.mission_id is null then false
        when c.absolute_progress then public.chrono_metric_value(v_state.mission_stats, c.metric) >= c.target
        else greatest(0, public.chrono_metric_value(v_state.mission_stats, c.metric) - pm.baseline) >= c.target
      end as done
    from public.chrono_player_missions pm
    left join public.chrono_mission_catalog c on c.mission_id = pm.mission_id and c.active
    where pm.user_id = p_user_id and pm.slot_key = 'extreme'
  ) q;

  select jsonb_build_object(
      'slotKey', q.slot_key,
      'slotIndex', q.slot_index,
      'difficulty', q.difficulty,
      'missionId', q.mission_id,
      'baseline', q.baseline,
      'cooldownUntil', 0,
      'claimed', q.claimed,
      'current', q.current_value,
      'progress', q.progress_value,
      'target', q.target,
      'done', q.done,
      'title', q.title,
      'description', q.description,
      'metric', q.metric
    )
  into v_secret
  from (
    select pm.*,
      coalesce(c.title, '') as title,
      coalesce(c.description, '') as description,
      coalesce(c.metric, '') as metric,
      coalesce(c.target, 0) as target,
      public.chrono_metric_value(v_state.mission_stats, coalesce(c.metric, '')) as current_value,
      case
        when c.mission_id is null then 0
        when c.absolute_progress then public.chrono_metric_value(v_state.mission_stats, c.metric)
        else greatest(0, public.chrono_metric_value(v_state.mission_stats, c.metric) - pm.baseline)
      end as progress_value,
      case
        when c.mission_id is null then false
        when c.absolute_progress then public.chrono_metric_value(v_state.mission_stats, c.metric) >= c.target
        else greatest(0, public.chrono_metric_value(v_state.mission_stats, c.metric) - pm.baseline) >= c.target
      end as done
    from public.chrono_player_missions pm
    left join public.chrono_mission_catalog c on c.mission_id = pm.mission_id and c.active
    where pm.user_id = p_user_id and pm.slot_key = 'secret'
  ) q;

  select count(*) into v_duplicate_count
  from (
    select mission_id
    from public.chrono_player_missions
    where user_id = p_user_id and mission_id is not null and difficulty in ('easy','medium','hard')
    group by mission_id
    having count(*) > 1
  ) duplicates;

  select count(*) into v_invalid_count
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c on c.mission_id = pm.mission_id and c.active
  where pm.user_id = p_user_id
    and pm.mission_id is not null
    and c.mission_id is null;

  return jsonb_build_object(
    'enabled', v_state.mission_rewards_enabled,
    'reputation', v_state.mission_reputation,
    'stats', coalesce(v_state.mission_stats, '{}'::jsonb),
    'slots', v_slots,
    'extreme', coalesce(v_extreme, '{}'::jsonb),
    'secret', coalesce(v_secret, '{}'::jsonb),
    'serverTime', floor(extract(epoch from now()) * 1000)::bigint,
    'legacyReconciledAt', v_state.mission_legacy_reconciled_at,
    'legacyImportedCount', v_state.mission_legacy_imported_count,
    'audit', jsonb_build_object(
      'normalSlots', jsonb_array_length(v_slots),
      'duplicateMissions', v_duplicate_count,
      'invalidMissions', v_invalid_count,
      'revision', v_state.revision
    ),
    'state', to_jsonb(v_state)
  );
end;
$$;

-- Garante a importação de códigos usados antes da checagem de duplicidade.
create or replace function public.chrono_redeem_code_server(
  p_user_id uuid,
  p_request_id uuid,
  p_code_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous jsonb;
  v_state public.chrono_player_state%rowtype;
  v_code public.chrono_reward_codes%rowtype;
  v_old_relics bigint;
  v_old_chrono bigint;
  v_old_keys bigint;
  v_old_tears bigint;
  v_new_relics bigint;
  v_new_chrono bigint;
  v_new_keys bigint;
  v_new_tears bigint;
  v_save jsonb;
  v_meta jsonb;
  v_stats jsonb;
  v_unlocks jsonb;
  v_used jsonb;
  v_response jsonb;
begin
  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id and request_id = p_request_id;
  if found then return v_previous; end if;

  select * into v_code
  from public.chrono_reward_codes
  where code_hash = lower(p_code_hash) and active;
  if not found then raise exception 'Código inválido'; end if;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;
  if not found or not v_state.initialized then raise exception 'Save online não inicializado'; end if;
  if not v_state.wallet_authority_enabled or not v_state.code_rewards_enabled then
    raise exception 'Códigos online ainda não estão ativados';
  end if;

  perform public.chrono_prepare_redeemed_codes_server(p_user_id);

  if exists (
    select 1 from public.chrono_redeemed_codes
    where user_id = p_user_id and code_id = v_code.code_id
  ) then
    raise exception 'Esse código já foi usado';
  end if;

  v_old_relics := v_state.relic_shards;
  v_old_chrono := v_state.chrono_fragments;
  v_old_keys := v_state.awakening_keys;
  v_old_tears := v_state.sinner_tears;

  if v_code.master_unlock then
    v_new_relics := greatest(v_state.relic_shards, 9999);
    v_new_chrono := greatest(v_state.chrono_fragments, 999);
    v_new_keys := greatest(v_state.awakening_keys, 99);
    v_new_tears := greatest(v_state.sinner_tears, 9999);
  else
    v_new_relics := v_state.relic_shards + v_code.relic_shards;
    v_new_chrono := v_state.chrono_fragments + v_code.chrono_fragments;
    v_new_keys := v_state.awakening_keys + v_code.awakening_keys;
    v_new_tears := v_state.sinner_tears + v_code.sinner_tears;
  end if;

  v_stats := coalesce(v_state.mission_stats, '{}'::jsonb);
  if v_code.chrono_fragments > 0 then
    v_stats := public.chrono_jsonb_increment(v_stats,array['chronoFragmentsCollected'],v_code.chrono_fragments);
  end if;
  if v_code.master_unlock then
    v_stats := jsonb_set(v_stats,'{chronoFragmentsCollected}',to_jsonb(greatest(public.chrono_jsonb_bigint(v_stats,array['chronoFragmentsCollected']),999::bigint)),true);
    v_stats := jsonb_set(v_stats,'{maxWave}',to_jsonb(greatest(public.chrono_jsonb_bigint(v_stats,array['maxWave']),20::bigint)),true);
  end if;

  v_save := coalesce(v_state.save_data, '{}'::jsonb);
  v_meta := coalesce(v_save -> 'chrono_v4_meta', '{}'::jsonb);
  v_meta := jsonb_set(v_meta, '{relicShards}', to_jsonb(v_new_relics), true);
  v_meta := jsonb_set(v_meta, '{chronoFragments}', to_jsonb(v_new_chrono), true);
  v_meta := jsonb_set(v_meta, '{awakeningKeys}', to_jsonb(v_new_keys), true);
  v_meta := jsonb_set(v_meta, '{sinnerTears830}', to_jsonb(v_new_tears), true);
  v_meta := jsonb_set(v_meta, '{doomFragments}', to_jsonb(v_new_tears), true);
  v_meta := jsonb_set(v_meta, '{stats}', v_stats, true);

  if v_code.master_unlock then
    v_meta := jsonb_set(v_meta, '{allUnlocked}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{allInUnlocked}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{nefalemPurchased830}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{riftModeUnlocked525}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{riftModeUnlocked}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{doomModeUnlocked810}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{doomModeUnlocked}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{unlockedMoonSlayer}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{moonMissionClaimed}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{unlockedShadowChild}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{shadowChildUnlocked}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{stellarEmperorRevealed}', 'true'::jsonb, true);
    v_meta := jsonb_set(v_meta, '{stellarEmperorSecretUnlocked}', 'true'::jsonb, true);

    v_unlocks := to_jsonb(array[
      'engineer','mage','ronin','alchemist','reaper','colonel','chronoHero',
      'shadowChild','moonSlayer','bomber','archer','ricocheteador','stellarEmperor'
    ]::text[]);
    v_save := jsonb_set(v_save, '{chrono_v4_meta_class_unlocks_v3}', v_unlocks, true);
    v_save := jsonb_set(v_save, '{chrono_v4_meta_secret_rift_v1}', '{"lostEmperorDefeated":true}'::jsonb, true);
  end if;

  v_used := coalesce(v_save -> 'chrono_v4_meta_redeemed_codes_v1', '[]'::jsonb);
  if jsonb_typeof(v_used) <> 'array' then v_used := '[]'::jsonb; end if;
  if not v_used @> jsonb_build_array(v_code.code_hash) then
    v_used := v_used || jsonb_build_array(v_code.code_hash);
  end if;
  v_save := jsonb_set(v_save, '{chrono_v4_meta_redeemed_codes_v1}', v_used, true);
  v_save := jsonb_set(v_save, '{chrono_v4_meta}', v_meta, true);

  insert into public.chrono_redeemed_codes(user_id,code_id)
  values (p_user_id,v_code.code_id);

  update public.chrono_player_state
  set relic_shards = v_new_relics,
      chrono_fragments = v_new_chrono,
      awakening_keys = v_new_keys,
      sinner_tears = v_new_tears,
      mission_stats = v_stats,
      save_data = v_save,
      revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  v_response := jsonb_build_object(
    'accepted', true,
    'codeId', v_code.code_id,
    'label', v_code.label,
    'rewardRelics', greatest(0, v_new_relics - v_old_relics),
    'rewardChrono', greatest(0, v_new_chrono - v_old_chrono),
    'rewardAwakeningKeys', greatest(0, v_new_keys - v_old_keys),
    'rewardSinnerTears', greatest(0, v_new_tears - v_old_tears),
    'masterUnlock', v_code.master_unlock,
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id,request_id,action,response)
  values (p_user_id,p_request_id,'redeem_code',v_response);

  return v_response;
end;
$$;

revoke all on function public.chrono_prepare_redeemed_codes_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_reconcile_legacy_missions_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_prepare_missions_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_mission_payload(uuid) from public,anon,authenticated;
revoke all on function public.chrono_redeem_code_server(uuid,uuid,text) from public,anon,authenticated;

grant execute on function public.chrono_prepare_redeemed_codes_server(uuid) to service_role;
grant execute on function public.chrono_reconcile_legacy_missions_server(uuid) to service_role;
grant execute on function public.chrono_prepare_missions_server(uuid) to service_role;
grant execute on function public.chrono_mission_payload(uuid) to service_role;
grant execute on function public.chrono_redeem_code_server(uuid,uuid,text) to service_role;
