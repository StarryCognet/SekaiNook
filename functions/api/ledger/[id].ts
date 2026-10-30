/**
 * 单条积分流水接口。
 * 路由：PATCH /api/ledger/:id（更新审批状态）、DELETE /api/ledger/:id（删除记录并清理关联图片）
 */

import { gateAdminPassword } from '../../_lib/admin-auth';
import { amountText, pushNotifications } from '../../_lib/notifications';
import { displayName, readFamilyNames } from '../../_lib/settings';

interface Env {
  DB: D1Database;
  STARRYMIKU_BUCKET: R2Bucket;
  /** Pages secret：管理员口令的首次初始化值（线上以 settings 表里的哈希为准） */
  ADMIN_PASSWORD?: string;
}

const LEDGER_STATUSES: readonly string[] = ['pending', 'approved', 'rejected'];
/** 驳回理由长度上限 */
const REASON_MAX_LENGTH = 60;
/** 记录 id 的形状（与 POST 落库时同一口径），先挡掉奇怪的路径参数 */
const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_:.-]*$/;
const ID_MAX_LENGTH = 64;

/** 图片对象前缀：与 functions/api/upload.ts 的上传 key 规则一致 */
const IMAGE_KEY_PREFIX = 'tasks/';

/**
 * 管理员口令的来源：JSON body 的 `password` 字段，或 `x-admin-password` 头。
 * DELETE 没有 body，走头；PATCH 两个都收，前端按方便选。
 */
function readAdminPassword(request: Request, body?: Record<string, unknown>): string {
  const fromBody = body && typeof body.password === 'string' ? body.password.trim() : '';
  if (fromBody) return fromBody;
  return request.headers.get('x-admin-password')?.trim() ?? '';
}

/**
 * 从图片 URL（.../api/images/<key>）中还原 R2 对象 key，非法则返回 null。
 * 只认 tasks/ 前缀下的普通 key：历史数据里 image_url 没校验过，不能让
 * `../../` 或别的前缀混进删除逻辑。
 */
function extractImageKey(imageUrl: string): string | null {
  const prefix = '/api/images/';
  try {
    const { pathname } = new URL(imageUrl, 'https://site.invalid');
    if (!pathname.startsWith(prefix)) return null;
    const key = decodeURIComponent(pathname.slice(prefix.length));
    if (!key.startsWith(IMAGE_KEY_PREFIX) || key.includes('..') || key.includes('//')) return null;
    return key;
  } catch {
    return null;
  }
}

/**
 * 这张图是否还被别处引用（其他流水 / 全局背景图）。
 * 删流水前必须查一次：image_url 历史上没有校验，构造一条指向别人照片（包括
 * settings.background 那张全家背景）的流水再删，就能把任意 R2 对象删掉。
 */
async function imageStillReferenced(env: Env, imageUrl: string): Promise<boolean> {
  const key = extractImageKey(imageUrl);
  if (!key) return true; // 认不出 key 就不删（保守）

  const others = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM family_ledger WHERE image_url LIKE ?'
  )
    .bind(`%${key}`)
    .first<{ n: number }>();
  if ((others?.n ?? 0) > 0) return true;

  const background = await env.DB.prepare('SELECT value FROM settings WHERE key = ?')
    .bind('background')
    .first<{ value: string }>();
  const backgroundKey =
    typeof background?.value === 'string' ? extractImageKey(background.value) : null;
  return backgroundKey === key;
}

