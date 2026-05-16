import { WebSocketServer, WebSocket } from "ws";
import { createServer, IncomingMessage, ServerResponse } from "http";

// ─── Constants ────────────────────────────────────────────────────────────────
const PORT = 3004;
const MAX_FRAME_SIZE = parseInt(process.env.MAX_FRAME_SIZE || `${500 * 1024}`, 10); // Configurable via env, default 500KB
const PING_INTERVAL = 30_000; // 30 seconds
const PONG_TIMEOUT = 10_000; // 10 seconds
const FRAME_LOG_INTERVAL = 100; // Log every 100 frames
const SHUTDOWN_CLOSE_TIMEOUT = 3_000; // 3 seconds to wait for close handshake

// ─── Types ────────────────────────────────────────────────────────────────────
interface Session {
  child: WebSocket | null;
  parents: Set<WebSocket>;
  frameCount: number;
  lastFrameAt: number | null;
  latestFrame: Buffer | null; // FIX-3: cache latest frame for new parents
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
const startupTime = Date.now(); // FIX-5: track server start time
let totalFramesRelayed = 0; // FIX-5: track total frames relayed since startup

// ─── Helpers ──────────────────────────────────────────────────────────────────
function getOrCreateSession(uid: string): Session {
  let session = sessions.get(uid);
  if (!session) {
    session = { child: null, parents: new Set(), frameCount: 0, lastFrameAt: null, latestFrame: null };
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

// FIX-1: CORS headers helper
function setCorsHeaders(res: ServerResponse): void {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.setHeader("Access-Control-Max-Age", "86400");
}

// ─── HTTP Server (for /health) ───────────────────────────────────────────────
const httpServer = createServer((req: IncomingMessage, res: ServerResponse) => {
  // FIX-1: Set CORS headers on ALL responses
  setCorsHeaders(res);

  // FIX-1: Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

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

    // FIX-5: Enhanced health endpoint with uptime, total frames, memory
    const uptime = Date.now() - startupTime;
    const memoryUsage = process.memoryUsage ? process.memoryUsage() : null;

    const payload = {
      status: "ok",
      uptime,
      uptimeSeconds: Math.floor(uptime / 1000),
      totalFramesRelayed,
      memoryUsage: memoryUsage
        ? {
            rss: memoryUsage.rss,
            heapTotal: memoryUsage.heapTotal,
            heapUsed: memoryUsage.heapUsed,
            external: memoryUsage.external,
            arrayBuffers: memoryUsage.arrayBuffers,
          }
        : null,
      connections: totalConnections,
      sessions: sessionsInfo,
    };

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(payload));
    return;
  }

  // FIX-7: Handle root path "/" — return simple status for health check / gateway proxy
  if (req.url === "/" && req.method === "GET") {
    const payload = {
      status: "ok",
      service: "stream-relay",
      uptimeSeconds: Math.floor((Date.now() - startupTime) / 1000),
    };
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(payload));
    return;
  }

  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
});

// ─── WebSocket Server ─────────────────────────────────────────────────────────
// FIX-7: Accept WebSocket upgrade on all paths (root /, /health, etc.)
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

