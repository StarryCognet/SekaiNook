import { useEffect, useState } from "react";
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
} from "antd";
import {
  SettingOutlined,
  InfoCircleOutlined,
  UserSwitchOutlined,
  LockOutlined,
  DeleteOutlined,
  PictureOutlined,
  SmileOutlined,
} from "@ant-design/icons";
import { APP_VERSION, CHANGELOG } from "../../config/changelog";
import { useFamilyStore } from "../../store/useFamilyStore";
import type { FamilyRole } from "../../store/useFamilyStore";
import { useSettingsStore } from "../../store/useSettingsStore";
import {
  DEFAULT_FAMILY_NAMES,
  MAX_NAME_LENGTH,
  displayName,
  validateName,
} from "../../types/settings";
import { scanOrphanImages, deleteOrphanImages } from "../../api/maintenance";
import { useBackButton } from "../../utils/useBackButton";
import { designTokens } from "../../theme/tokens";
import styles from "./SettingsPage.module.css";

/** 设置页：身份切换（切家长需口令）+ 家长口令管理 + 家庭称呼 + 打卡图片清理 + 应用信息与版本日志 */
export default function SettingsPage() {
  const { role, setRole, getParentPin, setParentPin } = useFamilyStore();
  const { names, ready: namesReady, save: saveNames } = useSettingsStore();

  // 切家长口令验证弹窗
  const [pinModalOpen, setPinModalOpen] = useState(false);
  const [pinInput, setPinInput] = useState("");

  // 修改家长口令弹窗
  const [changePinOpen, setChangePinOpen] = useState(false);
  const [oldPin, setOldPin] = useState("");
  const [newPin, setNewPin] = useState("");
  const [confirmPin, setConfirmPin] = useState("");

  // 打卡图片清理（家长）
  const [scanning, setScanning] = useState(false);
  const [cleaning, setCleaning] = useState(false);
  const [scanSummary, setScanSummary] = useState<string | null>(null);
  const [unusedCount, setUnusedCount] = useState(0);

  // 家庭称呼：各人只管对方那一半 —— 女儿改妈妈的称呼，妈妈改女儿的称呼
  const [callInput, setCallInput] = useState("");
  const [nicknameInput, setNicknameInput] = useState("");
  const [savingNames, setSavingNames] = useState(false);

  const isParent = role === "parent";
  /** 这次编辑的是对方的哪一套称呼（家长→女儿，小孩→妈妈） */
  const nameTarget: "mom" | "kid" = isParent ? "kid" : "mom";

  // 服务端称呼到位（或身份切换）后同步进输入框
  useEffect(() => {
    setCallInput(nameTarget === "kid" ? names.kidCall : names.momCall);
    setNicknameInput(nameTarget === "kid" ? names.kidNickname : names.momNickname);
  }, [
    nameTarget,
    names.kidCall,
    names.kidNickname,
    names.momCall,
    names.momNickname,
  ]);
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

  /** 保存对方那一半称呼（存服务端，另一台手机刷新就能看到） */
  const handleSaveNames = async () => {
    const callValue = callInput.trim();
    const nicknameValue = nicknameInput.trim();

    const tooLong = validateName(callValue) ?? validateName(nicknameValue);
    if (tooLong) {
      message.error(`称呼${tooLong}`);
      return;
    }
    if (!callValue && !nicknameValue) {
      message.error("称呼和昵称至少要填一个");
      return;
    }

    setSavingNames(true);
    try {
      const patch =
        nameTarget === "kid"
          ? {
              kidCall: callValue || DEFAULT_FAMILY_NAMES.kidCall,
              kidNickname: nicknameValue,
            }
          : {
              momCall: callValue || DEFAULT_FAMILY_NAMES.momCall,
              momNickname: nicknameValue,
            };
      const saved = await saveNames(patch);
      message.success(`已保存，界面上会显示「${displayName(saved, nameTarget)}」`);
    } catch (e) {
      message.error(e instanceof Error ? e.message : "保存失败，请重试");
    } finally {
      setSavingNames(false);
    }
  };

  /** 扫描闲置照片（只读，不删除） */
  const handleScan = async () => {
    setScanning(true);
    try {
      const result = await scanOrphanImages();
      setUnusedCount(result.orphans);
      setScanSummary(
        result.orphans > 0
          ? `共 ${result.total} 张打卡照片，${result.referenced} 张还在用，有 ${result.orphans} 张闲置照片可以清理`
          : `共 ${result.total} 张打卡照片，全部还在用，没有需要清理的`
      );
    } catch (e) {
      message.error(e instanceof Error ? e.message : "扫描失败，请重试");
    } finally {
      setScanning(false);
    }
  };

  /** 清理闲置照片（危险操作，二次确认后执行） */
  const handleClean = async () => {
    setCleaning(true);
    try {
      const result = await deleteOrphanImages();
      setScanSummary(
        result.failed > 0
          ? `已清理 ${result.deleted} 张闲置照片，${result.failed} 张没清掉`
          : `已清理 ${result.deleted} 张闲置照片`
      );
      setUnusedCount(0);
      message.success(`已清理 ${result.deleted} 张闲置照片`);
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

      {/* 家庭称呼（跨设备同步）：女儿改妈妈那半，妈妈改女儿那半 */}
      <Card className={styles.infoCard} variant="borderless">
        <div className={styles.infoHeader}>
          <div className={styles.infoIcon}>
            <SmileOutlined />
          </div>
          <div className={styles.infoText}>
            <div className={styles.appName}>称呼设置</div>
            <div className={styles.appDesc}>
              {isParent
                ? "你的界面里，女儿叫什么（昵称优先，留空就显示称呼）"
                : "你的界面里，妈妈叫什么（昵称优先，留空就显示称呼）"}
            </div>
          </div>
        </div>

        <div className={styles.nameFields}>
          <label className={styles.nameField}>
            <span className={styles.nameLabel}>
              {isParent ? "女儿的称呼" : "妈妈的称呼"}
            </span>
            <Input
              value={callInput}
              maxLength={MAX_NAME_LENGTH}
              placeholder={isParent ? "例如：女儿" : "例如：妈妈"}
              onChange={(e) => setCallInput(e.target.value)}
            />
          </label>
          <label className={styles.nameField}>
            <span className={styles.nameLabel}>
              {isParent ? "女儿的昵称" : "妈妈的昵称"}
            </span>
            <Input
              value={nicknameInput}
              maxLength={MAX_NAME_LENGTH}
              placeholder={isParent ? "例如：妹妹" : "例如：老妈"}
              onChange={(e) => setNicknameInput(e.target.value)}
            />
          </label>
        </div>

        <div className={styles.namePreview}>
          现在会显示「
          {displayName(
            {
              ...names,
              ...(nameTarget === "kid"
                ? { kidCall: callInput || DEFAULT_FAMILY_NAMES.kidCall, kidNickname: nicknameInput }
                : { momCall: callInput || DEFAULT_FAMILY_NAMES.momCall, momNickname: nicknameInput }),
            },
            nameTarget
          )}
          」（{isParent ? "女儿" : "妈妈"}自己的手机上打开也是这个名字）
        </div>

        <Button
          block
          type="primary"
          loading={savingNames}
          onClick={handleSaveNames}
          className={styles.nameSaveBtn}
        >
          保存称呼
        </Button>
        {!namesReady && (
          <div className={styles.roleHint}>
            还没连上云端称呼表（本地库需要执行 0004 迁移），当前显示的是本机缓存
          </div>
        )}
      </Card>

      {/* 打卡图片清理（仅家长）：清理被删除流水遗留的闲置照片 */}
      {isParent && (
        <Card className={styles.infoCard} variant="borderless">
          <div className={styles.infoHeader}>
            <div className={styles.infoIcon}>
              <PictureOutlined />
            </div>
            <div className={styles.infoText}>
              <div className={styles.appName}>打卡照片清理</div>
              <div className={styles.appDesc}>
                删除记录时照片会自动一起删掉；这里清理以前遗留下来、已经没人用的闲置照片
              </div>
            </div>
          </div>
          {scanSummary && <div className={styles.scanResult}>{scanSummary}</div>}
          <div className={styles.cleanupActions}>
            <Button icon={<PictureOutlined />} loading={scanning} onClick={handleScan}>
              扫描闲置照片
            </Button>
            {unusedCount > 0 && (
              <Popconfirm
                title={`确认清理这 ${unusedCount} 张闲置照片？`}
                description="照片将从云端永久删除，且不可恢复"
                okText="清理"
                okButtonProps={{ danger: true }}
                cancelText="取消"
                onConfirm={handleClean}
              >
                <Button danger loading={cleaning} icon={<DeleteOutlined />}>
                  清理 {unusedCount} 张
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
