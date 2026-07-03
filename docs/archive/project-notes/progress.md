# Progress Log

## Session: 2026-05-17

### Phase 1: 项目浏览与现状梳理
- **Status:** in_progress
- **Started:** 2026-05-17
- Actions taken:
  - 读取并应用 `using-superpowers`、`planning-with-files`、`brainstorming`、`writing-plans` 技能说明。
  - 初次在外层工作区检查规划文件和 Git 状态，发现外层不是 Git 仓库。
  - 创建本轮任务的规划文件、发现记录和进度日志。
  - 使用 `rg --files` 和目录列表浏览项目结构。
  - 确认主要实现位于 `aigc_five_men_team/`，前端为 Flutter，后端/数据库相关逻辑位于 `server/`。
  - 定位 `HomeScreen` 中的“本地守护”卡片及四个现有入口。
  - 读取 `LocalDatabase`，确认主数据库已有老人、家庭成员、周围人、重要经历等表和写入方法。
  - 读取 `ChatProvider` 与 `ChatRepository`，确认聊天抽取已有结构化字段，可作为问卷字段命名依据。
  - 查看四张数据库表结构截图，并记录截图字段与代码的对应关系。
  - 检查本地 Python 代理路由，确认 `local_chat_server.py` 只提供 `/health` 和 `/api/chat`。
  - 创建 `data_preentry_todo.md`，整理入口改造、数据库、表单、照片和验证任务。
  - 更新 `task_plan.md`，将 Phase 1 标记完成，Phase 2 标记为需求澄清中，Phase 3 初版文档标记完成。
  - 根据用户提醒切换真正项目根目录到 `D:\桌面\vivo-project\aigc_five_men_team`。
  - 确认当前 Git 分支为 `terryi-new`。
  - 确认已有非本轮改动：`pubspec.lock`、`windows/flutter/generated_plugin_registrant.cc`、`windows/flutter/generated_plugins.cmake`。
  - 将 `task_plan.md`、`findings.md`、`progress.md`、`data_preentry_todo.md` 移入 `aigc_five_men_team/`。
  - 用户确认照片保存策略：选择照片后复制到应用数据目录，SQLite 保存复制后的稳定路径。
  - 更新 `task_plan.md`、`findings.md`、`data_preentry_todo.md`，把照片策略标记为已确认。
  - 用户补充目标平台：希望能看到网页效果，最终落地为手机软件。
  - 更新规划文档，将平台策略调整为移动端优先并保留 Flutter Web 预览能力。
  - 用户补充 Web 预览中照片能长期保存最好，并给出最终运行/验收命令：`$env:VIVO_APP_KEY=""` 后执行 `flutter run -d windows`。
  - 更新规划文档，将 Web 照片持久化标记为浏览器本地长期保存优先，并记录最终运行命令。
  - 用户确认预录入模块只管理一位老人档案。
  - 更新规划文档，将单老人档案作为界面和数据流约束：保留 `owner_user_id` 兼容结构，但不暴露多使用者切换。
  - 根据用户提示核对 `nearby_people` 是否为缓冲层。
  - 读取 `ChatProvider`、`ChatRepository`、`LocalDatabase`、`RelationExtractor`，确认 `people` 线索写入 `nearby_people`，`relation_conflicts` 只更新 `nearby_people`，`family_members` 当前是独立直写路径。
  - 更新规划文档：将 `nearby_people` 定义为人物候选/缓冲层，并把“确认后同步到 `family_members`”列为待实现流程。
  - 用户修正最终运行方式：终端 1 设置 `$env:VIVO_APP_KEY=""` 后运行 `python server\local_chat_server.py`，终端 2 运行 `flutter run -d windows`。
  - 更新规划文档中的最终运行/验收命令为双终端流程。
