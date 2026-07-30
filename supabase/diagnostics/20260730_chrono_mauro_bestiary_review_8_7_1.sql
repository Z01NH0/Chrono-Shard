-- Chrono Shards 8.7.1 — diagnóstico somente leitura
-- Execute depois da migration 018 e do deploy da Edge Function 8.7.1.
-- Nenhuma consulta deste arquivo modifica dados.

-- 1. Defaults autoritativos para contas novas. Os dois primeiros devem ser true.
select column_name, column_default, is_nullable
from information_schema.columns
where table_schema='public'
  and table_name='chrono_player_state'
  and column_name in (
    'mauro_authority_enabled',
    'bestiary_authority_enabled',
    'collection_authority_enabled_at'
  )
order by column_name;

-- 2. Contas sem a autoridade nova. Deve retornar zero linhas.
select user_id, initialized, mauro_authority_enabled,
       bestiary_authority_enabled, collection_authority_enabled_at
from public.chrono_player_state
where not mauro_authority_enabled
   or not bestiary_authority_enabled
   or collection_authority_enabled_at is null;

-- 3. Quantidades oficiais dos catálogos. Esperado: 82, 28, 15, 44 e 40.
select
  (select count(*) from public.chrono_mauro_skin_catalog) as skins,
  (select count(*) from public.chrono_mauro_augment_catalog) as augments,
  (select count(*) from public.chrono_mauro_relic_catalog) as permanent_relics,
  (select count(*) from public.chrono_mauro_power_catalog) as powers,
  (select count(*) from public.chrono_bestiary_catalog) as bestiary_entries;

-- 4. Inventários com IDs que não existem no catálogo correspondente.
-- Todas as consultas devem retornar zero linhas.
select i.user_id, 'skin' as kind, x.id
from public.chrono_player_inventory i
cross join lateral unnest(i.skins) x(id)
left join public.chrono_mauro_skin_catalog c on c.skin_id=x.id
where c.skin_id is null
union all
select i.user_id, 'augment', x.id
from public.chrono_player_inventory i
cross join lateral unnest(i.augments) x(id)
left join public.chrono_mauro_augment_catalog c on c.augment_id=x.id
where c.augment_id is null
union all
select i.user_id, 'permanent_relic', x.id
from public.chrono_player_inventory i
cross join lateral unnest(i.permanent_relics) x(id)
left join public.chrono_mauro_relic_catalog c on c.relic_id=x.id
where c.relic_id is null
union all
select i.user_id, 'catalog_power', x.id
from public.chrono_player_inventory i
cross join lateral unnest(i.catalog_powerups) x(id)
left join public.chrono_mauro_power_catalog c on c.power_id=x.id
where c.power_id is null;

-- 5. Duplicidades internas em arrays oficiais. Deve retornar zero linhas.
select user_id, kind, item_id, count(*) as occurrences
from (
  select user_id, 'skin'::text as kind, unnest(skins) as item_id
  from public.chrono_player_inventory
  union all
  select user_id, 'augment', unnest(augments)
  from public.chrono_player_inventory
  union all
  select user_id, 'permanent_relic', unnest(permanent_relics)
  from public.chrono_player_inventory
  union all
  select user_id, 'catalog_power', unnest(catalog_powerups)
  from public.chrono_player_inventory
) q
group by user_id, kind, item_id
having count(*) > 1;

-- 6. Seleções de skin inválidas ou pertencentes a outro personagem.
-- Deve retornar zero linhas.
select i.user_id, s.key as character_key, s.value as skin_id
from public.chrono_player_inventory i
cross join lateral jsonb_each_text(
  case when jsonb_typeof(i.selected_skins)='object'
       then i.selected_skins else '{}'::jsonb end
) s
left join public.chrono_mauro_skin_catalog c
  on c.skin_id=s.value and c.character_key=s.key
left join public.chrono_player_infernal inf on inf.user_id=i.user_id
where not (
  (c.skin_id is not null and (c.rarity='base' or c.skin_id=any(i.skins)))
  or (
    s.value=any(coalesce(inf.demon_skins,'{}'::text[]))
    and (
      s.value like ('demon_'||s.key||'_%')
      or (s.key='ricocheteador' and s.value like 'demon_rico_%')
    )
  )
);

-- 7. Rotações estruturalmente inválidas. Deve retornar zero linhas.
select user_id, rotation_epoch,
       case when jsonb_typeof(rotation_items)='array'
            then jsonb_array_length(rotation_items) end as item_count,
       jsonb_typeof(rotation_items) as items_type,
       jsonb_typeof(sold_slots) as sold_type
from public.chrono_player_mauro
where not (
  rotation_epoch=-1
  and rotation_items='[]'::jsonb
  and sold_slots='{}'::jsonb
)
and case
  when jsonb_typeof(rotation_items) <> 'array' then true
  when jsonb_array_length(rotation_items) <> 8 then true
  when jsonb_typeof(sold_slots) <> 'object' then true
  else exists (
    select 1 from jsonb_each(sold_slots) e
    where jsonb_typeof(e.value) <> 'boolean'
  )
end;

-- 8. Slots vendidos fora do intervalo 0–7. Deve retornar zero linhas.
select m.user_id, e.key, e.value
from public.chrono_player_mauro m
cross join lateral jsonb_each(
  case when jsonb_typeof(m.sold_slots)='object'
       then m.sold_slots else '{}'::jsonb end
) e
where e.key !~ '^[0-7]$';

-- 9. Resgates de Bestiário feitos abaixo da meta. Deve retornar zero linhas.
select p.user_id, p.entry_id, p.kills, c.required_kills, p.claimed_at
from public.chrono_player_bestiary p
join public.chrono_bestiary_catalog c using(entry_id)
where p.claimed_at is not null and p.kills < c.required_kills;

-- 10. Contadores de run finalizados com sessão ainda ativa ou usuário divergente.
-- Deve retornar zero linhas.
select c.user_id, c.session_id, c.finalized, s.status, s.user_id as session_user
from public.chrono_bestiary_run_counters c
left join public.chrono_game_sessions s on s.id=c.session_id
where s.id is null
   or s.user_id<>c.user_id
   or (c.finalized and s.status='active');

-- 11. Funções essenciais e privilégios. Todas devem existir; anon/authenticated
-- não devem possuir EXECUTE.
select p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role', p.oid, 'EXECUTE') as service_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'chrono_mauro_bestiary_payload_server',
    'chrono_mauro_purchase_server',
    'chrono_mauro_equip_skin_server',
    'chrono_apply_bestiary_run_server',
    'chrono_bestiary_claim_server',
    'chrono_finish_run_bundle_server'
  )
order by p.proname;

-- 12. Recibos repetidos para a mesma conta/request_id. Deve retornar zero linhas.
select user_id, request_id, count(*)
from public.chrono_action_receipts
group by user_id, request_id
having count(*) > 1;

-- 13. Resumo das últimas operações do Mauro/Bestiário para inspeção manual.
select user_id, action, request_id, created_at,
       response->'purchase' as purchase,
       response->>'entryId' as bestiary_entry
from public.chrono_action_receipts
where action in ('mauro_purchase','mauro_equip_skin','bestiary_claim')
order by created_at desc
limit 50;
