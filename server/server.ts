import * as path from "jsr:@std/path";

const _p = (file: string) => path.join(import.meta.dirname, file);

type Session = {
  id: string;
  sourceSock: WebSocket;
};

const DENO_DEPLOY = Deno.env.get("DENO_DEPLOYMENT_ID") !== undefined;

const sessions = new Map<string, Session>();

if (DENO_DEPLOY) {
  Deno.serve(handleReq);
} else {
  Deno.serve(
    {
      port: 5174,
      cert: await Deno.readTextFile(_p("./cert.pem")),
      key: await Deno.readTextFile(_p("./key.pem")),
    },
    handleReq
  );
}

function handleReq(req: Request) {
  console.log(req.method, req.url);

  const url = new URL(req.url);
  if (req.method === "OPTIONS") {
    return handleCORS(req);
  } else if (url.pathname === "/session") {
    return handleNewSession(req);
  } else if (url.pathname === "/connect") {
    return handleConnect(req);
  } else if (req.method === "GET" && url.pathname === "/sessions") {
    return handleGetSessions(req);
  }

  return new Response(null, { status: 404 });
}

function handleCORS(req: Request) {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
    },
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
  socket.onclose = () => {
    socket.onclose = null;
    sessions.delete(session);
  };
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

  const handleSourceMessage = (event: any) => {
    // console.log("Received message from source:", event.data);
    if (socket.readyState !== WebSocket.OPEN) return;

    socket.send(event.data);
  };

  const handleSourceClose = () => {
    socket.close();
  };

  session.sourceSock.addEventListener("message", handleSourceMessage);
  session.sourceSock.addEventListener("close", handleSourceClose);

  socket.onmessage = (event: any) => {
    // console.log("Received message from client:", event.data);
    session.sourceSock.send(event.data);
  };

  socket.onclose = () => {
    session.sourceSock.removeEventListener("message", handleSourceMessage);
    session.sourceSock.removeEventListener("close", handleSourceClose);
    socket.onmessage = null;
    socket.onclose = null;
  };

  return response;
}

function handleGetSessions(req: Request) {
  const sessionIds = Array.from(sessions.keys());
  return new Response(JSON.stringify(sessionIds), {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Content-Type": "application/json",
    },
  });
}
