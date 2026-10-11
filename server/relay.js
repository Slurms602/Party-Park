// Bowling your Friends relay: play together without port forwarding.
// Everyone connects *out* to this server over a WebSocket. The host gets a 4-letter room code, friends join
// with it, and the relay forwards game packets between them (the host still runs the game).
//
//   npm install && node relay.js        (listens on $PORT, default 8080)
//
// Protocol: the first message is JSON text, {op:"host", v} or {op:"join", v, code}. After that, frames are
// binary: [int32 LE peer id][payload]. The host addresses a client id (0 = everyone, -id = everyone but id);
// clients always talk to the host, and the relay stamps their id on the way through.
'use strict';
const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT) || 8080;
const LETTERS = 'BCDFGHJKLMNPQRSTVWXZ'; // consonants only: no accidental words, no O/0 or I/1 mix-ups
const MAX_PLAYERS = 8;
const MAX_ROOMS = 5000;
const rooms = new Map(); // code -> {host, version, clients: Map<id, ws>, nextId}

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'content-type': 'text/plain', 'access-control-allow-origin': '*' });
  res.end(`Bowling your Friends relay is up. ${rooms.size} game(s) running.\n`);
});
const wss = new WebSocketServer({ server, maxPayload: 256 * 1024 });

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function fail(ws, msg) {
  send(ws, { op: 'error', msg });
  ws.close(4001, msg.slice(0, 120)); // the reason survives even if the client misses the message above
}

function newCode() {
  for (let attempt = 0; attempt < 100; attempt++) {
    let code = '';
    for (let i = 0; i < 4; i++) code += LETTERS[Math.floor(Math.random() * LETTERS.length)];
    if (!rooms.has(code)) return code;
  }
  return null;
}

wss.on('connection', (ws) => {
  ws.alive = true;
  ws.on('pong', () => { ws.alive = true; });
  ws.on('error', () => {});
  ws.once('message', (data, binary) => {
    let hello = null;
    try { hello = binary ? null : JSON.parse(data.toString()); } catch { /* ignore */ }
    if (hello && hello.op === 'host') host(ws, hello);
    else if (hello && hello.op === 'join') join(ws, hello);
    else ws.close(4001, 'bad hello');
  });
});

function host(ws, hello) {
  const code = rooms.size < MAX_ROOMS ? newCode() : null;
  if (!code) return fail(ws, 'The online server is full right now. Try again in a minute.');
  const room = { host: ws, version: String(hello.v || ''), clients: new Map(), nextId: 2 };
  rooms.set(code, room);
  send(ws, { op: 'hosted', code });
  ws.on('message', (data, binary) => {
    if (!binary || data.length < 4) return;
    const dest = data.readInt32LE(0);
    data.writeInt32LE(1, 0); // clients see everything as coming from the host (peer 1)
    if (dest > 0) {
      const c = room.clients.get(dest);
      if (c && c.readyState === c.OPEN) c.send(data);
    } else {
      for (const [id, c] of room.clients) if (id !== -dest && c.readyState === c.OPEN) c.send(data);
    }
  });
  ws.on('close', () => {
    rooms.delete(code);
    for (const c of room.clients.values()) c.close(4000, 'host left');
  });
}

function join(ws, hello) {
  const code = String(hello.code || '').toUpperCase().trim();
  const room = rooms.get(code);
  if (!room) return fail(ws, `No game with code ${code}. Double-check it with your host.`);
  if (room.version !== String(hello.v || '')) return fail(ws, "Your game version doesn't match the host's. Both of you need the latest build.");
  if (room.clients.size >= MAX_PLAYERS - 1) return fail(ws, 'That game is full.');
  const want = Number(hello.id); // clients pick a random id up front, like ENet does
  let id = Number.isInteger(want) && want > 1 && want <= 0x7fffffff ? want : room.nextId++;
  while (room.clients.has(id)) id = room.nextId++;
  room.clients.set(id, ws);
  send(ws, { op: 'joined', id });
  send(room.host, { op: 'peer_joined', id });
  ws.on('message', (data, binary) => {
    if (!binary || data.length < 4 || room.host.readyState !== room.host.OPEN) return;
    data.writeInt32LE(id, 0); // stamp the sender so the host knows who it is
    room.host.send(data);
  });
  ws.on('close', () => {
    if (room.clients.delete(id)) send(room.host, { op: 'peer_left', id });
  });
}

// Drop connections that stopped answering (closed laptops, dead Wi-Fi).
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 15000);

server.listen(PORT, () => console.log(`Bowling your Friends relay listening on :${PORT}`));
