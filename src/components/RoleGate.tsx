import { useEffect, useState } from "react";
import { Button, Card, Input, Modal, message } from "antd";
import { SmileOutlined, TeamOutlined, LockOutlined } from "@ant-design/icons";
import { useFamilyStore } from "../store/useFamilyStore";
import styles from "./RoleGate.module.css";

/**
 * 身份选择门 —— 首次在新设备打开时先选身份。
 * 之前缺省就是家长模式，妹妹的手机第一次打开即可审批自己的申请；
 * 现在默认不进任何模式，选家长必须验证口令。
 * 口令走异步校验（store.verifyParentPin），连续试错会被锁定，详见 store 注释。
 */
export default function RoleGate() {
  const { setRole, verifyParentPin, pinLockRemainingMs, pinAttemptsLeft } =
    useFamilyStore();
  const [pinOpen, setPinOpen] = useState(false);
  const [pin, setPin] = useState("");
  const [checking, setChecking] = useState(false);
  /** 锁定剩余秒数（0 = 未锁定），锁定期内每秒刷新一次 */
  const [lockSeconds, setLockSeconds] = useState(0);

  // 锁定中才起定时器；解锁后（剩余归零）自动停掉
  useEffect(() => {
    if (lockSeconds <= 0) return;
    const timer = setInterval(() => {
      setLockSeconds(Math.ceil(pinLockRemainingMs() / 1000));
    }, 1000);
    return () => clearInterval(timer);
  }, [lockSeconds, pinLockRemainingMs]);

  /** 验证口令后进入家长模式 */
  const confirmParent = async () => {
    if (checking) return;
    const left = Math.ceil(pinLockRemainingMs() / 1000);
    if (left > 0) {
      setLockSeconds(left);
      message.warning(`口令已锁定，请等 ${left} 秒再试`);
      return;
    }

    setChecking(true);
    let ok = false;
    try {
      ok = await verifyParentPin(pin);
    } finally {
      // 校验抛错（例如存储不可用）也要把 loading 收掉，不能卡住按钮
      setChecking(false);
    }
    if (ok) {
      setPinOpen(false);
      setRole("parent");
      message.success("已进入家长模式");
      return;
    }

    // 刚这一次失败可能刚好触发锁定：锁定中提示等多久，否则提示还剩几次机会
    const locked = Math.ceil(pinLockRemainingMs() / 1000);
    if (locked > 0) {
      setLockSeconds(locked);
      message.warning(`口令错得太多次，请等 ${locked} 秒再试`);
    } else {
      message.error(`口令不对，还可以试 ${pinAttemptsLeft()} 次`);
    }
  };

  return (
    <div className={styles.gate}>
      <Card className={styles.card} variant="borderless">
        <div className={styles.emoji}>👋</div>
        <div className={styles.title}>你是谁呀？</div>
        <div className={styles.subtitle}>
          选好身份就可以开始了，之后可在「设置」里切换
        </div>

        <Button
          block
          size="large"
          type="primary"
          icon={<SmileOutlined />}
          className={styles.choiceBtn}
          onClick={() => setRole("child")}
        >
          我是小孩
        </Button>
        <div className={styles.choiceHint}>打卡赚积分，等着家长审批</div>

        <Button
          block
          size="large"
          icon={<TeamOutlined />}
          className={styles.choiceBtn}
          onClick={() => {
            setPin("");
            setPinOpen(true);
          }}
        >
          我是家长
        </Button>
        <div className={styles.choiceHint}>需要口令，可审批打卡、增删记录</div>

        <div className={styles.footer}>
          口令由家长自己设。忘了的话，在已经登录家长模式的手机上到「设置 → 家长管理」里改一个
        </div>
      </Card>

      <Modal
        title="家长口令"
        open={pinOpen}
        onOk={confirmParent}
        onCancel={() => setPinOpen(false)}
        okText="进入家长模式"
        cancelText="取消"
        confirmLoading={checking}
        okButtonProps={{ disabled: lockSeconds > 0 }}
      >
        <Input.Password
          placeholder="请输入家长口令"
          prefix={<LockOutlined />}
          value={pin}
          onChange={(e) => setPin(e.target.value)}
          maxLength={8}
          autoFocus
          disabled={lockSeconds > 0}
          onPressEnter={confirmParent}
        />
        {lockSeconds > 0 && (
          <div style={{ marginTop: 8, fontSize: 12, color: "var(--color-text-tertiary)" }}>
            口令锁定中，请等 {lockSeconds} 秒再试
          </div>
        )}
      </Modal>
    </div>
  );
}
