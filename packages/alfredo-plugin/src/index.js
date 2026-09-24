import { watch, readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { spawn } from 'node:child_process';

const API_PATH = '/api/alfredo';

// DSH Fetch routes are exact paths; wildcards are rejected at load time.
const ROUTES = {
  GET: ['tasks', 'ready', 'sessions', 'packages', 'task-events'],
  POST: ['tasks', 'cancel', 'done', 'approve', 'cleanup', 'sessions', 'session/close',
    'packages/install', 'packages/uninstall', 'packages/update', 'worker'],
};

// DSH runs from an arbitrary directory; the Alfredo project is a registered
// workspace that holds `.alfredo/`, most recently updated first.
function resolveCwd(ctx, config) {
  if (config.cwd) return config.cwd;
  try {
    const found = (ctx.workspaceRegistry?.list() ?? [])
      .filter((w) => existsSync(join(w.path, '.alfredo')))
      .sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)))[0];
    if (found) return found.path;
  } catch (_) {}
  return process.cwd();
}

function runAlfredo(args, cwd, signal) {
  return new Promise((resolve, reject) => {
    const child = spawn('alfredo', args, { cwd, shell: false, stdio: ['ignore', 'pipe', 'pipe'], signal });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.once('error', reject);
    child.once('close', (code) => code === 0
      ? resolve(stdout.trim())
      : reject(new Error(stderr.trim() || `alfredo exited ${code}`)));
  });
}

async function commandResponse(request, cwd) {
  const url = new URL(request.url);
  const resource = url.pathname.slice(API_PATH.length + 1);
  const method = request.method.toUpperCase();
  let body = {};
  if (method === 'POST' || method === 'PUT') {
    try { body = await request.json(); } catch (_) {}
  }
  let args;
  if (method === 'GET' && resource === 'tasks') {
    args = ['task', 'list', '--json'];
  } else if (method === 'GET' && resource === 'ready') {
    args = ['task', 'ready', '--json', ...(url.searchParams.get('track') ? ['--track', url.searchParams.get('track')] : [])];
  } else if (method === 'GET' && resource === 'sessions') {
    args = ['session', 'list', '--json'];
  } else if (method === 'GET' && resource === 'packages') {
    try {
      const output = await runAlfredo(['package', 'list'], cwd, request.signal);
      const lines = output.split('\n').filter(Boolean);
      const pkgs = lines.map(line => {
        const [id, version, source] = line.split('\t');
        return { id: id || line, version: version || '', source: source || '' };
      });
      return Response.json(pkgs, { headers: { 'cache-control': 'no-store' } });
    } catch (e) {
      return Response.json([], { headers: { 'cache-control': 'no-store' } });
    }
  } else if (method === 'GET' && resource === 'task-events') {
    const taskId = url.searchParams.get('task');
    try {
      const eventsDir = join(cwd, '.alfredo', 'task-events');
      const files = readdirSync(eventsDir);
      const events = [];
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        if (taskId && !file.includes(taskId)) continue;
        try {
          const content = readFileSync(join(eventsDir, file), 'utf8');
          events.push(JSON.parse(content));
        } catch (_) {}
      }
      events.sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));
      return Response.json(events, { headers: { 'cache-control': 'no-store' } });
    } catch (_) {
      return Response.json([], { headers: { 'cache-control': 'no-store' } });
    }
  } else if (method === 'POST' && resource === 'tasks') {
    args = ['task', 'create', '--json', '--title', String(body.title || '')];
    if (body.priority) args.push('--priority', String(body.priority));
    if (body.run) args.push('--run', String(body.run));
    if (body.track) args.push('--track', String(body.track));
    for (const dep of body.dependencies || []) args.push('--depends-on', String(dep));
    for (const item of body.acceptance || []) args.push('--acceptance', String(item));
    for (const item of body.topics || []) args.push('--topic', String(item));
    for (const item of body.files || []) args.push('--file', String(item));
  } else if (method === 'POST' && resource === 'cancel') {
    args = ['task', 'cancel', String(body.task), '--json'];
  } else if (method === 'POST' && (resource === 'done' || resource === 'approve')) {
    args = ['task', 'done', String(body.task), '--json'];
  } else if (method === 'POST' && resource === 'cleanup') {
    args = ['task', 'cleanup', String(body.task), '--json', ...(body.force ? ['--force'] : [])];
  } else if (method === 'POST' && resource === 'sessions') {
    args = ['session', 'start', '--adapter', String(body.adapter || 'codex'), '--agent', String(body.agent || 'executor'), '--json'];
  } else if (method === 'POST' && resource === 'session/close') {
    args = ['session', 'close', String(body.session), '--json', ...(body.reason ? ['--reason', String(body.reason)] : [])];
  } else if (method === 'POST' && resource === 'packages/install') {
    args = ['package', 'install', String(body.package), '--target', String(body.target || 'dsh'), '--scope', String(body.scope || 'user')];
  } else if (method === 'POST' && resource === 'packages/uninstall') {
    args = ['package', 'uninstall', String(body.package), '--target', String(body.target || 'dsh'), '--scope', String(body.scope || 'user')];
  } else if (method === 'POST' && resource === 'packages/update') {
    args = ['update'];
  } else if (method === 'POST' && resource === 'worker') {
    args = ['session', 'start', '--adapter', String(body.adapter || 'antigravity'), '--agent', String(body.agent || 'executor'), '--json'];
  } else {
    return new Response('Not found', { status: 404 });
  }

  try {
    const output = await runAlfredo(args, cwd, request.signal);
    let data = null;
    if (output) {
      // Package commands print plain text rather than JSON.
      try { data = JSON.parse(output); } catch (_) { data = { ok: true, output }; }
    }
    return Response.json(data, { headers: { 'cache-control': 'no-store' } });
  } catch (error) {
    return Response.json({ error: error.message }, { status: 400 });
  }
}

export function apply(ctx, config = {}) {
  const cwd = () => resolveCwd(ctx, config);
  const resources = new Set([...ROUTES.GET, ...ROUTES.POST]);
  for (const resource of resources) {
    ctx.connection.fetch.register({
      path: `${API_PATH}/${resource}`,
      methods: ['GET', 'POST'].filter((m) => ROUTES[m].includes(resource)),
      requestBody: 'buffered',
      fetch: (request) => commandResponse(request, cwd()),
    });
  }
  let timer;
  let watcher;
  try {
    watcher = watch(join(cwd(), '.alfredo'), { recursive: true }, (_, filename) => {
      if (!filename || (!filename.startsWith('tasks/') && !filename.startsWith('task-events/'))) return;
      clearTimeout(timer);
      timer = setTimeout(() => ctx.emit('alfredo/update', filename), 250);
    });
  } catch (_) {
    // An uninitialized workspace is a valid empty state.
  }
  ctx.effect(() => () => { clearTimeout(timer); watcher?.close(); });
}

export const name = 'alfredo-plugin';
export const inject = ['connection', 'workspaceRegistry'];
