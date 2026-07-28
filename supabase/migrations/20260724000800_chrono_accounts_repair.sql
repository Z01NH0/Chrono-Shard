-- Chrono Shards 8.5.9 — correção de identidade, transferência de convidado e login
-- Execute uma única vez após 20260724000700_chrono_accounts.sql.

alter table public.chrono_profiles
  add column if not exists auth_email text;

-- Perfis criados pela 8.5.8 usavam este identificador interno previsível.
update public.chrono_profiles
set auth_email = username_normalized || '@chrono-shards.invalid'
where auth_email is null or btrim(auth_email) = '';

create unique index if not exists chrono_profiles_auth_email_unique_idx
  on public.chrono_profiles(lower(auth_email))
  where auth_email is not null;

alter table public.chrono_profiles
  drop constraint if exists chrono_profiles_auth_email_length;

alter table public.chrono_profiles
  add constraint chrono_profiles_auth_email_length
  check (auth_email is null or char_length(auth_email) between 6 and 254);

-- Move todo o progresso público de uma sessão anônima para um usuário Auth
-- permanente recém-criado. A função é transacional: ou todos os dados mudam,
-- ou nada muda.
create or replace function public.chrono_transfer_account_server(
  p_from_user_id uuid,
  p_to_user_id uuid,
  p_username text,
  p_username_normalized text,
  p_contact_email text,
  p_contact_email_normalized text,
  p_auth_email text,
  p_recovery_key_hash text
)
returns public.chrono_player_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.chrono_player_state%rowtype;
  v_old_profile public.chrono_profiles%rowtype;
  v_created_at timestamptz := now();
begin
  if p_from_user_id is null or p_to_user_id is null or p_from_user_id = p_to_user_id then
    raise exception 'Transferência de conta inválida';
  end if;

  if not exists(select 1 from auth.users where id = p_from_user_id) then
    raise exception 'Conta de origem não encontrada';
  end if;

  if not exists(select 1 from auth.users where id = p_to_user_id) then
    raise exception 'Conta de destino não encontrada';
  end if;

  if exists(select 1 from public.chrono_player_state where user_id = p_to_user_id)
     or exists(select 1 from public.chrono_profiles where user_id = p_to_user_id) then
    raise exception 'A conta de destino já possui progresso';
  end if;

  select * into v_old_profile
  from public.chrono_profiles
  where user_id = p_from_user_id
  for update;

  if found then
    v_created_at := v_old_profile.created_at;
  end if;

  -- Remove o perfil antigo antes de inserir o novo para liberar os índices
  -- únicos de nome e e-mail dentro da mesma transação.
  delete from public.chrono_profiles where user_id = p_from_user_id;

  update public.chrono_player_state
  set user_id = p_to_user_id
  where user_id = p_from_user_id;

  update public.chrono_game_sessions
  set user_id = p_to_user_id
  where user_id = p_from_user_id;

  update public.chrono_action_receipts
  set user_id = p_to_user_id
  where user_id = p_from_user_id;

  update public.chrono_player_missions
  set user_id = p_to_user_id
  where user_id = p_from_user_id;

  update public.chrono_redeemed_codes
  set user_id = p_to_user_id
  where user_id = p_from_user_id;

  -- Tentativas de recuperação pertencem ao dispositivo/ator antigo e não ao
  -- save. Elas não devem acompanhar a conta permanente.
  delete from public.chrono_recovery_attempts
  where actor_user_id = p_from_user_id;

  insert into public.chrono_profiles(
    user_id,
    username,
    username_normalized,
    contact_email,
    contact_email_normalized,
    auth_email,
    recovery_key_hash,
    last_recovered_at,
    last_login_at,
    created_at,
    updated_at
  ) values (
    p_to_user_id,
    p_username,
    p_username_normalized,
    p_contact_email,
    p_contact_email_normalized,
    p_auth_email,
    p_recovery_key_hash,
    v_old_profile.last_recovered_at,
    now(),
    v_created_at,
    now()
  );

  select * into v_state
  from public.chrono_player_state
  where user_id = p_to_user_id;

  if not found then
    raise exception 'O progresso da conta não foi encontrado após a transferência';
  end if;

  return v_state;
end;
$$;

revoke all on function public.chrono_transfer_account_server(
  uuid, uuid, text, text, text, text, text, text
) from public, anon, authenticated;

grant execute on function public.chrono_transfer_account_server(
  uuid, uuid, text, text, text, text, text, text
) to service_role;

-- Reforça o isolamento das tabelas de conta.
alter table public.chrono_profiles enable row level security;
revoke all on public.chrono_profiles from public, anon, authenticated;
grant all on public.chrono_profiles to service_role;
