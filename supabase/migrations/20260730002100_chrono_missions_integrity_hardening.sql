-- Chrono Shards 8.7.4 — integridade estrutural e hidratação das Missões Gerais
-- Executar depois da migration 020.
--
-- Objetivos:
-- 1. garantir exatamente os oito slots oficiais por conta;
-- 2. reparar índices, dificuldades, missões duplicadas e baselines impossíveis;
-- 3. impedir que o payload mude de posição quando um contrato estiver em cooldown;
-- 4. tornar o catálogo SQL a fonte visual oficial do cliente;
-- 5. manter resgate, cooldown e rotação autoritativos.

begin;

-- Remove somente slots que nunca fizeram parte do sistema oficial atual.
delete from public.chrono_player_missions
where slot_key not in (
  'normal:0','normal:1','normal:2','normal:3','normal:4','normal:5','extreme','secret'
);

-- Garante a existência dos oito slots para todas as contas já conhecidas.
insert into public.chrono_player_missions(user_id,slot_key,slot_index,difficulty,mission_id,baseline,claimed)
select ps.user_id, expected.slot_key, expected.slot_index, expected.difficulty,
       case when expected.slot_key='secret' then 's_moon' else null end,
       0,
       false
from public.chrono_player_state ps
cross join (values
  ('normal:0',0,'easy'),
  ('normal:1',1,'easy'),
  ('normal:2',2,'easy'),
  ('normal:3',3,'medium'),
  ('normal:4',4,'medium'),
  ('normal:5',5,'hard'),
  ('extreme',6,'extreme'),
  ('secret',7,'secret')
) as expected(slot_key,slot_index,difficulty)
on conflict (user_id,slot_key) do nothing;

-- Normaliza posição e dificuldade sem apagar um contrato que continue válido.
update public.chrono_player_missions pm
set slot_index = expected.slot_index,
    difficulty = expected.difficulty,
    claimed = case when expected.slot_key='secret' then pm.claimed else false end,
    mission_id = case when expected.slot_key='secret' then 's_moon' else pm.mission_id end,
    cooldown_until = case when expected.slot_key='secret' then null else pm.cooldown_until end,
    updated_at = now()
from (values
  ('normal:0',0,'easy'),
  ('normal:1',1,'easy'),
  ('normal:2',2,'easy'),
  ('normal:3',3,'medium'),
  ('normal:4',4,'medium'),
  ('normal:5',5,'hard'),
  ('extreme',6,'extreme'),
  ('secret',7,'secret')
) as expected(slot_key,slot_index,difficulty)
where pm.slot_key = expected.slot_key
  and (
    pm.slot_index is distinct from expected.slot_index
    or pm.difficulty is distinct from expected.difficulty
    or (expected.slot_key<>'secret' and pm.claimed)
    or (expected.slot_key='secret' and pm.mission_id is distinct from 's_moon')
    or (expected.slot_key='secret' and pm.cooldown_until is not null)
  );

-- Remove atribuições que já não combinam com o catálogo/dificuldade do slot.
update public.chrono_player_missions pm
set mission_id = null,
    baseline = 0,
    cooldown_until = null,
    claimed = false,
    updated_at = now()
where pm.slot_key <> 'secret'
  and pm.mission_id is not null
  and not exists (
    select 1
    from public.chrono_mission_catalog c
    where c.mission_id = pm.mission_id
      and c.difficulty = pm.difficulty
      and c.active
  );

-- Preserva o primeiro slot e limpa cópias do mesmo contrato em outros slots normais.
with ranked as (
  select pm.user_id, pm.slot_key,
         row_number() over (
           partition by pm.user_id, pm.mission_id
           order by pm.slot_index, pm.updated_at, pm.slot_key
         ) as rn
  from public.chrono_player_missions pm
  where pm.slot_key like 'normal:%'
    and pm.mission_id is not null
)
update public.chrono_player_missions pm
set mission_id = null,
    baseline = 0,
    cooldown_until = null,
    claimed = false,
    updated_at = now()
from ranked r
where pm.user_id = r.user_id
  and pm.slot_key = r.slot_key
  and r.rn > 1;

-- Um baseline acima do contador oficial congela o progresso. Rebaixa-o para o valor atual.
update public.chrono_player_missions pm
set baseline = public.chrono_metric_value(coalesce(ps.mission_stats,'{}'::jsonb),c.metric),
    updated_at = now()
from public.chrono_player_state ps,
     public.chrono_mission_catalog c