- Files created/modified:
  - `task_plan.md`（created）
  - `findings.md`（created）
  - `progress.md`（created）
  - `findings.md`（updated：记录项目结构）
  - `progress.md`（updated：记录浏览动作）
  - `findings.md`（updated：记录 UI/数据库/抽取逻辑）
  - `progress.md`（updated：记录关键文件阅读）
  - `findings.md`（updated：记录表结构截图）
  - `progress.md`（updated：记录图片查看）
  - `findings.md`（updated：记录前后端边界）
  - `progress.md`（updated：记录代理路由检查）
  - `data_preentry_todo.md`（created）
  - `task_plan.md`（updated：阶段状态与决策）
  - `progress.md`（updated：记录待办文档创建）
  - `task_plan.md`（moved into project root and updated：记录分支/真实项目根目录）
  - `findings.md`（moved into project root and updated：修正项目根目录/Git 信息）
  - `progress.md`（moved into project root and updated：记录迁移和分支确认）
  - `data_preentry_todo.md`（moved into project root）
  - `task_plan.md`（updated：照片存储策略确认）
  - `findings.md`（updated：照片策略决策）
  - `data_preentry_todo.md`（updated：照片文件处理待办）
  - `progress.md`（updated：记录用户确认）
  - `task_plan.md`（updated：平台策略确认）
  - `findings.md`（updated：平台策略决策）
  - `data_preentry_todo.md`（updated：Web 预览与手机落地要求）
  - `progress.md`（updated：记录平台目标）
  - `task_plan.md`（updated：Web 照片长期保存与最终运行命令）
  - `findings.md`（updated：Web 持久化与运行命令）
  - `data_preentry_todo.md`（updated：Web 本地持久化策略与验收命令）
  - `progress.md`（updated：记录 Web 持久化和运行命令）
  - `task_plan.md`（updated：单老人档案决策）
  - `findings.md`（updated：单老人档案决策）
  - `data_preentry_todo.md`（updated：隐藏多使用者切换任务）
  - `progress.md`（updated：记录单老人确认）
  - `findings.md`（updated：记录 nearby_people 缓冲层核对结果）
  - `data_preentry_todo.md`（updated：亲属与周围人缓冲/确认流程）
  - `task_plan.md`（updated：人物缓冲层决策与搜索错误）
  - `progress.md`（updated：记录 nearby_people 逻辑核对）
  - `task_plan.md`（updated：最终双终端运行命令）
  - `findings.md`（updated：最终双终端运行命令）
  - `data_preentry_todo.md`（updated：最终双终端验收步骤）
  - `progress.md`（updated：记录命令修正）

## Test Results
| Test | Input | Expected | Actual | Status |
|------|-------|----------|--------|--------|
| 规划文件存在性检查 | `Test-Path` | 三个规划文件尚不存在 | 均为 `False` | done |

## Error Log
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-05-17 | 在外层目录运行 `git status --short` 报错：当前目录不是 Git 仓库 | 1 | 用户确认项目位于 `aigc_five_men_team`，已切换并确认分支 `terryi-new` |
| 2026-05-17 | 从外层移动规划文档到项目目录时 `Move-Item` 被拒绝访问 | 1 | 按沙箱规则请求授权后移动成功 |
| 2026-05-17 | 初次 `rg` 搜索包含 `|` 的正则时被 PowerShell 误解析 | 1 | 改用单引号包住正则后成功搜索 |

## 5-Question Reboot Check
| Question | Answer |
|----------|--------|
| Where am I? | Phase 2：需求澄清与设计边界 |
| Where am I going? | 先摸清项目现状，再生成详细待办与问题清单，用户确认后再实施 |
| What's the goal? | 把现有“本地守护”入口改造成数据预录入模块，并形成可落地的前后端、数据库实现计划 |
| What have I learned? | 最终运行需双终端：先启动 `server\local_chat_server.py`，再运行 `flutter run -d windows` |
| What have I done? | 创建并迁移规划文档到项目根目录，并记录照片复制到应用数据目录的确认决策 |

### Phase 4: 实现阶段
- **Status:** completed
- Actions taken:
  - 新增照片档案模型 `ProfilePhotoModel` 与枚举，覆盖 `file_path` / `web_local`、照片分类、说明、拍摄时间地点、关联亲属/经历、重点照片和 metadata。
  - 新增 `PreEntryMapper`，固化 `nearby_people` 候选记录晋升为 `family_members` 的字段映射。
  - 将 Flutter 本地 SQLite 版本升到 6，新增 `profile_photos` 表和索引。
  - 给 `users` 补充 `gender`、`current_address`、`care_notes`、`medical_notes` 字段。
  - 给 `nearby_people` 补充照片、生日、地点、联系频率、是否仍常联系、`family_member_id` 等预录入字段。
  - 新增 `LocalDatabase.confirmNearbyPersonAsFamilyMember`，把缓冲层候选确认/同步到正式亲属表，并在候选 metadata 中记录同步结果。
  - 新增照片表 CRUD：`insertProfilePhoto`、`updateProfilePhoto`、`deleteProfilePhoto`、`getProfilePhotoById`、`listProfilePhotosForUser`。
  - 新增 `ProfilePhotoStorage.copyIntoAppStorage`，Windows/桌面端会把输入照片路径复制到数据库同级的 `profile_photos` 目录后再落库。
  - 修正默认用户初始化逻辑，避免每次启动用 `replace` 覆盖已预录入的老人档案。
  - 新增独立页面 `DataPreentryScreen`，包含老人基本信息、亲属候选、重要经历和照片录入四段。
  - 替换设置页入口：隐藏“使用者与数据划分”，移除旧“本地守护”四行，改为统一“数据预录入”入口。
  - 更新聊天记忆摘要，让新增老人字段能进入后续对话 prompt 上下文。
