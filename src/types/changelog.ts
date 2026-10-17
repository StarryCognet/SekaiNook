/**
 * 版本日志的共享类型。
 *
 * 为什么放 types/ 而不是留在 config/changelog.ts：
 * 它是「`GET /api/changelog` 返回什么形状」的契约，服务端读取工具
 * （functions/_lib/changelog.ts，自己声明了一份等价的）、接口层、设置页三处对齐；
 * 数据本身（那份兜底用的 CHANGELOG 数组）留在 config/ 里，类型归口到 types/。
 *
 * config/changelog.ts 仍然 re-export 这个类型，历史 import 不用改。
 */
export interface ChangelogEntry {
  /** 版本号，例如 '1.31.0' */
  version: string;
  /** 展示用的时间串，例如 '2026-10-17 22:40:00'（原样展示，不做时区换算） */
  date: string;
  /** 这一版的一句话主题 */
  title: string;
  /** 改动条目 */
  changes: string[];
}
