/**
 * 这个 Worker 的环境变量。
 *
 * 为什么不直接用 `wrangler types` 生成的 Env：那个只包含 wrangler.jsonc 里声明过的绑定，
 * 而 NTFY_TOPIC / REMIND_TOKEN / NTFY_TOKEN 是 secret（故意不写进配置文件），
 * 所以在这里显式声明一份，类型上看得见它们。
 */
export interface ReminderEnv {
  /** D1：和 Pages 项目同一个数据库（database_id 相同） */
  DB: D1Database;
  /** 用哪条通道：webpush | ntfy | bark | webhook；不设就按「配了哪个用哪个」猜 */
  PUSH_CHANNEL?: string;
  /** Web Push 公钥（base64url，65 字节）。**必须和 Pages 项目里那份一模一样** */
  VAPID_PUBLIC_KEY?: string;
  /** Web Push 私钥（base64url，32 字节），secret */
  VAPID_PRIVATE_KEY?: string;
  /** VAPID 联系人：`mailto:` 或 https 地址，推送服务商出问题时用来找你 */
  VAPID_SUBJECT?: string;
  /** 只发给某一侧：parent | child；不设就发给所有订阅过的设备 */
  PUSH_AUDIENCE?: string;
  /** ntfy 服务器地址，默认官方 https://ntfy.sh；自建时改成自己的域名 */
  NTFY_SERVER?: string;
  /** ntfy 主题名。它同时就是「密码」——知道主题名的人都能收到/发出通知 */
  NTFY_TOPIC?: string;
  /** 自建 ntfy 开了鉴权时才需要 */
  NTFY_TOKEN?: string;
  /** Bark 的设备 key（iOS 上装 Bark App 后拿到的那串） */
  BARK_KEY?: string;
  /** Bark 服务器地址，默认官方 https://api.day.app；自建时改 */
  BARK_SERVER?: string;
  /** 通用 webhook 地址（Server酱 / PushDeer / 自建 ntfy / 自己的机器人） */
  PUSH_WEBHOOK_URL?: string;
  /** 通用 webhook 的额外请求头，JSON 字符串，例：{"Authorization":"Bearer xxx"} */
  PUSH_WEBHOOK_HEADERS?: string;
  /** 手动触发接口 /trigger 的令牌，防止公网上的任何人拿它群发通知 */
  REMIND_TOKEN?: string;
  /** 置 '1' 时只计算不发（联调用；也可以用 /trigger?dry=1 单次覆盖） */
  DRY_RUN?: string;
  /** 通知点开后的落地页 */
  APP_URL?: string;
}
