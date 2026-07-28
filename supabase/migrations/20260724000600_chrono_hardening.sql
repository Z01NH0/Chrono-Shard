-- Chrono Shards 8.5.7 — endurecimento de sessões e índices.
-- Em bancos já configurados, execute este arquivo uma única vez.

-- Uma corrida antiga ou duas requisições simultâneas não devem deixar mais de
-- uma sessão ativa para a mesma conta. Mantém apenas a sessão ativa mais nova.
with ranked_active as (
  select id,
         row_number() over (
           partition by user_id
           order by started_at desc, id desc
         ) as position
  from public.chrono_game_sessions
  where status = 'active'
)
update public.chrono_game_sessions sessions
set status = 'abandoned',
    ended_at = coalesce(sessions.ended_at, now()),
    summary = coalesce(sessions.summary, '{}'::jsonb)
      || jsonb_build_object('closedBy', '8.5.7 session hardening')
from ranked_active ranked
where sessions.id = ranked.id
  and ranked.position > 1;

create unique index if not exists chrono_game_sessions_one_active_user_idx
  on public.chrono_game_sessions(user_id)
  where status = 'active';

create index if not exists chrono_game_sessions_user_started_idx
  on public.chrono_game_sessions(user_id, started_at desc);

create index if not exists chrono_action_receipts_created_idx
  on public.chrono_action_receipts(created_at desc);

create index if not exists chrono_redeemed_codes_redeemed_idx
  on public.chrono_redeemed_codes(redeemed_at desc);

-- Reafirma as proteções caso alguma tabela tenha sido recriada manualmente.
alter table public.chrono_player_state enable row level security;
alter table public.chrono_game_sessions enable row level security;
alter table public.chrono_action_receipts enable row level security;
alter table public.chrono_mission_catalog enable row level security;
alter table public.chrono_player_missions enable row level security;
alter table public.chrono_reward_codes enable row level security;
alter table public.chrono_redeemed_codes enable row level security;

revoke all on public.chrono_player_state from anon, authenticated;
revoke all on public.chrono_game_sessions from anon, authenticated;
revoke all on public.chrono_action_receipts from anon, authenticated;
revoke all on public.chrono_mission_catalog from anon, authenticated;
revoke all on public.chrono_player_missions from anon, authenticated;
revoke all on public.chrono_reward_codes from anon, authenticated;
revoke all on public.chrono_redeemed_codes from anon, authenticated;
