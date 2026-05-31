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
