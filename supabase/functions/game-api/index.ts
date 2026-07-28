import { withSupabase } from 'npm:@supabase/server@^1'

type JsonObject = Record<string, unknown>
type AdminClient = any

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
  'chrono_tutorial_modules_851',
  'chrono_rift_tutorial_skip_v1',
  'chrono_doom_tutorial_skip_v1',
])

const PROTECTED_CHARACTER_KEYS = new Set([
  'assault',
  'sniper',
  'engineer',
  'mage',
  'ronin',
  'alchemist',
  'reaper',
  'colonel',
  'chronoHero',
  'shadowChild',
  'moonSlayer',
  'bomber',
  'archer',
  'ricocheteador',
  'stellarEmperor',
])

const ALLOWED_CHARACTER_KEYS = new Set([
  ...PROTECTED_CHARACTER_KEYS,
  'nefalem',
])

const ALLOWED_RUN_MODES = new Set([
  'normal',
  'rift',
  'doom',
  'dunes',
  'tutorial',
])

const FREE_CHARACTER_KEYS = new Set(['assault', 'sniper'])
const RESERVED_USERNAMES = new Set([
  'admin', 'administrator', 'moderador', 'moderator', 'suporte', 'support',
  'chrono', 'chronoshards', 'chrono_shards', 'system', 'sistema', 'null',
  'undefined', 'root', 'staff', 'dev', 'developer', 'oficial', 'official',
])
const INTERNAL_EMAIL_DOMAIN = 'chrono-shards.invalid'
const INITIAL_PROTECTED_META_KEYS = [
  'allUnlocked', 'allInUnlocked', 'nefalemPurchased830',
  'riftModeUnlocked525', 'riftModeUnlocked', 'doomModeUnlocked810', 'doomModeUnlocked',
  'unlockedMoonSlayer', 'moonMissionClaimed', 'unlockedShadowChild', 'shadowChildUnlocked',
  'stellarEmperorRevealed', 'stellarEmperorSecretUnlocked',
]
const MAX_SNAPSHOT_BYTES = 512_000
const ALLOWED_TYPE_KILL_KEYS = [
  'chaser',
  'swarmer',
  'strafer',
  'tank',
  'bomber',
  'sentinel',
  'vomiter',
  'pukeling',
] as const
const ALLOWED_TYPE_KILLS = new Set<string>(ALLOWED_TYPE_KILL_KEYS)

const SOFT_ERROR_ACTIONS = new Set([
  'login_account',
  'register_account',
  'repair_account',
  'recover_account',
  'change_password',
  'rotate_recovery',
])


class PublicError extends Error {
  status: number
  code: string
  field?: string

  constructor(message: string, status = 400, code = 'REQUEST_ERROR', field?: string) {
    super(message)
    this.name = 'PublicError'
    this.status = status
    this.code = code
    this.field = field
  }
}

function publicError(message: string, status = 400, code = 'REQUEST_ERROR', field?: string): never {
  throw new PublicError(message, status, code, field)
}

function hasEmailIdentity(user: any): boolean {
  return Array.isArray(user?.identities) && user.identities.some((identity: any) =>
    identity?.provider === 'email',
  )
}

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

function sanitizeTypeKills(value: unknown, totalKills: number): Record<string, number> {
  const source = asObject(value)
  const out: Record<string, number> = {}
  let remaining = Math.max(0, totalKills)

  // Alguns patches antigos do cliente incrementavam o mesmo abate mais de uma vez.
  // O servidor aplica um orçamento global para que a soma por tipo nunca ultrapasse
  // o total real informado para a partida.
  for (const key of ALLOWED_TYPE_KILL_KEYS) {
    if (remaining <= 0) break
    const amount = Math.min(finiteInt(source[key], 0, totalKills), remaining)
    if (amount > 0) {
      out[key] = amount
      remaining -= amount
    }
  }

  return out
}

function normalizeRewardCode(value: unknown): string {
  return String(value ?? '').normalize('NFKC').trim().toLowerCase()
}

function normalizeUsername(value: unknown): string {
  return String(value ?? '').normalize('NFKC').trim().toLowerCase()
}

function normalizeContactEmail(value: unknown): string {
  return String(value ?? '').normalize('NFKC').trim().toLowerCase()
}

function normalizeRecoveryKey(value: unknown): string {
  return String(value ?? '').normalize('NFKC').toUpperCase().replace(/[^A-Z0-9]/g, '')
}

