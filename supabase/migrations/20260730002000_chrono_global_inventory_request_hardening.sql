-- Chrono Shards 8.7.3 — inventário global e integridade dos recibos
-- Execute UMA VEZ após 20260730001900_chrono_mauro_chest_mission_integration.sql.

begin;


-- A compra do baú usa gen_random_bytes(). O schema do pgcrypto varia entre
-- instalações do Supabase; detectamos o local real e ajustamos somente a RPC do
-- Chrono Shards. Não movemos a extensão, pois isso poderia quebrar outras funções
-- do mesmo projeto que dependam do schema em que ela já foi instalada.
do $$
declare
  v_schema text;
begin
  select n.nspname
  into v_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_schema is null then
    raise exception 'A extensão pgcrypto não está instalada';
  end if;

  execute pg_catalog.format(
    'alter function public.chrono_mauro_purchase_server(uuid,uuid,text,text,integer,text) set search_path = pg_catalog, %I',
    v_schema
  );
end;
$$;

-- Remove Variation Selector-16 isolado de nomes importados do catálogo. Ele não
-- muda o item, mas fazia HTML e SQL exibirem strings visualmente iguais e binariamente
-- diferentes, atrapalhando comparações, logs e futuras migrações de catálogo.
update public.chrono_mauro_skin_catalog
set name = pg_catalog.btrim(pg_catalog.replace(name, U&'\FE0F', ''))
where pg_catalog.strpos(name, U&'\FE0F') > 0;

-- A mesma Ampliação pode vir da Loja Infernal, de seus baús ou da Loja do Mauro.
-- Até a 8.7.2, cada loja consultava uma coluna diferente, permitindo que uma loja
-- oferecesse e cobrasse novamente por uma Ampliação já adquirida na outra.
create or replace function public.chrono_merge_owned_ids_server(p_left text[], p_right text[])
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array(
    select distinct pg_catalog.btrim(value)
    from pg_catalog.unnest(
      coalesce(p_left, '{}'::text[])
      || coalesce(p_right, '{}'::text[])
    ) as owned(value)
    where pg_catalog.btrim(value) <> ''
    order by pg_catalog.btrim(value)
  );
$$;

-- Garante que toda conta presente em um dos inventários exista no outro.
insert into public.chrono_player_inventory(user_id)
select user_id from public.chrono_player_infernal
on conflict(user_id) do nothing;

insert into public.chrono_player_infernal(user_id)
select user_id from public.chrono_player_inventory
on conflict(user_id) do nothing;

-- Importa e normaliza a propriedade já existente sem remover nenhum item legítimo.
update public.chrono_player_inventory as inventory
set augments = public.chrono_merge_owned_ids_server(inventory.augments, infernal.infernal_augments),
    updated_at = now()
from public.chrono_player_infernal as infernal
where infernal.user_id = inventory.user_id
  and inventory.augments is distinct from public.chrono_merge_owned_ids_server(inventory.augments, infernal.infernal_augments);

update public.chrono_player_infernal as infernal
set infernal_augments = public.chrono_merge_owned_ids_server(infernal.infernal_augments, inventory.augments),
    updated_at = now()
from public.chrono_player_inventory as inventory
where inventory.user_id = infernal.user_id
  and infernal.infernal_augments is distinct from public.chrono_merge_owned_ids_server(infernal.infernal_augments, inventory.augments);

create or replace function public.chrono_normalize_inventory_augments_server()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.augments := public.chrono_merge_owned_ids_server(new.augments, '{}'::text[]);
  return new;
end;
$$;

create or replace function public.chrono_normalize_infernal_augments_server()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.infernal_augments := public.chrono_merge_owned_ids_server(new.infernal_augments, '{}'::text[]);
  return new;
end;
$$;

