/**
 * SekaiNook 提醒 Worker（独立于 Pages 项目）。
 *
 * 为什么必须是独立 Worker：**Cloudflare Pages 不支持 cron triggers** —— 所以「21:30 提醒今天
 * 还差几个任务」这件事没法挂在 `functions/` 里，只能在 Pages 之外起一个带 `[triggers].crons`
 * 的 Worker，读同一个 D1（database_id 相同）。前端/函数一行都不用改。
 *
 * 两件事：
 *  - scheduled：cron `30 13 * * *`（UTC）= 21:30 北京时间 → 算完成数，没做够就推一条通知
 *  - fetch：`/health` 看配置是否齐、`/trigger` 手动触发（要令牌），联调用
 */
import type { ReminderEnv } from './env';
import { pickChannel, type PushChannel } from './channels';
import { planReminder, runReminder } from './reminder';

export default {
  async scheduled(
    _controller: ScheduledController,
    env: ReminderEnv,
    ctx: ExecutionContext
  ): Promise<void> {
    ctx.waitUntil(
      runReminder(env, { trigger: 'cron' }).then((result) => {
        console.log(JSON.stringify(result));
      })
    );
  },

  async fetch(request: Request, env: ReminderEnv): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      // 故意不返回「今天完成几个」——这个接口是公开的，没必要把家里的完成情况挂在公网上
      const plan = await planReminder(env);
      return json({
        ok: true,
        target: plan.target,
        deadline: plan.deadline,
        channel: pickChannel(env),
        server: env.NTFY_SERVER ?? 'https://ntfy.sh',
        hasTopic: Boolean(env.NTFY_TOPIC?.trim()),
        hasTriggerToken: Boolean(env.REMIND_TOKEN?.trim()),
        dryRun: env.DRY_RUN === '1',
        appUrl: env.APP_URL ?? '',
      });
    }

    if (url.pathname === '/trigger') {
      if (request.method !== 'GET' && request.method !== 'POST') {
        return json({ error: '只支持 GET / POST' }, 405);
      }
      if (!authorized(request, url, env)) {
        return json(
          {
            error: env.REMIND_TOKEN?.trim()
              ? '令牌不对'
              : '还没配置 REMIND_TOKEN：npx wrangler secret put REMIND_TOKEN（配好之前手动触发一律拒绝）',
          },
          401
        );
      }

      const nowParam = url.searchParams.get('now');
      const now = nowParam ? new Date(nowParam) : undefined;
      if (nowParam && Number.isNaN(now?.getTime())) {
        return json({ error: 'now 不是合法时间，例：2026-10-15T13:30:00Z' }, 400);
      }

      const channelParam = url.searchParams.get('channel')?.trim().toLowerCase();
      if (channelParam && !['ntfy', 'bark', 'webhook'].includes(channelParam)) {
        return json({ error: 'channel 只能是 ntfy / bark / webhook' }, 400);
      }

      const result = await runReminder(env, {
        trigger: 'manual',
        dry: flag(url, 'dry'),
        force: flag(url, 'force'),
        test: flag(url, 'test'),
        channel: channelParam as PushChannel | undefined,
        now,
      });
      return json(result);
    }

    return json(
      {
        error: 'not found',
        usage: [
          'GET  /health',
          'GET|POST /trigger?token=<REMIND_TOKEN>[&dry=1][&force=1][&test=1][&now=2026-10-15T13:30:00Z]',
        ],
      },
      404
    );
  },
} satisfies ExportedHandler<ReminderEnv>;

/** `?x=1` / `?x` 都算开；`?x=0` 算关（本地 DRY_RUN=1 时常用来单次真发） */
function flag(url: URL, name: string): boolean | undefined {
  if (!url.searchParams.has(name)) return undefined;
  const value = url.searchParams.get(name);
  return value !== '0' && value !== 'false';
}

function authorized(request: Request, url: URL, env: ReminderEnv): boolean {
  const expected = env.REMIND_TOKEN?.trim();
  if (!expected) return false;
  const header = request.headers.get('Authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ')
    ? header.slice(7).trim()
    : (url.searchParams.get('token') ?? '').trim();
  return token.length > 0 && token === expected;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}
