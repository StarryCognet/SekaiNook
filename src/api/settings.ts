/**
 * 家庭设置接口（跨设备同步的那一份）。
 * 路由：GET /api/settings（读）、PATCH /api/settings（改）
 *
 * 目前两类设置共用这张 settings 表：
 *   - names：家庭称呼（女儿怎么叫妈妈、妈妈怎么叫女儿）
 *   - background：全局背景图的图片地址（空字符串 = 没设）
 */

import { http } from './http';
import type { FamilyNames } from '../types/settings';

export interface SettingsResponse {
  names: FamilyNames;
  /** 全局背景图地址，'' = 没设 */
  background: string;
  /** false = 服务端 settings 表还没迁移，用的是默认值 */
  ready?: boolean;
}

/** 只提交要改的字段：称呼各改各的那一半，背景图单独改 */
export type SettingsPatch = Partial<FamilyNames> & { background?: string };

/** 读取家庭设置 */
export function fetchSettings(): Promise<SettingsResponse> {
  return http.get<SettingsResponse>('/api/settings');
}

/** 保存部分设置，返回保存后的完整设置 */
export function saveSettings(patch: SettingsPatch): Promise<SettingsResponse> {
  return http.patch<SettingsResponse>('/api/settings', patch);
}
