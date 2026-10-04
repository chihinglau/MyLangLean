---
name: podcast-crawl-transcribe
description: Run the MyLangLean podcast pipeline including crawl, source-language faster-whisper transcription with watchdog download, and approval that publishes audio and subtitles together. Use when asked to crawl, transcribe, approve, or verify podcast episodes and subtitles. Do not use for local subtitle-studio media or one-off transcription requests.
---

# 播客抓取 → 源语言识别 → 审批同步

按以下顺序执行，全程零人工干预。核心铁律：**字幕必须来自音频的真实 faster-whisper 转写，禁止 stub 或改写文本；字幕语言必须与单集 language 一致（de/en/fr/ja 各自对应）。**

## 1. 前置检查

- `GET http://127.0.0.1:8000/health` 确认服务存活且 `asr_backend=faster_whisper`。
- 管理接口统一带头：`X-Admin-Token: dev-admin-token`。
- 若服务是 stub 或未启动，按第 2 步启动；抓取/任务为进程内存态，**改了 asr.py / crawler.py / translate.py 必须重启 uvicorn 才生效**。

## 2. 启动真实后端（PowerShell 后台）

工作区根：`d:\ai\prj\trae\HuaWei\MyLangLean`，cwd 必须是 `server\`。

```powershell
$root='d:\ai\prj\trae\HuaWei\MyLangLean'
$env:HF_HOME="$root\.tools\hf-cache"
$env:MLL_ASR_BACKEND='faster_whisper'
$env:MLL_ASR_MODEL='small'                 # 慢速 CDN 时可先 tiny；质量验收用 small
$env:MLL_TRANSLATE_BACKEND='mymemory'
$env:MLL_CRAWL_MAX_EPISODES='3'            # podigee 等慢源降到 '1'
$env:MLL_ASR_DOWNLOAD_DEADLINE_SEC='120'   # podigee 慢源用 '480'
Set-Location "$root\server"
& "$root\.tools\venvs\mll\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

真机联动另开 shell：`.tools\android-sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000`。

## 3. 触发抓取并轮询

```powershell
$h=@{'X-Admin-Token'='dev-admin-token'}
# 触发（wait 默认 false，立即返回 job）
Invoke-RestMethod 'http://127.0.0.1:8000/api/v1/admin/crawl/run' -Method Post -Headers $h `
  -Body (@{sourceIds=@('<sourceId>')}|ConvertTo-Json) -ContentType 'application/json'
