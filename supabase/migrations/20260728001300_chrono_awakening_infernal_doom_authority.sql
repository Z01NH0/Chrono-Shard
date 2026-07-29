-- Chrono Shards 8.5.18
-- Awakening + Loja Infernal + DOOM autoritativos.
-- Execute uma única vez após a migration 20260728001200.

begin;

create extension if not exists pgcrypto;

alter table public.chrono_player_state
  add column if not exists awakening_authority_enabled boolean not null default false,
  add column if not exists infernal_authority_enabled boolean not null default false,
  add column if not exists doom_authority_enabled boolean not null default false,
  add column if not exists progression_authority_enabled_at timestamptz;

alter table public.chrono_game_sessions
  add column if not exists server_context jsonb not null default '{}'::jsonb;

create table if not exists public.chrono_awakening_catalog (
  character_key text not null,
  stage integer not null check (stage between 1 and 5),
  title text not null,
  description text not null,
  metric text not null,
  target bigint not null check (target > 0),
  primary key (character_key, stage)
);

insert into public.chrono_awakening_catalog(character_key,stage,title,description,metric,target) values
('assault',1,'Cerco de Vanguarda','Mate 500 inimigos com o Assault depois de ativar esta etapa.','classKills.assault',500),
('assault',2,'Motor de Guerra','Use 120 habilidades com o Assault depois de ativar esta etapa.','classSkillUses.assault',120),
('assault',3,'Linha Inquebrável','Derrote 12 bosses com o Assault depois de ativar esta etapa.','classBossKills.assault',12),
('assault',4,'Modo Turbo Letal','Derrote 10 bosses enquanto o Modo Turbo estiver ativo.','assaultTurboBossKills',10),
('assault',5,'Comandante de Vanguarda','Mate 1600 inimigos com o Assault depois de ativar esta etapa.','classKills.assault',1600),
('sniper',1,'Calma Absoluta','Mate 450 inimigos com o Sniper depois de ativar esta etapa.','classKills.sniper',450),
('sniper',2,'Respiração de Aço','Mate 30 Sentinels depois de ativar esta etapa.','typeKills.sentinel',30),
('sniper',3,'Tiro Impossível','Mate 35 elites depois de ativar esta etapa.','eliteKills',35),
('sniper',4,'Executor Distante','Derrote 14 bosses com o Sniper depois de ativar esta etapa.','classBossKills.sniper',14),
('sniper',5,'Linha Perfeita','Mate 1450 inimigos com o Sniper depois de ativar esta etapa.','classKills.sniper',1450),
('reaper',1,'Primeira Ceifa','Mate 520 inimigos com o Reaper depois de ativar esta etapa.','classKills.reaper',520),
('reaper',2,'Fome de Almas','Use 120 habilidades com o Reaper depois de ativar esta etapa.','classSkillUses.reaper',120),
('reaper',3,'Ceifador de Elites','Mate 38 elites depois de ativar esta etapa.','eliteKills',38),
('reaper',4,'Contrato Final','Derrote 14 bosses com o Reaper depois de ativar esta etapa.','classBossKills.reaper',14),
('reaper',5,'Lâmina do Fim','Mate 1650 inimigos com o Reaper depois de ativar esta etapa.','classKills.reaper',1650),
('alchemist',1,'Fórmula Instável','Mate 460 inimigos com o Alquimista depois de ativar esta etapa.','classKills.alchemist',460),
('alchemist',2,'Mistura Perigosa','Use 125 habilidades com o Alquimista depois de ativar esta etapa.','classSkillUses.alchemist',125),
('alchemist',3,'Controle Químico','Mate 28 Vomiters depois de ativar esta etapa.','typeKills.vomiter',28),
('alchemist',4,'Experimento Maior','Derrote 12 bosses com o Alquimista depois de ativar esta etapa.','classBossKills.alchemist',12),
('alchemist',5,'Transmutação Total','Mate 1500 inimigos com o Alquimista depois de ativar esta etapa.','classKills.alchemist',1500),
('colonel',1,'Ordem de Avanço','Mate 520 inimigos com o Coronel depois de ativar esta etapa.','classKills.colonel',520),
('colonel',2,'Apoio Aéreo','Use 130 habilidades com o Coronel depois de ativar esta etapa.','classSkillUses.colonel',130),
('colonel',3,'Linha Mantida','Alcance a wave 30 depois de ativar esta etapa.','maxWave',30),
('colonel',4,'Operação Colosso','Derrote 15 bosses com o Coronel depois de ativar esta etapa.','classBossKills.colonel',15),
('colonel',5,'General das Dunas','Mate 1700 inimigos com o Coronel depois de ativar esta etapa.','classKills.colonel',1700),
('engineer',1,'Primeira Máquina','Mate 470 inimigos com o Artífice depois de ativar esta etapa.','classKills.engineer',470),
('engineer',2,'Engenharia de Guerra','Use 130 habilidades com o Artífice depois de ativar esta etapa.','classSkillUses.engineer',130),
('engineer',3,'Anti-Horda','Mate 80 Swarmers depois de ativar esta etapa.','typeKills.swarmer',80),
('engineer',4,'Torre Contra Titã','Derrote 13 bosses com o Artífice depois de ativar esta etapa.','classBossKills.engineer',13),
('engineer',5,'Fábrica de Vitória','Mate 1550 inimigos com o Artífice depois de ativar esta etapa.','classKills.engineer',1550),
('archer',1,'Lobo Solitário','Mate 520 inimigos com o Arqueiro do Chrono depois de ativar esta etapa.','classKills.archer',520),
('archer',2,'Puxada Perfeita','Use 130 habilidades com o Arqueiro do Chrono depois de ativar esta etapa.','classSkillUses.archer',130),
('archer',3,'Ponta Meteórica','Derrote 12 bosses com o Arqueiro do Chrono depois de ativar esta etapa.','classBossKills.archer',12),
('archer',4,'Caçada Completa','Alcance a wave 30 depois de ativar esta etapa.','maxWave',30),
('archer',5,'Sobrevivente da Explosão','Mate 1650 inimigos com o Arqueiro do Chrono depois de ativar esta etapa.','classKills.archer',1650),
('bomber',1,'Estopim de Guerra','Mate 500 inimigos com o Bombardeiro depois de ativar esta etapa.','classKills.bomber',500),
('bomber',2,'Matemática Explosiva','Use 130 habilidades com o Bombardeiro depois de ativar esta etapa.','classSkillUses.bomber',130),
('bomber',3,'Espelho do Estopim','Destrua 35 Bombers depois de ativar esta etapa.','typeKills.bomber',35),
('bomber',4,'Demolidor de Colossos','Derrote 13 bosses com o Bombardeiro depois de ativar esta etapa.','classBossKills.bomber',13),
('bomber',5,'Caminhante da Terra','Alcance a wave 32 com o Bombardeiro depois de ativar esta etapa.','maxWave',32),
('mage',1,'Ecos do Vazio','Mate 500 inimigos com o Void Mage depois de ativar esta etapa.','classKills.mage',500),
('mage',2,'Geometria Impossível','Use 135 habilidades com o Void Mage depois de ativar esta etapa.','classSkillUses.mage',135),
('mage',3,'Relógios sem Céu','Destrua 30 Carrapatos Cronais depois de ativar esta etapa.','typeKills.riftTick',30),
('mage',4,'Horizonte de Eventos','Derrote 14 bosses com o Void Mage depois de ativar esta etapa.','classBossKills.mage',14),
('mage',5,'Testemunha da Singularidade','Alcance a wave 32 com o Void Mage depois de ativar esta etapa.','maxWave',32),
('ronin',1,'Primeiro Segundo','Mate 500 inimigos com o Chrono Ronin depois de ativar esta etapa.','classKills.ronin',500),
('ronin',2,'Lâmina sem Som','Use 125 habilidades com o Chrono Ronin depois de ativar esta etapa.','classSkillUses.ronin',125),
('ronin',3,'Quatro Contatos','Realize 80 contatos de Parry depois de ativar esta etapa.','roninParryContacts8427',80),
('ronin',4,'Duelo contra o Destino','Derrote 14 bosses com o Chrono Ronin depois de ativar esta etapa.','classBossKills.ronin',14),
('ronin',5,'Marca dos Nove Segundos','Alcance a wave 32 com o Chrono Ronin depois de ativar esta etapa.','maxWave',32)
on conflict (character_key,stage) do update set
  title=excluded.title, description=excluded.description, metric=excluded.metric, target=excluded.target;

create table if not exists public.chrono_player_awakenings (
  user_id uuid not null references auth.users(id) on delete cascade,
  character_key text not null,
  journey_unlocked boolean not null default false,
  completed_stages integer not null default 0 check (completed_stages between 0 and 5),
  ultimate_unlocked boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, character_key)
);

create table if not exists public.chrono_player_awakening_active (
  user_id uuid primary key references auth.users(id) on delete cascade,
  character_key text not null,
  stage integer not null check (stage between 1 and 5),
  metric text not null,
  target bigint not null check (target > 0),
  baseline bigint not null default 0 check (baseline >= 0),
  progress bigint not null default 0 check (progress >= 0),
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (character_key, stage)
    references public.chrono_awakening_catalog(character_key, stage)
);

