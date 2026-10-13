/**
 * 管理员后台接口（改积分数）。
 *
 * 密码校验在服务端：这个接口能改账本余额，如果只在前端拦一道，
 * 任何人直接 POST /api/admin 就能改。所以每个动作都把密码一起带上。
 *
 * 写请求不带 retry（http.ts 里写请求默认不重试）：调整是按差额算的，
 * 不会写着写着变两条，但也没必要让弱网重试去碰余额。
 */

import { http } from './http';

/** 管理员面板的当前状态（进门时、改完之后都回这一份） */
export interface AdminPanelState {
  /** 家庭积分余额 */
  family: number;
  /** 花园阳光余额 */
  sun: number;
  /** 本次是不是改了密码 */
  passwordChanged?: boolean;
  /** 本次改动的摘要，例如 ["家庭积分 20 → 500"] */
  changed?: string[];
}

/** 校验密码并把当前余额带回来（进管理员面板第一步） */
export function openAdminPanel(password: string): Promise<AdminPanelState> {
  return http.post<AdminPanelState>('/api/admin', { action: 'verify', password });
}

/** 把积分直接改成目标值：只传要改的那一个，另一个不动 */
export function adjustLedgerPoints(params: {
  password: string;
  family?: number;
  sun?: number;
}): Promise<AdminPanelState> {
  return http.post<AdminPanelState>('/api/admin', { action: 'adjust', ...params });
}

/** 改管理员密码（出厂密码见 functions/_lib/settings.ts 的 DEFAULT_ADMIN_PASSWORD） */
export function changeAdminPassword(params: {
  password: string;
  newPassword: string;
}): Promise<AdminPanelState> {
  return http.post<AdminPanelState>('/api/admin', { action: 'password', ...params });
}
