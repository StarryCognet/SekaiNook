/**
 * 积分流水集合接口。
 * 路由：GET /api/ledger（?status= / ?member= / ?limit= / ?since=）、POST /api/ledger
 *
 * 两条硬规矩：
 *  1. **POST 不采信客户端声称的审批状态**。除了服务端规则里标了 autoApprove 的花园奖励，
 *     其余一律写成 pending；只有 PATCH /api/ledger/:id 才能把它改成 approved。
 *     积分值、任务名、类型也一律以服务端规则（functions/_lib/rules.ts）为准。
 *  2. **幂等**：客户端可以自带 id（网络重试、离线补发都用同一个 id），
 *     主键冲突时直接返回已有记录，不会重复入账。
 *
 * 说明：member 列由 migrations/0002_ledger_member.sql 引入（历史遗留：多成员功能已下线，
 * 前端不再传该字段，接口保留此列只为兼容老数据）。
 */

import { amountText, pushNotifications } from '../../_lib/notifications';
import { displayName, readFamilyNames, sanitizeBackground } from '../../_lib/settings';
import {
  CUSTOM_TASK_DAILY_CAP,
  EXEC_TASK_ID,
  LEDGER_TASK_RULES,
  beijingDayBounds,
  checkLedgerRule,
} from '../../_lib/rules';

interface Env {
  DB: D1Database;
}

/** 成员名长度上限，避免脏数据撑爆界面 */
const MEMBER_MAX_LENGTH = 20;
/** 一次最多拉多少条；不传时默认最近 200 条（原先无上限整表拉取） */
const DEFAULT_LIMIT = 200;
const MAX_LIMIT = 500;
const ID_MAX_LENGTH = 64;
const ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_:.-]*$/;
/** 客户端自带任务名的长度上限（只有自定义任务走这条路），避免脏数据撑爆界面 */
const CLIENT_NAME_MAX_LENGTH = 30;

/** 查询流水列表，按创建时间倒序，可按状态/成员过滤，支持增量与分页 */
export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const search = new URL(request.url).searchParams;
  const status = search.get('status');
  const member = search.get('member');
  const since = search.get('since');
  const limitRaw = Number(search.get('limit'));
  const limit =
    Number.isFinite(limitRaw) && limitRaw > 0
      ? Math.min(Math.floor(limitRaw), MAX_LIMIT)
      : DEFAULT_LIMIT;

  const clauses: string[] = [];
  const values: string[] = [];
  if (status) {
    clauses.push('status = ?');
    values.push(status);
  }
  if (member) {
    clauses.push('member = ?');
    values.push(member);
  }
  if (since) {
    // 增量拉取：只要比上次拿到的更新的记录
    clauses.push('created_at > ?');
    values.push(since);
  }
  const where = clauses.length > 0 ? ` WHERE ${clauses.join(' AND ')}` : '';

  const stmt = env.DB.prepare(
    `SELECT * FROM family_ledger${where} ORDER BY created_at DESC LIMIT ${limit}`
  );
  const { results } = await (values.length > 0 ? stmt.bind(...values) : stmt).all();
  return Response.json(results ?? []);
};

