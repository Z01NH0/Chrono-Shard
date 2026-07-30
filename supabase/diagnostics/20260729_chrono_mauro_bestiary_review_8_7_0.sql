-- Chrono Shards 8.7.0 — diagnóstico somente leitura
-- As consultas marcadas como "deve retornar zero linhas" não alteram dados.

-- 1. Catálogos oficiais esperados: 82 skins, 28 ampliações, 15 relíquias,
-- 44 poderes de catálogo e 40 registros do Bestiário.
select
  (select count(*) from public.chrono_mauro_skin_catalog) as skins,
  (select count(*) from public.chrono_mauro_augment_catalog) as augments,
  (select count(*) from public.chrono_mauro_relic_catalog) as permanent_relics,
  (select count(*) from public.chrono_mauro_power_catalog) as catalog_powerups,
  (select count(*) from public.chrono_bestiary_catalog) as bestiary_entries;

-- 2. Contas inicializadas sem as novas autoridades. Deve retornar zero linhas.
select user_id, mauro_authority_enabled, bestiary_authority_enabled, collection_authority_enabled_at
from public.chrono_player_state
where initialized
  and (not mauro_authority_enabled or not bestiary_authority_enabled);

-- 3. Contas inicializadas sem inventário ou estado da loja. Deve retornar zero linhas
-- depois que cada conta carregar a versão nova ao menos uma vez.
select s.user_id,
       (i.user_id is null) as inventory_missing,
       (m.user_id is null) as mauro_state_missing
from public.chrono_player_state s
left join public.chrono_player_inventory i on i.user_id=s.user_id
left join public.chrono_player_mauro m on m.user_id=s.user_id
where s.initialized and (i.user_id is null or m.user_id is null);

-- 4. Itens comuns/raros/épicos do inventário fora do catálogo Mauro.
-- Skins demoníacas são mantidas na tabela Infernal e não aparecem nesta consulta.
select i.user_id, skin_id
from public.chrono_player_inventory i
cross join lateral unnest(i.skins) skin_id
left join public.chrono_mauro_skin_catalog c on c.skin_id=skin_id
where c.skin_id is null;

-- 5. Ampliações do inventário fora do catálogo Mauro.
select i.user_id, augment_id
from public.chrono_player_inventory i
cross join lateral unnest(i.augments) augment_id
left join public.chrono_mauro_augment_catalog c on c.augment_id=augment_id
where c.augment_id is null;

-- 6. Relíquias permanentes inválidas. Deve retornar zero linhas.
select i.user_id, relic_id
from public.chrono_player_inventory i
cross join lateral unnest(i.permanent_relics) relic_id
left join public.chrono_mauro_relic_catalog c on c.relic_id=relic_id
where c.relic_id is null;

-- 7. Poderes de catálogo inválidos. Deve retornar zero linhas.
select i.user_id, power_id
from public.chrono_player_inventory i
cross join lateral unnest(i.catalog_powerups) power_id
left join public.chrono_mauro_power_catalog c on c.power_id=power_id
where c.power_id is null;

-- 8. Registros resgatados sem alcançar a meta. Deve retornar zero linhas.
select b.user_id,b.entry_id,b.kills,c.required_kills,b.claimed_at
from public.chrono_player_bestiary b
join public.chrono_bestiary_catalog c on c.entry_id=b.entry_id
where b.claimed_at is not null and b.kills<c.required_kills;

-- 9. Contadores de run com chaves que não existem no catálogo. Deve retornar zero linhas.
select r.user_id,r.session_id,k.key
from public.chrono_bestiary_run_counters r
cross join lateral jsonb_object_keys(r.type_kills) k(key)
left join public.chrono_bestiary_catalog c on c.entry_id=k.key
where c.entry_id is null;

-- 10. Contadores por tipo cuja soma ultrapassa os abates da sessão. Deve retornar zero linhas.
select r.user_id,r.session_id,g.kills as session_kills,
       coalesce((select sum(public.chrono_safe_nonnegative_bigint_server(value))
                 from jsonb_each_text(r.type_kills)),0) as typed_kills
