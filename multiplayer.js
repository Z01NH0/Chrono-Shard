/* ============================================================
   CHRONO SHARDS — MULTIPLAYER MODULE (PeerJS, P2P, co-op)
   ------------------------------------------------------------
   Como usar:
   No final do <head> (ou antes do </body>) do seu index.html,
   ANTES de fechar </body>, adicione estas DUAS linhas:

     <script src="https://unpkg.com/peerjs@1.5.4/dist/peerjs.min.js"></script>
     <script src="multiplayer.js"></script>

   Coloque o arquivo multiplayer.js na MESMA pasta do index.html.
   Mais nada precisa ser editado no jogo: o módulo injeta o
   botão "🌐 ONLINE" automaticamente no menu inicial.
   ============================================================ */
(function () {
  'use strict';

  // ---------- CONFIG ----------
  const TICK_HZ = 20;
  const PEER_PREFIX = 'chronoshards-';
  const COLORS = ['#61dafb', '#ff6b9d', '#ffd166', '#86ffb0', '#9f6cff'];

  // ---------- STATE ----------
  const MP = (window.CHRONO_MP = {
    peer: null,
    isHost: false,
    roomCode: null,
    myId: null,
    myName: 'Player' + Math.floor(Math.random() * 900 + 100),
    myColor: COLORS[0],
    conns: new Map(),       // peerId -> DataConnection
    players: new Map(),     // peerId -> {name,color,classKey,ready,x,y,hp,maxHp,wave}
    settings: { mode: 'normal', limit: 2 },
    gameStarted: false,
    overlay: null,
    tickTimer: null,
    modifiersApplied: false,
  });

  // ---------- STYLES ----------
  const css = `
  .mp-modal{position:fixed;inset:0;z-index:9999;display:grid;place-items:center;background:rgba(2,4,12,.78);backdrop-filter:blur(8px);font-family:'Rajdhani',sans-serif;color:#eef2ff}
  .mp-card{width:min(560px,92vw);max-height:90vh;overflow:auto;background:linear-gradient(160deg,#0a0f24,#070912);border:1px solid rgba(120,200,255,.22);border-radius:18px;padding:24px;box-shadow:0 30px 80px rgba(0,0,0,.7),0 0 60px rgba(97,218,251,.08)}
  .mp-title{font-family:'Orbitron',sans-serif;font-weight:900;letter-spacing:.16em;font-size:22px;background:linear-gradient(90deg,#61dafb,#9f6cff,#ff6b9d);-webkit-background-clip:text;-webkit-text-fill-color:transparent;text-align:center;margin-bottom:6px}
  .mp-sub{text-align:center;color:#9bb0d6;font-size:13px;margin-bottom:18px;letter-spacing:.06em}
  .mp-btn{display:block;width:100%;padding:14px 16px;margin:8px 0;border:1px solid rgba(120,200,255,.22);border-radius:12px;background:linear-gradient(135deg,#1a2745,#0f1530);color:#eef2ff;font-family:inherit;font-size:15px;font-weight:700;letter-spacing:.12em;cursor:pointer;transition:transform .12s,box-shadow .12s,border-color .12s}
  .mp-btn:hover{transform:translateY(-2px);border-color:rgba(120,200,255,.55);box-shadow:0 8px 24px rgba(97,218,251,.18)}
  .mp-btn.primary{background:linear-gradient(135deg,#61dafb,#9f6cff);color:#0a0a1a}
  .mp-btn.danger{background:linear-gradient(135deg,#ff4d6d,#ff8fa3);color:#1a0a0a}
  .mp-btn.ghost{background:transparent}
  .mp-btn:disabled{opacity:.4;cursor:not-allowed;transform:none}
  .mp-input{width:100%;padding:12px 14px;margin:6px 0;border:1px solid rgba(120,200,255,.24);border-radius:10px;background:rgba(255,255,255,.04);color:#eef2ff;font-family:inherit;font-size:15px;letter-spacing:.08em;text-transform:uppercase}
  .mp-input:focus{outline:none;border-color:#61dafb;box-shadow:0 0 0 3px rgba(97,218,251,.18)}
  .mp-row{display:flex;gap:10px;align-items:center}
  .mp-row>*{flex:1}
  .mp-label{font-size:11px;color:#9bb0d6;letter-spacing:.18em;font-weight:700;margin:14px 0 6px;text-transform:uppercase}
  .mp-pill{display:inline-block;padding:6px 12px;border-radius:999px;font-size:11px;letter-spacing:.16em;font-weight:700;background:rgba(120,200,255,.12);color:#9bedff;margin-right:6px}
  .mp-code{font-family:'Orbitron',sans-serif;font-size:34px;font-weight:900;letter-spacing:.36em;text-align:center;padding:18px;background:linear-gradient(135deg,rgba(97,218,251,.12),rgba(159,108,255,.12));border:1px dashed rgba(120,200,255,.4);border-radius:14px;color:#9bedff;margin:8px 0;cursor:pointer;user-select:all}
  .mp-modes{display:grid;grid-template-columns:1fr 1fr;gap:8px}
  .mp-mode{padding:14px;border:1px solid rgba(120,200,255,.18);border-radius:12px;cursor:pointer;text-align:center;transition:all .15s}
  .mp-mode.active{border-color:#61dafb;background:rgba(97,218,251,.08);box-shadow:0 0 24px rgba(97,218,251,.18)}
  .mp-mode b{display:block;font-size:14px;letter-spacing:.14em;margin-bottom:4px}
  .mp-mode small{color:#9bb0d6;font-size:11px}
  .mp-limit{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
  .mp-limit button{padding:12px;border:1px solid rgba(120,200,255,.18);border-radius:10px;background:transparent;color:#eef2ff;font-family:inherit;font-weight:700;cursor:pointer;font-size:16px}
  .mp-limit button.active{border-color:#9f6cff;background:rgba(159,108,255,.14);color:#d4a0ff}
  .mp-players{display:flex;flex-direction:column;gap:6px;margin:8px 0}
  .mp-player{display:flex;align-items:center;gap:10px;padding:10px 12px;background:rgba(255,255,255,.03);border:1px solid rgba(120,200,255,.1);border-radius:10px;font-size:13px}
  .mp-player .dot{width:12px;height:12px;border-radius:50%;box-shadow:0 0 8px currentColor}
  .mp-player .nm{flex:1;font-weight:700;letter-spacing:.04em}
  .mp-player .st{font-size:10px;letter-spacing:.18em;padding:3px 8px;border-radius:6px;background:rgba(255,209,102,.14);color:#ffd166}
  .mp-player .st.ready{background:rgba(76,224,179,.16);color:#86ffb0}
  .mp-player .crown{font-size:14px}
  .mp-status{position:fixed;top:12px;left:50%;transform:translateX(-50%);background:rgba(6,8,18,.92);border:1px solid rgba(120,200,255,.2);border-radius:10px;padding:8px 14px;font-size:12px;letter-spacing:.14em;color:#9bedff;z-index:9998;font-family:'Rajdhani',sans-serif;font-weight:700}
  .mp-status.err{border-color:rgba(255,77,109,.6);color:#ff8fa3}
  .mp-toast{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);background:rgba(6,8,18,.95);border:1px solid rgba(120,200,255,.3);border-radius:10px;padding:10px 18px;font-size:13px;color:#eef2ff;z-index:9999;font-weight:700;animation:mpToast 2.6s ease forwards}
  @keyframes mpToast{0%{opacity:0;transform:translate(-50%,12px)}10%,80%{opacity:1;transform:translate(-50%,0)}100%{opacity:0;transform:translate(-50%,-8px)}}
  #mp-online-btn{margin-top:8px}
  `;
  const styleEl = document.createElement('style');
  styleEl.textContent = css;
  document.head.appendChild(styleEl);

  // ---------- UTIL ----------
  function $(s, r = document) { return r.querySelector(s); }
  function el(tag, attrs = {}, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (k === 'class') e.className = v;
      else if (k === 'style') e.style.cssText = v;
      else if (k.startsWith('on')) e[k] = v;
      else e.setAttribute(k, v);
    }
    for (const k of kids) e.append(k?.nodeType ? k : document.createTextNode(k ?? ''));
    return e;
  }
  function toast(msg, isErr = false) {
    const t = el('div', { class: 'mp-toast' + (isErr ? ' err' : '') }, msg);
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 2700);
  }
  function setStatus(msg, isErr = false) {
    let s = $('#mp-status');
    if (!s) { s = el('div', { id: 'mp-status', class: 'mp-status' }); document.body.appendChild(s); }
    s.className = 'mp-status' + (isErr ? ' err' : '');
    s.textContent = msg;
  }
  function clearStatus() { $('#mp-status')?.remove(); }
  function makeRoomCode() { return Math.random().toString(36).slice(2, 8).toUpperCase(); }
  function closeModal() { $('#mp-modal')?.remove(); }
  function showModal(content) {
    closeModal();
    const m = el('div', { id: 'mp-modal', class: 'mp-modal' });
    const c = el('div', { class: 'mp-card' });
    c.append(...(Array.isArray(content) ? content : [content]));
    m.append(c);
    document.body.appendChild(m);
    return c;
  }

  // ---------- ONLINE BUTTON INJECTION ----------
  // The game has many menu versions (v461, v487, v504, v529...).
  // We poll the DOM and inject an "ONLINE" button next to any JOGAR / PLAY
  // button we find inside the overlay card.
  function injectOnlineButton() {
    if (MP.gameStarted) return;
    const overlay = $('#overlay') || $('.overlay');
    const playBtns = document.querySelectorAll(
      '#play461, #playBtn, #playBtn23, #play50, button[id^="play"]'
    );
    let host = null;
    for (const b of playBtns) {
      if (b.offsetParent === null) continue;
      if (b.parentElement?.querySelector('#mp-online-btn')) return;
      host = b.parentElement;
      break;
    }
    if (!host) return;
    const btn = el('button', {
      id: 'mp-online-btn',
      class: 'mp-btn primary',
      style: 'margin-top:10px;background:linear-gradient(135deg,#86ffb0,#61dafb);color:#06140a',
      onclick: openOnlineMenu,
    }, '🌐 ONLINE');
    // try to match the game's button class for visual consistency
    if (host.querySelector('.duneBtn461')) btn.classList.add('duneBtn461');
    if (host.querySelector('.main-btn')) btn.classList.add('main-btn');
    host.appendChild(btn);
  }
  // poll once a frame for ~lifetime; cheap
  setInterval(injectOnlineButton, 400);

  // ---------- MAIN MENU ----------
  function openOnlineMenu() {
    const nameInput = el('input', {
      class: 'mp-input', placeholder: 'Seu nome', value: MP.myName, maxlength: 14,
    });
    nameInput.oninput = () => { MP.myName = nameInput.value.trim() || MP.myName; };

    showModal([
      el('div', { class: 'mp-title' }, 'MODO ONLINE'),
      el('div', { class: 'mp-sub' }, 'Co-op P2P • Conexão direta via PeerJS'),
      el('div', { class: 'mp-label' }, 'Seu nome'),
      nameInput,
      el('div', { class: 'mp-label' }, 'O que quer fazer?'),
      el('button', { class: 'mp-btn primary', onclick: openCreateRoom }, '🛡️  CRIAR SALA'),
      el('button', { class: 'mp-btn', onclick: openJoinRoom }, '⚔️  JUNTAR-SE'),
      el('button', { class: 'mp-btn ghost', onclick: closeModal }, '← Voltar'),
    ]);
  }

  // ---------- CREATE ROOM ----------
  function openCreateRoom() {
    const modes = el('div', { class: 'mp-modes' });
    function modeBtn(key, name, desc) {
      const b = el('div', { class: 'mp-mode' + (MP.settings.mode === key ? ' active' : '') },
        el('b', {}, name), el('small', {}, desc));
      b.onclick = () => { MP.settings.mode = key; openCreateRoom(); };
      return b;
    }
    modes.append(
      modeBtn('normal', 'NORMAL', 'Waves clássicas + bosses'),
      modeBtn('rift', 'FISSURAS', 'Defesa de núcleo • torretas')
    );

    const lim = el('div', { class: 'mp-limit' });
    for (const n of [2, 3, 4]) {
      const b = el('button', { class: MP.settings.limit === n ? 'active' : '' }, n + ' players');
      b.onclick = () => { MP.settings.limit = n; openCreateRoom(); };
      lim.append(b);
    }

    showModal([
      el('div', { class: 'mp-title' }, 'CRIAR SALA'),
      el('div', { class: 'mp-sub' }, 'Você será o anfitrião. Inimigos e bosses terão HP x2.'),
      el('div', { class: 'mp-label' }, 'Modo de jogo'),
      modes,
      el('div', { class: 'mp-label' }, 'Limite de jogadores'),
      lim,
      el('div', { style: 'height:14px' }),
      el('button', { class: 'mp-btn primary', onclick: startHosting }, '✅ CRIAR SALA'),
      el('button', { class: 'mp-btn ghost', onclick: openOnlineMenu }, '← Voltar'),
    ]);
  }

  // ---------- JOIN ROOM ----------
  function openJoinRoom() {
    const input = el('input', {
      class: 'mp-input', placeholder: 'CÓDIGO DA SALA', maxlength: 6,
    });
    input.oninput = () => { input.value = input.value.toUpperCase().replace(/[^A-Z0-9]/g, ''); };

    showModal([
      el('div', { class: 'mp-title' }, 'JUNTAR-SE'),
      el('div', { class: 'mp-sub' }, 'Digite o código de 6 caracteres que o anfitrião compartilhou.'),
      el('div', { class: 'mp-label' }, 'Código da sala'),
      input,
      el('div', { style: 'height:8px' }),
      el('button', { class: 'mp-btn primary', onclick: () => {
        const code = input.value.trim();
        if (code.length !== 6) return toast('Código deve ter 6 caracteres', true);
        joinRoom(code);
      } }, '🔌 CONECTAR'),
      el('button', { class: 'mp-btn ghost', onclick: openOnlineMenu }, '← Voltar'),
    ]);
  }

  // ---------- PEERJS BOOT ----------
  function ensurePeer() {
    return new Promise((resolve, reject) => {
      if (typeof Peer === 'undefined') {
        reject(new Error('PeerJS não carregou. Verifique a tag <script> do peerjs.min.js.'));
        return;
      }
      resolve();
    });
  }

  // ---------- HOST ----------
  async function startHosting() {
    try { await ensurePeer(); } catch (e) { return toast(e.message, true); }
    MP.isHost = true;
    MP.roomCode = makeRoomCode();
    MP.players.clear();
    MP.conns.clear();
    setStatus('Criando sala...');
    MP.peer = new Peer(PEER_PREFIX + MP.roomCode, {
      debug: 1, config: { iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:global.stun.twilio.com:3478' },
      ] },
    });
    MP.peer.on('open', (id) => {
      MP.myId = id;
      MP.myColor = COLORS[0];
      MP.players.set(id, { name: MP.myName, color: MP.myColor, classKey: null, ready: true, host: true });
      clearStatus();
      openLobby();
    });
    MP.peer.on('connection', (conn) => {
      if (MP.players.size >= MP.settings.limit) { conn.on('open', () => { conn.send({ t: 'full' }); conn.close(); }); return; }
      hookConnection(conn, false);
    });
    MP.peer.on('error', (err) => { console.error('Peer error', err); setStatus('Erro: ' + err.type, true); });
  }

  // ---------- JOIN ----------
  async function joinRoom(code) {
    try { await ensurePeer(); } catch (e) { return toast(e.message, true); }
    MP.isHost = false;
    MP.roomCode = code;
    setStatus('Conectando à sala ' + code + '...');
    MP.peer = new Peer({ debug: 1, config: { iceServers: [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:global.stun.twilio.com:3478' },
    ] } });
    MP.peer.on('open', (id) => {
      MP.myId = id;
      const conn = MP.peer.connect(PEER_PREFIX + code, { reliable: true });
      hookConnection(conn, true);
    });
    MP.peer.on('error', (err) => {
      console.error('Peer error', err);
      setStatus('Falha: ' + err.type, true);
      if (err.type === 'peer-unavailable') toast('Sala não encontrada', true);
    });
  }

  function hookConnection(conn, iAmJoiner) {
    conn.on('open', () => {
      MP.conns.set(conn.peer, conn);
      if (iAmJoiner) {
        // identify myself
        conn.send({ t: 'hello', name: MP.myName });
      } else {
        // host: send initial state
        // wait for their hello to register
      }
    });
    conn.on('data', (msg) => onMessage(conn, msg));
    conn.on('close', () => {
      MP.conns.delete(conn.peer);
      MP.players.delete(conn.peer);
      if (MP.isHost) broadcastLobby();
      renderLobby();
      if (!MP.isHost && conn.peer === PEER_PREFIX + MP.roomCode) {
        toast('Conexão com o anfitrião perdida', true);
        leaveRoom();
      }
    });
  }

  // ---------- MESSAGES ----------
  function onMessage(conn, msg) {
    if (!msg || !msg.t) return;
    switch (msg.t) {
      case 'hello': {
        if (!MP.isHost) return;
        if (MP.players.size >= MP.settings.limit) { conn.send({ t: 'full' }); conn.close(); return; }
        const color = COLORS[MP.players.size % COLORS.length];
        MP.players.set(conn.peer, { name: msg.name || 'Player', color, classKey: null, ready: false });
        broadcastLobby();
        renderLobby();
        break;
      }
      case 'lobby': {
        // joiner update
        MP.settings = msg.settings;
        MP.players = new Map(msg.players);
        MP.myColor = MP.players.get(MP.myId)?.color || MP.myColor;
        renderLobby();
        break;
      }
      case 'ready': {
        if (!MP.isHost) return;
        const p = MP.players.get(conn.peer);
        if (p) { p.ready = msg.ready; p.classKey = msg.classKey || p.classKey; }
        broadcastLobby();
        renderLobby();
        break;
      }
      case 'start': {
        MP.settings = msg.settings;
        MP.players = new Map(msg.players);
        beginGame();
        break;
      }
      case 'state': {
        const p = MP.players.get(conn.peer);
        if (p) Object.assign(p, msg.s);
        // host relays to others
        if (MP.isHost) {
          for (const [pid, c] of MP.conns) {
            if (pid !== conn.peer) try { c.send({ t: 'state-of', id: conn.peer, s: msg.s }); } catch {}
          }
        }
        break;
      }
      case 'state-of': {
        const p = MP.players.get(msg.id);
        if (p) Object.assign(p, msg.s);
        break;
      }
      case 'chat': {
        toast('💬 ' + (MP.players.get(conn.peer)?.name || '?') + ': ' + msg.text);
        if (MP.isHost) {
          for (const [pid, c] of MP.conns) if (pid !== conn.peer) try { c.send(msg); } catch {}
        }
        break;
      }
      case 'full': toast('Sala cheia', true); leaveRoom(); break;
    }
  }

  function broadcastLobby() {
    const payload = { t: 'lobby', settings: MP.settings, players: Array.from(MP.players.entries()) };
    for (const c of MP.conns.values()) try { c.send(payload); } catch {}
  }

  // ---------- LOBBY UI ----------
  function openLobby() { renderLobby(); }
  function renderLobby() {
    if (MP.gameStarted) return;
    const code = MP.roomCode;
    const codeEl = el('div', { class: 'mp-code', title: 'Clique para copiar' }, code);
    codeEl.onclick = () => { navigator.clipboard?.writeText(code); toast('Código copiado!'); };

    const list = el('div', { class: 'mp-players' });
    let idx = 0;
    for (const [pid, p] of MP.players) {
      idx++;
      list.append(el('div', { class: 'mp-player' },
        el('span', { class: 'dot', style: 'color:' + p.color + ';background:' + p.color }),
        el('span', { class: 'nm' }, (p.host ? '👑 ' : '') + p.name + (pid === MP.myId ? ' (você)' : '')),
        el('span', { class: 'st' + (p.ready ? ' ready' : '') }, p.ready ? 'PRONTO' : 'ESCOLHENDO')
      ));
    }
    for (let i = MP.players.size; i < MP.settings.limit; i++) {
      list.append(el('div', { class: 'mp-player', style: 'opacity:.45' },
        el('span', { class: 'dot', style: 'background:#333;color:#333' }),
        el('span', { class: 'nm' }, 'Aguardando jogador...'),
        el('span', { class: 'st' }, 'VAZIO')));
    }

    const me = MP.players.get(MP.myId);
    const readyBtn = el('button', {
      class: 'mp-btn ' + (me?.ready ? 'danger' : 'primary'),
      onclick: () => {
        const cls = pickClassQuick();
        if (!cls && !me?.ready) return toast('Escolha uma classe primeiro', true);
        if (MP.isHost) { me.ready = !me.ready; me.classKey = cls || me.classKey; broadcastLobby(); }
        else {
          const conn = [...MP.conns.values()][0];
          me.ready = !me.ready; me.classKey = cls || me.classKey;
          try { conn?.send({ t: 'ready', ready: me.ready, classKey: me.classKey }); } catch {}
        }
        renderLobby();
      },
    }, me?.ready ? '✖  CANCELAR PRONTO' : '✓  ESTOU PRONTO  (' + (me?.classKey || 'sem classe') + ')');

    const allReady = MP.players.size >= 2 && [...MP.players.values()].every(p => p.ready);
    const startBtn = el('button', {
      class: 'mp-btn primary', disabled: !(MP.isHost && allReady),
      onclick: () => {
        const payload = { t: 'start', settings: MP.settings, players: Array.from(MP.players.entries()) };
        for (const c of MP.conns.values()) try { c.send(payload); } catch {}
        beginGame();
      },
    }, MP.isHost ? (allReady ? '🚀 INICIAR PARTIDA' : 'AGUARDANDO TODOS PRONTOS') : 'AGUARDANDO HOST INICIAR');

    showModal([
      el('div', { class: 'mp-title' }, 'SALA ' + (MP.isHost ? '(HOST)' : '')),
      el('div', { class: 'mp-sub' }, 'Compartilhe o código com seus amigos'),
      codeEl,
      el('div', { style: 'text-align:center;margin:4px 0 14px' },
        el('span', { class: 'mp-pill' }, 'MODO: ' + (MP.settings.mode === 'rift' ? 'FISSURAS' : 'NORMAL')),
        el('span', { class: 'mp-pill' }, 'LIMITE: ' + MP.settings.limit)),
      el('div', { class: 'mp-label' }, 'Jogadores'),
      list,
      el('div', { style: 'height:8px' }),
      readyBtn, startBtn,
      el('button', { class: 'mp-btn ghost', onclick: leaveRoom }, '← Sair da sala'),
    ]);
  }

  function pickClassQuick() {
    // Try to detect the chosen class from the game's globals if any
    try {
      const list = Object.keys(window.CLASSES || {});
      if (!list.length) return null;
      return list[Math.floor(Math.random() * list.length)]; // random for simplicity; user can extend
    } catch { return null; }
  }

  function leaveRoom() {
    try { MP.peer?.destroy(); } catch {}
    MP.peer = null;
    MP.conns.clear();
    MP.players.clear();
    MP.roomCode = null;
    MP.isHost = false;
    MP.gameStarted = false;
    clearStatus();
    closeModal();
    if (MP.tickTimer) { clearInterval(MP.tickTimer); MP.tickTimer = null; }
    MP.overlay?.remove(); MP.overlay = null;
    window.openStartMenu?.();
  }

  // ---------- BEGIN GAME ----------
  function beginGame() {
    closeModal();
    MP.gameStarted = true;
    setStatus('🌐 ONLINE • ' + MP.players.size + ' jogadores • ' + (MP.settings.mode === 'rift' ? 'FISSURAS' : 'NORMAL'));
    applyCoopModifiers();
    // Trigger the game's existing start path
    const me = MP.players.get(MP.myId);
    const cls = me?.classKey || Object.keys(window.CLASSES || {})[0];
    if (MP.settings.mode === 'rift') window.__forceNextRift507 = true;
    try {
      if (typeof window.resetGame === 'function') window.resetGame(cls);
      else if (typeof window.openClassMenu === 'function') window.openClassMenu();
    } catch (e) { console.error('Falha ao iniciar jogo', e); toast('Não consegui iniciar o jogo', true); }
    document.getElementById('overlay')?.classList.add('hidden');
    setupOverlay();
    startTick();
  }

  // ---------- CO-OP MODIFIERS ----------
  function applyCoopModifiers() {
    if (MP.modifiersApplied) return;
    MP.modifiersApplied = true;
    // 1) Enemy + boss HP x2: patch any enemy spawn function we can find
    try {
      const targets = ['spawnEnemy', 'spawnBoss', 'addEnemy', 'createEnemy', 'makeEnemy'];
      for (const name of targets) {
        const fn = window[name];
        if (typeof fn !== 'function') continue;
        window[name] = function () {
          const r = fn.apply(this, arguments);
          try {
            if (r && typeof r === 'object' && typeof r.hp === 'number') {
              r.hp *= 2; if (typeof r.maxHp === 'number') r.maxHp *= 2;
            }
          } catch {}
          return r;
        };
      }
      // Also patch game.enemies array push as a fallback (after game starts)
      const tryPatchEnemies = () => {
        if (!window.game || !Array.isArray(window.game.enemies)) return;
        if (window.game.__mpPatched) return;
        window.game.__mpPatched = true;
        const origPush = window.game.enemies.push;
        window.game.enemies.push = function (...args) {
          for (const e of args) {
            if (e && typeof e.hp === 'number' && !e.__mpBuff) {
              e.__mpBuff = true; e.hp *= 2; if (typeof e.maxHp === 'number') e.maxHp *= 2;
            }
          }
          return origPush.apply(this, args);
        };
      };
      const iv = setInterval(() => { tryPatchEnemies(); if (window.game?.__mpPatched) clearInterval(iv); }, 200);
      setTimeout(() => clearInterval(iv), 30000);
    } catch (e) { console.warn('Falha ao aplicar HP x2', e); }

    // 2) Bigger map: scale the canvas display size up via CSS (does not change gameplay coords)
    try {
      const cv = document.getElementById('game');
      if (cv) {
        cv.style.width = 'min(110vw,1600px)';
        cv.style.maxWidth = 'none';
      }
    } catch {}
  }

  // ---------- POSITION SYNC ----------
  function startTick() {
    if (MP.tickTimer) clearInterval(MP.tickTimer);
    MP.tickTimer = setInterval(() => {
      const g = window.game;
      if (!g || !g.player) return;
      const s = {
        x: g.player.x, y: g.player.y,
        hp: g.player.hp, maxHp: g.player.maxHp,
        wave: g.wave || 0,
      };
      const me = MP.players.get(MP.myId);
      if (me) Object.assign(me, s);
      const payload = { t: 'state', s };
      for (const c of MP.conns.values()) try { c.send(payload); } catch {}
    }, 1000 / TICK_HZ);
  }

  // ---------- OVERLAY (ghosts of other players) ----------
  function setupOverlay() {
    MP.overlay?.remove();
    const cv = document.getElementById('game');
    if (!cv) return;
    const o = document.createElement('canvas');
    o.id = 'mp-overlay';
    o.style.cssText = 'position:absolute;pointer-events:none;z-index:6;border-radius:16px';
    MP.overlay = o;
    document.body.appendChild(o);
    function sync() {
      const r = cv.getBoundingClientRect();
      o.style.left = r.left + 'px';
      o.style.top = r.top + 'px';
      o.style.width = r.width + 'px';
      o.style.height = r.height + 'px';
      o.width = cv.width; o.height = cv.height;
    }
    sync();
    new ResizeObserver(sync).observe(cv);
    window.addEventListener('resize', sync);

    function draw() {
      if (!MP.gameStarted) return;
      const ctx = o.getContext('2d');
      ctx.clearRect(0, 0, o.width, o.height);
      for (const [pid, p] of MP.players) {
        if (pid === MP.myId) continue;
        if (typeof p.x !== 'number') continue;
        // ghost body
        ctx.save();
        ctx.globalAlpha = 0.85;
        ctx.fillStyle = p.color;
        ctx.shadowColor = p.color; ctx.shadowBlur = 18;
        ctx.beginPath(); ctx.arc(p.x, p.y, 14, 0, Math.PI * 2); ctx.fill();
        ctx.restore();
        // name + hp bar
        ctx.save();
        ctx.fillStyle = '#fff'; ctx.font = '700 12px Rajdhani, Arial';
        ctx.textAlign = 'center';
        ctx.shadowColor = '#000'; ctx.shadowBlur = 4;
        ctx.fillText(p.name || '?', p.x, p.y - 24);
        if (typeof p.hp === 'number' && typeof p.maxHp === 'number' && p.maxHp > 0) {
          const w = 36, h = 4, hpw = Math.max(0, w * (p.hp / p.maxHp));
          ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(p.x - w / 2, p.y + 18, w, h);
          ctx.fillStyle = '#ff4d6d'; ctx.fillRect(p.x - w / 2, p.y + 18, hpw, h);
        }
        ctx.restore();
      }
      requestAnimationFrame(draw);
    }
    requestAnimationFrame(draw);
  }

  // ---------- HOTKEY ----------
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && $('#mp-modal')) { /* keep modal */ }
  });

  // ---------- BOOT ----------
  console.log('%c[Chrono Shards Multiplayer] carregado','color:#61dafb;font-weight:bold');
})();
