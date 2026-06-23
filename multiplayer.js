/* ============================================================
   CHRONO SHARDS — MULTIPLAYER v11 (PeerJS, P2P co-op)
   v11 (auditoria sobre v10):
     - FIX ouro host duplicado: kill credit é a única fonte de income;
       startGoldPoolSync só aplica DELTAS NEGATIVOS (gastos) no host.
     - FIX race de gasto no cliente: ao chegar goldSync, preserva gasto
       local ainda não reportado e envia delta na hora.
     - FIX duplicação de hooks após restart: guardas em S.* (não no
       objeto game) + clearInterval para todos os loops de host.
     - FIX vazamento de loops: clearInterval em todos os start*Loop
       (enemy, dmg, targeting, bossWatcher, kill credit).
     - FIX shopResume no host: limpa shopPending/betweenWaves local.
     - FIX onHost/onJoin: reseta estado antes de criar nova sala.
     - FIX tryJoinOnce: trava dupla agenda quando error + timeout.
     - FIX startBulletBroadcast: skip de hash agora funciona sempre.
   ============================================================ */
(() => {
'use strict';

// ===================== CONFIG =====================
const VERSION         = 'mp-v13';
/* v13 — fixes principais sobre v12:
   - Wave infinita / "Esperando jogadores" persistente: o wrap de
     startNextWave agora SÓ intercepta quando uma loja está aberta
     (S.inShop). Auto-advances de wave (rift, sem shop) passam direto
     pro original.
   - applyEnemySnapshot: muta g.enemies in-place em vez de substituir a
     referência (impede o jogo de continuar simulando inimigos "fantasma"
     do client e mantém a lista visível pelo render do próprio jogo).
   - Cliente agora limpa loops locais de spawn de inimigo do jogo (set
     g.spawnCd alto + zera arrays de spawn-queue se existir) para evitar
     hordas locais paralelas às do host.
   - Pause sync robusta: escuta keydown direto (P/Esc) e força gg.paused
     em ambos os lados, sem depender de polling frágil de gg.paused.
   - Revive: tecla mudou de E para F. Reset correto de progresso quando
     o alvo morre/sai do raio.
   - Render de jogadores remotos: usa proxy pra chamar
     window.drawPlayer/window.drawBullets do jogo (skin/classe/efeitos
     corretos por personagem) trocando temporariamente game.player,
     game.classKey, mouse e game.bullets para o estado do peer.
   - Status replication: sincroniza shield, ult ativa, cloak, dash e
     hurt cooldown junto com o tick de jogadores.
   - "Esperando jogadores" só aparece dentro de S.inShop.            */
const TICK_HZ         = 20;
const ENEMY_HZ        = 15;
const BULLET_HZ       = 10;
const HOST_DMG_HZ     = 20;
const GOLD_SYNC_HZ    = 4;          // sincronização de pool de ouro
const GOLD_DROP_MULT  = 1.5;        // online: 1.5x ouro nas mortes
const REVIVE_TIME     = 10000;
const REVIVE_RANGE    = 90;
const REVIVE_HP_PCT   = 0.25;
const CHAT_MAX        = 8;
const PEER_PREFIX     = 'cs3-';
const SAVE_KEY        = 'chrono_v4_meta';
const CLASS_UNLOCK_K  = SAVE_KEY + '_class_unlocks_v3';
const FREE_CLASSES    = ['assault','sniper'];

const ENEMY_COUNT_BASE = 2.0;
const ENEMY_COUNT_STEP = 0.15;
const DIFFICULTY_ORDER = ['easy','medium','hard','extreme'];

const DIFFICULTY = {
  easy:    { label:'Fácil',   mult:1.0, color:'#4ce0b3' },
  medium:  { label:'Médio',   mult:1.6, color:'#46d6ff' },
  hard:    { label:'Difícil', mult:2.4, color:'#ffd166' },
  extreme: { label:'Extremo', mult:3.5, color:'#ff4d6d' },
};

function getUnlockedSet(){
  try {
    const raw = localStorage.getItem(CLASS_UNLOCK_K) || '[]';
    const arr = JSON.parse(raw);
    return new Set([...FREE_CLASSES, ...(Array.isArray(arr)?arr:[])]);
  } catch { return new Set(FREE_CLASSES); }
}

// ===================== ESTADO =====================
const S = {
  peer: null, isHost: false, myId: null,
  myName: 'P' + Math.floor(Math.random()*900+100),
  roomCode: null,
  difficulty: 'medium',
  riftMode: false,
  conns: new Map(),
  players: new Map(),
  started: false,
  chat: [],
  reviveTarget: null, reviveStart: 0,
  enemyIdCounter: 1,
  injectedMenuBtn: null,
  menuPollTimer: null,
  // visuais/redes:
  remoteBullets: new Map(), // peerId -> array de bullets snapshot {x,y,r,c}
  bulletTimer: null,
  lastBulletHash: 0,
  reconnectAttempts: 0,
  netToastTimer: null,
  hostRetries: 0,
  // ouro compartilhado:
  goldPool: 0,
  lastSyncedGold: 0,
  goldTimer: null,
  goldReady: false,
  // shop sincronizado:
  inShop: false,
  myShopReady: false,
  shopReadySet: new Set(),
  shopWaitEl: null,
  // pause sincronizado:
  pausedRemoteBy: null,
  iAmPauser: false,
  pauseOverlayEl: null,
  lastPausedFlag: false,
  bossAnnounced: new Set(),
  // handles para limpar intervalos no restart:
  _enemyTimer:null, _hostDmgTimer:null, _killCreditTimer:null,
  _bossWatchTimer:null, _pauseTimer:null, _tickTimer:null,
  _bulletHookGen:0, // gera novo "ID" para invalidar loops antigos de bullet hook
};



// ===================== UTIL =====================
const $ = (s, r=document) => r.querySelector(s);
const log = (...a) => console.log('%c[MP]', 'color:#6cf', ...a);
const warn = (...a) => console.warn('[MP]', ...a);
// IMPORTANTE: PeerJS IDs são case-sensitive. Usamos sempre minúsculas internamente
// e mostramos MAIÚSCULAS apenas na UI (mais legível). Caracteres permitidos: [a-z0-9].
const rid = () => Math.random().toString(36).slice(2,8).toLowerCase().replace(/[^a-z0-9]/g,'a');
const normalizeCode = (raw) => {
  // Aceita "ABC123", "abc123", "cs3-abc123", "CS3-ABC123", com espaços/traços extras.
  let s = String(raw||'').toLowerCase().trim().replace(/\s+/g,'');
  if (s.startsWith(PEER_PREFIX)) s = s.slice(PEER_PREFIX.length);
  s = s.replace(/[^a-z0-9]/g,'');
  return s ? (PEER_PREFIX + s) : '';
};
const prettyCode = (full) => (full||'').replace(PEER_PREFIX,'').toUpperCase();
const hpMult = () => (DIFFICULTY[S.difficulty]||DIFFICULTY.medium).mult;
const enemyCountMult = () => {
  const idx = Math.max(0, DIFFICULTY_ORDER.indexOf(S.difficulty));
  return ENEMY_COUNT_BASE + ENEMY_COUNT_STEP * idx;
};

function getClasses(){
  const c = window.CLASSES || window.Classes || null;
  if (!c) return [];
  if (Array.isArray(c)) {
    return c.map((x,i)=>({
      key: x.key||x.id||String(i),
      name: x.name||x.title||x.key||('Classe '+i),
      icon: x.icon||x.emoji||'⚔️',
      tag:  x.tag||'', tagColor: x.tagColor||'#6cf',
      color: x.color||'#6cf',
      desc: x.desc||x.description||''
    }));
  }
  return Object.entries(c).map(([k,v])=>({
    key: k,
    name: v.name||k,
    icon: v.icon||v.emoji||'⚔️',
    tag:  v.tag||'', tagColor: v.tagColor||'#6cf',
    color: v.color||'#6cf',
    desc: v.desc||v.description||''
  }));
}

function el(tag, props={}, ...kids){
  const n = document.createElement(tag);
  for (const k in props){
    if (k === 'style') Object.assign(n.style, props.style);
    else if (k === 'html') n.innerHTML = props.html;
    else if (k.startsWith('on') && typeof props[k] === 'function') n.addEventListener(k.slice(2), props[k]);
    else n[k] = props[k];
  }
  for (const c of kids) if (c!=null) n.append(c.nodeType ? c : document.createTextNode(c));
  return n;
}

// ===================== ESTILOS =====================
function injectCSS(){
  if (document.getElementById('mp-style')) return;
  const css = `
  #mp-root { font-family:'Rajdhani','Inter',system-ui,sans-serif; color:#eef2ff; }
  .mp-btn { font-family:inherit; cursor:pointer; border:1px solid rgba(120,200,255,0.25);
            background:linear-gradient(180deg,rgba(40,60,100,0.6),rgba(20,30,55,0.6));
            color:#eef2ff; border-radius:10px; padding:10px 14px; font-weight:700;
            letter-spacing:0.04em; transition:all .15s; }
  .mp-btn:hover:not(:disabled){ border-color:#61dafb; box-shadow:0 0 14px rgba(97,218,251,0.35); transform:translateY(-1px); }
  .mp-btn:disabled{ opacity:.45; cursor:not-allowed; }
  .mp-btn.primary{ background:linear-gradient(180deg,#46d6ff,#1e90ff); border-color:#9bedff; color:#001020; }
  .mp-btn.success{ background:linear-gradient(180deg,#4ce0b3,#1aa978); border-color:#9ef5d8; color:#001a10; }
  .mp-btn.ghost  { background:rgba(255,255,255,0.04); }
  .mp-btn.huge   { padding:22px 18px; font-size:15px; display:flex; flex-direction:column; align-items:center; gap:6px; }
  .mp-input{ font-family:inherit; background:rgba(6,8,18,0.7); border:1px solid rgba(120,200,255,0.2);
             color:#eef2ff; border-radius:8px; padding:10px 12px; width:100%; font-size:14px; }
  .mp-input:focus{ outline:none; border-color:#61dafb; box-shadow:0 0 0 2px rgba(97,218,251,0.2); }
  .mp-card{ background:rgba(6,8,18,0.92); border:1px solid rgba(120,200,255,0.15);
            backdrop-filter:blur(16px); border-radius:16px;
            box-shadow:0 20px 60px rgba(0,0,0,0.6), inset 0 0 30px rgba(80,140,255,0.04); }
  .mp-title{ font-family:'Orbitron',sans-serif; font-weight:900; letter-spacing:.15em;
             background:linear-gradient(90deg,#61dafb,#9f6cff,#ff6b9d);
             -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
  .mp-label{ font-size:10px; letter-spacing:.18em; opacity:.65; font-weight:700; margin-bottom:6px; display:block; }
  .mp-row{ display:flex; align-items:center; justify-content:space-between; padding:10px 12px;
           background:rgba(255,255,255,0.03); border:1px solid rgba(120,200,255,0.1);
           border-radius:10px; }
  .mp-row.ready{ border-color:rgba(76,224,179,0.4); background:rgba(76,224,179,0.06); }
  .mp-row.host { border-color:rgba(255,209,102,0.35); }
  .mp-chip{ font-size:11px; padding:2px 8px; border-radius:999px; letter-spacing:.08em; font-weight:700; }
  .mp-class-card{ position:relative; display:flex; flex-direction:column; gap:8px; padding:14px;
                  background:linear-gradient(160deg,rgba(30,40,75,0.85),rgba(8,12,25,0.92));
                  border:1px solid rgba(120,200,255,0.18); border-radius:14px;
                  cursor:pointer; transition:all .18s; text-align:left; min-height:148px;
                  box-shadow:inset 0 0 24px rgba(80,140,255,0.05); }
  .mp-class-card:hover:not(:disabled){ border-color:#61dafb; transform:translateY(-3px); box-shadow:0 10px 28px rgba(97,218,251,0.28); }
  .mp-class-card.picked{ border-color:#4ce0b3; box-shadow:0 0 0 2px rgba(76,224,179,0.45), 0 0 24px rgba(76,224,179,0.25); background:linear-gradient(160deg,rgba(30,70,55,0.85),rgba(8,20,15,0.92)); }
  .mp-class-card.locked{ filter:saturate(.35) grayscale(.6); opacity:.55; cursor:not-allowed; }
  .mp-class-icon{ width:54px; height:54px; border-radius:12px; display:grid; place-items:center; font-size:30px;
                  background:rgba(255,255,255,0.05); border:1px solid rgba(120,200,255,0.22); }
  .mp-diff{ display:grid; grid-template-columns:repeat(4,1fr); gap:6px; }
  .mp-diff button{ padding:10px 6px; border-radius:8px; border:1px solid rgba(120,200,255,0.18);
                   background:rgba(6,8,18,0.6); color:#eef2ff; font-family:inherit;
                   font-weight:700; font-size:12px; cursor:pointer; transition:all .15s; }
  .mp-diff button.on{ border-color: currentColor; box-shadow:0 0 0 2px currentColor inset; }
  .mp-fade-in{ animation:mpFade .2s ease-out; }
  @keyframes mpFade{ from{opacity:0; transform:translateY(4px);} to{opacity:1; transform:none;} }
  #mp-net-toast{
    position:fixed; top:14px; left:50%; transform:translateX(-50%) translateY(-12px);
    z-index:100000; pointer-events:none; opacity:0;
    background:linear-gradient(180deg,rgba(12,18,38,0.96),rgba(6,10,22,0.96));
    border:1px solid rgba(120,200,255,0.3); backdrop-filter:blur(12px);
    color:#eef2ff; padding:10px 18px; border-radius:999px; font-size:12px;
    font-weight:700; letter-spacing:.1em;
    box-shadow:0 12px 40px rgba(0,0,0,0.55), 0 0 24px rgba(97,218,251,0.18);
    transition:opacity .25s ease, transform .25s ease;
  }
  #mp-net-toast.show{ opacity:1; transform:translateX(-50%) translateY(0); }
  #mp-net-toast.ok   { border-color:rgba(76,224,179,0.55); color:#7ff0c8;
                       box-shadow:0 12px 40px rgba(0,0,0,0.55), 0 0 28px rgba(76,224,179,0.35); }
  #mp-net-toast.warn { border-color:rgba(255,209,102,0.55); color:#ffd166;
                       box-shadow:0 12px 40px rgba(0,0,0,0.55), 0 0 28px rgba(255,209,102,0.3); }
  #mp-net-toast.err  { border-color:rgba(255,77,109,0.6); color:#ff8fa3;
                       box-shadow:0 12px 40px rgba(0,0,0,0.55), 0 0 30px rgba(255,77,109,0.4); }
  .mp-code-display{
    font-family:'Orbitron','Rajdhani',sans-serif; font-size:30px; font-weight:900;
    letter-spacing:.32em; text-align:center; padding:14px 18px; border-radius:14px;
    background:linear-gradient(180deg,rgba(20,30,60,0.7),rgba(6,10,22,0.7));
    border:1px solid rgba(97,218,251,0.35);
    color:#9bedff; text-shadow:0 0 18px rgba(97,218,251,0.55);
    box-shadow:inset 0 0 30px rgba(97,218,251,0.12), 0 8px 28px rgba(0,0,0,0.5);
    animation:codePulse 2.6s ease-in-out infinite;
  }
  @keyframes codePulse{
    0%,100%{ box-shadow:inset 0 0 30px rgba(97,218,251,0.12), 0 8px 28px rgba(0,0,0,0.5), 0 0 0 rgba(97,218,251,0); }
    50%   { box-shadow:inset 0 0 30px rgba(97,218,251,0.22), 0 8px 28px rgba(0,0,0,0.5), 0 0 28px rgba(97,218,251,0.35); }
  }
  .mp-input.code{
    text-transform:uppercase; letter-spacing:.32em; text-align:center;
    font-family:'Orbitron','Rajdhani',sans-serif; font-size:22px; font-weight:900;
    padding:16px 12px; color:#9bedff;
  }
  .mp-input.code.invalid{ border-color:rgba(255,77,109,0.6); box-shadow:0 0 0 2px rgba(255,77,109,0.25); }
  .mp-input.code.valid  { border-color:rgba(76,224,179,0.6); box-shadow:0 0 0 2px rgba(76,224,179,0.25); }
  .mp-spinner{
    display:inline-block; width:12px; height:12px; border-radius:50%;
    border:2px solid rgba(155,237,255,0.25); border-top-color:#9bedff;
    animation:mpSpin .8s linear infinite; vertical-align:middle; margin-right:8px;
  }
  @keyframes mpSpin{ to { transform:rotate(360deg); } }
  `;
  document.head.append(el('style', { id:'mp-style', textContent: css }));
}

function netToast(msg, kind='ok', ms=2200){
  let t = document.getElementById('mp-net-toast');
  if (!t){ t = el('div', { id:'mp-net-toast' }); document.body.append(t); }
  t.textContent = msg;
  t.className = kind + ' show';
  if (S.netToastTimer) clearTimeout(S.netToastTimer);
  S.netToastTimer = setTimeout(()=>{ t.className = kind; }, ms);
}

// ===================== UI =====================
let UI = {};
function buildUI(){
  if (document.getElementById('mp-root')) return;
  injectCSS();

  const root = el('div', { id:'mp-root', style:{
    position:'fixed', inset:'0', zIndex:99999, pointerEvents:'none'
  }});

  const openBtn = el('button', { className:'mp-btn primary', style:{
    position:'absolute', top:'12px', right:'12px', pointerEvents:'auto',
    fontSize:'13px', display:'none'
  }}, '🎮 Multiplayer');
  openBtn.onclick = () => { toggleLobby(true); showStage('home'); };
  root.append(openBtn);

  const panel = el('div', { id:'mp-panel', className:'mp-card mp-fade-in', style:{
    position:'absolute', top:'50%', left:'50%', transform:'translate(-50%,-50%)',
    width:'min(640px,94vw)', maxHeight:'90vh', overflow:'auto',
    padding:'22px', pointerEvents:'auto', display:'none'
  }});

  panel.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:18px">
      <div>
        <div class="mp-title" style="font-size:22px">CHRONO SHARDS</div>
        <div style="font-size:11px;opacity:.6;letter-spacing:.2em;margin-top:2px">MULTIPLAYER CO-OP · ${VERSION}</div>
      </div>
      <button id="mp-close" class="mp-btn ghost" style="padding:6px 10px">×</button>
    </div>

    <div id="mp-stage-home" style="display:none">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:8px">
        <button id="mp-go-create" class="mp-btn primary huge">
          <span style="font-size:30px">🛡️</span><span>CRIAR SALA</span>
          <span style="font-size:10px;opacity:.7;font-weight:600">Você será o host</span>
        </button>
        <button id="mp-go-join" class="mp-btn success huge">
          <span style="font-size:30px">⚔️</span><span>ENTRAR EM SALA</span>
          <span style="font-size:10px;opacity:.7;font-weight:600">Use o código de um amigo</span>
        </button>
      </div>
      <div style="margin-top:18px;padding:10px 12px;background:rgba(97,218,251,0.06);
                  border:1px solid rgba(97,218,251,0.18);border-radius:10px;font-size:12px;opacity:.85">
        💡 Co-op P2P. O host é autoridade dos inimigos, bosses e dano.
      </div>
      <div id="mp-home-msg" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <div id="mp-stage-create" style="display:none">
      <button class="mp-btn ghost" data-back style="font-size:12px;padding:6px 10px;margin-bottom:14px">← voltar</button>
      <div style="display:grid;gap:12px">
        <div><span class="mp-label">SEU NOME</span><input id="mp-name-c" class="mp-input" maxlength="14"/></div>
        <div><span class="mp-label">DIFICULDADE</span><div id="mp-diff" class="mp-diff"></div></div>
        <label style="display:flex;align-items:center;gap:8px;font-size:13px;cursor:pointer">
          <input id="mp-rift" type="checkbox"/> Forçar Fissuras (modo 507)
        </label>
        <button id="mp-host" class="mp-btn primary" style="padding:14px">🛡️ CRIAR SALA</button>
      </div>
      <div id="mp-status-c" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <div id="mp-stage-join" style="display:none">
      <button class="mp-btn ghost" data-back style="font-size:12px;padding:6px 10px;margin-bottom:14px">← voltar</button>
      <div style="display:grid;gap:12px">
        <div><span class="mp-label">SEU NOME</span><input id="mp-name-j" class="mp-input" maxlength="14"/></div>
        <div><span class="mp-label">CÓDIGO DA SALA</span>
          <input id="mp-code" class="mp-input code" placeholder="A1B2C3" maxlength="14" autocomplete="off" spellcheck="false"/>
          <div id="mp-code-hint" style="margin-top:6px;font-size:11px;opacity:.55;text-align:center">Cole ou digite o código que o host te passou</div>
        </div>
        <button id="mp-join" class="mp-btn success" style="padding:14px">⚔️ ENTRAR NA SALA</button>
      </div>
      <div id="mp-status-j" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <div id="mp-stage-lobby" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:14px;gap:12px">
        <div style="flex:1">
          <div class="mp-label" style="margin:0 0 6px">CÓDIGO DA SALA · COMPARTILHE COM SEU AMIGO</div>
          <div id="mp-room-label" class="mp-code-display">------</div>
        </div>
        <div style="display:flex;gap:6px">
          <span id="mp-role" class="mp-chip" style="padding:4px 10px">HOST</span>
          <button id="mp-copy" class="mp-btn ghost" style="font-size:11px;padding:4px 8px">📋 copiar</button>
        </div>
      </div>
      <div class="mp-label">JOGADORES</div>
      <div id="mp-players" style="display:grid;gap:8px;margin-bottom:14px"></div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
        <button id="mp-pick" class="mp-btn primary" disabled>Selecionar Personagem</button>
        <button id="mp-start" class="mp-btn success" disabled>Iniciar Partida</button>
      </div>
      <div id="mp-lobby-msg" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <div id="mp-stage-pick" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
        <div>
          <div style="font-size:18px;font-weight:800;letter-spacing:.02em">Escolha seu personagem</div>
          <div style="font-size:11px;opacity:.55;margin-top:2px">Classes bloqueadas precisam ser desbloqueadas no menu principal do jogo.</div>
        </div>
        <button id="mp-pick-back" class="mp-btn ghost" style="font-size:12px;padding:6px 10px">← voltar</button>
      </div>
      <div id="mp-class-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;margin-top:14px"></div>
    </div>
  `;
  root.append(panel);

  const chat = el('div', { id:'mp-chat', style:{
    position:'absolute', left:'12px', bottom:'12px', width:'340px',
    pointerEvents:'none', display:'none'
  }});
  chat.innerHTML = `
    <div id="mp-chat-log" style="display:flex;flex-direction:column;gap:4px;margin-bottom:6px"></div>
    <input id="mp-chat-input" class="mp-input" placeholder="Enter para enviar..." style="display:none;pointer-events:auto"/>
  `;
  root.append(chat);

  const team = el('div', { id:'mp-team', className:'mp-card', style:{
    position:'absolute', top:'58px', right:'12px', width:'220px',
    padding:'10px', fontSize:'12px', display:'none', pointerEvents:'none'
  }});
  root.append(team);

  document.body.append(root);

  UI = {
    openBtn, panel, chat, team,
    close: $('#mp-close',panel),
    sHome:$('#mp-stage-home',panel), sCreate:$('#mp-stage-create',panel),
    sJoin:$('#mp-stage-join',panel), sLobby:$('#mp-stage-lobby',panel), sPick:$('#mp-stage-pick',panel),
    goCreate:$('#mp-go-create',panel), goJoin:$('#mp-go-join',panel),
    nameC:$('#mp-name-c',panel), nameJ:$('#mp-name-j',panel),
    diff:$('#mp-diff',panel), rift:$('#mp-rift',panel), host:$('#mp-host',panel),
    code:$('#mp-code',panel), join:$('#mp-join',panel),
    statusC:$('#mp-status-c',panel), statusJ:$('#mp-status-j',panel), homeMsg:$('#mp-home-msg',panel),
    roomLabel:$('#mp-room-label',panel), copy:$('#mp-copy',panel), role:$('#mp-role',panel),
    plist:$('#mp-players',panel), pick:$('#mp-pick',panel), start:$('#mp-start',panel),
    lmsg:$('#mp-lobby-msg',panel), pickBack:$('#mp-pick-back',panel), grid:$('#mp-class-grid',panel),
    chatLog:$('#mp-chat-log',chat), chatInput:$('#mp-chat-input',chat),
  };

  UI.nameC.value = S.myName; UI.nameJ.value = S.myName;
  renderDifficulty();

  UI.close.onclick = () => toggleLobby(false);
  UI.goCreate.onclick = () => showStage('create');
  UI.goJoin.onclick   = () => showStage('join');
  panel.querySelectorAll('[data-back]').forEach(b => b.onclick = () => showStage('home'));

  UI.host.onclick = onHost;
  UI.join.onclick = onJoin;
  UI.copy.onclick = () => {
    if (!S.roomCode) return;
    const short = prettyCode(S.roomCode);
    try { navigator.clipboard?.writeText(short); } catch(_) {}
    UI.copy.textContent='✓ copiado!';
    setTimeout(()=>UI.copy.textContent='📋 copiar', 1200);
  };
  UI.pick.onclick = () => { if (!UI.pick.disabled) showPick(); };
  UI.start.onclick = () => { if (!UI.start.disabled) hostStart(); };
  UI.pickBack.onclick = () => showStage('lobby');

  // Input do código: sanitização ao vivo + feedback visual + Enter para entrar
  UI.code.addEventListener('input', e => {
    const cleaned = String(e.target.value||'').toUpperCase().replace(/[^A-Z0-9-]/g,'');
    if (cleaned !== e.target.value) e.target.value = cleaned;
    const norm = normalizeCode(cleaned);
    e.target.classList.remove('valid','invalid');
    if (!cleaned) { /* neutro */ }
    else if (norm && norm.length > PEER_PREFIX.length) e.target.classList.add('valid');
    else e.target.classList.add('invalid');
  });
  UI.code.addEventListener('keydown', e => {
    if (e.key === 'Enter' && !UI.join.disabled) { e.preventDefault(); onJoin(); }
  });

  UI.chatInput.addEventListener('keydown', e => {
    e.stopPropagation();
    if (e.key === 'Enter'){
      const m = UI.chatInput.value.trim();
      if (m) sendChat(m);
      UI.chatInput.value=''; UI.chatInput.style.display='none'; UI.chatInput.blur();
    } else if (e.key === 'Escape'){
      UI.chatInput.value=''; UI.chatInput.style.display='none'; UI.chatInput.blur();
    }
  });
  window.addEventListener('keydown', e => {
    if (!S.started) return;
    if (document.activeElement === UI.chatInput) return;
    if (e.key === 'Enter'){ e.preventDefault(); UI.chatInput.style.display='block'; UI.chatInput.focus(); }
  });

  if (!window.__MP_BRIDGE_READY__) {
    UI.homeMsg.innerHTML = '⚠️ Bridge não detectado. Cole <code>mp-bridge.js</code> no final do &lt;script&gt; principal.';
  }

  startMenuButtonPoller();
}

function showStage(name){
  ['home','create','join','lobby','pick'].forEach(k => {
    const m = { home:UI.sHome, create:UI.sCreate, join:UI.sJoin, lobby:UI.sLobby, pick:UI.sPick }[k];
    if (m) m.style.display = (k===name) ? '' : 'none';
  });
}

function renderDifficulty(){
  UI.diff.innerHTML = '';
  for (const [k,d] of Object.entries(DIFFICULTY)){
    const b = el('button', {
      onclick: () => { S.difficulty = k; renderDifficulty(); },
      style: { color: d.color }
    }, d.label);
    if (k === S.difficulty) b.classList.add('on');
    UI.diff.append(b);
  }
}

function toggleLobby(show){ UI.panel.style.display = show ? '' : 'none'; }
function setStatus(m, which='c'){
  const e = which==='j' ? UI.statusJ : UI.statusC;
  if (e) e.textContent = m;
  log(m);
}

function startMenuButtonPoller(){
  if (S.menuPollTimer) return;
  S.menuPollTimer = setInterval(() => {
    try {
      if (S.started){
        if (S.injectedMenuBtn && S.injectedMenuBtn.isConnected) S.injectedMenuBtn.remove();
        S.injectedMenuBtn = null;
        UI.openBtn.style.display = 'none';
        return;
      }
      const rift = document.getElementById('riftMode50');
      const choice = document.querySelector('.riftModeChoice50');
      if (!rift || !choice){
        if (S.injectedMenuBtn && S.injectedMenuBtn.isConnected) S.injectedMenuBtn.remove();
        S.injectedMenuBtn = null;
        UI.openBtn.style.display = 'none';
        return;
      }
      if (S.injectedMenuBtn && S.injectedMenuBtn.isConnected) return;

      const card = rift.cloneNode(true);
      card.id = 'mpMode50';
      card.style.setProperty('--c', '#9f6cff');
      card.classList.remove('locked525','locked');
      card.querySelectorAll('.riftLockLayer525,.riftLockBadge525').forEach(n=>n.remove());
      card.querySelectorAll('h2,p').forEach(n=>{ n.style.opacity=''; });
      card.style.filter=''; card.style.pointerEvents='auto';
      const tag = card.querySelector('.riftTag50');
      const h2  = card.querySelector('h2');
      const p   = card.querySelector('p');
      if (tag){ tag.textContent = 'NOVO · CO-OP'; tag.style.color='#c8a8ff'; tag.style.borderColor='rgba(200,168,255,.45)'; }
      if (h2){ h2.textContent  = 'Multiplayer 2P'; h2.style.color='#fff'; h2.style.opacity='1'; }
      if (p){ p.textContent   = 'Convide um amigo e enfrente as waves em co-op. Inimigos compartilhados, lojas individuais e revive em equipe.'; p.style.opacity='1'; }
      card.onclick = (ev) => {
        ev.preventDefault(); ev.stopPropagation();
        toggleLobby(true); showStage('home');
      };
      choice.appendChild(card);
      S.injectedMenuBtn = card;
      UI.openBtn.style.display = 'none';
    } catch(e){}
  }, 400);
}

// ===================== PEERJS (com retry + reconnect) =====================
function attachPeerCommonHandlers(p, which){
  p.on('disconnected', () => {
    warn('peer disconnected, tentando reconectar...');
    netToast('Reconectando...', 'warn', 4000);
    try { p.reconnect(); } catch(_) {}
  });
  p.on('close', () => {
    warn('peer closed');
    netToast('Conexão encerrada', 'err', 4000);
  });
}

// Tradução de tipos de erro do PeerJS para mensagens em PT amigáveis
const PEER_ERR_PT = {
  'invalid-id'        : 'Código inválido (use só letras/números).',
  'invalid-key'       : 'Servidor de signalling indisponível.',
  'unavailable-id'    : 'Esse código já está em uso, gerando outro...',
  'peer-unavailable'  : 'Sala não encontrada. Confira o código com seu amigo.',
  'network'           : 'Sem internet ou servidor offline.',
  'disconnected'      : 'Desconectado do servidor de signalling.',
  'server-error'      : 'Servidor de signalling com erro. Tente novamente.',
  'socket-error'      : 'Falha de socket — tentando reconectar...',
  'socket-closed'     : 'Conexão com signalling encerrada.',
  'ssl-unavailable'   : 'SSL indisponível neste ambiente.',
  'webrtc'            : 'Seu navegador bloqueou WebRTC.',
  'browser-incompatible': 'Navegador incompatível com WebRTC.',
};
const peerErrMsg = (err) => {
  const t = err && err.type;
  return (t && PEER_ERR_PT[t]) || (err && (err.message || t)) || 'Erro desconhecido';
};

// Config padrão do PeerJS Cloud (público) + STUN do Google.
// `secure:true` é necessário quando a página roda em HTTPS (lovableproject.com).
function peerConfig(){
  const httpsPage = (typeof location !== 'undefined' && location.protocol === 'https:');
  return {
    debug: 1,
    secure: httpsPage,
    config: {
      iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:global.stun.twilio.com:3478' },
      ],
    },
  };
}

function ensurePeer(id){
  return new Promise((resolve,reject)=>{
    if (!window.Peer) return reject(new Error('PeerJS não carregado'));
    let p;
    try { p = id ? new Peer(id, peerConfig()) : new Peer(peerConfig()); }
    catch(e){ return reject(e); }

    let opened = false, settled = false;
    // timeout de abertura — se o servidor de signalling não responder em 12s, falha
    const openTimeout = setTimeout(()=>{
      if (settled) return; settled = true;
      try { p.destroy(); } catch(_) {}
      reject(new Error('Sem resposta do servidor de signalling (timeout 12s)'));
    }, 12000);

    p.on('open', pid => {
      if (settled) return; settled = true; clearTimeout(openTimeout);
      opened=true; S.peer=p; S.myId=pid;
      attachPeerCommonHandlers(p);
      resolve(p);
    });
    p.on('error', err => {
      warn('peer error', err && (err.type||err.message), err);
      if (!opened){
        if (!settled){ settled = true; clearTimeout(openTimeout); reject(err); }
      } else {
        // erros pós-open: peer-unavailable em connect, network, etc.
        netToast(peerErrMsg(err), err && err.type === 'peer-unavailable' ? 'err' : 'warn', 3500);
      }
    });
    p.on('connection', onIncoming);
  });
}

function clearAllLoops(){
  for (const k of ['_enemyTimer','_hostDmgTimer','_killCreditTimer',
                   '_bossWatchTimer','_pauseTimer','_tickTimer',
                   'bulletTimer','goldTimer']){
    if (S[k]) { try{ clearInterval(S[k]); }catch(_){ } S[k] = null; }
  }
  S._bulletHookGen++; // invalida qualquer client bullet hook antigo
}

function resetMpRuntime(){
  // chamado antes de criar/entrar em nova sala — limpa resíduo da partida anterior
  clearAllLoops();
  S.players = new Map();
  S.conns   = new Map();
  S.remoteBullets = new Map();
  S.shopReadySet  = new Set();
  S.bossAnnounced = new Set();
  S.pausedRemoteBy = null; S.iAmPauser = false; S.lastPausedFlag = false;
  S.inShop = false; S.myShopReady = false;
  S.goldPool = 0; S.lastSyncedGold = 0;
  S.started = false; S.lastBulletHash = 0;
  hidePauseOverlay(); hideShopWait();
  if (S.peer && !S.peer.destroyed) { try{ S.peer.destroy(); }catch(_){ } }
  S.peer = null; S.myId = null;
}

function onHost(){
  resetMpRuntime();
  S.myName  = (UI.nameC.value||S.myName).slice(0,14);
  S.riftMode= UI.rift.checked;
  S.isHost  = true;
  S.hostRetries = 0;
  tryHostOnce();
}

function tryHostOnce(){
  S.roomCode = PEER_PREFIX + rid();
  setStatus('Criando sala... (tentativa '+(S.hostRetries+1)+'/5)', 'c');
  ensurePeer(S.roomCode).then(()=>{
    netToast('Sala criada · ' + prettyCode(S.roomCode), 'ok', 2500);
    S.players.set(S.myId, mkLocalEntry());
    enterLobby();
  }).catch(e => {
    const t = e && e.type;
    // Retentativa para colisão de ID OU erro transitório de signalling
    const retriable = (t === 'unavailable-id' || t === 'id-taken' ||
                      t === 'network' || t === 'socket-error' || t === 'server-error');
    if (retriable && S.hostRetries < 4){
      S.hostRetries++;
      const delay = 350 + 250*S.hostRetries;
      log('Retentando criar sala em '+delay+'ms ('+t+')');
      setTimeout(tryHostOnce, delay);
    } else {
      setStatus('Falhou: '+peerErrMsg(e), 'c');
      netToast(peerErrMsg(e), 'err', 4000);
    }
  });
}

function onJoin(){
  const rawInput = (UI.code.value||'').trim();
  if (!rawInput) return setStatus('Digite o código da sala.', 'j');
  const full = normalizeCode(rawInput);
  if (!full || full.length <= PEER_PREFIX.length){
    setStatus('Código inválido. Use só letras/números.', 'j');
    netToast('Código inválido', 'err', 3000);
    return;
  }
  resetMpRuntime();
  S.myName = (UI.nameJ.value||S.myName).slice(0,14);
  S.isHost = false;
  S.roomCode = full;
  setStatus('Conectando em '+prettyCode(full)+'...', 'j');
  ensurePeer().then(()=>tryJoinOnce(0)).catch(e => {
    setStatus('Falhou: '+peerErrMsg(e), 'j');
    netToast(peerErrMsg(e), 'err', 4000);
  });
}

function tryJoinOnce(attempt){
  if (!S.peer || S.peer.destroyed){
    setStatus('Peer destruído. Recarregue a página.', 'j');
    netToast('Peer perdido — recarregue', 'err', 4000);
    return;
  }
  setStatus('Conectando ao host '+prettyCode(S.roomCode)+'... ('+(attempt+1)+'/3)', 'j');

  const conn = S.peer.connect(S.roomCode, { reliable:true, serialization:'json' });
  let opened=false, settled=false, fatal=false;

  const finish = () => {
    if (settled) return; settled = true;
    clearTimeout(timeout);
    try { S.peer.off && S.peer.off('error', onPeerErr); } catch(_) {}
  };

  // Captura peer-unavailable (sala não existe) que vem pelo objeto peer, NÃO pela conn
  const onPeerErr = (err) => {
    if (opened || settled) return;
    if (err && err.type === 'peer-unavailable'){
      fatal = true;
      finish();
      setStatus('Sala não encontrada. Confira o código com seu amigo.', 'j');
      netToast('Sala "'+prettyCode(S.roomCode)+'" não existe', 'err', 5000);
    }
  };
  try { S.peer.on('error', onPeerErr); } catch(_) {}

  const scheduleRetry = (label) => {
    if (settled || fatal) return;
    finish();
    if (attempt < 2){
      const delay = 800 * (attempt+1);
      setStatus(label+' Retentando em '+(delay/1000)+'s...', 'j');
      setTimeout(()=>tryJoinOnce(attempt+1), delay);
    } else {
      setStatus(label+' Verifique o código com o host.', 'j');
      netToast('Falha ao conectar', 'err', 4500);
    }
  };

  const timeout = setTimeout(()=>{
    if (opened) return;
    try { conn.close(); } catch(_) {}
    scheduleRetry('Sem resposta do host.');
  }, 8000);

  conn.on('open', ()=>{
    opened=true; finish();
    S.conns.set(S.roomCode, conn);
    conn.send({ t:'hello', name:S.myName, v:VERSION });
    S.players.set(S.myId, mkLocalEntry());
    netToast('Conectado ao host ✓', 'ok', 2500);
    enterLobby();
  });
  conn.on('data', d => handleData(conn, d));
  conn.on('close', ()=>{
    if (!opened) return; // close pré-open já tratado
    setStatus('Conexão fechada pelo host.', 'j');
    netToast('Conexão encerrada', 'err', 3500);
  });
  conn.on('error', e => {
    if (!opened) scheduleRetry('Erro: '+peerErrMsg(e)+'.');
  });
}

function onIncoming(conn){
  if (!S.isHost) return;
  conn.on('open', ()=>{
    S.conns.set(conn.peer, conn);
    log('peer joined', conn.peer);
    netToast('Jogador entrou', 'ok');
  });
  conn.on('data', d => handleData(conn, d));
  conn.on('close', ()=>{
    S.conns.delete(conn.peer);
    S.players.delete(conn.peer);
    S.remoteBullets.delete(conn.peer);
    S.shopReadySet.delete(conn.peer);
    // se quem caiu era quem pausou, libera todos
    if (S.pausedRemoteBy === conn.peer){
      S.pausedRemoteBy = null;
      hidePauseOverlay();
      const gg = window.game; if (gg){ gg.paused = false; gg.running = true; }
      bcast({ t:'resumeRemote' });
    }
    // se quem caiu travava o shop, re-avalia
    if (S.inShop && S.isHost) evaluateShopReady();
    netToast('Jogador saiu', 'warn');
    broadcastLobby(); renderLobby();
  });
  conn.on('error', e => warn('conn err', e));
}

function mkLocalEntry(){
  return { id:S.myId, name:S.myName, classKey:null, ready:false,
           x:0,y:0,hp:100,maxHp:100,wave:1,score:0,down:false, host:S.isHost };
}

// ===================== PROTOCOLO =====================
function send(conn, obj){ try{ conn.send(obj); }catch(e){} }
function bcast(obj){ for (const c of S.conns.values()) send(c, obj); }

function handleData(conn, d){
  if (!d || !d.t) return;
  if (S.isHost){
    switch(d.t){
      case 'hello':
        S.players.set(conn.peer, {
          id:conn.peer, name:(d.name||'P').slice(0,14),
          classKey:null, ready:false,
          x:0,y:0,hp:100,maxHp:100,wave:1,score:0,down:false, host:false
        });
        broadcastLobby(); renderLobby(); break;
      case 'pickClass': {
        const p = S.players.get(conn.peer);
        if (p){ p.classKey = d.classKey; p.ready = true; }
        broadcastLobby(); renderLobby(); break;
      }
      case 'state': {
        const p = S.players.get(conn.peer);
        if (p) Object.assign(p, d.s);
        break;
      }
      case 'bullets': {
        S.remoteBullets.set(conn.peer, Array.isArray(d.b) ? d.b : []);
        // host repassa para os outros peers (não para o emissor)
        for (const [pid, c] of S.conns){
          if (pid === conn.peer) continue;
          send(c, { t:'bulletsRemote', from:conn.peer, b:d.b });
        }
        break;
      }
      case 'dmg': hostApplyDamage(d.mpId, d.amount, conn.peer); break;
      case 'chat': bcastChat(d.from||'?', d.msg||''); break;
      case 'revive': {
        const tgt = S.players.get(d.target);
        if (tgt){
          tgt.down = false;
          tgt.hp = Math.max(1, Math.floor(tgt.maxHp * REVIVE_HP_PCT));
        }
        if (d.target === S.myId) doLocalRevive();
        else {
          const c = S.conns.get(d.target);
          if (c) send(c, { t:'youRevived' });
        }
        broadcastLobby(); break;
      }
      case 'down': {
        const p = S.players.get(conn.peer);
        if (p) p.down = !!d.down;
        broadcastLobby(); break;
      }
      // ---- v10: ouro compartilhado ----
      case 'goldDelta': {
        // cliente reporta delta local (gasto negativo). Host aplica sem multiplicador.
        const dlt = Number(d.delta)||0;
        S.goldPool = Math.max(0, S.goldPool + dlt);
        broadcastGoldPool();
        break;
      }
      case 'goldEarn': {
        // cliente matou inimigo (creditado via host kill credit já; este é fallback)
        const amt = Math.max(0, Math.floor((Number(d.amount)||0) * GOLD_DROP_MULT));
        S.goldPool += amt;
        broadcastGoldPool();
        break;
      }
      // ---- v10: shop sincronizado ----
      case 'shopReady': {
        S.shopReadySet.add(conn.peer);
        evaluateShopReady();
        break;
      }
      case 'shopUnready': {
        S.shopReadySet.delete(conn.peer);
        broadcastShopWait();
        break;
      }
      // ---- v10: pause sincronizado ----
      case 'paused': {
        if (S.pausedRemoteBy) break; // já tem alguém pausado
        S.pausedRemoteBy = conn.peer;
        const pName = (S.players.get(conn.peer)||{}).name || 'Player';
        bcast({ t:'pauseRemote', by: conn.peer, byName: pName });
        // host também congela (mas não mostra overlay próprio se foi o host que pausou)
        applyRemotePause(conn.peer, pName);
        break;
      }
      case 'unpaused': {
        if (S.pausedRemoteBy !== conn.peer) break;
        S.pausedRemoteBy = null;
        bcast({ t:'resumeRemote' });
        applyRemoteResume();
        break;
      }
    }
  } else {
    switch(d.t){
      case 'lobby':
        S.players = new Map(d.players.map(p=>[p.id,p]));
        S.difficulty = d.difficulty || S.difficulty;
        S.riftMode = d.riftMode;
        renderLobby(); break;
      case 'start': startLocalGame(d.classByPlayer[S.myId]); break;
      case 'youRevived': doLocalRevive(); break;
      case 'youHit': clientApplyHit(d.amount||0); break;
      case 'state': {
        for (const p of d.players){
          if (p.id === S.myId) continue;
          const cur = S.players.get(p.id) || {};
          S.players.set(p.id, Object.assign(cur, p));
        }
        break;
      }
      case 'bullets':
        S.remoteBullets.set('__host__', Array.isArray(d.b) ? d.b : []);
        break;
      case 'bulletsRemote':
        S.remoteBullets.set(d.from || '__other__', Array.isArray(d.b) ? d.b : []);
        break;
      case 'enemies': applyEnemySnapshot(d.list, d.wave); break;
      case 'chat': pushChat(d.from, d.msg); break;
      case 'bossSpawn': announceBoss(d.name||'BOSS', d.color||'#ff2e63'); break;
      case 'shopOpen':  clientHandleShopOpen(); break;
      case 'shopResume': clientHandleShopResume(); break;
      case 'shopWait':  renderShopWait(d.ready||0, d.total||1); break;
      case 'youKilled': clientApplyKill(d); break;
      // v10:
      case 'goldSync': {
        const gg = window.game;
        const pool = Number(d.pool)||0;
        if (gg){
          // Preserva gasto local ainda não reportado (evita race onde
          // o sync sobrescreve uma compra recém-feita).
          const localDelta = (gg.gold||0) - S.lastSyncedGold;
          if (localDelta < 0){
            const c = S.conns.get(S.roomCode);
            if (c) send(c, { t:'goldDelta', delta: localDelta });
            gg.gold = Math.max(0, pool + localDelta);
          } else {
            gg.gold = pool;
          }
          S.lastSyncedGold = gg.gold;
        }
        S.goldPool = pool;
        try { if (typeof window.updateHUD === 'function') window.updateHUD(); } catch(_){}
        break;
      }
      case 'pauseRemote': applyRemotePause(d.by, d.byName||'Player'); break;
      case 'resumeRemote': applyRemoteResume(); break;
    }
  }
}

function broadcastLobby(){
  if (!S.isHost) return;
  bcast({ t:'lobby', players:[...S.players.values()],
          difficulty:S.difficulty, riftMode:S.riftMode });
}
function broadcastState(){
  if (!S.isHost) return;
  bcast({ t:'state', players:[...S.players.values()].map(p=>({
    id:p.id, name:p.name, classKey:p.classKey,
    x:p.x, y:p.y, hp:p.hp, maxHp:p.maxHp,
    wave:p.wave, score:p.score, down:p.down
  }))});
}
function bcastChat(from, msg){
  pushChat(from, msg);
  if (!S.isHost) return;
  bcast({ t:'chat', from, msg });
}
function sendChat(msg){
  if (S.isHost) bcastChat(S.myName, msg);
  else {
    pushChat(S.myName, msg);
    const c = S.conns.get(S.roomCode); if (c) send(c, { t:'chat', from:S.myName, msg });
  }
}
function pushChat(from, msg){
  S.chat.push({from, msg, t:Date.now()});
  if (S.chat.length > CHAT_MAX) S.chat.shift();
  renderChat();
}

// ===================== LOBBY RENDER =====================
function enterLobby(){
  showStage('lobby');
  UI.roomLabel.textContent = prettyCode(S.roomCode);
  UI.role.textContent = S.isHost ? 'HOST' : 'CLIENTE';
  UI.role.style.background = S.isHost ? 'rgba(255,209,102,0.15)' : 'rgba(97,218,251,0.15)';
  UI.role.style.color = S.isHost ? '#ffd166' : '#61dafb';
  UI.role.style.borderColor = S.isHost ? 'rgba(255,209,102,0.35)' : 'rgba(97,218,251,0.35)';
  if (S.isHost) broadcastLobby();
  renderLobby();
}

function renderLobby(){
  if (!UI.plist) return;
  const players = [...S.players.values()];
  const classes = new Map(getClasses().map(c=>[c.key,c]));
  UI.plist.innerHTML = '';
  for (const p of players){
    const c = p.classKey ? classes.get(p.classKey) : null;
    const row = el('div', { className:'mp-row' + (p.ready?' ready':'') + (p.host?' host':'') });
    const left = el('div', { style:{display:'flex',alignItems:'center',gap:'10px'} });
    left.append(el('div', { style:{
      width:'36px',height:'36px',borderRadius:'8px',
      background:'rgba(255,255,255,0.05)',display:'grid',placeItems:'center',
      fontSize:'20px', border:'1px solid '+(c?(c.tagColor||'#6cf')+'44':'rgba(120,200,255,0.15)')
    }}, c?c.icon:'❔'));
    const info = el('div');
    info.append(el('div', { style:{fontWeight:'700',fontSize:'14px'} },
      p.name + (p.host?' 👑':'') + (p.id===S.myId?' (você)':'')));
    info.append(el('div', { style:{fontSize:'11px',opacity:.7,marginTop:'2px'} },
      p.classKey ? (c?c.name:p.classKey) : 'escolhendo personagem...'));
    left.append(info);
    const right = el('span', { className:'mp-chip', style:{
      background: p.ready?'rgba(76,224,179,0.2)':'rgba(255,255,255,0.06)',
      color: p.ready?'#4ce0b3':'#9ab',
      border:'1px solid '+(p.ready?'rgba(76,224,179,0.4)':'rgba(255,255,255,0.1)')
    }}, p.ready ? '✓ PRONTO' : '⏳ ESPERANDO');
    row.append(left, right);
    UI.plist.append(row);
  }
  const me = S.players.get(S.myId);
  const enough = players.length >= 2;
  const allReady = enough && players.every(p=>p.ready);
  if (!me)               setBtn(UI.pick, false, 'primary', 'Selecionar Personagem');
  else if (!enough)      setBtn(UI.pick, true,  'primary', '⚔️ Selecionar Personagem (esperando 2º)');
  else if (me.ready)     setBtn(UI.pick, true,  'ghost',   '🔁 Trocar Personagem');
  else                   setBtn(UI.pick, true,  'primary', '⚔️ Selecionar Personagem');

  if (S.isHost)
    setBtn(UI.start, allReady, 'success', allReady ? '▶ INICIAR PARTIDA' : 'Aguardando seleções...');
  else
    setBtn(UI.start, false, 'ghost', allReady ? 'Host vai iniciar...' : 'Aguardando seleções...');

  UI.lmsg.textContent = !enough ? 'Compartilhe o código com seu amigo para começar.'
                      : (!allReady ? 'Cada jogador precisa escolher um personagem.'
                      : (S.isHost ? 'Tudo pronto! Clique em INICIAR.' : 'Aguarde o host iniciar a partida...'));
}

function setBtn(b, enabled, variant, text){
  b.disabled = !enabled; b.textContent = text; b.className = 'mp-btn ' + variant;
}

function showPick(){
  const classes = getClasses();
  UI.grid.innerHTML = '';
  if (classes.length === 0){
    UI.grid.innerHTML = `
      <div style="grid-column:1/-1;padding:14px;background:rgba(255,77,109,0.1);
                  border:1px solid rgba(255,77,109,0.35);border-radius:10px;font-size:13px;line-height:1.5">
        <b>⚠️ window.CLASSES não encontrado.</b><br>
        Cole o trecho <code>mp-bridge.js</code> no FINAL do &lt;script&gt; principal do jogo, e recarregue.
      </div>`;
  } else {
    const me = S.players.get(S.myId);
    const unlocked = getUnlockedSet();
    classes.sort((a,b)=> (unlocked.has(b.key)?1:0) - (unlocked.has(a.key)?1:0));
    for (const c of classes){
      const isUnlocked = unlocked.has(c.key);
      const picked = me?.classKey===c.key;
      const card = el('button', {
        className:'mp-class-card' + (picked?' picked':'') + (isUnlocked?'':' locked'),
        disabled: !isUnlocked,
      });
      const header = el('div', { style:{display:'flex',justifyContent:'space-between',alignItems:'flex-start',gap:'8px'} });
      header.append(el('div', { className:'mp-class-icon', style:{
        borderColor:(c.tagColor||c.color||'#6cf')+'66',
        color:(c.tagColor||c.color||'#fff')
      }}, c.icon));
      const badges = el('div', { style:{display:'flex',flexDirection:'column',gap:'4px',alignItems:'flex-end'} });
      if (!isUnlocked){
        badges.append(el('span', { className:'mp-chip', style:{
          background:'rgba(255,209,102,0.15)', color:'#ffd166',
          border:'1px solid rgba(255,209,102,0.4)'
        }}, '🔒 BLOQUEADO'));
      } else if (c.tag){
        badges.append(el('span', { className:'mp-chip', style:{
          background:(c.tagColor||'#6cf')+'22', color:(c.tagColor||'#6cf'),
          border:'1px solid '+(c.tagColor||'#6cf')+'55'
        }}, c.tag));
      }
      if (picked) badges.append(el('span', { className:'mp-chip', style:{
        background:'rgba(76,224,179,.18)', color:'#4ce0b3',
        border:'1px solid rgba(76,224,179,.5)'
      }}, '✓ ESCOLHIDA'));
      header.append(badges);
      card.append(header);
      card.append(el('div', { style:{fontWeight:'800',fontSize:'16px',marginTop:'2px'} }, c.name));
      if (c.desc) card.append(el('div', { style:{fontSize:'12px',opacity:.7,lineHeight:'1.4'} },
        c.desc.length>120 ? c.desc.slice(0,120)+'…' : c.desc));
      if (!isUnlocked){
        card.append(el('div', { style:{
          fontSize:'10px',color:'#ffd166',marginTop:'auto',
          letterSpacing:'.05em',fontWeight:'700'
        }}, '⛏ Desbloqueie com fragmentos no menu principal'));
      }
      if (isUnlocked) card.onclick = () => pickClass(c.key);
      UI.grid.append(card);
    }
  }
  showStage('pick');
}

function pickClass(key){
  if (!getUnlockedSet().has(key)){ log('Classe bloqueada:', key); return; }
  const me = S.players.get(S.myId);
  if (me){ me.classKey = key; me.ready = true; }
  if (S.isHost) broadcastLobby();
  else { const c = S.conns.get(S.roomCode); if (c) send(c, { t:'pickClass', classKey:key }); }
  showStage('lobby'); renderLobby();
}

// ===================== INICIAR JOGO =====================
function hostStart(){
  if (!S.isHost) return;
  const classByPlayer = {};
  for (const p of S.players.values()){
    if (!p.classKey) { netToast('Aguardando todos escolherem classe', 'warn'); return; }
    classByPlayer[p.id] = p.classKey;
  }
  bcast({ t:'start', classByPlayer });
  startLocalGame(classByPlayer[S.myId]);
}

function closeGameOverlay(){
  const ov = document.getElementById('overlay');
  if (ov) ov.classList.add('hidden');
  if (ov && getComputedStyle(ov).display !== 'none') ov.style.display = 'none';
}

function startLocalGame(classKey){
  if (!classKey) { warn('sem classe!'); return; }
  S.started = true;
  toggleLobby(false);
  UI.chat.style.display = '';
  UI.team.style.display = '';
  if (S.injectedMenuBtn && S.injectedMenuBtn.isConnected) S.injectedMenuBtn.remove();
  S.injectedMenuBtn = null;
  UI.openBtn.style.display = 'none';

  if (S.riftMode) { try { window.__forceNextRift507 = true; } catch(e){} }
  try {
    if (typeof window.resetGame === 'function') {
      window.resetGame(classKey);
    } else { warn('window.resetGame não disponível'); return; }
  } catch(e){ console.error('[MP] erro ao iniciar:', e); return; }

  closeGameOverlay();
  setTimeout(closeGameOverlay, 50);
  setTimeout(closeGameOverlay, 250);

  setTimeout(()=>{
    installEnemyPatch();
    startTickLoop();
    startEnemySync();
    startHostDamageLoop();
    startHostTargetingLoop();
    startBulletBroadcast();
    startGoldPoolSync();
    startPauseWatcher();
    startOverlay();
    netToast('Partida iniciada · '+ (DIFFICULTY[S.difficulty]?.label||''), 'ok', 2500);
  }, 80);
}

// ===================== INIMIGOS COMPARTILHADOS =====================
function installEnemyPatch(){
  const g = window.game; if (!g) return;

  if (typeof window.gameOver === 'function' && !window.gameOver.__mpWrapped){
    const origGO = window.gameOver;
    const wrappedGO = function(){
      if (window.game && window.game.__mpDowned) return;
      const others = [...S.players.values()]
        .filter(p => p.id !== S.myId && p.classKey && !p.down);
      if (others.length > 0){
        const gg = window.game;
        if (gg){
          gg.__mpDowned = true;
          if (!S.isHost) gg.running = false;
          if (gg.player){ gg.player.hp = 0; gg.player.down = true; gg.player.dead = true; }
        }
        const me = S.players.get(S.myId); if (me) me.down = true;
        if (S.isHost) broadcastLobby();
        else { const c = S.conns.get(S.roomCode); if (c) send(c, { t:'down', down:true }); }
        return;
      }
      return origGO.apply(this, arguments);
    };
    wrappedGO.__mpWrapped = true;
    try { window.gameOver = wrappedGO; } catch(e){}
  }

  if (S.isHost){
    const orig = window.spawnEnemy;
    if (typeof orig === 'function' && !orig.__mpWrapped){
      const wrapped = function(...a){
        const totalMult = enemyCountMult();
        const whole = Math.floor(totalMult);
        const frac  = totalMult - whole;
        const N = whole + (Math.random() < frac ? 1 : 0);
        let firstR = null;
        for (let i=0; i<Math.max(1,N); i++){
          const before = g.enemies ? g.enemies.length : 0;
          const r = orig.apply(this, a);
          const e = (r && typeof r === 'object') ? r :
                    (g.enemies && g.enemies.length > before ? g.enemies[g.enemies.length-1] : null);
          if (e){
            const m = hpMult();
            if (typeof e.hp === 'number' && m !== 1){
              const base = e.maxHp || e.hp;
              e.hp    = e.hp * m; e.maxHp = base * m;
            }
            if (!e.__mpId) e.__mpId = S.enemyIdCounter++;
            if (i > 0){
              e.x = (e.x||0) + (Math.random()*60 - 30);
              e.y = (e.y||0) + (Math.random()*60 - 30);
            }
          }
          if (i===0) firstR = r;
        }
        return firstR;
      };
      wrapped.__mpWrapped = true;
      try { window.spawnEnemy = wrapped; } catch(e){}
    }
  } else {
    try {
      const noop = function(){
        const gg = window.game;
        if (gg) gg.enemiesSpawnedThisWave = (gg.enemiesSpawnedThisWave||0) + 1;
        return null;
      };
      noop.__mpWrapped = true;
      window.spawnEnemy = noop;
    } catch(e){}
    if (typeof window.updateWaveState === 'function' && !window.updateWaveState.__mpWrapped){
      const stub = function(){}; stub.__mpWrapped = true;
      try { window.updateWaveState = stub; } catch(e){}
    }
    // NÃO substituímos startNextWave por stub aqui: o installShopSync vai
    // envolvê-lo para enviar 'shopReady' ao host quando o cliente clicar em
    // continuar. clientHandleShopResume chama o original quando o host libera.
    installClientBulletHook();
  }
  installShopSync();
  installBossWatcher();
  if (S.isHost) installHostKillCredit();
}

function doLocalRevive(){
  const gg = window.game; if (!gg) return;
  gg.__mpDowned = false;
  gg.running = true;
  if (gg.player){
    const max = gg.player.maxHp || 100;
    gg.player.hp = Math.max(1, Math.floor(max * REVIVE_HP_PCT));
    gg.player.down = false; gg.player.dead = false;
  }
  const me = S.players.get(S.myId);
  if (me){ me.down = false; me.hp = (gg.player && gg.player.hp) || me.hp; }
  if (!S.isHost){
    const c = S.conns.get(S.roomCode); if (c) send(c, { t:'down', down:false });
  } else broadcastLobby();
  netToast('Você foi revivido!', 'ok');
}

function clientApplyHit(amount){
  const gg = window.game; if (!gg || !gg.player) return;
  if (gg.__mpDowned) return;
  gg.player.hp = Math.max(0, (gg.player.hp||0) - amount);
  if (gg.player.hp <= 0){
    try { if (typeof window.gameOver === 'function') window.gameOver(); } catch(e){}
  }
}

function installClientBulletHook(){
  // Usa S._bulletHookGen p/ invalidar loops antigos quando a partida reinicia.
  const myGen = ++S._bulletHookGen;
  const loop = ()=>{
    if (myGen !== S._bulletHookGen) return; // outro hook tomou o lugar
    if (!S.started) return;
    if (S.isHost)   return;
    const gg = window.game;
    if (gg && Array.isArray(gg.bullets) && Array.isArray(gg.enemies)){
      const bullets = gg.bullets, enemies = gg.enemies;
      for (let i=0;i<bullets.length;i++){
        const b = bullets[i];
        if (!b || b.__mpConsumed) continue;
        if (b.dead || b.life<=0) continue;
        for (let j=0;j<enemies.length;j++){
          const e = enemies[j];
          if (!e || !e.__mpId || e.__mpDead) continue;
          const dx = (b.x||0)-(e.x||0), dy=(b.y||0)-(e.y||0);
          const rr = (b.r||3) + (e.r||14);
          if (dx*dx + dy*dy < rr*rr){
            const dmg = b.damage || b.dmg || 10;
            const conn = S.conns.get(S.roomCode);
            if (conn) send(conn, { t:'dmg', mpId:e.__mpId, amount:dmg });
            b.__mpConsumed = true;
            if (!b.pierce && !b.piercing) { b.dead = true; b.life = 0; }
            break;
          }
        }
      }
    }
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
}

function hostApplyDamage(mpId, amount, fromPeer){
  const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
  for (const e of g.enemies){
    if (e && e.__mpId === mpId){
      if (typeof e.hp === 'number') e.hp -= amount;
      if (fromPeer) e.__mpLastHitter = fromPeer;
      break;
    }
  }
}

// =============== BULLET BROADCAST (visual) ===============
// Cada peer manda um snapshot leve de SUAS bullets para os outros
// verem os tiros/ultimates (overlay-only, sem dano remoto).
function snapshotMyBullets(){
  const gg = window.game;
  if (!gg || !Array.isArray(gg.bullets)) return [];
  const out = [];
  const bs = gg.bullets;
  const N = Math.min(bs.length, 80); // cap pra evitar pacote gigante
  for (let i=0;i<N;i++){
    const b = bs[i];
    if (!b || b.dead || b.life<=0) continue;
    out.push({
      x: Math.round(b.x||0),
      y: Math.round(b.y||0),
      r: b.r||3,
      c: b.color || b.col || null
    });
  }
  return out;
}

function startBulletBroadcast(){
  if (S.bulletTimer) clearInterval(S.bulletTimer);
  S.bulletTimer = setInterval(()=>{
    if (!S.started) return;
    if (S.conns.size === 0) return;
    const snap = snapshotMyBullets();
    // hash leve para evitar reenviar quando nada mudou
    let h = snap.length;
    for (let i=0;i<snap.length;i+=4){ h = (h*131 + snap[i].x + snap[i].y*7)|0; }
    if (h === S.lastBulletHash) return; // nada mudou desde último envio
    S.lastBulletHash = h;
    if (S.isHost){
      bcast({ t:'bullets', b:snap });
    } else {
      const c = S.conns.get(S.roomCode);
      if (c) send(c, { t:'bullets', b:snap });
    }
  }, 1000/BULLET_HZ);
}

// =============== BOSS BROADCAST + ANÚNCIO ===============
function installBossWatcher(){
  if (!S.isHost) return;
  if (S._bossWatchTimer) clearInterval(S._bossWatchTimer);
  S._bossWatchTimer = setInterval(()=>{
    const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
    for (const e of g.enemies){
      if (!e || e.type!=='boss') continue;
      if (!e.__mpId) e.__mpId = S.enemyIdCounter++;
      if (S.bossAnnounced.has(e.__mpId)) continue;
      S.bossAnnounced.add(e.__mpId);
      const name = (e.bossType||'BOSS').toString().toUpperCase();
      const color = e.color||'#ff2e63';
      bcast({ t:'bossSpawn', name, color, id:e.__mpId });
      announceBoss(name, color);
    }
  }, 250);
}
function announceBoss(name, color){
  const root = document.getElementById('mp-root'); if (!root) return;
  const n = el('div', { style:{
    position:'absolute', top:'18%', left:'50%', transform:'translateX(-50%)',
    fontFamily:'Orbitron,sans-serif', fontWeight:'900', fontSize:'34px',
    letterSpacing:'.2em', color:'#fff', textShadow:`0 0 24px ${color}, 0 0 40px ${color}`,
    pointerEvents:'none', zIndex:99999, opacity:'0', transition:'all .5s ease-out'
  }}, `⚠ ${name} DESPERTOU ⚠`);
  root.append(n);
  requestAnimationFrame(()=>{ n.style.opacity='1'; n.style.transform='translate(-50%,12px)'; });
  setTimeout(()=>{ n.style.opacity='0'; }, 2400);
  setTimeout(()=>{ n.remove(); }, 3000);
}

// =============== SHOP SINCRONIZADA (continue compartilhado) ===============
// Lojas, loot e upgrades são LOCAIS (cada jogador compra o seu).
// Mas o "continuar" só avança a wave quando TODOS clicarem.
function installShopSync(){
  // Wrap openShopMenu (host) para anunciar abertura para todos
  if (S.isHost && typeof window.openShopMenu === 'function' && !window.openShopMenu.__mpShopWrap){
    const orig = window.openShopMenu;
    const wrap = function(){
      S.inShop = true; S.myShopReady = false; S.shopReadySet = new Set();
      bcast({ t:'shopOpen' });
      showShopWaitForMe();
      return orig.apply(this, arguments);
    };
    wrap.__mpShopWrap = true; wrap.__mpWrapped = true;
    try { window.openShopMenu = wrap; } catch(e){}
  }
  // Wrap startNextWave — v13: SÓ intercepta se uma loja estiver realmente
  // aberta. Caso contrário (auto-advance entre waves, rift loop, etc.) o
  // original roda normalmente em ambos os lados. Isso elimina o loop de
  // "Esperando jogadores" travado e o contador de waves disparando sozinho.
  if (typeof window.startNextWave === 'function' && !window.startNextWave.__mpReadyWrap){
    const orig = window.startNextWave;
    const wrap = function(){
      // single-player, antes da partida, ou sem loja aberta -> passa direto
      if (!S.started || S.conns.size === 0 || !S.inShop){
        S.inShop = false; S.myShopReady = false; S.shopReadySet = new Set(); hideShopWait();
        return orig.apply(this, arguments);
      }
      if (!S.myShopReady){
        S.myShopReady = true;
        if (S.isHost){
          S.shopReadySet.add(S.myId);
          evaluateShopReady();
        } else {
          const c = S.conns.get(S.roomCode);
          if (c) send(c, { t:'shopReady' });
          showShopWaitForMe();
        }
      }
      return;
    };
    wrap.__mpReadyWrap = true; wrap.__mpWrapped = true;
    try {
      window.__mpOrigStartNextWave = orig;
      window.startNextWave = wrap;
    } catch(e){}
  }
}

function totalActivePlayers(){
  let n = 0;
  for (const p of S.players.values()){ if (p.classKey) n++; }
  return Math.max(1, n);
}

function evaluateShopReady(){
  if (!S.isHost) return;
  const total = totalActivePlayers();
  const ready = S.shopReadySet.size;
  // re-render overlay próprio se o host estiver pronto
  if (S.myShopReady) showShopWaitForMe();
  // broadcast progresso pros clientes
  bcast({ t:'shopWait', ready, total });
  if (ready >= total){
    // todos prontos! avança a wave de verdade
    S.inShop = false; S.myShopReady = false; S.shopReadySet = new Set();
    hideShopWait();
    bcast({ t:'shopResume' });
    try {
      // limpa flags locais do host antes (jogo original pode ter setado)
      const gg = window.game;
      if (gg){ gg.shopPending = false; gg.betweenWaves = false; gg.running = true; }
      const ov = document.getElementById('overlay');
      if (ov){ ov.classList.add('hidden'); ov.style.display='none'; }
      if (typeof window.__mpOrigStartNextWave === 'function') {
        window.__mpOrigStartNextWave();
      }
    } catch(e){ warn('startNextWave erro:', e); }
  }
}

function broadcastShopWait(){
  if (!S.isHost) return;
  bcast({ t:'shopWait', ready: S.shopReadySet.size, total: totalActivePlayers() });
}

function showShopWaitForMe(){
  const total = totalActivePlayers();
  const ready = S.isHost ? S.shopReadySet.size : 1; // cliente: pelo menos ele
  renderShopWait(ready, total);
}

function renderShopWait(ready, total){
  if (!S.myShopReady) return; // só mostra para quem já clicou em continuar
  if (!S.shopWaitEl){
    S.shopWaitEl = el('div', { id:'mp-shop-wait', style:{
      position:'fixed', top:'50%', left:'50%', transform:'translate(-50%,-50%)',
      zIndex: 100001, pointerEvents:'none',
      background:'rgba(6,8,18,0.92)', border:'1px solid rgba(120,200,255,0.4)',
      borderRadius:'14px', padding:'18px 26px', textAlign:'center',
      fontFamily:"'Orbitron','Rajdhani',sans-serif", color:'#eef2ff',
      boxShadow:'0 12px 48px rgba(0,0,0,0.7), 0 0 32px rgba(97,218,251,0.25)'
    }});
    document.body.append(S.shopWaitEl);
  }
  S.shopWaitEl.innerHTML = `
    <div style="font-size:11px;letter-spacing:.25em;opacity:.6;margin-bottom:6px">CO-OP</div>
    <div style="font-size:18px;font-weight:800;letter-spacing:.1em">⏳ Esperando jogadores</div>
    <div style="font-size:28px;font-weight:900;color:#61dafb;margin-top:6px">${ready}/${total}</div>
    <div style="font-size:11px;opacity:.6;margin-top:8px">A próxima wave começa quando todos confirmarem.</div>
  `;
  S.shopWaitEl.style.display = '';
}
function hideShopWait(){
  if (S.shopWaitEl) S.shopWaitEl.style.display = 'none';
}

function clientHandleShopOpen(){
  const gg = window.game; if (!gg) return;
  S.inShop = true; S.myShopReady = false;
  gg.shopPending = true; gg.running = false;
  try { if (typeof window.__origOpenShopMenu === 'function') window.__origOpenShopMenu();
        else if (typeof window.openShopMenu === 'function') window.openShopMenu(); } catch(e){}
}
function clientHandleShopResume(){
  const gg = window.game; if (!gg) return;
  S.inShop = false; S.myShopReady = false;
  hideShopWait();
  const ov = document.getElementById('overlay');
  if (ov){ ov.classList.add('hidden'); ov.style.display='none'; }
  gg.shopPending = false; gg.betweenWaves = false; gg.running = true;
  // chama startNextWave ORIGINAL no cliente para configurar estado local da nova wave
  try {
    if (typeof window.__mpOrigStartNextWave === 'function'){
      window.__mpOrigStartNextWave();
    }
  } catch(e){}
}

// =============== CRÉDITO DE KILLS PARA O CLIENTE (XP/Score apenas) ===============
// OURO agora é POOL COMPARTILHADO (vê startGoldPoolSync). Aqui só XP/score.
function installHostKillCredit(){
  if (S._killCreditTimer) clearInterval(S._killCreditTimer);
  let prev = new Map();
  S._killCreditTimer = setInterval(()=>{
    const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
    const cur = new Map();
    for (const e of g.enemies) if (e && e.__mpId) cur.set(e.__mpId, e);
    for (const [id, e] of prev){
      if (cur.has(id)) continue;
      const peer = e.__mpLastHitter;
      // Ouro vai pro pool com 1.5x, MAS:
      // - se foi o host quem matou, o jogo original já creditou gg.gold;
      //   nesse caso só aplicamos o BÔNUS de 0.5x (1.5x - 1.0x) para evitar dobrar.
      // - se foi cliente, adicionamos o valor cheio (cliente não toca em gg.gold).
      const baseGold = Math.max(1, Math.floor((e.value||10) * 0.5));
      if (!peer || peer === S.myId){
        // host matou — bônus apenas; startGoldPoolSync vai pegar o ganho base via delta
        const bonus = Math.max(0, Math.floor(baseGold * (GOLD_DROP_MULT - 1)));
        S.goldPool += bonus;
      } else {
        S.goldPool += Math.floor(baseGold * GOLD_DROP_MULT);
      }
      // XP/score para o cliente que deu o último hit
      if (peer && peer !== S.myId){
        const c = S.conns.get(peer); if (c){
          const xp   = Math.max(1, Math.floor((e.value||10) * 0.4));
          const score= e.value||10;
          const boss = e.type === 'boss';
          send(c, { t:'youKilled', xp, score, boss, name:(boss?(e.bossType||'BOSS'):e.type||'')});
        }
      }
    }
    prev = cur;
  }, 200);
}

function clientApplyKill(d){
  const gg = window.game; if (!gg) return;
  // OURO não aqui (vem por goldSync)
  gg.score = (gg.score||0) + (d.score||0);
  if (gg.player){
    gg.player.xp = (gg.player.xp||0) + (d.xp||0);
    if (gg.player.xpNext && gg.player.xp >= gg.player.xpNext){
      gg.player.xp -= gg.player.xpNext;
      gg.player.level = (gg.player.level||1) + 1;
      gg.player.xpNext = Math.floor(gg.player.xpNext * 1.35);
    }
  }
  try { if (typeof window.updateHUD === 'function') window.updateHUD(); } catch(_){}
  if (d.boss) announceBoss('BOSS DERROTADO', '#4ce0b3');
}

// =============== OURO COMPARTILHADO (pool) ===============
// Host é source-of-truth. Mantém S.goldPool. Detecta delta local
// (host ganha por kill = já contabilizado em installHostKillCredit;
// gastos locais detectados via delta negativo). Clientes só reportam DELTAS.
function startGoldPoolSync(){
  // inicializa pool com gold local
  const gg = window.game;
  if (S.isHost && gg){
    S.goldPool = gg.gold || 0;
    S.lastSyncedGold = S.goldPool;
  } else if (gg){
    S.lastSyncedGold = gg.gold || 0;
  }
  if (S.goldTimer) clearInterval(S.goldTimer);
  S.goldTimer = setInterval(()=>{
    if (!S.started) return;
    const gg = window.game; if (!gg) return;
    const cur = gg.gold || 0;
    const delta = cur - S.lastSyncedGold;
    if (S.isHost){
      // POSITIVOS: host matou um inimigo — o ganho-base (delta) entra no
      // pool aqui; o BÔNUS de 1.5x é aplicado em installHostKillCredit.
      // NEGATIVOS: host comprou algo — debita do pool compartilhado.
      if (delta > 0){
        S.goldPool += delta;
      } else if (delta < 0){
        S.goldPool = Math.max(0, S.goldPool + delta);
      }
      // mantém gg.gold do host alinhado ao pool e propaga
      if (gg.gold !== S.goldPool){
        gg.gold = S.goldPool;
        try { if (typeof window.updateHUD === 'function') window.updateHUD(); } catch(_){}
      }
      S.lastSyncedGold = gg.gold;
      broadcastGoldPool();
    } else {
      // cliente: só reporta GASTOS (delta negativo); ganhos vêm via goldSync
      if (delta < 0){
        const c = S.conns.get(S.roomCode);
        if (c) send(c, { t:'goldDelta', delta });
        S.lastSyncedGold = cur;
      } else if (delta > 0){
        // cliente nunca deveria ganhar gold local (kills via host); se ganhou,
        // desfaz para evitar pool fantasma
        gg.gold = S.lastSyncedGold;
      }
    }
  }, 1000/GOLD_SYNC_HZ);
}

function broadcastGoldPool(){
  if (!S.isHost) return;
  bcast({ t:'goldSync', pool: S.goldPool });
}

// =============== PAUSE SINCRONIZADO ===============
function startPauseWatcher(){
  // Monitora gg.paused; quando o JOGADOR LOCAL pausa (não-remoto), envia evento.
  if (S._pauseTimer) clearInterval(S._pauseTimer);
  S._pauseTimer = setInterval(()=>{
    if (!S.started) return;
    const gg = window.game; if (!gg) return;
    const isPaused = !!gg.paused;
    // Se outro player pausou, força local
    if (S.pausedRemoteBy && S.pausedRemoteBy !== S.myId){
      if (!isPaused){ gg.paused = true; }
      gg.running = false;
      // garante overlay visível
      if (!S.pauseOverlayEl || S.pauseOverlayEl.style.display === 'none'){
        const pName = (S.players.get(S.pausedRemoteBy)||{}).name || 'Player';
        showPauseOverlay(pName);
      }
      // esconde menu de pause local do jogo (se aparecer)
      hideLocalPauseMenu();
      S.lastPausedFlag = true;
      return;
    }
    // local: se pausou agora e não há pause remoto, anuncia
    if (isPaused && !S.lastPausedFlag && !S.pausedRemoteBy){
      S.iAmPauser = true;
      if (S.isHost){
        S.pausedRemoteBy = S.myId;
        const pName = S.myName;
        bcast({ t:'pauseRemote', by:S.myId, byName:pName });
      } else {
        const c = S.conns.get(S.roomCode);
        if (c) send(c, { t:'paused' });
      }
    } else if (!isPaused && S.lastPausedFlag && S.iAmPauser){
      S.iAmPauser = false;
      if (S.isHost){
        S.pausedRemoteBy = null;
        bcast({ t:'resumeRemote' });
      } else {
        const c = S.conns.get(S.roomCode);
        if (c) send(c, { t:'unpaused' });
      }
    }
    S.lastPausedFlag = isPaused;
  }, 120);
}

function applyRemotePause(byId, byName){
  if (byId === S.myId) return; // sou eu mesmo, não preciso de overlay
  const gg = window.game;
  if (gg){ gg.paused = true; gg.running = false; }
  showPauseOverlay(byName||'Player');
  hideLocalPauseMenu();
}
function applyRemoteResume(){
  hidePauseOverlay();
  const gg = window.game;
  if (gg){
    gg.paused = false;
    if (!S.inShop && !gg.__mpDowned) gg.running = true;
  }
}

function showPauseOverlay(name){
  if (!S.pauseOverlayEl){
    S.pauseOverlayEl = el('div', { id:'mp-pause-overlay', style:{
      position:'fixed', inset:'0', zIndex: 100002, pointerEvents:'none',
      display:'flex', alignItems:'center', justifyContent:'center',
      background:'rgba(2,4,12,0.55)', backdropFilter:'blur(6px)'
    }});
    document.body.append(S.pauseOverlayEl);
  }
  S.pauseOverlayEl.innerHTML = `
    <div style="text-align:center;font-family:'Orbitron','Rajdhani',sans-serif;color:#eef2ff">
      <div style="font-size:13px;letter-spacing:.3em;opacity:.7;margin-bottom:10px">CO-OP</div>
      <div style="font-size:44px;font-weight:900;letter-spacing:.15em;
                  background:linear-gradient(90deg,#61dafb,#9f6cff);
                  -webkit-background-clip:text;-webkit-text-fill-color:transparent">JOGO PAUSADO</div>
      <div style="font-size:18px;margin-top:14px;opacity:.9">por <b style="color:#ffd166">${name}</b></div>
      <div style="font-size:11px;opacity:.55;margin-top:18px;letter-spacing:.15em">aguardando retomada...</div>
    </div>
  `;
  S.pauseOverlayEl.style.display = 'flex';
}
function hidePauseOverlay(){
  if (S.pauseOverlayEl) S.pauseOverlayEl.style.display = 'none';
}
function hideLocalPauseMenu(){
  // tenta esconder menus de pause comuns do jogo (best-effort, IDs/classes comuns)
  const sels = ['#pauseMenu','#pauseOverlay','.pauseMenu','.pause-menu','#pause'];
  for (const s of sels){
    const n = document.querySelector(s);
    if (n){ n.style.display = 'none'; }
  }
}

function startEnemySync(){
  if (!S.isHost) return;
  if (S._enemyTimer) clearInterval(S._enemyTimer);
  S._enemyTimer = setInterval(()=>{
    const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
    const list = [];
    for (const e of g.enemies){
      if (!e) continue;
      if (!e.__mpId) e.__mpId = S.enemyIdCounter++;
      list.push({
        i: e.__mpId,
        x: Math.round(e.x||0), y: Math.round(e.y||0),
        h: Math.max(0, e.hp||0), M: e.maxHp||e.hp||1,
        r: e.r||14,
        t: e.type||'normal',
        b: !!e.boss, el: !!e.elite,
        c: e.color||null
      });
    }
    bcast({ t:'enemies', list, wave: g.wave||g.currentWave||1 });
  }, 1000/ENEMY_HZ);
}

function applyEnemySnapshot(list, wave){
  const g = window.game; if (!g) return;
  if (!Array.isArray(g.enemies)) g.enemies = [];
  // v13: muta in-place. Substituir g.enemies = next quebrava referências
  // mantidas por sub-sistemas patched do jogo (drones, AoE, contagem da wave).
  const existing = new Map();
  for (const e of g.enemies) if (e && e.__mpId) existing.set(e.__mpId, e);
  const incoming = new Set();
  const next = [];
  for (const s of list){
    incoming.add(s.i);
    let e = existing.get(s.i);
    if (!e){ e = makeShellEnemy(s); }
    else {
      e.x = s.x; e.y = s.y; e.hp = s.h; e.maxHp = s.M; e.r = s.r;
      e.type = s.t || e.type; e.boss = !!s.b; e.elite = !!s.el;
      if (s.c) e.color = s.c;
      e.dead = false;
    }
    next.push(e);
  }
  g.enemies.length = 0;
  for (const e of next) g.enemies.push(e);
  if (wave) { g.wave = wave; g.currentWave = wave; }
  // suprime spawner local do cliente (algumas waves agendam timers internos)
  if (!S.isHost){
    g.spawnCd = 9999;
    g.spawnQueue = []; g.pendingSpawns = []; g.toSpawn = 0;
    g.enemiesSpawnedThisWave = (g.waveEnemyCount||g.toSpawnTotal||list.length);
  }
}

function makeShellEnemy(s){
  return {
    __mpId: s.i, __mpShell: true,
    x: s.x, y: s.y, vx:0, vy:0,
    hp: s.h, maxHp: s.M, r: s.r||14,
    type: s.t||'normal', boss: !!s.b, elite: !!s.el,
    color: s.c||'#ff6b9d', dead: false,
    update(){}, draw(){},
  };
}

// ============== HOST: MIRA NOS DOIS PLAYERS ==============
function listLivePlayers(){
  const arr = [];
  for (const p of S.players.values()){
    if (!p.classKey) continue;
    if (p.down) continue;
    arr.push(p);
  }
  return arr;
}
function pickAggroTarget(x,y){
  // 70% mais próximo, 30% aleatório entre vivos — evita stacking total no host.
  const live = listLivePlayers();
  if (live.length === 0) return null;
  if (live.length === 1) return live[0];
  if (Math.random() < 0.30) return live[Math.floor(Math.random()*live.length)];
  let best=null, bd=Infinity;
  for (const p of live){
    const d = (p.x-x)*(p.x-x) + (p.y-y)*(p.y-y);
    if (d<bd){ bd=d; best=p; }
  }
  return best;
}

function startHostTargetingLoop(){
  if (!S.isHost) return;
  const myGen = ++S._bulletHookGen; // reusa gen p/ invalidar loops antigos
  let last = performance.now();
  const tick = ()=>{
    if (myGen !== S._bulletHookGen) return;
    if (!S.started) return;
    const now = performance.now();
    const dt = Math.min(0.05, (now-last)/1000);
    last = now;
    const g = window.game;
    if (g && Array.isArray(g.enemies)){
      const live = listLivePlayers();
      if (live.length >= 1){
        for (const e of g.enemies){
          if (!e || e.__mpShell) continue;
          // sticky target: troca alvo a cada ~1.5s para parecer natural
          if (!e.__mpAggroT || now - e.__mpAggroT > 1500){
            e.__mpAggro = pickAggroTarget(e.x||0, e.y||0);
            e.__mpAggroT = now;
          }
          const tgt = e.__mpAggro || pickAggroTarget(e.x||0, e.y||0);
          if (!tgt) continue;
          try {
            e.target = tgt;
            e.targetX = tgt.x; e.targetY = tgt.y;
          } catch(_){}
          const dx = tgt.x - (e.x||0), dy = tgt.y - (e.y||0);
          const d = Math.hypot(dx,dy) || 1;
          const speed = (e.speed || e.spd || 60) * 0.35;
          e.x = (e.x||0) + (dx/d) * speed * dt;
          e.y = (e.y||0) + (dy/d) * speed * dt;
        }
      }
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

// ============== HOST: DANO NOS DOIS PLAYERS ==============
function contactDamageFor(e){
  if (!e) return 0;
  if (e.type === 'tank')   return 20;
  if (e.type === 'boss')   return 24;
  if (e.elite)             return 20;
  return 13;
}

function startHostDamageLoop(){
  if (!S.isHost) return;
  const TICK = 1000 / HOST_DMG_HZ;
  if (S._hostDmgTimer) clearInterval(S._hostDmgTimer);
  S._hostDmgTimer = setInterval(()=>{
    const g = window.game; if (!g) return;
    const others = [...S.players.values()].filter(p => p.id !== S.myId && p.classKey && !p.down);
    if (others.length === 0) return;
    const dt = TICK / 1000;

    for (const rp of others){
      if (rp.__mpHurtCd == null) rp.__mpHurtCd = 0;
      rp.__mpHurtCd = Math.max(0, rp.__mpHurtCd - dt);

      let pendingHit = 0;
      let dotHit = 0;

      if (rp.__mpHurtCd <= 0 && Array.isArray(g.enemies)){
        for (const e of g.enemies){
          if (!e || e.__mpShell || e.dead) continue;
          const er = (e.r||14) + 14;
          const dx = (e.x||0) - rp.x, dy = (e.y||0) - rp.y;
          if (dx*dx + dy*dy < er*er){
            pendingHit = Math.max(pendingHit, contactDamageFor(e));
            if (e.type === 'bomber'){
              pendingHit = Math.max(pendingHit, 35);
              e.hp = 0; e.dead = true;
            }
            break;
          }
        }
      }

      if (Array.isArray(g.enemyBullets)){
        for (let i = g.enemyBullets.length - 1; i >= 0; i--){
          const b = g.enemyBullets[i];
          if (!b) continue;
          const br = (b.r||5) + 14;
          const dx = (b.x||0) - rp.x, dy = (b.y||0) - rp.y;
          if (dx*dx + dy*dy < br*br){
            if (rp.__mpHurtCd <= 0){
              pendingHit = Math.max(pendingHit, (b.damage || 10));
              g.enemyBullets.splice(i, 1);
            }
          }
        }
      }

      const total = pendingHit + dotHit;
      if (total > 0){
        rp.hp = Math.max(0, (rp.hp||0) - total);
        if (pendingHit > 0) rp.__mpHurtCd = 0.55;
        const c = S.conns.get(rp.id);
        if (c) send(c, { t:'youHit', amount: total });
        if (rp.hp <= 0 && !rp.down){
          rp.down = true;
          broadcastLobby();
        }
      }
    }
  }, TICK);
}


// ===================== SYNC DE JOGADORES =====================
function startTickLoop(){
  if (S._tickTimer) clearInterval(S._tickTimer);
  S._tickTimer = setInterval(()=>{
    const g = window.game; if (!g) return;
    const me = S.players.get(S.myId); if (!me) return;
    const pl = g.player || (g.players && g.players[0]) || null;
    if (pl){
      me.x = pl.x||0; me.y = pl.y||0;
      me.hp = pl.hp||0; me.maxHp = pl.maxHp||100;
      me.down = !!(pl.dead || pl.down || me.hp<=0);
      // v13: status replicado p/ render proxy
      me.shield    = pl.shield||0;
      me.maxShield = pl.maxShield||0;
      me.cloak     = pl.cloakActive||0;
      me.hurt      = pl.hurtCd||0;
      me.rail      = pl.railPierceMode||0;
      me.r         = pl.r||14;
      try {
        const m = window.mouse;
        if (m && typeof m.x === 'number')
          me.aim = Math.atan2((m.y||pl.y)-pl.y, (m.x||pl.x)-pl.x);
      } catch(_){}
    }
    me.wave = g.wave || g.currentWave || me.wave;
    me.score = g.score || me.score;
    if (S.isHost) broadcastState();
    else {
      const c = S.conns.get(S.roomCode);
      if (c) send(c, { t:'state', s:{
        x:me.x,y:me.y,hp:me.hp,maxHp:me.maxHp,
        wave:me.wave,score:me.score,down:me.down
      }});
    }
    renderTeam();
  }, 1000/TICK_HZ);
}

// ===================== OVERLAY =====================
let oc=null, octx=null;
function startOverlay(){
  if (oc) return;
  const gameCanvas = document.querySelector('canvas#game') || document.querySelector('canvas');
  if (!gameCanvas) return;
  oc = el('canvas', { style:{
    position:'fixed', pointerEvents:'none', zIndex:9998, left:'0', top:'0'
  }});
  document.body.append(oc);
  octx = oc.getContext('2d');
  const resize = ()=>{
    const r = gameCanvas.getBoundingClientRect();
    oc.width = r.width; oc.height = r.height;
    oc.style.left = r.left+'px'; oc.style.top = r.top+'px';
    oc.style.width = r.width+'px'; oc.style.height = r.height+'px';
  };
  resize();
  window.addEventListener('resize', resize);
  const ro = new ResizeObserver(resize); ro.observe(gameCanvas);

  const draw = ()=>{
    if (!octx) return;
    octx.clearRect(0,0,oc.width,oc.height);
    const g = window.game;
    const gc = document.querySelector('canvas#game') || document.querySelector('canvas');
    const scale = gc ? oc.width / gc.width : 1;

    // CLIENTE: desenha inimigos compartilhados (shells)
    if (!S.isHost && g && Array.isArray(g.enemies)){
      for (const e of g.enemies){
        if (!e || !e.__mpShell) continue;
        const sx = (e.x||0) * scale;
        const sy = (e.y||0) * scale;
        octx.fillStyle = e.boss ? '#ff4d6d' : (e.color || '#ff8866');
        octx.beginPath();
        octx.arc(sx, sy, (e.r||14)*scale, 0, Math.PI*2);
        octx.fill();
        if (e.maxHp){
          const bw = (e.r||14)*2*scale;
          octx.fillStyle='rgba(0,0,0,0.6)';
          octx.fillRect(sx-bw/2, sy-(e.r||14)*scale-6, bw, 3);
          octx.fillStyle='#ff4d6d';
          octx.fillRect(sx-bw/2, sy-(e.r||14)*scale-6, bw*Math.max(0,e.hp/e.maxHp), 3);
        }
      }
    }

    // BULLETS REMOTAS (visual-only)
    octx.globalAlpha = 0.85;
    for (const [pid, arr] of S.remoteBullets){
      if (!Array.isArray(arr)) continue;
      for (const b of arr){
        const sx = (b.x||0) * scale;
        const sy = (b.y||0) * scale;
        const r  = Math.max(1.5, (b.r||3) * scale);
        octx.fillStyle = b.c || '#9bedff';
        octx.beginPath();
        octx.arc(sx, sy, r, 0, Math.PI*2);
        octx.fill();
        // glow leve
        octx.strokeStyle = 'rgba(255,255,255,0.5)';
        octx.lineWidth = 1;
        octx.stroke();
      }
    }
    octx.globalAlpha = 1;

    // Outros jogadores — v13: tenta render proxy (sprite/skin do jogo) e
    // cai pra bolinha simples se algo falhar.
    for (const p of S.players.values()){
      if (p.id === S.myId) continue;
      const sx = (p.x||0) * scale;
      const sy = (p.y||0) * scale;
      let drawnViaProxy = false;
      if (!p.down) drawnViaProxy = tryProxyDrawPeer(p);
      if (!drawnViaProxy){
        octx.globalAlpha = p.down ? 0.45 : 0.9;
        octx.fillStyle = p.down ? '#ff4d6d' : (p.color || '#61dafb');
        octx.beginPath(); octx.arc(sx,sy,14*scale,0,Math.PI*2); octx.fill();
        octx.strokeStyle = '#fff'; octx.lineWidth = 2; octx.stroke();
        octx.globalAlpha = 1;
      }
      octx.fillStyle='#fff'; octx.font=`bold ${13*scale|0}px 'Rajdhani',sans-serif`; octx.textAlign='center';
      octx.fillText(p.name, sx, sy - 22*scale);
      octx.fillStyle='rgba(0,0,0,0.6)'; octx.fillRect(sx-20*scale, sy-34*scale, 40*scale, 4*scale);
      octx.fillStyle='#4ce0b3';
      octx.fillRect(sx-20*scale, sy-34*scale, 40*scale*Math.max(0,(p.hp||0)/(p.maxHp||1)), 4*scale);
      if (p.down){
        octx.fillStyle='#ffd166';
        octx.fillText('Segure F para reviver', sx, sy + 30*scale);
      }
    }
    // bullets remotas agora também tentam usar o renderer do jogo (skin/cor por classe)
    tryProxyDrawPeerBullets();
    handleRevive();
    requestAnimationFrame(draw);
  };
  draw();
}

// ===================== REVIVE =====================
const keysDown = {};
window.addEventListener('keydown', e => keysDown[(e.key||'').toLowerCase()] = true);
window.addEventListener('keyup',   e => keysDown[(e.key||'').toLowerCase()] = false);

function handleRevive(){
  if (!S.started) return;
  const me = S.players.get(S.myId); if (!me) return;
  if (me.down) { S.reviveTarget = null; return; }
  let target=null, best=REVIVE_RANGE;
  for (const p of S.players.values()){
    if (p.id===S.myId || !p.down) continue;
    const d = Math.hypot((p.x||0)-(me.x||0), (p.y||0)-(me.y||0));
    if (d<best){ best=d; target=p; }
  }
  if (target && keysDown['f']){
    if (S.reviveTarget !== target.id){
      S.reviveTarget = target.id; S.reviveStart = Date.now();
    }
    const pct = Math.min(1, (Date.now()-S.reviveStart)/REVIVE_TIME);
    drawReviveBar(target, pct);
    if (pct >= 1){
      if (S.isHost){
        const tp = S.players.get(target.id);
        if (tp){
          tp.down = false;
          tp.hp = Math.max(1, Math.floor(tp.maxHp * REVIVE_HP_PCT));
        }
        const c = S.conns.get(target.id);
        if (c) send(c, { t:'youRevived' });
        broadcastLobby();
      } else {
        const c = S.conns.get(S.roomCode);
        if (c) send(c, { t:'revive', target: target.id });
      }
      S.reviveTarget = null;
    }
  } else { S.reviveTarget = null; }
}

function drawReviveBar(p, pct){
  if (!octx) return;
  const gc = document.querySelector('canvas#game') || document.querySelector('canvas');
  const scale = gc ? oc.width / gc.width : 1;
  const sx = (p.x||0) * scale;
  const sy = (p.y||0) * scale;
  octx.fillStyle='rgba(0,0,0,0.7)'; octx.fillRect(sx-24*scale, sy+36*scale, 48*scale, 6*scale);
  octx.fillStyle='#ffd166'; octx.fillRect(sx-24*scale, sy+36*scale, 48*scale*pct, 6*scale);
}

// ===================== RENDER CHAT/TEAM =====================
function renderChat(){
  if (!UI.chatLog) return;
  UI.chatLog.innerHTML = '';
  for (const m of S.chat){
    const d = el('div', { style:{
      background:'rgba(6,8,18,0.75)', border:'1px solid rgba(120,200,255,0.15)',
      padding:'4px 10px', borderRadius:'8px', width:'fit-content',
      fontSize:'12px', textShadow:'0 1px 2px #000'
    }});
    d.append(el('b', { style:{color:'#61dafb'} }, m.from+': '));
    d.append(document.createTextNode(m.msg));
    UI.chatLog.append(d);
  }
}

function renderTeam(){
  if (!UI.team) return;
  const classes = new Map(getClasses().map(c=>[c.key,c]));
  UI.team.innerHTML = '';
  UI.team.append(el('div', { style:{
    fontSize:'10px', letterSpacing:'.15em', opacity:.6, marginBottom:'6px', fontWeight:'700'
  }}, 'EQUIPE · ' + (DIFFICULTY[S.difficulty]?.label || '')));
  for (const p of S.players.values()){
    const c = classes.get(p.classKey);
    const row = el('div', { style:{
      display:'flex', justifyContent:'space-between', alignItems:'center', gap:'6px',
      padding:'4px 0', opacity: p.down ? 0.5 : 1
    }});
    row.append(el('span', { style:{display:'flex',alignItems:'center',gap:'4px'} },
      el('span', {}, c?c.icon:'❔'),
      el('span', { style:{fontWeight:'600'} },
        p.name + (p.id===S.myId?' (você)':'') + (p.down?' 💀':''))));
    row.append(el('span', { style:{fontSize:'10px',opacity:.8} },
      `W${p.wave||1} · ${Math.max(0,p.hp|0)}/${p.maxHp|0}`));
    UI.team.append(row);
  }
}

// ===================== v13: PROXY RENDER DE PEERS =====================
// Reaproveita window.drawPlayer / window.drawBullets do jogo (que foi
// monkey-patched várias vezes pelos updates Eclipse/Hero/Skin/etc.) trocando
// temporariamente game.player, game.classKey, game.bullets, game.mouse para
// o estado do peer. Assim cada jogador remoto aparece com o sprite, skin,
// shield, dash trail e efeitos da SUA classe — sem reimplementar nada.
//
// Render acontece no canvas#game (mesmo do jogo) ANTES de cada frame do
// overlay; isso significa que efeitos do peer ficam atrás do HUD, igual aos
// do jogador local.

function _gameCanvasCtx(){
  const c = document.querySelector('canvas#game') || document.querySelector('canvas');
  if (!c) return null;
  return { c, ctx: c.getContext('2d') };
}

function tryProxyDrawPeer(p){
  try {
    const g = window.game; if (!g || !g.player) return false;
    const fn = window.drawPlayer; if (typeof fn !== 'function') return false;
    const cc = _gameCanvasCtx(); if (!cc) return false;

    // monta um "player virtual" reaproveitando defaults seguros do meu player
    const peerPlayer = Object.assign({}, g.player, {
      x: p.x||0, y: p.y||0,
      hp: p.hp||1, maxHp: p.maxHp||1,
      shield: p.shield||0, maxShield: p.maxShield|| (p.shield? p.shield: 1),
      cloakActive: p.cloak||0,
      hurtCd: p.hurt||0,
      railPierceMode: p.rail||0,
      trail: [], // evita usar trail do meu player
      r: p.r || g.player.r || 14,
      down: !!p.down, dead: false,
    });

    // mouse fake apontando para a direção do peer (ângulo enviado no tick)
    const fakeMouse = (typeof p.aim === 'number')
      ? { x: peerPlayer.x + Math.cos(p.aim)*40, y: peerPlayer.y + Math.sin(p.aim)*40 }
      : { x: peerPlayer.x + 40, y: peerPlayer.y };

    const savedPlayer = g.player;
    const savedClass  = g.classKey;
    const savedMouse  = window.mouse;
    g.player    = peerPlayer;
    g.classKey  = p.classKey || savedClass;
    window.mouse = fakeMouse;
    try { fn(); }
    finally {
      g.player = savedPlayer;
      g.classKey = savedClass;
      window.mouse = savedMouse;
    }
    return true;
  } catch(_){ return false; }
}

function tryProxyDrawPeerBullets(){
  try {
    const g = window.game; if (!g) return false;
    const fn = window.drawBullets; if (typeof fn !== 'function') return false;
    if (S.remoteBullets.size === 0) return false;
    const savedBullets = g.bullets;
    const savedClass   = g.classKey;
    // junta tudo num array efêmero — drawBullets do jogo só itera g.bullets
    const all = [];
    for (const [pid, arr] of S.remoteBullets){
      const peer = S.players.get(pid);
      const cls  = peer?.classKey || savedClass;
      if (!Array.isArray(arr)) continue;
      for (const b of arr){
        all.push({
          x: b.x||0, y: b.y||0,
          r: b.r||3,
          color: b.c || null,
          damage: 0, dmg: 0,
          dead: false, life: 1,
          __mpRemote: true, __classKey: cls,
        });
      }
    }
    g.bullets = all;
    try { fn(); } finally { g.bullets = savedBullets; }
    return true;
  } catch(_){ return false; }
}

// ===================== v13: PAUSE EXPLÍCITO POR TECLA =====================
// O polling de gg.paused era frágil (alguns updates do jogo ignoram a flag
// ou usam outra). Aqui interceptamos P/Escape diretamente e propagamos.
window.addEventListener('keydown', (e)=>{
  if (!S.started) return;
  const k = (e.key||'').toLowerCase();
  if (k !== 'p' && k !== 'escape') return;
  // se outro player já pausou, só permite ao próprio pauser despausar
  if (S.pausedRemoteBy && S.pausedRemoteBy !== S.myId) return;
  const gg = window.game; if (!gg) return;
  const willPause = !gg.paused;
  gg.paused = willPause;
  gg.running = !willPause && !gg.__mpDowned && !S.inShop;
  if (willPause){
    S.iAmPauser = true;
    S.pausedRemoteBy = S.myId;
    if (S.isHost) bcast({ t:'pauseRemote', by:S.myId, byName:S.myName });
    else { const c = S.conns.get(S.roomCode); if (c) send(c, { t:'paused' }); }
  } else {
    S.iAmPauser = false;
    S.pausedRemoteBy = null;
    hidePauseOverlay();
    if (S.isHost) bcast({ t:'resumeRemote' });
    else { const c = S.conns.get(S.roomCode); if (c) send(c, { t:'unpaused' }); }
  }
}, true);

// ===================== v13: GUARDA "ESPERANDO JOGADORES" =====================
// só permite o overlay aparecer quando uma loja está realmente aberta.
const _origShowShopWait = showShopWaitForMe;
showShopWaitForMe = function(){
  if (!S.inShop) { hideShopWait(); return; }
  return _origShowShopWait.apply(this, arguments);
};


function boot(){
  if (!window.Peer){
    warn('PeerJS ainda não disponível, retentando...');
    return setTimeout(boot, 400);
  }
  buildUI();
  log('Multiplayer pronto.', VERSION,
      'Bridge:', window.__MP_BRIDGE_READY__ ? '✓' : '✗',
      'Classes:', getClasses().length);
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();

})();
