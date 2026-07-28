-- Chrono Shards 8.5.10 — estabilidade do login e das missões
-- Execute uma única vez após 20260724000800_chrono_accounts_repair.sql.

-- Perfis antigos podem ter guardado um identificador de login diferente do
-- e-mail técnico realmente associado ao usuário no Supabase Auth. A Edge
-- Function também repara isso em tempo de execução; esta atualização antecipa
-- a correção para todas as contas válidas já existentes.
update public.chrono_profiles as profile
set auth_email = auth_user.email,
    updated_at = now()
from auth.users as auth_user
where auth_user.id = profile.user_id
  and auth_user.email is not null
  and btrim(auth_user.email) <> ''
  and profile.auth_email is distinct from auth_user.email;

-- Sessões muito antigas não devem continuar aparecendo como partidas ativas.
-- Isso evita que filas locais antigas tentem liquidar partidas abandonadas.
update public.chrono_game_sessions
set status = 'abandoned',
    ended_at = coalesce(ended_at, now()),
    summary = coalesce(summary, '{}'::jsonb) || jsonb_build_object(
      'abandonedReason', 'stale_session_cleanup_8_5_10'
    )
where status = 'active'
  and started_at < now() - interval '72 hours';

create index if not exists chrono_game_sessions_active_user_idx
  on public.chrono_game_sessions(user_id, started_at desc)
  where status = 'active';

create index if not exists chrono_profiles_username_lookup_idx
  on public.chrono_profiles(username_normalized, user_id);

-- Reforça que o cliente não pode escrever diretamente nas tabelas sensíveis.
alter table public.chrono_profiles enable row level security;
alter table public.chrono_recovery_attempts enable row level security;
alter table public.chrono_game_sessions enable row level security;
alter table public.chrono_player_state enable row level security;
alter table public.chrono_player_missions enable row level security;
alter table public.chrono_action_receipts enable row level security;
alter table public.chrono_redeemed_codes enable row level security;

revoke all on public.chrono_profiles from public, anon, authenticated;
revoke all on public.chrono_recovery_attempts from public, anon, authenticated;
revoke all on public.chrono_game_sessions from public, anon, authenticated;
revoke all on public.chrono_player_state from public, anon, authenticated;
revoke all on public.chrono_player_missions from public, anon, authenticated;
revoke all on public.chrono_action_receipts from public, anon, authenticated;
revoke all on public.chrono_redeemed_codes from public, anon, authenticated;

grant all on public.chrono_profiles to service_role;
grant all on public.chrono_recovery_attempts to service_role;
grant all on public.chrono_game_sessions to service_role;
grant all on public.chrono_player_state to service_role;
grant all on public.chrono_player_missions to service_role;
grant all on public.chrono_action_receipts to service_role;
grant all on public.chrono_redeemed_codes to service_role;
