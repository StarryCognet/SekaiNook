import { useEffect, useRef, useState } from 'react';
import { Button, Input, Modal, message } from 'antd';
import { CameraOutlined, PictureOutlined } from '@ant-design/icons';
import { addLedgerRecord } from '../api/familyLedger';
import { uploadImage } from '../api/upload';
import { compressImage } from '../utils/image';
import { useBackButton } from '../utils/useBackButton';
import type { TaskConfig } from '../types/family';
import styles from './CheckInModal.module.css';

/**
 * 任务打卡弹窗（拍照 / 相册 + 备注）。
 *
 * 账本页与首页（妹妹版）共用：家长提交直接入账，小孩提交进入待审批。
 * 提交成功后由调用方负责刷新数据与提示（两边文案不一样）。
 */
export interface CheckInModalProps {
  /** 正在打卡的任务；null = 关闭 */
  task: TaskConfig | null;
  /** 家长（直接入账）还是小孩（走审批） */
  isParent: boolean;
  /** 提交前的二次校验（时间窗 / 每日次数），返回文案则拒绝提交 */
  guard?: (task: TaskConfig) => string | null;
  onClose: () => void;
  /** 提交成功；调用方在这里刷新余额并给提示 */
  onSuccess: (task: TaskConfig, recordId: string) => void | Promise<void>;
}

export default function CheckInModal({
  task,
  isParent,
  guard,
  onClose,
  onSuccess,
}: CheckInModalProps) {
  const [note, setNote] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  /** 记住上一次打卡的任务：换任务（或关闭再打开）时清空草稿 */
  const draftTaskId = useRef<string | null>(null);

  useEffect(() => {
    const id = task?.id ?? null;
    if (id === draftTaskId.current) return;
    draftTaskId.current = id;
    setNote('');
    setImageFile(null);
    setImagePreview((prev) => {
      if (prev) URL.revokeObjectURL(prev);
      return null;
    });
  }, [task]);

  const close = () => {
    onClose();
  };

  // 安卓硬件返回键：弹窗打开时先关弹窗，而不是退出应用
  useBackButton(!!task, close);

  /** 选择图片（拍照或相册） */
  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageFile(file);
    setImagePreview((prev) => {
      if (prev) URL.revokeObjectURL(prev);
      return URL.createObjectURL(file);
    });
    e.target.value = '';
  };

  /** 提交：压缩图片 → 上传（如有）→ 写入流水 */
  const handleSubmit = async () => {
    if (!task) return;

    const blocked = guard?.(task);
    if (blocked) {
      message.warning(blocked);
      return;
    }

    setUploading(true);
    let imageUrl: string | undefined;
    let uploadError: string | null = null;

    // 上传图片（失败不阻断打卡，但必须把原因说清楚）
    if (imageFile) {
      try {
        // 手机原图常 3-15MB，先压到长边 1600 并转 JPEG，绕开后端 5MB 上限与 HEIF 格式问题
        const compressed = await compressImage(imageFile);
        const result = await uploadImage(compressed);
        imageUrl = result.url;
      } catch (e) {
        uploadError = e instanceof Error ? e.message : '图片上传失败';
      }
    }

    try {
      const recordId = await addLedgerRecord(
        task,
        { note: note.trim() || undefined, imageUrl },
        { status: isParent ? 'approved' : 'pending' }
      );
      // 先关弹窗再刷新：网络慢时不要让人盯着转圈的弹窗
      close();
      await onSuccess(task, recordId);
      if (uploadError) {
        message.warning({ content: `照片没传上去：${uploadError}（打卡本身已成功）`, duration: 6 });
      }
    } catch (e) {
      message.error(e instanceof Error ? e.message : '操作失败，请重试');
    } finally {
      setUploading(false);
    }
  };

  return (
    <Modal
      open={!!task}
      title={task ? `${isParent ? '打卡' : '申请打卡'}：${task.name}` : ''}
      onCancel={close}
      onOk={handleSubmit}
      okText={isParent ? '确认打卡' : '提交申请'}
      cancelText="取消"
      confirmLoading={uploading}
      // 手机端键盘弹出时不要把弹窗顶出屏幕：贴顶 + 内容区自己滚动
      style={{ top: 24 }}
      styles={{ body: { maxHeight: '60vh', overflowY: 'auto' } }}
      destroyOnHidden
    >
      {/* 上方：拍照 / 相册 双入口 */}
      <div className={styles.modalSection}>
        <div className={styles.modalLabel}>
          <CameraOutlined /> 上传照片
        </div>
        <div className={styles.uploadArea}>
          {imagePreview ? (
            <div className={styles.imagePreviewWrap}>
              <img src={imagePreview} alt="任务照片" className={styles.imagePreview} />
              <Button
                size="small"
                className={styles.imageRemove}
                onClick={() => {
                  setImageFile(null);
                  setImagePreview((prev) => {
                    if (prev) URL.revokeObjectURL(prev);
                    return null;
                  });
                }}
              >
                移除
              </Button>
            </div>
          ) : (
            <div className={styles.uploadChoices}>
              {/* 拍照：capture 直接调起系统相机 */}
              <label className={styles.uploadBtn}>
                <input
                  type="file"
                  accept="image/*"
                  capture="environment"
                  onChange={handleImageChange}
                  style={{ display: 'none' }}
                />
                <CameraOutlined />
                <span>拍照</span>
              </label>
              {/* 相册：不带 capture，让系统弹「相机 / 相册 / 文件」选择 */}
              <label className={styles.uploadBtn}>
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleImageChange}
                  style={{ display: 'none' }}
                />
                <PictureOutlined />
                <span>从相册选</span>
              </label>
            </div>
          )}
        </div>
      </div>

      {/* 下方：备注 */}
      <div className={styles.modalSection}>
        <div className={styles.modalLabel}>
          <PictureOutlined /> 备注
        </div>
        <Input.TextArea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="填写任务备注（可选）"
          rows={3}
          maxLength={200}
          showCount
        />
      </div>
    </Modal>
  );
}
