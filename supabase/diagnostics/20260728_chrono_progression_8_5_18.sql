-- Chrono Shards 8.5.18 — diagnóstico somente leitura.

-- 1. Contas que ainda não receberam todas as autoridades.
select user_id, awakening_authority_enabled, infernal_authority_enabled, doom_authority_enabled
from public.chrono_player_state
where not awakening_authority_enabled
   or not infernal_authority_enabled
   or not doom_authority_enabled;

-- 2. Etapas ativas inconsistentes com o catálogo.
select a.*
from public.chrono_player_awakening_active a
left join public.chrono_awakening_catalog c
  on c.character_key=a.character_key and c.stage=a.stage
where c.character_key is null
   or a.metric<>c.metric
   or a.target<>c.target
   or a.progress<0
   or a.progress>a.target;

-- 3. Jornadas com valores fora do intervalo ou Ultimate prematura.
select *
from public.chrono_player_awakenings
where completed_stages not between 0 and 5
   or (ultimate_unlocked and completed_stages<5);

-- 4. Mais de uma etapa ativa por usuário (deve ser impossível pela PK).
select user_id,count(*)
from public.chrono_player_awakening_active
group by user_id
having count(*)>1;

-- 5. Fila DOOM acima do limite ou itens não reconhecidos.
select i.user_id,i.queued_doom_buffs
from public.chrono_player_infernal i
where cardinality(i.queued_doom_buffs)>2
   or exists (
     select 1 from unnest(i.queued_doom_buffs) x
     where not public.chrono_valid_doom_buff(x)
   );

-- 6. Relíquias/skins inválidas.
select i.user_id,i.infernal_relics,i.demon_skins
from public.chrono_player_infernal i
where exists (select 1 from unnest(i.infernal_relics) x where not public.chrono_valid_infernal_relic(x))
   or exists (select 1 from unnest(i.demon_skins) x where not public.chrono_valid_demon_skin(x));

-- 7. Sessões DOOM ativas e pactos associados.
select id,user_id,status,started_at,server_context->'doomBuffs' as doom_buffs
from public.chrono_game_sessions
where mode='doom'
order by started_at desc
limit 50;

-- 8. Contadores de progressão sem sessão correspondente.
select c.*
from public.chrono_progression_run_counters c
left join public.chrono_game_sessions s on s.id=c.session_id
where s.id is null;

-- 9. Resumo por conta.
select s.user_id,s.awakening_keys,s.sinner_tears,
       coalesce(i.nefalem_owned,false) as nefalem_owned,
       coalesce(i.doom_unlocked,false) as doom_unlocked,
       cardinality(coalesce(i.infernal_relics,'{}'::text[])) as infernal_relic_count,
       cardinality(coalesce(i.demon_skins,'{}'::text[])) as demon_skin_count
from public.chrono_player_state s
left join public.chrono_player_infernal i on i.user_id=s.user_id
order by s.updated_at desc nulls last;