where ps.user_id = pm.user_id
  and c.mission_id = pm.mission_id
  and c.active
  and not c.absolute_progress
  and pm.baseline > public.chrono_metric_value(coalesce(ps.mission_stats,'{}'::jsonb),c.metric);

-- A posição do slot passa a ser uma garantia física, não apenas convenção do HTML.
create unique index if not exists chrono_player_missions_user_slot_index_uidx
  on public.chrono_player_missions(user_id,slot_index);

alter table public.chrono_player_missions
  drop constraint if exists chrono_player_missions_slot_shape_check;

alter table public.chrono_player_missions
  add constraint chrono_player_missions_slot_shape_check check (
    (slot_key='normal:0' and slot_index=0 and difficulty='easy') or
    (slot_key='normal:1' and slot_index=1 and difficulty='easy') or
    (slot_key='normal:2' and slot_index=2 and difficulty='easy') or
    (slot_key='normal:3' and slot_index=3 and difficulty='medium') or
    (slot_key='normal:4' and slot_index=4 and difficulty='medium') or
    (slot_key='normal:5' and slot_index=5 and difficulty='hard') or
    (slot_key='extreme' and slot_index=6 and difficulty='extreme') or
    (slot_key='secret' and slot_index=7 and difficulty='secret')
  );

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
    set mission_stats = coalesce(save_data #> '{chrono_v4_meta,stats}','{}'::jsonb),
        mission_reputation = greatest(
          mission_reputation,
          public.chrono_jsonb_bigint(coalesce(save_data -> 'chrono_v4_meta','{}'::jsonb),array['missionReputation489'])
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

  delete from public.chrono_player_missions
  where user_id = p_user_id
    and slot_key not in ('normal:0','normal:1','normal:2','normal:3','normal:4','normal:5','extreme','secret');

  -- Cria e normaliza os seis contratos comuns.
  for v_index in 0..5 loop
    v_diff := case when v_index<=2 then 'easy' when v_index<=4 then 'medium' else 'hard' end;
    v_slot_key := 'normal:' || v_index::text;

    insert into public.chrono_player_missions(user_id,slot_key,slot_index,difficulty,mission_id,baseline,claimed)
    values (p_user_id,v_slot_key,v_index,v_diff,null,0,false)
    on conflict (user_id,slot_key) do update set
      slot_index = excluded.slot_index,
      difficulty = excluded.difficulty,
      claimed = false,
      updated_at = case
        when public.chrono_player_missions.slot_index is distinct from excluded.slot_index
          or public.chrono_player_missions.difficulty is distinct from excluded.difficulty
          or public.chrono_player_missions.claimed
        then now() else public.chrono_player_missions.updated_at end;
  end loop;

  insert into public.chrono_player_missions(user_id,slot_key,slot_index,difficulty,mission_id,baseline,claimed)
  values (p_user_id,'extreme',6,'extreme',null,0,false)
  on conflict (user_id,slot_key) do update set
    slot_index=6,difficulty='extreme',claimed=false,
    updated_at=case
      when public.chrono_player_missions.slot_index<>6
        or public.chrono_player_missions.difficulty<>'extreme'
        or public.chrono_player_missions.claimed
      then now() else public.chrono_player_missions.updated_at end;

  v_old_secret := coalesce(v_state.save_data #>> '{chrono_v4_meta,moonMissionClaimed}','false')='true';
  insert into public.chrono_player_missions(user_id,slot_key,slot_index,difficulty,mission_id,baseline,cooldown_until,claimed)
  values (p_user_id,'secret',7,'secret','s_moon',0,null,v_old_secret)
  on conflict (user_id,slot_key) do update set
    slot_index=7,
    difficulty='secret',
    mission_id='s_moon',
    baseline=0,
    cooldown_until=null,
    claimed=public.chrono_player_missions.claimed or excluded.claimed,
    updated_at=case
      when public.chrono_player_missions.slot_index<>7
        or public.chrono_player_missions.difficulty<>'secret'
        or public.chrono_player_missions.mission_id is distinct from 's_moon'
        or public.chrono_player_missions.cooldown_until is not null
        or (excluded.claimed and not public.chrono_player_missions.claimed)
      then now() else public.chrono_player_missions.updated_at end;

  -- Catálogo removido ou dificuldade incompatível.
  update public.chrono_player_missions pm
  set mission_id=null,baseline=0,cooldown_until=null,claimed=false,updated_at=now()
  where pm.user_id=p_user_id
    and pm.slot_key<>'secret'
    and pm.mission_id is not null
    and not exists (
      select 1 from public.chrono_mission_catalog c
      where c.mission_id=pm.mission_id and c.difficulty=pm.difficulty and c.active
    );

  -- Repara duplicatas herdadas. A primeira posição permanece estável.
  with ranked as (
    select pm.slot_key,
           row_number() over(partition by pm.mission_id order by pm.slot_index,pm.updated_at,pm.slot_key) as rn
    from public.chrono_player_missions pm
    where pm.user_id=p_user_id and pm.slot_key like 'normal:%' and pm.mission_id is not null
  )
  update public.chrono_player_missions pm
  set mission_id=null,baseline=0,cooldown_until=null,claimed=false,updated_at=now()
  from ranked r
  where pm.user_id=p_user_id and pm.slot_key=r.slot_key and r.rn>1;

  -- Repara continuamente baselines incompatíveis, inclusive em contas antigas.
  update public.chrono_player_missions pm
  set baseline=public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric),updated_at=now()
  from public.chrono_mission_catalog c
  where pm.user_id=p_user_id
    and c.mission_id=pm.mission_id
    and c.active
    and not c.absolute_progress
    and pm.baseline>public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric);

  -- Preenche contratos normais livres sem repetir IDs na mesma conta.
  for v_index in 0..5 loop
    v_diff := case when v_index<=2 then 'easy' when v_index<=4 then 'medium' else 'hard' end;
    v_slot_key := 'normal:' || v_index::text;

    select * into v_slot
    from public.chrono_player_missions
    where user_id=p_user_id and slot_key=v_slot_key
    for update;

    if v_slot.mission_id is null
       and (v_slot.cooldown_until is null or v_slot.cooldown_until<=now()) then
      v_mission_id := null;
      select c.mission_id into v_mission_id
      from public.chrono_mission_catalog c
      where c.difficulty=v_diff and c.active
        and not exists (
          select 1 from public.chrono_player_missions used
          where used.user_id=p_user_id and used.mission_id=c.mission_id
        )
      order by random()
      limit 1;

      if v_mission_id is not null then
        select * into v_catalog from public.chrono_mission_catalog where mission_id=v_mission_id;
        update public.chrono_player_missions
        set mission_id=v_mission_id,
            baseline=public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),v_catalog.metric),
            cooldown_until=null,
            claimed=false,
            updated_at=now()
        where user_id=p_user_id and slot_key=v_slot_key;
      end if;
    end if;
  end loop;

  select * into v_slot
  from public.chrono_player_missions
  where user_id=p_user_id and slot_key='extreme'
  for update;

  if v_slot.mission_id is null
     and (v_slot.cooldown_until is null or v_slot.cooldown_until<=now()) then
    v_mission_id := null;
    select c.mission_id into v_mission_id
    from public.chrono_mission_catalog c
    where c.difficulty='extreme' and c.active
      and c.mission_id is distinct from v_slot.last_mission_id
    order by random()
    limit 1;

    if v_mission_id is null then
      select c.mission_id into v_mission_id
      from public.chrono_mission_catalog c
      where c.difficulty='extreme' and c.active
      order by random()
      limit 1;
    end if;

    if v_mission_id is not null then
      select * into v_catalog from public.chrono_mission_catalog where mission_id=v_mission_id;
      update public.chrono_player_missions
      set mission_id=v_mission_id,
          baseline=public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),v_catalog.metric),
          cooldown_until=null,
          claimed=false,
          updated_at=now()
      where user_id=p_user_id and slot_key='extreme';
    end if;
  end if;
