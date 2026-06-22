/* ============================================================
   CHRONO SHARDS — MULTIPLAYER v3 (PeerJS, P2P co-op)
   Recursos:
     - Lobby com UI revisada (cards, estados claros)
     - Seleção de personagem usando window.CLASSES (via mp-bridge.js)
     - Host autoritativo: inimigos compartilhados (mesmos inimigos
       para todo mundo, dano somado)
     - Fantasmas dos outros jogadores, chat, revive, HUD da equipe
   Pré-requisitos no HTML, NESTA ORDEM:
     <script src="https://unpkg.com/peerjs@1.5.4/dist/peerjs.min.js"></script>
     <script> ... jogo principal ... + mp-bridge.js no final ... </script>
     <script src="multiplayer.js"></script>
   ============================================================ */
(() => {
'use strict';

// ===================== CONFIG =====================
const VERSION       = 'mp-v3';
const TICK_HZ       = 20;        // sync de jogadores
const ENEMY_HZ      = 15;        // sync de inimigos (host -> clientes)
const REVIVE_TIME   = 3000;
const REVIVE_RANGE  = 90;
const CHAT_MAX      = 8;
const PEER_PREFIX   = 'cs3-';    // namespace PeerJS para evitar colisão

// ===================== ESTADO =====================
const S = {
  peer: null, isHost: false, myId: null,
  myName: 'P' + Math.floor(Math.random()*900+100),
  roomCode: null,
  hpMult: 2, riftMode: false,
  conns: new Map(),                 // id -> DataConnection
  players: new Map(),               // id -> playerEntry
  started: false,
  chat: [],
  reviveTarget: null, reviveStart: 0,
  // host-only: mapeia enemy -> id estável
  enemyIdCounter: 1,
  // client-only: snapshot recente de inimigos vindo do host
  remoteEnemies: new Map(),         // mpId -> snapshot
};

// ===================== UTIL =====================
const $ = (s, r=document) => r.querySelector(s);
const log = (...a) => console.log('%c[MP]', 'color:#6cf', ...a);
const warn = (...a) => console.warn('[MP]', ...a);
const rid = () => Math.random().toString(36).slice(2,8).toUpperCase();

function getClasses(){
  const c = window.CLASSES || window.Classes || null;
  if (!c) return [];
  if (Array.isArray(c)) {
    return c.map((x,i)=>({
      key: x.key||x.id||String(i),
      name: x.name||x.title||x.key||('Classe '+i),
      icon: x.icon||x.emoji||'⚔️',
      tag:  x.tag||'',
      tagColor: x.tagColor||'#6cf',
      color: x.color||'#6cf',
      desc: x.desc||x.description||''
    }));
  }
  return Object.entries(c).map(([k,v])=>({
    key: k,
    name: v.name||k,
    icon: v.icon||v.emoji||'⚔️',
    tag:  v.tag||'',
    tagColor: v.tagColor||'#6cf',
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
  .mp-input{ font-family:inherit; background:rgba(6,8,18,0.7); border:1px solid rgba(120,200,255,0.2);
             color:#eef2ff; border-radius:8px; padding:10px 12px; width:100%; }
  .mp-input:focus{ outline:none; border-color:#61dafb; box-shadow:0 0 0 2px rgba(97,218,251,0.2); }
  .mp-card{ background:rgba(6,8,18,0.92); border:1px solid rgba(120,200,255,0.15);
            backdrop-filter:blur(16px); border-radius:16px;
            box-shadow:0 20px 60px rgba(0,0,0,0.6), inset 0 0 30px rgba(80,140,255,0.04); }
  .mp-title{ font-family:'Orbitron',sans-serif; font-weight:900; letter-spacing:.15em;
             background:linear-gradient(90deg,#61dafb,#9f6cff,#ff6b9d);
             -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
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
  .mp-class-card:hover{ border-color:#61dafb; transform:translateY(-2px);
                        box-shadow:0 8px 24px rgba(97,218,251,0.25); }
  .mp-class-card.picked{ border-color:#4ce0b3; box-shadow:0 0 0 2px rgba(76,224,179,0.3); }
  .mp-bar{ height:4px; background:rgba(255,255,255,0.08); border-radius:4px; overflow:hidden; }
  .mp-bar > i{ display:block; height:100%; background:linear-gradient(90deg,#ffd166,#ff6b9d); }
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

  // Botão flutuante
  const openBtn = el('button', { className:'mp-btn primary', style:{
    position:'absolute', top:'12px', right:'12px', pointerEvents:'auto', fontSize:'13px'
  }}, '🎮 Multiplayer');
  openBtn.onclick = () => toggleLobby(true);
  root.append(openBtn);

  // Painel
  const panel = el('div', { id:'mp-panel', className:'mp-card mp-fade-in', style:{
    position:'absolute', top:'50%', left:'50%', transform:'translate(-50%,-50%)',
    width:'min(640px,94vw)', maxHeight:'90vh', overflow:'auto',
    padding:'22px', pointerEvents:'auto', display:'none'
  }});

  panel.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:18px">
      <div>
        <div class="mp-title" style="font-size:13px;margin-bottom:2px">CHRONO SHARDS</div>
        <div style="font-size:18px;font-weight:700">Multiplayer Co-op</div>
      </div>
      <button id="mp-close" class="mp-btn ghost" style="padding:6px 12px;font-size:18px;line-height:1">×</button>
    </div>

    <!-- STAGE: CONNECT -->
    <div id="mp-stage-connect">
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px">
        <label style="font-size:11px;letter-spacing:.1em;opacity:.7;font-weight:600">SEU NOME
          <input id="mp-name" class="mp-input" maxlength="14" style="margin-top:4px"/>
        </label>
        <label style="font-size:11px;letter-spacing:.1em;opacity:.7;font-weight:600">HP DOS INIMIGOS (HOST)
          <select id="mp-hp" class="mp-input" style="margin-top:4px">
            <option value="1">x1.0 (padrão)</option>
            <option value="1.5">x1.5</option>
            <option value="2" selected>x2.0 (recomendado p/ 2p)</option>
            <option value="3">x3.0</option>
          </select>
        </label>
      </div>
      <label style="display:flex;align-items:center;gap:8px;margin-bottom:16px;cursor:pointer">
        <input id="mp-rift" type="checkbox"/>
        <span style="font-size:13px">Forçar Fissuras (modo 507)</span>
      </label>
      <div style="display:grid;grid-template-columns:1fr;gap:12px">
        <button id="mp-host" class="mp-btn success">🛡️  CRIAR SALA (você será o host)</button>
        <div style="display:flex;gap:8px;align-items:stretch">
          <input id="mp-code" class="mp-input" placeholder="Código da sala (ex: AB12CD)" style="text-transform:uppercase;flex:1"/>
          <button id="mp-join" class="mp-btn primary" style="white-space:nowrap">⚔️  ENTRAR</button>
        </div>
      </div>
      <div id="mp-status" style="margin-top:14px;font-size:12px;opacity:.75;min-height:18px"></div>
    </div>

    <!-- STAGE: LOBBY -->
    <div id="mp-stage-lobby" style="display:none">
      <div class="mp-row" style="margin-bottom:14px">
        <div>
          <div style="font-size:11px;opacity:.6;letter-spacing:.1em">CÓDIGO DA SALA</div>
          <div style="font-family:'Orbitron',monospace;font-size:20px;font-weight:900;letter-spacing:.1em" id="mp-room-label">------</div>
        </div>
        <div style="display:flex;flex-direction:column;align-items:flex-end;gap:6px">
          <span id="mp-role" class="mp-chip" style="background:rgba(255,209,102,0.15);color:#ffd166;border:1px solid rgba(255,209,102,0.35)">HOST</span>
          <button id="mp-copy" class="mp-btn ghost" style="padding:4px 10px;font-size:11px">📋 copiar</button>
        </div>
      </div>

      <div style="font-size:11px;letter-spacing:.1em;opacity:.6;margin-bottom:8px">JOGADORES</div>
      <div id="mp-players" style="display:flex;flex-direction:column;gap:8px;margin-bottom:18px"></div>

      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
        <button id="mp-pick" class="mp-btn primary" disabled>Selecionar Personagem</button>
        <button id="mp-start" class="mp-btn success" disabled>Iniciar Partida</button>
      </div>
      <div id="mp-lobby-msg" style="margin-top:12px;font-size:12px;opacity:.7;text-align:center;min-height:18px"></div>
    </div>

    <!-- STAGE: PICK -->
    <div id="mp-stage-pick" style="display:none">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
        <div style="font-size:16px;font-weight:700">Escolha seu personagem</div>
        <button id="mp-pick-back" class="mp-btn ghost" style="padding:6px 12px;font-size:12px">← voltar</button>
      </div>
      <div id="mp-class-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:10px"></div>
    </div>
  `;
  root.append(panel);

  // Chat in-game
  const chat = el('div', { id:'mp-chat', style:{
    position:'absolute', left:'12px', bottom:'12px', width:'340px',
    pointerEvents:'none', display:'none'
  }});
  chat.innerHTML = `
    <div id="mp-chat-log" style="display:flex;flex-direction:column;gap:3px;margin-bottom:6px"></div>
    <input id="mp-chat-input" class="mp-input" placeholder="Enter para conversar... (ESC cancela)"
           style="display:none;pointer-events:auto;font-size:13px"/>
  `;
  root.append(chat);

  // Team panel in-game
  const team = el('div', { id:'mp-team', className:'mp-card', style:{
    position:'absolute', top:'58px', right:'12px', width:'220px',
    padding:'10px', fontSize:'12px', display:'none', pointerEvents:'none'
  }});
  root.append(team);

  document.body.append(root);

  UI = {
    openBtn, panel, chat, team,
    close: $('#mp-close', panel),
    sConnect: $('#mp-stage-connect', panel),
    sLobby:   $('#mp-stage-lobby', panel),
    sPick:    $('#mp-stage-pick', panel),
    name:     $('#mp-name', panel),
    hp:       $('#mp-hp', panel),
    rift:     $('#mp-rift', panel),
    host:     $('#mp-host', panel),
    code:     $('#mp-code', panel),
    join:     $('#mp-join', panel),
    status:   $('#mp-status', panel),
    roomLabel:$('#mp-room-label', panel),
    copy:     $('#mp-copy', panel),
    role:     $('#mp-role', panel),
    plist:    $('#mp-players', panel),
    pick:     $('#mp-pick', panel),
    start:    $('#mp-start', panel),
    lmsg:     $('#mp-lobby-msg', panel),
    pickBack: $('#mp-pick-back', panel),
    grid:     $('#mp-class-grid', panel),
    chatLog:  $('#mp-chat-log', chat),
    chatInput:$('#mp-chat-input', chat),
  };

  UI.name.value = S.myName;
  UI.close.onclick = () => toggleLobby(false);
  UI.host.onclick  = onHost;
  UI.join.onclick  = onJoin;
  UI.copy.onclick  = () => {
    if (!S.roomCode) return;
    const short = S.roomCode.replace(PEER_PREFIX,'');
    navigator.clipboard?.writeText(short);
    UI.copy.textContent='✓ copiado!';
    setTimeout(()=>UI.copy.textContent='📋 copiar', 1200);
  };
  UI.pick.onclick = () => { if (!UI.pick.disabled) showPick(); };
  UI.start.onclick = () => { if (!UI.start.disabled) hostStart(); };
  UI.pickBack.onclick = () => { UI.sPick.style.display='none'; UI.sLobby.style.display=''; };

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

  // Pre-check de bridge
  if (!window.__MP_BRIDGE_READY__) {
    setStatus('⚠️  Bridge não detectado. Cole mp-bridge.js no final do <script> do jogo.');
  }
}

function toggleLobby(show){ UI.panel.style.display = show ? '' : 'none'; }
function setStatus(m){ if (UI.status) UI.status.textContent = m; log(m); }

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
      else setStatus('Erro de rede: '+(err.type||err.message));
    });
    p.on('connection', onIncoming);
  });
}

function onHost(){
  S.myName  = (UI.name.value||S.myName).slice(0,14);
  S.hpMult  = parseFloat(UI.hp.value)||1;
  S.riftMode= UI.rift.checked;
  S.isHost  = true;
  S.roomCode= PEER_PREFIX + rid();
  setStatus('Criando sala...');
  ensurePeer(S.roomCode).then(()=>{
    S.players.set(S.myId, mkLocalEntry());
    enterLobby();
    setStatus('✓ Sala criada. Compartilhe o código com seu amigo.');
  }).catch(e => setStatus('Falhou: '+e.message));
}

function onJoin(){
  const raw = (UI.code.value||'').trim().toUpperCase();
  if (!raw) return setStatus('Digite o código.');
  S.myName = (UI.name.value||S.myName).slice(0,14);
  S.isHost = false;
  S.roomCode = raw.startsWith(PEER_PREFIX.toUpperCase()) ? raw.toLowerCase() :
               raw.startsWith(PEER_PREFIX) ? raw : (PEER_PREFIX+raw);
  setStatus('Conectando...');
  ensurePeer().then(()=>{
    const conn = S.peer.connect(S.roomCode, { reliable:true });
    let opened=false;
    const timeout = setTimeout(()=>{ if(!opened) setStatus('Timeout. Verifique o código.'); }, 8000);
    conn.on('open', ()=>{
      opened=true; clearTimeout(timeout);
      S.conns.set(S.roomCode, conn);
      conn.send({ t:'hello', name:S.myName, v:VERSION });
      S.players.set(S.myId, mkLocalEntry());
      enterLobby();
      setStatus('✓ Conectado.');
    });
    conn.on('data', d => handleData(conn, d));
    conn.on('close', ()=> setStatus('Conexão fechada.'));
    conn.on('error', e => setStatus('Erro: '+e.message));
  }).catch(e => setStatus('Falhou: '+e.message));
}

function onIncoming(conn){
  if (!S.isHost) return;
  conn.on('open', ()=>{
    S.conns.set(conn.peer, conn);
    log('peer joined', conn.peer);
  });
  conn.on('data', d => handleData(conn, d));
  conn.on('close', ()=>{
    S.conns.delete(conn.peer);
    S.players.delete(conn.peer);
    broadcastLobby(); renderLobby();
  });
}

function mkLocalEntry(){
  return { id:S.myId, name:S.myName, classKey:null, ready:false,
           x:0,y:0,hp:100,maxHp:100,wave:1,score:0,down:false,
           host:S.isHost };
}

// ===================== PROTOCOLO =====================
function send(conn, obj){ try{ conn.send(obj); }catch(e){} }
function bcast(obj){ for (const c of S.conns.values()) send(c, obj); }

function handleData(conn, d){
  if (!d || !d.t) return;
  if (S.isHost){
    switch(d.t){
      case 'hello': {
        S.players.set(conn.peer, {
          id:conn.peer, name:(d.name||'P').slice(0,14),
          classKey:null, ready:false,
          x:0,y:0,hp:100,maxHp:100,wave:1,score:0,down:false, host:false
        });
        broadcastLobby(); renderLobby();
        break;
      }
      case 'pickClass': {
        const p = S.players.get(conn.peer);
        if (p){ p.classKey = d.classKey; p.ready = true; }
        broadcastLobby(); renderLobby();
        break;
      }
      case 'state': {
        const p = S.players.get(conn.peer);
        if (p) Object.assign(p, d.s);
        break;
      }
      case 'dmg': hostApplyDamage(d.mpId, d.amount, conn.peer); break;
      case 'chat': bcastChat(d.from||'?', d.msg||''); break;
      case 'revive': {
        const tgt = S.players.get(d.target);
        if (tgt){ tgt.down=false; tgt.hp = Math.max(1, Math.floor(tgt.maxHp*0.5)); }
        broadcastLobby();
        break;
      }
    }
  } else {
    switch(d.t){
      case 'lobby': {
        S.players = new Map(d.players.map(p=>[p.id,p]));
        S.hpMult = d.hpMult; S.riftMode = d.riftMode;
        renderLobby();
        break;
      }
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
          hpMult:S.hpMult, riftMode:S.riftMode });
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

// ===================== RENDER LOBBY =====================
function enterLobby(){
  UI.sConnect.style.display='none';
  UI.sLobby.style.display='';
  UI.sPick.style.display='none';
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

  // Botão Selecionar
  if (!me) {
    setBtn(UI.pick, false, 'primary', 'Selecionar Personagem');
  } else if (!enough){
    setBtn(UI.pick, false, 'primary', `Aguardando jogadores (${players.length}/2)`);
  } else if (me.ready){
    setBtn(UI.pick, true, 'ghost', '🔁 Trocar Personagem');
  } else {
    setBtn(UI.pick, true, 'primary', '⚔️  Selecionar Personagem');
  }

  // Botão Iniciar
  if (S.isHost){
    setBtn(UI.start, allReady, 'success', allReady ? '▶  INICIAR PARTIDA' : 'Aguardando seleções...');
  } else {
    setBtn(UI.start, false, 'ghost', allReady ? 'Host vai iniciar...' : 'Aguardando seleções...');
  }

  UI.lmsg.textContent = !enough ? 'Compartilhe o código com seu amigo.'
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
        Cole o trecho <code>mp-bridge.js</code> no FINAL do &lt;script&gt; principal do jogo
        (antes do &lt;/script&gt; de fechamento), depois recarregue a página.
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
  UI.sLobby.style.display='none';
  UI.sPick.style.display='';
}

function pickClass(key){
  const me = S.players.get(S.myId);
  if (me){ me.classKey = key; me.ready = true; }
  if (S.isHost) broadcastLobby();
  else { const c = S.conns.get(S.roomCode); if (c) send(c, { t:'pickClass', classKey:key }); }
  UI.sPick.style.display='none';
  UI.sLobby.style.display='';
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

function startLocalGame(classKey){
  if (!classKey) { warn('sem classe!'); return; }
  S.started = true;
  toggleLobby(false);
  UI.chat.style.display = '';
  UI.team.style.display = '';

  if (S.riftMode) { try { window.__forceNextRift507 = true; } catch(e){} }

  try {
    if (typeof window.resetGame === 'function') window.resetGame(classKey);
    else warn('window.resetGame não disponível');
  } catch(e){ console.error('[MP] erro ao iniciar:', e); }

  // Após iniciar, instala patches dependentes do jogo
  setTimeout(()=>{
    installEnemyPatch();
    startTickLoop();
    startEnemySync();
    startOverlay();
  }, 50);
}

// ===================== INIMIGOS COMPARTILHADOS =====================
/* Estratégia:
   - HOST é o único que simula inimigos. Aplica hpMult ao spawn e
     atribui __mpId estável. Broadcasta snapshots leves a ENEMY_HZ.
   - CLIENTES têm spawnEnemy stub (não cria nada). A cada snapshot
     recebido, reconstroem game.enemies como objetos "casca" que o
     renderizador do jogo já desenha (mesmo tipo/r/cor). Esses
     inimigos casca ainda colidem com os tiros locais; quando um
     tiro local atinge um inimigo casca, em vez de aplicar dano
     localmente, enviamos { t:'dmg', mpId, amount } ao host.
   - O host detecta hits dos próprios tiros normalmente e também
     recebe os 'dmg' dos clientes, aplicando ao inimigo real.
*/

function installEnemyPatch(){
  const g = window.game; if (!g) return;

  if (S.isHost){
    // Wrap spawnEnemy: aplica hpMult e atribui __mpId
    const orig = window.spawnEnemy;
    if (typeof orig === 'function' && !orig.__mpWrapped){
      const wrapped = function(...a){
        const before = g.enemies ? g.enemies.length : 0;
        const r = orig.apply(this, a);
        const e = (r && typeof r === 'object') ? r :
                  (g.enemies && g.enemies.length > before ? g.enemies[g.enemies.length-1] : null);
        if (e){
          if (typeof e.hp === 'number' && S.hpMult !== 1){
            e.hp = e.hp * S.hpMult;
            e.maxHp = (e.maxHp || e.hp) * 1;
          }
          if (!e.__mpId) e.__mpId = S.enemyIdCounter++;
        }
        return r;
      };
      wrapped.__mpWrapped = true;
      try { window.spawnEnemy = wrapped; } catch(e){}
    }
  } else {
    // Cliente: stub
    try {
      const noop = function(){ return null; };
      noop.__mpWrapped = true;
      window.spawnEnemy = noop;
    } catch(e){}
    // Hook nos tiros: detecta hits e envia dmg pro host
    installClientBulletHook();
  }
}

function installClientBulletHook(){
  // Trabalha em alta frequência, varre game.bullets e game.enemies casca
  // Para cada bullet ativo, se colide com um inimigo casca, envia dmg
  // e marca o bullet como consumido (b.dead/b.life=0) pra evitar repetição.
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
            const dmg = b.dmg || b.damage || 10;
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
      // dá créditos de score/xp para o jogador que atirou?
      // (simplificação: o jogo do host gerencia recompensas normais)
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
  // index existentes por mpId
  const existing = new Map();
  for (const e of g.enemies) if (e && e.__mpId) existing.set(e.__mpId, e);
  const next = [];
  for (const s of list){
    let e = existing.get(s.i);
    if (!e){
      e = makeShellEnemy(s);
    } else {
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
  // Inimigo "casca" com campos mínimos que o renderer e collider esperam
  return {
    __mpId: s.i, __mpShell: true,
    x: s.x, y: s.y, vx:0, vy:0,
    hp: s.h, maxHp: s.M,
    r: s.r||14,
    type: s.t||'normal',
    boss: !!s.b, elite: !!s.el,
    color: s.c||'#ff6b9d',
    dead: false,
    update(){}, draw(){}, // no-op se chamado; o jogo principal usa seu próprio renderer
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
    const gameCanvas = document.querySelector('canvas#game') || document.querySelector('canvas');
    const scale = gameCanvas ? oc.width / gameCanvas.width : 1;

    for (const p of S.players.values()){
      if (p.id === S.myId) continue;
      const sx = ((p.x||0) - (cam.x||0) + (gameCanvas?gameCanvas.width/2:oc.width/2)) * scale;
      const sy = ((p.y||0) - (cam.y||0) + (gameCanvas?gameCanvas.height/2:oc.height/2)) * scale;
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
  const gameCanvas = document.querySelector('canvas#game') || document.querySelector('canvas');
  const scale = gameCanvas ? oc.width / gameCanvas.width : 1;
  const sx = ((p.x||0) - (cam.x||0) + (gameCanvas?gameCanvas.width/2:oc.width/2)) * scale;
  const sy = ((p.y||0) - (cam.y||0) + (gameCanvas?gameCanvas.height/2:oc.height/2)) * scale;
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
  }}, 'EQUIPE'));
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
