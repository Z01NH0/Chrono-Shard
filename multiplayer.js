/* ============================================================
   CHRONO SHARDS — MULTIPLAYER v14 (PeerJS P2P Co-op)
   ============================================================
   ARQUITETURA:
   • Host é autoridade de TUDO: inimigos, dano, wave, ouro
   • Cliente roda seu próprio jogo (player, bullets, skills)
   • Shell enemies no cliente usam interceptor de HP via
     Object.defineProperty — nunca morrem localmente, mas o
     dano acumulado é enviado ao host via flush timer (30Hz)
   • Timers de shell (shotTimer, summonTimer, etc.) são
     interceptados → inimigos não atiram no cliente
   • hurtCd do cliente é mantido alto → dano de contato
     é calculado só pelo host e enviado via 'youHit'
   • O game engine do cliente renderiza os shells naturalmente
     (drawEnemies usa os campos do shell)
   • Overlay canvas renderiza apenas: jogador remoto + bullets
     remotos + barra de revive
   • Sync de inimigos a 30Hz com velocidade para dead reckoning
   • Gold pool compartilhado com protocolo delta limpo
   • Shop gate: ambos confirmam antes da próxima wave
   ============================================================ */
(() => {
'use strict';

// ========================= CONFIG =========================
const VERSION       = 'mp-v14';
const TICK_HZ       = 20;
const ENEMY_HZ      = 30;
const BULLET_HZ     = 20;
const DMG_FLUSH_HZ  = 30;
const HOST_DMG_HZ   = 20;
const GOLD_HZ       = 5;
const REVIVE_TIME   = 8000;
const REVIVE_RANGE  = 110;
const REVIVE_HP_PCT = 0.25;
const HURTCD_LOCK   = 9999;  // mantém cliente imune a dano local
const HP_BUFFER     = 100000; // buffer de HP para shells
const CHAT_MAX      = 8;
const PEER_PREFIX   = 'cs3-';
const SAVE_KEY      = 'chrono_v4_meta';
const CLASS_UNLOCK  = SAVE_KEY + '_class_unlocks_v3';
const FREE_CLASSES  = ['assault', 'sniper'];
const GOLD_MULT     = 1.5;
const DIFF_ORDER    = ['easy','medium','hard','extreme'];
const DIFFICULTY    = {
  easy:    { label:'Fácil',   mult:1.0, color:'#4ce0b3' },
  medium:  { label:'Médio',   mult:1.6, color:'#46d6ff' },
  hard:    { label:'Difícil', mult:2.4, color:'#ffd166' },
  extreme: { label:'Extremo', mult:3.5, color:'#ff4d6d' },
};
const ENEMY_COUNT_BASE = 2.0;
const ENEMY_COUNT_STEP = 0.15;

// ========================= STATE =========================
const S = {
  peer: null, isHost: false, myId: null,
  myName: 'P' + Math.floor(Math.random() * 900 + 100),
  roomCode: null, difficulty: 'medium', riftMode: false,
  conns:   new Map(), // peerId -> DataConnection
  players: new Map(), // peerId -> playerEntry
  started: false,
  chat:    [],
  bossAnnounced: new Set(),
  remoteBullets:  new Map(), // peerId -> [{x,y,r,c}]
  // timers (todos limpos no reset)
  _tickTimer: null, _enemyTimer: null, _hostDmgTimer: null,
  _killTimer: null,  _bossTimer: null,  _bulletTimer: null,
  _goldTimer: null,  _shopTimer: null,  _hurtCdTimer: null,
  _dmgFlushTimer: null, _pauseTimer: null, _menuTimer: null,
  // gold compartilhado
  goldPool: 0, lastSyncedGold: 0,
  // shop
  inShop: false, myShopReady: false, shopReadySet: new Set(),
  prevShopOpen: false, shopWaitEl: null,
  // pause
  pausedBy: null, pausedByName: null,
  localPaused: false, pauseOverlayEl: null,
  // revive
  reviveTarget: null, reviveStart: 0,
  // misc
  enemyIdCounter: 1,
  lastBulletHash: 0,
  hostRetries: 0,
  injectedBtn: null,
  netToastTimer: null,
};

// ========================= UTILS =========================
const $    = (s, r = document) => r.querySelector(s);
const log  = (...a) => console.log('%c[MP14]', 'color:#6cf', ...a);
const warn = (...a) => console.warn('[MP14]', ...a);
const rid  = () => Math.random().toString(36).slice(2, 8).toLowerCase().replace(/[^a-z0-9]/g, 'a');

const normCode = raw => {
  let s = String(raw || '').toLowerCase().trim().replace(/\s+/g, '');
  if (s.startsWith(PEER_PREFIX)) s = s.slice(PEER_PREFIX.length);
  return (s = s.replace(/[^a-z0-9]/g, '')) ? PEER_PREFIX + s : '';
};
const prettyCode = full => (full || '').replace(PEER_PREFIX, '').toUpperCase();
const hpMult     = () => (DIFFICULTY[S.difficulty] || DIFFICULTY.medium).mult;
const enemyMult  = () => ENEMY_COUNT_BASE + ENEMY_COUNT_STEP * Math.max(0, DIFF_ORDER.indexOf(S.difficulty));
const send  = (conn, obj) => { try { conn.send(obj); } catch (_) {} };
const bcast = obj => { for (const c of S.conns.values()) send(c, obj); };

function getClasses() {
  const raw = window.CLASSES || null;
  if (!raw) return [];
  const normalize = (k, v) => ({
    key: k, name: v.name || k,
    icon: v.icon || v.emoji || '⚔️', tag: v.tag || '',
    tagColor: v.tagColor || '#6cf', color: v.color || '#6cf',
    desc: v.desc || v.description || ''
  });
  return Array.isArray(raw)
    ? raw.map((x, i) => normalize(x.key || x.id || String(i), x))
    : Object.entries(raw).map(([k, v]) => normalize(k, v));
}

function getUnlocked() {
  try {
    const a = JSON.parse(localStorage.getItem(CLASS_UNLOCK) || '[]');
    return new Set([...FREE_CLASSES, ...(Array.isArray(a) ? a : [])]);
  } catch { return new Set(FREE_CLASSES); }
}

function el(tag, props = {}, ...kids) {
  const n = document.createElement(tag);
  for (const k in props) {
    if (k === 'style') Object.assign(n.style, props.style);
    else if (k === 'html') n.innerHTML = props.html;
    else if (k.startsWith('on') && typeof props[k] === 'function') n.addEventListener(k.slice(2), props[k]);
    else n[k] = props[k];
  }
  for (const c of kids) if (c != null) n.append(c.nodeType ? c : document.createTextNode(c));
  return n;
}

function clearAllLoops() {
  const keys = ['_tickTimer','_enemyTimer','_hostDmgTimer','_killTimer','_bossTimer',
    '_bulletTimer','_goldTimer','_shopTimer','_hurtCdTimer','_dmgFlushTimer',
    '_pauseTimer','_menuTimer'];
  for (const k of keys) {
    if (S[k]) { try { clearInterval(S[k]); } catch (_) {} S[k] = null; }
  }
}

function resetRuntime() {
  clearAllLoops();
  S.players       = new Map();
  S.conns         = new Map();
  S.remoteBullets = new Map();
  S.shopReadySet  = new Set();
  S.bossAnnounced = new Set();
  S.pausedBy = null; S.pausedByName = null;
  S.localPaused  = false;
  S.inShop = false; S.myShopReady = false; S.prevShopOpen = false;
  S.goldPool = 0; S.lastSyncedGold = 0;
  S.started = false; S.lastBulletHash = 0;
  S.reviveTarget = null;
  hidePauseOverlay(); hideShopWait();
  if (S.peer && !S.peer.destroyed) { try { S.peer.destroy(); } catch (_) {} }
  S.peer = null; S.myId = null;
}

// ========================= CSS =========================
function injectCSS() {
  if (document.getElementById('mp14-style')) return;
  const css = `
  #mp-root{font-family:'Rajdhani','Inter',system-ui,sans-serif;color:#eef2ff}
  .mpb{font-family:inherit;cursor:pointer;border:1px solid rgba(120,200,255,.25);
       background:linear-gradient(180deg,rgba(40,60,100,.6),rgba(20,30,55,.6));
       color:#eef2ff;border-radius:10px;padding:10px 14px;font-weight:700;
       letter-spacing:.04em;transition:all .15s}
  .mpb:hover:not(:disabled){border-color:#61dafb;box-shadow:0 0 14px rgba(97,218,251,.35);transform:translateY(-1px)}
  .mpb:disabled{opacity:.45;cursor:not-allowed}
  .mpb.pri{background:linear-gradient(180deg,#46d6ff,#1e90ff);border-color:#9bedff;color:#001020}
  .mpb.suc{background:linear-gradient(180deg,#4ce0b3,#1aa978);border-color:#9ef5d8;color:#001a10}
  .mpb.gho{background:rgba(255,255,255,.04)}
  .mpb.big{padding:22px 18px;font-size:15px;display:flex;flex-direction:column;align-items:center;gap:6px}
  .mpi{font-family:inherit;background:rgba(6,8,18,.7);border:1px solid rgba(120,200,255,.2);
       color:#eef2ff;border-radius:8px;padding:10px 12px;width:100%;font-size:14px;box-sizing:border-box}
  .mpi:focus{outline:none;border-color:#61dafb;box-shadow:0 0 0 2px rgba(97,218,251,.2)}
  .mpi.code{text-transform:uppercase;letter-spacing:.32em;text-align:center;
             font-family:'Orbitron','Rajdhani',sans-serif;font-size:20px;font-weight:900;
             padding:14px 12px;color:#9bedff}
  .mpi.code.valid{border-color:rgba(76,224,179,.6);box-shadow:0 0 0 2px rgba(76,224,179,.25)}
  .mpi.code.invalid{border-color:rgba(255,77,109,.6);box-shadow:0 0 0 2px rgba(255,77,109,.25)}
  .mpcard{background:rgba(6,8,18,.92);border:1px solid rgba(120,200,255,.15);
          backdrop-filter:blur(16px);border-radius:16px;
          box-shadow:0 20px 60px rgba(0,0,0,.6),inset 0 0 30px rgba(80,140,255,.04)}
  .mptitle{font-family:'Orbitron',sans-serif;font-weight:900;letter-spacing:.15em;
            background:linear-gradient(90deg,#61dafb,#9f6cff,#ff6b9d);
            -webkit-background-clip:text;-webkit-text-fill-color:transparent}
  .mplabel{font-size:10px;letter-spacing:.18em;opacity:.65;font-weight:700;
            margin-bottom:6px;display:block}
  .mprow{display:flex;align-items:center;justify-content:space-between;padding:10px 12px;
         background:rgba(255,255,255,.03);border:1px solid rgba(120,200,255,.1);border-radius:10px}
  .mprow.rdy{border-color:rgba(76,224,179,.4);background:rgba(76,224,179,.06)}
  .mprow.hst{border-color:rgba(255,209,102,.35)}
  .mpchip{font-size:11px;padding:2px 8px;border-radius:999px;letter-spacing:.08em;font-weight:700}
  .mpclc{position:relative;display:flex;flex-direction:column;gap:8px;padding:14px;
         background:linear-gradient(160deg,rgba(30,40,75,.85),rgba(8,12,25,.92));
         border:1px solid rgba(120,200,255,.18);border-radius:14px;
         cursor:pointer;transition:all .18s;text-align:left;min-height:148px}
  .mpclc:hover:not(:disabled){border-color:#61dafb;transform:translateY(-3px);box-shadow:0 10px 28px rgba(97,218,251,.28)}
  .mpclc.pck{border-color:#4ce0b3;box-shadow:0 0 0 2px rgba(76,224,179,.45),0 0 24px rgba(76,224,179,.25)}
  .mpclc.lkd{filter:saturate(.35) grayscale(.6);opacity:.55;cursor:not-allowed}
  .mpdiff{display:grid;grid-template-columns:repeat(4,1fr);gap:6px}
  .mpdiff button{padding:10px 6px;border-radius:8px;border:1px solid rgba(120,200,255,.18);
                 background:rgba(6,8,18,.6);color:#eef2ff;font-family:inherit;
                 font-weight:700;font-size:12px;cursor:pointer;transition:all .15s}
  .mpdiff button.on{border-color:currentColor;box-shadow:0 0 0 2px currentColor inset}
  .mpcode{font-family:'Orbitron','Rajdhani',sans-serif;font-size:28px;font-weight:900;
          letter-spacing:.32em;text-align:center;padding:14px 18px;border-radius:14px;
          background:linear-gradient(180deg,rgba(20,30,60,.7),rgba(6,10,22,.7));
          border:1px solid rgba(97,218,251,.35);color:#9bedff;
          text-shadow:0 0 18px rgba(97,218,251,.55);
          box-shadow:inset 0 0 30px rgba(97,218,251,.12),0 8px 28px rgba(0,0,0,.5);
          animation:codePulse 2.6s ease-in-out infinite}
  @keyframes codePulse{
    0%,100%{box-shadow:inset 0 0 30px rgba(97,218,251,.12),0 8px 28px rgba(0,0,0,.5)}
    50%{box-shadow:inset 0 0 30px rgba(97,218,251,.22),0 8px 28px rgba(0,0,0,.5),0 0 28px rgba(97,218,251,.35)}
  }
  .mpfade{animation:mpFadeIn .2s ease-out}
  @keyframes mpFadeIn{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}
  .mpspin{display:inline-block;width:11px;height:11px;border-radius:50%;
          border:2px solid rgba(155,237,255,.25);border-top-color:#9bedff;
          animation:mpSpin .8s linear infinite;vertical-align:middle;margin-right:6px}
  @keyframes mpSpin{to{transform:rotate(360deg)}}
  #mp-toast{position:fixed;top:14px;left:50%;transform:translateX(-50%) translateY(-12px);
             z-index:100001;pointer-events:none;opacity:0;
             background:linear-gradient(180deg,rgba(12,18,38,.96),rgba(6,10,22,.96));
             border:1px solid rgba(120,200,255,.3);backdrop-filter:blur(12px);
             color:#eef2ff;padding:10px 18px;border-radius:999px;font-size:12px;
             font-weight:700;letter-spacing:.1em;
             box-shadow:0 12px 40px rgba(0,0,0,.55),0 0 24px rgba(97,218,251,.18);
             transition:opacity .25s ease,transform .25s ease}
  #mp-toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
  #mp-toast.ok{border-color:rgba(76,224,179,.55);color:#7ff0c8;box-shadow:0 12px 40px rgba(0,0,0,.55),0 0 28px rgba(76,224,179,.35)}
  #mp-toast.warn{border-color:rgba(255,209,102,.55);color:#ffd166}
  #mp-toast.err{border-color:rgba(255,77,109,.6);color:#ff8fa3;box-shadow:0 12px 40px rgba(0,0,0,.55),0 0 30px rgba(255,77,109,.4)}
  `;
  document.head.append(el('style', { id: 'mp14-style', textContent: css }));
}

function netToast(msg, kind = 'ok', ms = 2200) {
  let t = document.getElementById('mp-toast');
  if (!t) { t = el('div', { id: 'mp-toast' }); document.body.append(t); }
  t.textContent = msg;
  t.className = kind + ' show';
  if (S.netToastTimer) clearTimeout(S.netToastTimer);
  S.netToastTimer = setTimeout(() => { t.className = kind; }, ms);
}

// ========================= UI BUILD =========================
let UI = {};

function buildUI() {
  if (document.getElementById('mp-root')) return;
  injectCSS();

  const root = el('div', { id: 'mp-root', style: {
    position: 'fixed', inset: '0', zIndex: 99999, pointerEvents: 'none'
  }});

  const openBtn = el('button', { className: 'mpb pri', style: {
    position: 'absolute', top: '12px', right: '12px', pointerEvents: 'auto',
    fontSize: '13px', display: 'none'
  }}, '🎮 Multiplayer');
  openBtn.onclick = () => { togglePanel(true); showStage('home'); };
  root.append(openBtn);

  const panel = el('div', { id: 'mp-panel', className: 'mpcard mpfade', style: {
    position: 'absolute', top: '50%', left: '50%',
    transform: 'translate(-50%,-50%)',
    width: 'min(640px,94vw)', maxHeight: '90vh', overflow: 'auto',
    padding: '22px', pointerEvents: 'auto', display: 'none'
  }});

  panel.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:18px">
      <div>
        <div class="mptitle" style="font-size:22px">CHRONO SHARDS</div>
        <div style="font-size:11px;opacity:.6;letter-spacing:.2em;margin-top:2px">MULTIPLAYER CO-OP · ${VERSION}</div>
      </div>
      <button id="mp-close" class="mpb gho" style="padding:6px 10px">×</button>
    </div>

    <div id="mp-s-home" style="display:none">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
        <button id="mp-go-create" class="mpb pri big">
          <span style="font-size:28px">🛡️</span><span>CRIAR SALA</span>
          <span style="font-size:10px;opacity:.7;font-weight:600">Você será o host</span>
        </button>
        <button id="mp-go-join" class="mpb suc big">
          <span style="font-size:28px">⚔️</span><span>ENTRAR</span>
          <span style="font-size:10px;opacity:.7;font-weight:600">Use o código do amigo</span>
        </button>
      </div>
      <div style="margin-top:14px;padding:10px 12px;background:rgba(97,218,251,.06);
                  border:1px solid rgba(97,218,251,.18);border-radius:10px;font-size:12px;opacity:.85">
        💡 Co-op P2P direto. Host controla inimigos, dano e waves. Ouro compartilhado.
      </div>
      <div id="mp-home-msg" style="margin-top:10px;font-size:11px;opacity:.6;text-align:center"></div>
    </div>

    <div id="mp-s-create" style="display:none">
      <button class="mpb gho" data-back style="font-size:12px;padding:6px 10px;margin-bottom:14px">← voltar</button>
      <div style="display:grid;gap:12px">
        <div><span class="mplabel">SEU NOME</span><input id="mp-name-c" class="mpi" maxlength="14"/></div>
        <div><span class="mplabel">DIFICULDADE</span><div id="mp-diff" class="mpdiff"></div></div>
        <label style="display:flex;align-items:center;gap:8px;font-size:13px;cursor:pointer">
          <input id="mp-rift" type="checkbox"/> Forçar modo Fissura
        </label>
        <button id="mp-host" class="mpb pri" style="padding:14px">🛡️ CRIAR SALA</button>
      </div>
      <div id="mp-status-c" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <div id="mp-s-join" style="display:none">
      <button class="mpb gho" data-back style="font-size:12px;padding:6px 10px;margin-bottom:14px">← voltar</button>
      <div style="display:grid;gap:12px">
        <div><span class="mplabel">SEU NOME</span><input id="mp-name-j" class="mpi" maxlength="14"/></div>
        <div>
          <span class="mplabel">CÓDIGO DA SALA</span>
          <input id="mp-code" class="mpi code" placeholder="A1B2C3" maxlength="14" autocomplete="off" spellcheck="false"/>
          <div style="margin-top:6px;font-size:11px;opacity:.5;text-align:center">Cole ou digite o código do host</div>
        </div>
        <button id="mp-join" class="mpb suc" style="padding:14px">⚔️ ENTRAR NA SALA</button>
      </div>
      <div id="mp-status-j" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <div id="mp-s-lobby" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:14px;gap:12px">
        <div style="flex:1">
          <div class="mplabel" style="margin:0 0 6px">CÓDIGO · COMPARTILHE COM SEU AMIGO</div>
          <div id="mp-room-lbl" class="mpcode">------</div>
        </div>
        <div style="display:flex;gap:6px;align-items:flex-start;margin-top:4px">
          <span id="mp-role" class="mpchip" style="padding:4px 10px">HOST</span>
          <button id="mp-copy" class="mpb gho" style="font-size:11px;padding:4px 8px">📋</button>
        </div>
      </div>
      <div class="mplabel">JOGADORES</div>
      <div id="mp-plist" style="display:grid;gap:8px;margin-bottom:14px"></div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
        <button id="mp-pick"  class="mpb pri" disabled>Selecionar Personagem</button>
        <button id="mp-start" class="mpb suc" disabled>Iniciar Partida</button>
      </div>
      <div id="mp-lmsg" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <div id="mp-s-pick" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
        <div>
          <div style="font-size:17px;font-weight:800">Escolha seu personagem</div>
          <div style="font-size:11px;opacity:.55;margin-top:2px">Classes bloqueadas precisam ser desbloqueadas no menu principal.</div>
        </div>
        <button id="mp-pick-back" class="mpb gho" style="font-size:12px;padding:6px 10px">← voltar</button>
      </div>
      <div id="mp-class-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:12px;margin-top:12px"></div>
    </div>
  `;
  root.append(panel);

  // Chat
  const chat = el('div', { id: 'mp-chat', style: {
    position: 'absolute', left: '12px', bottom: '12px', width: '320px',
    pointerEvents: 'none', display: 'none'
  }});
  chat.innerHTML = `
    <div id="mp-chat-log" style="display:flex;flex-direction:column;gap:4px;margin-bottom:6px"></div>
    <input id="mp-chat-input" class="mpi" placeholder="Enter → enviar chat" style="display:none;pointer-events:auto"/>
  `;
  root.append(chat);

  // Team panel
  const team = el('div', { id: 'mp-team', className: 'mpcard', style: {
    position: 'absolute', top: '58px', right: '12px', width: '210px',
    padding: '10px', fontSize: '12px', display: 'none', pointerEvents: 'none'
  }});
  root.append(team);

  document.body.append(root);

  UI = {
    root, openBtn, panel, chat, team,
    close:   $('#mp-close', panel),
    sHome:   $('#mp-s-home', panel), sCreate: $('#mp-s-create', panel),
    sJoin:   $('#mp-s-join', panel), sLobby:  $('#mp-s-lobby', panel), sPick: $('#mp-s-pick', panel),
    goCreate: $('#mp-go-create', panel), goJoin: $('#mp-go-join', panel),
    nameC:   $('#mp-name-c', panel),  nameJ:  $('#mp-name-j', panel),
    diff:    $('#mp-diff', panel),   rift:   $('#mp-rift', panel),
    hostBtn: $('#mp-host', panel),   joinBtn: $('#mp-join', panel),
    codeIn:  $('#mp-code', panel),
    statusC: $('#mp-status-c', panel), statusJ: $('#mp-status-j', panel),
    homeMsg: $('#mp-home-msg', panel),
    roomLbl: $('#mp-room-lbl', panel), copyBtn: $('#mp-copy', panel),
    role:    $('#mp-role', panel),
    plist:   $('#mp-plist', panel),
    pickBtn: $('#mp-pick', panel), startBtn: $('#mp-start', panel),
    lmsg:    $('#mp-lmsg', panel),
    pickBack: $('#mp-pick-back', panel), grid: $('#mp-class-grid', panel),
    chatLog:  $('#mp-chat-log', chat), chatInput: $('#mp-chat-input', chat),
  };

  UI.nameC.value = S.myName; UI.nameJ.value = S.myName;
  renderDiff();

  // Events
  UI.close.onclick   = () => togglePanel(false);
  UI.goCreate.onclick = () => showStage('create');
  UI.goJoin.onclick   = () => showStage('join');
  panel.querySelectorAll('[data-back]').forEach(b => b.onclick = () => showStage('home'));
  UI.hostBtn.onclick  = onHost;
  UI.joinBtn.onclick  = onJoin;
  UI.pickBtn.onclick  = () => { if (!UI.pickBtn.disabled) showPick(); };
  UI.startBtn.onclick = () => { if (!UI.startBtn.disabled) hostStart(); };
  UI.pickBack.onclick = () => showStage('lobby');
  UI.copyBtn.onclick  = () => {
    if (!S.roomCode) return;
    try { navigator.clipboard?.writeText(prettyCode(S.roomCode)); } catch (_) {}
    UI.copyBtn.textContent = '✓';
    setTimeout(() => UI.copyBtn.textContent = '📋', 1200);
  };

  UI.codeIn.addEventListener('input', e => {
    const v = String(e.target.value || '').toUpperCase().replace(/[^A-Z0-9-]/g, '');
    if (v !== e.target.value) e.target.value = v;
    const n = normCode(v);
    e.target.classList.remove('valid', 'invalid');
    if (v) e.target.classList.add(n && n.length > PEER_PREFIX.length ? 'valid' : 'invalid');
  });
  UI.codeIn.addEventListener('keydown', e => {
    if (e.key === 'Enter' && !UI.joinBtn.disabled) { e.preventDefault(); onJoin(); }
  });

  // Chat key handling
  UI.chatInput.addEventListener('keydown', e => {
    e.stopPropagation();
    if (e.key === 'Enter') {
      const m = UI.chatInput.value.trim();
      if (m) sendChat(m);
      UI.chatInput.value = ''; UI.chatInput.style.display = 'none'; UI.chatInput.blur();
    } else if (e.key === 'Escape') {
      UI.chatInput.value = ''; UI.chatInput.style.display = 'none'; UI.chatInput.blur();
    }
  });
  window.addEventListener('keydown', e => {
    if (!S.started || document.activeElement === UI.chatInput) return;
    if (e.key === 'Enter') { e.preventDefault(); UI.chatInput.style.display = 'block'; UI.chatInput.focus(); }
  });

  // Pause (tecla P)
  window.addEventListener('keydown', e => {
    if (!S.started || document.activeElement === UI.chatInput) return;
    if ((e.key || '').toLowerCase() !== 'p') return;
    if (S.pausedBy && S.pausedBy !== S.myId) return; // outro pausou
    e.preventDefault(); e.stopPropagation();
    const g = window.game; if (!g) return;
    if (S.localPaused) {
      // RESUME
      S.localPaused = false;
      g.paused = false;
      if (!S.inShop && !g.__mpDowned) g.running = true;
      hidePauseOverlay();
      if (S.isHost) {
        S.pausedBy = null;
        bcast({ t: 'resumeRemote' });
      } else {
        const c = S.conns.get(S.roomCode);
        if (c) send(c, { t: 'unpaused' });
      }
    } else {
      // PAUSE
      S.localPaused = true;
      g.paused = true; g.running = false;
      showPauseOverlay(S.myName + ' (você)');
      if (S.isHost) {
        S.pausedBy = S.myId;
        bcast({ t: 'pauseRemote', by: S.myId, byName: S.myName });
      } else {
        const c = S.conns.get(S.roomCode);
        if (c) send(c, { t: 'paused' });
      }
    }
  }, true);

  if (!window.__MP_BRIDGE_READY__) {
    UI.homeMsg.textContent = '⚠ Bridge não detectado — certifique-se que o jogo carregou completamente.';
  }

  startMenuPoller();
}

function showStage(name) {
  const map = { home: UI.sHome, create: UI.sCreate, join: UI.sJoin, lobby: UI.sLobby, pick: UI.sPick };
  for (const [k, el] of Object.entries(map)) if (el) el.style.display = k === name ? '' : 'none';
}
function togglePanel(show) { UI.panel.style.display = show ? '' : 'none'; }
function setStatus(m, w = 'c') {
  const e = w === 'j' ? UI.statusJ : UI.statusC;
  if (e) e.textContent = m; log(m);
}
function renderDiff() {
  UI.diff.innerHTML = '';
  for (const [k, d] of Object.entries(DIFFICULTY)) {
    const b = el('button', { onclick: () => { S.difficulty = k; renderDiff(); }, style: { color: d.color } }, d.label);
    if (k === S.difficulty) b.classList.add('on');
    UI.diff.append(b);
  }
}

function startMenuPoller() {
  if (S._menuTimer) return;
  S._menuTimer = setInterval(() => {
    try {
      if (S.started) {
        if (S.injectedBtn?.isConnected) S.injectedBtn.remove();
        S.injectedBtn = null; UI.openBtn.style.display = 'none'; return;
      }
      const rift   = document.getElementById('riftMode50');
      const choice = document.querySelector('.riftModeChoice50');
      if (!rift || !choice) {
        if (S.injectedBtn?.isConnected) S.injectedBtn.remove();
        S.injectedBtn = null; UI.openBtn.style.display = 'none'; return;
      }
      if (S.injectedBtn?.isConnected) return;

      const card = rift.cloneNode(true);
      card.id = 'mpMode50'; card.style.setProperty('--c', '#9f6cff');
      card.classList.remove('locked525', 'locked');
      card.querySelectorAll('.riftLockLayer525,.riftLockBadge525').forEach(n => n.remove());
      card.querySelectorAll('h2,p').forEach(n => { n.style.opacity = ''; });
      card.style.filter = ''; card.style.pointerEvents = 'auto';
      const tag = card.querySelector('.riftTag50');
      const h2  = card.querySelector('h2');
      const p   = card.querySelector('p');
      if (tag) { tag.textContent = 'CO-OP'; tag.style.color = '#c8a8ff'; }
      if (h2)  { h2.textContent = 'Multiplayer 2P'; h2.style.opacity = '1'; }
      if (p)   { p.textContent = 'Enfrente as waves com um amigo. Inimigos compartilhados, ouro em pool e revive cooperativo.'; p.style.opacity = '1'; }
      card.onclick = ev => { ev.preventDefault(); ev.stopPropagation(); togglePanel(true); showStage('home'); };
      choice.appendChild(card);
      S.injectedBtn = card; UI.openBtn.style.display = 'none';
    } catch (_) {}
  }, 400);
}

// ========================= PEERJS =========================
const PEER_ERR_MSG = {
  'peer-unavailable':   'Sala não encontrada. Verifique o código com seu amigo.',
  'network':            'Sem internet ou servidor offline.',
  'server-error':       'Servidor de signalling com erro.',
  'unavailable-id':     'Código já em uso, gerando outro...',
  'invalid-id':         'Código inválido.',
  'socket-error':       'Erro de socket, tentando reconectar...',
  'browser-incompatible': 'Navegador incompatível com WebRTC.',
};
const peerErrMsg = e => (e && PEER_ERR_MSG[e.type]) || (e && e.message) || 'Erro desconhecido';

function peerCfg() {
  const isHttps = typeof location !== 'undefined' && location.protocol === 'https:';
  return {
    debug: 1, secure: isHttps,
    config: { iceServers: [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:global.stun.twilio.com:3478' },
    ]},
  };
}

function ensurePeer(id) {
  return new Promise((resolve, reject) => {
    if (!window.Peer) return reject(new Error('PeerJS não carregado.'));
    let p, opened = false, settled = false;
    try { p = id ? new Peer(id, peerCfg()) : new Peer(peerCfg()); }
    catch (e) { return reject(e); }

    const timeout = setTimeout(() => {
      if (settled) return; settled = true;
      try { p.destroy(); } catch (_) {}
      reject(new Error('Timeout conectando ao servidor de signalling (12s).'));
    }, 12000);

    p.on('open', pid => {
      if (settled) return; settled = true; clearTimeout(timeout);
      opened = true; S.peer = p; S.myId = pid;
      p.on('disconnected', () => { warn('peer disconnected'); netToast('Reconectando...', 'warn', 4000); try { p.reconnect(); } catch (_) {} });
      p.on('close', () => { warn('peer closed'); netToast('Conexão encerrada.', 'err', 4000); });
      resolve(p);
    });
    p.on('error', err => {
      warn('peer error', err?.type, err?.message);
      if (!opened) {
        if (!settled) { settled = true; clearTimeout(timeout); reject(err); }
      } else {
        netToast(peerErrMsg(err), 'warn', 3500);
      }
    });
    p.on('connection', onIncoming);
  });
}

function onHost() {
  resetRuntime();
  S.myName   = (UI.nameC.value || S.myName).slice(0, 14);
  S.riftMode = UI.rift.checked;
  S.isHost   = true; S.hostRetries = 0;
  tryHostOnce();
}
function tryHostOnce() {
  S.roomCode = PEER_PREFIX + rid();
  setStatus('Criando sala... (' + (S.hostRetries + 1) + '/5)', 'c');
  ensurePeer(S.roomCode).then(() => {
    netToast('Sala criada · ' + prettyCode(S.roomCode), 'ok', 2500);
    S.players.set(S.myId, mkEntry());
    enterLobby();
  }).catch(e => {
    const t = e?.type;
    const retry = ['unavailable-id','id-taken','network','socket-error','server-error'].includes(t);
    if (retry && S.hostRetries < 4) {
      S.hostRetries++;
      setTimeout(tryHostOnce, 400 + 250 * S.hostRetries);
    } else {
      setStatus('Falhou: ' + peerErrMsg(e), 'c');
      netToast(peerErrMsg(e), 'err', 4000);
    }
  });
}

function onJoin() {
  const raw = (UI.codeIn.value || '').trim();
  if (!raw) return setStatus('Digite o código da sala.', 'j');
  const full = normCode(raw);
  if (!full || full.length <= PEER_PREFIX.length) {
    setStatus('Código inválido.', 'j');
    netToast('Código inválido', 'err', 2500); return;
  }
  resetRuntime();
  S.myName   = (UI.nameJ.value || S.myName).slice(0, 14);
  S.isHost   = false; S.roomCode = full;
  setStatus('Conectando a ' + prettyCode(full) + '...', 'j');
  ensurePeer().then(() => tryJoinOnce(0)).catch(e => {
    setStatus('Falhou: ' + peerErrMsg(e), 'j');
    netToast(peerErrMsg(e), 'err', 4000);
  });
}
function tryJoinOnce(attempt) {
  if (!S.peer || S.peer.destroyed) return setStatus('Peer destruído. Recarregue.', 'j');
  setStatus('Conectando ao host... (' + (attempt + 1) + '/3)', 'j');
  const conn = S.peer.connect(S.roomCode, { reliable: true, serialization: 'json' });
  let opened = false, settled = false, fatal = false;

  const finish = () => {
    if (settled) return; settled = true; clearTimeout(tmo);
    try { S.peer.off && S.peer.off('error', peerErrHandler); } catch (_) {}
  };
  const peerErrHandler = err => {
    if (opened || settled) return;
    if (err?.type === 'peer-unavailable') {
      fatal = true; finish();
      setStatus('Sala não encontrada. Verifique o código.', 'j');
      netToast('Sala "' + prettyCode(S.roomCode) + '" não existe.', 'err', 5000);
    }
  };
  try { S.peer.on('error', peerErrHandler); } catch (_) {}

  const retry = label => {
    if (settled || fatal) return; finish();
    if (attempt < 2) {
      const delay = 800 * (attempt + 1);
      setStatus(label + ' Retentando em ' + (delay / 1000) + 's...', 'j');
      setTimeout(() => tryJoinOnce(attempt + 1), delay);
    } else {
      setStatus(label + ' Verifique o código.', 'j');
      netToast('Falha ao conectar.', 'err', 4500);
    }
  };
  const tmo = setTimeout(() => { if (!opened) { try { conn.close(); } catch (_) {} retry('Sem resposta do host.'); } }, 8000);

  conn.on('open', () => {
    opened = true; finish();
    S.conns.set(S.roomCode, conn);
    conn.send({ t: 'hello', name: S.myName, v: VERSION });
    S.players.set(S.myId, mkEntry());
    netToast('Conectado ✓', 'ok', 2000);
    enterLobby();
  });
  conn.on('data', d => handleData(conn, d));
  conn.on('close', () => { if (opened) { setStatus('Desconectado do host.', 'j'); netToast('Conexão encerrada.', 'err', 3500); } });
  conn.on('error', e => { if (!opened) retry('Erro: ' + peerErrMsg(e) + '.'); });
}

function onIncoming(conn) {
  if (!S.isHost) return;
  conn.on('open', () => {
    S.conns.set(conn.peer, conn);
    log('Peer joined:', conn.peer);
    netToast('Jogador entrou!', 'ok');
  });
  conn.on('data', d => handleData(conn, d));
  conn.on('close', () => {
    S.conns.delete(conn.peer); S.players.delete(conn.peer);
    S.remoteBullets.delete(conn.peer); S.shopReadySet.delete(conn.peer);
    if (S.pausedBy === conn.peer) {
      S.pausedBy = null; hidePauseOverlay();
      const g = window.game; if (g) { g.paused = false; g.running = true; }
      bcast({ t: 'resumeRemote' });
    }
    if (S.inShop) evaluateShopReady();
    netToast('Jogador saiu.', 'warn');
    broadcastLobby(); renderLobby();
  });
  conn.on('error', e => warn('conn err', e));
}

function mkEntry() {
  return { id: S.myId, name: S.myName, classKey: null, ready: false,
           x: 0, y: 0, hp: 100, maxHp: 100, wave: 1, score: 0, down: false, host: S.isHost };
}

// ========================= PROTOCOL =========================
function handleData(conn, d) {
  if (!d?.t) return;
  if (S.isHost) hostHandleData(conn, d);
  else          clientHandleData(conn, d);
}

function hostHandleData(conn, d) {
  switch (d.t) {
    case 'hello': {
      S.players.set(conn.peer, {
        id: conn.peer, name: (d.name || 'P').slice(0, 14),
        classKey: null, ready: false,
        x: 0, y: 0, hp: 100, maxHp: 100, wave: 1, score: 0, down: false, host: false
      });
      broadcastLobby(); renderLobby(); break;
    }
    case 'pickClass': {
      const p = S.players.get(conn.peer);
      if (p) { p.classKey = d.classKey; p.ready = true; }
      broadcastLobby(); renderLobby(); break;
    }
    case 'state': {
      const p = S.players.get(conn.peer);
      if (p) Object.assign(p, d.s); break;
    }
    case 'bullets': {
      S.remoteBullets.set(conn.peer, Array.isArray(d.b) ? d.b : []);
      // relay para outros peers
      for (const [pid, c] of S.conns) {
        if (pid !== conn.peer) send(c, { t: 'bulletsRemote', from: conn.peer, b: d.b });
      }
      break;
    }
    // Dano de bala do cliente num inimigo (shell no cliente, real no host)
    case 'dmg': {
      hostApplyDmg(d.mpId, d.amount, conn.peer); break;
    }
    case 'chat': bcastChat(d.from || '?', d.msg || ''); break;
    case 'revive': {
      const tp = S.players.get(d.target);
      if (tp) { tp.down = false; tp.hp = Math.max(1, Math.floor(tp.maxHp * REVIVE_HP_PCT)); }
      if (d.target === S.myId) doLocalRevive();
      else { const c = S.conns.get(d.target); if (c) send(c, { t: 'youRevived' }); }
      broadcastLobby(); break;
    }
    case 'down': {
      const p = S.players.get(conn.peer);
      if (p) p.down = !!d.down;
      broadcastLobby(); break;
    }
    case 'goldDelta': {
      const delta = Number(d.delta) || 0;
      if (delta < 0) S.goldPool = Math.max(0, S.goldPool + delta);
      broadcastGoldPool(); break;
    }
    case 'shopReady': {
      S.shopReadySet.add(conn.peer);
      evaluateShopReady(); break;
    }
    case 'shopUnready': {
      S.shopReadySet.delete(conn.peer);
      break;
    }
    case 'paused': {
      if (S.pausedBy) break;
      S.pausedBy = conn.peer;
      S.pausedByName = (S.players.get(conn.peer) || {}).name || 'Player';
      bcast({ t: 'pauseRemote', by: conn.peer, byName: S.pausedByName });
      applyRemotePause(conn.peer, S.pausedByName); break;
    }
    case 'unpaused': {
      if (S.pausedBy !== conn.peer) break;
      S.pausedBy = null; S.pausedByName = null;
      bcast({ t: 'resumeRemote' });
      applyRemoteResume(); break;
    }
  }
}

function clientHandleData(conn, d) {
  switch (d.t) {
    case 'lobby':
      S.players = new Map(d.players.map(p => [p.id, p]));
      S.difficulty = d.difficulty || S.difficulty;
      S.riftMode = d.riftMode;
      renderLobby(); break;
    case 'start': startLocalGame(d.classByPlayer[S.myId]); break;
    case 'youRevived': doLocalRevive(); break;
    case 'youHit':    clientApplyHit(d.amount || 0); break;
    case 'state': {
      for (const p of d.players) {
        if (p.id === S.myId) continue;
        S.players.set(p.id, Object.assign(S.players.get(p.id) || {}, p));
      }
      break;
    }
    case 'bullets':
      S.remoteBullets.set('__host__', Array.isArray(d.b) ? d.b : []); break;
    case 'bulletsRemote':
      S.remoteBullets.set(d.from || '__other__', Array.isArray(d.b) ? d.b : []); break;
    case 'enemies': applyEnemySnapshot(d.list, d.wave, d.gtime); break;
    case 'chat':    pushChat(d.from, d.msg); break;
    case 'bossSpawn': announceBoss(d.name || 'BOSS', d.color || '#ff2e63'); break;
    case 'shopOpen':   clientShopOpen(); break;
    case 'shopResume': clientShopResume(); break;
    case 'shopWait':   renderShopWait(d.ready || 0, d.total || 1); break;
    case 'youKilled':  clientApplyKill(d); break;
    case 'goldSync': {
      const g = window.game; if (!g) break;
      const pool = Number(d.pool) || 0;
      const localDelta = (g.gold || 0) - S.lastSyncedGold;
      if (localDelta < 0) {
        // cliente gastou — reporta ao host e ajusta
        const c = S.conns.get(S.roomCode);
        if (c) send(c, { t: 'goldDelta', delta: localDelta });
        g.gold = Math.max(0, pool + localDelta);
      } else {
        g.gold = pool;
      }
      S.lastSyncedGold = g.gold; S.goldPool = pool;
      try { if (typeof window.updateHUD === 'function') window.updateHUD(); } catch (_) {}
      break;
    }
    case 'pauseRemote':  applyRemotePause(d.by, d.byName || 'Player'); break;
    case 'resumeRemote': applyRemoteResume(); break;
  }
}

// ========================= LOBBY =========================
function broadcastLobby() {
  if (!S.isHost) return;
  bcast({ t: 'lobby', players: [...S.players.values()], difficulty: S.difficulty, riftMode: S.riftMode });
}
function broadcastState() {
  if (!S.isHost) return;
  bcast({ t: 'state', players: [...S.players.values()].map(p => ({
    id: p.id, name: p.name, classKey: p.classKey,
    x: p.x, y: p.y, hp: p.hp, maxHp: p.maxHp,
    wave: p.wave, score: p.score, down: p.down
  }))});
}

function enterLobby() {
  showStage('lobby');
  UI.roomLbl.textContent = prettyCode(S.roomCode);
  UI.role.textContent = S.isHost ? 'HOST' : 'CLIENTE';
  UI.role.style.cssText = 'padding:4px 10px;border-radius:999px;background:' +
    (S.isHost ? 'rgba(255,209,102,.15);color:#ffd166;border:1px solid rgba(255,209,102,.35)' :
                'rgba(97,218,251,.15);color:#61dafb;border:1px solid rgba(97,218,251,.35)');
  if (S.isHost) broadcastLobby();
  renderLobby();
}

function renderLobby() {
  if (!UI.plist) return;
  const players = [...S.players.values()];
  const cmap    = new Map(getClasses().map(c => [c.key, c]));
  UI.plist.innerHTML = '';
  for (const p of players) {
    const c   = p.classKey ? cmap.get(p.classKey) : null;
    const row = el('div', { className: 'mprow' + (p.ready ? ' rdy' : '') + (p.host ? ' hst' : '') });
    const L   = el('div', { style: { display:'flex',alignItems:'center',gap:'10px' } });
    L.append(el('div', { style: {
      width:'36px',height:'36px',borderRadius:'8px',background:'rgba(255,255,255,.05)',
      display:'grid',placeItems:'center',fontSize:'20px',
      border:'1px solid ' + (c ? (c.tagColor || '#6cf') + '44' : 'rgba(120,200,255,.15)')
    }}, c ? c.icon : '❔'));
    const info = el('div');
    info.append(el('div', { style: { fontWeight:'700',fontSize:'14px' } },
      p.name + (p.host ? ' 👑' : '') + (p.id === S.myId ? ' (você)' : '')));
    info.append(el('div', { style: { fontSize:'11px',opacity:.7,marginTop:'2px' } },
      p.classKey ? (c ? c.name : p.classKey) : 'escolhendo personagem...'));
    L.append(info);
    const chip = el('span', { className: 'mpchip', style: {
      background: p.ready ? 'rgba(76,224,179,.2)' : 'rgba(255,255,255,.06)',
      color: p.ready ? '#4ce0b3' : '#9ab',
      border: '1px solid ' + (p.ready ? 'rgba(76,224,179,.4)' : 'rgba(255,255,255,.1)')
    }}, p.ready ? '✓ PRONTO' : '⏳');
    row.append(L, chip); UI.plist.append(row);
  }
  const me      = S.players.get(S.myId);
  const enough  = players.length >= 2;
  const allRdy  = enough && players.every(p => p.ready);
  const setBtn  = (b, en, cls, txt) => { b.disabled = !en; b.className = 'mpb ' + cls; b.textContent = txt; };

  if (!me)          setBtn(UI.pickBtn, false, 'pri', 'Selecionar Personagem');
  else if (!enough) setBtn(UI.pickBtn, true,  'pri', '⚔️ Selecionar (aguardando 2º jogador)');
  else if (me.ready)setBtn(UI.pickBtn, true,  'gho', '🔁 Trocar Personagem');
  else              setBtn(UI.pickBtn, true,  'pri', '⚔️ Selecionar Personagem');

  if (S.isHost) setBtn(UI.startBtn, allRdy, 'suc', allRdy ? '▶ INICIAR PARTIDA' : 'Aguardando seleções...');
  else          setBtn(UI.startBtn, false,   'gho', allRdy ? 'Host vai iniciar...' : 'Aguardando seleções...');

  UI.lmsg.textContent = !enough ? 'Compartilhe o código com seu amigo.' :
    !allRdy ? 'Cada jogador precisa selecionar um personagem.' :
    S.isHost ? 'Tudo pronto! Clique em INICIAR PARTIDA.' : 'Aguardando o host iniciar...';
}

function showPick() {
  const classes  = getClasses();
  const unlocked = getUnlocked();
  UI.grid.innerHTML = '';
  if (!classes.length) {
    UI.grid.innerHTML = `<div style="grid-column:1/-1;padding:14px;background:rgba(255,77,109,.1);
      border:1px solid rgba(255,77,109,.35);border-radius:10px;font-size:13px">
      <b>⚠ window.CLASSES não encontrado.</b><br>Certifique-se que o jogo carregou completamente.</div>`;
    showStage('pick'); return;
  }
  const me = S.players.get(S.myId);
  classes.sort((a, b) => (unlocked.has(b.key) ? 1 : 0) - (unlocked.has(a.key) ? 1 : 0));
  for (const c of classes) {
    const isUnlocked = unlocked.has(c.key);
    const picked     = me?.classKey === c.key;
    const card = el('button', { className: 'mpclc' + (picked ? ' pck' : '') + (isUnlocked ? '' : ' lkd'), disabled: !isUnlocked });
    const hdr = el('div', { style: { display:'flex',justifyContent:'space-between',alignItems:'flex-start',gap:'8px' } });
    hdr.append(el('div', { style: {
      width:'52px',height:'52px',borderRadius:'12px',display:'grid',placeItems:'center',
      fontSize:'28px',background:'rgba(255,255,255,.05)',
      border:'1px solid ' + (c.tagColor || c.color || '#6cf') + '66'
    }}, c.icon));
    const badges = el('div', { style: { display:'flex',flexDirection:'column',gap:'4px',alignItems:'flex-end' } });
    if (!isUnlocked) badges.append(el('span', { className:'mpchip', style:{ background:'rgba(255,209,102,.15)',color:'#ffd166',border:'1px solid rgba(255,209,102,.4)' }}, '🔒 BLOQUEADO'));
    else if (c.tag)  badges.append(el('span', { className:'mpchip', style:{ background:(c.tagColor||'#6cf')+'22',color:(c.tagColor||'#6cf'),border:'1px solid '+(c.tagColor||'#6cf')+'55' }}, c.tag));
    if (picked) badges.append(el('span', { className:'mpchip', style:{ background:'rgba(76,224,179,.18)',color:'#4ce0b3',border:'1px solid rgba(76,224,179,.5)' }}, '✓ SELECIONADA'));
    hdr.append(badges); card.append(hdr);
    card.append(el('div', { style:{ fontWeight:'800',fontSize:'15px',marginTop:'2px' } }, c.name));
    if (c.desc) card.append(el('div', { style:{ fontSize:'11px',opacity:.7,lineHeight:'1.4' } }, c.desc.length > 110 ? c.desc.slice(0, 110) + '…' : c.desc));
    if (isUnlocked) card.onclick = () => pickClass(c.key);
    UI.grid.append(card);
  }
  showStage('pick');
}

function pickClass(key) {
  if (!getUnlocked().has(key)) return;
  const me = S.players.get(S.myId);
  if (me) { me.classKey = key; me.ready = true; }
  if (S.isHost) broadcastLobby();
  else { const c = S.conns.get(S.roomCode); if (c) send(c, { t: 'pickClass', classKey: key }); }
  showStage('lobby'); renderLobby();
}

// ========================= START GAME =========================
function hostStart() {
  if (!S.isHost) return;
  const cbp = {};
  for (const p of S.players.values()) {
    if (!p.classKey) { netToast('Todos precisam escolher uma classe.', 'warn'); return; }
    cbp[p.id] = p.classKey;
  }
  bcast({ t: 'start', classByPlayer: cbp });
  startLocalGame(cbp[S.myId]);
}

function closeOverlay() {
  const ov = document.getElementById('overlay');
  if (ov) { ov.classList.add('hidden'); ov.style.display = 'none'; }
}

function startLocalGame(classKey) {
  if (!classKey) return warn('Sem classe definida!');
  S.started = true;
  togglePanel(false);
  UI.chat.style.display = '';
  UI.team.style.display = '';
  if (S.injectedBtn?.isConnected) S.injectedBtn.remove();
  S.injectedBtn = null; UI.openBtn.style.display = 'none';

  if (S.riftMode) { try { window.__forceNextRift507 = true; } catch (_) {} }
  try {
    if (typeof window.resetGame === 'function') window.resetGame(classKey);
    else return warn('window.resetGame não disponível!');
  } catch (e) { return console.error('[MP14] Erro ao iniciar jogo:', e); }

  closeOverlay();
  setTimeout(closeOverlay, 60);
  setTimeout(closeOverlay, 300);

  setTimeout(() => {
    installEnemyPatch();
    wrapStartNextWave();
    startTickLoop();
    if (S.isHost) {
      startEnemySync();
      startHostDamageLoop();
      startHostTargetingLoop();
      startKillCreditLoop();
      startBossWatcher();
      startShopWatcher();
    } else {
      startClientDmgFlush();
      startHurtCdLock();
    }
    startBulletBroadcast();
    startGoldSync();
    startPauseWatcher();
    startOverlay();
    netToast('Partida iniciada · ' + (DIFFICULTY[S.difficulty]?.label || ''), 'ok', 2500);
  }, 100);
}

// ========================= ENEMY PATCH =========================
function installEnemyPatch() {
  const g = window.game; if (!g) return;

  // Wrapper de gameOver — permite modo "downed" em co-op
  if (typeof window.gameOver === 'function' && !window.gameOver.__mpWrap) {
    const orig = window.gameOver;
    const wrapped = function () {
      if (g.__mpDowned) return;
      const others = [...S.players.values()].filter(p => p.id !== S.myId && p.classKey && !p.down);
      if (others.length > 0) {
        g.__mpDowned = true;
        if (!S.isHost) g.running = false;
        if (g.player) { g.player.hp = 0; g.player.down = true; g.player.dead = true; }
        const me = S.players.get(S.myId); if (me) me.down = true;
        if (S.isHost) broadcastLobby();
        else { const c = S.conns.get(S.roomCode); if (c) send(c, { t: 'down', down: true }); }
        return;
      }
      return orig.apply(this, arguments);
    };
    wrapped.__mpWrap = true;
    try { window.gameOver = wrapped; } catch (_) {}
  }

  if (S.isHost) {
    // Host: envolve spawnEnemy para multiplicar inimigos e aplicar HP mult
    const orig = window.spawnEnemy;
    if (typeof orig === 'function' && !orig.__mpWrap) {
      const wrapped = function (...a) {
        const mult  = enemyMult();
        const whole = Math.floor(mult);
        const N     = whole + (Math.random() < (mult - whole) ? 1 : 0);
        let firstR  = null;
        for (let i = 0; i < Math.max(1, N); i++) {
          const before = Array.isArray(g.enemies) ? g.enemies.length : 0;
          const r = orig.apply(this, a);
          const e = (r && typeof r === 'object') ? r :
                    (Array.isArray(g.enemies) && g.enemies.length > before ? g.enemies[g.enemies.length - 1] : null);
          if (e) {
            if (!e.__mpId) e.__mpId = S.enemyIdCounter++;
            const m = hpMult();
            if (m !== 1 && typeof e.hp === 'number') {
              const base = e.maxHp || e.hp;
              e.hp = e.hp * m; e.maxHp = base * m;
            }
            if (i > 0) { e.x = (e.x || 0) + (Math.random() * 60 - 30); e.y = (e.y || 0) + (Math.random() * 60 - 30); }
          }
          if (i === 0) firstR = r;
        }
        return firstR;
      };
      wrapped.__mpWrap = true;
      try { window.spawnEnemy = wrapped; } catch (_) {}
    }
  } else {
    // Cliente: spawnEnemy é noop — inimigos vêm do host via snapshot
    const noop = function () {
      const gg = window.game;
      if (gg) gg.enemiesSpawnedThisWave = (gg.enemiesSpawnedThisWave || 0) + 1;
    };
    noop.__mpWrap = true;
    try { window.spawnEnemy = noop; } catch (_) {}
  }
}

// ========================= SHELL ENEMIES =========================
/*
  Shell enemies usam Object.defineProperty para interceptar leituras/escritas de hp:
  - get hp() → Math.max(1, _hp)   ← NUNCA retorna 0, logo enemyDeath nunca é chamado
  - set hp(v) → acumula dano em __pendingDmg sem deixar hp chegar a 0
  - Timers (shotTimer etc.) são congelados em 9999 → inimigos não atiram
*/
function makeShellEnemy(s) {
  const obj = {
    __mpId: s.i, __mpShell: true,
    x: s.x, y: s.y, vx: s.vx || 0, vy: s.vy || 0,
    maxHp: s.M, r: s.r || 14,
    type:  s.t || 'normal', bossType: s.bt || null,
    boss: !!s.b, elite: !!s.el,
    color: s.c || '#ff6b9d',
    wobble: Math.random() * Math.PI * 2,
    hitFlash: 0, marked: false, markedTimer: 0, frozenTime: 0,
    auraAngle: 0, shieldHp: 0, phase: 1,
    speed: s.spd || 80,
    dead: false,
    __pendingDmg: 0,
    __syncUpdate: false,
  };

  // Interceptor de HP — nunca deixa chegar a 0
  let _hp = s.h;
  Object.defineProperty(obj, 'hp', {
    get()  { return Math.max(1, _hp); },
    set(v) {
      const dmg = _hp - v;
      if (dmg > 0.01 && !obj.__syncUpdate) {
        obj.__pendingDmg += dmg;
        obj.hitFlash = 0.12;
      }
      _hp = Math.max(1, v);
    },
    configurable: true, enumerable: true
  });

  // Congela timers de ataque — shells não disparam balas
  for (const k of ['shotTimer', 'summonTimer', 'slamTimer', 'laserTimer']) {
    Object.defineProperty(obj, k, {
      get() { return 9999; }, set() {},
      configurable: true, enumerable: true
    });
  }

  return obj;
}

function applyEnemySnapshot(list, wave, gtime) {
  const g = window.game; if (!g) return;
  if (!Array.isArray(g.enemies)) g.enemies = [];
  if (!Array.isArray(list)) return;

  // Sincroniza game.time para movimento de boss consistente
  if (gtime !== undefined && typeof g.time === 'number') g.time = gtime;
  if (wave)  { g.wave = wave; g.currentWave = wave; }

  const existing = new Map();
  for (const e of g.enemies) if (e?.__mpId) existing.set(e.__mpId, e);

  const next = [];
  for (const s of list) {
    let e = existing.get(s.i);
    if (!e) {
      e = makeShellEnemy(s);
    } else {
      // Atualiza posição e HP via sync (sem disparar __pendingDmg)
      e.__syncUpdate = true;
      e.x = s.x; e.y = s.y;
      e.vx = s.vx || 0; e.vy = s.vy || 0;
      e.hp = s.h;
      e.__syncUpdate = false;
      e.maxHp = s.M; e.r = s.r || e.r;
      e.speed = s.spd || e.speed;
    }
    next.push(e);
  }
  g.enemies = next;
}

// Flush de dano pendente nos shells → envia ao host (30Hz)
function startClientDmgFlush() {
  if (S._dmgFlushTimer) clearInterval(S._dmgFlushTimer);
  S._dmgFlushTimer = setInterval(() => {
    if (!S.started || S.isHost) return;
    const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
    const conn = S.conns.get(S.roomCode); if (!conn) return;
    for (const e of g.enemies) {
      if (!e?.__mpShell || !e.__mpId || !e.__pendingDmg) continue;
      if (e.__pendingDmg > 0.5) {
        send(conn, { t: 'dmg', mpId: e.__mpId, amount: Math.round(e.__pendingDmg) });
        e.__pendingDmg = 0;
      }
    }
  }, 1000 / DMG_FLUSH_HZ);
}

// Mantém hurtCd do cliente alto → dano de contato calculado apenas pelo host
function startHurtCdLock() {
  if (S._hurtCdTimer) clearInterval(S._hurtCdTimer);
  S._hurtCdTimer = setInterval(() => {
    if (!S.started || S.isHost) return;
    const g = window.game;
    if (g?.player && !g.__mpDowned) g.player.hurtCd = HURTCD_LOCK;
  }, 8);
}

// ========================= HOST: ENEMY SYNC =========================
function startEnemySync() {
  if (!S.isHost) return;
  if (S._enemyTimer) clearInterval(S._enemyTimer);
  S._enemyTimer = setInterval(() => {
    const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
    if (S.conns.size === 0) return;
    const list = [];
    for (const e of g.enemies) {
      if (!e) continue;
      if (!e.__mpId) e.__mpId = S.enemyIdCounter++;
      list.push({
        i:   e.__mpId,
        x:   Math.round(e.x || 0),  y:  Math.round(e.y || 0),
        vx:  Math.round(e.vx || 0), vy: Math.round(e.vy || 0),
        h:   Math.max(0, Math.round(e.hp || 0)),
        M:   Math.round(e.maxHp || e.hp || 1),
        r:   e.r || 14, t: e.type || 'normal',
        b:   !!e.boss, el: !!e.elite,
        c:   e.color || null, bt: e.bossType || null,
        spd: Math.round(e.speed || 80),
      });
    }
    bcast({ t: 'enemies', list, wave: g.wave || g.currentWave || 1, gtime: g.time || 0 });
  }, 1000 / ENEMY_HZ);
}

// ========================= HOST: APPLY DAMAGE =========================
function hostApplyDmg(mpId, amount, fromPeer) {
  const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
  for (const e of g.enemies) {
    if (e?.__mpId === mpId) {
      e.hp     -= amount;
      e.hitFlash = 0.12;
      if (fromPeer) e.__mpLastHitter = fromPeer;
      break;
    }
  }
}

// ========================= HOST: TARGETING LOOP =========================
function startHostTargetingLoop() {
  if (!S.isHost) return;
  let active = true;
  const tick = () => {
    if (!active || !S.started) return;
    const now = performance.now();
    const g = window.game;
    if (g && Array.isArray(g.enemies)) {
      const live = getLivePlayers();
      // Só redireciona inimigos quando há 2+ jogadores vivos
      if (live.length >= 2) {
        for (const e of g.enemies) {
          if (!e || e.__mpShell || e.dead) continue;
          // Alterna alvo a cada ~1.8s — 65% mais próximo, 35% aleatório
          if (!e.__mpAggroT || now - e.__mpAggroT > 1800) {
            e.__mpAggro  = pickTarget(e.x || 0, e.y || 0);
            e.__mpAggroT = now;
          }
          const tgt = e.__mpAggro;
          if (!tgt) continue;
          // Sobrescreve vx/vy para apontar ao alvo escolhido
          const dx   = tgt.x - (e.x || 0), dy = tgt.y - (e.y || 0);
          const dist = Math.hypot(dx, dy) || 1;
          const spd  = e.speed || 80;
          e.vx = (dx / dist) * spd;
          e.vy = (dy / dist) * spd;
        }
      }
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

function getLivePlayers() {
  return [...S.players.values()].filter(p => p.classKey && !p.down);
}
function pickTarget(ex, ey) {
  const live = getLivePlayers(); if (!live.length) return null;
  if (live.length === 1) return live[0];
  if (Math.random() < 0.30) return live[Math.floor(Math.random() * live.length)];
  let best = null, bd = Infinity;
  for (const p of live) {
    const d = (p.x - ex) ** 2 + (p.y - ey) ** 2;
    if (d < bd) { bd = d; best = p; }
  }
  return best;
}

// ========================= HOST: DAMAGE LOOP =========================
function contactDmg(e) {
  if (!e) return 0;
  if (e.type === 'boss')   return 24;
  if (e.type === 'tank')   return 20;
  if (e.elite)             return 20;
  if (e.type === 'bomber') return 35;
  return 13;
}

function startHostDamageLoop() {
  if (!S.isHost) return;
  const TICK = 1000 / HOST_DMG_HZ;
  if (S._hostDmgTimer) clearInterval(S._hostDmgTimer);
  S._hostDmgTimer = setInterval(() => {
    if (!S.started) return;
    const g = window.game; if (!g) return;
    const others = [...S.players.values()].filter(p => p.id !== S.myId && p.classKey && !p.down);
    if (!others.length) return;
    const dt = TICK / 1000;

    for (const rp of others) {
      if (rp.__hurtCd == null) rp.__hurtCd = 0;
      rp.__hurtCd = Math.max(0, rp.__hurtCd - dt);

      let hit = 0;

      // Contato com inimigos
      if (rp.__hurtCd <= 0 && Array.isArray(g.enemies)) {
        for (const e of g.enemies) {
          if (!e || e.dead) continue;
          const er = (e.r || 14) + 14;
          const dx = (e.x || 0) - rp.x, dy = (e.y || 0) - rp.y;
          if (dx * dx + dy * dy < er * er) {
            hit = Math.max(hit, contactDmg(e));
            // Bomber explode ao contato
            if (e.type === 'bomber') { e.hp = 0; e.dead = true; }
            break;
          }
        }
      }

      // Balas inimigas atingindo o jogador remoto
      if (Array.isArray(g.enemyBullets)) {
        for (let i = g.enemyBullets.length - 1; i >= 0; i--) {
          const b = g.enemyBullets[i];
          if (!b) continue;
          const br = (b.r || 5) + 14;
          const dx = (b.x || 0) - rp.x, dy = (b.y || 0) - rp.y;
          if (dx * dx + dy * dy < br * br && rp.__hurtCd <= 0) {
            hit = Math.max(hit, b.damage || 10);
            g.enemyBullets.splice(i, 1);
          }
        }
      }

      if (hit > 0) {
        rp.hp = Math.max(0, (rp.hp || 0) - hit);
        rp.__hurtCd = 0.55;
        const c = S.conns.get(rp.id);
        if (c) send(c, { t: 'youHit', amount: hit });
        if (rp.hp <= 0 && !rp.down) {
          rp.down = true; broadcastLobby();
        }
      }
    }
  }, TICK);
}

function clientApplyHit(amount) {
  const g = window.game; if (!g?.player) return;
  if (g.__mpDowned) return;
  // ignora armor: host já calculou. Aplica direto no HP.
  const p  = g.player;
  let dmg  = amount;
  if (p.shield > 0) {
    const abs = Math.min(p.shield, dmg);
    p.shield -= abs; dmg -= abs;
    if (dmg <= 0) return;
  }
  p.hp = Math.max(0, p.hp - dmg);
  p.hurtCd = 0.3;
  g.flash = 0.18; g.flashColor = '#ff7b92'; g.shake = 8;
  if (p.hp <= 0) { try { if (typeof window.gameOver === 'function') window.gameOver(); } catch (_) {} }
}

function doLocalRevive() {
  const g = window.game; if (!g) return;
  g.__mpDowned = false; g.running = true;
  if (g.player) {
    g.player.hp = Math.max(1, Math.floor((g.player.maxHp || 100) * REVIVE_HP_PCT));
    g.player.down = false; g.player.dead = false;
  }
  const me = S.players.get(S.myId);
  if (me) { me.down = false; me.hp = g.player?.hp || me.hp; }
  if (!S.isHost) { const c = S.conns.get(S.roomCode); if (c) send(c, { t: 'down', down: false }); }
  else broadcastLobby();
  netToast('Você foi revivido!', 'ok');
}

// ========================= HOST: KILL CREDIT =========================
function startKillCreditLoop() {
  if (!S.isHost) return;
  if (S._killTimer) clearInterval(S._killTimer);
  let prev = new Map();
  S._killTimer = setInterval(() => {
    const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
    const cur = new Map();
    for (const e of g.enemies) if (e?.__mpId) cur.set(e.__mpId, e);

    for (const [id, e] of prev) {
      if (cur.has(id)) continue;
      // Inimigo morreu — credita ouro e XP
      const base = Math.max(1, Math.floor((e.value || 10) * 0.5));
      const peer = e.__mpLastHitter;

      // Gold pool (com multiplicador online)
      if (!peer || peer === S.myId) {
        // host matou — bônus do multiplicador (jogo já creditou base)
        S.goldPool += Math.floor(base * (GOLD_MULT - 1));
      } else {
        S.goldPool += Math.floor(base * GOLD_MULT);
      }

      // XP/score para o cliente que deu o último hit
      if (peer && peer !== S.myId) {
        const c = S.conns.get(peer); if (c) {
          send(c, { t: 'youKilled',
            xp:    Math.max(1, Math.floor((e.value || 10) * 0.4)),
            score: e.value || 10,
            boss:  e.type === 'boss',
            name:  e.type === 'boss' ? (e.bossType || 'BOSS') : (e.type || ''),
          });
        }
      }
    }
    prev = cur;
  }, 200);
}

function clientApplyKill(d) {
  const g = window.game; if (!g) return;
  g.score = (g.score || 0) + (d.score || 0);
  if (g.player) {
    g.player.xp = (g.player.xp || 0) + (d.xp || 0);
    while (g.player.xp >= g.xpNext) {
      g.player.xp -= g.xpNext; g.level = (g.level || 1) + 1;
      g.xpNext = Math.floor(g.xpNext * 1.35);
      try { if (typeof window.openUpgradeMenu === 'function') window.openUpgradeMenu(); } catch (_) {}
    }
  }
  try { if (typeof window.updateHUD === 'function') window.updateHUD(); } catch (_) {}
  if (d.boss) announceBoss(d.name ? d.name + ' DERROTADO' : 'BOSS DERROTADO', '#4ce0b3');
}

// ========================= BOSS WATCHER =========================
function startBossWatcher() {
  if (!S.isHost) return;
  if (S._bossTimer) clearInterval(S._bossTimer);
  S._bossTimer = setInterval(() => {
    const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
    for (const e of g.enemies) {
      if (!e || e.type !== 'boss') continue;
      if (!e.__mpId) e.__mpId = S.enemyIdCounter++;
      if (S.bossAnnounced.has(e.__mpId)) continue;
      S.bossAnnounced.add(e.__mpId);
      const name  = (e.bossType || 'BOSS').toUpperCase();
      const color = e.color || '#ff2e63';
      bcast({ t: 'bossSpawn', name, color, id: e.__mpId });
      announceBoss(name, color);
    }
  }, 250);
}

function announceBoss(name, color) {
  const root = document.getElementById('mp-root'); if (!root) return;
  const n = el('div', { style: {
    position: 'absolute', top: '18%', left: '50%', transform: 'translateX(-50%)',
    fontFamily: 'Orbitron,sans-serif', fontWeight: '900', fontSize: '32px',
    letterSpacing: '.2em', color: '#fff',
    textShadow: `0 0 24px ${color},0 0 40px ${color}`,
    pointerEvents: 'none', zIndex: 99999, opacity: '0',
    transition: 'all .5s ease-out'
  }}, `⚠ ${name} ⚠`);
  root.append(n);
  requestAnimationFrame(() => { n.style.opacity = '1'; n.style.transform = 'translateX(-50%) translateY(10px)'; });
  setTimeout(() => n.style.opacity = '0', 2500);
  setTimeout(() => n.remove(), 3100);
}

// ========================= SHOP SYNC =========================
/*
  Abordagem: host detecta abertura de loja via polling de game.shopPending.
  startNextWave é envolto UMA VEZ para fazer o gate de shop-ready.
*/
function startShopWatcher() {
  if (!S.isHost) return;
  if (S._shopTimer) clearInterval(S._shopTimer);
  S._shopTimer = setInterval(() => {
    const g = window.game; if (!g) return;
    const isOpen = !!(g.shopPending || g.betweenWaves);
    if (isOpen && !S.prevShopOpen) {
      // Loja acabou de abrir
      S.inShop = true; S.myShopReady = false; S.shopReadySet = new Set();
      bcast({ t: 'shopOpen' });
    }
    S.prevShopOpen = isOpen;
  }, 100);
}

function wrapStartNextWave() {
  const origSNW = window.startNextWave;
  if (typeof origSNW !== 'function' || origSNW.__mpShopWrap) return;
  const wrap = function () {
    // Fora do jogo multiplayer: comportamento original
    if (!S.started || S.conns.size === 0) {
      S.inShop = false; S.myShopReady = false; hideShopWait();
      return origSNW.apply(this, arguments);
    }
    // Auto-advance entre waves (sem loja): host executa, cliente ignora
    if (!S.inShop) {
      if (S.isHost) return origSNW.apply(this, arguments);
      return; // cliente — host controla a wave
    }
    // Na loja — gate de shop-ready
    if (!S.myShopReady) {
      S.myShopReady = true;
      if (S.isHost) {
        S.shopReadySet.add(S.myId);
        evaluateShopReady();
      } else {
        const c = S.conns.get(S.roomCode);
        if (c) send(c, { t: 'shopReady' });
        showShopWaitForMe();
      }
    }
  };
  wrap.__mpShopWrap = true;
  // Guarda referência para chamada direta quando todos estiverem prontos
  window.__mpOrigSNW = origSNW;
  try { window.startNextWave = wrap; } catch (_) {}
}

function totalActivePlayers() {
  let n = 0;
  for (const p of S.players.values()) if (p.classKey) n++;
  return Math.max(1, n);
}

function evaluateShopReady() {
  if (!S.isHost) return;
  const total = totalActivePlayers();
  const ready = S.shopReadySet.size;
  bcast({ t: 'shopWait', ready, total });
  if (S.myShopReady) showShopWaitForMe();
  if (ready >= total) {
    // Todos prontos → avança a wave
    S.inShop = false; S.myShopReady = false; S.shopReadySet = new Set();
    S.prevShopOpen = false;
    hideShopWait();
    bcast({ t: 'shopResume' });
    try {
      const g = window.game;
      if (g) { g.shopPending = false; g.betweenWaves = false; g.running = true; }
      closeOverlay();
      if (typeof window.__mpOrigSNW === 'function') window.__mpOrigSNW();
    } catch (e) { warn('startNextWave error:', e); }
  }
}

function clientShopOpen() {
  const g = window.game; if (!g) return;
  S.inShop = true; S.myShopReady = false;
  g.shopPending = true; g.running = false;
  try { if (typeof window.openShopMenu === 'function') window.openShopMenu(); } catch (_) {}
}
function clientShopResume() {
  const g = window.game; if (!g) return;
  S.inShop = false; S.myShopReady = false;
  hideShopWait(); closeOverlay();
  g.shopPending = false; g.betweenWaves = false; g.running = true;
  try { if (typeof window.__mpOrigSNW === 'function') window.__mpOrigSNW(); } catch (_) {}
}

function showShopWaitForMe() {
  const total = totalActivePlayers();
  const ready = S.isHost ? S.shopReadySet.size : 1;
  renderShopWait(ready, total);
}
function renderShopWait(ready, total) {
  if (!S.myShopReady) return;
  if (!S.shopWaitEl) {
    S.shopWaitEl = el('div', { id: 'mp-shop-wait', style: {
      position: 'fixed', top: '50%', left: '50%', transform: 'translate(-50%,-50%)',
      zIndex: 100001, pointerEvents: 'none',
      background: 'rgba(6,8,18,.95)', border: '1px solid rgba(120,200,255,.4)',
      borderRadius: '14px', padding: '20px 28px', textAlign: 'center',
      fontFamily: "'Orbitron','Rajdhani',sans-serif", color: '#eef2ff',
      boxShadow: '0 12px 48px rgba(0,0,0,.7),0 0 32px rgba(97,218,251,.25)'
    }});
    document.body.append(S.shopWaitEl);
  }
  S.shopWaitEl.innerHTML = `
    <div style="font-size:10px;letter-spacing:.25em;opacity:.6;margin-bottom:6px">CO-OP</div>
    <div style="font-size:17px;font-weight:800;letter-spacing:.08em">⏳ Aguardando jogadores</div>
    <div style="font-size:32px;font-weight:900;color:#61dafb;margin-top:8px">${ready}/${total}</div>
    <div style="font-size:11px;opacity:.6;margin-top:10px">A próxima wave começa quando todos confirmarem.</div>`;
  S.shopWaitEl.style.display = '';
}
function hideShopWait() {
  if (S.shopWaitEl) S.shopWaitEl.style.display = 'none';
}

// ========================= GOLD POOL =========================
function startGoldSync() {
  const g = window.game;
  if (S.isHost && g) { S.goldPool = g.gold || 0; S.lastSyncedGold = S.goldPool; }
  else if (g)         { S.lastSyncedGold = g.gold || 0; }

  if (S._goldTimer) clearInterval(S._goldTimer);
  S._goldTimer = setInterval(() => {
    if (!S.started) return;
    const g = window.game; if (!g) return;
    const cur   = g.gold || 0;
    const delta = cur - S.lastSyncedGold;
    if (S.isHost) {
      if (delta > 0) S.goldPool += delta;      // host matou algo → pooliza o ganho
      else if (delta < 0) S.goldPool = Math.max(0, S.goldPool + delta); // host comprou
      if (g.gold !== S.goldPool) {
        g.gold = S.goldPool;
        try { if (typeof window.updateHUD === 'function') window.updateHUD(); } catch (_) {}
      }
      S.lastSyncedGold = g.gold;
      bcast({ t: 'goldSync', pool: S.goldPool });
    } else {
      // Cliente não ganha gold localmente (kills via host)
      if (delta > 0) g.gold = S.lastSyncedGold; // desfaz ganho local fantasma
    }
  }, 1000 / GOLD_HZ);
}
function broadcastGoldPool() {
  if (S.isHost) bcast({ t: 'goldSync', pool: S.goldPool });
}

// ========================= BULLET BROADCAST =========================
function snapshotBullets() {
  const g = window.game;
  if (!g || !Array.isArray(g.bullets)) return [];
  const out = [], N = Math.min(g.bullets.length, 100);
  for (let i = 0; i < N; i++) {
    const b = g.bullets[i];
    if (!b || b.dead || b.life <= 0) continue;
    out.push({ x: Math.round(b.x || 0), y: Math.round(b.y || 0), r: b.r || 3, c: b.color || null });
  }
  return out;
}
function startBulletBroadcast() {
  if (S._bulletTimer) clearInterval(S._bulletTimer);
  S._bulletTimer = setInterval(() => {
    if (!S.started || S.conns.size === 0) return;
    const snap = snapshotBullets();
    let h = snap.length;
    for (let i = 0; i < snap.length; i += 4) h = (h * 131 + snap[i].x + snap[i].y * 7) | 0;
    if (h === S.lastBulletHash) return;
    S.lastBulletHash = h;
    if (S.isHost) bcast({ t: 'bullets', b: snap });
    else { const c = S.conns.get(S.roomCode); if (c) send(c, { t: 'bullets', b: snap }); }
  }, 1000 / BULLET_HZ);
}

// ========================= TICK LOOP (estado do jogador) =========================
function startTickLoop() {
  if (S._tickTimer) clearInterval(S._tickTimer);
  S._tickTimer = setInterval(() => {
    const g = window.game; if (!g) return;
    const me = S.players.get(S.myId); if (!me) return;
    const pl = g.player || null;
    if (pl) {
      me.x = pl.x || 0; me.y = pl.y || 0;
      me.hp = pl.hp || 0; me.maxHp = pl.maxHp || 100;
      me.down = !!(pl.dead || pl.down || me.hp <= 0 || g.__mpDowned);
    }
    me.wave  = g.wave || g.currentWave || me.wave;
    me.score = g.score || me.score;
    if (S.isHost) broadcastState();
    else {
      const c = S.conns.get(S.roomCode);
      if (c) send(c, { t: 'state', s: {
        x: me.x, y: me.y, hp: me.hp, maxHp: me.maxHp,
        wave: me.wave, score: me.score, down: me.down,
      }});
    }
    renderTeam();
  }, 1000 / TICK_HZ);
}

// ========================= PAUSE =========================
function startPauseWatcher() {
  if (S._pauseTimer) clearInterval(S._pauseTimer);
  S._pauseTimer = setInterval(() => {
    if (!S.started) return;
    // Se um jogador remoto pausou, mantém jogo parado
    if (S.pausedBy && S.pausedBy !== S.myId) {
      const g = window.game;
      if (g && !g.paused) { g.paused = true; g.running = false; }
      hideLocalPauseMenu();
    }
  }, 120);
}

function applyRemotePause(byId, byName) {
  if (byId === S.myId) return;
  const g = window.game; if (g) { g.paused = true; g.running = false; }
  S.pausedBy = byId; S.pausedByName = byName;
  showPauseOverlay(byName || 'Player');
  hideLocalPauseMenu();
}
function applyRemoteResume() {
  S.pausedBy = null; S.pausedByName = null; S.localPaused = false;
  hidePauseOverlay();
  const g = window.game;
  if (g) { g.paused = false; if (!S.inShop && !g.__mpDowned) g.running = true; }
}

function showPauseOverlay(name) {
  if (!S.pauseOverlayEl) {
    S.pauseOverlayEl = el('div', { id: 'mp-pause-overlay', style: {
      position: 'fixed', inset: '0', zIndex: 100002, pointerEvents: 'none',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'rgba(2,4,12,.55)', backdropFilter: 'blur(6px)'
    }});
    document.body.append(S.pauseOverlayEl);
  }
  S.pauseOverlayEl.innerHTML = `
    <div style="text-align:center;font-family:'Orbitron','Rajdhani',sans-serif;color:#eef2ff">
      <div style="font-size:12px;letter-spacing:.3em;opacity:.7;margin-bottom:10px">CO-OP</div>
      <div style="font-size:42px;font-weight:900;letter-spacing:.15em;
                  background:linear-gradient(90deg,#61dafb,#9f6cff);
                  -webkit-background-clip:text;-webkit-text-fill-color:transparent">PAUSADO</div>
      <div style="font-size:17px;margin-top:12px;opacity:.9">por <b style="color:#ffd166">${name}</b></div>
      <div style="font-size:11px;opacity:.5;margin-top:16px;letter-spacing:.15em">Pressione P para retomar...</div>
    </div>`;
  S.pauseOverlayEl.style.display = 'flex';
}
function hidePauseOverlay() { if (S.pauseOverlayEl) S.pauseOverlayEl.style.display = 'none'; }
function hideLocalPauseMenu() {
  ['#pauseMenu','#pauseOverlay','.pauseMenu','.pause-menu','#pause']
    .forEach(s => { const n = document.querySelector(s); if (n) n.style.display = 'none'; });
}

// ========================= OVERLAY CANVAS =========================
/*
  O overlay renderiza APENAS:
    • Sprite do jogador remoto (com barra de HP e ícone de classe)
    • Bullets remotas (visuais)
    • Barra de revive
    • Os INIMIGOS são renderizados pelo engine do jogo (game canvas),
      pois os shells têm todos os campos necessários para drawEnemies()
*/
let oc = null, octx = null;

function startOverlay() {
  if (oc) return;
  const gc = document.querySelector('canvas#game') || document.querySelector('canvas');
  if (!gc) { warn('Game canvas não encontrado!'); return; }

  oc = el('canvas', { style: {
    position: 'fixed', pointerEvents: 'none', zIndex: 9998, left: '0', top: '0'
  }});
  document.body.append(oc);
  octx = oc.getContext('2d');

  const resize = () => {
    const r = gc.getBoundingClientRect();
    oc.width = r.width; oc.height = r.height;
    oc.style.left = r.left + 'px'; oc.style.top = r.top + 'px';
    oc.style.width = r.width + 'px'; oc.style.height = r.height + 'px';
  };
  resize();
  window.addEventListener('resize', resize);
  new ResizeObserver(resize).observe(gc);

  const cmap = () => {
    const raw = window.CLASSES || null; if (!raw) return {};
    return Array.isArray(raw) ? Object.fromEntries(raw.map(c => [c.key || c.id, c])) : raw;
  };

  const drawFrame = () => {
    if (!octx) return;
    octx.clearRect(0, 0, oc.width, oc.height);

    const gc2 = document.querySelector('canvas#game') || document.querySelector('canvas');
    // scaleX: coordenada do game (0-1360) → pixel do overlay
    const scaleX = gc2 ? oc.width  / (gc2.width  || 1360) : 1;
    const scaleY = gc2 ? oc.height / (gc2.height || 780)  : 1;

    // ── Bullets remotas (visual only) ──
    octx.globalAlpha = 0.82;
    for (const [, arr] of S.remoteBullets) {
      if (!Array.isArray(arr)) continue;
      for (const b of arr) {
        const sx = (b.x || 0) * scaleX, sy = (b.y || 0) * scaleY;
        const r  = Math.max(1.5, (b.r || 3) * ((scaleX + scaleY) / 2));
        octx.fillStyle = b.c || '#9bedff';
        octx.shadowColor = b.c || '#9bedff'; octx.shadowBlur = 10;
        octx.beginPath(); octx.arc(sx, sy, r, 0, Math.PI * 2); octx.fill();
      }
    }
    octx.globalAlpha = 1; octx.shadowBlur = 0;

    // ── Jogadores remotos ──
    const classes = cmap();
    for (const p of S.players.values()) {
      if (p.id === S.myId) continue;
      const sx = (p.x || 0) * scaleX, sy = (p.y || 0) * scaleY;
      const cls   = classes[p.classKey] || null;
      const clr   = (cls?.color || cls?.tagColor) || '#61dafb';
      const icon  = (cls?.icon  || cls?.emoji)    || '◈';
      const R     = 16 * ((scaleX + scaleY) / 2);

      // Sombra de chão
      octx.globalAlpha = 0.3;
      octx.fillStyle = '#000';
      octx.beginPath(); octx.ellipse(sx, sy + R * 0.9, R * 0.8, R * 0.28, 0, 0, Math.PI * 2); octx.fill();

      // Corpo
      octx.globalAlpha = p.down ? 0.45 : 0.95;
      const grad = octx.createRadialGradient(sx, sy - R * 0.3, R * 0.1, sx, sy, R);
      grad.addColorStop(0, '#ffffff'); grad.addColorStop(0.45, clr); grad.addColorStop(1, p.down ? '#400' : 'rgba(0,0,0,.35)');
      octx.fillStyle = grad;
      octx.beginPath(); octx.arc(sx, sy, R, 0, Math.PI * 2); octx.fill();

      // Ring
      octx.lineWidth = 2.5; octx.strokeStyle = p.down ? '#ff4d6d' : clr;
      octx.shadowColor = clr; octx.shadowBlur = 14;
      octx.stroke(); octx.shadowBlur = 0;

      // Ícone
      octx.globalAlpha = 1;
      octx.fillStyle = '#fff';
      octx.font = `bold ${(R * 1.1) | 0}px 'Rajdhani',sans-serif`;
      octx.textAlign = 'center'; octx.textBaseline = 'middle';
      octx.fillText(icon, sx, sy + 1);
      octx.textBaseline = 'alphabetic';

      // Nome
      octx.fillStyle = '#fff';
      octx.font = `bold ${(12 * ((scaleX + scaleY) / 2)) | 0}px 'Rajdhani',sans-serif`;
      octx.fillText(p.name, sx, sy - R - 10 * ((scaleX + scaleY) / 2));

      // HP bar
      const bw = 46 * scaleX;
      octx.fillStyle = 'rgba(0,0,0,.65)';
      octx.fillRect(sx - bw / 2, sy - R - 6 * scaleY, bw, 3.5 * scaleY);
      const pct = Math.max(0, Math.min(1, (p.hp || 0) / (p.maxHp || 1)));
      octx.fillStyle = pct > 0.5 ? '#4ce0b3' : pct > 0.25 ? '#ffd166' : '#ff4d6d';
      octx.fillRect(sx - bw / 2, sy - R - 6 * scaleY, bw * pct, 3.5 * scaleY);

      // Down indicator
      if (p.down) {
        octx.fillStyle = '#ffd166';
        octx.font = `bold ${(11 * ((scaleX + scaleY) / 2)) | 0}px 'Rajdhani',sans-serif`;
        octx.fillText('⬆ F para reviver', sx, sy + R + 16 * scaleY);
      }
    }

    handleRevive(scaleX, scaleY);
    requestAnimationFrame(drawFrame);
  };
  requestAnimationFrame(drawFrame);
}

// ========================= REVIVE =========================
const keysDown = {};
window.addEventListener('keydown', e => keysDown[(e.key || '').toLowerCase()] = true);
window.addEventListener('keyup',   e => keysDown[(e.key || '').toLowerCase()] = false);

function handleRevive(scaleX, scaleY) {
  if (!S.started || !octx) return;
  const me = S.players.get(S.myId); if (!me || me.down) { S.reviveTarget = null; return; }

  let target = null, best = REVIVE_RANGE;
  for (const p of S.players.values()) {
    if (p.id === S.myId || !p.down) continue;
    const d = Math.hypot((p.x || 0) - (me.x || 0), (p.y || 0) - (me.y || 0));
    if (d < best) { best = d; target = p; }
  }

  if (target && keysDown['f']) {
    if (S.reviveTarget !== target.id) { S.reviveTarget = target.id; S.reviveStart = Date.now(); }
    const pct = Math.min(1, (Date.now() - S.reviveStart) / REVIVE_TIME);
    // Desenha barra de revive
    const sx = (target.x || 0) * scaleX, sy = (target.y || 0) * scaleY;
    const bw = 50 * scaleX;
    octx.fillStyle = 'rgba(0,0,0,.7)';
    octx.fillRect(sx - bw / 2, sy + 34 * scaleY, bw, 5 * scaleY);
    octx.fillStyle = '#ffd166';
    octx.fillRect(sx - bw / 2, sy + 34 * scaleY, bw * pct, 5 * scaleY);
    octx.fillStyle = '#fff';
    octx.font = `bold ${(10 * ((scaleX + scaleY) / 2)) | 0}px 'Rajdhani',sans-serif`;
    octx.textAlign = 'center'; octx.textBaseline = 'alphabetic';
    octx.fillText('REVIVENDO...', sx, sy + 28 * scaleY);

    if (pct >= 1) {
      if (S.isHost) {
        const tp = S.players.get(target.id);
        if (tp) { tp.down = false; tp.hp = Math.max(1, Math.floor(tp.maxHp * REVIVE_HP_PCT)); }
        const c = S.conns.get(target.id); if (c) send(c, { t: 'youRevived' });
        broadcastLobby();
      } else {
        const c = S.conns.get(S.roomCode); if (c) send(c, { t: 'revive', target: target.id });
      }
      S.reviveTarget = null;
    }
  } else {
    S.reviveTarget = null;
  }
}

// ========================= CHAT =========================
function sendChat(msg) {
  if (S.isHost) bcastChat(S.myName, msg);
  else {
    pushChat(S.myName, msg);
    const c = S.conns.get(S.roomCode); if (c) send(c, { t: 'chat', from: S.myName, msg });
  }
}
function bcastChat(from, msg) { pushChat(from, msg); if (S.isHost) bcast({ t: 'chat', from, msg }); }
function pushChat(from, msg) {
  S.chat.push({ from, msg, t: Date.now() });
  if (S.chat.length > CHAT_MAX) S.chat.shift();
  renderChat();
}
function renderChat() {
  if (!UI.chatLog) return;
  UI.chatLog.innerHTML = '';
  for (const m of S.chat) {
    const d = el('div', { style: {
      background: 'rgba(6,8,18,.75)', border: '1px solid rgba(120,200,255,.15)',
      padding: '3px 10px', borderRadius: '8px', width: 'fit-content', fontSize: '12px',
      textShadow: '0 1px 2px #000', maxWidth: '300px'
    }});
    d.append(el('b', { style: { color: '#61dafb' } }, m.from + ': '));
    d.append(document.createTextNode(m.msg));
    UI.chatLog.append(d);
  }
}

// ========================= TEAM PANEL =========================
function renderTeam() {
  if (!UI.team) return;
  const cmap = new Map(getClasses().map(c => [c.key, c]));
  UI.team.innerHTML = '';
  UI.team.append(el('div', { style: { fontSize: '10px', letterSpacing: '.15em', opacity: .6, marginBottom: '6px', fontWeight: '700' } },
    'EQUIPE · ' + (DIFFICULTY[S.difficulty]?.label || '')));
  for (const p of S.players.values()) {
    const c   = cmap.get(p.classKey);
    const row = el('div', { style: {
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      gap: '6px', padding: '3px 0', opacity: p.down ? 0.5 : 1
    }});
    row.append(el('span', { style: { display:'flex',alignItems:'center',gap:'4px',minWidth:0,overflow:'hidden' } },
      el('span', {}, c ? c.icon : '❔'),
      el('span', { style: { fontWeight: '600', overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' } },
        p.name + (p.id === S.myId ? ' (você)' : '') + (p.down ? ' 💀' : ''))));
    row.append(el('span', { style: { fontSize: '10px', opacity: .8, whiteSpace: 'nowrap' } },
      `W${p.wave || 1} · ${Math.max(0, (p.hp || 0) | 0)}/${(p.maxHp || 100) | 0}`));
    UI.team.append(row);
  }
}

// ========================= BOOT =========================
function boot() {
  if (!window.Peer) {
    warn('PeerJS ainda não disponível, aguardando...');
    return setTimeout(boot, 400);
  }
  buildUI();
  log('Multiplayer v14 pronto.', '| Bridge:', window.__MP_BRIDGE_READY__ ? '✓' : '✗', '| Classes:', getClasses().length);
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();

})();
