/* ============================================================
   CHRONO SHARDS — MULTIPLAYER MODULE v2 (PeerJS, P2P, co-op leve)
   Fluxo de lobby:
     1) Host cria sala -> recebe código
     2) Outros entram com o código
     3) Quando todos estão conectados, o botão "Selecionar Personagem"
        libera para CADA jogador
     4) Ao clicar abre uma tela de seleção de classe (lê window.CLASSES)
     5) Após escolher, o card do jogador mostra a classe escolhida
        (ícone + nome) no lugar de "escolhendo..."
     6) Quando TODOS escolherem, o botão "Iniciar" libera só pro host
     7) Host inicia -> todos chamam window.resetGame(classKey) e o
        co-op leve (fantasmas + chat + revive + wave compartilhada)
        começa
   ============================================================ */
(() => {
'use strict';

// ---------- CONFIG ----------
const TICK_HZ = 20;
const REVIVE_TIME_MS = 3000;
const REVIVE_RANGE = 90;
const CHAT_MAX = 6;
const VERSION = 'mp-v2';

// ---------- ESTADO ----------
const state = {
  peer: null,
  isHost: false,
  myId: null,
  myName: 'P' + Math.floor(Math.random()*900+100),
  roomCode: null,
  hpMult: 1,
  riftMode: false,
  // peers conectados (host: vários; client: só o host)
  conns: new Map(), // id -> DataConnection
  // jogadores no lobby/jogo: id -> {id,name,classKey,ready,x,y,hp,maxHp,wave,score,down}
  players: new Map(),
  started: false,
  chat: [],
  reviveTarget: null,
  reviveStart: 0,
};

// ---------- UTIL ----------
const $ = (sel, root=document) => root.querySelector(sel);
const el = (tag, props={}, ...kids) => {
  const n = document.createElement(tag);
  Object.assign(n.style, props.style||{});
  for (const k in props) if (k!=='style') n[k]=props[k];
  for (const k of kids) n.append(k.nodeType?k:document.createTextNode(k));
  return n;
};
const log = (...a) => console.log('[MP]', ...a);
const code6 = () => Math.random().toString(36).slice(2,8).toUpperCase();

function getClasses(){
  // Tenta várias fontes possíveis no jogo principal
  const c = window.CLASSES || window.Classes || window.GAME_CLASSES || null;
  if (!c) return [];
  if (Array.isArray(c)) return c.map((x,i)=>({key:x.key||x.id||String(i), name:x.name||x.title||x.key||('Classe '+i), icon:x.icon||x.emoji||'⚔️', desc:x.desc||x.description||''}));
  // objeto chaveado
  return Object.entries(c).map(([k,v])=>({key:k, name:v.name||v.title||k, icon:v.icon||v.emoji||'⚔️', desc:v.desc||v.description||''}));
}

// ---------- UI ROOT ----------
let ui = {};
function buildUI(){
  if (document.getElementById('mp-root')) return;
  const root = el('div', { id:'mp-root', style:{
    position:'fixed', inset:'0', zIndex: 99999, pointerEvents:'none',
    fontFamily:'system-ui, sans-serif', color:'#fff'
  }});

  // Botão flutuante de abrir lobby
  const openBtn = el('button', {
    textContent:'🎮 Multiplayer',
    style:{
      position:'absolute', top:'8px', right:'8px', pointerEvents:'auto',
      padding:'8px 12px', background:'#222', color:'#fff', border:'1px solid #555',
      borderRadius:'8px', cursor:'pointer', fontWeight:'bold'
    }
  });
  openBtn.onclick = () => toggleLobby(true);
  root.append(openBtn);

  // Painel lobby
  const panel = el('div', { id:'mp-lobby', style:{
    position:'absolute', top:'50%', left:'50%', transform:'translate(-50%,-50%)',
    width:'min(560px, 92vw)', maxHeight:'88vh', overflow:'auto',
    background:'rgba(15,15,20,0.96)', border:'1px solid #444', borderRadius:'12px',
    padding:'16px', pointerEvents:'auto', display:'none',
    boxShadow:'0 10px 40px rgba(0,0,0,0.6)'
  }});
  panel.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px">
      <h2 style="margin:0;font-size:18px">Multiplayer — Co-op Leve</h2>
      <button id="mp-close" style="background:#333;color:#fff;border:1px solid #555;border-radius:6px;padding:4px 10px;cursor:pointer">×</button>
    </div>

    <div id="mp-stage-connect">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px">
        <label style="font-size:12px;opacity:.8">Seu nome
          <input id="mp-name" maxlength="14" style="width:100%;padding:6px;background:#111;color:#fff;border:1px solid #444;border-radius:6px"/>
        </label>
        <label style="font-size:12px;opacity:.8">HP dos inimigos (host)
          <select id="mp-hp" style="width:100%;padding:6px;background:#111;color:#fff;border:1px solid #444;border-radius:6px">
            <option value="1">x1</option><option value="1.5">x1.5</option>
            <option value="2" selected>x2</option><option value="3">x3</option>
          </select>
        </label>
      </div>
      <label style="display:flex;align-items:center;gap:6px;font-size:13px;margin-bottom:10px">
        <input id="mp-rift" type="checkbox"/> Forçar Fissuras (modo 507)
      </label>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button id="mp-host" style="flex:1;padding:10px;background:#2a6;color:#fff;border:0;border-radius:8px;cursor:pointer;font-weight:bold">Criar sala</button>
        <div style="flex:2;display:flex;gap:6px">
          <input id="mp-code" placeholder="Código da sala" style="flex:1;padding:10px;background:#111;color:#fff;border:1px solid #444;border-radius:8px;text-transform:uppercase"/>
          <button id="mp-join" style="padding:10px 14px;background:#26a;color:#fff;border:0;border-radius:8px;cursor:pointer;font-weight:bold">Entrar</button>
        </div>
      </div>
      <div id="mp-status" style="margin-top:10px;font-size:12px;opacity:.8"></div>
    </div>

    <div id="mp-stage-lobby" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
        <div>Sala: <b id="mp-room-label" style="font-family:monospace;font-size:18px">------</b>
          <button id="mp-copy" style="margin-left:6px;padding:2px 8px;background:#333;color:#fff;border:1px solid #555;border-radius:4px;cursor:pointer;font-size:11px">copiar</button>
        </div>
        <div id="mp-role" style="font-size:12px;opacity:.8"></div>
      </div>
      <div id="mp-players" style="display:flex;flex-direction:column;gap:6px;margin-bottom:12px"></div>
      <div style="display:flex;gap:8px">
        <button id="mp-pick" disabled style="flex:1;padding:12px;background:#444;color:#aaa;border:0;border-radius:8px;cursor:not-allowed;font-weight:bold">Selecionar Personagem</button>
        <button id="mp-start" disabled style="flex:1;padding:12px;background:#444;color:#aaa;border:0;border-radius:8px;cursor:not-allowed;font-weight:bold">Iniciar</button>
      </div>
      <div id="mp-lobby-msg" style="margin-top:8px;font-size:12px;opacity:.8;text-align:center"></div>
    </div>

    <div id="mp-stage-pick" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px">
        <h3 style="margin:0;font-size:16px">Escolha seu personagem</h3>
        <button id="mp-pick-back" style="background:#333;color:#fff;border:1px solid #555;border-radius:6px;padding:4px 10px;cursor:pointer">voltar</button>
      </div>
      <div id="mp-class-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px"></div>
    </div>
  `;
  root.append(panel);

  // Chat overlay (in-game)
  const chat = el('div', { id:'mp-chat', style:{
    position:'absolute', left:'8px', bottom:'8px', width:'320px',
    pointerEvents:'none', display:'none'
  }});
  chat.innerHTML = `
    <div id="mp-chat-log" style="display:flex;flex-direction:column;gap:2px;margin-bottom:4px;font-size:12px;text-shadow:0 1px 2px #000"></div>
    <input id="mp-chat-input" placeholder="Enter para conversar..." style="width:100%;padding:6px;background:rgba(0,0,0,0.6);color:#fff;border:1px solid #555;border-radius:6px;display:none;pointer-events:auto"/>
  `;
  root.append(chat);

  // Team panel (in-game)
  const team = el('div', { id:'mp-team', style:{
    position:'absolute', top:'48px', right:'8px', width:'200px',
    background:'rgba(0,0,0,0.5)', border:'1px solid #444', borderRadius:'8px',
    padding:'6px', fontSize:'12px', display:'none'
  }});
  root.append(team);

  document.body.append(root);

  ui = {
    openBtn, panel, chat, team,
    close: $('#mp-close', panel),
    stageConnect: $('#mp-stage-connect', panel),
    stageLobby: $('#mp-stage-lobby', panel),
    stagePick: $('#mp-stage-pick', panel),
    name: $('#mp-name', panel),
    hp: $('#mp-hp', panel),
    rift: $('#mp-rift', panel),
    host: $('#mp-host', panel),
    code: $('#mp-code', panel),
    join: $('#mp-join', panel),
    status: $('#mp-status', panel),
    roomLabel: $('#mp-room-label', panel),
    copy: $('#mp-copy', panel),
    role: $('#mp-role', panel),
    playersList: $('#mp-players', panel),
    pick: $('#mp-pick', panel),
    start: $('#mp-start', panel),
    lobbyMsg: $('#mp-lobby-msg', panel),
    pickBack: $('#mp-pick-back', panel),
    classGrid: $('#mp-class-grid', panel),
    chatLog: $('#mp-chat-log', chat),
    chatInput: $('#mp-chat-input', chat),
  };
  ui.name.value = state.myName;

  ui.close.onclick = () => toggleLobby(false);
  ui.host.onclick = onHostClick;
  ui.join.onclick = onJoinClick;
  ui.copy.onclick = () => { if (state.roomCode) navigator.clipboard?.writeText(state.roomCode); ui.copy.textContent='copiado!'; setTimeout(()=>ui.copy.textContent='copiar',1200); };
  ui.pick.onclick = () => { if (!ui.pick.disabled) showPickScreen(); };
  ui.start.onclick = () => { if (!ui.start.disabled) hostStartGame(); };
  ui.pickBack.onclick = () => { ui.stagePick.style.display='none'; ui.stageLobby.style.display=''; };
  ui.chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      const msg = ui.chatInput.value.trim();
      if (msg) sendChat(msg);
      ui.chatInput.value=''; ui.chatInput.style.display='none'; ui.chatInput.blur();
      e.stopPropagation();
    } else if (e.key === 'Escape') {
      ui.chatInput.value=''; ui.chatInput.style.display='none'; ui.chatInput.blur();
    }
    e.stopPropagation();
  });

  window.addEventListener('keydown', (e) => {
    if (!state.started) return;
    if (document.activeElement === ui.chatInput) return;
    if (e.key === 'Enter') {
      ui.chatInput.style.display='block'; ui.chatInput.focus(); e.preventDefault();
    }
  });
}

function toggleLobby(show){
  ui.panel.style.display = show ? '' : 'none';
}

// ---------- CONEXÃO ----------
function ensurePeer(id){
  return new Promise((resolve, reject) => {
    if (!window.Peer) { reject(new Error('PeerJS não carregado')); return; }
    const p = id ? new Peer(id) : new Peer();
    p.on('open', (pid) => { state.peer = p; state.myId = pid; resolve(p); });
    p.on('error', (err) => { setStatus('Erro: '+err.type); console.error(err); });
    p.on('connection', onIncomingConn);
  });
}

function onHostClick(){
  state.myName = (ui.name.value||state.myName).slice(0,14);
  state.hpMult = parseFloat(ui.hp.value) || 1;
  state.riftMode = ui.rift.checked;
  state.isHost = true;
  state.roomCode = 'CS-' + code6();
  setStatus('Criando sala...');
  ensurePeer(state.roomCode).then(() => {
    state.players.set(state.myId, makeLocalPlayerEntry());
    enterLobbyStage();
    setStatus('Sala criada. Compartilhe o código.');
  }).catch(e => setStatus('Falhou: '+e.message));
}

function onJoinClick(){
  const code = (ui.code.value||'').trim().toUpperCase();
  if (!code) return setStatus('Digite o código.');
  state.myName = (ui.name.value||state.myName).slice(0,14);
  state.isHost = false;
  state.roomCode = code.startsWith('CS-') ? code : ('CS-'+code);
  setStatus('Conectando...');
  ensurePeer().then(() => {
    const conn = state.peer.connect(state.roomCode, { reliable:true });
    conn.on('open', () => {
      state.conns.set(state.roomCode, conn);
      conn.send({ t:'hello', name: state.myName, v: VERSION });
      state.players.set(state.myId, makeLocalPlayerEntry());
      enterLobbyStage();
      setStatus('Conectado.');
    });
    conn.on('data', (d) => handleData(conn, d));
    conn.on('close', () => { setStatus('Conexão fechada.'); });
    conn.on('error', (e) => { setStatus('Erro conn: '+e.message); });
  }).catch(e => setStatus('Falhou: '+e.message));
}

function onIncomingConn(conn){
  // Só host aceita conexões nesse modelo (estrela)
  if (!state.isHost) return;
  conn.on('open', () => {
    state.conns.set(conn.peer, conn);
    log('peer entrou:', conn.peer);
  });
  conn.on('data', (d) => handleData(conn, d));
  conn.on('close', () => {
    state.conns.delete(conn.peer);
    state.players.delete(conn.peer);
    broadcastLobby();
    renderLobby();
  });
}

function makeLocalPlayerEntry(){
  return { id: state.myId, name: state.myName, classKey: null, ready: false,
           x:0, y:0, hp:100, maxHp:100, wave:1, score:0, down:false, host: state.isHost };
}

// ---------- PROTOCOLO ----------
function handleData(conn, d){
  if (!d || !d.t) return;
  if (state.isHost){
    switch(d.t){
      case 'hello': {
        state.players.set(conn.peer, {
          id: conn.peer, name: (d.name||'P').slice(0,14), classKey:null, ready:false,
          x:0,y:0,hp:100,maxHp:100,wave:1,score:0,down:false, host:false
        });
        broadcastLobby(); renderLobby();
        break;
      }
      case 'pickClass': {
        const p = state.players.get(conn.peer);
        if (p){ p.classKey = d.classKey; p.ready = true; }
        broadcastLobby(); renderLobby();
        break;
      }
      case 'state': {
        const p = state.players.get(conn.peer);
        if (p){ Object.assign(p, d.s); }
        // host repassa estados para todos
        broadcastState();
        break;
      }
      case 'chat': broadcastChat(d.from||'?', d.msg||''); break;
      case 'revive': {
        // alguém reviveu outro
        const tgt = state.players.get(d.target);
        if (tgt){ tgt.down=false; tgt.hp = Math.max(1, Math.floor(tgt.maxHp*0.5)); }
        broadcastLobby();
        break;
      }
    }
  } else {
    switch(d.t){
      case 'lobby': {
        state.players = new Map(d.players.map(p => [p.id, p]));
        state.hpMult = d.hpMult; state.riftMode = d.riftMode;
        renderLobby();
        break;
      }
      case 'start': {
        startLocalGame(d.classByPlayer[state.myId]);
        break;
      }
      case 'state': {
        // d.players: array
        for (const p of d.players){
          if (p.id === state.myId) continue;
          const cur = state.players.get(p.id) || {};
          state.players.set(p.id, Object.assign(cur, p));
        }
        break;
      }
      case 'chat': pushChat(d.from, d.msg); break;
    }
  }
}

function broadcastLobby(){
  if (!state.isHost) return;
  const payload = {
    t:'lobby',
    players: Array.from(state.players.values()),
    hpMult: state.hpMult,
    riftMode: state.riftMode,
  };
  for (const c of state.conns.values()) try{ c.send(payload); }catch(e){}
}

function broadcastState(){
  if (!state.isHost) return;
  const payload = { t:'state', players: Array.from(state.players.values()).map(p => ({
    id:p.id, name:p.name, classKey:p.classKey, x:p.x, y:p.y, hp:p.hp, maxHp:p.maxHp,
    wave:p.wave, score:p.score, down:p.down
  })) };
  for (const c of state.conns.values()) try{ c.send(payload); }catch(e){}
}

function broadcastChat(from, msg){
  pushChat(from, msg);
  if (!state.isHost) return;
  const payload = { t:'chat', from, msg };
  for (const c of state.conns.values()) try{ c.send(payload); }catch(e){}
}

function sendChat(msg){
  if (state.isHost) broadcastChat(state.myName, msg);
  else { pushChat(state.myName, msg); const c = state.conns.get(state.roomCode); if (c) c.send({ t:'chat', from: state.myName, msg }); }
}

function pushChat(from, msg){
  state.chat.push({from, msg, t: Date.now()});
  if (state.chat.length > CHAT_MAX) state.chat.shift();
  renderChat();
}

// ---------- ETAPAS / RENDER ----------
function setStatus(msg){ if (ui.status) ui.status.textContent = msg; log(msg); }

function enterLobbyStage(){
  ui.stageConnect.style.display='none';
  ui.stageLobby.style.display='';
  ui.stagePick.style.display='none';
  ui.roomLabel.textContent = state.roomCode;
  ui.role.textContent = state.isHost ? 'Você é HOST' : 'Você é CLIENTE';
  if (state.isHost) broadcastLobby();
  renderLobby();
}

function renderLobby(){
  if (!ui.playersList) return;
  const players = Array.from(state.players.values());
  ui.playersList.innerHTML = '';
  const classes = getClasses();
  const classMap = new Map(classes.map(c=>[c.key,c]));

  for (const p of players){
    const c = p.classKey ? classMap.get(p.classKey) : null;
    const row = el('div', { style:{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'8px 10px', background:'rgba(255,255,255,0.04)',
      border:'1px solid #333', borderRadius:'8px'
    }});
    const left = el('div', { style:{display:'flex',alignItems:'center',gap:8} });
    left.append(el('span', { style:{fontSize:'18px'} }, c?c.icon:'❔'));
    const info = el('div');
    info.append(el('div', { style:{fontWeight:'bold'} }, p.name + (p.host?' 👑':'')));
    info.append(el('div', { style:{fontSize:'11px',opacity:.7} },
      p.classKey ? (c?c.name:p.classKey) : 'escolhendo...'));
    left.append(info);
    const right = el('div', { style:{fontSize:'12px'} },
      p.ready ? '✅ pronto' : '⏳');
    row.append(left, right);
    ui.playersList.append(row);
  }

  const everyoneIn = players.length >= 2;
  const me = state.players.get(state.myId);
  const allReady = players.length>=2 && players.every(p=>p.ready);

  // Botão Selecionar Personagem
  if (everyoneIn && me && !me.ready){
    enableBtn(ui.pick, '#26a', 'Selecionar Personagem');
  } else if (me && me.ready){
    enableBtn(ui.pick, '#555', 'Trocar Personagem');
  } else {
    disableBtn(ui.pick, `Aguardando jogadores (${players.length}/2+)`);
  }

  // Botão Iniciar (só host)
  if (state.isHost){
    if (allReady) enableBtn(ui.start, '#2a6', 'Iniciar');
    else disableBtn(ui.start, allReady?'Iniciar':'Aguardando seleções...');
  } else {
    disableBtn(ui.start, allReady ? 'Host vai iniciar...' : 'Aguardando seleções...');
  }

  ui.lobbyMsg.textContent = everyoneIn
    ? (allReady ? (state.isHost?'Tudo pronto! Clique em Iniciar.':'Aguardando o host iniciar...') : 'Cada jogador precisa escolher um personagem.')
    : 'Compartilhe o código com seu amigo.';
}

function enableBtn(b, color, text){
  b.disabled=false; b.style.background=color; b.style.color='#fff';
  b.style.cursor='pointer'; b.textContent=text;
}
function disableBtn(b, text){
  b.disabled=true; b.style.background='#333'; b.style.color='#888';
  b.style.cursor='not-allowed'; b.textContent=text;
}

function showPickScreen(){
  const classes = getClasses();
  ui.classGrid.innerHTML = '';
  if (classes.length === 0){
    ui.classGrid.innerHTML = '<div style="grid-column:1/-1;padding:12px;background:#311;border:1px solid #633;border-radius:8px">window.CLASSES não encontrado no jogo. Verifique se o multiplayer.js está carregado APÓS o script principal.</div>';
  }
  for (const c of classes){
    const card = el('button', { style:{
      display:'flex', flexDirection:'column', gap:4, padding:'10px',
      background:'#1a1a22', color:'#fff', border:'1px solid #444',
      borderRadius:'8px', cursor:'pointer', textAlign:'left'
    }});
    card.onmouseenter=()=>card.style.borderColor='#88f';
    card.onmouseleave=()=>card.style.borderColor='#444';
    card.append(el('div', { style:{fontSize:'22px'} }, c.icon));
    card.append(el('div', { style:{fontWeight:'bold'} }, c.name));
    if (c.desc) card.append(el('div', { style:{fontSize:'11px',opacity:.7} }, c.desc.slice(0,80)));
    card.onclick = () => choosePlayerClass(c.key);
    ui.classGrid.append(card);
  }
  ui.stageLobby.style.display='none';
  ui.stagePick.style.display='';
}

function choosePlayerClass(classKey){
  const me = state.players.get(state.myId);
  if (me){ me.classKey = classKey; me.ready = true; }
  if (state.isHost){
    broadcastLobby();
  } else {
    const c = state.conns.get(state.roomCode);
    if (c) c.send({ t:'pickClass', classKey });
  }
  ui.stagePick.style.display='none';
  ui.stageLobby.style.display='';
  renderLobby();
}

// ---------- INICIAR JOGO ----------
function hostStartGame(){
  if (!state.isHost) return;
  const classByPlayer = {};
  for (const p of state.players.values()) classByPlayer[p.id] = p.classKey;
  // envia para todos
  const payload = { t:'start', classByPlayer };
  for (const c of state.conns.values()) try{ c.send(payload); }catch(e){}
  startLocalGame(classByPlayer[state.myId]);
}

function startLocalGame(classKey){
  state.started = true;
  toggleLobby(false);
  ui.chat.style.display=''; ui.team.style.display='';
  installEnemyHpMultiplier();
  if (state.riftMode) try{ window.__forceNextRift507 = true; }catch(e){}
  try {
    if (typeof window.resetGame === 'function') window.resetGame(classKey);
    else if (typeof window.startGame === 'function') window.startGame(classKey);
    else console.warn('[MP] window.resetGame não encontrado');
  } catch(e){ console.error('[MP] erro ao iniciar:', e); }

  startTickLoop();
  startOverlayLoop();
}

// ---------- HP MULT (host) ----------
function installEnemyHpMultiplier(){
  if (!state.isHost) return;
  const mult = state.hpMult;
  if (mult === 1) return;
  const g = window.game; if (!g) return;
  // patch funções comuns
  const wrap = (fn) => function(...a){
    const r = fn.apply(this, a);
    try{
      const e = r || (g.enemies && g.enemies[g.enemies.length-1]);
      if (e && typeof e.hp === 'number'){ e.hp *= mult; e.maxHp = (e.maxHp||e.hp)*1; }
    }catch{}
    return r;
  };
  for (const k of ['spawnEnemy','addEnemy','createEnemy']){
    if (typeof g[k]==='function' && !g[k].__mpWrapped){
      const o = g[k]; g[k] = wrap(o); g[k].__mpWrapped = true;
    }
  }
}

// ---------- LOOP DE SYNC ----------
function startTickLoop(){
  setInterval(() => {
    const g = window.game; if (!g) return;
    const me = state.players.get(state.myId);
    if (!me) return;
    const pl = g.player || (g.players && g.players[0]) || null;
    if (pl){
      me.x = pl.x||0; me.y = pl.y||0;
      me.hp = pl.hp||0; me.maxHp = pl.maxHp||100;
      me.down = !!(pl.dead || pl.down || me.hp<=0);
    }
    me.wave = g.wave || g.currentWave || me.wave;
    me.score = g.score || me.score;

    if (state.isHost){
      // host atualiza próprio slot e faz broadcast geral
      broadcastState();
    } else {
      const c = state.conns.get(state.roomCode);
      if (c) try{ c.send({ t:'state', s:{ x:me.x,y:me.y,hp:me.hp,maxHp:me.maxHp,wave:me.wave,score:me.score,down:me.down }}); }catch{}
    }
    renderTeam();
  }, 1000/TICK_HZ);
}

// ---------- OVERLAY (fantasmas) ----------
let overlayCanvas = null, octx = null;
function startOverlayLoop(){
  if (overlayCanvas) return;
  const gameCanvas = document.querySelector('canvas');
  if (!gameCanvas) return;
  overlayCanvas = document.createElement('canvas');
  overlayCanvas.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:9998';
  document.body.append(overlayCanvas);
  octx = overlayCanvas.getContext('2d');
  const resize = () => {
    const r = gameCanvas.getBoundingClientRect();
    overlayCanvas.width = r.width; overlayCanvas.height = r.height;
    overlayCanvas.style.left = r.left+'px'; overlayCanvas.style.top = r.top+'px';
    overlayCanvas.style.width = r.width+'px'; overlayCanvas.style.height = r.height+'px';
  };
  resize(); window.addEventListener('resize', resize);

  const draw = () => {
    if (!octx) return;
    octx.clearRect(0,0,overlayCanvas.width, overlayCanvas.height);
    const g = window.game; const cam = g && (g.camera||g.cam) || {x:0,y:0};
    for (const p of state.players.values()){
      if (p.id === state.myId) continue;
      const sx = (p.x||0) - (cam.x||0) + overlayCanvas.width/2;
      const sy = (p.y||0) - (cam.y||0) + overlayCanvas.height/2;
      octx.globalAlpha = p.down ? 0.4 : 0.85;
      octx.fillStyle = p.down ? '#a33' : '#5af';
      octx.beginPath(); octx.arc(sx,sy,12,0,Math.PI*2); octx.fill();
      octx.globalAlpha=1;
      octx.fillStyle='#fff'; octx.font='12px sans-serif'; octx.textAlign='center';
      octx.fillText(p.name, sx, sy-18);
      // hp
      octx.fillStyle='#400'; octx.fillRect(sx-15,sy-32,30,4);
      octx.fillStyle='#0f4'; octx.fillRect(sx-15,sy-32,30*Math.max(0,(p.hp/(p.maxHp||1))),4);
      if (p.down){
        octx.fillStyle='#fa0'; octx.fillText('Segure E para reviver', sx, sy+24);
      }
    }
    handleRevive();
    requestAnimationFrame(draw);
  };
  draw();
}

// ---------- REVIVE ----------
const keys = {};
window.addEventListener('keydown', e => { keys[e.key.toLowerCase()] = true; });
window.addEventListener('keyup', e => { keys[e.key.toLowerCase()] = false; });

function handleRevive(){
  if (!state.started) return;
  const me = state.players.get(state.myId); if (!me) return;
  let target = null, bestD = REVIVE_RANGE;
  for (const p of state.players.values()){
    if (p.id===state.myId) continue;
    if (!p.down) continue;
    const d = Math.hypot((p.x||0)-(me.x||0),(p.y||0)-(me.y||0));
    if (d<bestD){ bestD=d; target=p; }
  }
  if (target && keys['e']){
    if (state.reviveTarget !== target.id){
      state.reviveTarget = target.id; state.reviveStart = Date.now();
    }
    const pct = Math.min(1,(Date.now()-state.reviveStart)/REVIVE_TIME_MS);
    drawReviveBar(target, pct);
    if (pct>=1){
      // envia revive
      const payload = { t:'revive', target: target.id };
      if (state.isHost){
        const tp = state.players.get(target.id);
        if (tp){ tp.down=false; tp.hp=Math.max(1,Math.floor(tp.maxHp*0.5)); }
        broadcastLobby();
      } else {
        const c = state.conns.get(state.roomCode); if (c) c.send(payload);
      }
      state.reviveTarget=null;
    }
  } else {
    state.reviveTarget=null;
  }
}

function drawReviveBar(p, pct){
  if (!octx) return;
  const g = window.game; const cam = g && (g.camera||g.cam) || {x:0,y:0};
  const sx = (p.x||0) - (cam.x||0) + overlayCanvas.width/2;
  const sy = (p.y||0) - (cam.y||0) + overlayCanvas.height/2;
  octx.fillStyle='#222'; octx.fillRect(sx-20,sy+30,40,5);
  octx.fillStyle='#ff0'; octx.fillRect(sx-20,sy+30,40*pct,5);
}

// ---------- CHAT/TEAM RENDER ----------
function renderChat(){
  if (!ui.chatLog) return;
  ui.chatLog.innerHTML='';
  for (const m of state.chat){
    const d = el('div', {}, `${m.from}: ${m.msg}`);
    d.style.background='rgba(0,0,0,0.4)'; d.style.padding='2px 6px'; d.style.borderRadius='4px'; d.style.width='fit-content';
    ui.chatLog.append(d);
  }
}
function renderTeam(){
  if (!ui.team) return;
  const classes = new Map(getClasses().map(c=>[c.key,c]));
  ui.team.innerHTML = '<div style="font-weight:bold;margin-bottom:4px">Equipe</div>';
  for (const p of state.players.values()){
    const c = classes.get(p.classKey);
    const row = el('div', { style:{display:'flex',justifyContent:'space-between',gap:4,opacity:p.down?0.5:1} });
    row.append(el('span', {}, `${c?c.icon:'❔'} ${p.name}${p.id===state.myId?' (você)':''}`));
    row.append(el('span', {}, `W${p.wave||1} ${Math.max(0,p.hp|0)}/${p.maxHp|0}`));
    ui.team.append(row);
  }
}

// ---------- BOOT ----------
function boot(){
  if (!window.Peer){
    console.warn('[MP] PeerJS ainda não disponível, tentando de novo...');
    return setTimeout(boot, 500);
  }
  buildUI();
  log('Multiplayer pronto. Versão', VERSION);
}
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();

})();