- Verification:
  - `dart.exe analyze ...`：通过，剩余 3 条 `home_screen.dart` 旧有 `withOpacity` info，不影响退出码。
  - `flutter_tools.dart test test\profile_photo_model_test.dart test\pre_entry_mapper_test.dart test\widget_test.dart`：4 项测试全部通过。
  - `flutter_tools.dart build windows --debug`：Windows Debug 构建通过，生成 `build\windows\x64\runner\Debug\aigc_five_men_team.exe`。
  - `flutter_tools.dart build web --debug`：Web Debug 构建通过，生成 `build\web`。

## Session: 2026-05-31

### TTS Phase 1: 官方文档与现有链路调研
- **Status:** completed
- Actions taken:
  - 读取并应用 `planning-with-files` 技能说明，恢复现有 `task_plan.md`、`findings.md`、`progress.md`。
  - 确认当前 Git 分支为 `main`，工作区已有 `theme.dart`、`home_screen.dart`、生成文件和 Claude UI 规划文档等未提交改动；本轮不覆盖这些改动。
  - 读取用户提供的 `D:\桌面\新建 DOCX 文档 (2).docx`，解压并按段落抽取 `word/document.xml`。
  - 确认官方文档为 vivo 在线语音合成流式 WebSocket API，地址 `wss://api-ai.vivo.com.cn/tts`。
  - 梳理鉴权 Header、URL 参数、请求 JSON、短/长文本引擎、短音频音色、PCM 流式返回字段和官方 PCM 转 WAV 示例。
  - 检索项目当前语音链路：Flutter 已有 vivo ASR + 系统听写回退；Python 代理已有 `/api/asr/transcribe` 与 `/api/speech/polish`，但没有 TTS；Flutter 依赖也没有音频播放库。
  - 定位聊天 UI 的消息渲染入口：`_ChatMessageView`、`_MessageBubble`、`_PromptCard`、`_ChatPhotoBubble`。
  - 在 `task_plan.md` 新增 TTS 任务阶段，在 `findings.md` 记录官方文档关键信息。
  - 查询 `audioplayers` 官方 pub.dev 页面，确认其覆盖 Windows、Android、Web，并支持从内存 WAV 字节播放。

### TTS Phase 2: 接入方案与需求确认
- **Status:** completed
- Actions taken:
  - 新增独立方案文档 `tts_read_aloud_plan.md`。
  - 记录首版交互建议、服务端 HTTP 契约、Flutter 播放模块、内存缓存、文件级改动和验证步骤。
- Pending:
  - 用真实 AppKey 联调确认 TTS 权限、`APP_ID` 和签名 Header 的线上要求。
- Confirmed:
  - 仅朗读“拾忆”的回复，不为老人消息显示回听按钮。
  - 仅点击后朗读，不自动播放新回复。
  - 默认音色使用 `yunye`，语速和音量默认均为 `50`。
  - 设置页开放语速和音量调节。
  - 用户提供 `APP_ID=2026594139`。
  - TTS 开发在 `main` 分支继续；首版先完成 Windows 双终端验收，代码结构兼顾 Android / Web。

### TTS Phase 3: 实施计划
- **Status:** completed
- Actions taken:
  - 用户批准方案 A：Python 本地代理完整合成 WAV 后返回 Flutter。
  - 抽取官方 DOCX Python 示例，确认示例读取 `APP_ID` 但没有稳定传出，仅写入固定 `vaid`；实现将使用可覆盖的 `APP_ID=2026594139` 填充 `vaid`，并携带参数表要求的签名 Header。
  - 新增 `docs/superpowers/plans/2026-05-31-chat-read-aloud-tts.md`，按测试驱动方式拆分服务端合成、HTTP 路由、Flutter 播放状态、UI 接入和验证步骤。

### TTS Phase 4: 实施与验证
- **Status:** implemented; pending live AppKey verification
- Implemented:
  - 新增 Python TTS 合成内核、HTTP 参数适配器和 `/api/tts/synthesize` 路由。
  - 新增 `/health` 的 `vivo_tts` 与 `vivo_tts_app_id` 字段。
  - 新增 Flutter TTS repository、播放器封装、设置持久化与 `VoiceOutputProvider`。
  - 拾忆非错误回复下方新增手动朗读按钮；再次点击停止，切换消息时停止旧音频。
  - 设置页新增朗读语速和朗读音量滑块，默认均为 `50`。
  - README 补充 Python 语音依赖、`VIVO_APP_ID` 和 TTS 常见问题。
