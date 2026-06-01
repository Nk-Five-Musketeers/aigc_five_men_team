# Findings & Decisions

## Requirements
- 项目是阿尔兹海默症干预聊天软件。
- 需要实现“预录入数据”功能，目前前后端都未完成。
- 现有界面中有“本地守护”，包含基本信息、家庭照片、重要经历、周围人信息；用户希望去掉这块界面，把它变成一个统一的数据预录入入口。
- 数据预录入模块至少包含四部分：
  - 老人基本信息录入：问卷形式，字段如姓名、年龄、性别、爱好等，尽量详细。
  - 亲属信息录入：问卷形式，字段如姓名、与老人的关系等。
  - 重要经历录入：时间、地点、一段话概括。
  - 照片录入：当前数据库缺少照片信息，需要新增数据库和后端逻辑。
- 问卷字段需要根据现有数据库逻辑产生，提交后必须能存入数据库。
- 用户要求先大致浏览项目整体，并先生成要做事项文档；不清楚的需求需要提问并完善文档。
- 注意：运行 `flutter --version` 等命令可能卡住。
- 目标平台已补充：希望能看到网页效果，Web 预览中照片最好能长期保存；最终会落地为手机软件，但当前最终运行/验收命令是 Windows 桌面双终端：终端 1 设置 `$env:VIVO_APP_KEY=""` 后运行 `python server\local_chat_server.py`，终端 2 运行 `flutter run -d windows`。
- 老人档案数量已确认：预录入模块只管理一位老人档案，不做多老人档案切换。

## Research Findings
- 真正项目根目录是 `D:\桌面\vivo-project\aigc_five_men_team`；外层 `D:\桌面\vivo-project` 还包含独立的 demo 文件 `app.py`、`index.html`、`README.md`。
- `aigc_five_men_team/` 是 Git 仓库，当前分支为 `terryi-new`。
- 当前已有非本轮改动：`pubspec.lock`、`windows/flutter/generated_plugin_registrant.cc`、`windows/flutter/generated_plugins.cmake`。
- Flutter 项目包含 `pubspec.yaml`、`lib/`、`web/`、`windows/`、`test/`。
- Flutter 前端关键目录包括：
  - `lib/main.dart`
  - `lib/ui/screens/home_screen.dart`
  - `lib/data/models/`
  - `lib/data/repositories/`
  - `lib/data/local_db/local_database.dart`
  - `lib/core/api_client.dart`
- 后端/服务相关目录在 `server/`，包含：
  - `database.py`
  - `local_chat_server.py`
  - `populate_tables.py`
  - 多个 SQLite 数据库文件：`elderly_care_auto.db`、`elderly_care_test.db`、`elderly_care_events_test.db`、`elderly_care_daily_test.db`、`nearby_people_test.db`
- 项目还包含若干数据库表结构截图：`老人基本信息表.png`、`亲友表.png`、`经历事件表.png`、`每日生活记录表.png`。
- 外层工作区不是 Git 仓库；`aigc_five_men_team/` 才是 Git 仓库。
- 应用入口为 `lib/main.dart`，通过 `ChangeNotifierProvider` 注入 `ChatProvider`，首页为 `HomeScreen`。
- README 明确：聊天记录与档案使用 SQLite（`sqflite`）保存在本机；桌面端数据库文件为 `bluecare.db`，Web 端为浏览器本地 IndexedDB/OPFS。
- `lib/ui/screens/home_screen.dart` 的设置页存在“本地守护”卡片，包含四行：
  - `基本信息`
  - `家庭照片`
  - `重要经历`
  - `周围人信息`
