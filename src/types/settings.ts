/**
 * 家庭称呼（跨设备同步的设置，存在 D1 的 settings 表里）。
 *
 * 视角约定：
 *   - 妈妈的界面里，另一个人是「女儿」→ kidCall / kidNickname
 *   - 妹妹的界面里，另一个人是「妈妈」→ momCall / momNickname；她自己一律是「我」
 *   - 妈妈的身份由女儿设置，女儿的身份由妈妈设置（各改各的那一半）
 *
 * 显示规则：昵称优先，没填昵称才用称呼（界面上统一走 displayName）。
 */

export interface FamilyNames {
  /** 女儿对妈妈的称呼，例如「妈妈」 */
  momCall: string;
  /** 女儿给妈妈起的昵称，例如「老妈」（填了就优先显示） */
  momNickname: string;
  /** 妈妈对女儿的称呼，例如「女儿」 */
  kidCall: string;
  /** 妈妈给女儿起的昵称，例如「妹妹」（填了就优先显示） */
  kidNickname: string;
}

export type FamilyNamesKey = keyof FamilyNames;

export const FAMILY_NAME_KEYS: readonly FamilyNamesKey[] = [
  'momCall',
  'momNickname',
  'kidCall',
  'kidNickname',
];

export const DEFAULT_FAMILY_NAMES: FamilyNames = {
  momCall: '妈妈',
  momNickname: '',
  kidCall: '女儿',
  kidNickname: '',
};

/** 一个称呼最多几个字（界面与接口同一口径） */
export const MAX_NAME_LENGTH = 12;

/** 界面上统一用它取名字：昵称优先，没填昵称才用称呼 */
export function displayName(names: FamilyNames, who: 'mom' | 'kid'): string {
  const fallback = who === 'mom' ? DEFAULT_FAMILY_NAMES.momCall : DEFAULT_FAMILY_NAMES.kidCall;
  const call = who === 'mom' ? names.momCall : names.kidCall;
  const nickname = who === 'mom' ? names.momNickname : names.kidNickname;
  return (nickname || call || fallback).trim() || fallback;
}

/** 表单校验：超长返回中文提示，合法返回 null */
export function validateName(value: string): string | null {
  return value.trim().length > MAX_NAME_LENGTH ? `最多 ${MAX_NAME_LENGTH} 个字` : null;
}