/** 新增一条流水（默认进待审批，除服务端标记 autoApprove 的花园奖励） */
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let body: Record<string, unknown>;
  try {
    body = await request.json<Record<string, unknown>>();
  } catch {
    return Response.json({ error: '请求体不是合法 JSON' }, { status: 400 });
  }

  const { task_id, amount, note, image_url } = body;

  if (typeof task_id !== 'string' || !task_id || task_id.length > ID_MAX_LENGTH) {
    return Response.json({ error: 'task_id 非法' }, { status: 400 });
  }

  // image_url 只认本站图片：pathname 以 /api/images/ 开头、不带 query/hash，
  // 而且 origin 必须是我们自己。不校验的话既能塞外链（追踪像素），
  // 也能让 DELETE 接口拿它反推出别人的 R2 key 去删对象。
  let imageValue: string | null = null;
  if (image_url !== undefined && image_url !== null) {
    imageValue = sanitizeBackground(image_url, new URL(request.url).origin);
    if (imageValue === null) {
      return Response.json({ error: 'image_url 必须是本站上传的图片地址' }, { status: 400 });
    }
  }

  // 已知任务：名字 / 类型 / 积分全部以服务端规则为准，客户端改不动
  const rule = LEDGER_TASK_RULES[task_id];
  // v1.30 堵空洞：未知 task_id 一律拒绝。
  // 旧行为是「客户端带齐 task_name/type/amount 就放行」，而且规则没有 dailyLimit 时下面
  // 整段限次判断会被跳过 ⇒ 可以编个 task_id 无限自报金额刷分。
  // 客户端自定义任务改走 user_task_exec（有 dailyLimit + clientAmount 夹取）。
  if (!rule) {
    return Response.json({ error: '未知任务，不能记账' }, { status: 403 });
  }
  // 服务端自己生成的记录（开户礼金 / 日结算罚款）也不接受客户端提交：
  // seed_welcome_bonus 是 autoApprove + 日限 1，若能直接 POST 就成了「每天白拿 100」。
  if (rule.serverOnly) {
    return Response.json({ error: `「${rule.name}」由服务端自动记账，不能直接提交` }, { status: 403 });
  }
  // 客户端金额只有在规则显式开了 clientAmount 时才被采纳（老余额迁移 garden_legacy、
  // v1.30 的自定义任务 user_task_exec）：先校验客户端 amount 是有限数，
  // 再四舍五入并夹到规则给的上下限内。
  // 超范围是**夹住而不是报错**：老数据万一记超了，也要按上限搬进来，不能让迁移整个失败。
  // 例外：clientAmountValidateOnly 的规则（预置学习任务 custom:english_words10 / custom:poem2）
  // 只借 clientAmount 做「客户端能不能传」的兼容校验，金额严格按服务端 rule.value —— 契约 §2
  // 规定这两条固定 +10，若采纳客户端值就能伪造 amount:100 多拿 90 分。
  let clientAmount: number | null = null;
  if (rule.clientAmount) {
    if (typeof amount !== 'number' || !Number.isFinite(amount)) {
      return Response.json({ error: 'amount 非法' }, { status: 400 });
    }
    if (!rule.clientAmountValidateOnly) {
      const { min, max } = rule.clientAmount;
      clientAmount = Math.min(Math.max(Math.round(amount), min), max);
    }
  }

  // 任务名默认由服务端规则定，客户端改不动；只有标了 clientName 的规则（v1.30 自定义任务
  // user_task_exec）才采纳客户端任务名 —— 契约 §2「名称由客户端带」。
  // 金额 / 类型 / 状态仍然完全由服务端说了算；空名回退到规则名，并做长度截断。
  const clientName =
    rule.clientName && typeof body.task_name === 'string'
      ? body.task_name.trim().replace(/\s+/g, ' ')
      : '';
  const finalName = clientName ? clientName.slice(0, CLIENT_NAME_MAX_LENGTH) : rule.name;
  // 客户端金额可正可负的规则（user_task_exec）：记录类型跟着金额符号走。
  // 否则「-50 的自定义任务」会被记成 type='earning' amount=-50，前端按 type 判收支会显示成 +50。
  // 对 garden_legacy（min 0）和所有不吃客户端金额的规则，结果与旧行为完全一致。
  const finalType = clientAmount !== null && clientAmount < 0 ? 'spending' : rule.type;
  // 没有 clientAmount 的规则一如既往：金额只认服务端 rule.value，客户端改不动
  const finalAmount = clientAmount ?? rule.value;

  // 客户端传来的 status 一律忽略：只有服务端标了 autoApprove 的才直接入账
  const finalStatus = rule?.autoApprove ? 'approved' : 'pending';

  const now = new Date();
  if (rule && !rule.autoApprove) {
    const blocked = checkLedgerRule(rule, now);
    if (blocked) {
      return Response.json({ error: blocked }, { status: 409 });
    }
  }

  // 客户端可以自带记录 id（网络重试 / 离线补发复用同一个 id）。这里先算出来，
  // 因为下面的每日上限判定要用它做一次幂等确认 —— 见那个分支里的说明。
  const providedId =
    typeof body.id === 'string' && ID_PATTERN.test(body.id) ? body.id.slice(0, ID_MAX_LENGTH) : null;
  const id = providedId ?? crypto.randomUUID();

  const { startIso, endIso } = beijingDayBounds(now);
  if (rule?.dailyLimit !== undefined) {
    // clientName 规则（v1.30 自定义任务）全都共用 EXEC_TASK_ID 一个 task_id，按 task_id 计数
    // 会把「整张自定义列表」当成一个任务（做了英语单词就再也不能倒垃圾）。这条路径改成三层闸门：
    //   ① 按任务名判重：同一个自定义任务每天只能打卡一次。用的是**即将写入库的那个 finalName**
    //      （trim + 折叠空白 + 截断之后的规范化结果）—— 写得进什么，就按什么判重，
    //      空格/大小写差异绕不过去；
    //   ② 粗闸门：当天自定义任务条数不超过 dailyLimit（20），防止列表被无限灌；
    //   ③ 总额闸门：当天自定义任务累计得分不超过 CUSTOM_TASK_DAILY_CAP（50），防换名刷分。
    // 其余规则（各自独立 id）的日限语义一字未动：只按 task_id 计数。
    const perTaskName = rule.clientName === true;
    const counted = await env.DB.prepare(
      perTaskName
        ? `SELECT COUNT(*) AS c FROM family_ledger
           WHERE task_id = ? AND task_name = ? AND status != 'rejected' AND created_at >= ? AND created_at < ?`
        : `SELECT COUNT(*) AS c FROM family_ledger
           WHERE task_id = ? AND status != 'rejected' AND created_at >= ? AND created_at < ?`
    )
      .bind(...(perTaskName ? [task_id, finalName, startIso, endIso] : [task_id, startIso, endIso]))
      .first<{ c: number }>();

    let limitMessage: string | null = null;
    if (perTaskName) {
      if ((counted?.c ?? 0) >= 1) {
        // ① 同名任务今天已经打过卡了
        limitMessage = `「${finalName}」今天已经打过卡啦`;
      } else {
        const totalToday = await env.DB.prepare(
          `SELECT COUNT(*) AS c FROM family_ledger
           WHERE task_id = ? AND status != 'rejected' AND created_at >= ? AND created_at < ?`
        )
          .bind(task_id, startIso, endIso)
          .first<{ c: number }>();
        // ③ 只算没被拒的、金额为正的；pending 也占额度（否则孩子连点就能绕过）
        const gained = await env.DB.prepare(
          `SELECT SUM(amount) AS s FROM family_ledger
           WHERE task_id = ? AND status != 'rejected' AND amount > 0 AND created_at >= ? AND created_at < ?`
        )
          .bind(EXEC_TASK_ID, startIso, endIso)
          .first<{ s: number | null }>();
        if ((totalToday?.c ?? 0) >= rule.dailyLimit) {
          // ② 粗闸门
          limitMessage = `今天添加的自定义任务已经够多啦（每天最多 ${rule.dailyLimit} 个）`;
        } else if ((gained?.s ?? 0) >= CUSTOM_TASK_DAILY_CAP) {
          limitMessage = `今天的自定义任务积分已经拿满啦（每天最多 ${CUSTOM_TASK_DAILY_CAP} 分）`;
        }
      }
    } else if ((counted?.c ?? 0) >= rule.dailyLimit) {
      limitMessage =
        rule.dailyLimit === 1
          ? `「${rule.name}」今天已经打过卡啦`
          : `「${rule.name}」每天最多 ${rule.dailyLimit} 次，今天用完啦`;
    }

    if (limitMessage) {
      // 先认幂等，再拒。重试可能晚于这次上限检查：第一次其实已经写进库了，
      // 只是响应丢在路上（离线补发、老余额迁移都靠同一个 id 重发）。
      // 若直接 409，客户端会以为这条被拒而回滚已经到账的阳光，迁移也永远搬不完。
      if (providedId) {
        const existing = await env.DB.prepare('SELECT id, status FROM family_ledger WHERE id = ?')
          .bind(providedId)
          .first<{ id: string; status: string }>();
        if (existing) {
          return Response.json({ id: existing.id, status: existing.status, duplicate: true });
        }
      }
      return Response.json({ error: limitMessage }, { status: 409 });
    }
  }

  const createdAt = now.toISOString();

  const member =
    typeof body.member === 'string' && body.member.trim()
      ? body.member.trim().slice(0, MEMBER_MAX_LENGTH)
      : null;

  const noteValue = typeof note === 'string' ? note : null;
  // imageValue 上面已经清洗过（站内图片 + origin 一致），这里直接用

  // INSERT OR IGNORE：同一个 id 重发（网络重试 / 离线补发）直接命中主键，不会重复入账
  const result = member
    ? await env.DB.prepare(
        `INSERT OR IGNORE INTO family_ledger (id, task_id, task_name, type, amount, note, image_url, status, created_at, member)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
        .bind(
          id,
          task_id,
          finalName,
          finalType,
          finalAmount,
          noteValue,
          imageValue,
          finalStatus,
          createdAt,
          member
        )
        .run()
    : await env.DB.prepare(
        `INSERT OR IGNORE INTO family_ledger (id, task_id, task_name, type, amount, note, image_url, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
        .bind(
          id,
          task_id,
          finalName,
          finalType,
          finalAmount,
          noteValue,
          imageValue,
          finalStatus,
          createdAt
        )
        .run();

  if (!result.meta.changes) {
    // 主键撞上了：这条请求之前已经成功写入过（重试或离线补发），把已有记录还给调用方
    const existing = await env.DB.prepare('SELECT id, status FROM family_ledger WHERE id = ?')
      .bind(id)
      .first<{ id: string; status: string }>();
    if (existing) {
      return Response.json({ id: existing.id, status: existing.status, duplicate: true });
    }
    return Response.json({ error: '写入失败，请重试' }, { status: 500 });
  }

  // 记完账再写通知（写通知失败不影响记账）：
  //   孩子提交打卡 → 告诉家长；花园奖励即时到账，不打扰家长；
  //   家长记账 / 审批结果 → 由 PATCH /api/ledger/:id 通知孩子
  if (finalStatus === 'pending') {
    const names = await readFamilyNames(env.DB);
    await pushNotifications(env.DB, [
      {
        audience: 'parent',
        type: 'checkin_pending',
        title: `${displayName(names, 'kid')}提交了打卡`,
        body: `${finalName} ${amountText(finalType, finalAmount)}`,
        link: '/family',
        dedupeKey: `ledger:${id}:pending`,
      },
    ]);
  }

  return Response.json({ id, status: finalStatus }, { status: 201 });
};
