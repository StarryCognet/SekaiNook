/**
 * 家庭称呼设置接口。
 * 路由：GET /api/settings（读）、PATCH /api/settings（改自己那一半）
 */

import { http } from './http';
import type { FamilyNames } from '../types/settings';

interface SettingsResponse {
  names: FamilyNames;
  /** false = 服务端 settings 表还没迁移，用的是默认称呼 */
  ready?: boolean;
}

/** 读取家庭称呼（女儿怎么叫妈妈、妈妈怎么叫女儿） */
export function fetchFamilyNames(): Promise<SettingsResponse> {
  return http.get<SettingsResponse>('/api/settings');
}

/** 保存部分称呼，返回保存后的完整称呼 */
export async function saveFamilyNames(patch: Partial<FamilyNames>): Promise<SettingsResponse> {
  const result = await http.patch<SettingsResponse>('/api/settings', patch);
  return result;
}
