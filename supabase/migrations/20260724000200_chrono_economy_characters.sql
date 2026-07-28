-- Chrono Shards Cloud Save — fase 2
-- Economia de compras e personagens validados no servidor.
-- Execute este arquivo uma única vez no SQL Editor do Supabase.

alter table public.chrono_player_state
  add column if not exists wallet_authority_enabled boolean not null default false,
  add column if not exists character_purchases_enabled boolean not null default false,
  add column if not exists wallet_authority_enabled_at timestamptz;

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

  if not v_state.wallet_authority_enabled or not v_state.character_purchases_enabled then
    update public.chrono_player_state
    set wallet_authority_enabled = true,
        character_purchases_enabled = true,
        wallet_authority_enabled_at = coalesce(wallet_authority_enabled_at, now()),
        revision = revision + 1
    where user_id = p_user_id
    returning * into v_state;
  end if;

  v_response := jsonb_build_object(
    'enabled', true,
    'message', 'Compras de personagens agora usam o saldo oficial do servidor.',
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values (p_user_id, p_request_id, 'enable_economy', v_response);

  return v_response;
end;
$$;

create or replace function public.chrono_purchase_character_server(
  p_user_id uuid,
  p_request_id uuid,
  p_character_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_previous jsonb;
  v_save jsonb;
  v_meta jsonb;
  v_unlocks jsonb;
  v_secret jsonb;
  v_currency text;
  v_cost bigint;
  v_owned boolean := false;
  v_revealed boolean := true;
  v_new_relics bigint;
  v_new_chrono bigint;
  v_response jsonb;
begin
  if p_character_key is null or length(p_character_key) < 1 or length(p_character_key) > 80 then
    raise exception 'Personagem inválido';
  end if;

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

  if not found or not v_state.initialized then
    raise exception 'Save online não inicializado';
  end if;

  if not v_state.wallet_authority_enabled or not v_state.character_purchases_enabled then
    raise exception 'A proteção de compras ainda não foi ativada';
  end if;

  case p_character_key
    when 'engineer'       then v_currency := 'relic';  v_cost := 30;
    when 'mage'           then v_currency := 'relic';  v_cost := 35;
    when 'ronin'          then v_currency := 'relic';  v_cost := 40;
    when 'alchemist'      then v_currency := 'relic';  v_cost := 40;
    when 'reaper'         then v_currency := 'relic';  v_cost := 50;
    when 'colonel'        then v_currency := 'relic';  v_cost := 75;
    when 'chronoHero'     then v_currency := 'relic';  v_cost := 110;
    when 'shadowChild'    then v_currency := 'relic';  v_cost := 170;
    when 'bomber'         then v_currency := 'relic';  v_cost := 55;
    when 'archer'         then v_currency := 'relic';  v_cost := 55;
    when 'ricocheteador'  then v_currency := 'relic';  v_cost := 75;
    when 'moonSlayer'     then v_currency := 'chrono'; v_cost := 17;
    when 'stellarEmperor' then v_currency := 'chrono'; v_cost := 30;
    when 'assault'        then raise exception 'Este personagem já é gratuito';
    when 'sniper'         then raise exception 'Este personagem já é gratuito';
    else raise exception 'Personagem ainda não suportado pela compra segura';
  end case;

  v_save := coalesce(v_state.save_data, '{}'::jsonb);
  v_meta := coalesce(v_save -> 'chrono_v4_meta', '{}'::jsonb);
  v_unlocks := coalesce(v_save -> 'chrono_v4_meta_class_unlocks_v3', '[]'::jsonb);
  v_secret := coalesce(v_save -> 'chrono_v4_meta_secret_rift_v1', '{}'::jsonb);

  if jsonb_typeof(v_unlocks) <> 'array' then
    v_unlocks := '[]'::jsonb;
  end if;

  select exists(
    select 1
    from jsonb_array_elements_text(v_unlocks) item
    where item = p_character_key
  ) into v_owned;

  if p_character_key = 'moonSlayer' and coalesce(v_meta ->> 'unlockedMoonSlayer', 'false') = 'true' then
    v_owned := true;
  end if;

  if v_owned then
    raise exception 'Personagem já adquirido';
  end if;

  if p_character_key = 'shadowChild' then
    v_revealed := coalesce(v_secret ->> 'lostEmperorDefeated', 'false') = 'true';
  elsif p_character_key = 'moonSlayer' then
    v_revealed := coalesce(v_meta ->> 'moonMissionClaimed', 'false') = 'true';
  elsif p_character_key = 'stellarEmperor' then
    v_revealed := (
      coalesce(v_meta ->> 'stellarEmperorRevealed', 'false') = 'true'
      or coalesce(v_meta ->> 'stellarEmperorSecretUnlocked', 'false') = 'true'
    );
  end if;

  if not v_revealed then
    raise exception 'Os requisitos secretos deste personagem ainda não foram cumpridos';
  end if;

  v_new_relics := v_state.relic_shards;
  v_new_chrono := v_state.chrono_fragments;

  if v_currency = 'relic' then
    if v_new_relics < v_cost then
      raise exception 'Relíquias insuficientes no saldo oficial';
    end if;
    v_new_relics := v_new_relics - v_cost;
    v_meta := jsonb_set(v_meta, '{relicShards}', to_jsonb(v_new_relics), true);
  else
    if v_new_chrono < v_cost then
      raise exception 'Fragmentos Chrono insuficientes no saldo oficial';
    end if;
    v_new_chrono := v_new_chrono - v_cost;
    v_meta := jsonb_set(v_meta, '{chronoFragments}', to_jsonb(v_new_chrono), true);
  end if;

  if p_character_key = 'moonSlayer' then
    v_meta := jsonb_set(v_meta, '{unlockedMoonSlayer}', 'true'::jsonb, true);
  end if;

  v_unlocks := v_unlocks || jsonb_build_array(p_character_key);
  v_save := jsonb_set(v_save, '{chrono_v4_meta}', v_meta, true);
  v_save := jsonb_set(v_save, '{chrono_v4_meta_class_unlocks_v3}', v_unlocks, true);

  update public.chrono_player_state
  set relic_shards = v_new_relics,
      chrono_fragments = v_new_chrono,
      save_data = v_save,
      revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  v_response := jsonb_build_object(
    'purchased', true,
    'characterKey', p_character_key,
    'currency', v_currency,
    'cost', v_cost,
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values (p_user_id, p_request_id, 'purchase_character', v_response);

  return v_response;
end;
$$;

revoke all on function public.chrono_enable_economy_server(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.chrono_enable_economy_server(uuid, uuid)
  to service_role;

revoke all on function public.chrono_purchase_character_server(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.chrono_purchase_character_server(uuid, uuid, text)
  to service_role;
