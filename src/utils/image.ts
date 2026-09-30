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
  /** 取消信号：用户改主意时立刻停手，别再占着主线程 */
  signal?: AbortSignal;
}

const DEFAULT_OPTIONS: Required<Omit<CompressOptions, 'signal'>> = {
  maxEdge: 1600,
  quality: 0.8,
};

/** 取消时统一抛这个形态的错误，调用方用 isAbortError 判断（别弹「上传失败」） */
function throwIfAborted(signal?: AbortSignal): void {
  if (!signal?.aborted) return;
  const error = new Error('已取消');
  error.name = 'AbortError';
  throw error;
}

/** 这次失败是不是「用户主动取消」 */
export function isAbortError(error: unknown): boolean {
  return error instanceof Error && error.name === 'AbortError';
}

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
 *
 * 关键：解码时就把长边缩到 maxEdge —— 4000×3000 的手机原图不再整张进内存，
 * 这是「上传大图时界面冻一下」的主因。竖图按宽缩完可能仍超长边，再用内存里的小图补一次。
 */
async function decodeImage(
  file: File,
  maxEdge: number,
  signal?: AbortSignal
): Promise<DecodedImage> {
  throwIfAborted(signal);
  if (typeof createImageBitmap === 'function') {
    try {
      let bitmap = await createImageBitmap(file, {
        imageOrientation: 'from-image',
        resizeWidth: maxEdge,
        resizeQuality: 'high',
      });
      throwIfAborted(signal);
      // 竖图：按宽缩完后高度仍可能超过 maxEdge，用已经变小了的位图再缩一次（很快）
      if (Math.max(bitmap.width, bitmap.height) > maxEdge) {
        const options: ImageBitmapOptions =
          bitmap.width >= bitmap.height
            ? { resizeWidth: maxEdge, resizeQuality: 'high' }
            : { resizeHeight: maxEdge, resizeQuality: 'high' };
        const shrunk = await createImageBitmap(bitmap, options);
        bitmap.close();
        bitmap = shrunk;
      }
      return {
        source: bitmap,
        width: bitmap.width,
        height: bitmap.height,
        cleanup: () => bitmap.close(),
      };
    } catch (e) {
      if (isAbortError(e)) throw e;
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
    throwIfAborted(signal);
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
  const { maxEdge, quality, signal } = { ...DEFAULT_OPTIONS, ...options };
  throwIfAborted(signal);

  let decoded: DecodedImage;
  try {
    decoded = await decodeImage(file, maxEdge, signal);
  } catch (e) {
    if (isAbortError(e)) throw e; // 用户取消：别把原图当成「压缩结果」传下去
    return file;
  }

  try {
    throwIfAborted(signal);
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
    throwIfAborted(signal);

    const blob = await new Promise<Blob | null>((resolve) => {
      canvas.toBlob(resolve, 'image/jpeg', quality);
    });
    throwIfAborted(signal);
    if (!blob || blob.size >= file.size) return file;

    return new File([blob], toJpegName(file.name), {
      type: 'image/jpeg',
      lastModified: Date.now(),
    });
  } catch (e) {
    if (isAbortError(e)) throw e;
    return file;
  } finally {
    decoded.cleanup();
  }
}
