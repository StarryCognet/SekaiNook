import { useState } from "react";
import { Button, Card, Input, Modal, message } from "antd";
import { SmileOutlined, TeamOutlined, LockOutlined } from "@ant-design/icons";
import { useFamilyStore } from "../store/useFamilyStore";
import styles from "./RoleGate.module.css";

/**
 * 身份选择门 —— 首次在新设备打开时先选身份。
 * 之前缺省就是家长模式，妹妹的手机第一次打开即可审批自己的申请；
 * 现在默认不进任何模式，选家长必须验证口令。
 */
export default function RoleGate() {
  const { setRole, getParentPin } = useFamilyStore();
  const [pinOpen, setPinOpen] = useState(false);
  const [pin, setPin] = useState("");

  /** 验证口令后进入家长模式 */
  const confirmParent = () => {
    if (pin === getParentPin()) {
      setPinOpen(false);
      setRole("parent");
      message.success("已进入家长模式");
    } else {
      message.error("口令错误");
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

        <div className={styles.footer}>出厂口令 1234，进去后请在设置页修改</div>
      </Card>

      <Modal
        title="家长口令"
        open={pinOpen}
        onOk={confirmParent}
        onCancel={() => setPinOpen(false)}
        okText="进入家长模式"
        cancelText="取消"
      >
        <Input.Password
          placeholder="请输入家长口令"
          prefix={<LockOutlined />}
          value={pin}
          onChange={(e) => setPin(e.target.value)}
          maxLength={8}
          autoFocus
          onPressEnter={confirmParent}
        />
      </Modal>
    </div>
  );
}