create or replace function public.chrono_sync_inventory_augments_server()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A atualização da tabela de destino aciona o trigger inverso. A profundidade
  -- impede recursão, mantendo a união monotônica dos itens adquiridos.
  if pg_catalog.pg_trigger_depth() > 1 then return new; end if;

  insert into public.chrono_player_infernal as target(user_id, infernal_augments)
  values(new.user_id, new.augments)
  on conflict(user_id) do update
  set infernal_augments = public.chrono_merge_owned_ids_server(target.infernal_augments, excluded.infernal_augments),
      updated_at = now();
  return new;
end;
$$;

create or replace function public.chrono_sync_infernal_augments_server()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_catalog.pg_trigger_depth() > 1 then return new; end if;

  insert into public.chrono_player_inventory as target(user_id, augments)
  values(new.user_id, new.infernal_augments)
  on conflict(user_id) do update
  set augments = public.chrono_merge_owned_ids_server(target.augments, excluded.augments),
      updated_at = now();
  return new;
end;
$$;

drop trigger if exists chrono_inventory_augments_normalize_insert on public.chrono_player_inventory;
drop trigger if exists chrono_inventory_augments_normalize_update on public.chrono_player_inventory;
drop trigger if exists chrono_infernal_augments_normalize_insert on public.chrono_player_infernal;
drop trigger if exists chrono_infernal_augments_normalize_update on public.chrono_player_infernal;
drop trigger if exists chrono_inventory_augments_sync_insert on public.chrono_player_inventory;
drop trigger if exists chrono_inventory_augments_sync_update on public.chrono_player_inventory;
drop trigger if exists chrono_infernal_augments_sync_insert on public.chrono_player_infernal;
drop trigger if exists chrono_infernal_augments_sync_update on public.chrono_player_infernal;

create trigger chrono_inventory_augments_normalize_insert
before insert on public.chrono_player_inventory
for each row execute function public.chrono_normalize_inventory_augments_server();
create trigger chrono_inventory_augments_normalize_update
before update of augments on public.chrono_player_inventory
for each row execute function public.chrono_normalize_inventory_augments_server();

create trigger chrono_infernal_augments_normalize_insert
before insert on public.chrono_player_infernal
for each row execute function public.chrono_normalize_infernal_augments_server();
create trigger chrono_infernal_augments_normalize_update
before update of infernal_augments on public.chrono_player_infernal
for each row execute function public.chrono_normalize_infernal_augments_server();

create trigger chrono_inventory_augments_sync_insert
after insert on public.chrono_player_inventory
for each row execute function public.chrono_sync_inventory_augments_server();
create trigger chrono_inventory_augments_sync_update
after update of augments on public.chrono_player_inventory
for each row execute function public.chrono_sync_inventory_augments_server();

create trigger chrono_infernal_augments_sync_insert
after insert on public.chrono_player_infernal
for each row execute function public.chrono_sync_infernal_augments_server();
create trigger chrono_infernal_augments_sync_update
after update of infernal_augments on public.chrono_player_infernal
for each row execute function public.chrono_sync_infernal_augments_server();


