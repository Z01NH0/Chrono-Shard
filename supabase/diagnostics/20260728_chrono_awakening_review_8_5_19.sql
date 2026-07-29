-- Chrono Shards 8.5.19 — diagnóstico somente leitura
-- Execute depois da migration 014. Este arquivo não altera dados.

-- 1) O catálogo esperado possui 10 personagens e 50 etapas.
select
  count(*) as total_stages,
  count(distinct character_key) as total_characters,
  min(stage) as minimum_stage,
  max(stage) as maximum_stage
from public.chrono_awakening_catalog;

-- 2) Cada personagem precisa possuir exatamente as etapas 1 a 5.
select
  character_key,
  count(*) as stage_count,
  min(stage) as minimum_stage,
  max(stage) as maximum_stage
from public.chrono_awakening_catalog
group by character_key
having count(*) <> 5
   or min(stage) <> 1
   or max(stage) <> 5;

-- 3) A etapa ativa deve usar a métrica e a meta atuais do catálogo.
select
  a.user_id,
  a.character_key,
  a.stage,
  a.metric as active_metric,
  c.metric as catalog_metric,
  a.target as active_target,
  c.target as catalog_target
from public.chrono_player_awakening_active a
join public.chrono_awakening_catalog c
  on c.character_key = a.character_key
 and c.stage = a.stage
where a.metric is distinct from c.metric
   or a.target is distinct from c.target;

-- 4) Progresso nunca pode ser negativo nem ultrapassar a meta.
select user_id, character_key, stage, progress, target
from public.chrono_player_awakening_active
where progress < 0
   or progress > target;

-- 5) A etapa ativa deve ser exatamente a próxima etapa da jornada.
select
  a.user_id,
  a.character_key,
  a.stage as active_stage,
  p.completed_stages,
  p.ultimate_unlocked
from public.chrono_player_awakening_active a
left join public.chrono_player_awakenings p
  on p.user_id = a.user_id
 and p.character_key = a.character_key
where p.user_id is null
   or p.ultimate_unlocked
   or a.stage <> p.completed_stages + 1;

-- 6) Não pode existir Awakening ativo para personagem não adquirido.
select a.user_id, a.character_key, a.stage
from public.chrono_player_awakening_active a
where not public.chrono_awakening_character_owned_server(
  a.user_id,
  a.character_key
);

-- 7) Ultimate liberada exige as cinco etapas concluídas.
select user_id, character_key, completed_stages, ultimate_unlocked
from public.chrono_player_awakenings
where ultimate_unlocked
  and completed_stages <> 5;

-- 8) Jornada com progresso precisa estar marcada como desbloqueada.
select user_id, character_key, journey_unlocked, completed_stages
from public.chrono_player_awakenings
where not journey_unlocked
  and (completed_stages > 0 or ultimate_unlocked);

-- 9) Somente uma etapa pode estar ativa por conta (a PK também garante isso).
select user_id, count(*) as active_count
from public.chrono_player_awakening_active
group by user_id
having count(*) > 1;

-- 10) Contadores de sessão inválidos ou regressivos aparentes.
select
  session_id,
  user_id,
  active_character,
  active_stage,
  metric_value,
  finalized,
  updated_at
from public.chrono_progression_run_counters
where metric_value < 0
   or active_stage < 1
   or active_stage > 5;

-- 11) Estado de autoridade das contas inicializadas.
select
  count(*) filter (where initialized) as initialized_accounts,
  count(*) filter (
    where initialized
      and awakening_authority_enabled
      and infernal_authority_enabled
      and doom_authority_enabled
  ) as fully_authoritative_accounts,
  count(*) filter (
    where initialized
      and not (
        awakening_authority_enabled
        and infernal_authority_enabled
        and doom_authority_enabled
      )
  ) as incomplete_authority_accounts
from public.chrono_player_state;

-- 12) Resumo por conta para inspeção manual.
select
  p.user_id,
  count(*) filter (where p.journey_unlocked) as unlocked_journeys,
  sum(p.completed_stages) as completed_stages,
  count(*) filter (where p.ultimate_unlocked) as unlocked_ultimates,
  exists(
    select 1
    from public.chrono_player_awakening_active a
    where a.user_id = p.user_id
  ) as has_active_stage
from public.chrono_player_awakenings p
group by p.user_id
order by completed_stages desc, unlocked_ultimates desc;