async function generatedAuthEmail(usernameNormalized: string, userId: string): Promise<string> {
  const digest = await sha256Hex(`chrono-auth-v2|${usernameNormalized}|${userId}`)
  return `u-${digest.slice(0, 40)}@${INTERNAL_EMAIL_DOMAIN}`
}

function validateUsername(username: string): void {
  if (!/^[a-z0-9_]{3,20}$/.test(username)) {
    publicError('Use de 3 a 20 caracteres: letras, números e _', 400, 'INVALID_USERNAME', 'username')
  }
  if (RESERVED_USERNAMES.has(username)) publicError('Este nome de usuário é reservado', 400, 'RESERVED_USERNAME', 'username')
}

function validateContactEmail(email: string): void {
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    publicError('Informe um e-mail válido', 400, 'INVALID_EMAIL', 'email')
  }
  if (email.endsWith(`@${INTERNAL_EMAIL_DOMAIN}`)) publicError('E-mail inválido', 400, 'INVALID_EMAIL', 'email')
}

function validatePassword(passwordValue: unknown): string {
  const password = String(passwordValue ?? '')
  if (password.length < 8 || password.length > 72) {
    publicError('A senha deve ter de 8 a 72 caracteres', 400, 'INVALID_PASSWORD', 'password')
  }
  if (!/\p{L}/u.test(password) || !/\p{N}/u.test(password)) {
    publicError('A senha precisa ter pelo menos uma letra e um número', 400, 'INVALID_PASSWORD', 'password')
  }
  if (/\p{C}/u.test(password)) publicError('A senha contém caracteres inválidos', 400, 'INVALID_PASSWORD', 'password')
  return password
}

function validateRecoveryKey(value: unknown): string {
  const key = normalizeRecoveryKey(value)
  if (key.length < 20 || key.length > 64) publicError('Chave de recuperação inválida', 400, 'INVALID_RECOVERY_KEY', 'recoveryKey')
  return key
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function recoveryHash(usernameNormalized: string, recoveryKey: string): Promise<string> {
  return sha256Hex(`chrono-recovery-v1|${usernameNormalized}|${recoveryKey}`)
}

async function passwordSession(
  req: Request,
  authEmail: string,
  password: string,
): Promise<Record<string, unknown> | null> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const apiKey = req.headers.get('apikey') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  if (!supabaseUrl || !apiKey) throw new Error('Configuração de autenticação indisponível')

  const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: {
      apikey: apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email: authEmail, password }),
  })

  let payload: Record<string, unknown> = {}
  try {
    payload = asObject(await response.json())
  } catch {
    payload = {}
  }
  if (!response.ok || typeof payload.access_token !== 'string' || typeof payload.refresh_token !== 'string') {
    return null
  }

  return {
    access_token: payload.access_token,
    refresh_token: payload.refresh_token,
    expires_in: payload.expires_in,
    expires_at: payload.expires_at,
    token_type: payload.token_type,
    user: payload.user,
  }
}

async function deleteTemporaryAnonymousActor(
  admin: AdminClient,
  actorUserId: string,
  targetUserId: string,
): Promise<void> {
  if (!actorUserId || actorUserId === targetUserId) return
  try {
    const { data, error } = await admin.auth.admin.getUserById(actorUserId)
    if (error) {
      console.warn('Não foi possível consultar sessão temporária', error)
      return
    }
    if (data?.user?.is_anonymous !== true) return
    const { error: deleteError } = await admin.auth.admin.deleteUser(actorUserId)
    if (deleteError) console.warn('Não foi possível remover sessão anônima temporária', deleteError)
  } catch (error) {
    console.warn('Falha ao limpar sessão anônima temporária', error)
  }
}

