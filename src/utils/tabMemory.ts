/**
 * Tab 记忆：让每个 Tab 拥有自己的「栈」。
 *
 * 浏览器里每建一个导航项就是一个路由，切换即卸载页面，天然会把滚动位置和
 * 界面状态丢掉；而 iOS 的 tab bar 语义是「每个 Tab 保留自己的导航栈」——
 * 切走再切回来要回到原处，再点一次当前 Tab 才回到根页/顶部。
 *
 * 这里用两本账实现：
 *   1. 路径记忆：每个 Tab 最后停在哪个路径（点 Tab 时优先回那里）
 *   2. 滚动记忆：每个路径的滚动位置（按路径分开存，子页面也各记各的）
 *
 * 存 sessionStorage：同一标签页会话内有效（等于「App 还开着」），
 * 关掉标签页就清空。移动端浏览器在内存紧张时会整个刷新页面，
 * 存一份能顺带把位置也恢复回来。
 */

/** 四个 Tab 的根路径；按最长前缀匹配，所以 /family/plan 会命中「学习计划」而不是「家庭工作台」 */
const TAB_ROOTS = ['/family/plan', '/family', '/garden', '/settings'];

const TAB_PATH_KEY = 'sekainook_tab_paths_v1';
const SCROLL_KEY = 'sekainook_scroll_v1';

/** 读取一份 JSON 表单（损坏就当没有，绝不因此崩掉导航） */
function readMap(key: string): Record<string, string | number> {
  try {
    const raw = sessionStorage.getItem(key);
    if (!raw) return {};
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
    return parsed as Record<string, string | number>;
  } catch {
    return {};
  }
}

function writeMap(key: string, value: Record<string, string | number>): void {
  try {
    sessionStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* 隐私模式下 sessionStorage 可能直接抛错，忽略即可 */
  }
}

/** 路径属于哪个 Tab（找不到兜底回「家庭工作台」） */
export function resolveTabRoot(pathname: string): string {
  let matched = '';
  for (const root of TAB_ROOTS) {
    const hit = pathname === root || pathname.startsWith(`${root}/`);
    if (hit && root.length > matched.length) matched = root;
  }
  return matched || '/family';
}

/** 记住某个 Tab 最后停留的路径 */
export function rememberTabPath(pathname: string): void {
  // 根路径只做重定向，记下来没意义
  if (pathname === '/') return;
  const map = readMap(TAB_PATH_KEY);
  const root = resolveTabRoot(pathname);
  if (map[root] === pathname) return;
  map[root] = pathname;
  writeMap(TAB_PATH_KEY, map);
}

/** 取某个 Tab 上次停留的路径（没记录返回 null，交给调用方用根路径兜底） */
export function getTabPath(tabRoot: string): string | null {
  const value = readMap(TAB_PATH_KEY)[tabRoot];
  if (typeof value !== 'string' || !value.startsWith('/')) return null;
  // 记忆可能是旧版本留下的：路径必须真的属于这个 Tab，否则宁可回根路径
  return resolveTabRoot(value) === tabRoot ? value : null;
}

/** 记住某个路径的滚动位置 */
export function rememberScroll(pathname: string, top: number): void {
  const map = readMap(SCROLL_KEY);
  const rounded = Math.max(0, Math.round(top));
  if (map[pathname] === rounded) return;
  map[pathname] = rounded;
  writeMap(SCROLL_KEY, map);
}

/** 取某个路径上次的滚动位置（没有返回 0） */
export function getScroll(pathname: string): number {
  const value = readMap(SCROLL_KEY)[pathname];
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0;
}
