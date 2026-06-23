/* =========================================================
   CHRONO SHARDS - MULTIPLAYER V14 REWRITE
   HOST AUTHORITATIVE ARCHITECTURE
========================================================= */

const MP = {
    isHost: false,
    conn: null,

    state: null,

    localInputs: {},

    lastSnapshot: null,

    tickRate: 20
};

function createDefaultState() {
    return {
        wave: 1,
        paused: false,

        riftMode: false,

        boss: null,
        bossAlive: false,

        gold: 0,

        players: {},
        enemies: [],
        bullets: [],

        timestamp: 0
    };
}

/* =========================================================
   INITIALIZATION
========================================================= */

function MP_init(isHost, connection) {
    MP.isHost = isHost;
    MP.conn = connection;

    MP.state = createDefaultState();

    if (MP.isHost) {
        setInterval(hostLoop, 1000 / MP.tickRate);
    }

    setupNetwork();
}

/* =========================================================
   HOST LOOP (SINGLE SOURCE OF TRUTH)
========================================================= */

function hostLoop() {
    if (!MP.isHost) return;

    const S = MP.state;

    if (!S.paused) {

        updateEnemies(S);
        updateBoss(S);
        updateWave(S);
        updateRift(S);
        updateBullets(S);
        updatePlayers(S);
    }

    broadcastSnapshot();
}

/* =========================================================
   GAME LOGIC (HOST ONLY)
========================================================= */

function updateWave(S) {
    if (S.enemies.length === 0 && !S.bossAlive) {
        S.wave++;

        if (S.wave >= 10) {
            S.riftMode = true;
        }

        spawnWave(S, S.wave);
    }
}

function updateRift(S) {
    // Rift is ONLY host controlled
    if (S.wave >= 10 && !S.riftMode) {
        S.riftMode = true;
    }
}

function updateEnemies(S) {
    for (let e of S.enemies) {
        if (e.hp <= 0) continue;
        if (e.update) e.update(S);
    }

    S.enemies = S.enemies.filter(e => e.hp > 0);
}

function updateBoss(S) {
    if (S.boss && S.boss.hp <= 0) {
        S.bossAlive = false;
        S.boss = null;
    }
}

function updateBullets(S) {
    for (let b of S.bullets) {
        if (b.update) b.update(S);
    }

    S.bullets = S.bullets.filter(b => !b.dead);
}

function updatePlayers(S) {
    for (let id in S.players) {
        const p = S.players[id];
        if (p.update) p.update(S);
    }
}

/* =========================================================
   SPAWNING
========================================================= */

function spawnWave(S, wave) {
    const count = 5 + wave * 2;

    for (let i = 0; i < count; i++) {
        S.enemies.push(createEnemy(wave));
    }
}

function createEnemy(wave) {
    return {
        x: Math.random() * 800,
        y: Math.random() * 600,
        hp: 10 + wave * 2,
        maxHp: 10 + wave * 2,

        update(S) {
            this.x += Math.sin(Date.now() * 0.001);
        }
    };
}

/* =========================================================
   NETWORK
========================================================= */

function setupNetwork() {
    if (!MP.conn) return;

    MP.conn.on("data", (data) => {

        if (MP.isHost) {
            handleClientInput(data);
        } else {
            applySnapshot(data);
        }
    });
}

function handleClientInput(data) {
    const S = MP.state;

    if (data.type === "input") {
        S.players[data.id] = {
            ...S.players[data.id],
            ...data.input
        };
    }
}

/* =========================================================
   SNAPSHOT SYSTEM
========================================================= */

function broadcastSnapshot() {
    const snapshot = serializeState(MP.state);

    if (MP.conn) {
        MP.conn.send(snapshot);
    }
}

function applySnapshot(snapshot) {
    MP.lastSnapshot = snapshot;
    MP.state = snapshot;
}

function serializeState(S) {
    return {
        wave: S.wave,
        paused: S.paused,
        riftMode: S.riftMode,

        boss: S.boss,
        bossAlive: S.bossAlive,

        gold: S.gold,

        players: S.players,
        enemies: S.enemies,
        bullets: S.bullets,

        timestamp: Date.now()
    };
}

/* =========================================================
   PAUSE (FIXED SINGLE SOURCE)
========================================================= */

function setPause(value) {
    if (!MP.isHost) return;

    MP.state.paused = value;
}

/* =========================================================
   INPUT CLIENT SIDE
========================================================= */

function sendInput(input) {
    if (!MP.conn) return;

    MP.conn.send({
        type: "input",
        input
    });
}

/* =========================================================
   RENDERING (CLIENT ONLY)
   IMPORTANT: USE ORIGINAL GAME FUNCTIONS
========================================================= */

function renderGame() {
    if (!MP.state) return;

    const S = MP.state;

    // IMPORTANT: reuse main game render functions
    drawMap?.(S);
    drawEnemies?.(S.enemies);
    drawPlayers?.(S.players);
    drawBullets?.(S.bullets);
    drawBoss?.(S.boss);
}
