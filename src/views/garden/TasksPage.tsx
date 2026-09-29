import { message } from "antd";
import { CheckOutlined, SunOutlined, ClockCircleOutlined } from "@ant-design/icons";
import { useGardenStore } from "../../store/useGardenStore";
import { getGardenIcon } from "../../components/garden/GardenIcon";
import styles from "./TasksPage.module.css";

/** 每个任务图标的配色类（颜色只能用主题变量，故按强调色归类，让卡片保持生动） */
const TASK_ICON_CLASS: Record<string, string> = {
  poem: styles.taskIconBrand,
  chinese: styles.taskIconPrimary,
  math: styles.taskIconWarm,
  reading: styles.taskIconSuccess,
  writing: styles.taskIconDanger,
  eyes: styles.taskIconPrimary,
  sport: styles.taskIconWarm,
  chore: styles.taskIconBrand,
};

/** 今日任务页面 */
export default function TasksPage() {
  const { tasks, completedCount, streakDays, completeTask } = useGardenStore();

  const total = tasks.length;
  const percent = total > 0 ? Math.round((completedCount / total) * 100) : 0;

  const handleComplete = (taskId: string, name: string, reward: number) => {
    completeTask(taskId);
    // store 会挡下「今天已经做过」的重复打卡（含连点两次），这时不能再报喜 ——
    // 否则孩子以为又赚了一份阳光，刷新后数字却没变，比不报还糟
    const done = useGardenStore.getState().tasks.some((task) => task.id === taskId && task.done);
    if (!done) {
      message.info(`「${name}」今天已经完成过啦`);
      return;
    }
    message.success(`+${reward} 阳光！${name}完成啦`);
  };

  return (
    <div className={styles.tasks}>
      {/* 顶部统计 */}
      <div className={styles.stats}>
        <div className={styles.statCard}>
          <div className={`${styles.statIcon} ${styles.statIconWarm}`}>
            <CheckOutlined />
          </div>
          <div className={styles.statInfo}>
            <div className={styles.statLabel}>今日完成</div>
            <div className={`num ${styles.statValue}`}>{completedCount}</div>
            <div className={styles.statSub}>个任务</div>
          </div>
        </div>
        <div className={styles.statCard}>
          <div className={`${styles.statIcon} ${styles.statIconSuccess}`}>
            <SunOutlined />
          </div>
          <div className={styles.statInfo}>
            <div className={styles.statLabel}>完成率</div>
            <div className={`num ${styles.statValue}`}>{percent}%</div>
            <div className={styles.statBar}>
              <div className={styles.statBarFill} style={{ width: `${percent}%` }} />
            </div>
          </div>
        </div>
        <div className={styles.statCard}>
          <div className={`${styles.statIcon} ${styles.statIconBrand}`}>
            <ClockCircleOutlined />
          </div>
          <div className={styles.statInfo}>
            <div className={styles.statLabel}>连续学习</div>
            <div className={`num ${styles.statValue}`}>{streakDays}</div>
            <div className={styles.statSub}>天</div>
          </div>
        </div>
      </div>

      {/* 任务列表 */}
      <div className={styles.taskList}>
        {tasks.map((task) => {
          const iconClass = TASK_ICON_CLASS[task.id] ?? styles.taskIconPrimary;
          return (
            <div key={task.id} className={`${styles.taskCard} ${task.done ? styles.taskCardDone : ""}`}>
              <button className={`${styles.taskCheck} ${task.done ? styles.taskCheckDone : ""}`} onClick={() => handleComplete(task.id, task.name, task.reward)} disabled={task.done}>
                {task.done && <CheckOutlined />}
              </button>

              <div className={`${styles.taskIcon} ${task.done ? styles.taskIconDone : iconClass}`}>
                {getGardenIcon(task.icon)}
              </div>

              <div className={styles.taskInfo}>
                <div className={styles.taskName}>{task.name}</div>
                <div className={styles.taskDesc}>{task.description}</div>
                <div className={styles.taskMeta}>
                  <span className={styles.taskDuration}>
                    <ClockCircleOutlined /> {task.duration} 分钟
                  </span>
                </div>
              </div>

              <div className={`${styles.taskReward} ${task.done ? styles.taskRewardDone : ""}`}>
                <SunOutlined className={styles.taskRewardIcon} />
                <span className={`num ${styles.taskRewardNum}`}>+{task.reward}</span>
                <span className={styles.taskRewardLabel}>阳光</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
