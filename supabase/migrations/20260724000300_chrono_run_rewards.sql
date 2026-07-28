-- Chrono Shards Cloud Save — fase 3
-- Liquidação de recursos obtidos durante partidas.
-- Execute este arquivo uma única vez no SQL Editor do Supabase.
--
-- Segurança: o navegador informa o que observou, mas o servidor limita cada
-- recurso usando duração, wave e abates da sessão. Não existe sincronização
-- livre de saldo nem endpoint que aceite um novo total arbitrário.

alter table public.chrono_player_state
  add column if not exists run_rewards_enabled_at timestamptz;

-- Jogadores que já ativaram a carteira oficial passam a ter a liquidação de
-- partidas ligada após esta migração.
update public.chrono_player_state
set run_results_enabled = true,
    run_rewards_enabled_at = coalesce(run_rewards_enabled_at, now())
where wallet_authority_enabled = true;

-- Atualiza a ativação da economia para também ligar as recompensas de partida.
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

  if found then
    return v_previous;
  end if;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'Save online não encontrado';
  end if;

  if not v_state.initialized or v_state.legacy_imported_at is null then
    raise exception 'Faça a migração inicial do save antes de ativar a economia';
  end if;

  if not v_state.wallet_authority_enabled
     or not v_state.character_purchases_enabled
     or not v_state.run_results_enabled then
    update public.chrono_player_state
    set wallet_authority_enabled = true,
        character_purchases_enabled = true,
        run_results_enabled = true,
        wallet_authority_enabled_at = coalesce(wallet_authority_enabled_at, now()),
        run_rewards_enabled_at = coalesce(run_rewards_enabled_at, now()),
        revision = revision + 1
    where user_id = p_user_id
    returning * into v_state;
  end if;

  v_response := jsonb_build_object(
    'enabled', true,
    'message', 'Compras e recompensas de partida usam o saldo oficial do servidor.',
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values (p_user_id, p_request_id, 'enable_economy', v_response);

  return v_response;
end;
$$;

-- Nova assinatura da liquidação. O servidor calcula a conversão de ouro e
-- aceita somente a parcela de ganhos observados que couber nos limites da run.
create or replace function public.chrono_finish_run_server(
  p_user_id uuid,
  p_request_id uuid,
  p_session_id uuid,
  p_score bigint,
  p_wave integer,
  p_kills integer,
  p_gold bigint,
  p_relic_delta integer,
  p_chrono_delta integer
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
begin
  if p_score < 0 or p_wave < 0 or p_kills < 0
     or p_gold < 0 or p_relic_delta < 0 or p_chrono_delta < 0 then
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

  -- Limites amplos para builds fortes, mas ainda impedem números absurdos.
  if p_kills > ceil(v_elapsed * 25 + 300) then
    raise exception 'Abates incompatíveis com a duração';
  end if;

  if p_wave > floor(v_elapsed / 3) + 40 then
    raise exception 'Wave incompatível com a duração';
  end if;

  if p_score > (p_kills * 500000::bigint)
               + (p_wave * 5000000::bigint)
               + 50000000::bigint then
    raise exception 'Score incompatível com o resumo';
  end if;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;

  if not found or not v_state.initialized then
    raise exception 'Save online não inicializado';
  end if;

  if not v_state.wallet_authority_enabled or not v_state.run_results_enabled then
    raise exception 'Recompensas de partida ainda não estão ativadas';
  end if;

  -- Ouro é convertido no servidor. O teto considera duração, kills e wave.
  v_max_gold := least(
    250000::bigint,
    greatest(
      500::bigint,
      500::bigint
      + p_kills::bigint * 45::bigint
      + p_wave::bigint * 650::bigint
      + floor(v_elapsed * 15)::bigint
    )
  );
  v_accepted_gold := least(p_gold, v_max_gold);
  v_gold_relics := floor(v_accepted_gold / 50.0)::integer;

  -- Ganhos diretos de relíquias da run (drops, lojas internas e recompensas do
  -- modo) são limitados por uma faixa plausível para aquela sessão.
  v_max_relic_delta := least(
    180,
    greatest(3,
      8
      + floor(p_kills / 18.0)::integer
      + floor(p_wave * 1.75)::integer
    )
  );
  v_run_relics := least(p_relic_delta, v_max_relic_delta);

  -- Fragmentos Chrono são raros; o teto cresce lentamente com a partida.
  v_max_chrono_delta := least(
    24,
    greatest(1,
      1
      + floor(p_wave / 4.0)::integer
      + floor(p_kills / 160.0)::integer
    )
  );
  v_run_chrono := least(p_chrono_delta, v_max_chrono_delta);

  v_reward_relics := v_gold_relics + v_run_relics;
  v_new_relics := v_state.relic_shards + v_reward_relics;
  v_new_chrono := v_state.chrono_fragments + v_run_chrono;
  v_new_high := greatest(v_state.high_score, p_score);

  v_save := coalesce(v_state.save_data, '{}'::jsonb);
  v_meta := coalesce(v_save -> 'chrono_v4_meta', '{}'::jsonb);
  v_stats := coalesce(v_meta -> 'stats', '{}'::jsonb);

  v_meta := jsonb_set(v_meta, '{relicShards}', to_jsonb(v_new_relics), true);
  v_meta := jsonb_set(v_meta, '{chronoFragments}', to_jsonb(v_new_chrono), true);
  v_meta := jsonb_set(v_meta, '{highScore}', to_jsonb(v_new_high), true);
  v_stats := jsonb_set(
    v_stats,
    '{chronoFragmentsCollected}',
    to_jsonb(
      case
        when coalesce(v_stats ->> 'chronoFragmentsCollected', '') ~ '^[0-9]+$'
          then (v_stats ->> 'chronoFragmentsCollected')::bigint
        else 0::bigint
      end + v_run_chrono
    ),
    true
  );
  v_meta := jsonb_set(v_meta, '{stats}', v_stats, true);
  v_save := jsonb_set(v_save, '{chrono_v4_meta}', v_meta, true);

  update public.chrono_game_sessions
  set status = 'finished',
      ended_at = now(),
      score = p_score,
      wave = p_wave,
      kills = p_kills,
      summary = jsonb_build_object(
        'elapsedSeconds', v_elapsed,
        'goldClaimed', p_gold,
        'goldAccepted', v_accepted_gold,
        'goldRelics', v_gold_relics,
        'relicDeltaClaimed', p_relic_delta,
        'relicDeltaAccepted', v_run_relics,
        'chronoDeltaClaimed', p_chrono_delta,
        'chronoDeltaAccepted', v_run_chrono,
        'rewardRelics', v_reward_relics
      )
  where id = p_session_id;

  update public.chrono_player_state
  set relic_shards = v_new_relics,
      chrono_fragments = v_new_chrono,
      high_score = v_new_high,
      save_data = v_save,
      revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  v_response := jsonb_build_object(
    'accepted', true,
    'progressApplied', true,
    'rewardRelics', v_reward_relics,
    'rewardChrono', v_run_chrono,
    'goldRelics', v_gold_relics,
    'runRelics', v_run_relics,
    'limits', jsonb_build_object(
      'gold', v_max_gold,
      'relicDelta', v_max_relic_delta,
      'chronoDelta', v_max_chrono_delta
    ),
    'claimed', jsonb_build_object(
      'gold', p_gold,
      'relicDelta', p_relic_delta,
      'chronoDelta', p_chrono_delta
    ),
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values (p_user_id, p_request_id, 'finish_run_v2', v_response);

  return v_response;
end;
$$;

revoke all on function public.chrono_enable_economy_server(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.chrono_enable_economy_server(uuid, uuid)
  to service_role;

revoke all on function public.chrono_finish_run_server(
  uuid, uuid, uuid, bigint, integer, integer, bigint, integer, integer
) from public, anon, authenticated;
grant execute on function public.chrono_finish_run_server(
  uuid, uuid, uuid, bigint, integer, integer, bigint, integer, integer
) to service_role;
