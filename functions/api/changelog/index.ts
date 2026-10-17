/**
 * 版本日志接口。
 * 路由：GET /api/changelog —— 读全部版本记录（表没迁移 / 还没播种时 ready:false）
 *
 * 响应：{ version, entries, ready }
 *   version —— 最新一条的版本号，没有内容时为 null
 *   entries —— 最新在前：[{ version, date, title, changes }]
 *   ready   —— entries 是否能用（= 非空）。**false 时客户端要退回自己 bundle 里那份**
 *              （Web: src/config/changelog.ts；Flutter: lib/config/changelog.dart），
 *              所以这里永远回 200，不用 4xx/5xx 去逼客户端处理错误分支。
 *
 * 为什么不鉴权、为什么不加写接口：
 *   * 版本日志本来就是给全家看的公开信息，和 /api/settings 一样是只读 GET；
 *   * 仓库铁律「不引入鉴权中间件」，所以也不为了「谁都能改日志」开一个带口令的写接口 ——
 *     内容的唯一入口是代码仓库里的 src/config/changelog.ts，用 npm run changelog:sync 推上来。
 */

import { readChangelog } from '../../_lib/changelog';

interface Env {
  DB: D1Database;
}

export const onRequestGet: PagesFunction<Env> = async ({ env }) => {
  try {
    const snapshot = await readChangelog(env.DB);
    return Response.json({
      version: snapshot.version,
      entries: snapshot.entries,
      ready: snapshot.entries.length > 0,
    });
  } catch (error) {
    // 常见原因：远端/本地库还没跑 0006 迁移，或者还没执行过 npm run changelog:sync
    console.error('get changelog failed', error);
    return Response.json({ version: null, entries: [], ready: false });
  }
};
