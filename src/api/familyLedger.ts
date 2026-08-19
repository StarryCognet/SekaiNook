import { supabase } from './supabaseClient';
import type { LedgerRecord, TaskConfig } from '../types/family';

/** 查询所有积分流水，按 created_at 倒序 */
export async function fetchLedgerRecords(): Promise<LedgerRecord[]> {
  const { data, error } = await supabase
    .from('family_ledger')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data ?? []) as LedgerRecord[];
}

/** 插入一条积分流水，amount 取 task.value */
export async function addLedgerRecord(task: TaskConfig): Promise<boolean> {
  const { error } = await supabase.from('family_ledger').insert({
    task_id: task.id,
    task_name: task.name,
    type: task.type,
    amount: task.value,
  });
  if (error) throw error;
  return true;
}

/** 计算当前总积分（所有 amount 之和） */
export async function getBalance(): Promise<number> {
  const { data, error } = await supabase.from('family_ledger').select('amount');
  if (error) throw error;
  const rows = (data ?? []) as Array<{ amount: number }>;
  return rows.reduce((sum, r) => sum + (r.amount ?? 0), 0);
}