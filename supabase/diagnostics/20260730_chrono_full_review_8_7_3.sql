-- Chrono Shards 8.7.3 — diagnóstico integral somente leitura
-- Execute após a migration 020. Este arquivo NÃO altera dados.

-- 1. Catálogos esperados: 82 skins, 28 Ampliações, 15 Relíquias permanentes,
-- 44 poderes e 40 registros do Bestiário.
select
  (select count(*) from public.chrono_mauro_skin_catalog) as skins,
  (select count(*) from public.chrono_mauro_augment_catalog) as augments,
  (select count(*) from public.chrono_mauro_relic_catalog) as permanent_relics,
  (select count(*) from public.chrono_mauro_power_catalog) as powers,
  (select count(*) from public.chrono_bestiary_catalog) as bestiary_entries;

-- 2. pgcrypto e schema usado pela extensão. O resultado ideal é "extensions".
select e.extname, n.nspname as extension_schema, e.extversion, e.extrelocatable
from pg_catalog.pg_extension e
join pg_catalog.pg_namespace n on n.oid = e.extnamespace
where e.extname = 'pgcrypto';

-- 3. Contas inicializadas sem alguma autoridade necessária. Deve retornar zero linhas.
select user_id, initialized, wallet_authority_enabled, mission_rewards_enabled,
       awakening_authority_enabled, infernal_authority_enabled, doom_authority_enabled,
       mauro_authority_enabled, bestiary_authority_enabled
from public.chrono_player_state
where initialized
  and not (
    wallet_authority_enabled and mission_rewards_enabled and awakening_authority_enabled
    and infernal_authority_enabled and doom_authority_enabled
    and mauro_authority_enabled and bestiary_authority_enabled
  );

-- 4. Ampliações que ainda divergem entre Loja Infernal e inventário global.
-- As duas consultas devem retornar zero linhas.
select i.user_id, x.augment_id, 'inventory_only' as mismatch
from public.chrono_player_inventory i
cross join lateral pg_catalog.unnest(i.augments) x(augment_id)
left join public.chrono_player_infernal f on f.user_id = i.user_id
where not (x.augment_id = any(coalesce(f.infernal_augments, '{}'::text[])))
union all
select f.user_id, x.augment_id, 'infernal_only' as mismatch
from public.chrono_player_infernal f
cross join lateral pg_catalog.unnest(f.infernal_augments) x(augment_id)
left join public.chrono_player_inventory i on i.user_id = f.user_id
where not (x.augment_id = any(coalesce(i.augments, '{}'::text[])));

-- 5. IDs vazios ou duplicados nos inventários. Deve retornar zero linhas.
with arrays as (
  select user_id, 'skins' as field, skins as items_array from public.chrono_player_inventory
  union all select user_id, 'augments', augments from public.chrono_player_inventory
  union all select user_id, 'permanent_relics', permanent_relics from public.chrono_player_inventory
  union all select user_id, 'catalog_powerups', catalog_powerups from public.chrono_player_inventory
  union all select user_id, 'infernal_augments', infernal_augments from public.chrono_player_infernal
  union all select user_id, 'infernal_relics', infernal_relics from public.chrono_player_infernal
  union all select user_id, 'demon_skins', demon_skins from public.chrono_player_infernal
), expanded as (
  select user_id, field, value, count(*) over(partition by user_id, field, value) as occurrences
  from arrays
  cross join lateral pg_catalog.unnest(items_array) item(value)
)
select *
from expanded
where pg_catalog.btrim(coalesce(value, '')) = '' or occurrences > 1;

-- 6. Seleções de skin sem propriedade ou ligadas ao personagem errado.
-- Deve retornar zero linhas.
select i.user_id, selected.key as character_key, selected.value as skin_id
from public.chrono_player_inventory i
left join public.chrono_player_infernal f on f.user_id = i.user_id
cross join lateral pg_catalog.jsonb_each_text(i.selected_skins) selected
where not exists (
  select 1
  from public.chrono_mauro_skin_catalog c
  where c.skin_id = selected.value
    and c.character_key = selected.key
    and (c.rarity = 'base' or c.skin_id = any(i.skins))
)
and not (
  selected.value = any(coalesce(f.demon_skins, '{}'::text[]))
  and (
    selected.value like ('demon_' || selected.key || '_%')
    or (selected.key = 'ricocheteador' and selected.value like 'demon_rico_%')
  )
);

-- 7. Rotações Mauro estruturalmente inválidas. Deve retornar zero linhas.
select user_id, rotation_epoch, rotation_items, sold_slots
from public.chrono_player_mauro
where case
  when pg_catalog.jsonb_typeof(rotation_items) <> 'array' then true
  when pg_catalog.jsonb_array_length(rotation_items) <> 8 then true
  when pg_catalog.jsonb_typeof(sold_slots) <> 'object' then true
  else exists (
    select 1 from pg_catalog.jsonb_each(sold_slots) sold
    where pg_catalog.jsonb_typeof(sold.value) <> 'boolean'
       or sold.key !~ '^[0-7]$'
  )
