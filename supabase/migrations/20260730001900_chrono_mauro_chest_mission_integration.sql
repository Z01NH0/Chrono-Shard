-- Chrono Shards 8.7.2 — correção do baú do Mauro e isolamento Missões/Bestiário
-- Execute UMA VEZ após 20260730001800_chrono_mauro_bestiary_hardening.sql.

begin;

-- No Supabase, pgcrypto normalmente fica no schema extensions. A função da
-- migration 017 usa gen_random_bytes() sem qualificação e possui search_path
-- vazio, por isso a compra do baú falha mesmo com pgcrypto instalado.
create extension if not exists pgcrypto;

do $$
declare
  v_pgcrypto_schema text;
begin
  select n.nspname
  into v_pgcrypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_pgcrypto_schema is null then
    raise exception 'A extensão pgcrypto não pôde ser localizada';
  end if;

  execute format(
    'alter function public.chrono_mauro_purchase_server(uuid,uuid,text,text,integer,text) set search_path = pg_catalog, %I',
    v_pgcrypto_schema
  );
end;
$$;

-- Checkpoints de Missões, Awakening/DOOM e Bestiário precisam confirmar juntos.
-- Antes desta migration, o checkpoint de Missões podia ser salvo e a chamada do
-- Bestiário falhar depois. O navegador recebia erro e não hidratava a interface,
-- deixando as Missões com aparência atrasada apesar de o banco já ter avançado.
create or replace function public.chrono_checkpoint_run_bundle_server(
  p_user_id uuid,
  p_session_id uuid,
  p_score bigint,
  p_wave integer,
  p_kills integer,
  p_boss_kills integer,
  p_elite_kills integer,
  p_skills_used integer,
  p_mission_type_kills jsonb,
  p_bestiary_type_kills jsonb,
  p_special_metrics jsonb,
  p_doom_summary jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_checkpoint_result jsonb;
  v_checkpoint jsonb;
  v_progression jsonb;
  v_bestiary jsonb;
  v_score bigint;
  v_wave integer;
  v_kills integer;
  v_boss_kills integer;
  v_elite_kills integer;
  v_skills_used integer;
begin
  v_checkpoint_result := public.chrono_checkpoint_run_server(
    p_user_id,
    p_session_id,
    p_score,
    p_wave,
    p_kills,
    p_boss_kills,
    p_elite_kills,
    p_skills_used,
    coalesce(p_mission_type_kills, '{}'::jsonb)
  );

  if not coalesce((v_checkpoint_result ->> 'accepted')::boolean, false) then
    return v_checkpoint_result;
  end if;

  v_checkpoint := coalesce(v_checkpoint_result -> 'checkpoint', '{}'::jsonb);
  v_score := greatest(0, public.chrono_jsonb_bigint(v_checkpoint, array['score']));
  v_wave := greatest(0, public.chrono_jsonb_bigint(v_checkpoint, array['wave']))::integer;
  v_kills := greatest(0, public.chrono_jsonb_bigint(v_checkpoint, array['kills']))::integer;
  v_boss_kills := least(v_kills, greatest(0, public.chrono_jsonb_bigint(v_checkpoint, array['bossKills'])))::integer;
  v_elite_kills := least(v_kills, greatest(0, public.chrono_jsonb_bigint(v_checkpoint, array['eliteKills'])))::integer;
  v_skills_used := greatest(0, public.chrono_jsonb_bigint(v_checkpoint, array['skillsUsed']))::integer;

  v_progression := public.chrono_apply_progression_run_server(
    p_user_id,
    p_session_id,
    v_score,
    v_wave,
    v_kills,
    v_boss_kills,
    v_elite_kills,
    v_skills_used,
    coalesce(v_checkpoint -> 'typeKills', '{}'::jsonb),
    coalesce(p_special_metrics, '{}'::jsonb),
    coalesce(p_doom_summary, '{}'::jsonb),
    false
  );

  v_bestiary := public.chrono_apply_bestiary_run_server(
    p_user_id,
    p_session_id,
    v_kills,
    coalesce(p_bestiary_type_kills, '{}'::jsonb),
    false
  );

  return v_checkpoint_result || jsonb_build_object(
    'progression', coalesce(v_progression -> 'progression', v_progression),
    'bestiary', v_bestiary,
    'bundleAtomic', true
  );
end;
$$;

revoke all on function public.chrono_checkpoint_run_bundle_server(
  uuid,uuid,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,jsonb
) from public, anon, authenticated;
grant execute on function public.chrono_checkpoint_run_bundle_server(
  uuid,uuid,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,jsonb
) to service_role;

comment on function public.chrono_checkpoint_run_bundle_server(
  uuid,uuid,bigint,integer,integer,integer,integer,integer,jsonb,jsonb,jsonb,jsonb
) is 'Checkpoint atômico de Missões, Awakening/DOOM e Bestiário — Chrono Shards 8.7.2';

commit;