- Verification:
  - `python -B -m unittest server.test_speech_synthesis server.test_tts_http -v`：8 项通过。
  - 本地代理 `/health`：返回 `vivo_tts=false` 与 `vivo_tts_app_id=2026594139`；未设置密钥时 `/api/tts/synthesize` 返回明确 Missing AppKey 错误。
  - `flutter test`：45 项全部通过。
  - `dart analyze`：仅剩 11 条仓库既有提示，本次新增代码未引入提示。
  - `flutter build windows --debug`：通过，生成 `build\windows\x64\runner\Debug\aigc_five_men_team.exe`。
  - `flutter build web --debug`：通过，生成 `build\web`。
  - 使用本地静态服务探测 Web 产物：`index.html` 与 `main.dart.js` 均返回 HTTP 200；内置浏览器连接持续超时，未能完成截图与点击检查。
- Environment notes:
  - `python -m compileall -q server` 会被既有只读 `server/__pycache__` 阻止覆盖；改用 `PYTHONDONTWRITEBYTECODE=1` 与 `python -B` 完成 Python 验证。
  - 已安装 `websocket-client 1.9.0`。当前机器旧 pip 需要统一单次 HTTP 代理为 `http://127.0.0.1:7898`。
- Remaining:
  - 当前会话没有有效 `VIVO_APP_KEY`，无法执行真实上游语音播放联调。需用实际密钥确认 TTS 权限、签名 Header 和 `vaid=APP_ID`。

### Memory Album Phase 1：回忆图鉴体验升级调研
- **Status:** in_progress
- Actions taken:
  - 读取 `brainstorming`、`frontend-design`、`imagegen` 与 `planning-with-files` 技能说明，本轮按“先设计讨论、后实施”的边界推进。
  - 恢复现有规划文档，确认当前工作区位于 `main`，本地分支落后远端 3 个提交，暂不拉取也不修改业务代码。
  - 定位 `MemoryAlbum` 模型、`MemoryAlbumRepository` 组合逻辑与 `home_screen.dart` 中的图鉴页面入口。
  - 确认现有图鉴已覆盖章节、时间线、照片、视频、家庭提问与逐句朗读段落，不需要从零设计。
  - 用户已同意开启浏览器可视化对照稿；已将 `.superpowers/` 加入 `.gitignore`，避免本地草图进入版本控制。
- Next:
  - 细读当前页面布局与状态切换。
  - 启动可视化草图服务，展示 2-3 种图鉴主体验方向。
  - 逐项确认核心受众、主体验和首版边界。
- UI review update:
  - 已确认当前图鉴分为横向照片翻页与纵向听故事两个模式。
  - 已记录主要问题：能力丰富但体验割裂；默认模式缺少章节叙事，朗读模式仍以统一卡片堆叠为主。
  - 下一步将围绕“把两个模式合并为一本可听影集”制作视觉方向草图。
- Visual direction decision:
  - 已在本地浏览器草图页展示 A“可听的人生影集”、B“人生时间轴”、C“家庭共编档案”三个方向。
  - 用户确认以 A 为主体，并吸收 B 和 C 的优点。
  - 下一步确认核心受众优先级，再细化首页布局与朗读交互。
- Audience decision:
  - 用户确认第一优先服务老人本人。
  - 设计约束收敛为：大照片、少操作、明显的一键朗读；家属协作和资料补全退居次级入口。
- Entry decision:
  - 用户确认保留影集封面仪式感。
  - 打开图鉴后先展示真实照片封面、老人姓名和简短副标题，再通过明显按钮进入故事。
- Cover decision:
  - 用户确认封面优先使用重点照片，其次家庭照片，最后回退头像。
  - 实施阶段需要调整当前头像优先的封面选择逻辑。
- Family contribution decision:
  - 用户认可轻量家庭共编：图鉴内只展示待补充提示，点击后跳转既有数据预录入模块。
  - 首版不在图鉴内新增编辑表单，保持观看体验纯粹并控制实现规模。
- Implementation kickoff:
  - 用户批准开始实施。
  - 新增设计说明 `docs/superpowers/specs/2026-05-31-memory-album-experience.md`。
  - 新增实施计划 `docs/superpowers/plans/2026-05-31-memory-album-experience.md`。
  - 本轮沿用用户此前明确批准的 `main` 分支原地开发，不创建额外 worktree。
