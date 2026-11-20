// Checks the live relay server end to end, the way two players use it:
// player A creates a game and gets a code, player B joins with it, both get
// "start", and an order from A reaches B. Waits for a sleeping (free)
// server to wake up.
// Run: cd server && node check_live.js wss://...
const WebSocket = require("ws");

const url = process.argv[2] || "wss://warring-hands.onrender.com";
const httpUrl = url.replace(/^ws/, "http");

function open(label) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const t0 = Date.now();
    ws.on("open", () => {
      console.log(`${label}: connected in ${Date.now() - t0} ms`);
      resolve(ws);
    });
    ws.on("error", (e) => reject(new Error(`${label}: ${e.message}`)));
  });
}

function next(ws, type, label) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label}: no "${type}" within 15 s`)), 15000);
    ws.on("message", function onMsg(data) {
      const msg = JSON.parse(data.toString());
      if (msg.t === type) {
        clearTimeout(timer);
        ws.off("message", onMsg);
        resolve(msg);
      } else if (msg.t === "error") {
        clearTimeout(timer);
        reject(new Error(`${label}: server said ${msg.msg}`));
      }
    });
  });
}

async function wake() {
  // A free server sleeps when unused: knock until it answers (up to 2 minutes).
  const t0 = Date.now();
  while (Date.now() - t0 < 120000) {
    try {
      const res = await fetch(httpUrl);
      const text = await res.text();
      console.log(`health check: HTTP ${res.status} "${text.trim()}" after ${Date.now() - t0} ms`);
      if (res.ok) return;
    } catch (e) {
      console.log(`health check: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
  throw new Error("server never answered the health check");
}

(async () => {
  console.log(`relay: ${url}`);
  await wake();
  const a = await open("player A");
  const created = next(a, "created", "player A");
  a.send(JSON.stringify({ t: "create" }));
  const { code } = await created;
  console.log(`player A: got game code ${code}`);
  const b = await open("player B");
  const startA = next(a, "start", "player A");
  const startB = next(b, "start", "player B");
  b.send(JSON.stringify({ t: "join", code }));
  const [sa, sb] = await Promise.all([startA, startB]);
  console.log(`both started: A seat ${sa.seat}, B seat ${sb.seat}, same seed ${sa.seed === sb.seed}`);
  const got = next(b, "ping", "player B");
  const t0 = Date.now();
  a.send(JSON.stringify({ t: "ping", g: 0 }));
  await got;
  console.log(`an order from A reached B in ${Date.now() - t0} ms`);
  a.close();
  b.close();
  console.log("RELAY OK");
  process.exit(0);
})().catch((e) => {
  console.log(`RELAY FAILED: ${e.message}`);
  process.exit(1);
});