async function upgradeUserInPlace(
  admin: AdminClient,
  userId: string,
  profile: {
    username: string
    usernameNormalized: string
    contactEmail: string
    contactEmailNormalized: string
  },
  password: string,
  recoveryKey: string,
  createProfile: boolean,
): Promise<{ userId: string; authEmail: string; state: Record<string, unknown> }> {
  const authEmail = await generatedAuthEmail(profile.usernameNormalized, userId)
  const keyHash = await recoveryHash(profile.usernameNormalized, recoveryKey)
  let insertedProfile = false

  if (createProfile) {
    const { error: insertError } = await admin
      .from('chrono_profiles')
      .insert({
        user_id: userId,
        username: profile.username,
        username_normalized: profile.usernameNormalized,
        contact_email: profile.contactEmail,
        contact_email_normalized: profile.contactEmailNormalized,
        auth_email: authEmail,
        recovery_key_hash: keyHash,
        last_login_at: new Date().toISOString(),
      })
    if (insertError) {
      const message = String(insertError.message ?? '')
      if (message.includes('chrono_profiles_username') || message.includes('username_normalized')) {
        publicError('Este nome de usuário já está em uso', 409, 'USERNAME_TAKEN', 'username')
      }
      if (message.includes('chrono_profiles_contact_email') || message.includes('contact_email_normalized')) {
        publicError('Este e-mail já está registrado', 409, 'EMAIL_TAKEN', 'email')
      }
      throw insertError
    }
    insertedProfile = true
  }

  const { data: updatedAuth, error: authError } = await admin.auth.admin.updateUserById(userId, {
    email: authEmail,
    password,
    email_confirm: true,
    user_metadata: { username: profile.username },
  })

  if (authError || !updatedAuth?.user) {
    if (insertedProfile) {
      try {
        await admin.from('chrono_profiles').delete().eq('user_id', userId)
      } catch {
        // A limpeza é apenas compensatória; o erro original continua sendo o relevante.
      }
    }
    throw authError ?? new Error('Não foi possível transformar a sessão em conta permanente')
  }

  const finalAuthEmail = String(updatedAuth.user.email ?? authEmail)
  const { error: profileUpdateError } = await admin
    .from('chrono_profiles')
    .update({
      auth_email: finalAuthEmail,
      recovery_key_hash: keyHash,
      last_login_at: new Date().toISOString(),
    })
    .eq('user_id', userId)
  if (profileUpdateError) throw profileUpdateError

  const { data: state, error: stateError } = await admin
    .from('chrono_player_state')
    .select('*')
    .eq('user_id', userId)
    .single()
  if (stateError) throw stateError

  return { userId, authEmail: finalAuthEmail, state: state as Record<string, unknown> }
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

function sanitizeFreshAccountSnapshot(input: unknown): JsonObject {
  const snapshot = sanitizeSnapshot(input)
  const meta = asObject(snapshot.chrono_v4_meta)
  meta.relicShards = 0
  meta.chronoFragments = 0
  meta.awakeningKeys = 0
  meta.sinnerTears830 = 0
  meta.doomFragments = 0
  meta.highScore = 0
  meta.missionReputation489 = 0
  for (const key of INITIAL_PROTECTED_META_KEYS) delete meta[key]
  snapshot.chrono_v4_meta = meta
  snapshot.chrono_v4_meta_class_unlocks_v3 = cleanArray(
    snapshot.chrono_v4_meta_class_unlocks_v3,
    100,
  ).filter((item) => typeof item === 'string' && FREE_CHARACTER_KEYS.has(item))
  snapshot.chrono_v4_meta_redeemed_codes_v1 = []
  snapshot.chrono_v4_meta_secret_rift_v1 = {}
  return snapshot
}

function stateOwnsCharacter(stateValue: unknown, classKey: string): boolean {
  if (FREE_CHARACTER_KEYS.has(classKey)) return true

  const state = asObject(stateValue)
  const save = asObject(state.save_data)
  const meta = asObject(save.chrono_v4_meta)
  const unlocks = cleanArray(save.chrono_v4_meta_class_unlocks_v3, 200)
    .filter((item): item is string => typeof item === 'string')

  if (meta.allUnlocked === true || meta.allInUnlocked === true) return true
  if (unlocks.includes(classKey)) return true
  if (classKey === 'moonSlayer' && meta.unlockedMoonSlayer === true) return true
  if (classKey === 'shadowChild' && (meta.unlockedShadowChild === true || meta.shadowChildUnlocked === true)) return true
  if (classKey === 'nefalem' && meta.nefalemPurchased830 === true) return true
  return false
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status })
}

