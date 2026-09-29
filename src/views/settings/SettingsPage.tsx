import { useState } from "react";
import {
  Card,
  Tag,
  Timeline,
  Segmented,
  Modal,
  Input,
  Form,
  Button,
  message,
  Popconfirm,
  Empty,
} from "antd";
import {
  SettingOutlined,
  InfoCircleOutlined,
  UserSwitchOutlined,
  LockOutlined,
  TeamOutlined,
  PlusOutlined,
  DeleteOutlined,
  PictureOutlined,
} from "@ant-design/icons";
import { APP_VERSION, CHANGELOG } from "../../config/changelog";
import { useFamilyStore } from "../../store/useFamilyStore";
import type { FamilyRole } from "../../store/useFamilyStore";
import { scanOrphanImages, deleteOrphanImages } from "../../api/maintenance";
import { useBackButton } from "../../utils/useBackButton";
import { designTokens } from "../../theme/tokens";
import styles from "./SettingsPage.module.css";

/** 设置页：身份切换（切家长需口令）+ 家长口令管理 + 家庭成员 + 打卡图片清理 + 应用信息与版本日志 */
export default function SettingsPage() {
  const {
    role,
    setRole,
    getParentPin,
    setParentPin,
    members,
    addMember,
    removeMember,
  } = useFamilyStore();

  // 切家长口令验证弹窗
  const [pinModalOpen, setPinModalOpen] = useState(false);
  const [pinInput, setPinInput] = useState("");

  // 修改家长口令弹窗
  const [changePinOpen, setChangePinOpen] = useState(false);
  const [oldPin, setOldPin] = useState("");
  const [newPin, setNewPin] = useState("");
  const [confirmPin, setConfirmPin] = useState("");

  // 家庭成员
  const [newMemberName, setNewMemberName] = useState("");

  // 打卡图片清理（家长）
  const [scanning, setScanning] = useState(false);
  const [cleaning, setCleaning] = useState(false);
  const [scanSummary, setScanSummary] = useState<string | null>(null);
  const [orphanCount, setOrphanCount] = useState(0);

  const isParent = role === "parent";
  // 弹窗打开时接管安卓返回键：返回键先关弹窗，而不是退出设置页
  useBackButton(pinModalOpen, () => setPinModalOpen(false));
  useBackButton(changePinOpen, () => setChangePinOpen(false));

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

  /** 添加家庭成员（多孩子家庭用；不添加则界面与单孩子时完全一致） */
  const handleAddMember = () => {
    const name = newMemberName.trim();
    if (!name) {
      message.warning("请输入成员名字");
      return;
    }
    if (members.includes(name)) {
      message.warning("已经有这个名字啦");
      return;
    }
    if (members.length >= 6) {
      message.warning("最多 6 位成员");
      return;
    }
    addMember(name);
    setNewMemberName("");
    message.success(`已添加成员「${name}」`);
  };

  /** 扫描孤儿图片（只读，不删除） */
  const handleScan = async () => {
    setScanning(true);
    try {
      const result = await scanOrphanImages();
      setOrphanCount(result.orphans);
      setScanSummary(
        result.orphans > 0
          ? `共 ${result.total} 张打卡图片，其中 ${result.referenced} 张仍被流水引用，发现 ${result.orphans} 张孤儿图片可以清理`
          : `共 ${result.total} 张打卡图片，全部仍被流水引用，没有需要清理的图片`
      );
    } catch (e) {
      message.error(e instanceof Error ? e.message : "扫描失败，请重试");
    } finally {
      setScanning(false);
    }
  };

  /** 清理孤儿图片（危险操作，二次确认后执行） */
  const handleClean = async () => {
    setCleaning(true);
    try {
      const result = await deleteOrphanImages();
      setScanSummary(
        result.failed > 0
          ? `已清理 ${result.deleted} 张孤儿图片，${result.failed} 张清理失败`
          : `已清理 ${result.deleted} 张孤儿图片`
      );
      setOrphanCount(0);
      message.success(`已清理 ${result.deleted} 张孤儿图片`);
    } catch (e) {
      message.error(e instanceof Error ? e.message : "清理失败，请重试");
    } finally {
      setCleaning(false);
    }
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
          value={role ?? undefined}
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

      {/* 家庭成员（仅家长）：不添加成员时，打卡与余额都是「全家一本账」 */}
      {isParent && (
        <Card className={styles.infoCard} variant="borderless">
          <div className={styles.infoHeader}>
            <div className={styles.infoIcon}>
              <TeamOutlined />
            </div>
            <div className={styles.infoText}>
              <div className={styles.appName}>家庭成员</div>
              <div className={styles.appDesc}>
                多个孩子时可为每人单独记账；不添加则所有记录不区分成员
              </div>
            </div>
          </div>
          <div className={styles.memberAdd}>
            <Input
              placeholder="成员名字，例如：妹妹"
              value={newMemberName}
              maxLength={20}
              onChange={(e) => setNewMemberName(e.target.value)}
              onPressEnter={handleAddMember}
            />
            <Button type="primary" icon={<PlusOutlined />} onClick={handleAddMember}>
              添加
            </Button>
          </div>
          {members.length === 0 ? (
            <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="还没有添加成员" />
          ) : (
            <div className={styles.memberList}>
              {members.map((name) => (
                <div key={name} className={styles.memberItem}>
                  <span className={styles.memberName}>{name}</span>
                  <Popconfirm
                    title={`移除成员「${name}」？`}
                    description="已有流水的成员标记会保留，仅从选择列表里移除"
                    okText="移除"
                    okButtonProps={{ danger: true }}
                    cancelText="取消"
                    onConfirm={() => {
                      removeMember(name);
                      message.success(`已移除成员「${name}」`);
                    }}
                  >
                    <Button size="small" danger icon={<DeleteOutlined />}>
                      移除
                    </Button>
                  </Popconfirm>
                </div>
              ))}
            </div>
          )}
        </Card>
      )}

      {/* 打卡图片清理（仅家长）：清理被删除流水遗留的 R2 孤儿图片 */}
      {isParent && (
        <Card className={styles.infoCard} variant="borderless">
          <div className={styles.infoHeader}>
            <div className={styles.infoIcon}>
              <PictureOutlined />
            </div>
            <div className={styles.infoText}>
              <div className={styles.appName}>打卡图片清理</div>
              <div className={styles.appDesc}>
                删除流水时图片会自动一起删除；这里清理历史遗留的孤儿图片
              </div>
            </div>
          </div>
          {scanSummary && <div className={styles.scanResult}>{scanSummary}</div>}
          <div className={styles.cleanupActions}>
            <Button icon={<PictureOutlined />} loading={scanning} onClick={handleScan}>
              扫描孤儿图片
            </Button>
            {orphanCount > 0 && (
              <Popconfirm
                title={`确认清理 ${orphanCount} 张孤儿图片？`}
                description="图片将从 R2 永久删除，且不可恢复"
                okText="清理"
                okButtonProps={{ danger: true }}
                cancelText="取消"
                onConfirm={handleClean}
              >
                <Button danger loading={cleaning} icon={<DeleteOutlined />}>
                  清理 {orphanCount} 张
                </Button>
              </Popconfirm>
            )}
          </div>
        </Card>
      )}

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
        destroyOnHidden
        style={{ top: 24 }}
      >
        <Form layout="vertical">
          <Form.Item label="请输入家长口令">
            <Input.Password
              placeholder="4-8 位口令"
              value={pinInput}
              onChange={(e) => setPinInput(e.target.value)}
              maxLength={8}
              onPressEnter={handlePinConfirm}
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
        destroyOnHidden
        style={{ top: 24 }}
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
