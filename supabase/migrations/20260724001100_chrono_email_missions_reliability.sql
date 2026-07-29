-- Chrono Shards 8.5.14 — e-mail consistente e progresso de missões resiliente
-- Execute UMA VEZ após 20260724001000_chrono_real_email_identity.sql.

begin;

alter table public.chrono_profiles
  add column if not exists email_domain_validated boolean not null default false,
  add column if not exists email_domain_checked_at timestamptz;

alter table public.chrono_player_state
  add column if not exists mission_stats_updated_at timestamptz;

-- Não reescrevemos em massa os e-mails antigos aqui. Uma normalização global
-- poderia colidir com o índice único caso duas versões antigas tenham gravado o
-- mesmo endereço com espaços diferentes. As comparações abaixo normalizam na
-- leitura e o diagnóstico lista qualquer legado que precise de tratamento.

-- Verifica duplicidade tanto no perfil do jogo quanto no Supabase Auth.
-- Essa função não confirma a posse da caixa postal; ela apenas impede identidades duplicadas.
create or replace function public.chrono_email_availability_server(
  p_email text,
  p_exclude_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_profile_user uuid;
  v_auth_user uuid;
begin
  if v_email = '' or position('@' in v_email) <= 1 then
    return jsonb_build_object('available', false, 'reason', 'invalid');
  end if;

  select p.user_id into v_profile_user
  from public.chrono_profiles p
  where lower(btrim(p.contact_email_normalized)) = v_email
    and (p_exclude_user_id is null or p.user_id <> p_exclude_user_id)
  limit 1;

  select u.id into v_auth_user
  from auth.users u
  where lower(btrim(coalesce(u.email, ''))) = v_email
    and (p_exclude_user_id is null or u.id <> p_exclude_user_id)
  limit 1;

  return jsonb_build_object(
    'available', v_profile_user is null and v_auth_user is null,
    'profileConflict', v_profile_user is not null,
    'authConflict', v_auth_user is not null,
    'profileUserId', v_profile_user,
    'authUserId', v_auth_user
  );
end;
$$;

-- Guarda checkpoints cumulativos da partida. Eles não concedem recompensas;
-- apenas evitam perda de progresso caso o game over ou o navegador falhe.
create or replace function public.chrono_checkpoint_run_server(
  p_user_id uuid,
  p_session_id uuid,
  p_score bigint,
  p_wave integer,
  p_kills integer,
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
  v_elapsed numeric;
  v_existing jsonb;
  v_checkpoint jsonb;
  v_types jsonb := '{}'::jsonb;
  v_key text;
  v_value_text text;
  v_value bigint;
  v_total bigint := 0;
  v_allowed text[] := array['chaser','swarmer','strafer','tank','bomber','sentinel','vomiter','pukeling'];
  v_safe_types jsonb := '{}'::jsonb;
  v_remaining bigint;
begin
  if p_score < 0 or p_wave < 0 or p_kills < 0 or p_boss_kills < 0
     or p_elite_kills < 0 or p_skills_used < 0 then
    raise exception 'Valores negativos não são aceitos';
  end if;

  select * into v_session
  from public.chrono_game_sessions
  where id = p_session_id and user_id = p_user_id
  for update;

  if not found then raise exception 'Sessão não encontrada'; end if;
  if v_session.status <> 'active' then raise exception 'Sessão já encerrada'; end if;

  v_elapsed := greatest(1, extract(epoch from (now() - v_session.started_at)));
  if p_kills > ceil(v_elapsed * 30 + 400) then raise exception 'Abates incompatíveis com a duração'; end if;
  if p_wave > floor(v_elapsed / 2) + 60 then raise exception 'Wave incompatível com a duração'; end if;
  if p_boss_kills > p_kills or p_elite_kills > p_kills then raise exception 'Resumo de inimigos inválido'; end if;
  if p_skills_used > ceil(v_elapsed * 10 + 300) then raise exception 'Uso de habilidades incompatível com a duração'; end if;
  if jsonb_typeof(coalesce(p_type_kills, '{}'::jsonb)) <> 'object' then raise exception 'Resumo de inimigos inválido'; end if;

  for v_key, v_value_text in select key, value from jsonb_each_text(coalesce(p_type_kills, '{}'::jsonb)) loop
    if not (v_key = any(v_allowed)) then raise exception 'Tipo de inimigo inválido'; end if;
    if v_value_text !~ '^[0-9]+$' or length(v_value_text) > 10 then raise exception 'Contagem de inimigo inválida'; end if;
    v_value := v_value_text::bigint;
    if v_value > p_kills then raise exception 'Contagem por tipo maior que os abates'; end if;
    v_total := v_total + v_value;
    v_types := jsonb_set(v_types, array[v_key], to_jsonb(v_value), true);
  end loop;
  if v_total > p_kills then raise exception 'Soma de inimigos maior que os abates'; end if;

  v_existing := coalesce(v_session.summary -> 'checkpoint', '{}'::jsonb);
  for v_key in select unnest(v_allowed) loop
    v_types := jsonb_set(
      v_types,
      array[v_key],
      to_jsonb(greatest(
        public.chrono_jsonb_bigint(v_existing, array['typeKills', v_key]),
        public.chrono_jsonb_bigint(v_types, array[v_key])
      )),
      true
    );
  end loop;

  -- Se versões diferentes do cliente classificarem a mesma morte de modos
  -- diferentes, o máximo por categoria pode ultrapassar o total. Reaplica um
  -- orçamento global para que uma partida legítima não seja rejeitada.
  v_remaining := greatest(public.chrono_jsonb_bigint(v_existing, array['kills']), p_kills::bigint);
  foreach v_key in array v_allowed loop
    v_value := least(public.chrono_jsonb_bigint(v_types, array[v_key]), v_remaining);
    if v_value > 0 then
      v_safe_types := jsonb_set(v_safe_types, array[v_key], to_jsonb(v_value), true);
      v_remaining := v_remaining - v_value;
    end if;
  end loop;
  v_types := v_safe_types;

  v_checkpoint := jsonb_build_object(
    'score', greatest(public.chrono_jsonb_bigint(v_existing, array['score']), p_score),
    'wave', greatest(public.chrono_jsonb_bigint(v_existing, array['wave']), p_wave::bigint),
    'kills', greatest(public.chrono_jsonb_bigint(v_existing, array['kills']), p_kills::bigint),
    'bossKills', greatest(public.chrono_jsonb_bigint(v_existing, array['bossKills']), p_boss_kills::bigint),
    'eliteKills', greatest(public.chrono_jsonb_bigint(v_existing, array['eliteKills']), p_elite_kills::bigint),
    'skillsUsed', greatest(public.chrono_jsonb_bigint(v_existing, array['skillsUsed']), p_skills_used::bigint),
    'typeKills', v_types,
    'savedAt', floor(extract(epoch from now()) * 1000)::bigint
  );

  update public.chrono_game_sessions
  set summary = jsonb_set(coalesce(summary, '{}'::jsonb), '{checkpoint}', v_checkpoint, true)
  where id = p_session_id;

  return jsonb_build_object('accepted', true, 'checkpoint', v_checkpoint);
end;
$$;

-- Recupera apenas a telemetria de missões de runs que ficaram ativas sem
-- liquidação. Não concede moedas. No carregamento de Missões, somente checkpoints
-- sem atualização recente são recuperados; ao começar uma nova run, todas as runs
-- anteriores são encerradas para impedir sessões concorrentes.
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
  v_recovered integer := 0;
  v_abandoned integer := 0;
  v_recovered_kills bigint := 0;
begin
  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object('recovered', 0, 'abandoned', 0, 'state', null);
  end if;

  v_stats := coalesce(v_state.mission_stats, coalesce(v_state.save_data #> '{chrono_v4_meta,stats}', '{}'::jsonb));
  v_stats := jsonb_set(v_stats, '{typeKills}', coalesce(v_stats -> 'typeKills', '{}'::jsonb), true);
  v_stats := jsonb_set(v_stats, '{classKills}', coalesce(v_stats -> 'classKills', '{}'::jsonb), true);
  v_stats := jsonb_set(v_stats, '{classBossKills}', coalesce(v_stats -> 'classBossKills', '{}'::jsonb), true);
  v_stats := jsonb_set(v_stats, '{classSkillUses}', coalesce(v_stats -> 'classSkillUses', '{}'::jsonb), true);

  for v_session in
    select * from public.chrono_game_sessions
    where user_id = p_user_id and status = 'active'
    order by started_at
    for update
  loop
    v_checkpoint := coalesce(v_session.summary -> 'checkpoint', '{}'::jsonb);
    v_saved_ms := public.chrono_jsonb_bigint(v_checkpoint, array['savedAt']);

    if not p_force then
      if v_saved_ms <= 0 then
        continue;
      end if;
      if to_timestamp(v_saved_ms / 1000.0) > now() - make_interval(secs => greatest(15, least(3600, p_stale_seconds))) then
        continue;
      end if;
    end if;

    v_abandoned := v_abandoned + 1;
    v_kills := public.chrono_jsonb_bigint(v_checkpoint, array['kills']);
    v_boss := least(v_kills, public.chrono_jsonb_bigint(v_checkpoint, array['bossKills']));
    v_elite := least(v_kills, public.chrono_jsonb_bigint(v_checkpoint, array['eliteKills']));
    v_skills := public.chrono_jsonb_bigint(v_checkpoint, array['skillsUsed']);
    v_wave := public.chrono_jsonb_bigint(v_checkpoint, array['wave']);

    if v_kills > 0 or v_boss > 0 or v_elite > 0 or v_skills > 0 or v_wave > 0 then
      v_stats := public.chrono_jsonb_increment(v_stats, array['totalKills'], v_kills);
      v_stats := public.chrono_jsonb_increment(v_stats, array['bossKills'], v_boss);
      v_stats := public.chrono_jsonb_increment(v_stats, array['eliteKills'], v_elite);
      v_stats := public.chrono_jsonb_increment(v_stats, array['skillsUsed'], v_skills);
      v_stats := jsonb_set(v_stats, array['maxWave'], to_jsonb(greatest(public.chrono_jsonb_bigint(v_stats, array['maxWave']), v_wave)), true);
      v_stats := public.chrono_jsonb_increment(v_stats, array['classKills', v_session.class_key], v_kills);
      v_stats := public.chrono_jsonb_increment(v_stats, array['classBossKills', v_session.class_key], v_boss);
      v_stats := public.chrono_jsonb_increment(v_stats, array['classSkillUses', v_session.class_key], v_skills);

      if jsonb_typeof(v_checkpoint -> 'typeKills') = 'object' then
        for v_key, v_value_text in
          select key, value from jsonb_each_text(v_checkpoint -> 'typeKills')
        loop
          if v_key = any(array['chaser','swarmer','strafer','tank','bomber','sentinel','vomiter','pukeling'])
             and v_value_text ~ '^[0-9]+$' and length(v_value_text) <= 10 then
            v_value := least(v_kills, v_value_text::bigint);
            v_stats := public.chrono_jsonb_increment(v_stats, array['typeKills', v_key], v_value);
          end if;
        end loop;
      end if;

      v_recovered := v_recovered + 1;
      v_recovered_kills := v_recovered_kills + v_kills;
    end if;

    update public.chrono_game_sessions
    set status = 'abandoned',
        ended_at = now(),
        summary = jsonb_set(
          jsonb_set(coalesce(summary, '{}'::jsonb), '{checkpointRecovered}', to_jsonb(v_kills > 0 or v_skills > 0 or v_wave > 0), true),
          '{checkpointRecoveredAt}', to_jsonb(now()), true
        )
    where id = v_session.id;
  end loop;

  if v_recovered > 0 then
    v_save := coalesce(v_state.save_data, '{}'::jsonb);
    v_meta := coalesce(v_save -> 'chrono_v4_meta', '{}'::jsonb);
    v_meta := jsonb_set(v_meta, '{stats}', v_stats, true);
    v_save := jsonb_set(v_save, '{chrono_v4_meta}', v_meta, true);

    update public.chrono_player_state
    set mission_stats = v_stats,
        save_data = v_save,
        mission_stats_updated_at = now(),
        revision = revision + 1
    where user_id = p_user_id
    returning * into v_state;
  end if;

  return jsonb_build_object(
    'recovered', v_recovered,
    'abandoned', v_abandoned,
    'recoveredKills', v_recovered_kills,
    'state', to_jsonb(v_state)
  );
end;
$$;

-- Corrige baselines impossíveis causadas por snapshots antigos ou por contratos
-- criados sobre estatísticas inconsistentes.
update public.chrono_player_missions pm
set baseline = least(
      pm.baseline,
      public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric)
    ),
    updated_at = now()
from public.chrono_player_state ps,
     public.chrono_mission_catalog mc
where ps.user_id = pm.user_id
  and mc.mission_id = pm.mission_id
  and pm.baseline > public.chrono_metric_value(coalesce(ps.mission_stats, '{}'::jsonb), mc.metric);

-- Preserva a implementação anterior e cria uma fachada que aproveita o último
-- checkpoint antes de liquidar a partida.
do $$
begin
  if to_regprocedure('public.chrono_finish_run_server_legacy_8514(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb)') is null then
    execute 'alter function public.chrono_finish_run_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb) rename to chrono_finish_run_server_legacy_8514';
  end if;
end;
$$;

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
  v_checkpoint jsonb := '{}'::jsonb;
  v_types jsonb := '{}'::jsonb;
  v_key text;
  v_kills integer;
  v_boss integer;
  v_elite integer;
  v_skills integer;
  v_score bigint;
  v_wave integer;
  v_response jsonb;
  v_state public.chrono_player_state%rowtype;
  v_safe_types jsonb := '{}'::jsonb;
  v_remaining bigint;
  v_value bigint;
begin
  select coalesce(summary -> 'checkpoint', '{}'::jsonb)
  into v_checkpoint
  from public.chrono_game_sessions
  where id = p_session_id and user_id = p_user_id;

  v_score := greatest(p_score, public.chrono_jsonb_bigint(v_checkpoint, array['score']));
  v_wave := greatest(p_wave, public.chrono_jsonb_bigint(v_checkpoint, array['wave'])::integer);
  v_kills := greatest(p_kills, public.chrono_jsonb_bigint(v_checkpoint, array['kills'])::integer);
  v_boss := least(v_kills, greatest(p_boss_kills, public.chrono_jsonb_bigint(v_checkpoint, array['bossKills'])::integer));
  v_elite := least(v_kills, greatest(p_elite_kills, public.chrono_jsonb_bigint(v_checkpoint, array['eliteKills'])::integer));
  v_skills := greatest(p_skills_used, public.chrono_jsonb_bigint(v_checkpoint, array['skillsUsed'])::integer);

  foreach v_key in array array['chaser','swarmer','strafer','tank','bomber','sentinel','vomiter','pukeling'] loop
    v_types := jsonb_set(
      v_types,
      array[v_key],
      to_jsonb(greatest(
        public.chrono_jsonb_bigint(coalesce(p_type_kills, '{}'::jsonb), array[v_key]),
        public.chrono_jsonb_bigint(v_checkpoint, array['typeKills', v_key])
      )),
      true
    );
  end loop;

  v_remaining := v_kills;
  foreach v_key in array array['chaser','swarmer','strafer','tank','bomber','sentinel','vomiter','pukeling'] loop
    v_value := least(public.chrono_jsonb_bigint(v_types, array[v_key]), v_remaining);
    if v_value > 0 then
      v_safe_types := jsonb_set(v_safe_types, array[v_key], to_jsonb(v_value), true);
      v_remaining := v_remaining - v_value;
    end if;
  end loop;
  v_types := v_safe_types;

  v_response := public.chrono_finish_run_server_legacy_8514(
    p_user_id, p_request_id, p_session_id, v_score, v_wave, v_kills,
    p_gold, p_relic_delta, p_chrono_delta, v_boss, v_elite, v_skills, v_types
  );

  if coalesce((v_response ->> 'accepted')::boolean, false) then
    update public.chrono_player_state
    set mission_stats_updated_at = now()
    where user_id = p_user_id
    returning * into v_state;

    v_response := jsonb_set(v_response, '{state}', to_jsonb(v_state), true);
  end if;

  return v_response;
end;
$$;

alter table public.chrono_profiles enable row level security;
alter table public.chrono_player_state enable row level security;
alter table public.chrono_game_sessions enable row level security;
alter table public.chrono_player_missions enable row level security;

revoke all on public.chrono_profiles from public, anon, authenticated;
revoke all on public.chrono_player_state from public, anon, authenticated;
revoke all on public.chrono_game_sessions from public, anon, authenticated;
revoke all on public.chrono_player_missions from public, anon, authenticated;

grant all on public.chrono_profiles to service_role;
grant all on public.chrono_player_state to service_role;
grant all on public.chrono_game_sessions to service_role;
grant all on public.chrono_player_missions to service_role;

revoke all on function public.chrono_email_availability_server(text,uuid) from public, anon, authenticated;
revoke all on function public.chrono_checkpoint_run_server(uuid,uuid,bigint,integer,integer,integer,integer,integer,jsonb) from public, anon, authenticated;
revoke all on function public.chrono_recover_stale_run_checkpoints_server(uuid,integer,boolean) from public, anon, authenticated;
revoke all on function public.chrono_finish_run_server_legacy_8514(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb) from public, anon, authenticated;
revoke all on function public.chrono_finish_run_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb) from public, anon, authenticated;

grant execute on function public.chrono_email_availability_server(text,uuid) to service_role;
grant execute on function public.chrono_checkpoint_run_server(uuid,uuid,bigint,integer,integer,integer,integer,integer,jsonb) to service_role;
grant execute on function public.chrono_recover_stale_run_checkpoints_server(uuid,integer,boolean) to service_role;
grant execute on function public.chrono_finish_run_server_legacy_8514(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb) to service_role;
grant execute on function public.chrono_finish_run_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb) to service_role;

comment on column public.chrono_profiles.email_domain_validated is
  'Indica que o domínio do e-mail respondeu como domínio de correio. Não confirma a posse da caixa postal.';
comment on column public.chrono_profiles.email_ownership_verified is
  'Só pode ser true após OTP/link ou provedor social. Sem SMTP permanece false.';
comment on column public.chrono_player_state.mission_stats_updated_at is
  'Última liquidação aceita que alterou estatísticas oficiais de missões.';

commit;