- Implementation result:
  - 使用测试驱动方式调整封面照片顺序：重点照片、家庭照片、普通非头像照片、头像兜底。
  - 新增影集封面，提供“开始听故事”和“先翻一翻”。
  - 将已有逐句朗读页面作为统一阅读页，加入章节导航条，移除不再需要的朗读状态卡。
  - 新增人生时间线页和轻量家庭补充提示，补充入口跳转既有数据预录入模块。
  - 修正预录入返回来源：从图鉴进入后可以返回图鉴。
  - 调试基线测试时发现 Flutter 与 Python 默认音色约定需要统一；用户最新确认使用 `wanqing`，已同步 Flutter Provider、Flutter TTS 仓库接口、Python 默认值、测试与 README。
- Verification:
  - `flutter test`：53 项全部通过。
  - `dart analyze`：仅剩 11 条仓库既有提示，本轮新增警告已清理。
  - `flutter build windows --debug`：通过，生成 `build\windows\x64\runner\Debug\aigc_five_men_team.exe`。
  - `flutter build web --debug`：通过，生成 `build\web`。
  - 实际 Flutter Web 预览服务：`http://localhost:8092`。入口、`flutter_bootstrap.js`、`main.dart.js` 均返回 HTTP 200。
  - 内置浏览器自动接管仍然超时，本机无备用 Playwright 模块；需要用户在真实预览中手动确认最终视觉效果。
- Voice selection correction:
  - 用户最新确认默认朗读音色需要使用 `wanqing`。
  - 已统一更新 Flutter `VoiceOutputProvider`、Flutter `TtsSynthesizer` / `TtsRepository`、Python `DEFAULT_VOICE`、默认行为测试与 README。
  - 显式指定 `yunye` 的底层 WebSocket 协议测试仍然保留，用于确认调用者可以覆盖默认音色。
  - `python -B -m unittest server.test_speech_synthesis server.test_tts_http -v`：8 项通过。
  - `flutter test`：53 项全部通过。
  - `dart analyze`：仍仅为 11 条仓库既有提示。
  - `flutter build web --debug`：重新构建通过；`http://localhost:8092` 的入口、`flutter_bootstrap.js`、`main.dart.js` 均返回 HTTP 200。

### Memory Album Phase 4：按验收反馈简化
- **Status:** implementation complete; verification in progress
- Confirmed:
  - 删除图鉴内全部“家里人补充”提示。
  - 图鉴副标题固定为“慢慢翻，也慢慢听”。
  - 朗读只作用于当前故事页，仅点击触发，不自动连续播放。
  - 图鉴朗读复用陪伴页 `/api/tts/synthesize` 链路和 `wanqing` 音色。
- Implemented:
  - 新增 `lib/core/memory_album/memory_album_story_pages.dart`，筛选故事章节、限制正文两句并提供封面照片兜底。
  - 将封面主按钮调整为“开始翻阅”，移除封面上的动态介绍和第二个入口。
  - 将阅读页替换为单页影集：大图、章节、标题、时间地点、短正文和固定底栏。
  - 底栏仅保留上一页、朗读当前故事、下一页；翻页、离页、刷新和进入时间线时停止当前播放。
  - 时间线保留为只读二级页面，删除补充入口。
  - 删除旧条目组件中残留的家庭补充卡片，避免后续误复用。
- Verification so far:
  - 新增测试先按预期失败：缺少 `memory_album_story_pages.dart`。
  - `flutter test test\memory_album_story_pages_test.dart`：2 项通过。
  - `flutter test test\memory_album_repository_test.dart`：7 项通过。
  - 图鉴、仓库、朗读 Provider 和朗读 UI 聚焦测试：18 项全部通过。
  - `git diff --check`：通过，仅显示 Windows 行尾提示。
  - `python -B -m unittest server.test_speech_synthesis server.test_tts_http -v`：8 项全部通过。
  - `flutter test`：55 项全部通过。
  - `dart analyze`：无编译错误；剩余 14 条提示，其中 11 条为仓库既有提示，3 条为旧版不可达朗读组件的未引用警告。
  - `flutter build windows --debug`：通过，生成 `build\windows\x64\runner\Debug\aigc_five_men_team.exe`。
  - `flutter build web --debug`：通过，生成 `build\web`。
  - `http://localhost:8092/`、`flutter_bootstrap.js` 与 `main.dart.js` 均返回 HTTP 200。
  - 内置浏览器自动连接连续两次超时，无法完成截图级视觉验收。人工预览地址保持为 `http://localhost:8092/`。
