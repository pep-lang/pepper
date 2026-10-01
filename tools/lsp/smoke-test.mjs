// Smoke test for pepper-lsp: raw JSON-RPC over stdio.
// Usage: node tools/lsp/smoke-test.mjs <path-to-pep-file>
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";

const BIN = process.env.PEPPER_LSP_BIN || (process.platform === "win32" ? "target/debug/pepper-lsp.exe" : "target/debug/pepper-lsp");
const REPO_ROOT = process.env.PEPPER_REPO_ROOT || "D:/pepper";
const targetFile = process.argv[2];
const text = readFileSync(targetFile, "utf8");
const uri = "file:///D:/pepper/tests/String.Methods/test.pep";

const proc = spawn(BIN, [], { cwd: REPO_ROOT, stdio: ["pipe", "pipe", "inherit"] });

let buf = Buffer.alloc(0);
const pending = new Map(); // id -> resolve
const notifications = [];
let nextId = 1;

function send(obj) {
  const body = Buffer.from(JSON.stringify(obj), "utf8");
  proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
  proc.stdin.write(body);
}

function request(method, params) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    send({ jsonrpc: "2.0", id, method, params });
  });
}

function notify(method, params) {
  send({ jsonrpc: "2.0", method, params });
}

proc.stdout.on("data", (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  while (true) {
    const headerEnd = buf.indexOf("\r\n\r\n");
    if (headerEnd < 0) break;
    const header = buf.subarray(0, headerEnd).toString("utf8");
    const m = header.match(/Content-Length: (\d+)/i);
    if (!m) { buf = buf.subarray(headerEnd + 4); continue; }
    const len = parseInt(m[1], 10);
    if (buf.length < headerEnd + 4 + len) break;
    const body = buf.subarray(headerEnd + 4, headerEnd + 4 + len).toString("utf8");
    buf = buf.subarray(headerEnd + 4 + len);
    const msg = JSON.parse(body);
    if (msg.id !== undefined && pending.has(msg.id)) {
      const p = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) p.reject(new Error(JSON.stringify(msg.error)));
      else p.resolve(msg.result);
    } else if (msg.method) {
      notifications.push(msg);
    }
  }
});

let failures = 0;
function check(name, cond, extra) {
  if (cond) console.log(`PASS ${name}`);
  else { failures++; console.log(`FAIL ${name}${extra ? " — " + JSON.stringify(extra).slice(0, 400) : ""}`); }
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// Waits up to `ms` for the server to publish diagnostics for `u`. A valid file
// runs full sema over the runtime first, which can take seconds on a loaded
// runner, so a fixed delay races it.
async function diagnosticsFor(u, ms = 30000) {
  const find = () => notifications.find((n) => n.method === "textDocument/publishDiagnostics" && n.params.uri === u);
  for (const start = Date.now(); !find() && Date.now() - start < ms; ) await wait(50);
  return find();
}

// ── Case 1: valid file → empty diagnostics, hover, document symbols ──────────
const init = await request("initialize", { processId: null, rootUri: null, capabilities: {} });
check("initialize returns serverInfo pepper-lsp", init?.serverInfo?.name === "pepper-lsp", init);
check("capabilities advertise hover", !!init?.capabilities?.hoverProvider);
check("capabilities advertise completion", !!init?.capabilities?.completionProvider);
check("capabilities advertise definition", !!init?.capabilities?.definitionProvider);
check("capabilities advertise documentSymbol", !!init?.capabilities?.documentSymbolProvider);

notify("initialized", {});
notify("textDocument/didOpen", { textDocument: { uri, languageId: "pep", version: 1, text } });
const diags = await diagnosticsFor(uri);
check("diagnostics published for open doc", !!diags, notifications.map((n) => n.method));
check("valid file has zero diagnostics", diags?.params.diagnostics.length === 0, diags?.params.diagnostics);

// Hover over `s` in `s.append("ING");` (line 4 → LSP line 3, col 4).
const hover = await request("textDocument/hover", { textDocument: { uri }, position: { line: 3, character: 4 } });
check("hover on local var shows type", typeof hover?.contents?.value === "string" && hover.contents.value.includes("`s`") && hover.contents.value.includes("String"), hover);

// Hover over the string literal `"ING"` (line 4 → LSP line 3, col 14).
const hoverLit = await request("textDocument/hover", { textDocument: { uri }, position: { line: 3, character: 14 } });
check("hover on string literal shows `String`", typeof hoverLit?.contents?.value === "string" && hoverLit.contents.value.includes("`String`"), hoverLit);

// Document symbols.
const syms = await request("textDocument/documentSymbol", { textDocument: { uri } });
check("document symbols include main", Array.isArray(syms) && syms.some((s) => s.name === "main"), syms);

// Go-to-definition of `s` at its use in `s.append(...)` (line 4 → LSP line 3, col 4).
const def = await request("textDocument/definition", { textDocument: { uri }, position: { line: 3, character: 4 } });
check("go-to-definition of s finds declaration on line 3", Array.isArray(def) && def.length === 1 && def[0].range.start.line === 2, def);

// Completion inside the function body.
const comp = await request("textDocument/completion", { textDocument: { uri }, position: { line: 3, character: 4 } });
check("completion includes keyword `var`", Array.isArray(comp) && comp.some((c) => c.label === "var"), comp?.slice(0, 5));
check("completion includes local `s`", Array.isArray(comp) && comp.some((c) => c.label === "s"), comp);

// ── Case 2: file with a syntax error → diagnostic at the right line/col ───────
const badUri = "file:///D:/pepper/tools/lsp/smoke-bad.pep";
const badText = 'main(): int {\n    var x = ;\n}\n';
notify("textDocument/didOpen", { textDocument: { uri: badUri, languageId: "pep", version: 1, text: badText } });
const badDiags = await diagnosticsFor(badUri);
check("diagnostics published for broken doc", !!badDiags, notifications.map((n) => n.method));
check("broken file has a diagnostic", badDiags?.params.diagnostics.length >= 1, badDiags?.params.diagnostics);
// Parser reports the error at line 2 (the `var x = ;` statement).
const first = badDiags?.params.diagnostics[0];
check("parse diagnostic on line 2", first?.range.start.line === 1, first);
console.log("parse diagnostic:", JSON.stringify(first));

notify("exit", {});
proc.kill();
console.log(failures === 0 ? "ALL PASS" : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