- 目前只有 `周围人信息` 绑定了入口，会进入 `_NearbyPeopleView`；`基本信息`、`家庭照片`、`重要经历` 只是静态行。
- `_NearbyPeopleView` 现在只支持弹窗添加“周围人”：姓名、关系、联系电话、紧急联系人；写入 `LocalDatabase.upsertNearbyPerson`，表是 `nearby_people`。
- Flutter 本地数据库版本为 `_dbVersion = 5`，核心表包括：
  - `users`：老人/使用者基本信息，已有字段 `name`、`avatar_path`、`metadata`、`birth_year`、`hometown`、`career`、`hobbies`、`food_preference`、`personality`、`taboo`、`dialect`。
  - `family_members`：家庭成员，已有字段 `owner_user_id`、`name`、`relation`、`photo_path`、`birthday`、`location`、`contact_freq`、`notes`、`is_active`。
  - `nearby_people`：周围人/联系人，已有字段 `owner_user_id`、`name`、`relation`、`phone`、`address`、`note`、`is_emergency_contact`、`distance_meters`、`metadata`。
  - `memory_events`：重要经历，已有字段 `owner_user_id`、`event_time`、`title`、`description`、`location`、`people_involved`、`emotion`、`photo_paths`、`video_path`、`importance`、`source`、`verified`。
  - `attachments`：消息附件，挂在 `messages` 上，不适合直接表示老人档案照片库。
- Flutter 本地数据库已经有这些写入方法可复用：
  - `LocalDatabase.updateUser`
  - `LocalDatabase.insertFamilyMember` / `updateFamilyMember` / `listFamilyMembersForUser`
  - `LocalDatabase.upsertNearbyPerson` / `getNearbyPeopleForUser` / `removeNearbyPerson`
  - `LocalDatabase.insertMemoryEvent` / `updateMemoryEvent` / `listMemoryEventsForUser`
- 聊天抽取逻辑 `chat_repository.dart` 已经把大模型抽取结果映射到 `elder_profile`、`family_members`、`memory_events`、`daily_life`；新建问卷字段应尽量沿用这些 key，避免生成另一套不兼容结构。
- `nearby_people` 逻辑核对：
  - `chat_repository.dart` 的抽取结果中，`people` 是“对话中出现的他人”，会解析为 `ExtractedRelationHint`。
  - `ExtractedRelationHint` 注释明确写着“周围人一条线索，用于写入 `nearby_people`”。
  - `ChatProvider._applyExtractedHint` 会把 `people` 线索写入/更新 `nearby_people`。
  - `relation_conflicts` 关联 `nearby_people`，用于“原有人物信息”和“新提到信息”不一致时让用户选择保留原有或采用新信息；采用新信息时只更新 `nearby_people`。
  - 因此 `nearby_people` 在现有代码中确实承担“人物关系候选/缓冲/待确认层”的角色。
  - 但当前代码没有发现自动把 `nearby_people` 晋升或分发到 `family_members`、`users`、`memory_events` 的逻辑。
  - `family_members` 目前是另一条独立路径：LLM 输出 `family_members` 后，`ChatProvider._applyExtractedFamilyMembers` 会直接写入 `family_members`。
  - 结论：用户理解的“先进入 `nearby_people`，再根据合理性进入其他地方”是更合理的产品/数据流目标，但现有实现尚未完整打通晋升流程。
