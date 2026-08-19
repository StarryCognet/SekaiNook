/**
 * 图片上传 API —— 通过 Cloudflare Pages Functions 上传到 R2。
 * 前端部署到 Cloudflare Pages 后，/api/upload 由 Pages Functions 处理，
 * 直接访问绑定的 R2 bucket（绑定名 SEKAINOOK_BUCKET）。
 */

/** 上传结果 */
export interface UploadResult {
  url: string;
  key: string;
}

/**
 * 上传图片到 Cloudflare R2（通过 Pages Functions）。
 * @param file 图片文件（来自相机或相册）
 * @returns 上传成功返回 { url, key }
 */
export async function uploadImage(file: File): Promise<UploadResult> {
  const res = await fetch('/api/upload', {
    method: 'POST',
    headers: { 'Content-Type': file.type || 'image/jpeg' },
    body: file,
  });

  if (!res.ok) {
    throw new Error(`上传失败：${res.status}`);
  }

  const data = (await res.json()) as UploadResult;
  return data;
}
