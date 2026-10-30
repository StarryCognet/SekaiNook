/**
 * Pages Functions → Node HTTP 适配层（测试站用，不改变 Cloudflare 的行为）。
 *
 * 做法：扫描 `functions/` 目录，按 Pages 的文件即路由规则生成路由表，
 * 把每个模块导出的 `onRequestXxx` 挂到 http.Server 上；
 * 业务代码（functions/**）一行不改，所以 CF 与本地 Node 共用同一份实现。
 *
 * 路由规则（与 Pages 一致）：
 *   api/ledger/index.ts       → /api/ledger
 *   api/ledger/[id].ts        → /api/ledger/:id
 *   api/images/[[key]].ts     → /api/images/*   （params.key 是数组，调用方会 join('/')）
 *   api/xxx.ts                → /api/xxx
 *   _middleware.ts            → 包在所有请求外层（只做 CORS，见原文件）
 *
 * 动态 import 用 tsx 的 loader 直接读 .ts，无需预编译。
 */
import http from 'node:http';
import { readdir } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { Readable } from 'node:stream';
import { buildEnv } from './env';

type Handler = (context: unknown) => Promise<Response> | Response;

interface RouteEntry {
  pattern: RegExp;
  keys: { name: string; rest: boolean }[];
  /** 静态段权重高：/api/ledger/summary 必须先于 /api/ledger/[id] 匹配 */
  score: number;
  module: Record<string, Handler>;
}

const ROOT = process.cwd();
const FUNCTIONS_DIR = process.env.FUNCTIONS_DIR ?? path.join(ROOT, 'functions');
const PORT = Number(process.env.PORT ?? 8788);
const HOST = process.env.HOST ?? '127.0.0.1';

/** 递归收集路由模块；`_` 开头的文件/目录（_middleware、_lib）不挂路由 */
async function walk(dir: string, out: string[] = []): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name.startsWith('_')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) await walk(full, out);
    else if (entry.isFile() && entry.name.endsWith('.ts')) out.push(full);
  }
  return out;
}

function toRoutePattern(file: string): {
  pattern: RegExp;
  keys: { name: string; rest: boolean }[];
  score: number;
} {
  let rel = path.relative(FUNCTIONS_DIR, file).split(path.sep).join('/').replace(/\.ts$/, '');
  if (rel === 'index') rel = '';
  else if (rel.endsWith('/index')) rel = rel.slice(0, -'/index'.length);

  const segments = rel === '' ? [] : rel.split('/');
  const keys: { name: string; rest: boolean }[] = [];
  let source = '^';
  let score = 0;

  for (const segment of segments) {
    const catchAll = /^\[\[(.+)\]\]$/.exec(segment);
    const param = /^\[(.+)\]$/.exec(segment);
    if (catchAll) {
      keys.push({ name: catchAll[1], rest: true });
      source += '/(.*)';
    } else if (param) {
      keys.push({ name: param[1], rest: false });
      source += '/([^/]+)';
      score += 1;
    } else {
      source += '/' + segment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      score += 10;
    }
  }

  source += '/?$';
  return { pattern: new RegExp(source), keys, score };
}

async function loadRoutes(): Promise<{ routes: RouteEntry[]; middleware: Handler | null }> {
  const files = await walk(FUNCTIONS_DIR);
  const routes: RouteEntry[] = [];

  for (const file of files) {
    const module = (await import(pathToFileURL(file).href)) as Record<string, Handler>;
    const { pattern, keys, score } = toRoutePattern(file);
    routes.push({ pattern, keys, score, module });
  }

  routes.sort((a, b) => b.score - a.score);

  let middleware: Handler | null = null;
  try {
    const mod = (await import(
      pathToFileURL(path.join(FUNCTIONS_DIR, '_middleware.ts')).href
    )) as Record<string, Handler>;
    middleware = mod.onRequest ?? null;
  } catch {
    middleware = null;
  }

  return { routes, middleware };
}