create table if not exists public.chrono_player_infernal (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nefalem_owned boolean not null default false,
  doom_unlocked boolean not null default false,
  infernal_relics text[] not null default '{}',
  legacy_levels jsonb not null default '{}'::jsonb,
  queued_doom_buffs text[] not null default '{}',
  demon_skins text[] not null default '{}',
  infernal_augments text[] not null default '{}',
  shop_epoch bigint not null default -1,
  shop_offers jsonb not null default '{}'::jsonb,
  shop_sold jsonb not null default '{}'::jsonb,
  pity_apoc integer not null default 0 check (pity_apoc >= 0),
  pity_heretic integer not null default 0 check (pity_heretic >= 0),
  doom_stats jsonb not null default '{}'::jsonb,
  imported_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.chrono_progression_run_counters (
  session_id uuid primary key references public.chrono_game_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  active_character text,
  active_stage integer,
  metric_value bigint not null default 0 check (metric_value >= 0),
  last_summary jsonb not null default '{}'::jsonb,
  finalized boolean not null default false,
  doom_reward bigint not null default 0 check (doom_reward >= 0),
  updated_at timestamptz not null default now()
);

create index if not exists chrono_player_awakenings_user_idx on public.chrono_player_awakenings(user_id);
create index if not exists chrono_progression_run_user_idx on public.chrono_progression_run_counters(user_id,updated_at desc);

alter table public.chrono_awakening_catalog enable row level security;
alter table public.chrono_player_awakenings enable row level security;
alter table public.chrono_player_awakening_active enable row level security;
alter table public.chrono_player_infernal enable row level security;
alter table public.chrono_progression_run_counters enable row level security;

revoke all on public.chrono_awakening_catalog from public, anon, authenticated;
revoke all on public.chrono_player_awakenings from public, anon, authenticated;
revoke all on public.chrono_player_awakening_active from public, anon, authenticated;
revoke all on public.chrono_player_infernal from public, anon, authenticated;
revoke all on public.chrono_progression_run_counters from public, anon, authenticated;
grant all on public.chrono_awakening_catalog to service_role;
grant all on public.chrono_player_awakenings to service_role;
grant all on public.chrono_player_awakening_active to service_role;
grant all on public.chrono_player_infernal to service_role;
grant all on public.chrono_progression_run_counters to service_role;

create or replace function public.chrono_array_has(p_values text[], p_value text)
returns boolean language sql immutable set search_path='' as $$
  select coalesce(p_value = any(coalesce(p_values,'{}'::text[])), false)
$$;

create or replace function public.chrono_valid_infernal_relic(p_id text)
returns boolean language sql immutable set search_path='' as $$
  select p_id = any(array['heart_ashes','butcher_horn','hungry_seal','abyss_eye','profane_chain'])
$$;

create or replace function public.chrono_valid_doom_buff(p_id text)
returns boolean language sql immutable set search_path='' as $$
  select p_id = any(array['boiling_blood','ash_step','tyrant_hunter','executioner_pact','greed_seal','last_prophecy','endless_fury'])
$$;

create or replace function public.chrono_valid_legacy(p_id text)
returns boolean language sql immutable set search_path='' as $$
  select p_id = any(array['ancestral_blood','chrono_conductor','golden_pact','soul_magnet','merchant_favor','forbidden_spark'])
$$;

create or replace function public.chrono_safe_int_text(p_value text, p_default integer default 0)
returns integer language plpgsql immutable set search_path='' as $$
begin
  if p_value is null or btrim(p_value)='' or p_value !~ '^-?[0-9]+$' then return p_default; end if;
  begin return p_value::integer; exception when others then return p_default; end;
end;
$$;

create or replace function public.chrono_safe_bool_text(p_value text, p_default boolean default false)
returns boolean language sql immutable set search_path='' as $$
  select case lower(coalesce(btrim(p_value),'')) when 'true' then true when 'false' then false when '1' then true when '0' then false else p_default end
$$;

create or replace function public.chrono_sanitize_legacy_levels(p_value jsonb)
returns jsonb language sql immutable set search_path='' as $$
  select jsonb_build_object(
    'ancestral_blood',least(5,greatest(0,public.chrono_safe_int_text(p_value->>'ancestral_blood',0))),
    'chrono_conductor',least(5,greatest(0,public.chrono_safe_int_text(p_value->>'chrono_conductor',0))),
    'golden_pact',least(5,greatest(0,public.chrono_safe_int_text(p_value->>'golden_pact',0))),
    'soul_magnet',least(4,greatest(0,public.chrono_safe_int_text(p_value->>'soul_magnet',0))),
    'merchant_favor',least(5,greatest(0,public.chrono_safe_int_text(p_value->>'merchant_favor',0))),
    'forbidden_spark',least(1,greatest(0,public.chrono_safe_int_text(p_value->>'forbidden_spark',0)))
  )
$$;

create or replace function public.chrono_valid_infernal_augment(p_id text)
returns boolean language sql immutable set search_path='' as $$
  select p_id = any(array[
    'assault_arsenal','assault_remorse','sniper_execution','sniper_still','engineer_maintenance','engineer_infernal',
    'mage_condensed_void','mage_between_doors','ronin_return_blade','ronin_oath','alchemist_volatile','alchemist_transmuter',
    'reaper_procession','reaper_eclipse','colonel_ghost','colonel_command','bomber_napalm','bomber_precision',
    'archer_celestial_string','archer_judgement','chrono_fractured_clock','chrono_prism_core','shadow_veil','shadow_heir',
    'moon_crescent','moon_sheath','rico_angle','rico_table'
  ])
$$;

create or replace function public.chrono_valid_demon_skin(p_id text)
returns boolean language sql immutable set search_path='' as $$
  select p_id ~ '^demon_(assault|sniper|engineer|mage|ronin|alchemist|reaper|colonel|bomber|archer|chronoHero|shadowChild|moonSlayer|rico|ricocheteador|stellarEmperor)_(common|rare|epic|legendary|heretic)$'
$$;

create or replace function public.chrono_shop_shuffled(p_values text[], p_user_id uuid, p_epoch bigint, p_salt text, p_limit integer default 100)
returns jsonb language sql stable set search_path='' as $$
  select coalesce(jsonb_agg(q.id order by q.sort_key), '[]'::jsonb)
  from (
    select id,md5(p_user_id::text || ':' || p_epoch::text || ':' || p_salt || ':' || id) as sort_key
    from unnest(coalesce(p_values,'{}'::text[])) id
    order by sort_key
    limit greatest(0,p_limit)
  ) q
$$;

create or replace function public.chrono_refresh_infernal_locked_server(p_user_id uuid)
returns public.chrono_player_infernal
language plpgsql security definer set search_path='' as $$
declare
  v_row public.chrono_player_infernal%rowtype;
  v_epoch bigint := floor(extract(epoch from now()) / 600)::bigint;
  v_augments text[];
  v_skins text[];
  v_permanent text[];
  v_buffs text[];
  v_all_skins text[];
begin
  insert into public.chrono_player_infernal(user_id) values(p_user_id)
  on conflict(user_id) do nothing;

  select * into v_row from public.chrono_player_infernal where user_id=p_user_id for update;

  if v_row.shop_epoch = v_epoch and jsonb_typeof(v_row.shop_offers)='object' then
    return v_row;
  end if;

  select coalesce(array_agg(id),'{}'::text[]) into v_augments
  from unnest(array[
    'assault_arsenal','assault_remorse','sniper_execution','sniper_still','engineer_maintenance','engineer_infernal',
    'mage_condensed_void','mage_between_doors','ronin_return_blade','ronin_oath','alchemist_volatile','alchemist_transmuter',
    'reaper_procession','reaper_eclipse','colonel_ghost','colonel_command','bomber_napalm','bomber_precision',
    'archer_celestial_string','archer_judgement','chrono_fractured_clock','chrono_prism_core','shadow_veil','shadow_heir',
    'moon_crescent','moon_sheath','rico_angle','rico_table'
  ]) id where not public.chrono_array_has(v_row.infernal_augments,id);

  select array_agg('demon_'||c||'_'||r) into v_all_skins
  from unnest(array['assault','sniper','engineer','mage','ronin','alchemist','reaper','colonel','bomber','archer','chronoHero','shadowChild','moonSlayer','ricocheteador','stellarEmperor']) c
  cross join unnest(array['common','rare','epic','legendary','heretic']) r;

  select coalesce(array_agg(id),'{}'::text[]) into v_skins
  from unnest(coalesce(v_all_skins,'{}'::text[])) id
  where not public.chrono_array_has(v_row.demon_skins,id);

  select coalesce(array_agg(id),'{}'::text[]) into v_permanent
  from unnest(array['heart_ashes','butcher_horn','hungry_seal','abyss_eye','profane_chain']) id
  where not public.chrono_array_has(v_row.infernal_relics,id);

  select coalesce(array_agg(id),'{}'::text[]) into v_buffs
  from unnest(array['boiling_blood','ash_step','tyrant_hunter','executioner_pact','greed_seal','last_prophecy','endless_fury']) id
  where not public.chrono_array_has(v_row.queued_doom_buffs,id);

  update public.chrono_player_infernal set
    shop_epoch=v_epoch,
    shop_offers=jsonb_build_object(
      'relics',public.chrono_shop_shuffled(array['relic12','relic30','relic70'],p_user_id,v_epoch,'relics',3),
      'chrono',public.chrono_shop_shuffled(array['chrono3','chrono10','chrono30'],p_user_id,v_epoch,'chrono',3),
      'augments',public.chrono_shop_shuffled(v_augments,p_user_id,v_epoch,'augments',3),
      'permanent',public.chrono_shop_shuffled(v_permanent,p_user_id,v_epoch,'permanent',3),
      'doomBuffs',public.chrono_shop_shuffled(v_buffs,p_user_id,v_epoch,'doomBuffs',3),
      'chests',public.chrono_shop_shuffled(array['profane','blood','throne'],p_user_id,v_epoch,'chests',3),
      'skins',public.chrono_shop_shuffled(v_skins,p_user_id,v_epoch,'skins',3)
    ),
    shop_sold='{}'::jsonb,
    updated_at=now()
  where user_id=p_user_id returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.chrono_sync_progression_save_server(p_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_inf public.chrono_player_infernal%rowtype;
  v_save jsonb; v_meta jsonb; v_completed jsonb; v_journeys jsonb; v_ultimates jsonb; v_active jsonb;
  v_skin jsonb; v_skin_unlocked jsonb; v_aug jsonb; v_aug_unlocked jsonb;
begin
  select * into v_state from public.chrono_player_state where user_id=p_user_id;
  if not found then return; end if;
  insert into public.chrono_player_infernal(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_inf from public.chrono_player_infernal where user_id=p_user_id;

  select coalesce(jsonb_object_agg(character_key,completed_stages),'{}'::jsonb),
         coalesce(jsonb_object_agg(character_key,journey_unlocked),'{}'::jsonb),
         coalesce(jsonb_object_agg(character_key,ultimate_unlocked),'{}'::jsonb)
    into v_completed,v_journeys,v_ultimates
  from public.chrono_player_awakenings where user_id=p_user_id;

  select case when a.user_id is null then 'null'::jsonb else jsonb_build_object(
    'id',a.character_key,'stage',a.stage-1,'baseline',a.baseline,'serverProgress',a.progress,
    'serverTarget',a.target,'serverMetric',a.metric,'startedAt',extract(epoch from a.started_at)*1000
  ) end into v_active
  from (select p_user_id as user_id) u left join public.chrono_player_awakening_active a on a.user_id=u.user_id;

  v_save:=coalesce(v_state.save_data,'{}'::jsonb); v_meta:=coalesce(v_save->'chrono_v4_meta','{}'::jsonb);
  v_meta:=jsonb_set(v_meta,'{awakeningKeys}',to_jsonb(v_state.awakening_keys),true);
  v_meta:=jsonb_set(v_meta,'{sinnerTears830}',to_jsonb(v_state.sinner_tears),true);
  v_meta:=jsonb_set(v_meta,'{doomFragments}',to_jsonb(v_state.sinner_tears),true);
  v_meta:=jsonb_set(v_meta,'{nefalemPurchased830}',to_jsonb(v_inf.nefalem_owned),true);
  v_meta:=jsonb_set(v_meta,'{doomModeUnlocked810}',to_jsonb(v_inf.doom_unlocked),true);
  v_meta:=jsonb_set(v_meta,'{doomModeUnlocked}',to_jsonb(v_inf.doom_unlocked),true);
  v_meta:=jsonb_set(v_meta,'{infernalRelics830}',to_jsonb(v_inf.infernal_relics),true);
  v_meta:=jsonb_set(v_meta,'{doomRunBuffs830}',to_jsonb(v_inf.queued_doom_buffs),true);
  v_meta:=jsonb_set(v_meta,'{infernalLegacy830}',coalesce(v_inf.legacy_levels,'{}'::jsonb),true);
  v_meta:=jsonb_set(v_meta,'{awakeningJourneys489}',coalesce(v_journeys,'{}'::jsonb),true);
  v_meta:=jsonb_set(v_meta,'{awakeningUltimates}',coalesce(v_ultimates,'{}'::jsonb),true);
  v_meta:=jsonb_set(v_meta,'{awakeningRewards480}',coalesce(v_ultimates,'{}'::jsonb),true);
  v_meta:=jsonb_set(v_meta,'{awakenings463}',jsonb_build_object('completed',coalesce(v_completed,'{}'::jsonb),'active',v_active),true);
  v_save:=jsonb_set(v_save,'{chrono_v4_meta}',v_meta,true);

  v_skin:=coalesce(v_save->'chrono_v4_meta_skins_clean_702','{}'::jsonb);
  v_skin_unlocked:=case when jsonb_typeof(v_skin->'unlocked')='object' then v_skin->'unlocked' else '{}'::jsonb end;
  select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into v_skin_unlocked
  from jsonb_each(v_skin_unlocked) where key not like 'demon\_%' escape '\';
  v_skin_unlocked:=coalesce(v_skin_unlocked,'{}'::jsonb) || coalesce((select jsonb_object_agg(x,true) from unnest(v_inf.demon_skins) x),'{}'::jsonb);
  v_skin:=jsonb_set(v_skin,'{unlocked}',v_skin_unlocked,true);
  v_save:=jsonb_set(v_save,'{chrono_v4_meta_skins_clean_702}',v_skin,true);

  v_aug:=coalesce(v_save->'chrono_v4_meta_chrono_augments_620','{}'::jsonb);
  v_aug_unlocked:=(case when jsonb_typeof(v_aug->'unlocked')='object' then v_aug->'unlocked' else '{}'::jsonb end) || coalesce((select jsonb_object_agg(x,true) from unnest(v_inf.infernal_augments) x),'{}'::jsonb);
  v_aug:=jsonb_set(v_aug,'{unlocked}',v_aug_unlocked,true);
  v_save:=jsonb_set(v_save,'{chrono_v4_meta_chrono_augments_620}',v_aug,true);

  update public.chrono_player_state set save_data=v_save where user_id=p_user_id;
end;
$$;

create or replace function public.chrono_progression_payload_server(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_state public.chrono_player_state%rowtype; v_inf public.chrono_player_infernal%rowtype;
  v_journeys jsonb; v_active jsonb;
begin
  insert into public.chrono_player_state(user_id) values(p_user_id) on conflict(user_id) do nothing;
  v_inf:=public.chrono_refresh_infernal_locked_server(p_user_id);
  select * into v_state from public.chrono_player_state where user_id=p_user_id;
  select coalesce(jsonb_object_agg(c.character_key,jsonb_build_object(
    'journeyUnlocked',coalesce(p.journey_unlocked,false),
    'completedStages',coalesce(p.completed_stages,0),
    'ultimateUnlocked',coalesce(p.ultimate_unlocked,false)
  )),'{}'::jsonb) into v_journeys
  from (select distinct character_key from public.chrono_awakening_catalog) c
  left join public.chrono_player_awakenings p on p.user_id=p_user_id and p.character_key=c.character_key;

  select case when a.user_id is null then 'null'::jsonb else jsonb_build_object(
    'characterKey',a.character_key,'stage',a.stage,'metric',a.metric,'target',a.target,
    'baseline',a.baseline,'progress',least(a.progress,a.target),'done',a.progress>=a.target,
    'startedAt',extract(epoch from a.started_at)*1000
  ) end into v_active
  from (select p_user_id as user_id) u left join public.chrono_player_awakening_active a on a.user_id=u.user_id;

  return jsonb_build_object(
    'serverTime',floor(extract(epoch from clock_timestamp())*1000),
    'awakening',jsonb_build_object('keys',v_state.awakening_keys,'journeys',v_journeys,'active',v_active),
    'infernal',jsonb_build_object(
      'tears',v_state.sinner_tears,'nefalemOwned',v_inf.nefalem_owned,'doomUnlocked',v_inf.doom_unlocked,
      'infernalRelics',to_jsonb(v_inf.infernal_relics),'legacyLevels',v_inf.legacy_levels,
      'queuedDoomBuffs',to_jsonb(v_inf.queued_doom_buffs),'demonSkins',to_jsonb(v_inf.demon_skins),
      'infernalAugments',to_jsonb(v_inf.infernal_augments),'doomStats',v_inf.doom_stats,
      'shop',jsonb_build_object(
        'version',2,'created',v_inf.shop_epoch*600000,'next',(v_inf.shop_epoch+1)*600000,
        'rotationId',p_user_id::text||':'||v_inf.shop_epoch::text,'offers',v_inf.shop_offers,
        'sold',v_inf.shop_sold,'pity',jsonb_build_object('apoc',v_inf.pity_apoc,'heretic',v_inf.pity_heretic)
      )
    )
  );
end;
$$;

create or replace function public.chrono_start_awakening_stage_server(p_user_id uuid,p_request_id uuid,p_character_key text,p_stage integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_previous jsonb; v_state public.chrono_player_state%rowtype; v_catalog public.chrono_awakening_catalog%rowtype;
  v_player public.chrono_player_awakenings%rowtype; v_response jsonb; v_baseline bigint;
begin
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;
  if found then return v_previous; end if;
  select * into v_catalog from public.chrono_awakening_catalog where character_key=p_character_key and stage=p_stage;
  if not found then raise exception 'Etapa de Awakening inválida'; end if;
  select * into v_state from public.chrono_player_state where user_id=p_user_id for update;
  if not found or not v_state.initialized then raise exception 'Save online não inicializado'; end if;
  if not v_state.awakening_authority_enabled then raise exception 'Awakening autoritativo ainda não foi ativado'; end if;
  if exists(select 1 from public.chrono_player_awakening_active where user_id=p_user_id) then raise exception 'Já existe uma etapa de Awakening ativa'; end if;
  insert into public.chrono_player_awakenings(user_id,character_key) values(p_user_id,p_character_key)
    on conflict(user_id,character_key) do nothing;
  select * into v_player from public.chrono_player_awakenings where user_id=p_user_id and character_key=p_character_key for update;
  if v_player.ultimate_unlocked then raise exception 'Ultimate já desbloqueada'; end if;
  if p_stage <> v_player.completed_stages+1 then raise exception 'Conclua as etapas anteriores primeiro'; end if;
  if v_state.awakening_keys < 1 then raise exception 'Chaves de Awakening insuficientes'; end if;
  v_baseline:=case when v_catalog.metric='maxWave' then 0 else public.chrono_metric_value(coalesce(v_state.mission_stats,'{}'::jsonb),v_catalog.metric) end;
  update public.chrono_player_awakenings set journey_unlocked=true,updated_at=now() where user_id=p_user_id and character_key=p_character_key;
  insert into public.chrono_player_awakening_active(user_id,character_key,stage,metric,target,baseline,progress)
    values(p_user_id,p_character_key,p_stage,v_catalog.metric,v_catalog.target,v_baseline,0);
  update public.chrono_player_state set awakening_keys=awakening_keys-1,revision=revision+1 where user_id=p_user_id returning * into v_state;
  perform public.chrono_sync_progression_save_server(p_user_id);
  v_response:=jsonb_build_object('started',true,'characterKey',p_character_key,'stage',p_stage,'progression',public.chrono_progression_payload_server(p_user_id),'state',to_jsonb(v_state));
  insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'awakening_start_stage',v_response);
  return v_response;
end;
$$;

create or replace function public.chrono_claim_awakening_stage_server(p_user_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_previous jsonb; v_active public.chrono_player_awakening_active%rowtype; v_response jsonb; v_state public.chrono_player_state%rowtype;
begin
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;
  if found then return v_previous; end if;
  select * into v_active from public.chrono_player_awakening_active where user_id=p_user_id for update;
  if not found then raise exception 'Nenhuma etapa de Awakening ativa'; end if;
  if v_active.progress < v_active.target then raise exception 'A etapa ainda não foi concluída'; end if;
  insert into public.chrono_player_awakenings(user_id,character_key,journey_unlocked,completed_stages)
    values(p_user_id,v_active.character_key,true,v_active.stage)
  on conflict(user_id,character_key) do update set journey_unlocked=true,completed_stages=greatest(public.chrono_player_awakenings.completed_stages,excluded.completed_stages),updated_at=now();
  delete from public.chrono_player_awakening_active where user_id=p_user_id;
  update public.chrono_player_state set revision=revision+1 where user_id=p_user_id returning * into v_state;
  perform public.chrono_sync_progression_save_server(p_user_id);
  v_response:=jsonb_build_object('claimed',true,'characterKey',v_active.character_key,'stage',v_active.stage,'progression',public.chrono_progression_payload_server(p_user_id),'state',to_jsonb(v_state));
  insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'awakening_claim_stage',v_response);
  return v_response;
end;
$$;

create or replace function public.chrono_claim_awakening_ultimate_server(p_user_id uuid,p_request_id uuid,p_character_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_previous jsonb; v_player public.chrono_player_awakenings%rowtype; v_response jsonb; v_state public.chrono_player_state%rowtype;
begin
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;
  if found then return v_previous; end if;
  select * into v_player from public.chrono_player_awakenings where user_id=p_user_id and character_key=p_character_key for update;
  if not found or v_player.completed_stages<5 then raise exception 'Complete as cinco etapas primeiro'; end if;
  if v_player.ultimate_unlocked then raise exception 'Ultimate já resgatada'; end if;
  update public.chrono_player_awakenings set ultimate_unlocked=true,updated_at=now() where user_id=p_user_id and character_key=p_character_key;
  update public.chrono_player_state set revision=revision+1 where user_id=p_user_id returning * into v_state;
  perform public.chrono_sync_progression_save_server(p_user_id);
  v_response:=jsonb_build_object('claimed',true,'characterKey',p_character_key,'progression',public.chrono_progression_payload_server(p_user_id),'state',to_jsonb(v_state));
  insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'awakening_claim_ultimate',v_response);
  return v_response;
end;
$$;

create or replace function public.chrono_infernal_item_price(p_section text,p_item text)
returns integer language plpgsql immutable set search_path='' as $$
begin
  if p_section='relics' then return case p_item when 'relic12' then 12 when 'relic30' then 26 when 'relic70' then 52 else null end;
  elsif p_section='chrono' then return case p_item when 'chrono3' then 20 when 'chrono10' then 55 when 'chrono30' then 135 else null end;
  elsif p_section='augments' and public.chrono_valid_infernal_augment(p_item) then return 120;
  elsif p_section='permanent' then return case p_item when 'heart_ashes' then 180 when 'butcher_horn' then 200 when 'hungry_seal' then 240 when 'abyss_eye' then 220 when 'profane_chain' then 200 else null end;
  elsif p_section='doomBuffs' then return case p_item when 'boiling_blood' then 20 when 'ash_step' then 18 when 'tyrant_hunter' then 30 when 'executioner_pact' then 35 when 'greed_seal' then 25 when 'last_prophecy' then 45 when 'endless_fury' then 28 else null end;
  elsif p_section='skins' and public.chrono_valid_demon_skin(p_item) then
    return case when p_item like '%_heretic' then 650 when p_item like '%_legendary' then 480 when p_item like '%_epic' then 360 when p_item like '%_rare' then 260 else 180 end;
  elsif p_section='chests' then return case p_item when 'profane' then 300 when 'blood' then 95 when 'throne' then 180 else null end;
  end if;
  return null;
end;
$$;

drop function if exists public.chrono_infernal_purchase_server(uuid,uuid,text,integer);

create or replace function public.chrono_infernal_purchase_server(p_user_id uuid,p_request_id uuid,p_section text,p_index integer,p_rotation_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_previous jsonb; v_state public.chrono_player_state%rowtype; v_inf public.chrono_player_infernal%rowtype;
  v_item text; v_base integer; v_cost integer; v_discount integer; v_currency text:='tears'; v_sold_key text;
  v_relics bigint; v_chrono bigint; v_tears bigint; v_reward jsonb:='{}'::jsonb; v_response jsonb;
  v_rarity integer; v_roll double precision; v_candidate text; v_qty integer;
begin
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;
  if found then return v_previous; end if;
  if not (p_section = any(array['relics','chrono','augments','permanent','doomBuffs','chests','skins'])) then raise exception 'Seção da Loja Infernal inválida'; end if;
  if p_index<0 or p_index>20 then raise exception 'Índice da oferta inválido'; end if;
  select * into v_state from public.chrono_player_state where user_id=p_user_id for update;
  if not found or not v_state.initialized then raise exception 'Save online não inicializado'; end if;
  if not v_state.infernal_authority_enabled then raise exception 'Loja Infernal autoritativa ainda não foi ativada'; end if;
  v_inf:=public.chrono_refresh_infernal_locked_server(p_user_id);
  if coalesce(p_rotation_id,'') <> p_user_id::text||':'||v_inf.shop_epoch::text then raise exception 'A rotação da Loja Infernal mudou; atualize as ofertas antes de comprar'; end if;
  v_item:=v_inf.shop_offers->p_section->>p_index;
  if v_item is null or v_item='' then raise exception 'Oferta indisponível nesta rotação'; end if;
  v_sold_key:=p_section||':'||p_index::text;
  if coalesce((v_inf.shop_sold->>v_sold_key)::boolean,false) then raise exception 'Oferta já comprada nesta rotação'; end if;
  v_base:=public.chrono_infernal_item_price(p_section,v_item);
  if v_base is null then raise exception 'Item da Loja Infernal inválido'; end if;
  v_discount:=least(5,greatest(0,coalesce((v_inf.legacy_levels->>'merchant_favor')::integer,0)));
  v_cost:=greatest(1,ceil(v_base*(100-v_discount)/100.0)::integer);
  if p_section='chests' and v_item='profane' then v_currency:='relics'; end if;
  v_relics:=v_state.relic_shards; v_chrono:=v_state.chrono_fragments; v_tears:=v_state.sinner_tears;
  if v_currency='relics' then if v_relics<v_cost then raise exception 'Relíquias insuficientes'; end if; v_relics:=v_relics-v_cost;
  else if v_tears<v_cost then raise exception 'Lágrimas dos Pecadores insuficientes'; end if; v_tears:=v_tears-v_cost; end if;

  if p_section='relics' then
    v_qty:=case v_item when 'relic12' then 12 when 'relic30' then 30 else 70 end; v_relics:=v_relics+v_qty;
    v_reward:=jsonb_build_object('kind','relics','amount',v_qty,'title','+'||v_qty||' Relíquias');
  elsif p_section='chrono' then
    v_qty:=case v_item when 'chrono3' then 3 when 'chrono10' then 10 else 30 end; v_chrono:=v_chrono+v_qty;
    v_reward:=jsonb_build_object('kind','chrono','amount',v_qty,'title','+'||v_qty||' Fragmentos Chrono');
  elsif p_section='augments' then
    if public.chrono_array_has(v_inf.infernal_augments,v_item) then raise exception 'Ampliação já adquirida'; end if;
    v_inf.infernal_augments:=array_append(v_inf.infernal_augments,v_item); v_reward:=jsonb_build_object('kind','augment','id',v_item,'title','Ampliação Chronal desbloqueada');
  elsif p_section='permanent' then
    if public.chrono_array_has(v_inf.infernal_relics,v_item) then raise exception 'Relíquia Infernal já adquirida'; end if;
    v_inf.infernal_relics:=array_append(v_inf.infernal_relics,v_item); v_reward:=jsonb_build_object('kind','infernalRelic','id',v_item,'title','Relíquia Infernal desbloqueada');
  elsif p_section='doomBuffs' then
    if public.chrono_array_has(v_inf.queued_doom_buffs,v_item) then raise exception 'Pacto já preparado'; end if;
    if cardinality(v_inf.queued_doom_buffs)>=2 then raise exception 'Limite de dois pactos DOOM atingido'; end if;
    v_inf.queued_doom_buffs:=array_append(v_inf.queued_doom_buffs,v_item); v_reward:=jsonb_build_object('kind','doomBuff','id',v_item,'title','Pacto preparado para o próximo DOOM');
  elsif p_section='skins' then
    if public.chrono_array_has(v_inf.demon_skins,v_item) then raise exception 'Skin já adquirida'; end if;
    v_inf.demon_skins:=array_append(v_inf.demon_skins,v_item); v_reward:=jsonb_build_object('kind','skin','id',v_item,'title','Skin demoníaca desbloqueada');
  elsif p_section='chests' then
    v_roll:=random();
    v_rarity:=case v_item when 'profane' then case when v_roll<.60 then 0 when v_roll<.88 then 1 when v_roll<.98 then 2 else 3 end
      when 'blood' then case when v_roll<.36 then 1 when v_roll<.72 then 2 when v_roll<.93 then 3 when v_roll<.995 then 4 else 5 end
      else case when v_roll<.22 then 2 when v_roll<.58 then 3 when v_roll<.88 then 4 else 5 end end;
    if v_inf.pity_heretic>=24 and v_item<>'profane' then v_rarity:=5;
    elsif v_inf.pity_apoc>=7 then v_rarity:=greatest(v_rarity,4); end if;
    v_inf.pity_apoc:=case when v_rarity>=4 then 0 else v_inf.pity_apoc+1 end;
    if v_item<>'profane' then v_inf.pity_heretic:=case when v_rarity>=5 then 0 else v_inf.pity_heretic+1 end; end if;
    v_roll:=random();
    if v_rarity<=1 then
      if v_roll<.78 then v_qty:=80+floor(random()*151)::integer;v_relics:=v_relics+v_qty;v_reward:=jsonb_build_object('kind','relics','amount',v_qty,'rarity',v_rarity,'title','+'||v_qty||' Relíquias');
      else v_qty:=1+v_rarity;v_chrono:=v_chrono+v_qty;v_reward:=jsonb_build_object('kind','chrono','amount',v_qty,'rarity',v_rarity,'title','+'||v_qty||' Fragmentos Chrono'); end if;
    elsif v_rarity=2 then
      select 'demon_'||c||'_'||r into v_candidate
      from unnest(array['assault','sniper','engineer','mage','ronin','alchemist','reaper','colonel','bomber','archer','chronoHero','shadowChild','moonSlayer','ricocheteador','stellarEmperor']) c
      cross join unnest(array['common','rare']) r
      where not public.chrono_array_has(v_inf.demon_skins,'demon_'||c||'_'||r)
      order by random() limit 1;
      if v_candidate is not null and v_roll>.55 then v_inf.demon_skins:=array_append(v_inf.demon_skins,v_candidate);v_reward:=jsonb_build_object('kind','skin','id',v_candidate,'rarity',v_rarity,'title','Skin demoníaca desbloqueada');
      else v_qty:=230+floor(random()*121)::integer;v_relics:=v_relics+v_qty;v_reward:=jsonb_build_object('kind','relics','amount',v_qty,'rarity',v_rarity,'title','+'||v_qty||' Relíquias'); end if;
    elsif v_rarity=3 then
      select id into v_candidate from unnest(array['assault_arsenal','assault_remorse','sniper_execution','sniper_still','engineer_maintenance','engineer_infernal','mage_condensed_void','mage_between_doors','ronin_return_blade','ronin_oath','alchemist_volatile','alchemist_transmuter','reaper_procession','reaper_eclipse','colonel_ghost','colonel_command','bomber_napalm','bomber_precision','archer_celestial_string','archer_judgement','chrono_fractured_clock','chrono_prism_core','shadow_veil','shadow_heir','moon_crescent','moon_sheath','rico_angle','rico_table']) id
      where not public.chrono_array_has(v_inf.infernal_augments,id) order by random() limit 1;
      if v_candidate is not null and v_roll>.68 then v_inf.infernal_augments:=array_append(v_inf.infernal_augments,v_candidate);v_reward:=jsonb_build_object('kind','augment','id',v_candidate,'rarity',v_rarity,'title','Ampliação Chronal desbloqueada');
      else v_qty:=380+floor(random()*151)::integer;v_relics:=v_relics+v_qty;v_reward:=jsonb_build_object('kind','relics','amount',v_qty,'rarity',v_rarity,'title','+'||v_qty||' Relíquias'); end if;
    elsif v_rarity=4 then
      select id into v_candidate from unnest(array['heart_ashes','butcher_horn','hungry_seal','abyss_eye','profane_chain']) id where not public.chrono_array_has(v_inf.infernal_relics,id) order by random() limit 1;
      if v_candidate is not null and v_roll>.72 then v_inf.infernal_relics:=array_append(v_inf.infernal_relics,v_candidate);v_reward:=jsonb_build_object('kind','infernalRelic','id',v_candidate,'rarity',v_rarity,'title','Relíquia Infernal desbloqueada');
      elsif v_roll>.45 then v_qty:=10;v_chrono:=v_chrono+v_qty;v_reward:=jsonb_build_object('kind','chrono','amount',v_qty,'rarity',v_rarity,'title','+10 Fragmentos Chrono');
      else v_qty:=700;v_relics:=v_relics+v_qty;v_reward:=jsonb_build_object('kind','relics','amount',v_qty,'rarity',v_rarity,'title','+700 Relíquias'); end if;
    else
      if v_roll<.34 then v_qty:=20;v_chrono:=v_chrono+v_qty;v_reward:=jsonb_build_object('kind','chrono','amount',v_qty,'rarity',v_rarity,'title','+20 Fragmentos Chrono');
      elsif v_roll<.66 then v_qty:=90;v_tears:=v_tears+v_qty;v_reward:=jsonb_build_object('kind','tears','amount',v_qty,'rarity',v_rarity,'title','+90 Lágrimas');
      else v_qty:=1200;v_relics:=v_relics+v_qty;v_reward:=jsonb_build_object('kind','relics','amount',v_qty,'rarity',v_rarity,'title','+1.200 Relíquias'); end if;
    end if;
  end if;

  v_inf.shop_sold:=jsonb_set(coalesce(v_inf.shop_sold,'{}'::jsonb),array[v_sold_key],'true'::jsonb,true);
  update public.chrono_player_infernal set infernal_relics=v_inf.infernal_relics,queued_doom_buffs=v_inf.queued_doom_buffs,demon_skins=v_inf.demon_skins,infernal_augments=v_inf.infernal_augments,shop_sold=v_inf.shop_sold,pity_apoc=v_inf.pity_apoc,pity_heretic=v_inf.pity_heretic,updated_at=now() where user_id=p_user_id;
  update public.chrono_player_state set relic_shards=v_relics,chrono_fragments=v_chrono,sinner_tears=v_tears,revision=revision+1 where user_id=p_user_id returning * into v_state;
  perform public.chrono_sync_progression_save_server(p_user_id);
  v_response:=jsonb_build_object('purchased',true,'section',p_section,'index',p_index,'itemId',v_item,'cost',v_cost,'currency',v_currency,'reward',v_reward,'progression',public.chrono_progression_payload_server(p_user_id),'state',to_jsonb(v_state));
  insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'infernal_purchase',v_response);
  return v_response;
end;
$$;

create or replace function public.chrono_infernal_legacy_server(p_user_id uuid,p_request_id uuid,p_legacy_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_previous jsonb;v_state public.chrono_player_state%rowtype;v_inf public.chrono_player_infernal%rowtype;v_level integer;v_max integer;v_base integer;v_cost integer;v_discount integer;v_response jsonb;
begin
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;if found then return v_previous;end if;
  if not public.chrono_valid_legacy(p_legacy_id) then raise exception 'Legado inválido';end if;
  select * into v_state from public.chrono_player_state where user_id=p_user_id for update;if not found then raise exception 'Save online não encontrado';end if;
  v_inf:=public.chrono_refresh_infernal_locked_server(p_user_id);v_level:=greatest(0,coalesce((v_inf.legacy_levels->>p_legacy_id)::integer,0));
  v_max:=case p_legacy_id when 'soul_magnet' then 4 when 'forbidden_spark' then 1 else 5 end;
  if v_level>=v_max then raise exception 'Legado já está no nível máximo';end if;
  v_base:=case p_legacy_id
    when 'ancestral_blood' then (array[180,300,480,700,950])[v_level+1]
    when 'chrono_conductor' then (array[160,270,420,620,850])[v_level+1]
    when 'golden_pact' then (array[150,250,390,580,800])[v_level+1]
    when 'soul_magnet' then (array[140,240,380,600])[v_level+1]
    when 'merchant_favor' then (array[200,340,520,760,1050])[v_level+1]
    else 1200 end;
  v_discount:=least(5,greatest(0,coalesce((v_inf.legacy_levels->>'merchant_favor')::integer,0)));v_cost:=greatest(1,ceil(v_base*(100-v_discount)/100.0)::integer);
  if v_state.sinner_tears<v_cost then raise exception 'Lágrimas dos Pecadores insuficientes';end if;
  update public.chrono_player_infernal set legacy_levels=jsonb_set(legacy_levels,array[p_legacy_id],to_jsonb(v_level+1),true),updated_at=now() where user_id=p_user_id;
  update public.chrono_player_state set sinner_tears=sinner_tears-v_cost,revision=revision+1 where user_id=p_user_id returning * into v_state;
  perform public.chrono_sync_progression_save_server(p_user_id);
  v_response:=jsonb_build_object('purchased',true,'legacyId',p_legacy_id,'level',v_level+1,'cost',v_cost,'progression',public.chrono_progression_payload_server(p_user_id),'state',to_jsonb(v_state));
  insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'infernal_legacy',v_response);return v_response;
end;
$$;

create or replace function public.chrono_purchase_nefalem_server(p_user_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_previous jsonb;v_state public.chrono_player_state%rowtype;v_inf public.chrono_player_infernal%rowtype;v_discount integer;v_cost integer;v_response jsonb;
begin
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;if found then return v_previous;end if;
  select * into v_state from public.chrono_player_state where user_id=p_user_id for update;if not found then raise exception 'Save online não encontrado';end if;
  v_inf:=public.chrono_refresh_infernal_locked_server(p_user_id);if v_inf.nefalem_owned then raise exception 'Nefalem já adquirido';end if;
  v_discount:=least(5,greatest(0,coalesce((v_inf.legacy_levels->>'merchant_favor')::integer,0)));v_cost:=greatest(1,ceil(500*(100-v_discount)/100.0)::integer);
  if v_state.sinner_tears<v_cost then raise exception 'Lágrimas dos Pecadores insuficientes';end if;
  update public.chrono_player_infernal set nefalem_owned=true,updated_at=now() where user_id=p_user_id;
  update public.chrono_player_state set sinner_tears=sinner_tears-v_cost,revision=revision+1 where user_id=p_user_id returning * into v_state;
  perform public.chrono_sync_progression_save_server(p_user_id);
  v_response:=jsonb_build_object('purchased',true,'cost',v_cost,'progression',public.chrono_progression_payload_server(p_user_id),'state',to_jsonb(v_state));
  insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'infernal_nefalem',v_response);return v_response;
end;
$$;

create or replace function public.chrono_prepare_doom_run_server(p_user_id uuid,p_session_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_session public.chrono_game_sessions%rowtype;v_inf public.chrono_player_infernal%rowtype;v_loadout text[];v_payload jsonb;
begin
  select * into v_session from public.chrono_game_sessions where id=p_session_id and user_id=p_user_id for update;
  if not found or v_session.status<>'active' or v_session.mode<>'doom' then raise exception 'Sessão DOOM inválida';end if;
  v_inf:=public.chrono_refresh_infernal_locked_server(p_user_id);if not v_inf.doom_unlocked then raise exception 'Modo DOOM ainda não foi desbloqueado no servidor';end if;
  if jsonb_typeof(v_session.server_context->'doomBuffs')='array' then
    select coalesce(array_agg(value),'{}'::text[]) into v_loadout from jsonb_array_elements_text(v_session.server_context->'doomBuffs');
  else
    v_loadout:=(coalesce(v_inf.queued_doom_buffs,'{}'::text[]))[1:2];
    update public.chrono_player_infernal set queued_doom_buffs='{}',updated_at=now() where user_id=p_user_id;
    update public.chrono_game_sessions set server_context=jsonb_set(server_context,'{doomBuffs}',to_jsonb(v_loadout),true) where id=p_session_id;
    perform public.chrono_sync_progression_save_server(p_user_id);
  end if;
  v_payload:=jsonb_build_object('ids',to_jsonb(coalesce(v_loadout,'{}'::text[])));
  return v_payload;
end;
$$;

create or replace function public.chrono_unlock_doom_server(p_user_id uuid,p_request_id uuid,p_session_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_previous jsonb;v_session public.chrono_game_sessions%rowtype;v_counter public.chrono_progression_run_counters%rowtype;v_response jsonb;v_state public.chrono_player_state%rowtype;
begin
  select response into v_previous from public.chrono_action_receipts where user_id=p_user_id and request_id=p_request_id;if found then return v_previous;end if;
  select * into v_session from public.chrono_game_sessions where id=p_session_id and user_id=p_user_id for update;
  if not found or v_session.mode<>'normal' or v_session.status<>'active' then raise exception 'O DOOM só pode ser desbloqueado durante uma partida normal registrada';end if;
  select * into v_counter from public.chrono_progression_run_counters where session_id=p_session_id and user_id=p_user_id;
  if not found or coalesce((v_counter.last_summary#>>'{specialMetrics,infernalBossKills}')::integer,0)<1 then raise exception 'A derrota do Devorador Infernal ainda não foi validada pelo servidor';end if;
  insert into public.chrono_player_infernal(user_id,doom_unlocked) values(p_user_id,true)
    on conflict(user_id) do update set doom_unlocked=true,updated_at=now();
  update public.chrono_player_state set revision=revision+1 where user_id=p_user_id returning * into v_state;
  perform public.chrono_sync_progression_save_server(p_user_id);
  v_response:=jsonb_build_object('unlocked',true,'progression',public.chrono_progression_payload_server(p_user_id),'state',to_jsonb(v_state));
  insert into public.chrono_action_receipts(user_id,request_id,action,response) values(p_user_id,p_request_id,'doom_unlock',v_response);return v_response;
end;
$$;

create or replace function public.chrono_progression_metric_for_run(
  p_metric text,p_active_character text,p_session_class text,p_kills bigint,p_boss bigint,p_elite bigint,p_skills bigint,p_wave bigint,p_types jsonb,p_special jsonb
) returns bigint language plpgsql immutable set search_path='' as $$
begin
  if p_metric='maxWave' then return case when p_session_class=p_active_character then greatest(0,p_wave) else 0 end;
  elsif p_metric='eliteKills' then return greatest(0,p_elite);
  elsif p_metric like 'classKills.%' then return case when split_part(p_metric,'.',2)=p_session_class then greatest(0,p_kills) else 0 end;
  elsif p_metric like 'classBossKills.%' then return case when split_part(p_metric,'.',2)=p_session_class then greatest(0,p_boss) else 0 end;
  elsif p_metric like 'classSkillUses.%' then return case when split_part(p_metric,'.',2)=p_session_class then greatest(0,p_skills) else 0 end;
  elsif p_metric='typeKills.riftTick' then return greatest(0,coalesce((p_special->>'riftTickKills')::bigint,0));
  elsif p_metric like 'typeKills.%' then return greatest(0,coalesce((p_types->>split_part(p_metric,'.',2))::bigint,0));
  elsif p_metric='assaultTurboBossKills' then return case when p_session_class='assault' then greatest(0,coalesce((p_special->>'assaultTurboBossKills')::bigint,0)) else 0 end;
  elsif p_metric='roninParryContacts8427' then return case when p_session_class='ronin' then greatest(0,coalesce((p_special->>'roninParryContacts')::bigint,0)) else 0 end;
  end if;
  return 0;
end;
$$;

create or replace function public.chrono_apply_progression_run_server(
  p_user_id uuid,p_session_id uuid,p_score bigint,p_wave integer,p_kills integer,p_boss_kills integer,p_elite_kills integer,p_skills_used integer,
  p_type_kills jsonb,p_special_metrics jsonb,p_doom_summary jsonb,p_final boolean default false
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_session public.chrono_game_sessions%rowtype;v_counter public.chrono_progression_run_counters%rowtype;v_active public.chrono_player_awakening_active%rowtype;
  v_metric bigint:=0;v_prev bigint:=0;v_delta bigint:=0;v_state public.chrono_player_state%rowtype;v_inf public.chrono_player_infernal%rowtype;
  v_elapsed numeric;v_reward integer:=0;v_loadout jsonb;v_completed integer;v_failed integer;v_miniboss integer;v_dboss integer;v_peak integer;v_doom_time integer;v_emperor boolean;v_cap integer;
  v_stats jsonb;v_types jsonb;v_special jsonb;v_summary jsonb;
begin
  select * into v_session from public.chrono_game_sessions where id=p_session_id and user_id=p_user_id for update;
  if not found then raise exception 'Sessão não encontrada';end if;
  if not p_final and v_session.status<>'active' then return jsonb_build_object('accepted',false,'terminal',true);end if;
  insert into public.chrono_progression_run_counters(session_id,user_id) values(p_session_id,p_user_id) on conflict(session_id) do nothing;
  select * into v_counter from public.chrono_progression_run_counters where session_id=p_session_id for update;
  if p_final and v_counter.finalized then return jsonb_build_object('accepted',true,'replayed',true,'doomReward',v_counter.doom_reward,'progression',public.chrono_progression_payload_server(p_user_id));end if;
  v_special:=coalesce(p_special_metrics,'{}'::jsonb);v_summary:=jsonb_build_object('score',p_score,'wave',p_wave,'kills',p_kills,'bossKills',p_boss_kills,'eliteKills',p_elite_kills,'skillsUsed',p_skills_used,'typeKills',coalesce(p_type_kills,'{}'::jsonb),'specialMetrics',v_special,'doomSummary',coalesce(p_doom_summary,'{}'::jsonb));
  select * into v_active from public.chrono_player_awakening_active where user_id=p_user_id for update;
  -- Uma etapa iniciada no meio de uma partida não herda feitos anteriores daquela run.
  -- Ela começa a contar somente em sessões abertas depois da ativação.
  if found and v_session.started_at >= v_active.started_at then
    v_metric:=public.chrono_progression_metric_for_run(v_active.metric,v_active.character_key,v_session.class_key,p_kills,p_boss_kills,p_elite_kills,p_skills_used,p_wave,coalesce(p_type_kills,'{}'::jsonb),v_special);
    if v_counter.active_character=v_active.character_key and v_counter.active_stage=v_active.stage then v_prev:=v_counter.metric_value;else v_prev:=0;end if;
    if v_active.metric='maxWave' then update public.chrono_player_awakening_active set progress=greatest(progress,v_metric),updated_at=now() where user_id=p_user_id;
    else v_delta:=greatest(0,v_metric-v_prev);update public.chrono_player_awakening_active set progress=least(target,progress+v_delta),updated_at=now() where user_id=p_user_id;end if;
  end if;
  update public.chrono_progression_run_counters set active_character=case when v_active.user_id is null then null else v_active.character_key end,active_stage=case when v_active.user_id is null then null else v_active.stage end,metric_value=v_metric,last_summary=v_summary,updated_at=now() where session_id=p_session_id;
  update public.chrono_game_sessions set server_context=jsonb_set(jsonb_set(server_context,'{specialMetrics}',v_special,true),'{doomSummary}',coalesce(p_doom_summary,'{}'::jsonb),true) where id=p_session_id;

  if p_final then
    select * into v_state from public.chrono_player_state where user_id=p_user_id for update;
    v_stats:=coalesce(v_state.mission_stats,'{}'::jsonb);v_types:=coalesce(v_stats->'typeKills','{}'::jsonb);
    v_types:=jsonb_set(v_types,'{riftTick}',to_jsonb(coalesce((v_types->>'riftTick')::bigint,0)+greatest(0,coalesce((v_special->>'riftTickKills')::bigint,0))),true);
    v_stats:=jsonb_set(v_stats,'{typeKills}',v_types,true);
    v_stats:=jsonb_set(v_stats,'{assaultTurboBossKills}',to_jsonb(coalesce((v_stats->>'assaultTurboBossKills')::bigint,0)+greatest(0,coalesce((v_special->>'assaultTurboBossKills')::bigint,0))),true);
    v_stats:=jsonb_set(v_stats,'{roninParryContacts8427}',to_jsonb(coalesce((v_stats->>'roninParryContacts8427')::bigint,0)+greatest(0,coalesce((v_special->>'roninParryContacts')::bigint,0))),true);
    if v_session.mode='doom' then
      v_elapsed:=greatest(0,extract(epoch from (coalesce(v_session.ended_at,now())-v_session.started_at)));
      v_completed:=least(greatest(0,coalesce((p_doom_summary->>'missionsCompleted')::integer,0)),floor(v_elapsed/12)::integer+2);
      v_failed:=least(greatest(0,coalesce((p_doom_summary->>'missionsFailed')::integer,0)),floor(v_elapsed/10)::integer+3);
      v_miniboss:=least(greatest(0,coalesce((p_doom_summary->>'minibossKills')::integer,0)),p_kills);
      v_dboss:=least(greatest(0,coalesce((p_doom_summary->>'bossKills')::integer,0)),p_boss_kills+3);
      v_peak:=least(100,greatest(0,coalesce((p_doom_summary->>'peakValue')::integer,0)));
      v_doom_time:=least(floor(v_elapsed)::integer,greatest(0,coalesce((p_doom_summary->>'timeAtDoom')::integer,0)));
      v_emperor:=coalesce((p_doom_summary->>'emperorDefeated')::boolean,false) and v_dboss>0;
      v_reward:=least(500,greatest(0,floor(v_elapsed/45)::integer+v_completed*10+v_miniboss*3+v_dboss*7+case when v_emperor then 20 else 0 end+case when v_peak>=25 then 2 else 0 end+case when v_peak>=50 then 4 else 0 end+case when v_peak>=75 then 7 else 0 end+case when v_peak>=100 then 12 else 0 end));
      v_loadout:=coalesce(v_session.server_context->'doomBuffs','[]'::jsonb);if exists(select 1 from jsonb_array_elements_text(v_loadout) x where x='greed_seal') then v_reward:=floor(v_reward*1.25)::integer;end if;
      v_cap:=least(500,greatest(20,p_kills/3+floor(v_elapsed/20)::integer+80));v_reward:=least(v_reward,v_cap);
      update public.chrono_player_state set sinner_tears=sinner_tears+v_reward,mission_stats=v_stats,mission_stats_updated_at=now(),revision=revision+1 where user_id=p_user_id returning * into v_state;
      insert into public.chrono_player_infernal(user_id) values(p_user_id) on conflict(user_id) do nothing;
      update public.chrono_player_infernal set doom_stats=jsonb_build_object(
        'runs',coalesce((doom_stats->>'runs')::bigint,0)+1,
        'bestPeak',greatest(coalesce((doom_stats->>'bestPeak')::integer,0),v_peak),
        'bestTimeAtDoom',greatest(coalesce((doom_stats->>'bestTimeAtDoom')::integer,0),v_doom_time),
        'missionsCompleted',coalesce((doom_stats->>'missionsCompleted')::bigint,0)+v_completed,
        'bossKills',coalesce((doom_stats->>'bossKills')::bigint,0)+v_dboss,
        'tearsEarned',coalesce((doom_stats->>'tearsEarned')::bigint,0)+v_reward,
        'emperorDefeated',coalesce((doom_stats->>'emperorDefeated')::boolean,false) or v_emperor
      ),updated_at=now() where user_id=p_user_id;
    else
      update public.chrono_player_state set mission_stats=v_stats,mission_stats_updated_at=now(),revision=revision+1 where user_id=p_user_id returning * into v_state;
    end if;
    update public.chrono_progression_run_counters set finalized=true,doom_reward=v_reward,updated_at=now() where session_id=p_session_id;
    perform public.chrono_sync_progression_save_server(p_user_id);
  end if;
  return jsonb_build_object('accepted',true,'doomReward',v_reward,'progression',public.chrono_progression_payload_server(p_user_id),'state',case when p_final then to_jsonb(v_state) else null end);
end;
$$;

-- Importação única e limitada dos sistemas que eram locais até a 8.5.17.
do $$
declare r record;m jsonb;active jsonb;c text;completed integer;ult boolean;journey boolean;inf_relics text[];buffs text[];skins text[];augs text[];legacy jsonb;active_metric text;active_target bigint;current_value bigint;import_progress bigint;import_baseline bigint;
begin
  for r in select * from public.chrono_player_state loop
    m:=coalesce(r.save_data->'chrono_v4_meta','{}'::jsonb) || coalesce(r.client_save_data->'chrono_v4_meta','{}'::jsonb);
    insert into public.chrono_player_infernal(user_id,nefalem_owned,doom_unlocked,infernal_relics,legacy_levels,queued_doom_buffs,demon_skins,infernal_augments,imported_at)
    values(
      r.user_id,public.chrono_safe_bool_text(m->>'nefalemPurchased830',false),(public.chrono_safe_bool_text(m->>'doomModeUnlocked810',false) or public.chrono_safe_bool_text(m->>'doomModeUnlocked',false)),
      coalesce((select array_agg(distinct x) from jsonb_array_elements_text(case when jsonb_typeof(m->'infernalRelics830')='array' then m->'infernalRelics830' else '[]'::jsonb end) x where public.chrono_valid_infernal_relic(x)),'{}'::text[]),
      public.chrono_sanitize_legacy_levels(coalesce(m->'infernalLegacy830','{}'::jsonb)),
      (coalesce((select array_agg(distinct x) from jsonb_array_elements_text(case when jsonb_typeof(m->'doomRunBuffs830')='array' then m->'doomRunBuffs830' else '[]'::jsonb end) x where public.chrono_valid_doom_buff(x)),'{}'::text[]))[1:2],
      coalesce((select array_agg(distinct regexp_replace(key,'^demon_rico_','demon_ricocheteador_')) from jsonb_each(case when jsonb_typeof(((coalesce(r.save_data,'{}'::jsonb)||coalesce(r.client_save_data,'{}'::jsonb))->'chrono_v4_meta_skins_clean_702')->'unlocked')='object' then ((coalesce(r.save_data,'{}'::jsonb)||coalesce(r.client_save_data,'{}'::jsonb))->'chrono_v4_meta_skins_clean_702')->'unlocked' else '{}'::jsonb end) where value='true'::jsonb and public.chrono_valid_demon_skin(key)),'{}'::text[]),
      coalesce((select array_agg(distinct key) from jsonb_each(case when jsonb_typeof(((coalesce(r.save_data,'{}'::jsonb)||coalesce(r.client_save_data,'{}'::jsonb))->'chrono_v4_meta_chrono_augments_620')->'unlocked')='object' then ((coalesce(r.save_data,'{}'::jsonb)||coalesce(r.client_save_data,'{}'::jsonb))->'chrono_v4_meta_chrono_augments_620')->'unlocked' else '{}'::jsonb end) where value='true'::jsonb and public.chrono_valid_infernal_augment(key)),'{}'::text[]),now()
    ) on conflict(user_id) do update set
      nefalem_owned=public.chrono_player_infernal.nefalem_owned or excluded.nefalem_owned,
      doom_unlocked=public.chrono_player_infernal.doom_unlocked or excluded.doom_unlocked,
      infernal_relics=coalesce((select array_agg(distinct x) from unnest(public.chrono_player_infernal.infernal_relics||excluded.infernal_relics) x),'{}'::text[]),
      legacy_levels=public.chrono_sanitize_legacy_levels(public.chrono_player_infernal.legacy_levels||excluded.legacy_levels),
      queued_doom_buffs=excluded.queued_doom_buffs,
      demon_skins=coalesce((select array_agg(distinct x) from unnest(public.chrono_player_infernal.demon_skins||excluded.demon_skins) x),'{}'::text[]),
      infernal_augments=coalesce((select array_agg(distinct x) from unnest(public.chrono_player_infernal.infernal_augments||excluded.infernal_augments) x),'{}'::text[]),
      imported_at=coalesce(public.chrono_player_infernal.imported_at,now());

    for c in select distinct character_key from public.chrono_awakening_catalog loop
      completed:=least(5,greatest(0,public.chrono_safe_int_text(m#>>array['awakenings463','completed',c],0)));
      ult:=(public.chrono_safe_bool_text(m#>>array['awakeningUltimates',c],false) or public.chrono_safe_bool_text(m#>>array['awakeningRewards480',c],false));
      journey:=public.chrono_safe_bool_text(m#>>array['awakeningJourneys489',c],false) or completed>0 or ult;
      if journey then insert into public.chrono_player_awakenings(user_id,character_key,journey_unlocked,completed_stages,ultimate_unlocked)
        values(r.user_id,c,true,completed,ult) on conflict(user_id,character_key) do update set journey_unlocked=true,completed_stages=greatest(public.chrono_player_awakenings.completed_stages,excluded.completed_stages),ultimate_unlocked=public.chrono_player_awakenings.ultimate_unlocked or excluded.ultimate_unlocked; end if;
    end loop;
    active:=m#>'{awakenings463,active}';
    if jsonb_typeof(active)='object' and active->>'id' is not null then
      c:=active->>'id';completed:=least(5,greatest(0,public.chrono_safe_int_text(active->>'stage',0)))+1;
      select metric,target into active_metric,active_target from public.chrono_awakening_catalog where character_key=c and stage=completed;
      if found and not exists(select 1 from public.chrono_player_awakening_active where user_id=r.user_id) then
        current_value:=greatest(0,public.chrono_metric_value(coalesce(r.mission_stats,'{}'::jsonb),active_metric));
        if active_metric='maxWave' then
          import_baseline:=0;
          import_progress:=least(active_target,greatest(0,public.chrono_safe_int_text(active->>'serverProgress',public.chrono_safe_int_text(active->>'waveBest',0))));
        else
          import_baseline:=greatest(0,public.chrono_safe_int_text(active->>'baseline',least(current_value,2147483647)::integer));
          if active ? 'serverProgress' then
            import_progress:=least(active_target,greatest(0,public.chrono_safe_int_text(active->>'serverProgress',0)));
          else
            import_progress:=least(active_target,greatest(0,current_value-import_baseline));
          end if;
          import_baseline:=greatest(0,current_value-import_progress);
        end if;
        insert into public.chrono_player_awakenings(user_id,character_key,journey_unlocked) values(r.user_id,c,true) on conflict(user_id,character_key) do update set journey_unlocked=true;
        insert into public.chrono_player_awakening_active(user_id,character_key,stage,metric,target,baseline,progress)
        values(r.user_id,c,completed,active_metric,active_target,import_baseline,import_progress);
      end if;
    end if;
    update public.chrono_player_state set awakening_authority_enabled=true,infernal_authority_enabled=true,doom_authority_enabled=true,progression_authority_enabled_at=coalesce(progression_authority_enabled_at,now()) where user_id=r.user_id;
    perform public.chrono_sync_progression_save_server(r.user_id);
  end loop;
end $$;

-- Novas contas entram autoritativas automaticamente.
create or replace function public.chrono_progression_state_defaults_trigger()
returns trigger language plpgsql set search_path='' as $$
begin
  new.awakening_authority_enabled:=true;new.infernal_authority_enabled:=true;new.doom_authority_enabled:=true;
  new.progression_authority_enabled_at:=coalesce(new.progression_authority_enabled_at,now());return new;
end $$;
drop trigger if exists chrono_progression_defaults on public.chrono_player_state;
create trigger chrono_progression_defaults before insert on public.chrono_player_state for each row execute function public.chrono_progression_state_defaults_trigger();

-- Permissões: somente a service_role da Edge Function executa as ações.
revoke all on function public.chrono_array_has(text[],text) from public,anon,authenticated;
revoke all on function public.chrono_valid_infernal_relic(text) from public,anon,authenticated;
revoke all on function public.chrono_valid_doom_buff(text) from public,anon,authenticated;
revoke all on function public.chrono_valid_legacy(text) from public,anon,authenticated;
revoke all on function public.chrono_safe_int_text(text,integer) from public,anon,authenticated;
revoke all on function public.chrono_safe_bool_text(text,boolean) from public,anon,authenticated;
revoke all on function public.chrono_sanitize_legacy_levels(jsonb) from public,anon,authenticated;
revoke all on function public.chrono_valid_infernal_augment(text) from public,anon,authenticated;
revoke all on function public.chrono_valid_demon_skin(text) from public,anon,authenticated;
revoke all on function public.chrono_shop_shuffled(text[],uuid,bigint,text,integer) from public,anon,authenticated;
revoke all on function public.chrono_refresh_infernal_locked_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_sync_progression_save_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_progression_payload_server(uuid) from public,anon,authenticated;
revoke all on function public.chrono_start_awakening_stage_server(uuid,uuid,text,integer) from public,anon,authenticated;
revoke all on function public.chrono_claim_awakening_stage_server(uuid,uuid) from public,anon,authenticated;
revoke all on function public.chrono_claim_awakening_ultimate_server(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.chrono_infernal_item_price(text,text) from public,anon,authenticated;
revoke all on function public.chrono_infernal_purchase_server(uuid,uuid,text,integer,text) from public,anon,authenticated;
revoke all on function public.chrono_infernal_legacy_server(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.chrono_purchase_nefalem_server(uuid,uuid) from public,anon,authenticated;
revoke all on function public.chrono_prepare_doom_run_server(uuid,uuid) from public,anon,authenticated;
revoke all on function public.chrono_unlock_doom_server(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.chrono_progression_metric_for_run(text,text,text,bigint,bigint,bigint,bigint,bigint,jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.chrono_apply_progression_run_server(uuid,uuid,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,boolean) from public,anon,authenticated;
revoke all on function public.chrono_progression_state_defaults_trigger() from public,anon,authenticated;

grant execute on function public.chrono_progression_payload_server(uuid) to service_role;
grant execute on function public.chrono_start_awakening_stage_server(uuid,uuid,text,integer) to service_role;
grant execute on function public.chrono_claim_awakening_stage_server(uuid,uuid) to service_role;
grant execute on function public.chrono_claim_awakening_ultimate_server(uuid,uuid,text) to service_role;
grant execute on function public.chrono_infernal_purchase_server(uuid,uuid,text,integer,text) to service_role;
grant execute on function public.chrono_infernal_legacy_server(uuid,uuid,text) to service_role;
grant execute on function public.chrono_purchase_nefalem_server(uuid,uuid) to service_role;
grant execute on function public.chrono_prepare_doom_run_server(uuid,uuid) to service_role;
grant execute on function public.chrono_unlock_doom_server(uuid,uuid,uuid) to service_role;
grant execute on function public.chrono_apply_progression_run_server(uuid,uuid,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,boolean) to service_role;

comment on table public.chrono_player_awakenings is 'Progressão de Awakening autoritativa por personagem.';
comment on table public.chrono_player_infernal is 'Loja Infernal, Nefalem, pactos, skins e DOOM autoritativos.';
comment on function public.chrono_apply_progression_run_server is 'Aplica telemetria cumulativa da run em Awakening e recompensas DOOM com idempotência.';

commit;
