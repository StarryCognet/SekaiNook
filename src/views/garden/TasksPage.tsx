import { message } from "antd";
import { CheckOutlined, SunOutlined, ClockCircleOutlined } from "@ant-design/icons";
import { useGardenStore } from "../../store/useGardenStore";
import { getGardenIcon } from "../../components/garden/GardenIcon";
import { gardenTokens } from "../../theme/gardenTokens";
import styles from "./TasksPage.module.css";

/** 每个任务的图标主题色（让卡片更生动） */
const TASK_COLORS: Record<string, { bg: string; color: string }> = {
  poem: { bg: "#F3EDFF", color: "#B791FA" },
  chinese: { bg: "#E8F4FF", color: "#4A9DE0" },
  math: { bg: "#FFF3E0", color: "#F5A623" },
  reading: { bg: "#E8F8E8", color: "#52C41A" },
  writing: { bg: "#FFE9F0", color: "#E94560" },
  eyes: { bg: "#E6F7FF", color: "#13C2C2" },
  sport: { bg: "#FFF7E0", color: "#FFC53D" },
  chore: { bg: "#F0F0FF", color: "#7B61FF" },
};

/** 今日任务页面 */
export default function TasksPage() {
  const { tasks, completedCount, streakDays, completeTask } = useGardenStore();

  const total = tasks.length;
  const percent = total > 0 ? Math.round((completedCount / total) * 100) : 0;

  const handleComplete = (taskId: string, name: string, reward: number) => {
    completeTask(taskId);
    message.success(`+${reward} 阳光！${name}完成啦`);
  };

  return (
    <div className={styles.tasks}>
      {/* 顶部统计 */}
      <div className={styles.stats}>
        <div className={styles.statCard}>
          <div className={styles.statIcon} style={{ background: "#FFF7E0", color: "#FFC53D" }}>
            <CheckOutlined />
          </div>
          <div className={styles.statInfo}>
            <div className={styles.statLabel}>今日完成</div>
            <div className={`num ${styles.statValue}`}>{completedCount}</div>
            <div className={styles.statSub}>个任务</div>
          </div>
        </div>
        <div className={styles.statCard}>
          <div className={styles.statIcon} style={{ background: "#E8F8E8", color: "#52C41A" }}>
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
          <div className={styles.statIcon} style={{ background: "#F3EDFF", color: "#B791FA" }}>
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
          const color = TASK_COLORS[task.id] ?? { bg: "#F3EDFF", color: "#B791FA" };
          return (
            <div key={task.id} className={`${styles.taskCard} ${task.done ? styles.taskCardDone : ""}`}>
              <button className={`${styles.taskCheck} ${task.done ? styles.taskCheckDone : ""}`} onClick={() => handleComplete(task.id, task.name, task.reward)} disabled={task.done}>
                {task.done && <CheckOutlined />}
              </button>

              <div
                className={styles.taskIcon}
                style={{
                  background: task.done ? "rgba(82,196,26,0.12)" : color.bg,
                  color: task.done ? gardenTokens.colors.success : color.color,
                }}
              >
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
                <SunOutlined style={{ color: gardenTokens.colors.sun }} />
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
