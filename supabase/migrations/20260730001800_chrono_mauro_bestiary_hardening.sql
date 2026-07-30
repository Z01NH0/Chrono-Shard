-- Chrono Shards 8.7.1 — endurecimento da Loja do Mauro e do Bestiário
-- Execute uma única vez após 20260729001700_chrono_mauro_bestiary_authority.sql.
-- Corrige a habilitação de contas criadas depois da migration 017 e normaliza
-- estados estruturais que poderiam deixar a loja oficial disponível apenas
-- para contas antigas.

begin;

-- A migration 017 habilitava apenas as contas já inicializadas naquele momento.
-- Com os defaults antigos em FALSE, uma conta criada depois do deploy recebia o
-- payload da loja, mas toda compra era recusada pelas RPCs autoritativas.
alter table public.chrono_player_state
  alter column mauro_authority_enabled set default true,
  alter column bestiary_authority_enabled set default true,
  alter column collection_authority_enabled_at set default now();

update public.chrono_player_state
set mauro_authority_enabled = true,
    bestiary_authority_enabled = true,
    collection_authority_enabled_at = coalesce(collection_authority_enabled_at, now()),
    revision = revision + case
      when not mauro_authority_enabled
        or not bestiary_authority_enabled
        or collection_authority_enabled_at is null
      then 1 else 0 end
where not mauro_authority_enabled
   or not bestiary_authority_enabled
   or collection_authority_enabled_at is null;

-- Remove duplicidades que possam ter vindo de snapshots antigos antes de
-- reforçar o uso do inventário oficial.
update public.chrono_player_inventory
set skins = (
      select coalesce(array_agg(distinct x order by x), '{}'::text[])
      from unnest(coalesce(skins, '{}'::text[])) x
      where x is not null and btrim(x) <> ''
    ),
    augments = (
      select coalesce(array_agg(distinct x order by x), '{}'::text[])
      from unnest(coalesce(augments, '{}'::text[])) x
      where x is not null and btrim(x) <> ''
    ),
    permanent_relics = (
      select coalesce(array_agg(distinct x order by x), '{}'::text[])
      from unnest(coalesce(permanent_relics, '{}'::text[])) x
      where x is not null and btrim(x) <> ''
    ),
    catalog_powerups = (
      select coalesce(array_agg(distinct x order by x), '{}'::text[])
      from unnest(coalesce(catalog_powerups, '{}'::text[])) x
      where x is not null and btrim(x) <> ''
    ),
    selected_skins = case
      when jsonb_typeof(selected_skins) = 'object' then selected_skins
      else '{}'::jsonb
    end,
    updated_at = now();

-- Uma rotação estruturalmente inválida é marcada para reconstrução segura na
-- próxima leitura. Não altera rotações válidas nem devolve itens já comprados.
update public.chrono_player_mauro
set rotation_epoch = -1,
    rotation_items = '[]'::jsonb,
    sold_slots = '{}'::jsonb,
    updated_at = now()
where case
  when jsonb_typeof(rotation_items) <> 'array' then true
  when jsonb_array_length(rotation_items) <> 8 then true
  when jsonb_typeof(sold_slots) <> 'object' then true
  else exists (
    select 1
    from jsonb_each(sold_slots) e
    where jsonb_typeof(e.value) <> 'boolean'
  )
end;

-- Garante que a seleção de skins permaneça um objeto JSON em novas escritas.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.chrono_player_inventory'::regclass
      and conname = 'chrono_player_inventory_selected_skins_object'
  ) then
    alter table public.chrono_player_inventory
      add constraint chrono_player_inventory_selected_skins_object
      check (jsonb_typeof(selected_skins) = 'object');
  end if;
end;
$$;

comment on column public.chrono_player_state.mauro_authority_enabled is
  'Autoridade permanente da Loja do Mauro. Novas contas recebem TRUE por padrão desde a 8.7.1.';
comment on column public.chrono_player_state.bestiary_authority_enabled is
  'Autoridade permanente do Bestiário. Novas contas recebem TRUE por padrão desde a 8.7.1.';

commit;
