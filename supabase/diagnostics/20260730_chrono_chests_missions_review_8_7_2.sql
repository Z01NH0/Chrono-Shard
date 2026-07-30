-- Chrono Shards 8.7.2 — diagnóstico somente leitura
-- Execute após a migration 019 e o deploy da Edge Function 8.7.2.

-- 1. A extensão pgcrypto deve existir e informar o schema em que foi instalada.
select e.extname, n.nspname as extension_schema, e.extversion
from pg_catalog.pg_extension e
join pg_catalog.pg_namespace n on n.oid = e.extnamespace
where e.extname = 'pgcrypto';

-- 2. A função de compra do Mauro deve enxergar pg_catalog e o schema do pgcrypto.
select
  p.oid::regprocedure as function_signature,
  p.proconfig
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'chrono_mauro_purchase_server';

-- 3. O bundle atômico de checkpoint deve existir com a assinatura 8.7.2.
select
  p.oid::regprocedure as function_signature,
  p.prosecdef as security_definer,
  p.proconfig
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'chrono_checkpoint_run_bundle_server';

-- 4. Somente service_role deve possuir execução explícita nas novas funções.
select
  p.oid::regprocedure as function_signature,
  coalesce(r.rolname, 'PUBLIC') as grantee,
  x.privilege_type
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
left join pg_catalog.pg_roles r on r.oid = x.grantee
where n.nspname = 'public'
  and p.proname in ('chrono_checkpoint_run_bundle_server')
order by 1, 2;

-- 5. Contadores do Bestiário nunca podem ultrapassar o total oficial conhecido
-- da sessão. Deve retornar zero linhas.
select
  c.user_id,
  c.session_id,
  coalesce((select sum(value::bigint) from jsonb_each_text(c.type_kills)), 0) as classified_kills,
  greatest(
    coalesce(s.kills, 0)::bigint,
    public.chrono_jsonb_bigint(coalesce(s.summary, '{}'::jsonb), array['checkpoint','kills'])
  ) as official_kills
from public.chrono_bestiary_run_counters c
join public.chrono_game_sessions s on s.id = c.session_id and s.user_id = c.user_id
where coalesce((select sum(value::bigint) from jsonb_each_text(c.type_kills)), 0)
  > greatest(
      coalesce(s.kills, 0)::bigint,
      public.chrono_jsonb_bigint(coalesce(s.summary, '{}'::jsonb), array['checkpoint','kills'])
    );

-- 6. Entradas do Bestiário sem catálogo correspondente. Deve retornar zero linhas.
select b.user_id, b.entry_id, b.kills
from public.chrono_player_bestiary b
left join public.chrono_bestiary_catalog c on c.entry_id = b.entry_id
where c.entry_id is null;

-- 7. Missões oficiais com IDs que não existem no catálogo. Deve retornar zero linhas.
select m.user_id, m.slot_key, m.mission_id
from public.chrono_player_missions m
left join public.chrono_mission_catalog c on c.mission_id = m.mission_id
where m.mission_id is not null and c.mission_id is null;

-- 8. Visão resumida das autoridades e dos estados existentes.
select
  count(*) as accounts,
  count(*) filter (where mauro_authority_enabled) as mauro_enabled,
  count(*) filter (where bestiary_authority_enabled) as bestiary_enabled,
  count(*) filter (where mission_rewards_enabled) as missions_enabled
from public.chrono_player_state;

-- 9. Rotações do Mauro estruturalmente inválidas. Deve retornar zero linhas.
select user_id, rotation_epoch, rotation_items, sold_slots
from public.chrono_player_mauro
where jsonb_typeof(rotation_items) <> 'array'
   or jsonb_array_length(rotation_items) <> 8
   or jsonb_typeof(sold_slots) <> 'object';

-- 10. Compras de baú registradas recentemente para conferência manual.
select user_id, request_id, action, created_at,
       response #>> '{purchase,item,type}' as item_type,
       jsonb_array_length(coalesce(response #> '{chest,rewards}', '[]'::jsonb)) as reward_count
from public.chrono_action_receipts
where action = 'mauro_purchase'
  and response #>> '{purchase,item,type}' = 'mauroChest714'
order by created_at desc
limit 20;
