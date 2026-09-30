import { Card, List, Tag } from 'antd';
import { CheckCircleOutlined, SunOutlined } from '@ant-design/icons';
import { todayKey, useGardenStore } from '../../store/useGardenStore';
import styles from './RecordsPage.module.css';

/** 学习记录页面 */
export default function RecordsPage() {
  const { tasks, completedCount, todayEarned, todayEarnedDate } = useGardenStore();
  const doneTasks = tasks.filter((t) => t.done);
  // 「今日完成」是任务数口径：completedCount 由 store 从 tasks 派生，最多等于任务总数，
  // 所以按「已完成 / 任务总数」展示。背诗、语文练习也会点亮对应的那两个任务，
  // 但一天背三首诗只算一个任务 —— 多出来的入账只体现在上面的「获得阳光」里。
  // 「获得阳光」按今天实际入账的奖励求和：背诗、语文练习都可能一天入账多次
  // （任务本身只记一次奖励），以前按任务固定奖励求和会和真实到手的对不上。
  // 商城兑换只扣余额、不动 todayEarned，所以「赚到的」与「花掉的」不会互相污染。
  // 存档里的日期不是今天（跨天还没重置）时一律按 0 算。
  const earnedToday = todayEarnedDate === todayKey() ? todayEarned : 0;

  return (
    <div className={styles.records}>
      <div className={styles.sectionTitle}>学习记录</div>

      {/* 今日完成概览 */}
      <Card className={styles.summaryCard} variant="borderless">
        <div className={styles.summaryItem}>
          <div className={styles.summaryLabel}>今日完成</div>
          <div className={`num ${styles.summaryValue}`}>
            {completedCount}/{tasks.length}
          </div>
          <div className={styles.summarySub}>个任务</div>
        </div>
        <div className={styles.summaryItem}>
          <div className={styles.summaryLabel}>获得阳光</div>
          <div className={`num ${styles.summaryValue} ${styles.summaryValueWarm}`}>
            {earnedToday}
          </div>
          <div className={styles.summarySub}>积分</div>
        </div>
      </Card>

      {/* 已完成任务列表 */}
      <Card className={styles.recordList} variant="borderless" title="今日已完成">
        {doneTasks.length === 0 ? (
          <div className={styles.empty}>今天还没有完成任务，快去加油吧！</div>
        ) : (
          <List
            dataSource={doneTasks}
            renderItem={(task) => (
              <List.Item>
                <List.Item.Meta
                  avatar={<CheckCircleOutlined className={styles.doneIcon} />}
                  title={task.name}
                  description={
                    task.completedAt
                      ? new Date(task.completedAt).toLocaleTimeString('zh-CN', {
                          hour: '2-digit',
                          minute: '2-digit',
                        })
                      : ''
                  }
                />
                <Tag className={styles.rewardTag} icon={<SunOutlined />}>
                  +{task.reward}
                </Tag>
              </List.Item>
            )}
          />
        )}
      </Card>
    </div>
  );
}
