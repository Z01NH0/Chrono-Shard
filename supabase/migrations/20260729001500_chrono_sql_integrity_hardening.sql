-- Chrono Shards 8.6.1 — correções de integridade SQL
-- Execute uma única vez após 20260728001400_chrono_awakening_hydration_hardening.sql.
--
-- Corrige:
-- 1. progresso de objetivos maxWave acima da meta, que podia violar
--    chrono_player_awakening_active_progress_target_check;
-- 2. estados antigos já acima da meta;
-- 3. overloads obsoletos de chrono_finish_run_server que não são mais usados
--    pela Edge Function atual.

begin;

-- Repara qualquer estado antigo antes de instalar a proteção permanente.
update public.chrono_player_awakening_active
set progress = least(greatest(progress, 0), target),
    updated_at = now()
where progress < 0
   or progress > target;

-- Toda gravação futura fica limitada a [0, target]. Isso cobre maxWave e também
-- protege importações, reparos e alterações futuras contra valores fora da meta.
create or replace function public.chrono_clamp_awakening_progress_server()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.target is null or new.target <= 0 then
    raise exception 'Meta de Awakening inválida';
  end if;

  new.progress := least(greatest(coalesce(new.progress, 0), 0), new.target);
  return new;
end;
$$;

drop trigger if exists chrono_clamp_awakening_progress
  on public.chrono_player_awakening_active;

create trigger chrono_clamp_awakening_progress
before insert or update of progress, target
on public.chrono_player_awakening_active
for each row
execute function public.chrono_clamp_awakening_progress_server();

-- As versões de 6 e 9 argumentos ficaram no histórico como overloads antigos.
-- A Edge Function atual usa somente a assinatura autoritativa de 13 argumentos.
drop function if exists public.chrono_finish_run_server(
  uuid, uuid, uuid, bigint, integer, integer
);

drop function if exists public.chrono_finish_run_server(
  uuid, uuid, uuid, bigint, integer, integer, bigint, integer, integer
);

revoke all on function public.chrono_clamp_awakening_progress_server()
  from public, anon, authenticated;
grant execute on function public.chrono_clamp_awakening_progress_server()
  to service_role;

comment on function public.chrono_clamp_awakening_progress_server() is
  'Limita o progresso de Awakening ao intervalo de zero até a meta, evitando falhas em objetivos maxWave.';

commit;