- 重要经历照片已有 `memory_events.photo_paths` 字段；亲属照片已有 `family_members.photo_path`；老人头像已有 `users.avatar_path`。但缺少“家庭照片/照片库”的独立照片表，因此用户说的“数据库缺乏照片信息”在 Flutter 主库中可以理解为缺少可管理的通用照片档案表。
- Python `server/database.py` 也有 `users.avatar_path` 和 `life_events.photo_paths`，但表名与 Flutter 主库不同（如 `life_events` vs `memory_events`）。除非后续确认需要后端 API 持久化，否则优先以 Flutter `LocalDatabase` 为实际落库目标。
- `aigc_five_men_team/server/local_chat_server.py` 只有 `/health` 和 `/api/chat`；没有档案、亲属、经历或照片的 HTTP API。
- 外层工作区的 `app.py` 是另一个 vivo chat/video demo 代理，包含 `/api/chat`、`/api/video/submit`、`/api/video/query`，与 Flutter 档案本地库不直接相连。
- 因此“预录入数据”的后端工作，在当前架构下更准确地说是 Flutter 数据层/SQLite schema、migration、repository/helper 方法，而不是新增 Python HTTP 接口；除非后续明确要求外部服务也能读写这些档案。
- 表结构截图确认：
  - 表1“老人基本信息表”字段包含 `id`、`name`、`birth_year`、`hometown`、`career`、`hobbies`、`food_preference`、`personality`、`taboo`、`dialect`、`avatar_path`、`created_at`。
  - 表2“家庭成员表”字段包含 `id`、`name`、`relation`、`photo_path`、`birthday`、`location`、`contact_freq`、`notes`、`is_active`。
  - 表3“记忆事件库（核心表）”字段包含 `id`、`event_time`、`title`、`description`、`location`、`people_involved`、`emotion`、`photo_paths`、`video_path`、`importance`、`source`、`verified`、`used_count`、`last_used`。
  - 表5“每日生活记录表”字段包含 `id`、`date`、`breakfast`、`lunch`、`dinner`、`activities`、`people_met`、`places_went`、`mood`、`raw_extract`、`source_dialog`。
  - 项目中没有发现“表4：照片表”截图；这进一步说明照片库/家庭照片模块还缺数据库结构。

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| 探索阶段避免运行 `flutter --version` | 用户提醒该命令可能卡住，先通过文件结构判断技术栈 |
| 数据预录入优先落到 Flutter 本地 SQLite `LocalDatabase` | README 与现有 UI/Provider 都围绕本地 `bluecare.db`，并已有模型与写入方法 |
| 照片建议新增独立表，而不是只塞进 `users.metadata` | 已有头像/亲属单图/经历多图字段，但没有可列表管理、分类、说明和关联的通用照片档案 |
| 暂不把预录入设计成 Python HTTP 接口 | 当前本地代理只处理聊天转发；Flutter 已能直接写本地 SQLite，新增 HTTP 层会增加同步与一致性复杂度 |
| 照片采用“复制到应用数据目录 + SQLite 保存稳定路径” | 用户已确认；能降低原始路径失效风险，并避免把图片二进制直接存入数据库 |
| 平台策略为移动端优先 + Web 预览 | 用户希望能看网页效果，最终会落地为手机软件；后续界面和依赖选择要避免 Windows-only 实现 |
| Web 预览照片最好长期保存 | 用户已确认；Web 没有普通文件路径长期访问能力，后续设计需为 Web 单独使用浏览器本地持久化策略 |
| 单老人档案模式 | 用户已确认；保留数据库 `owner_user_id` 是为了兼容现有结构，但新预录入 UI 不暴露多使用者管理 |
| `nearby_people` 作为人物关系缓冲层 | 代码已体现其候选/冲突确认作用；后续预录入应补上从缓冲层确认后同步到正式表的流程 |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| 初次在外层工作区运行 Git，提示不是 Git 仓库 | 用户提醒后切换到 `aigc_five_men_team/`，确认分支为 `terryi-new` |

## Resources
- 项目根目录：`D:\桌面\vivo-project\aigc_five_men_team`
- 外层工作区：`D:\桌面\vivo-project`
- Python/SQLite 服务目录：`D:\桌面\vivo-project\aigc_five_men_team\server`
- 主界面文件：`D:\桌面\vivo-project\aigc_five_men_team\lib\ui\screens\home_screen.dart`
- 本地数据库文件：`D:\桌面\vivo-project\aigc_five_men_team\lib\data\local_db\local_database.dart`
- 聊天状态与抽取应用：`D:\桌面\vivo-project\aigc_five_men_team\lib\logic\chat_provider.dart`
- 抽取结构定义：`D:\桌面\vivo-project\aigc_five_men_team\lib\data\repositories\chat_repository.dart`
- 本地聊天代理：`D:\桌面\vivo-project\aigc_five_men_team\server\local_chat_server.py`
- 最终运行/验收命令：
  - 终端 1：先设置 `$env:VIVO_APP_KEY=""`，再执行 `python server\local_chat_server.py`
  - 终端 2：执行 `flutter run -d windows`
