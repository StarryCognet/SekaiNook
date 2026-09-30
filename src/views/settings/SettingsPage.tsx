import { useEffect, useRef, useState } from "react";
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
  BgColorsOutlined,
  CheckOutlined,
  UploadOutlined,
  ArrowLeftOutlined,
  RightOutlined,
  DownOutlined,
  UpOutlined,
} from "@ant-design/icons";
import { APP_VERSION, CHANGELOG } from "../../config/changelog";
import { useFamilyStore } from "../../store/useFamilyStore";
import type { FamilyRole } from "../../store/useFamilyStore";
import { useSettingsStore } from "../../store/useSettingsStore";
import { useThemeStore, useThemePalette } from "../../store/useThemeStore";
import { THEMES, type ThemeId } from "../../theme/themes";
import {
  DEFAULT_FAMILY_NAMES,
  MAX_NAME_LENGTH,
  displayName,
  validateName,
} from "../../types/settings";
import { scanOrphanImages, deleteOrphanImages } from "../../api/maintenance";
import { uploadImage } from "../../api/upload";
import { compressImage, isAbortError } from "../../utils/image";
import { useBackButton } from "../../utils/useBackButton";
import styles from "./SettingsPage.module.css";

/** 设置页第二层的大类 */
type SectionId = "appearance" | "family" | "admin";

/** 版本日志收起时展示几个版本（都是最新在前） */
const RECENT_LOG_COUNT = 3;

/** 称呼草稿的存储键前缀：改了一半就走开（切身份 / 关掉标签）也不丢 */
const NAME_DRAFT_KEY = "sekainook_name_draft";

type NameDraft = { call: string; nickname: string };

function readNameDraft(target: "mom" | "kid"): NameDraft | null {
  try {
    const raw = localStorage.getItem(`${NAME_DRAFT_KEY}:${target}`);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<NameDraft>;
    if (typeof parsed.call !== "string" || typeof parsed.nickname !== "string") {
      return null;
    }
    return { call: parsed.call, nickname: parsed.nickname };
  } catch {
    return null;
  }
}

function writeNameDraft(target: "mom" | "kid", draft: NameDraft): void {
  try {
    localStorage.setItem(`${NAME_DRAFT_KEY}:${target}`, JSON.stringify(draft));
  } catch {
    // 存不下就算了，不拦着保存
  }
}

function clearNameDraft(target: "mom" | "kid"): void {
  try {
    localStorage.removeItem(`${NAME_DRAFT_KEY}:${target}`);
  } catch {
    // 同上
  }
}

/**
 * 设置页：两层结构 ——
 *   第一层只列大类入口（外观 / 家庭 / 家长管理）与「关于」（应用信息 + 版本日志）；
 *   点一个入口进第二层再改具体项，第二层顶部有返回。关于与版本日志留在第一层不动。
 *   版本日志默认收起（只看最新 3 个），展开后顶部与底部各有收起按钮。
 */
