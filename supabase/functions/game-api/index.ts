import { withSupabase } from 'npm:@supabase/server@^1'

type JsonObject = Record<string, unknown>

const SAVE_KEYS = new Set([
  'chrono_v4_meta',
  'chrono_v4_meta_class_unlocks_v3',
  'chrono_v4_meta_secret_rift_v1',
  'chrono_v4_meta_redeemed_codes_v1',
  'chrono_v4_meta_chrono_augments_620',
  'chrono_v4_meta_skins_clean_702',
  'chrono_v4_meta_power_catalog_unlocks_544',
  'chrono_v4_meta_mauro_shop_clean_702',
  'chrono_v4_meta_infernal_shop_830',
  'chrono_v4_meta_doom_mode_v1',
  'chrono_rift_tutorial_skip_v1',
  'chrono_doom_tutorial_skip_v1',
])

const MAX_SNAPSHOT_BYTES = 2_000_000

function asObject(value: unknown): JsonObject {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonObject
    : {}
}

function finiteInt(value: unknown, min: number, max: number): number {
  const n = Number(value)
  if (!Number.isFinite(n)) return min
  return Math.max(min, Math.min(max, Math.trunc(n)))
}

function cleanArray(value: unknown, maxLength = 500): unknown[] {
  return Array.isArray(value) ? value.slice(0, maxLength) : []
}

function sanitizeSnapshot(input: unknown): JsonObject {
  const source = asObject(input)
  const out: JsonObject = {}

  for (const [key, value] of Object.entries(source)) {
    if (SAVE_KEYS.has(key)) out[key] = value
  }

  const meta = asObject(out.chrono_v4_meta)
  meta.relicShards = finiteInt(meta.relicShards, 0, 1_000_000)
  meta.chronoFragments = finiteInt(meta.chronoFragments, 0, 100_000)
  meta.awakeningKeys = finiteInt(meta.awakeningKeys, 0, 10_000)
  meta.sinnerTears830 = finiteInt(
    meta.sinnerTears830 ?? meta.doomFragments,
    0,
    1_000_000,
  )
  meta.doomFragments = meta.sinnerTears830
  meta.highScore = finiteInt(meta.highScore, 0, 2_000_000_000)
  meta.unlockedRelics = cleanArray(meta.unlockedRelics, 500)
  out.chrono_v4_meta = meta

  out.chrono_v4_meta_class_unlocks_v3 = cleanArray(
    out.chrono_v4_meta_class_unlocks_v3,
    100,
  ).filter((item) => typeof item === 'string')

  const serialized = JSON.stringify(out)
  if (new TextEncoder().encode(serialized).byteLength > MAX_SNAPSHOT_BYTES) {
    throw new Error('Save local grande demais para migração')
  }

  return JSON.parse(serialized) as JsonObject
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status })
}