async function bootstrapPlayerState(
  admin: AdminClient,
  userId: string,
  inputSnapshot: unknown,
): Promise<Record<string, unknown>> {
  const snapshot = sanitizeSnapshot(
    Object.keys(asObject(inputSnapshot)).length
      ? inputSnapshot
      : { chrono_v4_meta: {} },
  )
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

  const needsInitialization = current.initialized !== true || !current.legacy_imported_at
  const needsProtection = !current.wallet_authority_enabled || !current.character_purchases_enabled ||
    !current.run_results_enabled || !current.mission_rewards_enabled || !current.code_rewards_enabled

  if (!needsInitialization && !needsProtection) return current as Record<string, unknown>

  const update: Record<string, unknown> = {
    wallet_authority_enabled: true,
    character_purchases_enabled: true,
    run_results_enabled: true,
    mission_rewards_enabled: true,
    code_rewards_enabled: true,
    wallet_authority_enabled_at: current.wallet_authority_enabled_at ?? new Date().toISOString(),
    revision: Number(current.revision ?? 0) + 1,
  }

  if (needsInitialization) {
    // Contas novas nunca importam moedas/desbloqueios arbitrários do navegador.
    // O snapshot local serve só como compatibilidade para sistemas ainda locais.
    const initialSnapshot = sanitizeFreshAccountSnapshot(snapshot)
    const initialMeta = asObject(initialSnapshot.chrono_v4_meta)
    update.initialized = true
    update.authority_mode = 'migration'
    update.legacy_imported_at = new Date().toISOString()
    update.relic_shards = finiteInt(initialMeta.relicShards, 0, 1_000_000)
    update.chrono_fragments = finiteInt(initialMeta.chronoFragments, 0, 100_000)
    update.awakening_keys = finiteInt(initialMeta.awakeningKeys, 0, 10_000)
    update.sinner_tears = finiteInt(initialMeta.sinnerTears830 ?? initialMeta.doomFragments, 0, 1_000_000)
    update.high_score = finiteInt(initialMeta.highScore, 0, 2_000_000_000)
    update.save_data = initialSnapshot
    update.client_save_data = initialSnapshot
    update.client_save_hash = await sha256Hex(JSON.stringify(initialSnapshot))
    update.client_saved_at = new Date().toISOString()
  }

  const { data: state, error: updateError } = await admin
    .from('chrono_player_state')
    .update(update)
    .eq('user_id', userId)
    .select('*')
    .single()
  if (updateError) throw updateError
  return state as Record<string, unknown>
}