-- A RPC de equipar skin era a única mutação da Loja do Mauro que não conferia
-- initialized/mauro_authority_enabled no próprio PostgreSQL. A Edge Function já
-- bloqueava o fluxo normal, mas uma chamada service_role interna poderia contornar
-- a flag. Mantemos a mesma assinatura e acrescentamos a validação autoritativa.
create or replace function public.chrono_mauro_equip_skin_server(
  p_user_id uuid,
  p_request_id uuid,
  p_character_key text,
  p_skin_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous jsonb;
  v_previous_action text;
  v_state public.chrono_player_state%rowtype;
  v_inv public.chrono_player_inventory%rowtype;
  v_inf public.chrono_player_infernal%rowtype;
  v_skin public.chrono_mauro_skin_catalog%rowtype;
  v_response jsonb;
begin
  if pg_catalog.btrim(coalesce(p_character_key, '')) = ''
     or pg_catalog.btrim(coalesce(p_skin_id, '')) = '' then
    raise exception 'Seleção de skin inválida';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('chrono:mauro-skin:' || p_user_id::text || ':' || p_request_id::text, 0)
  );

  select action, response
  into v_previous_action, v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id and request_id = p_request_id;
  if found then
    if v_previous_action <> 'mauro_equip_skin' then
      raise exception 'Identificador já usado por outra operação';
    end if;
    return v_previous;
  end if;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id
  for update;
  if not found or not v_state.initialized then
    raise exception 'Save online não inicializado';
  end if;
  if not v_state.mauro_authority_enabled then
    raise exception 'Loja do Mauro ainda não está autoritativa';
  end if;

  insert into public.chrono_player_inventory(user_id)
  values(p_user_id)
  on conflict(user_id) do nothing;
  insert into public.chrono_player_infernal(user_id)
  values(p_user_id)
  on conflict(user_id) do nothing;

  select * into v_inv
  from public.chrono_player_inventory
  where user_id = p_user_id
  for update;
  select * into v_inf
  from public.chrono_player_infernal
  where user_id = p_user_id;

  select * into v_skin
  from public.chrono_mauro_skin_catalog
  where skin_id = p_skin_id and character_key = p_character_key;

  if v_skin.skin_id is null
     and not (p_skin_id = any(coalesce(v_inf.demon_skins, '{}'::text[]))) then
    raise exception 'Skin inválida para este personagem';
  end if;
  if p_skin_id = any(coalesce(v_inf.demon_skins, '{}'::text[]))
     and not (
       p_skin_id like ('demon_' || p_character_key || '_%')
       or (p_character_key = 'ricocheteador' and p_skin_id like 'demon_rico_%')
     ) then
    raise exception 'Skin demoníaca pertence a outro personagem';
  end if;
  if not (
    coalesce(v_skin.rarity, '') = 'base'
    or p_skin_id = any(v_inv.skins)
    or p_skin_id = any(coalesce(v_inf.demon_skins, '{}'::text[]))
  ) then
    raise exception 'Skin não adquirida';
  end if;

  v_inv.selected_skins := pg_catalog.jsonb_set(
    coalesce(v_inv.selected_skins, '{}'::jsonb),
    array[p_character_key],
    pg_catalog.to_jsonb(p_skin_id),
    true
  );
  update public.chrono_player_inventory
  set selected_skins = v_inv.selected_skins,
      updated_at = now()
  where user_id = p_user_id;

  update public.chrono_player_state
  set revision = revision + 1
  where user_id = p_user_id;

  v_response := pg_catalog.jsonb_build_object(
    'equipped', true,
    'characterKey', p_character_key,
    'skinId', p_skin_id,
    'payload', public.chrono_mauro_bestiary_payload_server(p_user_id)
  );
  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values(p_user_id, p_request_id, 'mauro_equip_skin', v_response);
  return v_response;
end;
$$;

