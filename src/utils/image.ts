/**
 * 图片压缩工具 —— 手机拍照上传前统一压缩。
 *
 * 背景：后端 POST /api/upload 有 5MB 硬上限，且只接受 jpg/png/webp/gif。
 * 安卓手机随手一拍常达 3-15MB，部分机型默认存 HEIF（image/heic）会被 415 拒绝。
 * 这里在浏览器端把照片等比缩到长边 maxEdge 并转成 JPEG，通常落到 200-500KB。
 *
 * 压缩失败（浏览器无法解码该格式）时返回原文件，保证打卡流程不中断。
 */

import { designTokens } from '../theme/tokens';

/** 压缩参数 */
export interface CompressOptions {
  /** 长边上限（px），超出则等比缩放 */
  maxEdge?: number;
  /** JPEG 质量（0-1） */
  quality?: number;
}

const DEFAULT_OPTIONS: Required<CompressOptions> = {
  maxEdge: 1600,
  quality: 0.8,
};

/** 解码结果：可绘制源 + 尺寸 + 释放回调 */
interface DecodedImage {
  source: CanvasImageSource;
  width: number;
  height: number;
  cleanup: () => void;
}

/**
 * 解码图片。
 * 优先 createImageBitmap（自动按 EXIF 摆正方向，安卓/iPhone 竖拍不会躺倒），
 * 旧安卓 WebView 不支持时回退 <img>。
 */
async function decodeImage(file: File): Promise<DecodedImage> {
  if (typeof createImageBitmap === 'function') {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
      return {
        source: bitmap,
        width: bitmap.width,
        height: bitmap.height,
        cleanup: () => bitmap.close(),
      };
    } catch {
      // 落到 <img> 回退分支（例如浏览器不支持该编码格式）
    }
  }

  const objectUrl = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const el = new Image();
      el.onload = () => resolve(el);
      el.onerror = () => reject(new Error('图片解码失败'));
      el.src = objectUrl;
    });
    return {
      source: img,
      width: img.naturalWidth,
      height: img.naturalHeight,
      cleanup: () => URL.revokeObjectURL(objectUrl),
    };
  } catch (e) {
    URL.revokeObjectURL(objectUrl);
    throw e;
  }
}

/** 把文件名换成 .jpg 后缀 */
function toJpegName(name: string): string {
  const base = name.replace(/\.[^.]+$/, '') || 'photo';
  return `${base}.jpg`;
}

/**
 * 压缩图片为 JPEG。
 * - 只在能显著减小时替换原文件（压缩结果反而更大时保留原图）
 * - 无法解码时原样返回（后端会给出「仅支持 jpg / png / webp / gif 图片」的提示）
 */
export async function compressImage(file: File, options?: CompressOptions): Promise<File> {
  const { maxEdge, quality } = { ...DEFAULT_OPTIONS, ...options };

  let decoded: DecodedImage;
  try {
    decoded = await decodeImage(file);
  } catch {
    return file;
  }

  try {
    const scale = Math.min(1, maxEdge / Math.max(decoded.width, decoded.height));
    const width = Math.max(1, Math.round(decoded.width * scale));
    const height = Math.max(1, Math.round(decoded.height * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;

    const ctx = canvas.getContext('2d');
    if (!ctx) return file;

    // PNG/WebP 的透明区域转 JPEG 后会发黑，先铺白底
    ctx.fillStyle = designTokens.colors.white;
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(decoded.source, 0, 0, width, height);

    const blob = await new Promise<Blob | null>((resolve) => {
      canvas.toBlob(resolve, 'image/jpeg', quality);
    });
    if (!blob || blob.size >= file.size) return file;

    return new File([blob], toJpegName(file.name), {
      type: 'image/jpeg',
      lastModified: Date.now(),
    });
  } catch {
    return file;
  } finally {
    decoded.cleanup();
  }
}