from public.chrono_bestiary_run_counters r
join public.chrono_game_sessions g on g.id=r.session_id and g.user_id=r.user_id
where coalesce((select sum(public.chrono_safe_nonnegative_bigint_server(value))
                from jsonb_each_text(r.type_kills)),0) > coalesce(g.kills,0)
  and g.status<>'active';

-- 11. Slots vendidos fora de 0–7. Deve retornar zero linhas.
select m.user_id,k.key
from public.chrono_player_mauro m
cross join lateral jsonb_object_keys(m.sold_slots) k(key)
where k.key !~ '^[0-7]$';

-- 12. Rotações com quantidade de itens diferente de oito. Deve retornar zero linhas.
select user_id,rotation_epoch,jsonb_array_length(rotation_items) as items
from public.chrono_player_mauro
where jsonb_array_length(rotation_items)<>8 and rotation_epoch>=0;

-- 13. RPCs obrigatórias da fase 8.7.0. Deve listar seis funções.
select p.proname,pg_get_function_identity_arguments(p.oid) as arguments
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

-- 14. Resumo da atividade autoritativa.
select
  (select count(*) from public.chrono_player_inventory) as inventories,
  (select count(*) from public.chrono_player_mauro) as mauro_accounts,
  (select count(*) from public.chrono_player_bestiary where kills>0) as bestiary_progress_rows,
  (select count(*) from public.chrono_player_bestiary where claimed_at is not null) as claimed_records,
  (select count(*) from public.chrono_action_receipts where action='mauro_purchase') as mauro_receipts,
  (select count(*) from public.chrono_action_receipts where action='bestiary_claim') as bestiary_receipts;

-- 15. Contadores marcados como finalizados enquanto a sessão ainda está ativa,
-- ou sessões encerradas sem contador finalizado. Deve retornar zero linhas após a próxima
-- sincronização da conta.
select r.user_id,r.session_id,g.status,r.finalized
from public.chrono_bestiary_run_counters r
join public.chrono_game_sessions g on g.id=r.session_id and g.user_id=r.user_id
where (r.finalized and g.status='active')
   or (not r.finalized and g.status='finished');

-- 16. Privilégios das RPCs e helpers internos. PUBLIC/anon/authenticated não devem possuir EXECUTE.
select p.proname,pg_get_function_identity_arguments(p.oid) as arguments,
       exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where a.grantee=0 and a.privilege_type='EXECUTE') as public_execute,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') as service_role_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'chrono_seed_mod_server',
    'chrono_rarity_rank_server',
    'chrono_chest_roll_rarity_server',
    'chrono_build_mauro_rotation_server',
    'chrono_refresh_mauro_locked_server',
    'chrono_mauro_bestiary_payload_server',
    'chrono_mauro_purchase_server',
    'chrono_mauro_equip_skin_server',
    'chrono_apply_bestiary_run_server',
    'chrono_bestiary_claim_server',
    'chrono_finish_run_bundle_server',
    'chrono_safe_nonnegative_bigint_server',
    'chrono_safe_bool_server'
  )
order by p.proname;


-- 17. Skins selecionadas inválidas, não adquiridas ou ligadas ao personagem errado.
-- Deve retornar zero linhas; o payload 8.7.0 também remove essas seleções automaticamente.
select i.user_id,s.key as character_key,s.value as skin_id
from public.chrono_player_inventory i
cross join lateral jsonb_each_text(i.selected_skins) s
left join public.chrono_player_infernal inf on inf.user_id=i.user_id
where not exists(
        select 1 from public.chrono_mauro_skin_catalog c
        where c.skin_id=s.value and c.character_key=s.key
          and (c.rarity='base' or c.skin_id=any(i.skins))
      )
  and not(
        s.value=any(coalesce(inf.demon_skins,'{}'::text[]))
        and (s.value like ('demon_'||s.key||'_%') or (s.key='ricocheteador' and s.value like 'demon_rico_%'))
      );
