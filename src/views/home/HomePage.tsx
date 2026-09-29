import { useFamilyStore } from '../../store/useFamilyStore';
import KidHome from './KidHome';
import ParentHome from './ParentHome';

/**
 * 首页（第 1 个 Tab）。
 *
 * 同一台设备上只有一个人在用（妹妹的手机 / 妈妈的手机），所以这里按身份分流到
 * 两套完全不同的界面 —— 妹妹要的是「今天做什么」，妈妈要的是「有什么要我处理」，
 * 拼成一套反而两边都别扭。
 */
export default function HomePage() {
  const role = useFamilyStore((s) => s.role);
  return role === 'parent' ? <ParentHome /> : <KidHome />;
}
