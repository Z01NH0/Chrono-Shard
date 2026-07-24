-- Chrono Shards Cloud Save — base autoritativa
-- Execute este arquivo no SQL Editor do projeto Supabase.

create extension if not exists pgcrypto;

create table if not exists public.chrono_player_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0 check (revision >= 0),
  initialized boolean not null default false,
  authority_mode text not null default 'migration'
    check (authority_mode in ('migration', 'authoritative')),
  run_results_enabled boolean not null default false,
  legacy_imported_at timestamptz,
  relic_shards bigint not null default 0 check (relic_shards >= 0),
  chrono_fragments bigint not null default 0 check (chrono_fragments >= 0),
  awakening_keys bigint not null default 0 check (awakening_keys >= 0),
  sinner_tears bigint not null default 0 check (sinner_tears >= 0),
  high_score bigint not null default 0 check (high_score >= 0),
  save_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chrono_game_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null,
  class_key text not null,
  server_seed uuid not null default gen_random_uuid(),
  status text not null default 'active'
    check (status in ('active', 'finished', 'rejected', 'abandoned')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  score bigint,
  wave integer,
  kills integer,
  summary jsonb not null default '{}'::jsonb
);

create index if not exists chrono_game_sessions_user_status_idx
  on public.chrono_game_sessions(user_id, status, started_at desc);

create table if not exists public.chrono_action_receipts (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  action text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, request_id)
);

alter table public.chrono_player_state enable row level security;
alter table public.chrono_game_sessions enable row level security;
alter table public.chrono_action_receipts enable row level security;

-- O navegador não lê nem grava tabelas diretamente. Tudo passa pela Edge Function.
revoke all on public.chrono_player_state from anon, authenticated;
revoke all on public.chrono_game_sessions from anon, authenticated;
revoke all on public.chrono_action_receipts from anon, authenticated;

-- Garante que a service_role continue apta a operar pela Edge Function.
grant all on public.chrono_player_state to service_role;
grant all on public.chrono_game_sessions to service_role;
grant all on public.chrono_action_receipts to service_role;

create or replace function public.chrono_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists chrono_player_state_touch on public.chrono_player_state;
create trigger chrono_player_state_touch
before update on public.chrono_player_state
for each row execute function public.chrono_touch_updated_at();

-- Finalização de partida em uma transação. A recompensa abaixo é propositalmente
-- conservadora e deve ser calibrada depois de medir partidas legítimas.
create or replace function public.chrono_finish_run_server(
  p_user_id uuid,
  p_request_id uuid,
  p_session_id uuid,
  p_score bigint,
  p_wave integer,
  p_kills integer
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
  v_reward integer;
  v_new_relics bigint;
  v_new_high bigint;
  v_meta jsonb;
  v_save jsonb;
  v_response jsonb;
begin
  if p_score < 0 or p_wave < 0 or p_kills < 0 then
    raise exception 'Valores negativos não são aceitos';
  end if;

  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id and request_id = p_request_id;

  if found then
    return v_previous;
  end if;

  select * into v_session
  from public.chrono_game_sessions
  where id = p_session_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'Sessão não encontrada';
  end if;

  if v_session.status <> 'active' then
    raise exception 'Sessão já encerrada';
  end if;

  v_elapsed := extract(epoch from (now() - v_session.started_at));

  if v_elapsed < 5 then
    raise exception 'Partida curta demais';
  end if;

  -- Limites amplos: barram valores absurdos sem punir builds fortes.
  if p_kills > ceil(v_elapsed * 25 + 300) then
    raise exception 'Abates incompatíveis com a duração';
  end if;

  if p_wave > floor(v_elapsed / 3) + 40 then
    raise exception 'Wave incompatível com a duração';
  end if;

  if p_score > (p_kills * 500000::bigint) + (p_wave * 5000000::bigint) + 50000000::bigint then
    raise exception 'Score incompatível com o resumo';
  end if;

  insert into public.chrono_player_state(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if v_state.run_results_enabled then
    v_reward := greatest(0, least(75,
      floor(p_kills / 55.0)::integer + floor(p_wave / 7.0)::integer
    ));
    v_new_high := greatest(v_state.high_score, p_score);
  else
    -- Enquanto a telemetria/checkpoints não estiverem prontos, o endpoint apenas
    -- registra a sessão e não altera a economia nem o ranking oficial.
    v_reward := 0;
    v_new_high := v_state.high_score;
  end if;

  v_new_relics := v_state.relic_shards + v_reward;
  v_save := coalesce(v_state.save_data, '{}'::jsonb);
  v_meta := coalesce(v_save -> 'chrono_v4_meta', '{}'::jsonb);
  v_meta := jsonb_set(v_meta, '{relicShards}', to_jsonb(v_new_relics), true);
  v_meta := jsonb_set(v_meta, '{highScore}', to_jsonb(v_new_high), true);
  v_save := jsonb_set(v_save, '{chrono_v4_meta}', v_meta, true);

  update public.chrono_game_sessions
  set status = 'finished', ended_at = now(), score = p_score,
      wave = p_wave, kills = p_kills,
      summary = jsonb_build_object(
        'elapsedSeconds', v_elapsed,
        'rewardRelics', v_reward
      )
  where id = p_session_id;

  update public.chrono_player_state
  set initialized = true,
      relic_shards = v_new_relics,
      high_score = v_new_high,
      save_data = v_save,
      revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  v_response := jsonb_build_object(
    'accepted', true,
    'rewardRelics', v_reward,
    'progressApplied', v_state.run_results_enabled,
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values (p_user_id, p_request_id, 'finish_run', v_response);

  return v_response;
end;
$$;

revoke all on function public.chrono_finish_run_server(uuid, uuid, uuid, bigint, integer, integer)
  from public, anon, authenticated;
grant execute on function public.chrono_finish_run_server(uuid, uuid, uuid, bigint, integer, integer)
  to service_role;

-- Por segurança, funções auxiliares também não ficam expostas ao cliente.
revoke all on function public.chrono_touch_updated_at() from public, anon, authenticated;
grant execute on function public.chrono_touch_updated_at() to service_role;
