import { useState } from "react";
import { Card, Tag, Timeline, Segmented, Modal, Input, Form, Button, message } from "antd";
import {
  SettingOutlined,
  InfoCircleOutlined,
  UserSwitchOutlined,
  LockOutlined,
} from "@ant-design/icons";
import { APP_VERSION, CHANGELOG } from "../../config/changelog";
import { useFamilyStore } from "../../store/useFamilyStore";
import type { FamilyRole } from "../../store/useFamilyStore";
import { designTokens } from "../../theme/tokens";
import styles from "./SettingsPage.module.css";

/** 设置页：身份切换（切家长需口令验证）+ 家长口令管理 + 应用信息 + 版本日志 */
export default function SettingsPage() {
  const { role, setRole, getParentPin, setParentPin } = useFamilyStore();

  // 切家长口令验证弹窗
  const [pinModalOpen, setPinModalOpen] = useState(false);
  const [pinInput, setPinInput] = useState("");

  // 修改家长口令弹窗
  const [changePinOpen, setChangePinOpen] = useState(false);
  const [oldPin, setOldPin] = useState("");
  const [newPin, setNewPin] = useState("");
  const [confirmPin, setConfirmPin] = useState("");

  /** 身份切换：切到家长需验证口令，切到小孩直接切换 */
  const handleRoleChange = (value: string | number) => {
    const next = value as FamilyRole;
    if (next === "parent" && role === "child") {
      setPinInput("");
      setPinModalOpen(true);
      return;
    }
    setRole(next);
  };

  /** 验证口令并切换为家长 */
  const handlePinConfirm = () => {
    if (pinInput === getParentPin()) {
      setRole("parent");
      setPinModalOpen(false);
      message.success("已切换为家长");
    } else {
      message.error("口令错误");
    }
  };

  /** 修改家长口令 */
  const handleChangePin = () => {
    if (oldPin !== getParentPin()) {
      message.error("原口令错误");
      return;
    }
    if (newPin.length < 4 || newPin.length > 8) {
      message.error("新口令需为 4-8 位");
      return;
    }
    if (newPin !== confirmPin) {
      message.error("两次输入的新口令不一致");
      return;
    }
    setParentPin(newPin);
    setChangePinOpen(false);
    setOldPin("");
    setNewPin("");
    setConfirmPin("");
    message.success("家长口令已更新");
  };

  return (
    <div className={styles.settings}>
      {/* 当前身份切换 */}
      <Card className={styles.infoCard} variant="borderless">
        <div className={styles.infoHeader}>
          <div className={styles.infoIcon}>
            <UserSwitchOutlined />
          </div>
          <div className={styles.infoText}>
            <div className={styles.appName}>当前身份</div>
            <div className={styles.appDesc}>
              {role === "parent" ? "家长：可审批小孩的打卡申请" : "小孩：打卡后需家长审批"}
            </div>
          </div>
        </div>
        <Segmented
          block
          value={role}
          onChange={handleRoleChange}
          options={[
            { label: "家长", value: "parent" },
            { label: "小孩", value: "child" },
          ]}
          className={styles.roleSwitch}
        />
        <div className={styles.roleHint}>
          {role === "parent"
            ? "切回小孩无需口令，随时可切"
            : "切换为家长需输入家长口令"}
        </div>
        {role === "parent" && (
          <Button
            block
            className={styles.changePinBtn}
            icon={<LockOutlined />}
            onClick={() => {
              setOldPin("");
              setNewPin("");
              setConfirmPin("");
              setChangePinOpen(true);
            }}
          >
            修改家长口令
          </Button>
        )}
      </Card>

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

      {/* 切换为家长：口令验证弹窗 */}
      <Modal
        title="切换为家长"
        open={pinModalOpen}
        onOk={handlePinConfirm}
        onCancel={() => setPinModalOpen(false)}
        okText="确认"
        cancelText="取消"
        destroyOnClose
      >
        <Form layout="vertical">
          <Form.Item label="请输入家长口令">
            <Input.Password
              placeholder="4-8 位口令"
              value={pinInput}
              onChange={(e) => setPinInput(e.target.value)}
              maxLength={8}
              onPressEnter={handlePinConfirm}
              autoFocus
            />
          </Form.Item>
        </Form>
        <div className={styles.pinHint}>口令不正确将无法切换到家长模式</div>
      </Modal>

      {/* 修改家长口令弹窗 */}
      <Modal
        title="修改家长口令"
        open={changePinOpen}
        onOk={handleChangePin}
        onCancel={() => setChangePinOpen(false)}
        okText="保存"
        cancelText="取消"
        destroyOnClose
      >
        <Form layout="vertical">
          <Form.Item label="原口令">
            <Input.Password
              placeholder="请输入原口令"
              value={oldPin}
              onChange={(e) => setOldPin(e.target.value)}
              maxLength={8}
            />
          </Form.Item>
          <Form.Item label="新口令">
            <Input.Password
              placeholder="4-8 位新口令"
              value={newPin}
              onChange={(e) => setNewPin(e.target.value)}
              maxLength={8}
            />
          </Form.Item>
          <Form.Item label="确认新口令">
            <Input.Password
              placeholder="再次输入新口令"
              value={confirmPin}
              onChange={(e) => setConfirmPin(e.target.value)}
              maxLength={8}
              onPressEnter={handleChangePin}
            />
          </Form.Item>
        </Form>
        <div className={styles.pinHint}>出厂口令为 1234，请尽快修改</div>
      </Modal>
    </div>
  );
}
