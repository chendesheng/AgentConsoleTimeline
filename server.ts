type Session = {
  id: string;
  sourceSock: WebSocket;
};

const sessions = new Map<string, Session>();

Deno.serve({ port: 5174 }, (req) => {
  console.log("Request:", req.url, req.method);

  const url = new URL(req.url);
  if (req.method === "OPTIONS") {
    handleCORS(req);
  } else if (url.pathname === "/session") {
    return handleNewSession(req);
  } else if (url.pathname === "/connect") {
    return handleConnect(req);
  } else if (req.method === "GET" && url.pathname === "/sessions") {
    return handleGetSessions(req);
  }

  return new Response(null, { status: 404 });
});

function handleCORS(req: Request) {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*"
    }
  });
}

function handleNewSession(req: Request) {
  if (req.headers.get("upgrade") != "websocket") {
    return new Response(null, { status: 501 });
  }
  const { socket, response } = Deno.upgradeWebSocket(req);
  const url = new URL(req.url);

  const session = url.searchParams.get("session");
  if (!session) {
    return new Response("session is required", { status: 400 });
  }

  sessions.set(session, { id: session, sourceSock: socket });
  return response;
}

function handleConnect(req: Request) {
  if (req.headers.get("upgrade") != "websocket") {
    return new Response(null, { status: 501 });
  }
  const { socket, response } = Deno.upgradeWebSocket(req);
  const url = new URL(req.url);

  const sessionId = url.searchParams.get("session");
  if (!sessionId) {
    return new Response("session is required", { status: 400 });
  }

  const session = sessions.get(sessionId);
  if (!session) {
    return new Response("session not found", { status: 404 });
  }

  session.sourceSock.addEventListener("message", (event) => {
    console.log("Received message from source:", event.data);
    socket.send(event.data);
  });

  socket.addEventListener("message", (event) => {
    console.log("Received message from client:", event.data);
    session.sourceSock.send(event.data);
  });

  return response;
}

function handleGetSessions(req: Request) {
  const sessionIds = Array.from(sessions.keys());
  return new Response(JSON.stringify(sessionIds), {
    headers: {
      "Content-Type": "application/json"
    }
  });
}
