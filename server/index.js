// Warring Hands relay server.
//
// Pairs two players by a 4-digit room code and passes their messages to each
// other. It doesn't run the game: both devices run the same lockstep
// simulation and only exchange orders, so this stays tiny.
//
// Messages are JSON over a WebSocket:
//   client -> server  {t: "create"}                 -> {t: "created", code}
//   client -> server  {t: "join", code}             -> both get {t: "start", seat, seed}
//                                                      (or {t: "error", msg})
//   client -> server  anything else (e.g. {t: "turn", ...}, {t: "hash", ...})
//                     is passed to the other player as is, with `seat` added.
//   server -> client  {t: "left"} when the other player disconnects.
//
// HTTP GET on any path answers "ok" (for the host's health check).
// Run: npm start (PORT from the environment, default 8080).

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.PORT) || 8080;
const MAX_MESSAGE = 64 * 1024;
const ROOM_WAIT_MS = 30 * 60 * 1000; // an unjoined room expires after 30 min
const PING_MS = 25 * 1000;

const rooms = new Map(); // code -> {players: [ws, ws?], created}

function newCode() {
  for (let i = 0; i < 1000; i++) {
    const code = String(Math.floor(1000 + Math.random() * 9000));
    if (!rooms.has(code)) return code;
  }
  return null;
}

function send(ws, msg) {
  if (ws && ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
}

function leave(ws) {
  const code = ws.room;
  if (!code || !rooms.has(code)) return;
  const room = rooms.get(code);
  for (const other of room.players) {
    if (other !== ws) {
      send(other, { t: "left" });
      other.room = null;
    }
  }
  rooms.delete(code);
  ws.room = null;
}

function handle(ws, msg) {
  if (msg.t === "create") {
    leave(ws);
    const code = newCode();
    if (!code) return send(ws, { t: "error", msg: "No free rooms, try again later" });
    rooms.set(code, { players: [ws], created: Date.now() });
    ws.room = code;
    ws.seat = 0;
    return send(ws, { t: "created", code });
  }
  if (msg.t === "join") {
    const code = String(msg.code || "");
    const room = rooms.get(code);
    if (!room) return send(ws, { t: "error", msg: "No game with that code" });
    if (room.players.length >= 2) return send(ws, { t: "error", msg: "That game is full" });
    if (room.players[0] === ws) return send(ws, { t: "error", msg: "That's your own game" });
    leave(ws);
    room.players.push(ws);
    ws.room = code;
    ws.seat = 1;
    const seed = Math.floor(Math.random() * 2147483647);
    room.players.forEach((p, seat) => send(p, { t: "start", seat, seed, code }));
    return;
  }
  // In a game: pass it on to the other player.
  const room = ws.room && rooms.get(ws.room);
  if (!room) return;
  msg.seat = ws.seat;
  for (const other of room.players) {
    if (other !== ws) send(other, msg);
  }
}

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("ok");
});

const wss = new WebSocketServer({ server, maxPayload: MAX_MESSAGE });

wss.on("connection", (ws) => {
  ws.alive = true;
  ws.room = null;
  ws.on("pong", () => (ws.alive = true));
  ws.on("message", (data) => {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }
    if (msg && typeof msg === "object" && typeof msg.t === "string") handle(ws, msg);
  });
  ws.on("close", () => leave(ws));
});

// Drop dead connections and stale rooms.
const timer = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) {
      ws.terminate();
      continue;
    }
    ws.alive = false;
    ws.ping();
  }
  const now = Date.now();
  for (const [code, room] of rooms) {
    if (room.players.length < 2 && now - room.created > ROOM_WAIT_MS) {
      for (const p of room.players) p.close();
      rooms.delete(code);
    }
  }
}, PING_MS);
wss.on("close", () => clearInterval(timer));

server.listen(PORT, () => console.log(`Warring Hands relay listening on ${PORT}`));

module.exports = { server, wss, rooms };
