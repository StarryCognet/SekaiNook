/**
 * R2 兼容层：把 Cloudflare R2 的最小契约映射到本地文件系统。
 *
 * 只实现 `functions/` 里实际用到的四个方法（逐条对照过调用点）：
 *   get(key)                        —— functions/api/images/[[key]].ts
 *     用到 body / httpMetadata.contentType / httpEtag / writeHttpMetadata()
 *   put(key, body, { httpMetadata }) —— functions/api/upload.ts
 *   delete(key | key[])             —— ledger 删记录、orphans 批量清理
 *   list({ prefix, limit, cursor }) —— functions/api/maintenance/orphans.ts，靠 truncated+cursor 分页
 *
 * 内容类型存在同名 `.meta.json` 旁挂文件里（R2 本身也只存元数据，不解析文件内容）。
 * `.meta.json` 在 list 时会被过滤掉，不会污染对象列表。
 */
import { createReadStream } from 'node:fs';
import { mkdir, readdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';

interface ObjectMetadata {
  contentType?: string;
}

export interface R2ObjectBody {
  key: string;
  size: number;
  uploaded: Date;
  httpEtag: string;
  httpMetadata: ObjectMetadata;
  body: ReadableStream;
  writeHttpMetadata(headers: Headers): void;
}

function assertKey(key: string): void {
  if (!key || key.startsWith('/') || key.includes('..') || key.includes('\0')) {
    throw new Error(`非法的对象 key: ${key}`);
  }
}

export function createR2Bucket(root: string) {
  const base = path.resolve(root);

  /** 递归列出 prefix 下的所有 key（按字典序，结果稳定，cursor 才能可靠分页） */
  async function listKeys(prefix: string): Promise<string[]> {
    const keys: string[] = [];
    const walk = async (dir: string): Promise<void> => {
      let entries;
      try {
        entries = await readdir(dir, { withFileTypes: true });
      } catch {
        return;
      }
      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          await walk(full);
        } else if (entry.isFile() && !entry.name.endsWith('.meta.json')) {
          const key = path.relative(base, full).split(path.sep).join('/');
          if (!prefix || key.startsWith(prefix)) keys.push(key);
        }
      }
    };
    await walk(base);
    keys.sort();
    return keys;
  }

  return {
    async get(key: string): Promise<R2ObjectBody | null> {
      assertKey(key);
      const file = path.join(base, key);
      let info;
      try {
        info = await stat(file);
      } catch {
        return null;
      }
      if (!info.isFile()) return null;

      let metadata: ObjectMetadata = {};
      try {
        metadata = JSON.parse(await readFile(`${file}.meta.json`, 'utf8')) as ObjectMetadata;
      } catch {
        metadata = {};
      }

      const body = Readable.toWeb(createReadStream(file)) as unknown as ReadableStream;
      return {
        key,
        size: info.size,
        uploaded: info.mtime,
        // 与 R2 的 ETag 形态保持同样的引号包裹，响应头里直接用
        httpEtag: `"${info.size.toString(16)}-${Math.floor(info.mtimeMs).toString(16)}"`,
        httpMetadata: metadata,
        body,
        writeHttpMetadata(headers: Headers) {
          if (metadata.contentType) headers.set('Content-Type', metadata.contentType);
        },
      };
    },

    async put(
      key: string,
      value: ArrayBuffer | Uint8Array | string,
      options?: { httpMetadata?: ObjectMetadata }
    ): Promise<void> {
      assertKey(key);
      const file = path.join(base, key);
      await mkdir(path.dirname(file), { recursive: true });
      const buffer =
        typeof value === 'string' ? Buffer.from(value) : Buffer.from(value as ArrayBuffer | Uint8Array);
      await writeFile(file, buffer);
      await writeFile(
        `${file}.meta.json`,
        JSON.stringify({ contentType: options?.httpMetadata?.contentType ?? '' })
      );
    },

    async delete(keyOrKeys: string | string[]): Promise<void> {
      const keys = Array.isArray(keyOrKeys) ? keyOrKeys : [keyOrKeys];
      for (const key of keys) {
        assertKey(key);
        const file = path.join(base, key);
        await rm(file, { force: true });
        await rm(`${file}.meta.json`, { force: true });
      }
    },

    async list(options: { prefix?: string; limit?: number; cursor?: string } = {}) {
      const all = await listKeys(options.prefix ?? '');
      const start = options.cursor ? all.indexOf(options.cursor) + 1 : 0;
      const limit = options.limit && options.limit > 0 ? options.limit : 1000;
      const page = all.slice(start, start + limit);
      const truncated = start + limit < all.length;

      const objects = await Promise.all(
        page.map(async (key) => {
          const info = await stat(path.join(base, key));
          return { key, size: info.size, uploaded: info.mtime };
        })
      );

      return {
        objects,
        truncated,
        // R2 的 cursor 是不透明串；这里用「上一页最后一个 key」实现稳定翻页
        cursor: truncated && page.length > 0 ? page[page.length - 1] : undefined,
      };
    },
  };
}
