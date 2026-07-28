-- Chrono Shards Cloud Save — fase 4
-- Missões e códigos promocionais validados pelo servidor.
-- Execute este arquivo UMA VEZ no SQL Editor do Supabase, depois das migrações
-- 8.5.0, 8.5.2 e 8.5.4.

alter table public.chrono_player_state
  add column if not exists mission_rewards_enabled boolean not null default false,
  add column if not exists code_rewards_enabled boolean not null default false,
  add column if not exists mission_reputation bigint not null default 0 check (mission_reputation >= 0),
  add column if not exists mission_stats jsonb not null default '{}'::jsonb,
  add column if not exists mission_rewards_enabled_at timestamptz,
  add column if not exists code_rewards_enabled_at timestamptz;

create or replace function public.chrono_jsonb_bigint(
  p_doc jsonb,
  p_path text[]
)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text;
begin
  v_text := coalesce(p_doc #>> p_path, '');
  if v_text ~ '^[0-9]+$' and length(v_text) <= 18 then
    return greatest(0, v_text::bigint);
  end if;
  return 0;
end;
$$;

create or replace function public.chrono_jsonb_increment(
  p_doc jsonb,
  p_path text[],
  p_amount bigint
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_doc jsonb := coalesce(p_doc, '{}'::jsonb);
  v_current bigint;
begin
  v_current := public.chrono_jsonb_bigint(v_doc, p_path);
  return jsonb_set(
    v_doc,
    p_path,
    to_jsonb(greatest(0, v_current + greatest(0, p_amount))),
    true
  );
end;
$$;

create or replace function public.chrono_metric_value(
  p_stats jsonb,
  p_metric text
)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
begin
  return public.chrono_jsonb_bigint(
    coalesce(p_stats, '{}'::jsonb),
    string_to_array(coalesce(p_metric, ''), '.')
  );
end;
$$;

-- Aproveita, uma única vez, o histórico que já havia sido migrado para o save
-- online. Depois desta fase, os novos valores passam a ser acumulados por runs
-- liquidadas pelo servidor.
update public.chrono_player_state
set mission_stats = case
      when mission_stats = '{}'::jsonb then
        coalesce(save_data #> '{chrono_v4_meta,stats}', '{}'::jsonb)
      else mission_stats
    end,
    mission_reputation = greatest(
      mission_reputation,
      public.chrono_jsonb_bigint(
        coalesce(save_data -> 'chrono_v4_meta', '{}'::jsonb),
        array['missionReputation489']
      )
    );

create table if not exists public.chrono_mission_catalog (
  mission_id text primary key,
  difficulty text not null check (difficulty in ('easy','medium','hard','extreme','secret')),
  title text not null,
  description text not null,
  metric text not null,
  target bigint not null check (target > 0),
  reward_relics integer not null default 0 check (reward_relics >= 0),
  reward_chrono integer not null default 0 check (reward_chrono >= 0),
  reward_reputation integer not null default 0 check (reward_reputation >= 0),
  cooldown_seconds integer not null default 0 check (cooldown_seconds >= 0),
  absolute_progress boolean not null default false,
  active boolean not null default true
);

insert into public.chrono_mission_catalog
  (mission_id,difficulty,title,description,metric,target,reward_relics,reward_chrono,reward_reputation,cooldown_seconds,absolute_progress)
values
  ('e_k40','easy','Limpeza Rápida','Mate 40 inimigos.','totalKills',40,5,0,10,60,false),
  ('e_chaser12','easy','Caçadores Caídos','Mate 12 Chasers.','typeKills.chaser',12,5,0,10,60,false),
  ('e_swarmer14','easy','Inseticida Temporal','Mate 14 Swarmers.','typeKills.swarmer',14,5,0,10,60,false),
  ('e_strafer10','easy','Sem Zigue-Zague','Mate 10 Strafers.','typeKills.strafer',10,5,0,10,60,false),
  ('e_tank5','easy','Blindagem Quebrada','Mate 5 Tanks.','typeKills.tank',5,5,0,10,60,false),
  ('e_bomber7','easy','Pavio Apagado','Mate 7 Bombers.','typeKills.bomber',7,5,0,10,60,false),
  ('e_sentinel6','easy','Olhos Desligados','Mate 6 Sentinels.','typeKills.sentinel',6,5,0,10,60,false),
  ('e_elite3','easy','Primeira Elite','Mate 3 inimigos elite.','eliteKills',3,5,0,10,60,false),
  ('e_skill18','easy','Circuito Aquecido','Use 18 habilidades.','skillsUsed',18,5,0,10,60,false),
  ('e_assault24','easy','Linha de Frente','Mate 24 inimigos com o Assault.','classKills.assault',24,5,0,10,60,false),

  ('m_k130','medium','Purge de Aço','Mate 130 inimigos.','totalKills',130,10,0,25,180,false),
  ('m_boss3','medium','Caça aos Colossos','Derrote 3 bosses.','bossKills',3,10,0,25,180,false),
  ('m_elite12','medium','Fim da Guarda','Mate 12 inimigos elite.','eliteKills',12,10,0,25,180,false),
  ('m_skill42','medium','Sinfonia de Cooldowns','Use 42 habilidades.','skillsUsed',42,10,0,25,180,false),
  ('m_vomiter7','medium','Estômago de Ferro','Mate 7 Vomiters.','typeKills.vomiter',7,10,0,25,180,false),
  ('m_pukeling22','medium','Maré Ácida','Mate 22 Pukelings.','typeKills.pukeling',22,10,0,25,180,false),
  ('m_sniper45','medium','Sem Piscar','Mate 45 inimigos com o Sniper.','classKills.sniper',45,10,0,25,180,false),
  ('m_reaper50','medium','Ceifa Intermediária','Mate 50 inimigos com o Reaper.','classKills.reaper',50,10,0,25,180,false),
  ('m_mage45','medium','Feitiço Instável','Mate 45 inimigos com o Void Mage.','classKills.mage',45,10,0,25,180,false),
  ('m_chrono1','medium','Estilhaço Raro','Colete 1 Fragmento Chrono.','chronoFragmentsCollected',1,10,0,25,180,false),

  ('h_k340','hard','Massacre Chronal','Mate 340 inimigos.','totalKills',340,20,0,75,360,false),
  ('h_boss7','hard','Assinatura de Bosses','Derrote 7 bosses.','bossKills',7,20,0,75,360,false),
  ('h_elite30','hard','Queda da Vanguarda','Mate 30 inimigos elite.','eliteKills',30,20,0,75,360,false),
  ('h_skill90','hard','Arsenal Sem Descanso','Use 90 habilidades.','skillsUsed',90,20,0,75,360,false),
  ('h_colonel100','hard','Guerra Total','Mate 100 inimigos com o Coronel.','classKills.colonel',100,20,0,75,360,false),
  ('h_engineer100','hard','Máquinas Contra o Tempo','Mate 100 inimigos com o Artífice.','classKills.engineer',100,20,0,75,360,false),
  ('h_alchemist100','hard','Reação Irreversível','Mate 100 inimigos com o Alquimista.','classKills.alchemist',100,20,0,75,360,false),
  ('h_chrono2','hard','Ruptura Concentrada','Colete 2 Fragmentos Chrono.','chronoFragmentsCollected',2,20,0,75,360,false),

  ('x_k700','extreme','Extermínio Absoluto','Mate 700 inimigos antes de resgatar este contrato.','totalKills',700,50,1,150,300,false),
  ('x_boss10','extreme','Cadeia de Colossos','Derrote 10 bosses.','bossKills',10,50,1,150,300,false),
  ('x_elite65','extreme','Carnificina de Elite','Mate 65 inimigos elite.','eliteKills',65,50,1,150,300,false),
  ('x_skill170','extreme','Arsenal Sem Limites','Use 170 habilidades.','skillsUsed',170,50,1,150,300,false),
  ('x_chrono4','extreme','Ruptura Chronal','Colete 4 Fragmentos Chrono.','chronoFragmentsCollected',4,50,1,150,300,false),

  ('s_moon','secret','Luar Sangrento','Colete 5 Fragmentos Chrono. A recompensa permanece selada.','chronoFragmentsCollected',5,0,0,0,0,true)
on conflict (mission_id) do update set
  difficulty = excluded.difficulty,
  title = excluded.title,
  description = excluded.description,
  metric = excluded.metric,
  target = excluded.target,
  reward_relics = excluded.reward_relics,
  reward_chrono = excluded.reward_chrono,
  reward_reputation = excluded.reward_reputation,
  cooldown_seconds = excluded.cooldown_seconds,
  absolute_progress = excluded.absolute_progress,
  active = true;

create table if not exists public.chrono_player_missions (
  user_id uuid not null references auth.users(id) on delete cascade,
  slot_key text not null,
  slot_index integer not null default 0,
  difficulty text not null check (difficulty in ('easy','medium','hard','extreme','secret')),
  mission_id text references public.chrono_mission_catalog(mission_id),
  baseline bigint not null default 0 check (baseline >= 0),
  cooldown_until timestamptz,
  claimed boolean not null default false,
  last_mission_id text,
  updated_at timestamptz not null default now(),
  primary key (user_id, slot_key)
);

create index if not exists chrono_player_missions_user_idx
  on public.chrono_player_missions(user_id, slot_index);

create table if not exists public.chrono_reward_codes (
  code_hash text primary key,
  code_id text not null unique,
  label text not null,
  relic_shards integer not null default 0 check (relic_shards >= 0),
  chrono_fragments integer not null default 0 check (chrono_fragments >= 0),
  awakening_keys integer not null default 0 check (awakening_keys >= 0),
  sinner_tears integer not null default 0 check (sinner_tears >= 0),
  master_unlock boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.chrono_reward_codes
  (code_hash,code_id,label,relic_shards,chrono_fragments,awakening_keys,sinner_tears,master_unlock,active)
values
  ('9b928cf915def0104cf6824578b5d95687968f01ff84893ad0b7afdc3e86809e','r100','+100 relíquias recebidas!',100,0,0,0,false,true),
  ('fda5dc3d60c0c8578c28306ecfe28e83f30ddcf34ce733adc934b0023488720c','r250','+250 relíquias recebidas!',250,0,0,0,false,true),
  ('e38e6f022b5bf149d5b56f5ee326fb7282bc5cec0e1cfe84901e91f7e441b4d2','c7','+7 Fragmentos Chrono!',0,7,0,0,false,true),
  ('510766e99515c26c27c8dded209dc5774300d22f26042af82848120407414c21','master','Tudo liberado • +9.999 Lágrimas dos Pecadores!',0,0,0,9999,true,true)
on conflict (code_hash) do update set
  code_id = excluded.code_id,
  label = excluded.label,
  relic_shards = excluded.relic_shards,
  chrono_fragments = excluded.chrono_fragments,
  awakening_keys = excluded.awakening_keys,
  sinner_tears = excluded.sinner_tears,
  master_unlock = excluded.master_unlock,
  active = excluded.active;

create table if not exists public.chrono_redeemed_codes (
  user_id uuid not null references auth.users(id) on delete cascade,
  code_id text not null references public.chrono_reward_codes(code_id),
  redeemed_at timestamptz not null default now(),
  primary key (user_id, code_id)
);

-- Preserva códigos que já estavam marcados como usados no save migrado.
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
on conflict (user_id, code_id) do nothing;

alter table public.chrono_mission_catalog enable row level security;
alter table public.chrono_player_missions enable row level security;
alter table public.chrono_reward_codes enable row level security;
alter table public.chrono_redeemed_codes enable row level security;

revoke all on public.chrono_mission_catalog from public, anon, authenticated;
revoke all on public.chrono_player_missions from public, anon, authenticated;
revoke all on public.chrono_reward_codes from public, anon, authenticated;
revoke all on public.chrono_redeemed_codes from public, anon, authenticated;

grant all on public.chrono_mission_catalog to service_role;
grant all on public.chrono_player_missions to service_role;
grant all on public.chrono_reward_codes to service_role;
grant all on public.chrono_redeemed_codes to service_role;

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

  -- Slot extremo rotativo.
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

  -- Missão secreta absoluta. A conclusão antiga é preservada.
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
begin
  perform public.chrono_prepare_missions_server(p_user_id);

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'slotKey', pm.slot_key,
      'slotIndex', pm.slot_index,
      'difficulty', pm.difficulty,
      'missionId', pm.mission_id,
      'baseline', pm.baseline,
      'cooldownUntil', case when pm.cooldown_until is null then 0 else floor(extract(epoch from pm.cooldown_until) * 1000)::bigint end,
      'claimed', pm.claimed
    ) order by pm.slot_index
  ), '[]'::jsonb)
  into v_slots
  from public.chrono_player_missions pm
  where pm.user_id = p_user_id and pm.slot_key like 'normal:%';

  select jsonb_build_object(
      'slotKey', pm.slot_key,
      'slotIndex', pm.slot_index,
      'difficulty', pm.difficulty,
      'missionId', pm.mission_id,
      'baseline', pm.baseline,
      'cooldownUntil', case when pm.cooldown_until is null then 0 else floor(extract(epoch from pm.cooldown_until) * 1000)::bigint end,
      'claimed', pm.claimed,
      'lastMissionId', pm.last_mission_id
    )
  into v_extreme
  from public.chrono_player_missions pm
  where pm.user_id = p_user_id and pm.slot_key = 'extreme';

  select jsonb_build_object(
      'slotKey', pm.slot_key,
      'slotIndex', pm.slot_index,
      'difficulty', pm.difficulty,
      'missionId', pm.mission_id,
      'baseline', pm.baseline,
      'cooldownUntil', 0,
      'claimed', pm.claimed
    )
  into v_secret
  from public.chrono_player_missions pm
  where pm.user_id = p_user_id and pm.slot_key = 'secret';

  return jsonb_build_object(
    'enabled', v_state.mission_rewards_enabled,
    'reputation', v_state.mission_reputation,
    'stats', coalesce(v_state.mission_stats, '{}'::jsonb),
    'slots', v_slots,
    'extreme', coalesce(v_extreme, '{}'::jsonb),
    'secret', coalesce(v_secret, '{}'::jsonb),
    'state', to_jsonb(v_state)
  );
end;
$$;

create or replace function public.chrono_load_missions_server(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.chrono_mission_payload(p_user_id);
end;
$$;

create or replace function public.chrono_claim_mission_server(
  p_user_id uuid,
  p_request_id uuid,
  p_slot_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous jsonb;
  v_state public.chrono_player_state%rowtype;
  v_slot public.chrono_player_missions%rowtype;
  v_catalog public.chrono_mission_catalog%rowtype;
  v_current bigint;
  v_progress bigint;
  v_new_relics bigint;
  v_new_chrono bigint;
  v_new_rep bigint;
  v_save jsonb;
  v_meta jsonb;
  v_stats jsonb;
  v_response jsonb;
begin
  if p_slot_key not in ('normal:0','normal:1','normal:2','normal:3','normal:4','normal:5','extreme','secret') then
    raise exception 'Slot de missão inválido';
  end if;

  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id and request_id = p_request_id;

  if found then return v_previous; end if;

  perform public.chrono_prepare_missions_server(p_user_id);

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if not found or not v_state.initialized then
    raise exception 'Save online não inicializado';
  end if;
  if not v_state.wallet_authority_enabled or not v_state.mission_rewards_enabled then
    raise exception 'Recompensas de missão ainda não estão ativadas';
  end if;

  select * into v_slot
  from public.chrono_player_missions
  where user_id = p_user_id and slot_key = p_slot_key
  for update;

  if not found then raise exception 'Missão não encontrada'; end if;
  if v_slot.claimed then raise exception 'Esta missão já foi resgatada'; end if;
  if v_slot.mission_id is null then
    if v_slot.cooldown_until is not null and v_slot.cooldown_until > now() then
      raise exception 'Este contrato ainda está em cooldown';
    end if;
    raise exception 'Contrato ainda não preparado';
  end if;

  select * into v_catalog
  from public.chrono_mission_catalog
  where mission_id = v_slot.mission_id and active;

  if not found then raise exception 'Catálogo da missão indisponível'; end if;

  v_current := public.chrono_metric_value(v_state.mission_stats, v_catalog.metric);
  v_progress := case
    when v_catalog.absolute_progress then v_current
    else greatest(0, v_current - v_slot.baseline)
  end;

  if v_progress < v_catalog.target then
    raise exception 'Objetivo ainda não concluído no servidor (% de %)', v_progress, v_catalog.target;
  end if;

  v_new_relics := v_state.relic_shards + v_catalog.reward_relics;
  v_new_chrono := v_state.chrono_fragments + v_catalog.reward_chrono;
  v_new_rep := v_state.mission_reputation + v_catalog.reward_reputation;
  v_stats := coalesce(v_state.mission_stats, '{}'::jsonb);

  if v_catalog.reward_chrono > 0 then
    v_stats := public.chrono_jsonb_increment(
      v_stats,
      array['chronoFragmentsCollected'],
      v_catalog.reward_chrono
    );
  end if;

  v_save := coalesce(v_state.save_data, '{}'::jsonb);
  v_meta := coalesce(v_save -> 'chrono_v4_meta', '{}'::jsonb);
  v_meta := jsonb_set(v_meta, '{relicShards}', to_jsonb(v_new_relics), true);
  v_meta := jsonb_set(v_meta, '{chronoFragments}', to_jsonb(v_new_chrono), true);
  v_meta := jsonb_set(v_meta, '{missionReputation489}', to_jsonb(v_new_rep), true);
  v_meta := jsonb_set(v_meta, '{stats}', v_stats, true);

  if p_slot_key = 'secret' then
    v_meta := jsonb_set(v_meta, '{moonMissionClaimed}', 'true'::jsonb, true);
    update public.chrono_player_missions
    set claimed = true, updated_at = now()
    where user_id = p_user_id and slot_key = p_slot_key;
  else
    update public.chrono_player_missions
    set last_mission_id = v_slot.mission_id,
        mission_id = null,
        baseline = 0,
        cooldown_until = now() + make_interval(secs => v_catalog.cooldown_seconds),
        claimed = false,
        updated_at = now()
    where user_id = p_user_id and slot_key = p_slot_key;
  end if;

  v_save := jsonb_set(v_save, '{chrono_v4_meta}', v_meta, true);

  update public.chrono_player_state
  set relic_shards = v_new_relics,
      chrono_fragments = v_new_chrono,
      mission_reputation = v_new_rep,
      mission_stats = v_stats,
      save_data = v_save,
      revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  v_response := public.chrono_mission_payload(p_user_id)
    || jsonb_build_object(
      'accepted', true,
      'slotKey', p_slot_key,
      'missionId', v_catalog.mission_id,
      'rewardRelics', v_catalog.reward_relics,
      'rewardChrono', v_catalog.reward_chrono,
      'rewardReputation', v_catalog.reward_reputation,
      'secretUnlocked', p_slot_key = 'secret'
    );

  insert into public.chrono_action_receipts(user_id,request_id,action,response)
  values (p_user_id,p_request_id,'claim_mission',v_response);

  return v_response;
end;
$$;

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
    v_stats := public.chrono_jsonb_increment(
      v_stats,
      array['chronoFragmentsCollected'],
      v_code.chrono_fragments
    );
  end if;
  if v_code.master_unlock then
    v_stats := jsonb_set(
      v_stats,
      '{chronoFragmentsCollected}',
      to_jsonb(greatest(public.chrono_jsonb_bigint(v_stats,array['chronoFragmentsCollected']),999::bigint)),
      true
    );
    v_stats := jsonb_set(
      v_stats,
      '{maxWave}',
      to_jsonb(greatest(public.chrono_jsonb_bigint(v_stats,array['maxWave']),20::bigint)),
      true
    );
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

-- A ativação da economia passa a ligar também missões e códigos.
create or replace function public.chrono_enable_economy_server(
  p_user_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_previous jsonb;
  v_response jsonb;
begin
  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id and request_id = p_request_id;
  if found then return v_previous; end if;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;
  if not found then raise exception 'Save online não encontrado'; end if;
  if not v_state.initialized or v_state.legacy_imported_at is null then
    raise exception 'Faça a migração inicial do save antes de ativar a economia';
  end if;

  if not v_state.wallet_authority_enabled
     or not v_state.character_purchases_enabled
     or not v_state.run_results_enabled
     or not v_state.mission_rewards_enabled
     or not v_state.code_rewards_enabled then
    update public.chrono_player_state
    set wallet_authority_enabled = true,
        character_purchases_enabled = true,
        run_results_enabled = true,
        mission_rewards_enabled = true,
        code_rewards_enabled = true,
        wallet_authority_enabled_at = coalesce(wallet_authority_enabled_at, now()),
        run_rewards_enabled_at = coalesce(run_rewards_enabled_at, now()),
        mission_rewards_enabled_at = coalesce(mission_rewards_enabled_at, now()),
        code_rewards_enabled_at = coalesce(code_rewards_enabled_at, now()),
        mission_stats = case
          when mission_stats = '{}'::jsonb then coalesce(save_data #> '{chrono_v4_meta,stats}', '{}'::jsonb)
          else mission_stats
        end,
        mission_reputation = greatest(
          mission_reputation,
          public.chrono_jsonb_bigint(coalesce(save_data -> 'chrono_v4_meta','{}'::jsonb),array['missionReputation489'])
        ),
        revision = revision + 1
    where user_id = p_user_id
    returning * into v_state;
  end if;

  perform public.chrono_prepare_missions_server(p_user_id);

  v_response := jsonb_build_object(
    'enabled', true,
    'message', 'Compras, runs, missões e códigos usam o progresso oficial do servidor.',
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id,request_id,action,response)
  values (p_user_id,p_request_id,'enable_economy',v_response);
  return v_response;
end;
$$;

-- Usuários que já tinham ativado a carteira recebem automaticamente esta fase.
update public.chrono_player_state
set mission_rewards_enabled = true,
    code_rewards_enabled = true,
    mission_rewards_enabled_at = coalesce(mission_rewards_enabled_at, now()),
    code_rewards_enabled_at = coalesce(code_rewards_enabled_at, now())
where wallet_authority_enabled = true;

-- Liquidação de run com estatísticas usadas pelas missões oficiais.
create or replace function public.chrono_finish_run_server(
  p_user_id uuid,
  p_request_id uuid,
  p_session_id uuid,
  p_score bigint,
  p_wave integer,
  p_kills integer,
  p_gold bigint,
  p_relic_delta integer,
  p_chrono_delta integer,
  p_boss_kills integer,
  p_elite_kills integer,
  p_skills_used integer,
  p_type_kills jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.chrono_game_sessions%rowtype;
  v_state public.chrono_player_state%rowtype;
  v_previous jsonb;
  v_elapsed numeric;
  v_max_gold bigint;
  v_accepted_gold bigint;
  v_gold_relics integer;
  v_max_relic_delta integer;
  v_run_relics integer;
  v_max_chrono_delta integer;
  v_run_chrono integer;
  v_reward_relics integer;
  v_new_relics bigint;
  v_new_chrono bigint;
  v_new_high bigint;
  v_meta jsonb;
  v_stats jsonb;
  v_save jsonb;
  v_response jsonb;
  v_key text;
  v_value_text text;
  v_value bigint;
  v_type_total bigint := 0;
  v_allowed_types text[] := array['chaser','swarmer','strafer','tank','bomber','sentinel','vomiter','pukeling'];
  v_type_kills jsonb := coalesce(p_type_kills, '{}'::jsonb);
begin
  if p_score < 0 or p_wave < 0 or p_kills < 0 or p_gold < 0
     or p_relic_delta < 0 or p_chrono_delta < 0 or p_boss_kills < 0
     or p_elite_kills < 0 or p_skills_used < 0 then
    raise exception 'Valores negativos não são aceitos';
  end if;

  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id and request_id = p_request_id;
  if found then return v_previous; end if;

  select * into v_session
  from public.chrono_game_sessions
  where id = p_session_id and user_id = p_user_id
  for update;
  if not found then raise exception 'Sessão não encontrada'; end if;
  if v_session.status <> 'active' then raise exception 'Sessão já encerrada'; end if;

  v_elapsed := extract(epoch from (now() - v_session.started_at));
  if v_elapsed < 5 then raise exception 'Partida curta demais'; end if;
  if p_kills > ceil(v_elapsed * 25 + 300) then raise exception 'Abates incompatíveis com a duração'; end if;
  if p_wave > floor(v_elapsed / 3) + 40 then raise exception 'Wave incompatível com a duração'; end if;
  if p_score > (p_kills * 500000::bigint) + (p_wave * 5000000::bigint) + 50000000::bigint then
    raise exception 'Score incompatível com o resumo';
  end if;
  if p_boss_kills > p_kills or p_boss_kills > (p_wave * 4 + 20) then
    raise exception 'Quantidade de bosses incompatível com a run';
  end if;
  if p_elite_kills > p_kills or p_elite_kills > ceil(p_kills * 0.75 + 20) then
    raise exception 'Quantidade de elites incompatível com a run';
  end if;
  if p_skills_used > ceil(v_elapsed * 8 + 240) then
    raise exception 'Uso de habilidades incompatível com a duração';
  end if;
  if jsonb_typeof(v_type_kills) <> 'object' then raise exception 'Resumo de inimigos inválido'; end if;

  for v_key,v_value_text in select key,value from jsonb_each_text(v_type_kills) loop
    if not (v_key = any(v_allowed_types)) then raise exception 'Tipo de inimigo inválido'; end if;
    if v_value_text !~ '^[0-9]+$' or length(v_value_text) > 10 then raise exception 'Contagem de inimigo inválida'; end if;
    v_value := v_value_text::bigint;
    if v_value > p_kills then raise exception 'Contagem por tipo maior que os abates'; end if;
    v_type_total := v_type_total + v_value;
  end loop;
  if v_type_total > p_kills then raise exception 'Soma de inimigos maior que os abates'; end if;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;
  if not found or not v_state.initialized then raise exception 'Save online não inicializado'; end if;
  if not v_state.wallet_authority_enabled or not v_state.run_results_enabled then
    raise exception 'Recompensas de partida ainda não estão ativadas';
  end if;

  v_max_gold := least(250000::bigint,greatest(500::bigint,500::bigint+p_kills::bigint*45::bigint+p_wave::bigint*650::bigint+floor(v_elapsed*15)::bigint));
  v_accepted_gold := least(p_gold,v_max_gold);
  v_gold_relics := floor(v_accepted_gold/50.0)::integer;
  v_max_relic_delta := least(180,greatest(3,8+floor(p_kills/18.0)::integer+floor(p_wave*1.75)::integer));
  v_run_relics := least(p_relic_delta,v_max_relic_delta);
  v_max_chrono_delta := least(24,greatest(1,1+floor(p_wave/4.0)::integer+floor(p_kills/160.0)::integer));
  v_run_chrono := least(p_chrono_delta,v_max_chrono_delta);

  v_reward_relics := v_gold_relics+v_run_relics;
  v_new_relics := v_state.relic_shards+v_reward_relics;
  v_new_chrono := v_state.chrono_fragments+v_run_chrono;
  v_new_high := greatest(v_state.high_score,p_score);

  v_stats := coalesce(v_state.mission_stats,coalesce(v_state.save_data #> '{chrono_v4_meta,stats}','{}'::jsonb));
  v_stats := jsonb_set(v_stats,'{typeKills}',coalesce(v_stats->'typeKills','{}'::jsonb),true);
  v_stats := jsonb_set(v_stats,'{classKills}',coalesce(v_stats->'classKills','{}'::jsonb),true);
  v_stats := jsonb_set(v_stats,'{classBossKills}',coalesce(v_stats->'classBossKills','{}'::jsonb),true);
  v_stats := jsonb_set(v_stats,'{classSkillUses}',coalesce(v_stats->'classSkillUses','{}'::jsonb),true);
  v_stats := public.chrono_jsonb_increment(v_stats,array['totalKills'],p_kills);
  v_stats := public.chrono_jsonb_increment(v_stats,array['bossKills'],p_boss_kills);
  v_stats := public.chrono_jsonb_increment(v_stats,array['eliteKills'],p_elite_kills);
  v_stats := public.chrono_jsonb_increment(v_stats,array['skillsUsed'],p_skills_used);
  v_stats := public.chrono_jsonb_increment(v_stats,array['chronoFragmentsCollected'],v_run_chrono);
  v_stats := jsonb_set(v_stats,array['maxWave'],to_jsonb(greatest(public.chrono_jsonb_bigint(v_stats,array['maxWave']),p_wave::bigint)),true);
  v_stats := public.chrono_jsonb_increment(v_stats,array['classKills',v_session.class_key],p_kills);
  v_stats := public.chrono_jsonb_increment(v_stats,array['classBossKills',v_session.class_key],p_boss_kills);
  v_stats := public.chrono_jsonb_increment(v_stats,array['classSkillUses',v_session.class_key],p_skills_used);

  for v_key,v_value_text in select key,value from jsonb_each_text(v_type_kills) loop
    v_stats := public.chrono_jsonb_increment(v_stats,array['typeKills',v_key],v_value_text::bigint);
  end loop;

  v_save := coalesce(v_state.save_data,'{}'::jsonb);
  v_meta := coalesce(v_save->'chrono_v4_meta','{}'::jsonb);
  v_meta := jsonb_set(v_meta,'{relicShards}',to_jsonb(v_new_relics),true);
  v_meta := jsonb_set(v_meta,'{chronoFragments}',to_jsonb(v_new_chrono),true);
  v_meta := jsonb_set(v_meta,'{highScore}',to_jsonb(v_new_high),true);
  v_meta := jsonb_set(v_meta,'{stats}',v_stats,true);
  v_save := jsonb_set(v_save,'{chrono_v4_meta}',v_meta,true);

  update public.chrono_game_sessions
  set status='finished',ended_at=now(),score=p_score,wave=p_wave,kills=p_kills,
      summary=jsonb_build_object(
        'elapsedSeconds',v_elapsed,'goldClaimed',p_gold,'goldAccepted',v_accepted_gold,
        'goldRelics',v_gold_relics,'relicDeltaClaimed',p_relic_delta,
        'relicDeltaAccepted',v_run_relics,'chronoDeltaClaimed',p_chrono_delta,
        'chronoDeltaAccepted',v_run_chrono,'rewardRelics',v_reward_relics,
        'bossKills',p_boss_kills,'eliteKills',p_elite_kills,
        'skillsUsed',p_skills_used,'typeKills',v_type_kills
      )
  where id=p_session_id;

  update public.chrono_player_state
  set relic_shards=v_new_relics,chrono_fragments=v_new_chrono,high_score=v_new_high,
      mission_stats=v_stats,save_data=v_save,revision=revision+1
  where user_id=p_user_id
  returning * into v_state;

  v_response := jsonb_build_object(
    'accepted',true,'progressApplied',true,'rewardRelics',v_reward_relics,
    'rewardChrono',v_run_chrono,'goldRelics',v_gold_relics,'runRelics',v_run_relics,
    'limits',jsonb_build_object('gold',v_max_gold,'relicDelta',v_max_relic_delta,'chronoDelta',v_max_chrono_delta),
    'claimed',jsonb_build_object('gold',p_gold,'relicDelta',p_relic_delta,'chronoDelta',p_chrono_delta),
    'state',to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id,request_id,action,response)
  values (p_user_id,p_request_id,'finish_run_v3',v_response);
  return v_response;
end;
$$;

revoke all on function public.chrono_jsonb_bigint(jsonb,text[]) from public,anon,authenticated;
revoke all on function public.chrono_jsonb_increment(jsonb,text[],bigint) from public,anon,authenticated;
revoke all on function public.chrono_metric_value(jsonb,text) from public,anon,authenticated;
revoke all on function public.chrono_prepare_missions_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_mission_payload(uuid) from public,anon,authenticated;
revoke all on function public.chrono_load_missions_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_claim_mission_server(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.chrono_redeem_code_server(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.chrono_enable_economy_server(uuid,uuid) from public,anon,authenticated;
revoke all on function public.chrono_finish_run_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb) from public,anon,authenticated;

grant execute on function public.chrono_jsonb_bigint(jsonb,text[]) to service_role;
grant execute on function public.chrono_jsonb_increment(jsonb,text[],bigint) to service_role;
grant execute on function public.chrono_metric_value(jsonb,text) to service_role;
grant execute on function public.chrono_prepare_missions_server(uuid) to service_role;
grant execute on function public.chrono_mission_payload(uuid) to service_role;
grant execute on function public.chrono_load_missions_server(uuid) to service_role;
grant execute on function public.chrono_claim_mission_server(uuid,uuid,text) to service_role;
grant execute on function public.chrono_redeem_code_server(uuid,uuid,text) to service_role;
grant execute on function public.chrono_enable_economy_server(uuid,uuid) to service_role;
grant execute on function public.chrono_finish_run_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb) to service_role;