Deno.serve(
  withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return json({ error: 'Método inválido' }, 405)

    const claims = (ctx.userClaims ?? {}) as Record<string, unknown>
    const userId = String(claims.sub ?? claims.id ?? '')

    if (!userId) return json({ error: 'Usuário não identificado' }, 401)

    let body: JsonObject
    try {
      body = asObject(await req.json())
    } catch {
      return json({ error: 'JSON inválido' }, 400)
    }

    const action = String(body.action ?? '')
    const admin = ctx.supabaseAdmin

    try {
      if (action === 'health') {
        return json({ ok: true, service: 'chrono-shards-cloud' })
      }

      if (action === 'load_state') {
        const { error: ensureError } = await admin
          .from('chrono_player_state')
          .upsert({ user_id: userId }, { onConflict: 'user_id', ignoreDuplicates: true })

        if (ensureError) throw ensureError

        const { data, error } = await admin
          .from('chrono_player_state')
          .select('*')
          .eq('user_id', userId)
          .single()

        if (error) throw error
        return json({ state: data })
      }

      if (action === 'import_legacy') {
        const requestId = String(body.requestId ?? '')
        if (!requestId) return json({ error: 'requestId ausente' }, 400)

        const snapshot = sanitizeSnapshot(body.snapshot)
        const meta = asObject(snapshot.chrono_v4_meta)

        const { data: previous } = await admin
          .from('chrono_action_receipts')
          .select('response')
          .eq('user_id', userId)
          .eq('request_id', requestId)
          .maybeSingle()

        if (previous?.response) return json(previous.response)

        const { error: ensureError } = await admin
          .from('chrono_player_state')
          .upsert({ user_id: userId }, { onConflict: 'user_id', ignoreDuplicates: true })
        if (ensureError) throw ensureError

        const { data: current, error: currentError } = await admin
          .from('chrono_player_state')
          .select('*')
          .eq('user_id', userId)
          .single()
        if (currentError) throw currentError

        if (current.legacy_imported_at) {
          return json({ error: 'Este usuário já realizou a migração inicial' }, 409)
        }

        const update = {
          initialized: true,
          authority_mode: 'migration',
          legacy_imported_at: new Date().toISOString(),
          relic_shards: finiteInt(meta.relicShards, 0, 1_000_000),
          chrono_fragments: finiteInt(meta.chronoFragments, 0, 100_000),
          awakening_keys: finiteInt(meta.awakeningKeys, 0, 10_000),
          sinner_tears: finiteInt(meta.sinnerTears830 ?? meta.doomFragments, 0, 1_000_000),
          high_score: finiteInt(meta.highScore, 0, 2_000_000_000),
          save_data: snapshot,
          revision: Number(current.revision ?? 0) + 1,
        }

        const { data: state, error: updateError } = await admin
          .from('chrono_player_state')
          .update(update)
          .eq('user_id', userId)
          .is('legacy_imported_at', null)
          .select('*')
          .single()

        if (updateError) throw updateError

        const response = {
          imported: true,
          message: 'Save local registrado. O modo autoritativo permanece desligado até as ações permanentes serem migradas.',
          state,
        }

        const { error: receiptError } = await admin
          .from('chrono_action_receipts')
          .insert({
            user_id: userId,
            request_id: requestId,
            action: 'import_legacy',
            response,
          })
        if (receiptError) throw receiptError

        return json(response)
      }

      if (action === 'start_run') {
        const mode = String(body.mode ?? 'normal').slice(0, 40)
        const classKey = String(body.classKey ?? '').slice(0, 80)
        if (!classKey) return json({ error: 'Classe ausente' }, 400)

        const { error: abandonError } = await admin
          .from('chrono_game_sessions')
          .update({ status: 'abandoned', ended_at: new Date().toISOString() })
          .eq('user_id', userId)
          .eq('status', 'active')
        if (abandonError) throw abandonError

        const { data, error } = await admin
          .from('chrono_game_sessions')
          .insert({ user_id: userId, mode, class_key: classKey })
          .select('id, server_seed, started_at')
          .single()

        if (error) throw error
        return json({ session: data })
      }

      if (action === 'finish_run') {
        const requestId = String(body.requestId ?? '')
        const sessionId = String(body.sessionId ?? '')
        if (!requestId || !sessionId) {
          return json({ error: 'Identificadores ausentes' }, 400)
        }

        const { data, error } = await admin.rpc('chrono_finish_run_server', {
          p_user_id: userId,
          p_request_id: requestId,
          p_session_id: sessionId,
          p_score: finiteInt(body.score, 0, 2_000_000_000),
          p_wave: finiteInt(body.wave, 0, 1_000_000),
          p_kills: finiteInt(body.kills, 0, 10_000_000),
        })

        if (error) throw error
        return json(data)
      }

      return json({ error: 'Ação desconhecida' }, 400)
    } catch (error) {
      console.error('Chrono Cloud error', error)
      const message = error instanceof Error ? error.message : 'Erro interno'
      return json({ error: message }, 500)
    }
  }),
)