end;
$$;

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
  v_invalid integer := 0;
  v_duplicates integer := 0;
  v_impossible integer := 0;
  v_bad_shape integer := 0;
begin
  perform public.chrono_prepare_missions_server(p_user_id);

  select * into v_state
  from public.chrono_player_state
  where user_id=p_user_id;

  if not found then raise exception 'Save online não inicializado'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'slotKey',pm.slot_key,
    'slotIndex',pm.slot_index,
    'difficulty',pm.difficulty,
    'missionId',pm.mission_id,
    'baseline',pm.baseline,
    'cooldownUntil',case when pm.cooldown_until is null then 0 else floor(extract(epoch from pm.cooldown_until)*1000)::bigint end,
    'claimed',pm.claimed,
    'lastMissionId',pm.last_mission_id,
    'metric',c.metric,
    'target',coalesce(c.target,0),
    'current',public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric),
    'progress',case
      when c.mission_id is null then 0
      else least(c.target,case
        when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)
        else greatest(0,public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)-pm.baseline)
      end)
    end,
    'done',case
      when c.mission_id is null then false
      when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)>=c.target
      else greatest(0,public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)-pm.baseline)>=c.target
    end,
    'absoluteProgress',coalesce(c.absolute_progress,false),
    'title',c.title,
    'description',c.description,
    'rewardRelics',coalesce(c.reward_relics,0),
    'rewardChrono',coalesce(c.reward_chrono,0),
    'rewardReputation',coalesce(c.reward_reputation,0)
  ) order by pm.slot_index),'[]'::jsonb)
  into v_slots
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c on c.mission_id=pm.mission_id and c.active
  where pm.user_id=p_user_id and pm.slot_key like 'normal:%';

  select jsonb_build_object(
    'slotKey',pm.slot_key,'slotIndex',pm.slot_index,'difficulty',pm.difficulty,
    'missionId',pm.mission_id,'baseline',pm.baseline,
    'cooldownUntil',case when pm.cooldown_until is null then 0 else floor(extract(epoch from pm.cooldown_until)*1000)::bigint end,
    'claimed',pm.claimed,'lastMissionId',pm.last_mission_id,'metric',c.metric,
    'target',coalesce(c.target,0),
    'current',public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric),
    'progress',case when c.mission_id is null then 0 else least(c.target,case when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric) else greatest(0,public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)-pm.baseline) end) end,
    'done',case when c.mission_id is null then false when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)>=c.target else greatest(0,public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)-pm.baseline)>=c.target end,
    'absoluteProgress',coalesce(c.absolute_progress,false),'title',c.title,'description',c.description,
    'rewardRelics',coalesce(c.reward_relics,0),'rewardChrono',coalesce(c.reward_chrono,0),'rewardReputation',coalesce(c.reward_reputation,0)
  ) into v_extreme
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c on c.mission_id=pm.mission_id and c.active
  where pm.user_id=p_user_id and pm.slot_key='extreme';

  select jsonb_build_object(
    'slotKey',pm.slot_key,'slotIndex',pm.slot_index,'difficulty',pm.difficulty,
    'missionId',pm.mission_id,'baseline',pm.baseline,'cooldownUntil',0,
    'claimed',pm.claimed,'lastMissionId',pm.last_mission_id,'metric',c.metric,
    'target',coalesce(c.target,0),
    'current',public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric),
    'progress',case when c.mission_id is null then 0 else least(c.target,case when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric) else greatest(0,public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)-pm.baseline) end) end,
    'done',case when c.mission_id is null then false when c.absolute_progress then public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)>=c.target else greatest(0,public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric)-pm.baseline)>=c.target end,
    'absoluteProgress',coalesce(c.absolute_progress,false),'title',c.title,'description',c.description,
    'rewardRelics',coalesce(c.reward_relics,0),'rewardChrono',coalesce(c.reward_chrono,0),'rewardReputation',coalesce(c.reward_reputation,0)
  ) into v_secret
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c on c.mission_id=pm.mission_id and c.active
  where pm.user_id=p_user_id and pm.slot_key='secret';

  select count(*) into v_invalid
  from public.chrono_player_missions pm
  left join public.chrono_mission_catalog c on c.mission_id=pm.mission_id and c.active
  where pm.user_id=p_user_id and pm.mission_id is not null and c.mission_id is null;

  select count(*) into v_duplicates
  from (
    select pm.mission_id
    from public.chrono_player_missions pm
    where pm.user_id=p_user_id and pm.slot_key like 'normal:%' and pm.mission_id is not null
    group by pm.mission_id having count(*)>1
  ) d;

  select count(*) into v_impossible
  from public.chrono_player_missions pm
  join public.chrono_mission_catalog c on c.mission_id=pm.mission_id and c.active
  where pm.user_id=p_user_id and not c.absolute_progress
    and pm.baseline>public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),c.metric);

  select count(*) into v_bad_shape
  from public.chrono_player_missions pm
  where pm.user_id=p_user_id and not (
    (slot_key='normal:0' and slot_index=0 and difficulty='easy') or
    (slot_key='normal:1' and slot_index=1 and difficulty='easy') or
    (slot_key='normal:2' and slot_index=2 and difficulty='easy') or
    (slot_key='normal:3' and slot_index=3 and difficulty='medium') or
    (slot_key='normal:4' and slot_index=4 and difficulty='medium') or
    (slot_key='normal:5' and slot_index=5 and difficulty='hard') or
    (slot_key='extreme' and slot_index=6 and difficulty='extreme') or
    (slot_key='secret' and slot_index=7 and difficulty='secret')
  );

  return jsonb_build_object(
    'enabled',v_state.wallet_authority_enabled and v_state.mission_rewards_enabled,
    'authority','server',
    'catalogRevision',874,
    'reputation',v_state.mission_reputation,
    'stats',coalesce(v_state.mission_stats,'{}'::jsonb),
    'slots',v_slots,
    'extreme',coalesce(v_extreme,'{}'::jsonb),
    'secret',coalesce(v_secret,'{}'::jsonb),
    'serverTime',floor(extract(epoch from now())*1000)::bigint,
    'revision',v_state.revision,
    'legacyReconciledAt',v_state.mission_legacy_reconciled_at,
    'legacyImportedCount',v_state.mission_legacy_imported_count,
    'audit',jsonb_build_object(
      'normalSlots',jsonb_array_length(v_slots),
      'invalidMissions',v_invalid,
      'duplicateMissions',v_duplicates,
      'impossibleBaselines',v_impossible,
      'invalidSlotShape',v_bad_shape
    ),
    'state',to_jsonb(v_state)
  );