function matchRoute(url: string, routes: RouteEntry[]) {
  const pathname = new URL(url).pathname;
  for (const route of routes) {
    const matched = route.pattern.exec(pathname);
    if (!matched) continue;

    const params: Record<string, string | string[]> = {};
    route.keys.forEach((key, index) => {
      const raw = matched[index + 1] ?? '';
      if (key.rest) {
        params[key.name] = raw.split('/').filter(Boolean);
      } else {
        try {
          params[key.name] = decodeURIComponent(raw);
        } catch {
          params[key.name] = raw;
        }
      }
    });
    return { route, params };
  }
  return null;
}

async function toRequest(nodeRequest: http.IncomingMessage): Promise<Request> {
  const headers = new Headers();
  for (const [name, value] of Object.entries(nodeRequest.headers)) {
    if (Array.isArray(value)) value.forEach((item) => headers.append(name, item));
    else if (value !== undefined) headers.set(name, value);
  }

  const host = nodeRequest.headers.host ?? 'localhost';
  const url = `http://${host}${nodeRequest.url ?? '/'}`;
  const method = (nodeRequest.method ?? 'GET').toUpperCase();
  const hasBody = !['GET', 'HEAD'].includes(method);
  const body = hasBody ? (Readable.toWeb(nodeRequest) as unknown as ReadableStream) : undefined;

  return new Request(url, {
    method,
    headers,
    body,
    // undici 要求流式 body 显式声明 half duplex
    duplex: hasBody ? 'half' : undefined,
  } as RequestInit);
}

/** 按 Pages 约定挑处理函数：onRequestGet / onRequestPost / ... / onRequest */
function pickHandler(module: Record<string, Handler>, method: string): Handler | undefined {
  const suffix = method.charAt(0) + method.slice(1).toLowerCase();
  return module[`onRequest${suffix}`] ?? module.onRequest;
}

async function main() {
  const env = buildEnv();
  const { routes, middleware } = await loadRoutes();

  const server = http.createServer(async (nodeRequest, nodeResponse) => {
    try {
      const request = await toRequest(nodeRequest);

      const matched = matchRoute(request.url, routes);

      const context: Record<string, unknown> = {
        request,
        env,
        params: matched?.params ?? {},
        data: {},
        waitUntil: () => {},
      };
      context.next = () =>
        matched
          ? dispatch(matched.route, context, request.method)
          : Promise.resolve(new Response('Not Found', { status: 404 }));

      let response: Response;
      if (middleware) {
        response = await middleware(context);
      } else if (matched) {
        response = await dispatch(matched.route, context, request.method);
      } else {
        response = new Response('Not Found', { status: 404 });
      }

      nodeResponse.statusCode = response.status;
      response.headers.forEach((value, name) => {
        nodeResponse.setHeader(name, value);
      });

      if (response.body && request.method !== 'HEAD') {
        Readable.fromWeb(response.body as Parameters<typeof Readable.fromWeb>[0]).pipe(nodeResponse);
      } else {
        nodeResponse.end();
      }
    } catch (error) {
      console.error('[sekainook] request failed:', error);
      if (!nodeResponse.headersSent) {
        nodeResponse.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      }
      nodeResponse.end('Internal Server Error');
    }
  });

  const dispatch = async (route: RouteEntry, context: unknown, method: string) => {
    const handler = pickHandler(route.module, method);
    if (!handler) return new Response('Method Not Allowed', { status: 405 });
    return await handler(context);
  };

  server.listen(PORT, HOST, () => {
    console.log(`[sekainook] listening on http://${HOST}:${PORT}`);
    console.log(`[sekainook] DB      = ${env.DB_PATH}`);
    console.log(`[sekainook] R2_DIR  = ${env.R2_DIR}`);
    console.log(`[sekainook] routes  = ${routes.length}`);
    for (const route of routes) console.log(`  ${route.pattern.source}`);
  });

  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.on(signal, () => {
      console.log(`[sekainook] ${signal} → shutting down`);
      server.close(() => process.exit(0));
    });
  }
}

main().catch((error) => {
  console.error('[sekainook] failed to start:', error);
  process.exit(1);
});
