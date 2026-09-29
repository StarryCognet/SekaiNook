/**
 * 维护类接口客户端：孤儿图片扫描与清理。
 *
 * 统一通过 ./http 访问 /api/maintenance/*，不要直接 fetch。
 */

import { http } from './http';

/** 孤儿图片扫描结果（GET /api/maintenance/orphans） */
export interface OrphanScanResult {
  /** R2 中 tasks/ 前缀下的对象总数 */
  total: number;
  /** 其中被 family_ledger.image_url 引用到的对象数 */
  referenced: number;
  /** 无引用的孤儿对象数 */
  orphans: number;
  /** 孤儿对象 key 列表（最多返回前 200 个） */
  keys: string[];
}

/** 孤儿图片清理结果（POST /api/maintenance/orphans） */
export interface OrphanCleanResult {
  /** 成功删除的对象数 */
  deleted: number;
  /** 删除失败的对象数 */
  failed: number;
  /** 已删除的对象 key 列表（最多返回前 200 个） */
  keys: string[];
}

/** 扫描 R2 中的孤儿图片（只读 dry run，不会删除任何对象） */
export function scanOrphanImages(): Promise<OrphanScanResult> {
  return http.get<OrphanScanResult>('/api/maintenance/orphans');
}

/** 删除 R2 中的孤儿图片（危险操作，后端要求 confirm: true 才执行） */
export function deleteOrphanImages(): Promise<OrphanCleanResult> {
  return http.post<OrphanCleanResult>('/api/maintenance/orphans', { confirm: true });
}