# 轮询（注意路径是 jobs 不是 tasks）
Invoke-RestMethod 'http://127.0.0.1:8000/api/v1/admin/crawl/jobs/<jobId>' -Headers $h
# 结束态：status=ok，看 sourcesOk / candidatesNew；message 含失败原因
```

抓取时 `_enrich_with_subtitles()` 仅在 content_hash 变化时逐集识别，单集 try/except 独立降级（失败集不带字幕、不拖批）。识别速度 small/CPU/int8 ≈6.7x 实时，**瓶颈是 PC→CDN 下载，不要误判为识别卡死**——用 Python 进程 CPU 是否增长区分：下载卡死 CPU 不动，识别中 CPU 持续增长。

## 4. 校验候选（审批前必做）

```powershell
$cands=(Invoke-RestMethod 'http://127.0.0.1:8000/api/v1/admin/crawl/candidates?status=pending' -Headers $h).items
```

逐集核对 `episodes[].transcript`：
- `language` 必须等于订阅源语言（de/en/fr/ja）；
- `segments[0].text` 必须是该语种真实文字（德语 "Hallo…"、法语 "Bonjour…"、英语 "Excuse me…"、日语假名/汉字）；
- 中文译文统计：`($segments | Where-Object {$_.translation}).Count`；缺失是翻译额度问题，不阻塞源语言字幕；
- 无 transcript 的单集查 job message，多为下载看门狗超时，可重抓或调大 `MLL_ASR_DOWNLOAD_DEADLINE_SEC`。

## 5. 审批发布 + 目录验证

```powershell
foreach($c in $cands){
  Invoke-RestMethod "http://127.0.0.1:8000/api/v1/admin/crawl/candidates/$($c.id)/approve" `
    -Method Post -Headers $h -Body '{"publish":true,"level":"beginner"}' -ContentType 'application/json'
  # 返回 podcast / inserted_episodes / backfilled_transcripts
}
```

发布后验证语音与字幕同源下发：
```powershell
$eps=Invoke-RestMethod "http://127.0.0.1:8000/api/v1/catalog/podcasts/<podcastId>/episodes"
$eps | Where-Object {$_.transcript} | ForEach-Object {$_.transcript.language}  # 应全部一致
```
App 侧命中随单集下发的 transcript 时直接使用，不调转录接口、不扣额度、无"正在生成字幕"等待。

## 6. 故障速查

- **podigee 下载静默卡死 / 0 字节挂起**：httpx read 空闲超时在挂起连接上不生效；asr.py 已用子线程 + `join(deadline)` 硬看门狗（每次尝试独立临时文件，最多 2 次）。慢源设 `MLL_ASR_DOWNLOAD_DEADLINE_SEC=480` 且每源只抓 1 集。
- **blubrry / anchor.fm ConnectTimeout**：放弃；blubrry 包装链由 crawler `_unwrap_blubrry()` 解到源站直链。
- **ausha 403**：必须 UA `Mozilla/5.0`（下载与识别均已带）。
- **MyMemory 额度（quotaFinished / MYMEMORY WARNING）**：匿名约 5k 字符/日，后续集译文缺失；设 `MLL_TRANSLATOR_EMAIL` 提额后重抓。单句失败返回空串、整体失败 pipeline 降级为仅源语言，均不抛异常。
- **播放延时 / 每次点播放都重新缓冲**：目录下发公网 CDN 原链；已由 [AudioCacheProxy.kt](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/AudioCacheProxy.kt) 解决——设备内 127.0.0.1 边播边缓存（`filesDir/audio-cache`，`<key>.part/.cache/.meta`，512MB LRU，seek 超前前缀时直连上游）。排查时 `run-as com.mylanglean.app ls -la files/audio-cache/`，重放后缓存 mtime 应不变。改该文件后需重建 APK。
- **清 stub 假字幕**（特征文本 "Real voices make language feel alive"）：`UPDATE episodes SET transcript_json='' WHERE transcript_json LIKE '%Real voices make language feel alive%'`，再重抓。

## 7. 关键文件

- 识别与下载看门狗：[server/app/services/asr.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/services/asr.py)
- 抓取/解包/逐集 enrich：[server/app/services/crawler.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/services/crawler.py)
- 翻译：[server/app/services/translate.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/services/translate.py)
- 编排流水线：[server/app/services/subtitle_pipeline.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/services/subtitle_pipeline.py)
- 配置项：[server/app/core/config.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/config.py)
- 回归测试（应为 8/8）：`.tools\venvs\mll\Scripts\python.exe server\tests\run_all.py`

Transcript/TranscriptOut 为冻结帧格式，勿改结构。

## 8. （可选）真机零干预验证要点

设备 HBN-AL00，adb id `2MN0224730027764`，锁屏 PIN `001225`，分辨率 1260x2844。
- USB 枚举变 Unknown 时软件无法恢复（非管理员 PnP 操作被拒），请用户重新插拔数据线后继续。
- 播放中 uiautomator dump 报 "could not get idle state"，先暂停播放再 dump。
- 播放器：大播放/暂停钮中心 (630,2579)，关闭 X 中心 (95,234)；勿点底部迷你条 chevron（会重新展开播放器）。
- 发现页逐语种展开卡片点单集，截图用 `screencap -p /sdcard/x.png` 再 pull，验证：音频在播、字幕语种与音频一致、当前词橙色高亮、日/法语含中文译文。
