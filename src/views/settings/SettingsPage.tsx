import { Card, Tag, Timeline } from 'antd';
import { SettingOutlined, InfoCircleOutlined } from '@ant-design/icons';
import { APP_VERSION, CHANGELOG } from '../../config/changelog';
import { designTokens } from '../../theme/tokens';
import styles from './SettingsPage.module.css';

/** 设置页：应用信息 + 版本日志 */
export default function SettingsPage() {
  return (
    <div className={styles.settings}>
      {/* 应用信息 */}
      <Card className={styles.infoCard} variant="borderless">
        <div className={styles.infoHeader}>
          <div className={styles.infoIcon}>
            <SettingOutlined />
          </div>
          <div className={styles.infoText}>
            <div className={styles.appName}>SekaiNook</div>
            <div className={styles.appDesc}>家庭财务与行为管理</div>
          </div>
        </div>
        <div className={styles.versionRow}>
          <span className={styles.versionLabel}>
            <InfoCircleOutlined /> 当前版本
          </span>
          <Tag color="processing" className={styles.versionTag}>
            v{APP_VERSION}
          </Tag>
        </div>
      </Card>

      {/* 版本日志 */}
      <Card
        className={styles.logCard}
        variant="borderless"
        title={
          <span className={styles.logTitle}>
            <InfoCircleOutlined /> 版本日志
          </span>
        }
      >
        <Timeline
          items={CHANGELOG.map((entry) => ({
            color: designTokens.colors.primary,
            children: (
              <div className={styles.logEntry}>
                <div className={styles.logHeader}>
                  <span className={styles.logVersion}>v{entry.version}</span>
                  <span className={styles.logDate}>{entry.date}</span>
                </div>
                <div className={styles.logTitleText}>{entry.title}</div>
                <ul className={styles.logChanges}>
                  {entry.changes.map((change, i) => (
                    <li key={i}>{change}</li>
                  ))}
                </ul>
              </div>
            ),
          }))}
        />
      </Card>
    </div>
  );
}
