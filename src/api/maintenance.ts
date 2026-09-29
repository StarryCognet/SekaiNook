/**
 * 维护类接口客户端：闲置照片扫描与清理。
 *
 * 界面上叫「闲置照片」（删除记录后留在云端的照片）；
 * 代码与接口路径沿用 orphan（未被任何流水引用）这个叫法。
 * 统一通过 ./http 访问 /api/maintenance/*，不要直接 fetch。
 */

import { http } from './http';

/** 闲置照片扫描结果（GET /api/maintenance/orphans；orphans 字段 = 无人引用的照片数） */
export interface OrphanScanResult {
  /** R2 中 tasks/ 前缀下的对象总数 */
  total: number;
  /** 其中被 family_ledger.image_url 引用到的对象数 */
  referenced: number;
  /** 无人引用的闲置照片数 */
  orphans: number;
  /** 闲置照片 key 列表（最多返回前 200 个） */
  keys: string[];
}

/** 闲置照片清理结果（POST /api/maintenance/orphans） */
export interface OrphanCleanResult {
  /** 成功删除的对象数 */
  deleted: number;
  /** 删除失败的对象数 */
  failed: number;
  /** 已删除的对象 key 列表（最多返回前 200 个） */
  keys: string[];
}

/** 扫描闲置照片（只读 dry run，不会删除任何对象） */
export function scanOrphanImages(): Promise<OrphanScanResult> {
  return http.get<OrphanScanResult>('/api/maintenance/orphans');
}

/** 清理闲置照片（危险操作，后端要求 confirm: true 才执行） */
export function deleteOrphanImages(): Promise<OrphanCleanResult> {
  return http.post<OrphanCleanResult>('/api/maintenance/orphans', { confirm: true });
}
