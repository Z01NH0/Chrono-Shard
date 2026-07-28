-- Chrono Shards 8.5.7 — auditoria SOMENTE LEITURA
-- Pode ser executada no SQL Editor depois da migração de consistência.
-- Não altera dados.

-- 1) Estado geral de cada conta.
select
  user_id,
  initialized,
  authority_mode,
  revision,
  relic_shards,
  chrono_fragments,
  awakening_keys,
  sinner_tears,
  wallet_authority_enabled,
  character_purchases_enabled,
  run_results_enabled,
  mission_rewards_enabled,
  code_rewards_enabled,
  mission_reputation,
  mission_legacy_reconciled_at,
  mission_legacy_imported_count,
  legacy_imported_at,
  updated_at
from public.chrono_player_state
order by updated_at desc;

-- 2) Quantidade e integridade dos contratos por conta.
select
  ps.user_id,
  count(pm.*) filter (where pm.slot_key like 'normal:%') as normal_slots,
  count(pm.*) filter (where pm.slot_key = 'extreme') as extreme_slots,
  count(pm.*) filter (where pm.slot_key = 'secret') as secret_slots,
  count(pm.*) filter (
    where pm.mission_id is not null and c.mission_id is null
  ) as invalid_missions,
  count(pm.*) filter (
    where pm.mission_id is not null and c.difficulty is distinct from pm.difficulty
  ) as wrong_difficulty
from public.chrono_player_state ps
left join public.chrono_player_missions pm on pm.user_id = ps.user_id
left join public.chrono_mission_catalog c
  on c.mission_id = pm.mission_id and c.active
group by ps.user_id
order by ps.user_id;

-- 3) Duplicatas entre os seis contratos normais.
select user_id, mission_id, count(*) as occurrences
from public.chrono_player_missions
where slot_key like 'normal:%' and mission_id is not null
group by user_id, mission_id
having count(*) > 1
order by user_id, mission_id;

-- 4) Contratos com progresso oficial calculado.
select
  pm.user_id,
  pm.slot_key,
  pm.difficulty,
  pm.mission_id,
  c.title,
  c.metric,
  pm.baseline,
  public.chrono_metric_value(ps.mission_stats, c.metric) as current_value,
  case
    when c.absolute_progress then public.chrono_metric_value(ps.mission_stats, c.metric)
    else greatest(0, public.chrono_metric_value(ps.mission_stats, c.metric) - pm.baseline)
  end as official_progress,
  c.target,
  case
    when c.absolute_progress then public.chrono_metric_value(ps.mission_stats, c.metric) >= c.target
    else greatest(0, public.chrono_metric_value(ps.mission_stats, c.metric) - pm.baseline) >= c.target
  end as completed,
  pm.cooldown_until,
  pm.claimed
from public.chrono_player_missions pm
join public.chrono_player_state ps on ps.user_id = pm.user_id
left join public.chrono_mission_catalog c
  on c.mission_id = pm.mission_id and c.active
order by pm.user_id, pm.slot_index;

-- 5) Verificação de recibos duplicados. Deve retornar zero linhas.
select user_id, request_id, count(*) as occurrences
from public.chrono_action_receipts
group by user_id, request_id
having count(*) > 1;

-- 6) Sessões ainda abertas há mais de 24 horas, úteis para limpeza posterior.
select id, user_id, mode, class_key, status, started_at
from public.chrono_game_sessions
where status = 'active' and started_at < now() - interval '24 hours'
order by started_at;

-- 7) Deve existir no máximo uma sessão ativa por conta. Deve retornar zero linhas.
select user_id, count(*) as active_sessions
from public.chrono_game_sessions
where status = 'active'
group by user_id
having count(*) > 1;

-- 8) Modos ou personagens desconhecidos registrados em sessões.
select id, user_id, mode, class_key, status, started_at
from public.chrono_game_sessions
where mode not in ('normal','rift','doom','dunes','tutorial')
   or class_key not in (
     'assault','sniper','engineer','mage','ronin','alchemist','reaper','colonel',
     'chronoHero','shadowChild','moonSlayer','bomber','archer','ricocheteador',
     'stellarEmperor','nefalem'
   )
order by started_at desc;

-- 9) RLS deve estar ligada nas sete tabelas do Chrono.
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'chrono_player_state','chrono_game_sessions','chrono_action_receipts',
    'chrono_mission_catalog','chrono_player_missions','chrono_reward_codes',
    'chrono_redeemed_codes'
  )
order by c.relname;

-- 10) anon/authenticated não devem possuir privilégios diretos nessas tabelas.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'chrono_player_state','chrono_game_sessions','chrono_action_receipts',
    'chrono_mission_catalog','chrono_player_missions','chrono_reward_codes',
    'chrono_redeemed_codes'
  )
  and grantee in ('anon','authenticated')
order by grantee, table_name, privilege_type;
