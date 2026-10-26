// Status Page, a Sidefolk extension template for Node (18 or later, no packages).
// MCP over stdio: one JSON-RPC message per line in, one per line out, nothing else on stdout
// (console.error for logs). Sidefolk runs it in a sandbox with the internet and nothing else.
import { createInterface } from "node:readline";

const TOOLS = [{
  name: "service_status",
  title: "Service status",
  description: "The overall status of a service that publishes a Statuspage summary, such as www.githubstatus.com.",
  inputSchema: {
    type: "object", additionalProperties: false, required: ["host"],
    properties: { host: { type: "string", maxLength: 200, description: "The status page's host, like www.githubstatus.com." } },
  },
}];

async function serviceStatus({ host }) {
  if (!/^[a-z0-9.-]+$/i.test(host)) throw new Problem("Give the status page's host name, like www.githubstatus.com.");
  const response = await fetch(`https://${host}/api/v2/status.json`, { signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Problem(`${host} answered ${response.status}; it may not be a Statuspage site.`);
  const body = await response.json();
  return `${body.page?.name ?? host}: ${body.status?.description ?? "unknown"}.`;
}

class Problem extends Error {}

async function answer(method, params) {
  switch (method) {
    case "initialize":
      return { protocolVersion: params.protocolVersion ?? "2025-06-18", capabilities: { tools: {} },
               serverInfo: { name: "status-page", version: "0.1.0" } };
    case "ping":
      return {};
    case "tools/list":
      return { tools: TOOLS };
    case "tools/call":
      if (params.name !== "service_status") return { content: [{ type: "text", text: "Unknown tool." }], isError: true };
      try {
        return { content: [{ type: "text", text: await serviceStatus(params.arguments ?? {}) }] };
      } catch (error) {
        // A Problem is for the model to read and fix; anything else is reported the same way, briefly.
        return { content: [{ type: "text", text: error instanceof Problem ? error.message : `It failed: ${error.message}` }], isError: true };
      }
    default:
      throw Object.assign(new Error(`Method not found: ${method}`), { code: -32601 });
  }
}

const lines = createInterface({ input: process.stdin });
lines.on("line", async (line) => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  if (message === null || typeof message !== "object" || !("id" in message)) return; // notifications need no answer
  const reply = { jsonrpc: "2.0", id: message.id };
  try {
    reply.result = await answer(message.method, message.params ?? {});
  } catch (error) {
    reply.error = { code: error.code ?? -32603, message: error.message };
  }
  process.stdout.write(JSON.stringify(reply) + "\n");
});