- 规划文件：`task_plan.md`
- 发现记录：`findings.md`
- 进度日志：`progress.md`

## Visual/Browser Findings
- 已查看 `老人基本信息表.png`、`亲友表.png`、`经历事件表.png`、`每日生活记录表.png`。截图中的字段与 Flutter `LocalDatabase` 大体一致，但缺少独立照片表。

## Implementation Findings
- 预录入数据落库点仍以 Flutter 本地 SQLite 为准，Python `server/local_chat_server.py` 未新增档案 API。
- `profile_photos` 已作为统一照片表加入本地库，承担老人头像、家庭照片、经历照片、日常照片等可列表管理的照片档案。
- `nearby_people` 现在继续作为人物候选/缓冲层；新增确认动作后，会同步到 `family_members` 并记录 `family_member_id` 与确认 metadata。
- 旧默认用户初始化曾使用 `ConflictAlgorithm.replace`，会有覆盖已录入档案的风险；已改为 `ignore`，避免应用启动时清空预录入字段。
- 当前照片交互已接入官方 `file_selector`，桌面/移动端选择图片后复制到应用数据目录；Web 端选择图片后以 data URI 写入 SQLite Web/IndexedDB，并用 `storage_type = web_local` 区分。

## 语音朗读 TTS 调研（2026-05-31）
- 用户提供的官方 DOCX：`D:\桌面\新建 DOCX 文档 (2).docx`，文档标题为“音频生成”，标注更新时间 `2026-04-22 06:01:19`。
- 该文档描述的是 vivo 在线语音合成流式 API，不是 Flutter 端系统 TTS：
  - WebSocket 地址：`wss://api-ai.vivo.com.cn/tts`
  - 请求协议：`wss`
  - 响应：JSON
  - 音频：`24KHz`、`16bit`、单通道；文档主流程使用 PCM。
- WebSocket 握手鉴权：
  - Header `Authorization: Bearer AppKey`
  - 文档参数表还列出 `X-AI-GATEWAY-SIGNATURE: developers-aigc`
  - URL 必填参数：`engineid`、`system_time`、`user_id`、`model`、`product`、`package`、`client_version`、`system_version`、`sdk_version`、`android_version`、`requestId`
  - 官方 Python 示例只显式传 `Authorization`，并额外传了 `vaid`；文档表格与示例存在少量差异，实施时需要用真实密钥联调确认。
- 对话朗读推荐引擎：`short_audio_synthesis_jovi`。文档说明短音频合成适用于对话合成/语音助手；长文本屏幕朗读可用 `long_audio_synthesis_screen`。
- 文本合成 JSON 请求字段：
  - `aue`: `0` PCM，`1` Opus
  - `auf`: `audio/L16;rate=24000`
  - `vcn`: 发音人
  - `speed`: 可选 `[0-100]`，默认 `50`
  - `volume`: 可选 `[1-100]`，默认 `50`
  - `text`: UTF-8 文本 Base64；Base64 前最大 `2048` 字节
  - `encoding`: `utf8`
  - `reqId`: 请求 ID
- 推荐初始音色：短音频引擎可用 `vivoHelper`（奕雯）、`yunye`（云野-温柔）、`wanqing`、`xiaofu`、`yige_child`、`yige`、`yiyi`、`xiaoming`。面向老人陪伴场景，优先考虑 `yunye` 或 `vivoHelper`，最终由用户确认。
- 流式响应字段：
  - `error_code == 0` 表示成功
  - `data.audio` 为 Base64 音频片段
  - `data.status`: `0` 第一帧，`1` 合成中，`2` 最后一帧
  - `data.slice` 帧序号，`data.progress` 合成进度
  - 官方示例持续拼接 PCM 片段，结束后封装为 WAV：单声道、16bit、24000Hz。