export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
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
        return json({
          ok: true,
          service: 'chrono-shards-cloud',
          phase: 'accounts-missions-8.5.10',
        })
      }

      if (action === 'load_account') {
        const { data: profile, error: profileError } = await admin
          .from('chrono_profiles')
          .select('user_id, username, contact_email, auth_email, created_at, last_login_at')
          .eq('user_id', userId)
          .maybeSingle()
        if (profileError) throw profileError

        const { data: authRecord, error: authRecordError } = await admin.auth.admin.getUserById(userId)
        if (authRecordError) throw authRecordError
        const authUser = authRecord?.user
        const needsRepair = !!profile && (!hasEmailIdentity(authUser) || authUser?.is_anonymous === true)

        if (profile && !needsRepair) {
          const { error: touchError } = await admin
            .from('chrono_profiles')
            .update({ last_login_at: new Date().toISOString() })
            .eq('user_id', userId)
          if (touchError) console.warn('Não foi possível atualizar last_login_at', touchError)
        }

        return json({
          account: {
            anonymous: !profile,
            needsRepair,
            profile: profile ?? null,
          },
        })
      }

      if (action === 'bootstrap_account') {
        const state = await bootstrapPlayerState(admin, userId, body.snapshot)
        return json({ initialized: true, state })
      }

      if (action === 'sync_snapshot') {
        const snapshot = sanitizeSnapshot(body.snapshot)
        const snapshotHash = await sha256Hex(JSON.stringify(snapshot))

        const { data: current, error: currentError } = await admin
          .from('chrono_player_state')
          .select('initialized, client_save_hash')
          .eq('user_id', userId)
          .maybeSingle()
        if (currentError) throw currentError

        if (!current?.initialized) {
          const state = await bootstrapPlayerState(admin, userId, snapshot)
          return json({ saved: true, unchanged: false, clientSavedAt: state.client_saved_at ?? null })
        }

        if (current.client_save_hash === snapshotHash) {
          return json({ saved: true, unchanged: true })
        }

        const savedAt = new Date().toISOString()
        const { error: saveError } = await admin
          .from('chrono_player_state')
          .update({
            client_save_data: snapshot,
            client_save_hash: snapshotHash,
            client_saved_at: savedAt,
          })
          .eq('user_id', userId)
        if (saveError) throw saveError

        return json({ saved: true, unchanged: false, clientSavedAt: savedAt })
      }

      if (action === 'login_account') {
        const usernameNormalized = normalizeUsername(body.username)
        validateUsername(usernameNormalized)
        const { data: profile, error: profileError } = await admin
          .from('chrono_profiles')
          .select('user_id, username, auth_email')
          .eq('username_normalized', usernameNormalized)
          .maybeSingle()
        if (profileError) throw profileError

        if (!profile) {
          await new Promise((resolve) => setTimeout(resolve, 250))
          return json({ authenticated: false, error: 'Nome de usuário ou senha inválidos', code: 'INVALID_LOGIN', field: 'password' })
        }

        const { data: authRecord, error: authRecordError } = await admin.auth.admin.getUserById(profile.user_id)
        if (authRecordError) throw authRecordError
        const authUser = authRecord?.user
        const ready = !!authUser?.email && hasEmailIdentity(authUser) && authUser?.is_anonymous !== true

        if (!ready) {
          return json({
            authenticated: false,
            needsRepair: true,
            repairCurrentSession: profile.user_id === userId,
            error: profile.user_id === userId
              ? 'Esta conta precisa ser concluída antes do login.'
              : 'Esta conta precisa ser recuperada com a chave de recuperação.',
            code: 'ACCOUNT_NEEDS_REPAIR',
            field: 'username',
          })
        }

        const actualAuthEmail = String(authUser.email)
        if (profile.auth_email !== actualAuthEmail) {
          const { error: repairEmailError } = await admin
            .from('chrono_profiles')
            .update({ auth_email: actualAuthEmail })
            .eq('user_id', profile.user_id)
          if (repairEmailError) console.warn('Não foi possível corrigir auth_email', repairEmailError)
        }


        const password = validatePassword(body.password)
        const session = await passwordSession(req, actualAuthEmail, password)
        if (!session) {
          await new Promise((resolve) => setTimeout(resolve, 250))
          return json({ authenticated: false, error: 'Nome de usuário ou senha inválidos', code: 'INVALID_LOGIN', field: 'password' })
        }

        await deleteTemporaryAnonymousActor(admin, userId, profile.user_id)
        return json({ authenticated: true, username: profile.username, session })
      }

      if (action === 'register_account') {
        const username = String(body.username ?? '').normalize('NFKC').trim()
        const usernameNormalized = normalizeUsername(username)
        const contactEmail = String(body.email ?? '').normalize('NFKC').trim()
        const contactEmailNormalized = normalizeContactEmail(contactEmail)
        const password = validatePassword(body.password)
        const recoveryKey = validateRecoveryKey(body.recoveryKey)

        validateUsername(usernameNormalized)
        validateContactEmail(contactEmailNormalized)

        const { data: existingProfile, error: existingProfileError } = await admin
          .from('chrono_profiles')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle()
        if (existingProfileError) throw existingProfileError
        if (existingProfile) publicError('Esta sessão já possui uma conta. Conclua a configuração ou entre novamente.', 409, 'ACCOUNT_EXISTS')

        const { data: authRecord, error: authRecordError } = await admin.auth.admin.getUserById(userId)
        if (authRecordError) throw authRecordError
        if (!authRecord?.user?.is_anonymous) publicError('Esta sessão não pode ser registrada novamente', 409, 'ACCOUNT_EXISTS')

        const { data: usernameTaken, error: usernameError } = await admin
          .from('chrono_profiles')
          .select('user_id')
          .eq('username_normalized', usernameNormalized)
          .maybeSingle()
        if (usernameError) throw usernameError
        if (usernameTaken) publicError('Este nome de usuário já está em uso', 409, 'USERNAME_TAKEN', 'username')

        const { data: emailTaken, error: emailError } = await admin
          .from('chrono_profiles')
          .select('user_id')
          .eq('contact_email_normalized', contactEmailNormalized)
          .maybeSingle()
        if (emailError) throw emailError
        if (emailTaken) publicError('Este e-mail já está registrado', 409, 'EMAIL_TAKEN', 'email')

        await bootstrapPlayerState(admin, userId, body.snapshot)
        const upgraded = await upgradeUserInPlace(admin, userId, {
          username,
          usernameNormalized,
          contactEmail,
          contactEmailNormalized,
        }, password, recoveryKey, true)
        const session = await passwordSession(req, upgraded.authEmail, password)

        return json({
          registered: true,
          username,
          userId: upgraded.userId,
          state: upgraded.state,
          session,
        })
      }

      if (action === 'repair_account') {
        const password = validatePassword(body.password)
        const recoveryKey = validateRecoveryKey(body.recoveryKey)
        const { data: profile, error: profileError } = await admin
          .from('chrono_profiles')
          .select('username, username_normalized, contact_email, contact_email_normalized')
          .eq('user_id', userId)
          .maybeSingle()
        if (profileError) throw profileError
        if (!profile) publicError('Conta para reparo não encontrada', 404, 'ACCOUNT_NOT_FOUND')

        const { data: authRecord, error: authRecordError } = await admin.auth.admin.getUserById(userId)
        if (authRecordError) throw authRecordError
        if (hasEmailIdentity(authRecord?.user) && authRecord?.user?.is_anonymous !== true) {
          publicError('Esta conta já está configurada corretamente', 409, 'ACCOUNT_ALREADY_VALID')
        }

        const upgraded = await upgradeUserInPlace(admin, userId, {
          username: profile.username,
          usernameNormalized: profile.username_normalized,
          contactEmail: profile.contact_email,
          contactEmailNormalized: profile.contact_email_normalized,
        }, password, recoveryKey, false)
        const session = await passwordSession(req, upgraded.authEmail, password)

        return json({
          repaired: true,
          username: profile.username,
          userId: upgraded.userId,
          state: upgraded.state,
          session,
        })
      }

      if (action === 'recover_account') {
        const usernameNormalized = normalizeUsername(body.username)
        const recoveryKey = validateRecoveryKey(body.recoveryKey)
        const newPassword = validatePassword(body.newPassword)
        validateUsername(usernameNormalized)

        const { data: attempt, error: attemptError } = await admin
          .from('chrono_recovery_attempts')
          .select('failed_attempts, locked_until')
          .eq('actor_user_id', userId)
          .eq('username_normalized', usernameNormalized)
          .maybeSingle()
        if (attemptError) throw attemptError

        const actorLockUntil = attempt?.locked_until ? new Date(attempt.locked_until).getTime() : 0
        if (actorLockUntil > Date.now()) {
          publicError('Muitas tentativas. Aguarde alguns minutos e tente novamente.', 429, 'RECOVERY_RATE_LIMIT')
        }

        const recordFailure = async () => {
          const attempts = finiteInt(attempt?.failed_attempts, 0, 20) + 1
          const lockedUntil = attempts >= 5 ? new Date(Date.now() + 15 * 60_000).toISOString() : null
          const nextAttempts = attempts >= 5 ? 0 : attempts
          const { error } = await admin
            .from('chrono_recovery_attempts')
            .upsert({
              actor_user_id: userId,
              username_normalized: usernameNormalized,
              failed_attempts: nextAttempts,
              locked_until: lockedUntil,
              updated_at: new Date().toISOString(),
            }, { onConflict: 'actor_user_id,username_normalized' })
          if (error) throw error
          await new Promise((resolve) => setTimeout(resolve, 300))
          return json({ error: 'Usuário ou chave de recuperação inválidos', code: 'INVALID_RECOVERY', field: 'recoveryKey', status: 400 })
        }

        const { data: profile, error: profileError } = await admin
          .from('chrono_profiles')
          .select('user_id, username, username_normalized, contact_email, contact_email_normalized, auth_email, recovery_key_hash')
          .eq('username_normalized', usernameNormalized)
          .maybeSingle()
        if (profileError) throw profileError
        if (!profile) return recordFailure()

        const suppliedHash = await recoveryHash(usernameNormalized, recoveryKey)
        if (suppliedHash !== profile.recovery_key_hash) return recordFailure()

        const { data: targetAuth, error: targetAuthError } = await admin.auth.admin.getUserById(profile.user_id)
        if (targetAuthError) throw targetAuthError
        const authReady = !!targetAuth?.user?.email && hasEmailIdentity(targetAuth?.user) && targetAuth?.user?.is_anonymous !== true
        const authEmail = authReady
          ? String(targetAuth.user.email)
          : await generatedAuthEmail(profile.username_normalized, profile.user_id)

        const { error: passwordError } = await admin.auth.admin.updateUserById(profile.user_id, {
          email: authEmail,
          password: newPassword,
          email_confirm: true,
          user_metadata: { username: profile.username },
        })
        if (passwordError) throw passwordError

        const { error: resetError } = await admin
          .from('chrono_profiles')
          .update({
            auth_email: authEmail,
            last_recovered_at: new Date().toISOString(),
          })
          .eq('user_id', profile.user_id)
        if (resetError) throw resetError

        await admin
          .from('chrono_recovery_attempts')
          .delete()
          .eq('actor_user_id', userId)
          .eq('username_normalized', usernameNormalized)

        const session = await passwordSession(req, authEmail, newPassword)
        if (!session) throw new Error('A senha foi atualizada, mas a sessão não pôde ser criada')
        await deleteTemporaryAnonymousActor(admin, userId, profile.user_id)
        return json({ recovered: true, session })
      }

      if (action === 'rotate_recovery' || action === 'change_password') {
        const currentPassword = validatePassword(body.currentPassword)
        const { data: profile, error: profileError } = await admin
          .from('chrono_profiles')
          .select('username_normalized, auth_email')
          .eq('user_id', userId)
          .single()
        if (profileError) throw profileError

        const { data: authRecord, error: authError } = await admin.auth.admin.getUserById(userId)
        if (authError) throw authError
        const actualAuthEmail = String(authRecord?.user?.email ?? profile.auth_email ?? '')
        if (!actualAuthEmail) publicError('Conta sem identidade de login', 409, 'ACCOUNT_NEEDS_REPAIR')
        const verified = await passwordSession(req, actualAuthEmail, currentPassword)
        if (!verified) publicError('Senha atual incorreta', 401, 'INVALID_CURRENT_PASSWORD', 'currentPassword')

        if (action === 'rotate_recovery') {
          const recoveryKey = validateRecoveryKey(body.recoveryKey)
          const keyHash = await recoveryHash(profile.username_normalized, recoveryKey)
          const { error: updateError } = await admin
            .from('chrono_profiles')
            .update({ recovery_key_hash: keyHash, auth_email: actualAuthEmail })
            .eq('user_id', userId)
          if (updateError) throw updateError
          return json({ rotated: true })
        }

        const newPassword = validatePassword(body.newPassword)
        const { error: passwordUpdateError } = await admin.auth.admin.updateUserById(userId, {
          password: newPassword,
        })
        if (passwordUpdateError) throw passwordUpdateError
        const session = await passwordSession(req, actualAuthEmail, newPassword)
        if (!session) throw new Error('Senha alterada, mas a nova sessão não pôde ser criada')
        return json({ changed: true, session })
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

        const { data: previous } = await admin
          .from('chrono_action_receipts')
          .select('response')
          .eq('user_id', userId)
          .eq('request_id', requestId)
          .maybeSingle()

        if (previous?.response) return json(previous.response)

        const state = await bootstrapPlayerState(admin, userId, body.snapshot)
        const response = {
          imported: true,
          message: 'Progresso sincronizado.',
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

      if (action === 'enable_economy') {
        const requestId = String(body.requestId ?? '')
        if (!requestId) return json({ error: 'requestId ausente' }, 400)

        const { data, error } = await admin.rpc('chrono_enable_economy_server', {
          p_user_id: userId,
          p_request_id: requestId,
        })

        if (error) throw error
        return json(data)
      }

      if (action === 'purchase_character') {
        const requestId = String(body.requestId ?? '')
        const characterKey = String(body.characterKey ?? '').slice(0, 80)

        if (!requestId || !characterKey) {
          return json({ error: 'Dados da compra ausentes' }, 400)
        }

        if (!PROTECTED_CHARACTER_KEYS.has(characterKey)) {
          return json({ error: 'Personagem ainda não suportado pela compra segura' }, 400)
        }

        const { data, error } = await admin.rpc('chrono_purchase_character_server', {
          p_user_id: userId,
          p_request_id: requestId,
          p_character_key: characterKey,
        })

        if (error) throw error
        return json(data)
      }

      if (action === 'load_missions') {
        const { data, error } = await admin.rpc('chrono_load_missions_server', {
          p_user_id: userId,
        })

        if (error) throw error
        return json(data)
      }

      if (action === 'claim_mission') {
        const requestId = String(body.requestId ?? '')
        const slotKey = String(body.slotKey ?? '').slice(0, 40)

        if (!requestId || !slotKey) {
          return json({ error: 'Dados da missão ausentes' }, 400)
        }

        const { data, error } = await admin.rpc('chrono_claim_mission_server', {
          p_user_id: userId,
          p_request_id: requestId,
          p_slot_key: slotKey,
        })

        if (error) throw error
        return json(data)
      }

      if (action === 'redeem_code') {
        const requestId = String(body.requestId ?? '')
        const normalizedCode = normalizeRewardCode(body.code)

        if (!requestId || !normalizedCode) {
          return json({ error: 'Digite um código' }, 400)
        }
        if (normalizedCode.length > 256) {
          return json({ error: 'Código grande demais' }, 400)
        }

        const codeHash = await sha256Hex(normalizedCode)
        const { data, error } = await admin.rpc('chrono_redeem_code_server', {
          p_user_id: userId,
          p_request_id: requestId,
          p_code_hash: codeHash,
        })

        if (error) throw error
        return json(data)
      }

      if (action === 'start_run') {
        const mode = String(body.mode ?? 'normal').slice(0, 40)
        const classKey = String(body.classKey ?? '').slice(0, 80)
        if (!classKey) return json({ error: 'Classe ausente' }, 400)
        if (!ALLOWED_RUN_MODES.has(mode)) {
          return json({ error: 'Modo de jogo inválido' }, 400)
        }
        if (!ALLOWED_CHARACTER_KEYS.has(classKey)) {
          return json({ error: 'Personagem inválido' }, 400)
        }

        const { data: state, error: stateError } = await admin
          .from('chrono_player_state')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle()

        if (stateError) throw stateError

        if (
          state?.character_purchases_enabled === true &&
          PROTECTED_CHARACTER_KEYS.has(classKey) &&
          !stateOwnsCharacter(state, classKey)
        ) {
          return json({ error: 'Personagem não adquirido no servidor' }, 403)
        }

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
        return json({ session: data, state })
      }

      if (action === 'finish_run') {
        const requestId = String(body.requestId ?? '')
        const sessionId = String(body.sessionId ?? '')
        if (!requestId || !sessionId) {
          return json({ error: 'Identificadores ausentes' }, 400)
        }

        const totalKills = finiteInt(body.kills, 0, 10_000_000)
        const { data, error } = await admin.rpc('chrono_finish_run_server', {
          p_user_id: userId,
          p_request_id: requestId,
          p_session_id: sessionId,
          p_score: finiteInt(body.score, 0, 2_000_000_000),
          p_wave: finiteInt(body.wave, 0, 1_000_000),
          p_kills: totalKills,
          p_gold: finiteInt(body.gold, 0, 1_000_000_000),
          p_relic_delta: finiteInt(body.relicDelta, 0, 1_000_000),
          p_chrono_delta: finiteInt(body.chronoDelta, 0, 100_000),
          p_boss_kills: finiteInt(body.bossKills, 0, totalKills),
          p_elite_kills: finiteInt(body.eliteKills, 0, totalKills),
          p_skills_used: finiteInt(body.skillsUsed, 0, 10_000_000),
          p_type_kills: sanitizeTypeKills(body.typeKills, totalKills),
        })

        if (error) {
          const message = String(error.message ?? '')
          if (message.toLowerCase().includes('sessão não encontrada')) {
            return json({ accepted: false, terminal: true, error: 'Sessão não encontrada', code: 'RUN_SESSION_MISSING' })
          }
          if (message.toLowerCase().includes('sessão já finalizada') || message.toLowerCase().includes('sessão já encerrada')) {
            return json({ accepted: false, terminal: true, error: 'Sessão já finalizada', code: 'RUN_ALREADY_SETTLED' })
          }
          if (message.toLowerCase().includes('não pertence')) {
            return json({ accepted: false, terminal: true, error: 'A sessão não pertence a esta conta', code: 'RUN_OWNER_MISMATCH' })
          }

          const validationPatterns = [
            'partida curta demais',
            'incompatível',
            'valores negativos',
            'resumo de inimigos inválido',
            'tipo de inimigo inválido',
            'contagem de inimigo inválida',
            'contagem por tipo maior',
            'soma de inimigos maior',
            'save online não inicializado',
            'recompensas de partida ainda não estão ativadas',
          ]
          const lowerMessage = message.toLowerCase()
          if (validationPatterns.some((pattern) => lowerMessage.includes(pattern))) {
            const { error: rejectError } = await admin
              .from('chrono_game_sessions')
              .update({
                status: 'rejected',
                ended_at: new Date().toISOString(),
                summary: {
                  rejected: true,
                  reason: 'validation_failed',
                  detail: message.slice(0, 240),
                },
              })
              .eq('id', sessionId)
              .eq('user_id', userId)
              .eq('status', 'active')
            if (rejectError) console.warn('Não foi possível marcar a run como rejeitada', rejectError)
            return json({
              accepted: false,
              terminal: true,
              rejected: true,
              error: 'A partida não pôde ser validada.',
              code: 'RUN_VALIDATION_REJECTED',
            })
          }
          throw error
        }
        return json(data)
      }

      return json({ error: 'Ação desconhecida' }, 400)
    } catch (error) {
      console.error('Chrono Cloud error', error)
      if (error instanceof PublicError) {
        const payload = { error: error.message, code: error.code, field: error.field ?? null, status: error.status }
        return json(payload, SOFT_ERROR_ACTIONS.has(action) ? 200 : error.status)
      }
      const message = error instanceof Error
        ? error.message
        : error && typeof error === 'object' && 'message' in error
          ? String((error as { message?: unknown }).message ?? 'Erro interno')
          : 'Erro interno'
      return json({ error: message, code: 'INTERNAL_ERROR' }, 500)
    }
  }),
}