revoke all on function public.chrono_mauro_equip_skin_server(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.chrono_mauro_equip_skin_server(uuid,uuid,text,text)
  to service_role;

-- Substitui a versão 8.7.0 do aplicador do Bestiário. A versão antiga repetia
-- a mesma validação e aceitava p_final=true enquanto a sessão ainda estava ativa.
create or replace function public.chrono_apply_bestiary_run_server(
  p_user_id uuid,
  p_session_id uuid,
  p_total_kills bigint,
  p_type_kills jsonb,
  p_final boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.chrono_game_sessions%rowtype;
  v_counter public.chrono_bestiary_run_counters%rowtype;
  v_state public.chrono_player_state%rowtype;
  v_pair record;
  v_catalog record;
  v_value bigint;
  v_prev bigint;
  v_delta bigint;
  v_sum bigint := 0;
  v_previous_total bigint := 0;
  v_remaining bigint := 0;
  v_official_total bigint := 0;
  v_safe_types jsonb := '{}'::jsonb;
  v_updated jsonb := '{}'::jsonb;
begin
  if p_total_kills < 0 or jsonb_typeof(coalesce(p_type_kills, '{}'::jsonb)) <> 'object' then
    raise exception 'Resumo do Bestiário inválido';
  end if;

  select * into v_state
  from public.chrono_player_state
  where user_id = p_user_id;
  if not found or not v_state.initialized or not v_state.bestiary_authority_enabled then
    raise exception 'Bestiário ainda não está autoritativo';
  end if;

  select * into v_session
  from public.chrono_game_sessions
  where id = p_session_id and user_id = p_user_id
  for update;
  if not found then raise exception 'Sessão não encontrada'; end if;
  if v_session.status not in ('active','finished') then
    return jsonb_build_object('accepted',false,'terminal',true);
  end if;
  if p_final and v_session.status <> 'finished' then
    raise exception 'Bestiário final exige uma sessão encerrada';
  end if;

  v_official_total := greatest(
    coalesce(v_session.kills,0)::bigint,
    public.chrono_jsonb_bigint(coalesce(v_session.summary,'{}'::jsonb),array['checkpoint','kills'])
  );
  if p_total_kills > v_official_total then
    raise exception 'Resumo do Bestiário maior que o checkpoint oficial';
  end if;

  -- Valida o resumo atual antes de tocar no progresso oficial.
  for v_pair in select key,value from jsonb_each_text(coalesce(p_type_kills,'{}'::jsonb)) loop
    if not exists(select 1 from public.chrono_bestiary_catalog where entry_id=v_pair.key) then
      raise exception 'Tipo de Bestiário inválido: %',v_pair.key;
    end if;
    begin
      v_value := v_pair.value::bigint;
    exception when others then
      raise exception 'Contagem de Bestiário inválida';
    end;
    if v_value < 0 then raise exception 'Contagem de Bestiário inválida'; end if;
    v_sum := v_sum + v_value;
  end loop;
  if v_sum > p_total_kills then
    raise exception 'Soma do Bestiário maior que o total de abates';
  end if;

  insert into public.chrono_bestiary_run_counters(user_id,session_id)
  values(p_user_id,p_session_id)
  on conflict(user_id,session_id) do nothing;

  select * into v_counter
  from public.chrono_bestiary_run_counters
  where user_id=p_user_id and session_id=p_session_id
  for update;

  if v_counter.finalized then
    return jsonb_build_object('accepted',true,'final',true,'replayed',true,'updated','{}'::jsonb);
  end if;

  v_counter.type_kills := coalesce(v_counter.type_kills,'{}'::jsonb);

  -- Confere a telemetria já aceita para a sessão. Ela nunca pode consumir mais
  -- categorias do que o total oficial de abates da própria partida.
  for v_pair in select key,value from jsonb_each_text(v_counter.type_kills) loop
    if not exists(select 1 from public.chrono_bestiary_catalog where entry_id=v_pair.key) then
      raise exception 'Contador antigo do Bestiário contém tipo inválido: %',v_pair.key;
    end if;
    begin
      v_value := v_pair.value::bigint;
    exception when others then
      raise exception 'Contador antigo do Bestiário está corrompido';
    end;
    if v_value < 0 then raise exception 'Contador antigo do Bestiário está corrompido'; end if;
    v_previous_total := v_previous_total + v_value;
  end loop;

  if v_previous_total > v_official_total then
    raise exception 'Contadores do Bestiário excedem os abates oficiais da sessão';
  end if;

  -- Preserva tudo que já foi confirmado e distribui apenas o orçamento restante.
  -- Assim, trocar a categoria de uma mesma morte entre checkpoints não cria uma
  -- segunda morte no Bestiário.
  v_remaining := greatest(0, v_official_total - v_previous_total);
  for v_catalog in
    select entry_id
    from public.chrono_bestiary_catalog
    order by sort_order, entry_id
  loop
    v_prev := public.chrono_jsonb_bigint(v_counter.type_kills,array[v_catalog.entry_id]);
    v_value := public.chrono_jsonb_bigint(coalesce(p_type_kills,'{}'::jsonb),array[v_catalog.entry_id]);
    v_delta := least(greatest(0,v_value-v_prev),v_remaining);

    if v_delta > 0 then
      insert into public.chrono_player_bestiary(user_id,entry_id,kills)
      values(p_user_id,v_catalog.entry_id,v_delta)
      on conflict(user_id,entry_id) do update
      set kills=public.chrono_player_bestiary.kills+excluded.kills,
          updated_at=now()
      returning kills into v_value;
      v_updated := jsonb_set(v_updated,array[v_catalog.entry_id],to_jsonb(v_value),true);
      v_remaining := v_remaining - v_delta;
    end if;

    if v_prev + v_delta > 0 then
      v_safe_types := jsonb_set(
        v_safe_types,
        array[v_catalog.entry_id],
        to_jsonb(v_prev + v_delta),
        true
      );
    end if;
  end loop;

  update public.chrono_bestiary_run_counters
  set type_kills=v_safe_types,
      finalized=finalized or p_final,
      updated_at=now()
  where user_id=p_user_id and session_id=p_session_id;

  return jsonb_build_object('accepted',true,'final',p_final,'updated',v_updated);
end;
$$;

revoke all on function public.chrono_apply_bestiary_run_server(uuid,uuid,bigint,jsonb,boolean)
  from public,anon,authenticated;
grant execute on function public.chrono_apply_bestiary_run_server(uuid,uuid,bigint,jsonb,boolean)
  to service_role;

-- Recibos vazios ou sem ação dificultam a auditoria. A chave primária histórica
-- permanece (user_id, request_id); a Edge Function 8.7.3 transforma o UUID do
-- cliente em um UUID determinístico por ação antes de chamar cada RPC econômica.
update public.chrono_action_receipts
set action = 'legacy_unknown'
where pg_catalog.btrim(coalesce(action, '')) = '';

alter table public.chrono_action_receipts
  drop constraint if exists chrono_action_receipts_action_not_empty;
alter table public.chrono_action_receipts
  add constraint chrono_action_receipts_action_not_empty
  check (pg_catalog.btrim(action) <> '');

create index if not exists chrono_action_receipts_user_action_created_idx
  on public.chrono_action_receipts(user_id, action, created_at desc);

revoke all on function public.chrono_merge_owned_ids_server(text[],text[]) from public,anon,authenticated;
revoke all on function public.chrono_normalize_inventory_augments_server() from public,anon,authenticated;
revoke all on function public.chrono_normalize_infernal_augments_server() from public,anon,authenticated;
revoke all on function public.chrono_sync_inventory_augments_server() from public,anon,authenticated;
revoke all on function public.chrono_sync_infernal_augments_server() from public,anon,authenticated;

grant execute on function public.chrono_merge_owned_ids_server(text[],text[]) to service_role;
grant execute on function public.chrono_normalize_inventory_augments_server() to service_role;
grant execute on function public.chrono_normalize_infernal_augments_server() to service_role;
grant execute on function public.chrono_sync_inventory_augments_server() to service_role;
grant execute on function public.chrono_sync_infernal_augments_server() to service_role;

comment on function public.chrono_merge_owned_ids_server(text[],text[]) is
  'União normalizada e sem duplicatas de identificadores permanentes — Chrono Shards 8.7.3';
comment on function public.chrono_sync_inventory_augments_server() is
  'Sincroniza Ampliações da Loja do Mauro com o inventário Infernal — Chrono Shards 8.7.3';
comment on function public.chrono_sync_infernal_augments_server() is
  'Sincroniza Ampliações Infernais com o inventário global — Chrono Shards 8.7.3';

commit;