export default function SettingsPage() {
  const {
    role,
    setRole,
    verifyParentPin,
    setParentPin,
    pinLockRemainingMs,
    pinAttemptsLeft,
    hasCustomParentPin,
  } = useFamilyStore();
  const { names, ready: namesReady, save: saveNames } = useSettingsStore();
  // 主题（本机）与背景图（跨设备同步）
  const { themeId, setThemeId, background, saveBackground } = useThemeStore();
  const palette = useThemePalette();

  // 当前在第二层的哪个大类；null = 停在外层入口列表
  const [section, setSection] = useState<SectionId | null>(null);
  const settingsRef = useRef<HTMLDivElement | null>(null);

  // 版本日志折叠：默认收起
  const [logExpanded, setLogExpanded] = useState(false);

  // 切家长口令验证弹窗
  const [pinModalOpen, setPinModalOpen] = useState(false);
  const [pinInput, setPinInput] = useState("");

  // 修改家长口令弹窗
  const [changePinOpen, setChangePinOpen] = useState(false);
  const [oldPin, setOldPin] = useState("");
  const [newPin, setNewPin] = useState("");
  const [confirmPin, setConfirmPin] = useState("");

  // 口令校验中（异步比对摘要）与剩余锁定秒数（0 = 未锁定）
  const [pinChecking, setPinChecking] = useState(false);
  const [pinLockSeconds, setPinLockSeconds] = useState(0);
  /** 口令是不是家长自己的那份：存进来后由 state 驱动，改完口令立刻刷新文案 */
  const [customPin, setCustomPin] = useState(() => hasCustomParentPin());

  // 打卡图片清理（家长）
  const [scanning, setScanning] = useState(false);
  const [cleaning, setCleaning] = useState(false);
  const [scanSummary, setScanSummary] = useState<string | null>(null);
  const [unusedCount, setUnusedCount] = useState(0);

  // 家庭称呼：各人只管对方那一半 —— 女儿改妈妈的称呼，妈妈改女儿的称呼
  const [callInput, setCallInput] = useState("");
  const [nicknameInput, setNicknameInput] = useState("");
  const [savingNames, setSavingNames] = useState(false);

  // 全局背景图：选文件 → 压缩 → 传云端 → 存地址
  const bgInputRef = useRef<HTMLInputElement | null>(null);
  const [uploadingBg, setUploadingBg] = useState(false);
  const [removingBg, setRemovingBg] = useState(false);
  /** 上传中可取消：用户改主意时立刻停手，别占着主线程解码大图 */
  const bgAbortRef = useRef<AbortController | null>(null);

  const isParent = role === "parent";
  /** 这次编辑的是对方的哪一套称呼（家长→女儿，小孩→妈妈） */
  const nameTarget: "mom" | "kid" = isParent ? "kid" : "mom";
  const currentThemeName =
    THEMES.find((item) => item.id === themeId)?.name ?? themeId;

  /** 已保存的对方称呼（用来判断输入框里是不是还没保存的改动） */
  const serverCall = nameTarget === "kid" ? names.kidCall : names.momCall;
  const serverNickname =
    nameTarget === "kid" ? names.kidNickname : names.momNickname;
  const namesDirty =
    namesReady && (callInput !== serverCall || nicknameInput !== serverNickname);

  // 外层入口：一句话告诉你这组里有什么、现在是什么状态
  const sections: { id: SectionId; title: string; desc: string; icon: React.ReactNode }[] = [
    {
      id: "appearance",
      title: "外观",
      desc: `主题与背景图 · 现在是「${currentThemeName}」主题${
        background ? " · 已设背景图" : ""
      }`,
      icon: <BgColorsOutlined />,
    },
    {
      id: "family",
      title: "家庭",
      desc: `身份与称呼 · 现在用的是${isParent ? "家长" : "小孩"}身份`,
      icon: <UserSwitchOutlined />,
    },
    ...(isParent
      ? [
          {
            id: "admin" as SectionId,
            title: "家长管理",
            desc: "家长口令、打卡照片清理",
            icon: <LockOutlined />,
          },
        ]
      : []),
  ];

  const visibleLog = logExpanded
    ? CHANGELOG
    : CHANGELOG.slice(0, RECENT_LOG_COUNT);
  const hiddenLogCount = Math.max(0, CHANGELOG.length - RECENT_LOG_COUNT);

  /** 进第二层：顺手把滚动拉回顶部，否则会落在上一层停留的位置 */
  const openSection = (id: SectionId) => {
    setSection(id);
    requestAnimationFrame(() =>
      settingsRef.current?.scrollIntoView({ block: "start" })
    );
  };
  const closeSection = () => setSection(null);

  // 服务端称呼到位（或身份切换）后同步进输入框；本地还留着没保存的草稿时以草稿为准
  useEffect(() => {
    const draft = readNameDraft(nameTarget);
    setCallInput(
      draft ? draft.call : nameTarget === "kid" ? names.kidCall : names.momCall
    );
    setNicknameInput(
      draft ? draft.nickname : nameTarget === "kid" ? names.kidNickname : names.momNickname
    );
  }, [
    nameTarget,
    names.kidCall,
    names.kidNickname,
    names.momCall,
    names.momNickname,
  ]);
  // 改了一半就走开（切身份、点进别的层、关掉标签）也不丢：有改动就自动留一份草稿
  useEffect(() => {
    if (!namesReady || !namesDirty) return;
    writeNameDraft(nameTarget, { call: callInput, nickname: nicknameInput });
  }, [namesReady, namesDirty, nameTarget, callInput, nicknameInput]);
  // 弹窗 / 第二层打开时接管安卓返回键：返回键先退一层，而不是退出设置页
  useBackButton(section !== null, closeSection);
  useBackButton(pinModalOpen, () => setPinModalOpen(false));
  useBackButton(changePinOpen, () => setChangePinOpen(false));

  // 锁定中每秒刷新剩余秒数；剩余时间读的是 localStorage，刷新页面也绕不过去
  useEffect(() => {
    if (pinLockSeconds <= 0) return;
    const timer = setInterval(() => {
      setPinLockSeconds(Math.ceil(pinLockRemainingMs() / 1000));
    }, 1000);
    return () => clearInterval(timer);
  }, [pinLockSeconds, pinLockRemainingMs]);

  /** 距解锁的剩余秒数（0 = 未锁定）。剩余时间存在 localStorage，刷新页面也绕不过去 */
  const lockSecondsLeft = () => Math.ceil(pinLockRemainingMs() / 1000);

  /**
   * 口令校验失败的统一提示：锁定中只说要等多久，否则提示还剩几次机会。
   * 两种情况都不透露任何关于正确口令的信息。
   */
  const warnPinFailed = (label: string) => {
    const left = lockSecondsLeft();
    if (left > 0) {
      setPinLockSeconds(left);
      message.warning(`${label}错得太多次，请等 ${left} 秒再试`);
      return;
    }
    message.error(`${label}不对，还可以试 ${pinAttemptsLeft()} 次`);
  };

  /** 身份切换：切到家长需验证口令，切到小孩直接切换 */
  const handleRoleChange = (value: string | number) => {
    const next = value as FamilyRole;
    if (next === "parent" && role === "child") {
      setPinInput("");
      // 上次锁定可能一直持续到刷新之后，开弹窗时就把倒计时同步进来
      setPinLockSeconds(lockSecondsLeft());
      setPinModalOpen(true);
      return;
    }
    setRole(next);
  };

  /** 验证口令并切换为家长（异步校验 + 失败锁定） */
  const handlePinConfirm = async () => {
    if (pinChecking) return;
    const left = lockSecondsLeft();
    if (left > 0) {
      setPinLockSeconds(left);
      message.warning(`口令已锁定，请等 ${left} 秒再试`);
      return;
    }

    setPinChecking(true);
    let ok = false;
    try {
      ok = await verifyParentPin(pinInput);
    } finally {
      // 校验抛错（例如存储不可用）也要把 loading 收掉，不能卡住按钮
      setPinChecking(false);
    }
    if (ok) {
      setRole("parent");
      setPinModalOpen(false);
      message.success("已切换为家长");
      return;
    }
    warnPinFailed("口令");
  };

  /** 修改家长口令（原口令走同一套异步校验，试错一样会被锁定） */
  const handleChangePin = async () => {
    if (pinChecking) return;
    const left = lockSecondsLeft();
    if (left > 0) {
      setPinLockSeconds(left);
      message.warning(`口令已锁定，请等 ${left} 秒再试`);
      return;
    }

    setPinChecking(true);
    try {
      // 先确认身份，不通过就不碰新口令
      if (!(await verifyParentPin(oldPin))) {
        warnPinFailed("原口令");
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
      await setParentPin(newPin);
    } catch (e) {
      message.error(e instanceof Error ? e.message : "口令保存失败，请重试");
      return;
    } finally {
      setPinChecking(false);
    }

    setChangePinOpen(false);
    setOldPin("");
    setNewPin("");
    setConfirmPin("");
    message.success("家长口令已更新");
    setCustomPin(hasCustomParentPin());
  };

  /** 换主题：只改本机显示，另一台手机自己选 */
  const handleThemeChange = (id: ThemeId) => {
    if (id === themeId) return;
    setThemeId(id);
    const preset = THEMES.find((item) => item.id === id);
    // 连点几套主题只留最后一条提示（固定 key 会替换掉上一条，不再堆一屏）
    message.success({
      content: `已切换到「${preset?.name ?? id}」主题`,
      key: "theme-switch",
    });
  };

  /** 选好背景图：压缩后传云端，再把地址存进设置（两台手机同步） */
  const handleBgPicked = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = ""; // 允许连续选同一个文件
    if (!file) return;
    if (!file.type.startsWith("image/")) {
      message.error("请选择图片文件");
      return;
    }

    const controller = new AbortController();
    bgAbortRef.current = controller;
    setUploadingBg(true);
    try {
      // 解码期就把 signal 传下去：几千万像素的大图能中途停手，不占着主线程
      const compressed = await compressImage(file, { signal: controller.signal });
      if (controller.signal.aborted) return;
      const { url } = await uploadImage(compressed);
      if (controller.signal.aborted) return;
      await saveBackground(url);
      message.success("背景图已换好，另一台手机打开也是这张");
    } catch (e) {
      if (isAbortError(e)) {
        message.info("已取消，背景图没换");
      } else {
        message.error(e instanceof Error ? e.message : "上传失败，请重试");
      }
    } finally {
      bgAbortRef.current = null;
      setUploadingBg(false);
    }
  };

  /** 移除背景图：恢复主题自带纯色底 */
  const handleRemoveBackground = async () => {
    setRemovingBg(true);
    try {
      await saveBackground("");
      message.success("已移除背景图");
    } catch (e) {
      message.error(e instanceof Error ? e.message : "移除失败，请重试");
    } finally {
      setRemovingBg(false);
    }
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
      clearNameDraft(nameTarget); // 已经进服务端了，草稿退休
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

  /** 第二层顶部的返回条，每个大类页都带一条 */
  const renderBackBar = () => (
    <button type="button" className={styles.backBtn} onClick={closeSection}>
      <ArrowLeftOutlined /> 设置
    </button>
  );

  return (
    <div className={styles.settings} ref={settingsRef}>
      {/* ================= 第一层：大类入口 ================= */}
      {section === null && (
        <section className={styles.group}>
          <div className={styles.entryList}>
            {sections.map((entry) => (
              <button
                key={entry.id}
                type="button"
                className={styles.entry}
                onClick={() => openSection(entry.id)}
              >
                <span className={styles.entryIcon}>{entry.icon}</span>
                <span className={styles.entryBody}>
                  <span className={styles.entryName}>{entry.title}</span>
                  <span className={styles.entryDesc}>{entry.desc}</span>
                </span>
                <RightOutlined className={styles.entryArrow} />
              </button>
            ))}
          </div>
        </section>
      )}

      {/* ================= 第二层：外观 ================= */}
      {section === "appearance" && (
        <section className={styles.group}>
          {renderBackBar()}
          <h2 className={styles.groupTitle}>外观</h2>
          <p className={styles.groupDesc}>主题和背景图，改完这台手机立刻变</p>

          {/* 主题切换 */}
          <Card className={styles.infoCard} variant="borderless">
            <div className={styles.infoHeader}>
              <div className={styles.infoIcon}>
                <BgColorsOutlined />
              </div>
              <div className={styles.infoText}>
                <div className={styles.appName}>主题</div>
                <div className={styles.appDesc}>
                  全局生效；只改这台手机的显示，另一台手机自己选。顶栏右上角那颗太阳/月亮也能一键在深浅之间来回切
                </div>
              </div>
            </div>
            <div className={styles.themeList}>
              {THEMES.map((preset) => {
                const active = preset.id === themeId;
                return (
                  <button
                    key={preset.id}
                    type="button"
                    className={`${styles.themeItem} ${active ? styles.themeItemActive : ""}`}
                    onClick={() => handleThemeChange(preset.id)}
                  >
                    <span className={styles.themeSwatch}>
                      {preset.swatch.map((color) => (
                        <i key={color} style={{ background: color }} />
                      ))}
                    </span>
                    <span className={styles.themeBody}>
                      <span className={styles.themeName}>{preset.name}</span>
                      <span className={styles.themeDesc}>{preset.description}</span>
                    </span>
                    {active && <CheckOutlined className={styles.themeCheck} />}
                  </button>
                );
              })}
            </div>
          </Card>

          {/* 全局背景图 */}
          <Card className={styles.infoCard} variant="borderless">
            <div className={styles.infoHeader}>
              <div className={styles.infoIcon}>
                <PictureOutlined />
              </div>
              <div className={styles.infoText}>
                <div className={styles.appName}>全局背景图</div>
                <div className={styles.appDesc}>
                  换一张全家福当底色，两台手机会同步
                </div>
              </div>
            </div>

            {background ? (
              <div className={styles.bgPreview}>
                <img className={styles.bgPreviewImg} src={background} alt="当前背景图" />
                <span className={styles.bgPreviewNote}>现在用的就是这张</span>
              </div>
            ) : (
              <div className={styles.bgEmpty}>还没设置背景图，现在用主题自带的纯色底</div>
            )}

            <div className={styles.bgActions}>
              <Button
                icon={<UploadOutlined />}
                loading={uploadingBg}
                onClick={() => bgInputRef.current?.click()}
              >
                {background ? "换一张照片" : "上传照片当背景"}
              </Button>
              {uploadingBg && (
                <Button onClick={() => bgAbortRef.current?.abort()}>取消上传</Button>
              )}
              {background && (
                <Popconfirm
                  title="移除背景图？"
                  description="移除后恢复主题自带的纯色底，照片会在下次清理闲置照片时从云端删掉"
                  okText="移除"
                  cancelText="取消"
                  onConfirm={handleRemoveBackground}
                >
                  <Button danger icon={<DeleteOutlined />} loading={removingBg}>
                    移除背景图
                  </Button>
                </Popconfirm>
              )}
            </div>
            <input
              ref={bgInputRef}
              type="file"
              accept="image/*"
              hidden
              onChange={handleBgPicked}
            />
            <div className={styles.roleHint}>建议用横图；上传前会自动压到长边 1600px</div>
          </Card>
        </section>
      )}

      {/* ================= 第二层：家庭 ================= */}
      {section === "family" && (
        <section className={styles.group}>
          {renderBackBar()}
          <h2 className={styles.groupTitle}>家庭</h2>
          <p className={styles.groupDesc}>身份和称呼，两个人在各自手机上各管一半</p>

          {/* 当前身份 */}
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
                  placeholder={isParent ? "例如：宝贝" : "例如：老妈"}
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
            {namesDirty && (
              <div className={styles.nameDraftHint}>
                有改动还没保存：先帮你留在这台手机上，切走再回来还能接着改
              </div>
            )}
            {!namesReady && (
              <div className={styles.roleHint}>
                还没连上云端称呼表（本地库需要执行 0004 迁移），当前显示的是本机缓存
              </div>
            )}
          </Card>
        </section>
      )}

      {/* ================= 第二层：家长管理（仅家长可见） ================= */}
      {section === "admin" && isParent && (
        <section className={styles.group}>
          {renderBackBar()}
          <h2 className={styles.groupTitle}>家长管理</h2>
          <p className={styles.groupDesc}>口令和打卡照片，只有家长身份看得到</p>

          {/* 家长口令 */}
          <Card className={styles.infoCard} variant="borderless">
            <div className={styles.infoHeader}>
              <div className={styles.infoIcon}>
                <LockOutlined />
              </div>
              <div className={styles.infoText}>
                <div className={styles.appName}>家长口令</div>
                <div className={styles.appDesc}>
                  切到家长身份要输它；
                  {customPin
                    ? "已经改成你自己的口令了（忘了只能清掉这台手机的浏览器数据重来）"
                    : "现在还是出厂口令 1234，建议改成只有你知道的"}
                </div>
              </div>
            </div>
            <Button
              block
              className={styles.changePinBtn}
              icon={<LockOutlined />}
              onClick={() => {
                setOldPin("");
                setNewPin("");
                setConfirmPin("");
                // 上次锁定可能一直持续到刷新之后，开弹窗时就把倒计时同步进来
                setPinLockSeconds(lockSecondsLeft());
                setChangePinOpen(true);
              }}
            >
              修改家长口令
            </Button>
          </Card>

          {/* 打卡图片清理：清理被删除流水遗留的闲置照片 */}
          <Card className={styles.infoCard} variant="borderless">
            <div className={styles.infoHeader}>
              <div className={styles.infoIcon}>
                <DeleteOutlined />
              </div>
              <div className={styles.infoText}>
                <div className={styles.appName}>打卡照片清理</div>
                <div className={styles.appDesc}>
                  删除记录时照片会自动一起删掉；这里清理以前遗留下来、已经没人用的闲置照片
                  （正在用的背景图不会被清掉）
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
        </section>
      )}

      {/* ================= 第一层：关于（只在入口列表这一层显示） ================= */}
      {section === null && (
      <section className={styles.group}>
        <h2 className={styles.groupTitle}>关于</h2>
        <p className={styles.groupDesc}>这是什么版本、改过什么</p>

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

        {/* 版本日志：默认收起只显示最近几个，展开看全部 */}
        <Card
          className={styles.logCard}
          variant="borderless"
          title={
            <span className={styles.logTitle}>
              <InfoCircleOutlined /> 版本日志
            </span>
          }
          extra={
            logExpanded ? (
              <Button
                size="small"
                type="text"
                icon={<UpOutlined />}
                onClick={() => setLogExpanded(false)}
              >
                收起
              </Button>
            ) : null
          }
        >
          <Timeline
            items={visibleLog.map((entry) => ({
              color: palette.primary,
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

          <div className={styles.logFooter}>
            {logExpanded ? (
              <Button
                block
                type="text"
                icon={<UpOutlined />}
                onClick={() => setLogExpanded(false)}
              >
                收起，只看最近 {RECENT_LOG_COUNT} 个版本
              </Button>
            ) : (
              <>
                <Button
                  block
                  icon={<DownOutlined />}
                  onClick={() => setLogExpanded(true)}
                >
                  展开全部（共 {CHANGELOG.length} 个版本）
                </Button>
                <div className={styles.logHint}>
                  收起时只显示最近 {RECENT_LOG_COUNT} 个版本，还有 {hiddenLogCount} 个更早的在里面
                </div>
              </>
            )}
          </div>
        </Card>
      </section>
      )}

      {/* 切换为家长：口令验证弹窗 */}
      <Modal
        title="切换为家长"
        open={pinModalOpen}
        onOk={handlePinConfirm}
        onCancel={() => setPinModalOpen(false)}
        okText="确认"
        cancelText="取消"
        confirmLoading={pinChecking}
        okButtonProps={{ disabled: pinLockSeconds > 0 }}
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
              disabled={pinLockSeconds > 0}
              onPressEnter={handlePinConfirm}
            />
          </Form.Item>
        </Form>
        <div className={styles.pinHint}>
          {pinLockSeconds > 0
            ? `口令锁定中，请等 ${pinLockSeconds} 秒再试`
            : "口令不正确将无法切换到家长模式"}
        </div>
      </Modal>

      {/* 修改家长口令弹窗 */}
      <Modal
        title="修改家长口令"
        open={changePinOpen}
        onOk={handleChangePin}
        onCancel={() => setChangePinOpen(false)}
        okText="保存"
        cancelText="取消"
        confirmLoading={pinChecking}
        okButtonProps={{ disabled: pinLockSeconds > 0 }}
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
              disabled={pinLockSeconds > 0}
            />
          </Form.Item>
          <Form.Item label="新口令">
            <Input.Password
              placeholder="4-8 位新口令"
              value={newPin}
              onChange={(e) => setNewPin(e.target.value)}
              maxLength={8}
              disabled={pinLockSeconds > 0}
            />
          </Form.Item>
          <Form.Item label="确认新口令">
            <Input.Password
              placeholder="再次输入新口令"
              value={confirmPin}
              onChange={(e) => setConfirmPin(e.target.value)}
              maxLength={8}
              disabled={pinLockSeconds > 0}
              onPressEnter={handleChangePin}
            />
          </Form.Item>
        </Form>
        <div className={styles.pinHint}>
          {pinLockSeconds > 0
            ? `口令锁定中，请等 ${pinLockSeconds} 秒再试`
            : "出厂口令为 1234，请尽快修改"}
        </div>
      </Modal>
    </div>
  );
}
