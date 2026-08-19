import { Card, List, Tag } from 'antd';
import { CheckCircleOutlined, SunOutlined } from '@ant-design/icons';
import { useGardenStore } from '../../store/useGardenStore';
import { gardenTokens } from '../../theme/gardenTokens';
import styles from './RecordsPage.module.css';

/** 学习记录页面 */
export default function RecordsPage() {
  const { tasks, completedCount } = useGardenStore();
  const doneTasks = tasks.filter((t) => t.done);

  return (
    <div className={styles.records}>
      <div className={styles.sectionTitle}>学习记录</div>

      {/* 今日完成概览 */}
      <Card className={styles.summaryCard} variant="borderless">
        <div className={styles.summaryItem}>
          <div className={styles.summaryLabel}>今日完成</div>
          <div className={`num ${styles.summaryValue}`}>{completedCount}</div>
          <div className={styles.summarySub}>个任务</div>
        </div>
        <div className={styles.summaryItem}>
          <div className={styles.summaryLabel}>获得阳光</div>
          <div className={`num ${styles.summaryValue}`}>
            {doneTasks.reduce((sum, t) => sum + t.reward, 0)}
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
                  avatar={
                    <CheckCircleOutlined
                      style={{ color: gardenTokens.colors.success, fontSize: 20 }}
                    />
                  }
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
                <Tag color="gold" icon={<SunOutlined />}>
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