- 当前项目已有 ASR，但没有 TTS：
  - Flutter 端已有 `lib/core/voice_input/`：默认 vivo ASR，失败回退系统 `speech_to_text`。
  - Python 代理已有 `/api/asr/transcribe` 与 `/api/speech/polish`，可新增并行的 `/api/tts/synthesize`。
  - 当前依赖中没有音频播放库；TTS 接入需要补充跨 Windows / Android / Web 的播放方案。
  - 对话 UI 渲染入口在 `lib/ui/screens/home_screen.dart` 的 `_ChatMessageView`、`_MessageBubble`、`_PromptCard`、`_ChatPhotoBubble`，适合在拾忆回复旁增加朗读按钮，并维护单一播放状态。
- 推荐沿用已有 ASR 本地代理架构：Flutter 通过 `/api/tts/synthesize` 提交文本，Python 代理连接 Vivo TTS WebSocket，把 PCM 分片包装为 WAV 后返回。
- Flutter 播放层建议采用 `audioplayers`。其官方 pub.dev 页面说明支持 Android、iOS、Linux、macOS、Web、Windows；`BytesSource` 可以直接播放内存字节，适合本项目的 WAV 响应。
- 推荐第一版仅为“拾忆”的文字回复提供点击朗读，不自动播放；同一时间只播放一条消息，并对合成结果做内存缓存。
- 已新增独立设计文档 `tts_read_aloud_plan.md`，包含接口契约、文件级修改清单、验证方案和待确认事项。
- 用户已确认首版产品边界：仅朗读“拾忆”回复、仅点击播放、默认音色 `yunye`、设置页开放语速和音量调节，默认值均为 `50`。
- 用户提供 Vivo `APP_ID=2026594139`。现有 AppKey 是否开通 TTS 权限，以及线上实际是否要求 `APP_ID`，留待最小化真实请求确认。
- 用户确认 TTS 工作直接在当前 `main` 分支继续。第一版先完成 Windows 双终端验收，代码结构保持 Android / Web 可复用。

## 语音朗读 TTS 实施结果（2026-05-31）
- Python 新增 `server/speech_synthesis.py`：支持 `2048` UTF-8 字节安全切分、Vivo WebSocket 握手、PCM 分片拼接和单声道 16bit 24000Hz WAV 封装。
- Python 新增 `server/tts_http.py` 和 `/api/tts/synthesize`：默认 `voice=yunye`、`speed=50`、`volume=50`，参数错误返回 400，上游 TTS 错误返回 502。
- `/health` 新增 `vivo_tts` 和 `vivo_tts_app_id`；未配置 AppKey 的本地探测返回 `vivo_tts=false` 和默认 `APP_ID=2026594139`。
- Flutter 新增 `lib/core/voice_output/` 与 `VoiceOutputProvider`：Dio 请求 WAV、`audioplayers` 播放内存字节、同一时间单条播放、重复点击停止、切换回复停止上一条、文本与参数组合缓存。
- 朗读设置使用 `shared_preferences` 持久化；设置页开放朗读语速和音量，默认均为 `50`。
- 聊天界面只为拾忆的非错误回复显示朗读按钮；不会自动朗读，老人消息不显示按钮。
- 已安装 Python `websocket-client 1.9.0`。旧 pip 需要把 HTTP/HTTPS/ALL 代理统一临时设为 `http://127.0.0.1:7898` 后才能完成安装。
- 尚未进行真实 Vivo TTS 上游联调：当前会话没有填入有效 `VIVO_APP_KEY`。需用真实密钥确认 TTS 权限、签名 Header 和 `vaid=APP_ID` 组合。
- Web Debug 构建已通过，静态服务探测 `index.html` 与 `main.dart.js` 均为 HTTP 200。内置浏览器连接持续超时，因此本轮没有完成网页截图与手动点击验收。
