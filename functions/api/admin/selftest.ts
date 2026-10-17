/**
 * 全站自检控制台接口。
 * 路由：GET  /api/admin/selftest —— 取清单（不需要密码，清单不含任何数据）
 *       POST /api/admin/selftest —— 跑自检（要管理员密码，与 POST /api/admin 同一套节流）
 *
 * **为什么清单也在服务端**：检查项分散在 functions/_lib/selftest/*，清单与执行是同一份
 *   数据（见 registry.ts）。若清单写在客户端，加了检查项忘了同步两端就会漂。
 *
 * **为什么 GET 不要密码**：清单里只有「有哪些检查、能不能写库」这种静态信息，不含余额、
 *   不含通知内容。而且管理员区在客户端本来就在口令门禁之后，多一道密码只是让 UI 更难写。
 *   真正会动数据的是 POST，那里必须过闸门（见 _lib/admin-auth.ts）。
 *
 * **为什么把提醒 Worker 也纳进来**：手机提醒是「Worker 定时 + 浏览器订阅」两段，
 *   出问题时最难判断是哪一段。自检里能直接看 Worker 在不在线、预演算出来几个人没做完、
 *   以及真发一条能不能到达设备。
 */

import { gateAdminPassword, adminLockedResponse } from '../../_lib/admin-auth';
import { buildCatalog, runSelftest } from '../../_lib/selftest/run';
import type { SelftestEnv, SelftestRunRequest } from '../../_lib/selftest/types';

interface Env extends SelftestEnv {
  DB: D1Database;
}

/** 站点根地址：自检要打真实 HTTP 路径，所以按请求的 origin 拼 */
function originOf(request: Request): string {
  const url = new URL(request.url);
  return `${url.protocol}//${url.host}`;
}

export const onRequestGet: PagesFunction<Env> = async () => {
  return Response.json(buildCatalog());
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return Response.json({ error: '请求体必须是对象' }, { status: 400 });
  }

  const body = payload as Record<string, unknown>;
  const password = typeof body.password === 'string' ? body.password : '';

  const gate = await gateAdminPassword(env.DB, password);
  if (!gate.ok) {
    if (gate.status === 429) {
      return adminLockedResponse(Number(gate.body.lockRemainingMs ?? 0));
    }
    return Response.json(gate.body, { status: gate.status });
  }

  const runRequest: SelftestRunRequest = {
    password,
    items: Array.isArray(body.items) ? (body.items as string[]) : undefined,
    groups: Array.isArray(body.groups) ? (body.groups as string[]) : undefined,
    params: body.params && typeof body.params === 'object' ? (body.params as Record<string, unknown>) : undefined,
    clientResults: Array.isArray(body.clientResults) ? (body.clientResults as SelftestRunRequest['clientResults']) : undefined,
    includeClient: body.includeClient === undefined ? undefined : Boolean(body.includeClient),
  };

  try {
    const result = await runSelftest(env, originOf(request), runRequest);
    return Response.json(result);
  } catch (error) {
    console.error('selftest run failed', error);
    return Response.json(
      { error: `自检没跑起来：${error instanceof Error ? error.message : String(error)}` },
      { status: 500 }
    );
  }
};