/** 更新审批状态（审批通过 / 驳回 / 重新提交） */
export const onRequestPatch: PagesFunction<Env> = async ({ params, request, env }) => {
  const id = String(params.id);
  if (!ID_PATTERN.test(id) || id.length > ID_MAX_LENGTH) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { status } = body;
  if (typeof status !== 'string' || !LEDGER_STATUSES.includes(status)) {
    return Response.json({ error: 'status 非法' }, { status: 400 });
  }

  // 驳回时家长可以留一句话，会原样带给女儿（比固定文案有用得多）
  const reason =
    typeof body.reason === 'string' ? body.reason.trim().slice(0, REASON_MAX_LENGTH) : '';

  // 先读原记录：既用于 404 判定，也用于给通知拼文案、判断状态是否真的变了
  const record = await env.DB.prepare(
    'SELECT task_name, type, amount, status FROM family_ledger WHERE id = ?'
  )
    .bind(id)
    .first<{ task_name: string; type: string; amount: number; status: string }>();

  if (!record) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }

  // ── 口令闸 ──
  // 审批通过 / 驳回 / 家长撤销（approved→pending）都必须家长口令。
  // 唯一免口令的路径是「孩子把被驳回的记录重新提交」（rejected→pending）：
  // 那条只是把申请放回待审批，不改变余额。不做闸时 GET /api/ledger 匿名吐全部 id，
  // 任何人拿 id PATCH 一条就能伪造「家长审批」。
  const childResubmit = status === 'pending' && record.status === 'rejected';
  if (!childResubmit) {
    const gate = await gateAdminPassword(env.DB, readAdminPassword(request, body), env.ADMIN_PASSWORD);
    if (!gate.ok) return Response.json(gate.body, { status: gate.status });
  }

  // 只改状态，不信任客户端别的字段；带上 changes 检查，记录在读到之后被删掉时别回 ok
  const updated = await env.DB.prepare('UPDATE family_ledger SET status = ? WHERE id = ?')
    .bind(status, id)
    .run();
  if ((updated.meta?.changes ?? 0) === 0) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }

  // 状态没变就不重复通知（家长连点两下、网络重试都会走到这里）
  if (record.status !== status) {
    const amountLabel = amountText(record.type, record.amount);
    // 文案里的称呼按设置表走：孩子看的是「妈妈通过了…」，家长看的是「女儿提交了…」
    const names = await readFamilyNames(env.DB);
    const mom = displayName(names, 'mom');
    const kid = displayName(names, 'kid');
    if (status === 'approved') {
      await pushNotifications(env.DB, [
        {
          audience: 'child',
          type: 'approved',
          title: `${mom}通过了「${record.task_name}」`,
          body: `${amountLabel} 积分已入账`,
          link: '/family',
          dedupeKey: `ledger:${id}:approved:${record.status}`,
        },
      ]);
    } else if (status === 'rejected') {
      await pushNotifications(env.DB, [
        {
          audience: 'child',
          type: 'rejected',
          title: `${mom}驳回了「${record.task_name}」`,
          body: reason ? `${mom}说：${reason}` : '看看哪里不对，改好可以再提交一次',
          link: '/family',
          dedupeKey: `ledger:${id}:rejected:${record.status}`,
        },
      ]);
    } else if (status === 'pending') {
      await pushNotifications(env.DB, [
        {
          audience: 'parent',
          type: 'resubmitted',
          title: `${kid}重新提交了打卡`,
          body: `${record.task_name} ${amountLabel}`,
          link: '/family',
          dedupeKey: `ledger:${id}:resubmit:${record.status}`,
        },
      ]);
    }
  }

  return Response.json({ ok: true });
};

/** 删除一条流水，并一并删除其关联的 R2 图片 */
export const onRequestDelete: PagesFunction<Env> = async ({ params, request, env }) => {
  const id = String(params.id);
  if (!ID_PATTERN.test(id) || id.length > ID_MAX_LENGTH) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }

  // 先取出记录，拿到图片地址与状态（删除后无法再查）
  const record = await env.DB.prepare('SELECT status, image_url FROM family_ledger WHERE id = ?')
    .bind(id)
    .first<{ status: string | null; image_url: string | null }>();
  if (!record) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }

  // ── 口令闸 ──
  // 孩子撤回自己的「待审批」记录免口令（它还没进余额）；删除已通过 / 已驳回的流水
  // 会改写历史余额，必须家长口令。不做闸时公开 id 就能把整张流水表清空（含 R2 照片）。
  if (record.status !== 'pending') {
    const gate = await gateAdminPassword(
      env.DB,
      readAdminPassword(request),
      env.ADMIN_PASSWORD
    );
    if (!gate.ok) return Response.json(gate.body, { status: gate.status });
  }

  // 先删库、再删图：反过来一旦删图成功而删库失败，就会留下「点开是坏图」的流水
  const deleted = await env.DB.prepare('DELETE FROM family_ledger WHERE id = ?').bind(id).run();
  if ((deleted.meta?.changes ?? 0) === 0) {
    return Response.json({ error: '记录不存在' }, { status: 404 });
  }

  if (record.image_url) {
    try {
      // 还被别的流水或全局背景图用着就不删（历史数据可能指向别处）
      if (!(await imageStillReferenced(env, record.image_url))) {
        const key = extractImageKey(record.image_url);
        if (key) await env.STARRYMIKU_BUCKET.delete(key);
      }
    } catch (error) {
      // 图片没删掉不影响流水已删；留下的孤儿由「清理闲置照片」兜底
      console.error('delete ledger image failed', error);
    }
  }

  return Response.json({ ok: true });
};