end;
$$;


-- Recuperação de partidas interrompidas com o mesmo orçamento global por tipo
-- usado na liquidação. Checkpoints antigos ou malformados não podem contar a
-- mesma morte em várias categorias de Missão.
create or replace function public.chrono_recover_stale_run_checkpoints_server(
  p_user_id uuid,
  p_stale_seconds integer default 45,
  p_force boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_session public.chrono_game_sessions%rowtype;
  v_checkpoint jsonb;
  v_stats jsonb;
  v_save jsonb;
  v_meta jsonb;
  v_saved_ms bigint;
  v_kills bigint;
  v_boss bigint;
  v_elite bigint;
  v_skills bigint;
  v_wave bigint;
  v_key text;
  v_value_text text;
  v_value bigint;
  v_remaining bigint;
  v_raw_types jsonb;
  v_recovered integer := 0;
  v_abandoned integer := 0;
  v_recovered_kills bigint := 0;
begin
  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('recovered',0,'abandoned',0,'state',null);
  end if;

  v_stats := coalesce(v_state.mission_stats,coalesce(v_state.save_data #> '{chrono_v4_meta,stats}','{}'::jsonb));
  v_stats := jsonb_set(v_stats,'{typeKills}',coalesce(v_stats->'typeKills','{}'::jsonb),true);
  v_stats := jsonb_set(v_stats,'{classKills}',coalesce(v_stats->'classKills','{}'::jsonb),true);
  v_stats := jsonb_set(v_stats,'{classBossKills}',coalesce(v_stats->'classBossKills','{}'::jsonb),true);
  v_stats := jsonb_set(v_stats,'{classSkillUses}',coalesce(v_stats->'classSkillUses','{}'::jsonb),true);

  for v_session in
    select * from public.chrono_game_sessions
    where user_id=p_user_id and status='active'
    order by started_at
    for update
  loop
    v_checkpoint := coalesce(v_session.summary->'checkpoint','{}'::jsonb);
    v_saved_ms := public.chrono_jsonb_bigint(v_checkpoint,array['savedAt']);

    if not p_force then
      if v_saved_ms<=0 then continue; end if;
      if to_timestamp(v_saved_ms/1000.0)>now()-make_interval(secs=>greatest(15,least(3600,p_stale_seconds))) then continue; end if;
    end if;

    v_abandoned := v_abandoned+1;
    v_kills := greatest(0,public.chrono_jsonb_bigint(v_checkpoint,array['kills']));
    v_boss := least(v_kills,greatest(0,public.chrono_jsonb_bigint(v_checkpoint,array['bossKills'])));
    v_elite := least(v_kills,greatest(0,public.chrono_jsonb_bigint(v_checkpoint,array['eliteKills'])));
    v_skills := greatest(0,public.chrono_jsonb_bigint(v_checkpoint,array['skillsUsed']));
    v_wave := greatest(0,public.chrono_jsonb_bigint(v_checkpoint,array['wave']));

    if v_kills>0 or v_boss>0 or v_elite>0 or v_skills>0 or v_wave>0 then
      v_stats := public.chrono_jsonb_increment(v_stats,array['totalKills'],v_kills);
      v_stats := public.chrono_jsonb_increment(v_stats,array['bossKills'],v_boss);
      v_stats := public.chrono_jsonb_increment(v_stats,array['eliteKills'],v_elite);
      v_stats := public.chrono_jsonb_increment(v_stats,array['skillsUsed'],v_skills);
      v_stats := jsonb_set(v_stats,array['maxWave'],to_jsonb(greatest(public.chrono_jsonb_bigint(v_stats,array['maxWave']),v_wave)),true);
      v_stats := public.chrono_jsonb_increment(v_stats,array['classKills',v_session.class_key],v_kills);
      v_stats := public.chrono_jsonb_increment(v_stats,array['classBossKills',v_session.class_key],v_boss);
      v_stats := public.chrono_jsonb_increment(v_stats,array['classSkillUses',v_session.class_key],v_skills);

      v_raw_types := '{}'::jsonb;
      if jsonb_typeof(v_checkpoint->'typeKills')='object' then
        for v_key,v_value_text in select key,value from jsonb_each_text(v_checkpoint->'typeKills') loop
          if v_key=any(array['chaser','swarmer','strafer','tank','bomber','sentinel','vomiter','pukeling'])
             and v_value_text~'^[0-9]+$' and length(v_value_text)<=10 then
            v_raw_types := jsonb_set(v_raw_types,array[v_key],to_jsonb(least(v_kills,v_value_text::bigint)),true);
          end if;
        end loop;
      end if;

      v_remaining := v_kills;
      foreach v_key in array array['chaser','swarmer','strafer','tank','bomber','sentinel','vomiter','pukeling'] loop
        v_value := least(public.chrono_jsonb_bigint(v_raw_types,array[v_key]),v_remaining);
        if v_value>0 then
          v_stats := public.chrono_jsonb_increment(v_stats,array['typeKills',v_key],v_value);
          v_remaining := v_remaining-v_value;
        end if;
      end loop;

      v_recovered := v_recovered+1;
      v_recovered_kills := v_recovered_kills+v_kills;
    end if;

    update public.chrono_game_sessions
    set status='abandoned',ended_at=now(),
        summary=jsonb_set(
          jsonb_set(coalesce(summary,'{}'::jsonb),'{checkpointRecovered}',to_jsonb(v_kills>0 or v_skills>0 or v_wave>0),true),
          '{checkpointRecoveredAt}',to_jsonb(now()),true
        )
    where id=v_session.id;
  end loop;

  if v_recovered>0 then
    v_save := coalesce(v_state.save_data,'{}'::jsonb);
    v_meta := coalesce(v_save->'chrono_v4_meta','{}'::jsonb);
    v_meta := jsonb_set(v_meta,'{stats}',v_stats,true);
    v_save := jsonb_set(v_save,'{chrono_v4_meta}',v_meta,true);

    update public.chrono_player_state
    set mission_stats=v_stats,save_data=v_save,mission_stats_updated_at=now(),revision=revision+1
    where user_id=p_user_id
    returning * into v_state;
  end if;

  return jsonb_build_object(
    'recovered',v_recovered,
    'abandoned',v_abandoned,
    'recoveredKills',v_recovered_kills,
    'state',to_jsonb(v_state)
  );
end;
$$;

revoke all on function public.chrono_recover_stale_run_checkpoints_server(uuid,integer,boolean) from public,anon,authenticated;
grant execute on function public.chrono_recover_stale_run_checkpoints_server(uuid,integer,boolean) to service_role;

comment on function public.chrono_recover_stale_run_checkpoints_server(uuid,integer,boolean) is
  'Recupera feitos de Missões de runs abandonadas com orçamento global de tipos — Chrono Shards 8.7.4.';

revoke all on function public.chrono_prepare_missions_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_mission_payload(uuid) from public,anon,authenticated;
grant execute on function public.chrono_prepare_missions_server(uuid) to service_role;
grant execute on function public.chrono_mission_payload(uuid) to service_role;

comment on function public.chrono_prepare_missions_server(uuid) is
  'Normaliza os oito slots oficiais, repara duplicatas/baselines e prepara rotações sem depender do cliente.';
comment on function public.chrono_mission_payload(uuid) is
  'Payload autoritativo 8.7.4 com slots estáveis, progresso limitado à meta e auditoria estrutural.';

commit;
