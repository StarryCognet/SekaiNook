/**
 * 图片上传 API —— 通过 Cloudflare Pages Functions 上传到 R2。
 * 前端部署到 Cloudflare Pages 后，/api/upload 由 Pages Functions 处理，
 * 直接访问绑定的 R2 bucket（绑定名 STARRYMIKU_BUCKET）。
 *
 * 注意：这里是 src/api 下唯一直接用 fetch 的地方 —— 请求体是图片 Blob 二进制，
 * 不是 JSON，不能走 http.ts 的序列化通道（见 .trae/rules/project_rules.md）。
 */

import { ApiError } from './http';

/** 上传结果 */
export interface UploadResult {
  url: string;
  key: string;
}

/**
 * 上传图片到 Cloudflare R2（通过 Pages Functions）。
 * @param file 图片文件（来自相机或相册，建议先用 utils/image.ts 压缩）
 * @returns 上传成功返回 { url, key }
 * @throws ApiError 携带后端文案（如「图片不能超过 5MB」「仅支持 jpg / png / webp / gif 图片」）
 */
export async function uploadImage(file: File): Promise<UploadResult> {
  const res = await fetch('/api/upload', {
    method: 'POST',
    headers: {
      'Content-Type': file.type || 'image/jpeg',
    },
    body: file,
  });

  if (!res.ok) {
    // 把后端的 { error } 文案透出来，否则用户只看到「上传失败：413」不知道原因
    let message = `上传失败（${res.status}）`;
    try {
      const data = (await res.json()) as { error?: string };
      if (data?.error) message = data.error;
    } catch {
      // 响应体不是 JSON，保留默认提示
    }
    throw new ApiError(message, res.status);
  }

  const data = (await res.json()) as UploadResult;
  return data;
}
