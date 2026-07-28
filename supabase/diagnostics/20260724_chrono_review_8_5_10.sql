-- Chrono Shards 8.5.10 — auditoria somente leitura

-- 1. Perfis e identidade Auth. Esperado: auth_email_match = true e is_anonymous = false para contas permanentes.
select
  p.user_id,
  p.username,
  p.auth_email,
  u.email as auth_user_email,
  u.is_anonymous,
  (p.auth_email is not distinct from u.email) as auth_email_match,
  p.last_login_at
from public.chrono_profiles p
left join auth.users u on u.id = p.user_id
order by p.created_at desc;

-- 2. Sessões ativas antigas. Esperado: zero linhas com mais de 72 horas.
select id,user_id,mode,class_key,status,started_at
from public.chrono_game_sessions
where status = 'active'
  and started_at < now() - interval '72 hours'
order by started_at;

-- 3. Runs recentes rejeitadas e motivo de validação.
select id,user_id,class_key,status,started_at,ended_at,summary
from public.chrono_game_sessions
where status = 'rejected'
order by ended_at desc nulls last
limit 30;

-- 4. Estatísticas oficiais usadas pelas missões.
select
  user_id,
  revision,
  mission_stats ->> 'totalKills' as total_kills,
  mission_stats ->> 'bossKills' as boss_kills,
  mission_stats ->> 'eliteKills' as elite_kills,
  mission_stats ->> 'skillsUsed' as skills_used,
  mission_stats -> 'typeKills' as type_kills,
  mission_stats -> 'classKills' as class_kills,
  updated_at
from public.chrono_player_state
order by updated_at desc;

-- 5. Slots oficiais e estado de conclusão.
select user_id,slot_key,mission_id,difficulty,baseline,ready_at,claimed_at,updated_at
from public.chrono_player_missions
order by user_id,slot_key;

-- 6. Recibos duplicados. Esperado: zero linhas.
select user_id,request_id,count(*)
from public.chrono_action_receipts
group by user_id,request_id
having count(*) > 1;