end;

-- 8. Contadores do Bestiário com IDs inexistentes ou valores inválidos.
-- Deve retornar zero linhas.
select c.user_id, c.session_id, entry.key, entry.value
from public.chrono_bestiary_run_counters c
cross join lateral pg_catalog.jsonb_each_text(c.type_kills) entry
where not exists (
  select 1 from public.chrono_bestiary_catalog b where b.entry_id = entry.key
)
   or entry.value !~ '^[0-9]+$';

-- 8.1. Soma cumulativa por tipo acima dos abates oficiais da sessão.
-- Deve retornar zero linhas. Uma linha indica telemetria antiga inflada por troca
-- de categorias entre checkpoints e precisa ser analisada antes de resgates.
select c.user_id, c.session_id, s.status,
       totals.type_kills_total,
       greatest(
         coalesce(s.kills, 0)::bigint,
         public.chrono_jsonb_bigint(coalesce(s.summary, '{}'::jsonb), array['checkpoint','kills'])
       ) as official_kills
from public.chrono_bestiary_run_counters c
join public.chrono_game_sessions s
  on s.id = c.session_id and s.user_id = c.user_id
cross join lateral (
  select coalesce(sum(
    case when entry.value ~ '^[0-9]+$' then entry.value::bigint else 0 end
  ), 0)::bigint as type_kills_total
  from pg_catalog.jsonb_each_text(c.type_kills) entry
) totals
where totals.type_kills_total > greatest(
  coalesce(s.kills, 0)::bigint,
  public.chrono_jsonb_bigint(coalesce(s.summary, '{}'::jsonb), array['checkpoint','kills'])
);

-- 9. Recompensas do Bestiário marcadas antes da meta. Deve retornar zero linhas.
select p.user_id, p.entry_id, p.kills, c.required_kills, p.claimed_at
from public.chrono_player_bestiary p
join public.chrono_bestiary_catalog c using(entry_id)
where p.claimed_at is not null and p.kills < c.required_kills;

-- 10. Estados ativos de Awakening inválidos ou fantasmas. Deve retornar zero linhas.
select a.user_id, a.character_key, a.stage, a.progress, a.target,
       p.completed_stages, p.ultimate_unlocked
from public.chrono_player_awakening_active a
left join public.chrono_player_awakenings p
  on p.user_id = a.user_id and p.character_key = a.character_key
left join public.chrono_awakening_catalog c
  on c.character_key = a.character_key and c.stage = a.stage
where c.character_key is null
   or p.user_id is null
   or p.ultimate_unlocked
   or p.completed_stages >= a.stage
   or a.stage <> p.completed_stages + 1
   or a.progress < 0
   or a.progress > a.target
   or a.metric is distinct from c.metric
   or a.target is distinct from c.target;

-- 11. Sessões terminadas sem ended_at ou sessões ativas já encerradas. Deve retornar zero linhas.
select id, user_id, status, started_at, ended_at
from public.chrono_game_sessions
where (status in ('finished','rejected','abandoned') and ended_at is null)
   or (status = 'active' and ended_at is not null);

-- 12. Recibos sem ação e distribuição das ações.
-- A primeira consulta deve retornar zero linhas.
select user_id, request_id, action, created_at
from public.chrono_action_receipts
where pg_catalog.btrim(coalesce(action, '')) = '';
select action, count(*) as receipts, min(created_at) as first_seen, max(created_at) as last_seen
from public.chrono_action_receipts
group by action
order by receipts desc, action;

-- 13. Funções SECURITY DEFINER do projeto sem search_path explícito.
-- Deve retornar zero linhas.
select n.nspname as schema_name, p.proname,
       pg_catalog.pg_get_function_identity_arguments(p.oid) as arguments,
       p.proconfig
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef
  and p.proname like 'chrono_%'
  and not exists (
    select 1 from pg_catalog.unnest(coalesce(p.proconfig, '{}'::text[])) setting
    where setting like 'search_path=%'
  )
order by p.proname;

-- 14. Triggers de sincronização do inventário global. Devem existir oito linhas.
select event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_schema = 'public'
  and trigger_name in (
    'chrono_inventory_augments_normalize_insert',
    'chrono_inventory_augments_normalize_update',
    'chrono_infernal_augments_normalize_insert',
    'chrono_infernal_augments_normalize_update',
    'chrono_inventory_augments_sync_insert',
    'chrono_inventory_augments_sync_update',
    'chrono_infernal_augments_sync_insert',
    'chrono_infernal_augments_sync_update'
  )
order by trigger_name;
