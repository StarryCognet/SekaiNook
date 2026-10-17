/**
 * 版本日志接口。
 *
 * 日志的真源在 D1（changelog 表）：网页版和 Flutter 版都读它，改一处两端都看得见 ——
 * 以前两端各存一份代码常量，改一边另一边不跟着变。代码里那份 CHANGELOG 现在的身份是
 * **播种数据 + 兜底**：接口不可用（表没迁移 / 还没同步）时退回它，页面不会开天窗。
 *
 * 接口永远回 200，用 ready 区分「这份数据能不能用」，所以调用方只需要看图省事的分支：
 *   ready === true  → 用 entries
 *   ready === false → 用本地那份兜底（此时 entries 一定是空数组）
 */
import { http } from './http';
import type { ChangelogEntry } from '../types/changelog';

/** `GET /api/changelog` 的返回（与 functions/api/changelog/index.ts 对齐） */
export interface ChangelogResponse {
  /** 最新一条的版本号；没有内容时为 null */
  version: string | null;
  /** 最新在前 */
  entries: ChangelogEntry[];
  /** entries 能不能用（= 非空） */
  ready: boolean;
}

/** 拉取版本日志。失败会抛 ApiError，调用方吞掉并退回 bundle 里那份 */
export function fetchChangelog(): Promise<ChangelogResponse> {
  return http.get<ChangelogResponse>('/api/changelog');
}
