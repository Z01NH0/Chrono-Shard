/* ============================================================
   CHRONO SHARDS — MULTIPLAYER v4 (PeerJS, P2P co-op)
   Mudanças em relação ao v3:
     - Lobby reorganizado: tela inicial com 2 botões grandes
       (CRIAR SALA / ENTRAR EM SALA). Entrar pede só o código.
     - "HP dos inimigos" virou Dificuldade (Fácil/Médio/Difícil/Extremo).
     - BUGFIX CRÍTICO: ao iniciar a partida, fechamos o #overlay
       do menu de seleção de classes do jogo (era ele que escondia
       o jogo e fazia parecer que "nada acontecia").
     - Cliente: trava o avanço local de waves e spawn local; usa
       snapshot do host como fonte da verdade dos inimigos.
     - Host: aplica multiplicador de HP por dificuldade aos inimigos.
   ============================================================ */
(() => {
'use strict';

// ===================== CONFIG =====================
const VERSION       = 'mp-v4';
const TICK_HZ       = 20;
const ENEMY_HZ      = 15;
const REVIVE_TIME   = 3000;
const REVIVE_RANGE  = 90;
const CHAT_MAX      = 8;
const PEER_PREFIX   = 'cs3-';

const DIFFICULTY = {
  easy:    { label:'Fácil',   mult:1.0, color:'#4ce0b3' },
  medium:  { label:'Médio',   mult:1.6, color:'#46d6ff' },
  hard:    { label:'Difícil', mult:2.4, color:'#ffd166' },
  extreme: { label:'Extremo', mult:3.5, color:'#ff4d6d' },
};

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
};

// ===================== UTIL =====================
const $ = (s, r=document) => r.querySelector(s);
const log = (...a) => console.log('%c[MP]', 'color:#6cf', ...a);
const warn = (...a) => console.warn('[MP]', ...a);
const rid = () => Math.random().toString(36).slice(2,8).toUpperCase();
const hpMult = () => (DIFFICULTY[S.difficulty]||DIFFICULTY.medium).mult;

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
  .mp-class-card{ display:flex; flex-direction:column; gap:6px; padding:12px;
                  background:linear-gradient(180deg,rgba(20,30,55,0.7),rgba(10,15,30,0.7));
                  border:1px solid rgba(120,200,255,0.18); border-radius:12px;
                  cursor:pointer; transition:all .15s; text-align:left; }
  .mp-class-card:hover{ border-color:#61dafb; transform:translateY(-2px); box-shadow:0 8px 24px rgba(97,218,251,0.25); }
  .mp-class-card.picked{ border-color:#4ce0b3; box-shadow:0 0 0 2px rgba(76,224,179,0.3); }
  .mp-diff{ display:grid; grid-template-columns:repeat(4,1fr); gap:6px; }
  .mp-diff button{ padding:10px 6px; border-radius:8px; border:1px solid rgba(120,200,255,0.18);
                   background:rgba(6,8,18,0.6); color:#eef2ff; font-family:inherit;
                   font-weight:700; font-size:12px; cursor:pointer; transition:all .15s; }
  .mp-diff button.on{ border-color: currentColor; box-shadow:0 0 0 2px currentColor inset; }
  .mp-fade-in{ animation:mpFade .2s ease-out; }
  @keyframes mpFade{ from{opacity:0; transform:translateY(4px);} to{opacity:1; transform:none;} }
  `;
  document.head.append(el('style', { id:'mp-style', textContent: css }));
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
    position:'absolute', top:'12px', right:'12px', pointerEvents:'auto', fontSize:'13px'
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
        <div style="font-size:11px;opacity:.6;letter-spacing:.2em;margin-top:2px">MULTIPLAYER CO-OP</div>
      </div>
      <button id="mp-close" class="mp-btn ghost" style="padding:6px 10px">×</button>
    </div>

    <!-- STAGE HOME -->
    <div id="mp-stage-home" style="display:none">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:8px">
        <button id="mp-go-create" class="mp-btn primary huge">
          <span style="font-size:30px">🛡️</span>
          <span>CRIAR SALA</span>
          <span style="font-size:10px;opacity:.7;font-weight:600">Você será o host</span>
        </button>
        <button id="mp-go-join" class="mp-btn success huge">
          <span style="font-size:30px">⚔️</span>
          <span>ENTRAR EM SALA</span>
          <span style="font-size:10px;opacity:.7;font-weight:600">Use o código de um amigo</span>
        </button>
      </div>
      <div style="margin-top:18px;padding:10px 12px;background:rgba(97,218,251,0.06);
                  border:1px solid rgba(97,218,251,0.18);border-radius:10px;font-size:12px;opacity:.85">
        💡 Co-op P2P. Cada partida usa o host como autoridade dos inimigos e bosses.
      </div>
      <div id="mp-home-msg" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <!-- STAGE CREATE -->
    <div id="mp-stage-create" style="display:none">
      <button class="mp-btn ghost" data-back style="font-size:12px;padding:6px 10px;margin-bottom:14px">← voltar</button>
      <div style="display:grid;gap:12px">
        <div>
          <span class="mp-label">SEU NOME</span>
          <input id="mp-name-c" class="mp-input" maxlength="14" />
        </div>
        <div>
          <span class="mp-label">DIFICULDADE</span>
          <div id="mp-diff" class="mp-diff"></div>
        </div>
        <label style="display:flex;align-items:center;gap:8px;font-size:13px;cursor:pointer">
          <input id="mp-rift" type="checkbox"/>
          Forçar Fissuras (modo 507)
        </label>
        <button id="mp-host" class="mp-btn primary" style="padding:14px">🛡️ CRIAR SALA</button>
      </div>
      <div id="mp-status-c" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <!-- STAGE JOIN -->
    <div id="mp-stage-join" style="display:none">
      <button class="mp-btn ghost" data-back style="font-size:12px;padding:6px 10px;margin-bottom:14px">← voltar</button>
      <div style="display:grid;gap:12px">
        <div>
          <span class="mp-label">SEU NOME</span>
          <input id="mp-name-j" class="mp-input" maxlength="14" />
        </div>
        <div>
          <span class="mp-label">CÓDIGO DA SALA</span>
          <input id="mp-code" class="mp-input" placeholder="ex: A1B2C3" style="text-transform:uppercase;letter-spacing:.2em;text-align:center;font-size:18px;font-weight:700"/>
        </div>
        <button id="mp-join" class="mp-btn success" style="padding:14px">⚔️ ENTRAR NA SALA</button>
      </div>
      <div id="mp-status-j" style="margin-top:10px;font-size:11px;opacity:.7;text-align:center"></div>
    </div>

    <!-- STAGE LOBBY -->
    <div id="mp-stage-lobby" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
        <div>
          <div class="mp-label" style="margin:0">CÓDIGO DA SALA</div>
          <div id="mp-room-label" style="font-family:Orbitron,sans-serif;font-size:24px;font-weight:900;letter-spacing:.2em;color:#61dafb">------</div>
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

    <!-- STAGE PICK -->
    <div id="mp-stage-pick" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
        <div style="font-size:16px;font-weight:700">Escolha seu personagem</div>
        <button id="mp-pick-back" class="mp-btn ghost" style="font-size:12px;padding:6px 10px">← voltar</button>
      </div>
      <div id="mp-class-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:10px"></div>
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
    close:     $('#mp-close', panel),
    sHome:     $('#mp-stage-home', panel),
    sCreate:   $('#mp-stage-create', panel),
    sJoin:     $('#mp-stage-join', panel),
    sLobby:    $('#mp-stage-lobby', panel),
    sPick:     $('#mp-stage-pick', panel),
    goCreate:  $('#mp-go-create', panel),
    goJoin:    $('#mp-go-join', panel),
    nameC:     $('#mp-name-c', panel),
    nameJ:     $('#mp-name-j', panel),
    diff:      $('#mp-diff', panel),
    rift:      $('#mp-rift', panel),
    host:      $('#mp-host', panel),
    code:      $('#mp-code', panel),
    join:      $('#mp-join', panel),
    statusC:   $('#mp-status-c', panel),
    statusJ:   $('#mp-status-j', panel),
    homeMsg:   $('#mp-home-msg', panel),
    roomLabel: $('#mp-room-label', panel),
    copy:      $('#mp-copy', panel),
    role:      $('#mp-role', panel),
    plist:     $('#mp-players', panel),
    pick:      $('#mp-pick', panel),
    start:     $('#mp-start', panel),
    lmsg:      $('#mp-lobby-msg', panel),
    pickBack:  $('#mp-pick-back', panel),
    grid:      $('#mp-class-grid', panel),
    chatLog:   $('#mp-chat-log', chat),
    chatInput: $('#mp-chat-input', chat),
  };

  UI.nameC.value = S.myName;
  UI.nameJ.value = S.myName;
  renderDifficulty();

  UI.close.onclick = () => toggleLobby(false);
  UI.goCreate.onclick = () => showStage('create');
  UI.goJoin.onclick   = () => showStage('join');
  panel.querySelectorAll('[data-back]').forEach(b => b.onclick = () => showStage('home'));

  UI.host.onclick = onHost;
  UI.join.onclick = onJoin;
  UI.copy.onclick = () => {
    if (!S.roomCode) return;
    const short = S.roomCode.replace(PEER_PREFIX,'').toUpperCase();
    navigator.clipboard?.writeText(short);
    UI.copy.textContent='✓ copiado!';
    setTimeout(()=>UI.copy.textContent='📋 copiar', 1200);
  };
  UI.pick.onclick = () => { if (!UI.pick.disabled) showPick(); };
  UI.start.onclick = () => { if (!UI.start.disabled) hostStart(); };
  UI.pickBack.onclick = () => showStage('lobby');

  UI.code.addEventListener('input', e => { e.target.value = e.target.value.toUpperCase(); });

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
    if (e.key === 'Enter'){
      e.preventDefault();
      UI.chatInput.style.display='block';
      UI.chatInput.focus();
    }
  });

  if (!window.__MP_BRIDGE_READY__) {
    UI.homeMsg.innerHTML = '⚠️ Bridge não detectado. Cole <code>mp-bridge.js</code> no final do &lt;script&gt; principal.';
  }
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
  const el = which==='j' ? UI.statusJ : UI.statusC;
  if (el) el.textContent = m;
  log(m);
}

// ===================== PEERJS =====================
function ensurePeer(id){
  return new Promise((resolve,reject)=>{
    if (!window.Peer) return reject(new Error('PeerJS não carregado'));
    const p = id ? new Peer(id) : new Peer();
    let opened = false;
    p.on('open', pid => { opened=true; S.peer=p; S.myId=pid; resolve(p); });
    p.on('error', err => {
      warn('peer error', err);
      if (!opened) reject(err);
      else log('Erro de rede:', err.type||err.message);
    });
    p.on('connection', onIncoming);
  });
}

function onHost(){
  S.myName  = (UI.nameC.value||S.myName).slice(0,14);
  S.riftMode= UI.rift.checked;
  S.isHost  = true;
  S.roomCode= PEER_PREFIX + rid();
  setStatus('Criando sala...', 'c');
  ensurePeer(S.roomCode).then(()=>{
    S.players.set(S.myId, mkLocalEntry());
    enterLobby();
  }).catch(e => setStatus('Falhou: '+e.message, 'c'));
}

function onJoin(){
  const raw = (UI.code.value||'').trim().toUpperCase();
  if (!raw) return setStatus('Digite o código.', 'j');
  S.myName = (UI.nameJ.value||S.myName).slice(0,14);
  S.isHost = false;
  S.roomCode = raw.toLowerCase().startsWith(PEER_PREFIX) ? raw.toLowerCase() : (PEER_PREFIX+raw.toLowerCase());
  setStatus('Conectando...', 'j');
  ensurePeer().then(()=>{
    const conn = S.peer.connect(S.roomCode, { reliable:true });
    let opened=false;
    const timeout = setTimeout(()=>{ if(!opened) setStatus('Timeout. Verifique o código.', 'j'); }, 8000);
    conn.on('open', ()=>{
      opened=true; clearTimeout(timeout);
      S.conns.set(S.roomCode, conn);
      conn.send({ t:'hello', name:S.myName, v:VERSION });
      S.players.set(S.myId, mkLocalEntry());
      enterLobby();
    });
    conn.on('data', d => handleData(conn, d));
    conn.on('close', ()=> setStatus('Conexão fechada.', 'j'));
    conn.on('error', e => setStatus('Erro: '+e.message, 'j'));
  }).catch(e => setStatus('Falhou: '+e.message, 'j'));
}

function onIncoming(conn){
  if (!S.isHost) return;
  conn.on('open', ()=>{ S.conns.set(conn.peer, conn); log('peer joined', conn.peer); });
  conn.on('data', d => handleData(conn, d));
  conn.on('close', ()=>{
    S.conns.delete(conn.peer); S.players.delete(conn.peer);
    broadcastLobby(); renderLobby();
  });
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
      case 'dmg': hostApplyDamage(d.mpId, d.amount); break;
      case 'chat': bcastChat(d.from||'?', d.msg||''); break;
      case 'revive': {
        const tgt = S.players.get(d.target);
        if (tgt){ tgt.down=false; tgt.hp = Math.max(1, Math.floor(tgt.maxHp*0.5)); }
        broadcastLobby(); break;
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
      case 'state': {
        for (const p of d.players){
          if (p.id === S.myId) continue;
          const cur = S.players.get(p.id) || {};
          S.players.set(p.id, Object.assign(cur, p));
        }
        break;
      }
      case 'enemies': applyEnemySnapshot(d.list, d.wave); break;
      case 'chat': pushChat(d.from, d.msg); break;
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
  UI.roomLabel.textContent = S.roomCode.replace(PEER_PREFIX,'').toUpperCase();
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
  b.disabled = !enabled;
  b.textContent = text;
  b.className = 'mp-btn ' + variant;
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
    for (const c of classes){
      const card = el('button', { className:'mp-class-card' + (me?.classKey===c.key?' picked':'') });
      card.append(el('div', { style:{display:'flex',justifyContent:'space-between',alignItems:'center'} },
        el('span', { style:{fontSize:'26px'} }, c.icon),
        c.tag ? el('span', { className:'mp-chip', style:{
          background:c.tagColor+'22', color:c.tagColor, border:'1px solid '+c.tagColor+'44'
        }}, c.tag) : ''
      ));
      card.append(el('div', { style:{fontWeight:'700',fontSize:'15px'} }, c.name));
      if (c.desc) card.append(el('div', { style:{fontSize:'11px',opacity:.65,lineHeight:'1.35'} },
        c.desc.length>110 ? c.desc.slice(0,110)+'…' : c.desc));
      card.onclick = () => pickClass(c.key);
      UI.grid.append(card);
    }
  }
  showStage('pick');
}

function pickClass(key){
  const me = S.players.get(S.myId);
  if (me){ me.classKey = key; me.ready = true; }
  if (S.isHost) broadcastLobby();
  else { const c = S.conns.get(S.roomCode); if (c) send(c, { t:'pickClass', classKey:key }); }
  showStage('lobby');
  renderLobby();
}

// ===================== INICIAR JOGO =====================
function hostStart(){
  if (!S.isHost) return;
  const classByPlayer = {};
  for (const p of S.players.values()) classByPlayer[p.id] = p.classKey;
  bcast({ t:'start', classByPlayer });
  startLocalGame(classByPlayer[S.myId]);
}

function closeGameOverlay(){
  // BUGFIX: o jogo usa #overlay para mostrar menus (inclusive seleção
  // inicial de classe). Se não escondermos, fica preto e "nada acontece".
  const ov = document.getElementById('overlay');
  if (ov) ov.classList.add('hidden');
  // Algumas builds usam style.display
  if (ov && getComputedStyle(ov).display !== 'none') ov.style.display = 'none';
}

function startLocalGame(classKey){
  if (!classKey) { warn('sem classe!'); return; }
  S.started = true;
  toggleLobby(false);
  UI.chat.style.display = '';
  UI.team.style.display = '';
  if (S.riftMode) { try { window.__forceNextRift507 = true; } catch(e){} }
  try {
    if (typeof window.resetGame === 'function') {
      window.resetGame(classKey);
    } else {
      warn('window.resetGame não disponível');
      return;
    }
  } catch(e){ console.error('[MP] erro ao iniciar:', e); return; }

  // CRÍTICO: esconder o overlay do menu original do jogo
  closeGameOverlay();
  // E garantir de novo após próximos ticks, caso o jogo reabra
  setTimeout(closeGameOverlay, 50);
  setTimeout(closeGameOverlay, 250);

  setTimeout(()=>{
    installEnemyPatch();
    startTickLoop();
    startEnemySync();
    startOverlay();
  }, 80);
}

// ===================== INIMIGOS COMPARTILHADOS =====================
function installEnemyPatch(){
  const g = window.game; if (!g) return;

  if (S.isHost){
    const orig = window.spawnEnemy;
    if (typeof orig === 'function' && !orig.__mpWrapped){
      const wrapped = function(...a){
        const before = g.enemies ? g.enemies.length : 0;
        const r = orig.apply(this, a);
        const e = (r && typeof r === 'object') ? r :
                  (g.enemies && g.enemies.length > before ? g.enemies[g.enemies.length-1] : null);
        if (e){
          const m = hpMult();
          if (typeof e.hp === 'number' && m !== 1){
            e.hp = e.hp * m;
            e.maxHp = (e.maxHp || e.hp) * m / m;
            if (typeof e.maxHp === 'number') e.maxHp = e.maxHp * m;
          }
          if (!e.__mpId) e.__mpId = S.enemyIdCounter++;
        }
        return r;
      };
      wrapped.__mpWrapped = true;
      try { window.spawnEnemy = wrapped; } catch(e){}
    }
  } else {
    // CLIENTE: stub spawn e congela avanço local de waves (host comanda)
    try {
      const noop = function(){
        // ainda incrementa o contador local pra evitar travar updateWaveState
        const gg = window.game;
        if (gg) gg.enemiesSpawnedThisWave = (gg.enemiesSpawnedThisWave||0) + 1;
        return null;
      };
      noop.__mpWrapped = true;
      window.spawnEnemy = noop;
    } catch(e){}

    // Bloqueia o avanço local de wave / abertura de loja (host controla)
    if (typeof window.updateWaveState === 'function' && !window.updateWaveState.__mpWrapped){
      const stub = function(){};
      stub.__mpWrapped = true;
      try { window.updateWaveState = stub; } catch(e){}
    }
    if (typeof window.openShopMenu === 'function' && !window.openShopMenu.__mpWrapped){
      const stub = function(){};
      stub.__mpWrapped = true;
      try { window.openShopMenu = stub; } catch(e){}
    }

    installClientBulletHook();
  }
}

function installClientBulletHook(){
  const g = window.game; if (!g) return;
  if (g.__mpBulletHook) return;
  g.__mpBulletHook = true;

  const loop = ()=>{
    if (!S.started || S.isHost) return;
    const gg = window.game;
    if (gg && Array.isArray(gg.bullets) && Array.isArray(gg.enemies)){
      const bullets = gg.bullets;
      const enemies = gg.enemies;
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

function hostApplyDamage(mpId, amount){
  const g = window.game; if (!g || !Array.isArray(g.enemies)) return;
  for (const e of g.enemies){
    if (e && e.__mpId === mpId){
      if (typeof e.hp === 'number') e.hp -= amount;
      break;
    }
  }
}

function startEnemySync(){
  if (!S.isHost) return;
  setInterval(()=>{
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
  const existing = new Map();
  for (const e of g.enemies) if (e && e.__mpId) existing.set(e.__mpId, e);
  const next = [];
  for (const s of list){
    let e = existing.get(s.i);
    if (!e){ e = makeShellEnemy(s); }
    else {
      e.x = s.x; e.y = s.y;
      e.hp = s.h; e.maxHp = s.M;
      e.r = s.r;
    }
    next.push(e);
  }
  g.enemies = next;
  if (wave) { g.wave = wave; g.currentWave = wave; }
}

function makeShellEnemy(s){
  return {
    __mpId: s.i, __mpShell: true,
    x: s.x, y: s.y, vx:0, vy:0,
    hp: s.h, maxHp: s.M,
    r: s.r||14,
    type: s.t||'normal',
    boss: !!s.b, elite: !!s.el,
    color: s.c||'#ff6b9d',
    dead: false,
    update(){}, draw(){},
  };
}

// ===================== SYNC DE JOGADORES =====================
function startTickLoop(){
  setInterval(()=>{
    const g = window.game; if (!g) return;
    const me = S.players.get(S.myId); if (!me) return;
    const pl = g.player || (g.players && g.players[0]) || null;
    if (pl){
      me.x = pl.x||0; me.y = pl.y||0;
      me.hp = pl.hp||0; me.maxHp = pl.maxHp||100;
      me.down = !!(pl.dead || pl.down || me.hp<=0);
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
    const cam = (g && (g.camera||g.cam)) || {x:0,y:0};
    const gc = document.querySelector('canvas#game') || document.querySelector('canvas');
    const scale = gc ? oc.width / gc.width : 1;
    for (const p of S.players.values()){
      if (p.id === S.myId) continue;
      const sx = ((p.x||0) - (cam.x||0) + (gc?gc.width/2:oc.width/2)) * scale;
      const sy = ((p.y||0) - (cam.y||0) + (gc?gc.height/2:oc.height/2)) * scale;
      octx.globalAlpha = p.down ? 0.45 : 0.85;
      octx.fillStyle = p.down ? '#ff4d6d' : '#61dafb';
      octx.beginPath(); octx.arc(sx,sy,12*scale,0,Math.PI*2); octx.fill();
      octx.globalAlpha = 1;
      octx.fillStyle='#fff'; octx.font=`${12*scale|0}px 'Rajdhani',sans-serif`; octx.textAlign='center';
      octx.fillText(p.name, sx, sy - 18*scale);
      octx.fillStyle='rgba(0,0,0,0.6)'; octx.fillRect(sx-18*scale, sy-30*scale, 36*scale, 4*scale);
      octx.fillStyle='#4ce0b3';
      octx.fillRect(sx-18*scale, sy-30*scale, 36*scale*Math.max(0,(p.hp||0)/(p.maxHp||1)), 4*scale);
      if (p.down){
        octx.fillStyle='#ffd166';
        octx.fillText('Segure E para reviver', sx, sy + 26*scale);
      }
    }
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
  let target=null, best=REVIVE_RANGE;
  for (const p of S.players.values()){
    if (p.id===S.myId || !p.down) continue;
    const d = Math.hypot((p.x||0)-(me.x||0), (p.y||0)-(me.y||0));
    if (d<best){ best=d; target=p; }
  }
  if (target && keysDown['e']){
    if (S.reviveTarget !== target.id){
      S.reviveTarget = target.id; S.reviveStart = Date.now();
    }
    const pct = Math.min(1, (Date.now()-S.reviveStart)/REVIVE_TIME);
    drawReviveBar(target, pct);
    if (pct >= 1){
      const payload = { t:'revive', target: target.id };
      if (S.isHost){
        const tp = S.players.get(target.id);
        if (tp){ tp.down=false; tp.hp = Math.max(1, Math.floor(tp.maxHp*0.5)); }
        broadcastLobby();
      } else {
        const c = S.conns.get(S.roomCode); if (c) send(c, payload);
      }
      S.reviveTarget = null;
    }
  } else {
    S.reviveTarget = null;
  }
}

function drawReviveBar(p, pct){
  if (!octx) return;
  const g = window.game;
  const cam = (g && (g.camera||g.cam)) || {x:0,y:0};
  const gc = document.querySelector('canvas#game') || document.querySelector('canvas');
  const scale = gc ? oc.width / gc.width : 1;
  const sx = ((p.x||0) - (cam.x||0) + (gc?gc.width/2:oc.width/2)) * scale;
  const sy = ((p.y||0) - (cam.y||0) + (gc?gc.height/2:oc.height/2)) * scale;
  octx.fillStyle='rgba(0,0,0,0.7)'; octx.fillRect(sx-24*scale, sy+32*scale, 48*scale, 6*scale);
  octx.fillStyle='#ffd166'; octx.fillRect(sx-24*scale, sy+32*scale, 48*scale*pct, 6*scale);
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
        p.name + (p.id===S.myId?' (você)':''))));
    row.append(el('span', { style:{fontSize:'10px',opacity:.8} },
      `W${p.wave||1} · ${Math.max(0,p.hp|0)}/${p.maxHp|0}`));
    UI.team.append(row);
  }
}

// ===================== BOOT =====================
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
