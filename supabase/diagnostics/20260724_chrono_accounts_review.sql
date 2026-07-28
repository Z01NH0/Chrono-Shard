-- Chrono Shards 8.5.8 — diagnóstico somente leitura

select
  count(*) as profiles,
  count(*) filter (where last_login_at > now() - interval '30 days') as profiles_active_30d
from public.chrono_profiles;

select username_normalized, count(*)
from public.chrono_profiles
group by username_normalized
having count(*) > 1;

select contact_email_normalized, count(*)
from public.chrono_profiles
group by contact_email_normalized
having count(*) > 1;

select p.user_id, p.username, u.is_anonymous, u.email
from public.chrono_profiles p
join auth.users u on u.id = p.user_id
where u.is_anonymous is true
   or u.email is null
   or u.email <> p.username_normalized || '@chrono-shards.invalid';

select s.user_id
from public.chrono_player_state s
join public.chrono_profiles p on p.user_id = s.user_id
where not s.initialized
   or not s.wallet_authority_enabled
   or not s.character_purchases_enabled
   or not s.run_results_enabled
   or not s.mission_rewards_enabled
   or not s.code_rewards_enabled;

select
  count(*) filter (where client_saved_at is not null) as automatic_saves,
  count(*) filter (where initialized and client_saved_at is null) as initialized_without_automatic_save,
  max(client_saved_at) as most_recent_automatic_save
from public.chrono_player_state;

select
  count(*) as recovery_attempt_rows,
  count(*) filter (where locked_until > now()) as temporarily_locked_actors
from public.chrono_recovery_attempts;