function handleClose(ws: WebSocket, isReplacement: boolean = false): void {
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
    log("INFO", `Child disconnected: uid=${uid}${isReplacement ? " (replaced)" : ""}`);
    if (session && session.child === ws) {
      session.child = null;
      // FIX-4: Send child_reconnected instead of child_disconnected when replacing
      const msgType = isReplacement ? "child_reconnected" : "child_disconnected";
      const disconnectMsg = JSON.stringify({ type: msgType });
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
        // FIX-4: Mark as replacement so handleClose sends child_reconnected
        const oldChild = session.child;
        // Remove old child's meta first to prevent double-handling in close handler
        // We'll call handleClose manually with isReplacement=true
        const oldMeta = clientMeta.get(oldChild);
        if (oldMeta) {
          // Clear pong timer of old child
          if (oldMeta.pongTimer) {
            clearTimeout(oldMeta.pongTimer);
            oldMeta.pongTimer = null;
          }
          clientMeta.delete(oldChild);
        }
        // Notify parents with child_reconnected BEFORE closing old child
        const reconnectMsg = JSON.stringify({ type: "child_reconnected" });
        for (const parent of session.parents) {
          try {
            if (parent.readyState === WebSocket.OPEN) {
              parent.send(reconnectMsg);
            }
          } catch (err) {
            log("ERROR", `Failed to notify parent of reconnect: ${err}`);
          }
        }
        oldChild.close(4003, "Replaced by new child connection");
      } catch (err) {
        log("ERROR", `Error closing previous child: ${err}`);
      }
    }
    session.child = ws;
    log("INFO", `Child connected: uid=${uid}`);
  } else {
    session.parents.add(ws);
    log("INFO", `Parent connected: uid=${uid} (total parents: ${session.parents.size})`);

    // FIX-3: Send latest cached frame to newly connected parent immediately
    if (session.latestFrame) {
      try {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(session.latestFrame, { binary: true });
          log("INFO", `Sent cached latest frame to new parent for uid=${uid} (${session.latestFrame.length} bytes)`);
        }
      } catch (err) {
        log("ERROR", `Failed to send cached frame to new parent: ${err}`);
      }
    }
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
    // FIX-2: Explicit binary detection via Buffer check instead of relying solely on isBinary
    const isBinaryFrame = Buffer.isBuffer(data) || isBinary;

    // Only child should send binary frames
    if (role === "child" && isBinaryFrame) {
      // Frame size check
      if (data.length > MAX_FRAME_SIZE) {
        log("WARN", `Frame too large: ${data.length} bytes (max ${MAX_FRAME_SIZE}), uid=${uid}`);
        return; // Drop oversized frame
      }

      session.frameCount++;
      session.lastFrameAt = Date.now();
      totalFramesRelayed++; // FIX-5: track global frame count

      // FIX-3: Cache latest frame
      session.latestFrame = Buffer.from(data);

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
    } else if (role === "parent" && isBinaryFrame) {
      // Parents shouldn't send binary, but we handle gracefully
      log("WARN", `Parent attempted to send binary data, ignoring (uid=${uid})`);
    } else if (!isBinaryFrame) {
      // Text messages - could be used for control commands in the future
      const text = data.toString("utf-8");
      log("INFO", `Text message from ${role} uid=${uid}: ${text.slice(0, 200)}`);
    }
  });

  // Handle close
  ws.on("close", (code: number, reason: Buffer) => {
    handleClose(ws, false);
  });

  // Handle errors
  ws.on("error", (err: Error) => {
    log("ERROR", `WebSocket error for ${role} uid=${uid}: ${err.message}`);
    handleClose(ws, false);
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
  log("INFO", `Max frame size: ${MAX_FRAME_SIZE} bytes (${Math.round(MAX_FRAME_SIZE / 1024)}KB)`);
});

// ─── Graceful Shutdown ────────────────────────────────────────────────────────
function shutdown(signal: string): void {
  log("INFO", `Received ${signal}, shutting down gracefully...`);

  // FIX-8: Collect all open WebSocket connections with close handshake timeout
  const allSockets: WebSocket[] = [];
  for (const [, session] of sessions) {
    if (session.child && session.child.readyState === WebSocket.OPEN) {
      allSockets.push(session.child);
      session.child.close(1001, "Server shutting down");
    }
    for (const parent of session.parents) {
      if (parent.readyState === WebSocket.OPEN) {
        allSockets.push(parent);
        parent.close(1001, "Server shutting down");
      }
    }
  }

  // FIX-8: Force-terminate any sockets that haven't completed close handshake within timeout
  if (allSockets.length > 0) {
    const forceTimer = setTimeout(() => {
      for (const ws of allSockets) {
        if (ws.readyState !== WebSocket.CLOSED) {
          log("WARN", `Force-terminating WebSocket connection that did not complete close handshake`);
          ws.terminate();
        }
      }
    }, SHUTDOWN_CLOSE_TIMEOUT);

    // Clear timer if all sockets close gracefully before timeout
    let closedCount = 0;
    for (const ws of allSockets) {
      ws.on("close", () => {
        closedCount++;
        if (closedCount === allSockets.length) {
          clearTimeout(forceTimer);
        }
      });
    }
  }

  httpServer.close(() => {
    log("INFO", "HTTP server closed");
    process.exit(0);
  });

  // Force exit after 5 seconds (overall safety net)
  setTimeout(() => {
    log("WARN", "Forced shutdown after timeout");
    process.exit(1);
  }, 5000);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
