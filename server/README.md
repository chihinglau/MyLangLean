# MyLangLean 服务端（FastAPI）

PC 端数据与分发中枢：账号注册登录、发现内容（播客/单集）发布、订阅云同步、
Android APK 发布与 OTA 升级检查，并托管零构建的运营管理台。

## 启动

```powershell
# 使用仓库自带 venv（无需安装任何新依赖）
D:\ai\prj\trae\HuaWei\MyLangLean\.tools\venvs\mll\Scripts\python.exe `
  -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

工作目录为 `server/`（或设置 `PYTHONPATH=server`）。真机可用
`adb reverse tcp:8000 tcp:8000` 经 localhost 访问 PC 服务。

- 健康检查：`GET http://127.0.0.1:8000/health`
- 接口文档：`GET /docs`
- 运营管理台：`GET /admin`（单文件原生 HTML/JS，无外网依赖）

## 配置（环境变量，前缀 `MLL_`）

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MLL_DATA_DIR` | `<repo>/server/data` | 数据目录：`mll.db`、`media/`、`releases/` |
| `MLL_ADMIN_TOKEN` | `dev-admin-token` | 管理接口令牌（请求头 `X-Admin-Token`），生产必改 |
| `MLL_JWT_SECRET` | `change-me-in-production` | JWT 签名密钥，生产必改 |
| `MLL_MONTHLY_QUOTA_SEC` | `6000` | 注册用户每月转写额度（秒） |
| `MLL_GUEST_PREVIEW_SEC` | `300` | 游客试听额度（秒） |
| `MLL_CORS_ORIGINS` | `*` | 允许的跨域来源，逗号分隔（如 `https://a.com,http://localhost:5173`）；管理台响应另带 CSP/nosniff/Referrer-Policy/no-store |
| `MLL_ASR_BACKEND` | `stub` | ASR 后端（stub / faster_whisper） |

首次启动自动建表（WAL + 外键）并播种：8 个播客 × 2 个单集（与 App
`MockCatalog` 一致），同时把 `app/assets/audio/sample.mp3` 复制到
`<data_dir>/media/sample.mp3`，经 `GET /media/sample.mp3` 提供播放。
重复启动幂等，不会重复播种。

## API 摘要（业务前缀 `/api/v1`）

账号（`Authorization: Bearer <jwt>`）：

- `POST /auth/device` `{device_id}` 游客登录（持久化游客行）
- `POST /auth/register` `{email, password(>=6), name?}` 注册即发 JWT；重复邮箱 409
- `POST /auth/login` `{email, password}` 未注册/错密 401、禁用 403
- `GET  /me` 当前账号 `{id,email,name,is_guest,created_at}`

公开目录（输出统一 camelCase：feedUrl/artworkUrl/durationMs/pubDate）：

- `GET /catalog/meta` 语言/难度选项与 content_version
- `GET /catalog/podcasts?q=&language=&level=&page=1&size=200`
  （响应含 `content_version`；App 快照缓存为 `{ts,content_version,items}` 信封；
  `q` 中 `\%_` 已转义，LIKE 无通配注入）
- `GET /catalog/podcasts/{id}`
- `GET /catalog/podcasts/{id}/episodes`

仅 `published=1` 的播客对公开接口与 `GET /me/subscriptions` 可见；
管理员经 `/admin/podcasts` 与“查看用户订阅”可看到含下架项的全集。

订阅：

- `GET    /me/subscriptions`
- `PUT    /me/subscriptions/{podcastId}`（幂等；目标缺失/下架 404）
- `DELETE /me/subscriptions/{podcastId}`（幂等 204）

发布与 OTA：

- `GET /releases/latest?platform=android&channel=stable&current=0.4.0%2B4`
  → `{id,has_update,version,build_no,notes,mandatory,size,sha256,url,published_at}`；
  无更新仅返回 `{has_update:false}`。语义版本优先，`current=0.4.1+5`
  形式再按 buildNo 决胜（query 中 `+` 须编码为 `%2B`）。
  `platform` 仅 `android/ohos`、`channel` 仅 `stable/beta/alpha`、
  `current` 必须可解析，否则 **422**（永不返回 5xx）。
- `GET /releases?platform=&channel=` 发布历史
- `GET /releases/download/{id}` APK 文件流，支持 `Range`（206 断点续传）

管理接口（请求头 `X-Admin-Token`，缺失/错误 401）：

- `GET   /admin/users`（含 subscription_count/disabled/created_at）
- `PATCH /admin/users/{id}` body `{disabled?, name?(≤64,超长 422), reset_password?}`
- `GET   /admin/users/{id}/subscriptions`（含已下架播客）
- `GET   /admin/podcasts`（含已下架，管理台上下架按钮的数据源）
- `POST/PUT/PATCH/DELETE /admin/podcasts[/{id}]`（PATCH 常用于上下架）
- `POST   /admin/podcasts/{id}/episodes`、`DELETE /admin/episodes/{id}`
- `POST   /admin/catalog/reseed` 重置为内置目录
- `POST   /admin/releases` multipart：`file`（必须 .apk 否则 400）+
  `platform∈{android,ohos}`/`version(x.y.z)`/`buildNo(≥0)`/`channel∈{stable,beta,alpha}`
  /`notes`/`mandatory`；非法字段一律 **422**。落盘文件名由白名单字段+随机 uuid 构成
  （杜绝路径穿越），服务端流式计算 size 与 SHA-256
- `GET    /admin/releases`、`DELETE /admin/releases/{id}`（删库并连带删除磁盘文件）

保留能力：`GET /discover/proxy`（PodcastIndex 代理，未配凭据 503）、
`/quota`、`/transcriptions[/upload]`、`/translate`、`/score`。

安全基线：密码使用 PBKDF2-HMAC-SHA256（200k 迭代、每用户独立盐，
存储串 `pbkdf2$...`）；SQL 全参数化；JWT payload 缺 `sub` 即 401、禁用账号 403；
上传目录隔离、扩展名白名单 + 字段白名单双重防穿越；游客 `device_id` 服务端模型
白名单 `^[A-Za-z0-9._:\-]{1,128}$`；管理台输出经 HTML 转义（含单引号）并带 CSP；
重复并发注册落库唯一约束冲突时返回 409 中文提示。所有面向 App 的错误 detail 均为中文。

App 侧 OTA 客户端对应实现：每次下载独立会话 token 防并发串写、`.part` 按发布 id
隔离并以 Range 断点续传、落盘后按 `sha256` 校验再替换安装文件、强制更新不可取消。

## 测试

```powershell
# 一键：全部 test_* 模块 + 既有 smoke 冒烟（每模块独立临时 MLL_DATA_DIR）
D:\ai\prj\trae\HuaWei\MyLangLean\.tools\venvs\mll\Scripts\python.exe `
  server\tests\run_all.py

# 单模块直跑
...\python.exe server\tests\test_auth.py

# pytest 形态
...\python.exe -m pytest server\tests
```

全部通过时 `run_all.py` 退出码为 0。
