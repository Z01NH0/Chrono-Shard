-- Chrono Shards 8.5.8 — contas, nomes de usuário e recuperação sem SMTP
-- Execute este arquivo uma única vez no SQL Editor do Supabase.

create extension if not exists pgcrypto;


-- Snapshot automático dos sistemas que ainda não foram totalmente migrados.
-- Ele fica separado do save autoritativo para nunca sobrescrever compras,
-- moedas e recompensas validadas pelo servidor.
alter table public.chrono_player_state
  add column if not exists client_save_data jsonb not null default '{}'::jsonb,
  add column if not exists client_save_hash text,
  add column if not exists client_saved_at timestamptz;

update public.chrono_player_state
set client_save_data = save_data,
    client_saved_at = coalesce(client_saved_at, updated_at, now())
where initialized = true
  and client_save_data = '{}'::jsonb
  and save_data <> '{}'::jsonb;

create index if not exists chrono_player_state_client_saved_idx
  on public.chrono_player_state(client_saved_at desc nulls last);

create table if not exists public.chrono_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  username_normalized text not null,
  contact_email text not null,
  contact_email_normalized text not null,
  recovery_key_hash text not null,
  last_recovered_at timestamptz,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chrono_profiles_username_length
    check (char_length(username_normalized) between 3 and 20),
  constraint chrono_profiles_username_format
    check (username_normalized ~ '^[a-z0-9_]+$'),
  constraint chrono_profiles_username_normalized_lower
    check (username_normalized = lower(username_normalized)),
  constraint chrono_profiles_contact_email_length
    check (char_length(contact_email_normalized) between 3 and 254),
  constraint chrono_profiles_contact_email_normalized_lower
    check (contact_email_normalized = lower(contact_email_normalized)),
  constraint chrono_profiles_recovery_hash_length
    check (recovery_key_hash ~ '^[0-9a-f]{64}$')
);


create table if not exists public.chrono_recovery_attempts (
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  username_normalized text not null
    check (username_normalized ~ '^[a-z0-9_]{3,20}$'),
  failed_attempts integer not null default 0
    check (failed_attempts >= 0 and failed_attempts <= 20),
  locked_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (actor_user_id, username_normalized)
);

create index if not exists chrono_recovery_attempts_locked_idx
  on public.chrono_recovery_attempts(locked_until)
  where locked_until is not null;

alter table public.chrono_recovery_attempts enable row level security;
revoke all on public.chrono_recovery_attempts from anon, authenticated;
grant all on public.chrono_recovery_attempts to service_role;

create unique index if not exists chrono_profiles_username_unique_idx
  on public.chrono_profiles(username_normalized);

create unique index if not exists chrono_profiles_contact_email_unique_idx
  on public.chrono_profiles(contact_email_normalized);

create index if not exists chrono_profiles_last_login_idx
  on public.chrono_profiles(last_login_at desc nulls last);

alter table public.chrono_profiles enable row level security;
revoke all on public.chrono_profiles from anon, authenticated;
grant all on public.chrono_profiles to service_role;

create or replace function public.chrono_profiles_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists chrono_profiles_touch on public.chrono_profiles;
create trigger chrono_profiles_touch
before update on public.chrono_profiles
for each row execute function public.chrono_profiles_touch_updated_at();

revoke all on function public.chrono_profiles_touch_updated_at()
  from public, anon, authenticated;
grant execute on function public.chrono_profiles_touch_updated_at()
  to service_role;

-- Novas contas passam a usar automaticamente as proteções já instaladas.
-- A atualização só liga recursos que já existem nas migrations anteriores.
update public.chrono_player_state
set wallet_authority_enabled = true,
    character_purchases_enabled = true,
    run_results_enabled = true,
    mission_rewards_enabled = true,
    code_rewards_enabled = true,
    wallet_authority_enabled_at = coalesce(wallet_authority_enabled_at, now())
where initialized = true
  and (
    not wallet_authority_enabled
    or not character_purchases_enabled
    or not run_results_enabled
    or not mission_rewards_enabled
    or not code_rewards_enabled
  );
