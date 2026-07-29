-- Chrono Shards 8.6.2 — liberação segura das jornadas de Awakening
-- Execute uma única vez após:
--   20260729001500_chrono_sql_integrity_hardening.sql
--
-- Corrige o caso em que uma linha antiga de chrono_player_awakening_active
-- continua existindo mesmo depois de a etapa ter sido resgatada ou de a
-- Ultimate do personagem ter sido desbloqueada. Como a tabela possui uma linha
-- por usuário, esse estado fantasma bloqueia todas as outras jornadas.

begin;

-- Guarda os usuários reparados para atualizar revisão e snapshot oficial.
create temporary table chrono_released_awakening_862(
  user_id uuid primary key
) on commit drop;

insert into chrono_released_awakening_862(user_id)
select distinct a.user_id
from public.chrono_player_awakening_active a
join public.chrono_player_awakenings p
  on p.user_id = a.user_id
 and p.character_key = a.character_key
where p.ultimate_unlocked = true
   or p.completed_stages >= a.stage
on conflict(user_id) do nothing;

-- 1. Remove estados fantasmas já existentes.
-- Não devolvemos Chave nesses casos: a etapa já foi contabilizada ou a Ultimate
-- já foi liberada, portanto a chave foi consumida legitimamente.
delete from public.chrono_player_awakening_active a
using chrono_released_awakening_862 r
where a.user_id = r.user_id;

update public.chrono_player_state s
set revision = revision + 1
from chrono_released_awakening_862 r
where s.user_id = r.user_id;

-- 2. Mantém a regra permanentemente.
-- Sempre que uma etapa passa a constar como concluída ou a Ultimate é liberada,
-- qualquer linha ativa obsoleta desse mesmo personagem é removida na mesma
-- transação. Uma missão válida de outro personagem não é tocada.
create or replace function public.chrono_release_completed_awakening_active_server()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.chrono_player_awakening_active a
  where a.user_id = new.user_id
    and a.character_key = new.character_key
    and (
      new.ultimate_unlocked = true
      or new.completed_stages >= a.stage
    );

  return new;
end;
$$;

drop trigger if exists chrono_release_completed_awakening_active
  on public.chrono_player_awakenings;

create trigger chrono_release_completed_awakening_active
after insert or update
on public.chrono_player_awakenings
for each row
execute function public.chrono_release_completed_awakening_active_server();

-- 3. Reforça a função de resgate da Ultimate. Mesmo que uma conta antiga tenha
-- chegado a esse ponto com uma linha ativa do mesmo personagem, ela é limpa
-- antes de o payload autoritativo ser devolvido ao HTML.
create or replace function public.chrono_claim_awakening_ultimate_server(
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
  v_previous jsonb;
  v_player public.chrono_player_awakenings%rowtype;
  v_response jsonb;
  v_state public.chrono_player_state%rowtype;
  v_removed integer := 0;
begin
  select response into v_previous
  from public.chrono_action_receipts
  where user_id = p_user_id
    and request_id = p_request_id;

  if found then
    return v_previous;
  end if;

  if not public.chrono_awakening_character_owned_server(p_user_id, p_character_key) then
    raise exception 'Adquira este personagem antes de resgatar a Ultimate';
  end if;

  select * into v_player
  from public.chrono_player_awakenings
  where user_id = p_user_id
    and character_key = p_character_key
  for update;

  if not found or v_player.completed_stages < 5 then
    raise exception 'Complete as cinco etapas primeiro';
  end if;

  if v_player.ultimate_unlocked then
    -- Torna uma repetição segura e, ao mesmo tempo, repara uma linha fantasma.
    delete from public.chrono_player_awakening_active
    where user_id = p_user_id
      and character_key = p_character_key;
    get diagnostics v_removed = row_count;

    if v_removed > 0 then
      update public.chrono_player_state
      set revision = revision + 1
      where user_id = p_user_id
      returning * into v_state;
    else
      select * into v_state
      from public.chrono_player_state
      where user_id = p_user_id;
    end if;

    perform public.chrono_sync_progression_save_server(p_user_id);

    v_response := jsonb_build_object(
      'claimed', false,
      'alreadyClaimed', true,
      'characterKey', p_character_key,
      'progression', public.chrono_progression_payload_server(p_user_id),
      'state', to_jsonb(v_state)
    );

    insert into public.chrono_action_receipts(user_id, request_id, action, response)
    values(p_user_id, p_request_id, 'awakening_claim_ultimate', v_response);

    return v_response;
  end if;

  update public.chrono_player_awakenings
  set ultimate_unlocked = true,
      journey_unlocked = true,
      completed_stages = 5,
      updated_at = now()
  where user_id = p_user_id
    and character_key = p_character_key;

  -- Proteção explícita além do trigger. Não remove uma missão válida de outro
  -- personagem que tenha sido iniciada depois da quinta etapa.
  delete from public.chrono_player_awakening_active
  where user_id = p_user_id
    and character_key = p_character_key;

  update public.chrono_player_state
  set revision = revision + 1
  where user_id = p_user_id
  returning * into v_state;

  perform public.chrono_sync_progression_save_server(p_user_id);

  v_response := jsonb_build_object(
    'claimed', true,
    'characterKey', p_character_key,
    'progression', public.chrono_progression_payload_server(p_user_id),
    'state', to_jsonb(v_state)
  );

  insert into public.chrono_action_receipts(user_id, request_id, action, response)
  values(p_user_id, p_request_id, 'awakening_claim_ultimate', v_response);

  return v_response;
end;
$$;

-- Regrava o snapshot oficial das contas corrigidas nesta migration.
do $$
declare
  r record;
begin
  for r in select user_id from chrono_released_awakening_862
  loop
    perform public.chrono_sync_progression_save_server(r.user_id);
  end loop;
end;
$$;

revoke all on function public.chrono_release_completed_awakening_active_server()
  from public, anon, authenticated;
grant execute on function public.chrono_release_completed_awakening_active_server()
  to service_role;

revoke all on function public.chrono_claim_awakening_ultimate_server(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.chrono_claim_awakening_ultimate_server(uuid, uuid, text)
  to service_role;

comment on function public.chrono_release_completed_awakening_active_server() is
  'Remove estados ativos obsoletos quando a etapa já foi concluída ou a Ultimate foi liberada.';

commit;
