-- Chrono Shards 8.7.4 — diagnóstico somente leitura das Missões Gerais
-- Execute depois da migration 021. Este arquivo NÃO altera dados.

-- 1. Catálogo oficial: esperado 34 contratos ativos.
select
  count(*) filter (where active) as active_missions,
  count(*) filter (where active and difficulty='easy') as easy,
  count(*) filter (where active and difficulty='medium') as medium,
  count(*) filter (where active and difficulty='hard') as hard,
  count(*) filter (where active and difficulty='extreme') as extreme,
  count(*) filter (where active and difficulty='secret') as secret
from public.chrono_mission_catalog;

-- 2. Contas que não possuem exatamente os oito slots oficiais. Esperado: zero linhas.
select ps.user_id,count(pm.slot_key) as slot_count,
       array_agg(pm.slot_key order by pm.slot_index) as slots
from public.chrono_player_state ps
left join public.chrono_player_missions pm on pm.user_id=ps.user_id
group by ps.user_id
having count(pm.slot_key)<>8;

-- 3. Slots com chave, índice ou dificuldade incompatíveis. Esperado: zero linhas.
select user_id,slot_key,slot_index,difficulty,mission_id
from public.chrono_player_missions
where not (
  (slot_key='normal:0' and slot_index=0 and difficulty='easy') or
  (slot_key='normal:1' and slot_index=1 and difficulty='easy') or
  (slot_key='normal:2' and slot_index=2 and difficulty='easy') or
  (slot_key='normal:3' and slot_index=3 and difficulty='medium') or
  (slot_key='normal:4' and slot_index=4 and difficulty='medium') or
  (slot_key='normal:5' and slot_index=5 and difficulty='hard') or
  (slot_key='extreme' and slot_index=6 and difficulty='extreme') or
  (slot_key='secret' and slot_index=7 and difficulty='secret')
);

-- 4. Índice repetido na mesma conta. Esperado: zero linhas.
select user_id,slot_index,count(*) as duplicate_count,array_agg(slot_key order by slot_key) as slots
from public.chrono_player_missions
group by user_id,slot_index
having count(*)>1;

-- 5. Mesmo contrato repetido em slots normais. Esperado: zero linhas.
select user_id,mission_id,count(*) as duplicate_count,array_agg(slot_key order by slot_index) as slots
from public.chrono_player_missions
where slot_key like 'normal:%' and mission_id is not null
group by user_id,mission_id
having count(*)>1;

-- 6. Contratos ausentes, inativos ou associados à dificuldade errada. Esperado: zero linhas.
select pm.user_id,pm.slot_key,pm.difficulty,pm.mission_id,c.difficulty as catalog_difficulty,c.active
from public.chrono_player_missions pm
left join public.chrono_mission_catalog c on c.mission_id=pm.mission_id
where pm.mission_id is not null
  and (c.mission_id is null or not c.active or c.difficulty<>pm.difficulty);

-- 7. Baselines maiores que a estatística oficial. Esperado: zero linhas.
select pm.user_id,pm.slot_key,pm.mission_id,c.metric,pm.baseline,
       public.chrono_metric_value(coalesce(ps.mission_stats,'{}'::jsonb),c.metric) as official_value
from public.chrono_player_missions pm
join public.chrono_player_state ps on ps.user_id=pm.user_id
join public.chrono_mission_catalog c on c.mission_id=pm.mission_id and c.active
where not c.absolute_progress
  and pm.baseline>public.chrono_metric_value(coalesce(ps.mission_stats,'{}'::jsonb),c.metric);

-- 8. Missão secreta fora do formato fixo. Esperado: zero linhas.
select user_id,slot_key,mission_id,baseline,cooldown_until
from public.chrono_player_missions
where slot_key='secret'
  and (mission_id is distinct from 's_moon' or baseline<>0 or cooldown_until is not null);

-- 9. Contas permanentes com autoridade de Missões incompleta.
select user_id,initialized,wallet_authority_enabled,mission_rewards_enabled,revision
from public.chrono_player_state
where initialized and (not wallet_authority_enabled or not mission_rewards_enabled);

-- 10. Formato das estatísticas essenciais. Esperado: zero linhas.
select user_id,mission_stats
from public.chrono_player_state
where jsonb_typeof(coalesce(mission_stats,'{}'::jsonb))<>'object'
   or (mission_stats ? 'typeKills' and jsonb_typeof(mission_stats->'typeKills')<>'object')
   or (mission_stats ? 'classKills' and jsonb_typeof(mission_stats->'classKills')<>'object')
   or (mission_stats ? 'classBossKills' and jsonb_typeof(mission_stats->'classBossKills')<>'object')
   or (mission_stats ? 'classSkillUses' and jsonb_typeof(mission_stats->'classSkillUses')<>'object');

-- 11. Runs ativas com checkpoint antigo, úteis para verificar recuperação automática.
select id,user_id,class_key,mode,started_at,
       summary->'checkpoint'->>'savedAt' as checkpoint_saved_at,
       summary->'checkpoint'->>'kills' as checkpoint_kills
from public.chrono_game_sessions
where status='active'
order by started_at;

-- 12. Resumo estrutural após a migration.
select
  to_regprocedure('public.chrono_prepare_missions_server(uuid)') is not null as prepare_rpc,
  to_regprocedure('public.chrono_mission_payload(uuid)') is not null as payload_rpc,
  to_regprocedure('public.chrono_load_missions_server(uuid)') is not null as load_rpc,
  to_regprocedure('public.chrono_claim_mission_server(uuid,uuid,text)') is not null as claim_rpc,
  to_regprocedure('public.chrono_recover_stale_run_checkpoints_server(uuid,integer,boolean)') is not null as recovery_rpc,
  to_regprocedure('public.chrono_finish_run_bundle_server(uuid,uuid,uuid,bigint,integer,integer,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,jsonb)') is not null as finish_bundle_rpc;
