import { WebSocketServer, WebSocket } from "ws";
import { createServer, IncomingMessage, ServerResponse } from "http";

// ─── Constants ────────────────────────────────────────────────────────────────
const PORT = 3004;
const MAX_FRAME_SIZE = 500 * 1024; // 500KB
const PING_INTERVAL = 30_000; // 30 seconds
const PONG_TIMEOUT = 10_000; // 10 seconds
const FRAME_LOG_INTERVAL = 100; // Log every 100 frames

// ─── Types ────────────────────────────────────────────────────────────────────
interface Session {
  child: WebSocket | null;
  parents: Set<WebSocket>;
  frameCount: number;
  lastFrameAt: number | null;
}

interface ClientMeta {
  role: "child" | "parent";
  uid: string;
  alive: boolean;
  pongTimer: ReturnType<typeof setTimeout> | null;
}

// ─── State ────────────────────────────────────────────────────────────────────
const sessions = new Map<string, Session>(); // uid -> Session
const clientMeta = new WeakMap<WebSocket, ClientMeta>();

// ─── Helpers ──────────────────────────────────────────────────────────────────
function getOrCreateSession(uid: string): Session {
  let session = sessions.get(uid);
  if (!session) {
    session = { child: null, parents: new Set(), frameCount: 0, lastFrameAt: null };
    sessions.set(uid, session);
  }
  return session;
}

function removeParent(ws: WebSocket, uid: string): void {
  const session = sessions.get(uid);
  if (session) {
    session.parents.delete(ws);
    // Clean up empty sessions
    if (!session.child && session.parents.size === 0) {
      sessions.delete(uid);
    }
  }
}

function log(level: "INFO" | "WARN" | "ERROR", msg: string): void {
  const ts = new Date().toISOString();
  console.log(`[${ts}] [${level}] ${msg}`);
}

// ─── HTTP Server (for /health) ───────────────────────────────────────────────
const httpServer = createServer((req: IncomingMessage, res: ServerResponse) => {
  if (req.url === "/health" && req.method === "GET") {
    const totalConnections = Array.from(sessions.values()).reduce(
      (acc, s) => acc + (s.child ? 1 : 0) + s.parents.size,
      0
    );

    const sessionsInfo = Array.from(sessions.entries()).map(([uid, s]) => ({
      uid,
      hasChild: s.child !== null,
      parentCount: s.parents.size,
      frameCount: s.frameCount,
      lastFrameAt: s.lastFrameAt,
    }));

    const payload = {
      status: "ok",
      connections: totalConnections,
      sessions: sessionsInfo,
    };

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(payload));
    return;
  }

  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
});

// ─── WebSocket Server ─────────────────────────────────────────────────────────
const wss = new WebSocketServer({ server: httpServer });

function parseQuery(url: string | undefined): Record<string, string> {
  const params: Record<string, string> = {};
  if (!url) return params;
  const qIndex = url.indexOf("?");
  if (qIndex === -1) return params;
  const search = url.slice(qIndex + 1);
  for (const pair of search.split("&")) {
    const [key, value] = pair.split("=");
    if (key && value) {
      params[decodeURIComponent(key)] = decodeURIComponent(value);
    }
  }
  return params;
}

function handleClose(ws: WebSocket): void {
  const meta = clientMeta.get(ws);
  if (!meta) return;

  // Clear pong timer
  if (meta.pongTimer) {
    clearTimeout(meta.pongTimer);
    meta.pongTimer = null;
  }

  const { role, uid } = meta;
  const session = sessions.get(uid);

  if (role === "child") {
    log("INFO", `Child disconnected: uid=${uid}`);
    if (session && session.child === ws) {
      session.child = null;
      // Notify all parents
      const disconnectMsg = JSON.stringify({ type: "child_disconnected" });
      for (const parent of session.parents) {
        try {
          if (parent.readyState === WebSocket.OPEN) {
            parent.send(disconnectMsg);
          }
        } catch (err) {
          log("ERROR", `Failed to notify parent of disconnect: ${err}`);
        }
      }
      // Clean up session if no parents either
      if (session.parents.size === 0) {
        sessions.delete(uid);
      }
    }
  } else if (role === "parent") {
    log("INFO", `Parent disconnected: uid=${uid}`);
    removeParent(ws, uid);
  }

  clientMeta.delete(ws);
}

// ─── Heartbeat ────────────────────────────────────────────────────────────────
function startHeartbeat(ws: WebSocket): void {
  const meta = clientMeta.get(ws);
  if (!meta) return;

  const interval = setInterval(() => {
    if (ws.readyState !== WebSocket.OPEN) {
      clearInterval(interval);
      return;
    }

    meta.alive = false;
    ws.ping();

    // Set a timeout to close if pong not received
    meta.pongTimer = setTimeout(() => {
      if (!meta.alive && ws.readyState === WebSocket.OPEN) {
        log("WARN", `Heartbeat timeout for ${meta.role} uid=${meta.uid}, closing`);
        ws.terminate();
      }
    }, PONG_TIMEOUT);
  }, PING_INTERVAL);

  // Clean up interval on close
  ws.on("close", () => clearInterval(interval));
}

wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
  const query = parseQuery(req.url);
  const role = query.role as "child" | "parent" | undefined;
  const uid = query.uid;

  // Validate required params
  if (!role || (role !== "child" && role !== "parent")) {
    log("WARN", `Invalid or missing role param: role=${role}`);
    ws.close(4001, "Missing or invalid 'role' query param (must be 'child' or 'parent')");
    return;
  }

  if (!uid || typeof uid !== "string" || uid.trim().length === 0) {
    log("WARN", `Invalid or missing uid param: uid=${uid}`);
    ws.close(4002, "Missing or invalid 'uid' query param");
    return;
  }

  const meta: ClientMeta = { role, uid, alive: true, pongTimer: null };
  clientMeta.set(ws, meta);

  const session = getOrCreateSession(uid);

  if (role === "child") {
    // Replace existing child if any
    if (session.child && session.child.readyState === WebSocket.OPEN) {
      log("WARN", `Replacing existing child for uid=${uid}`);
      try {
        session.child.close(4003, "Replaced by new child connection");
      } catch (err) {
        log("ERROR", `Error closing previous child: ${err}`);
      }
    }
    session.child = ws;
    log("INFO", `Child connected: uid=${uid}`);
  } else {
    session.parents.add(ws);
    log("INFO", `Parent connected: uid=${uid} (total parents: ${session.parents.size})`);
  }

  // Handle pong for heartbeat
  ws.on("pong", () => {
    meta.alive = true;
    if (meta.pongTimer) {
      clearTimeout(meta.pongTimer);
      meta.pongTimer = null;
    }
  });

  // Handle messages
  ws.on("message", (data: Buffer, isBinary: boolean) => {
    // Only child should send binary frames
    if (role === "child" && isBinary) {
      // Frame size check
      if (data.length > MAX_FRAME_SIZE) {
        log("WARN", `Frame too large: ${data.length} bytes (max ${MAX_FRAME_SIZE}), uid=${uid}`);
        return; // Drop oversized frame
      }

      session.frameCount++;
      session.lastFrameAt = Date.now();

      // Log every N frames
      if (session.frameCount % FRAME_LOG_INTERVAL === 0) {
        log("INFO", `Frame count: ${session.frameCount} for uid=${uid}, size=${data.length} bytes`);
      }

      // Relay to all connected parents
      for (const parent of session.parents) {
        try {
          if (parent.readyState === WebSocket.OPEN) {
            parent.send(data, { binary: true });
          }
        } catch (err) {
          log("ERROR", `Failed to relay frame to parent: ${err}`);
        }
      }
    } else if (role === "parent" && isBinary) {
      // Parents shouldn't send binary, but we handle gracefully
      log("WARN", `Parent attempted to send binary data, ignoring (uid=${uid})`);
    } else if (!isBinary) {
      // Text messages - could be used for control commands in the future
      const text = data.toString("utf-8");
      log("INFO", `Text message from ${role} uid=${uid}: ${text.slice(0, 200)}`);
    }
  });

  // Handle close
  ws.on("close", (code: number, reason: Buffer) => {
    handleClose(ws);
  });

  // Handle errors
  ws.on("error", (err: Error) => {
    log("ERROR", `WebSocket error for ${role} uid=${uid}: ${err.message}`);
    handleClose(ws);
  });

  // Start heartbeat
  startHeartbeat(ws);
});

wss.on("error", (err: Error) => {
  log("ERROR", `WebSocket server error: ${err.message}`);
});

// ─── Start Server ─────────────────────────────────────────────────────────────
httpServer.listen(PORT, () => {
  log("INFO", `Stream relay server started on port ${PORT}`);
  log("INFO", `WebSocket endpoint: ws://host/?XTransformPort=${PORT}&role=<child|parent>&uid=<childUid>`);
  log("INFO", `Health endpoint: http://host:${PORT}/health`);
});

// ─── Graceful Shutdown ────────────────────────────────────────────────────────
function shutdown(signal: string): void {
  log("INFO", `Received ${signal}, shutting down gracefully...`);

  // Close all WebSocket connections
  for (const [uid, session] of sessions) {
    if (session.child && session.child.readyState === WebSocket.OPEN) {
      session.child.close(1001, "Server shutting down");
    }
    for (const parent of session.parents) {
      if (parent.readyState === WebSocket.OPEN) {
        parent.close(1001, "Server shutting down");
      }
    }
  }

  httpServer.close(() => {
    log("INFO", "HTTP server closed");
    process.exit(0);
  });

  // Force exit after 5 seconds
  setTimeout(() => {
    log("WARN", "Forced shutdown after timeout");
    process.exit(1);
  }, 5000);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
