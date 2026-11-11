// Checks the relay: create, join, start, passing messages, leaving, errors.
// Run: npm test
process.env.PORT = process.env.PORT || "18765";
const { server, wss } = require("./index.js");
const WebSocket = require("ws");

const url = `ws://localhost:${process.env.PORT}`;
let failures = 0;
function check(label, ok) {
  console.log((ok ? "PASS " : "FAIL ") + label);
  if (!ok) failures++;
}

function client() {
  return new Promise((resolve) => {
    const ws = new WebSocket(url);
    ws.inbox = [];
    ws.waiters = [];
    ws.on("message", (d) => {
      const msg = JSON.parse(d.toString());
      const w = ws.waiters.shift();
      if (w) w(msg);
      else ws.inbox.push(msg);
    });
    ws.on("open", () => resolve(ws));
  });
}
function next(ws) {
  return new Promise((resolve, reject) => {
    if (ws.inbox.length) return resolve(ws.inbox.shift());
    const t = setTimeout(() => reject(new Error("timeout")), 2000);
    ws.waiters.push((m) => {
      clearTimeout(t);
      resolve(m);
    });
  });
}
const sendTo = (ws, m) => ws.send(JSON.stringify(m));

(async () => {
  const a = await client();
  const b = await client();
  sendTo(a, { t: "create" });
  const created = await next(a);
  check("create gives a 4-digit code", created.t === "created" && /^\d{4}$/.test(created.code));
  sendTo(b, { t: "join", code: "0000" });
  const bad = await next(b);
  check("a wrong code is refused", bad.t === "error");
  sendTo(b, { t: "join", code: created.code });
  const sa = await next(a);
  const sb = await next(b);
  check("joining starts the game for both", sa.t === "start" && sb.t === "start");
  check("...with seats 0 and 1 and the same seed", sa.seat === 0 && sb.seat === 1 && sa.seed === sb.seed);
  const c = await client();
  sendTo(c, { t: "join", code: created.code });
  check("a third player can't join", (await next(c)).t === "error");
  sendTo(a, { t: "turn", tick: 5, cmds: [{ type: "move" }] });
  const got = await next(b);
  check("orders are passed to the other player, with the sender's seat",
    got.t === "turn" && got.tick === 5 && got.seat === 0 && got.cmds.length === 1);
  sendTo(b, { t: "hash", tick: 100, h: 42 });
  const gotHash = await next(a);
  check("...both ways", gotHash.t === "hash" && gotHash.seat === 1 && gotHash.h === 42);
  a.close();
  check("when one leaves, the other is told", (await next(b)).t === "left");
  b.close();
  c.close();
  wss.close();
  server.close();
  console.log("FAILURES: " + failures);
  process.exit(failures ? 1 : 0);
})().catch((e) => {
  console.log("FAIL " + e.message);
  process.exit(1);
});
