/// <reference types="vite/client" />

/**
 * 构建标识：由 vite.config.ts 的 define 在构建（含 dev 启动）时注入。
 * 当前用途是给 Service Worker 的注册 URL 加版本参数，见 src/utils/swUpdate.ts。
 */
declare const __BUILD_ID__: string;
