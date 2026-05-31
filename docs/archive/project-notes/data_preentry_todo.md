# 数据预录入模块待办文档

## 目标
把设置页里的“本地守护”（基本信息、家庭照片、重要经历、周围人信息）改造成一个统一的数据预录入入口。进入后，家属可以按步骤录入老人基本信息、亲属信息、重要经历和照片；提交后的数据要进入现有本地 SQLite 数据库，并能被后续聊天记忆摘要使用。

## 当前项目结论
- 真正项目根目录是 `D:\桌面\vivo-project\aigc_five_men_team`，当前分支是 `terryi-new`。
- 主应用是 Flutter，入口是 `lib/main.dart`，主页面是 `lib/ui/screens/home_screen.dart`。
- 真实档案库在 Flutter 本地 SQLite：`lib/data/local_db/local_database.dart`，数据库名 `bluecare.db`。
- Python 本地代理 `server/local_chat_server.py` 只负责 `/api/chat` 和 `/health`，目前不负责档案落库。
- 外层工作区的 `app.py` 是另一个 demo 代理，与本功能不直接相连。
- 现有“本地守护”位于 `HomeScreen` 设置页中，目前只有“周围人信息”可进入，其余三项是静态行。
- 已有数据表能覆盖大部分问卷：
  - `users`：老人基本信息。
  - `family_members`：家庭成员/亲属。
  - `nearby_people`：周围人/联系人。
  - `memory_events`：重要经历。
  - `attachments`：消息附件，不适合作为家庭照片库。
- 目前缺少独立“照片库”表；已有字段只是头像、亲属单图、经历多图路径。

## 推荐实现边界
- 前端：新增独立的数据预录入页面或视图，不继续把四个入口散落在“本地守护”卡片中。
- 数据层：优先扩展 Flutter `LocalDatabase`，不新增 Python HTTP API，除非明确需要跨进程/跨设备导入档案。
- 照片：新增独立照片表，保存照片路径、分类、说明、时间地点、关联人物或经历等元数据。
- 照片存储策略已确认：选择照片后复制到应用数据目录，SQLite 保存复制后的稳定路径，不保存原始外部路径，也不直接保存图片二进制。
- 平台策略已确认：移动端优先，Flutter Web 需要能预览页面效果，Web 中照片最好能长期保存，最终落地为手机软件。
- 当前最终运行/验收命令已确认：
  - 终端 1：先设置 `$env:VIVO_APP_KEY=""`，再运行 `python server\local_chat_server.py`。
  - 终端 2：运行 `flutter run -d windows`。
- 依赖和交互要优先选择移动端可落地方案，同时保持 Web 页面能打开和展示核心流程。
- 老人档案模式已确认：只管理一位老人档案。界面不提供多老人新增/切换；数据库继续保留 `owner_user_id` 以兼容现有表结构和聊天逻辑。

## 建议问卷字段

### 1. 老人基本信息
优先写入 `users` 表；已有列不足的内容可以先写入 `metadata`，确认后再决定是否升为显式字段。

- 基础身份：姓名、性别、出生年月/年龄、籍贯、现居地。
- 生活背景：职业经历、常住城市、方言习惯。
- 喜好与照护：兴趣爱好、饮食习惯、喜欢的话题、不喜欢/忌讳的话题、性格特点。
- 对话辅助：常用称呼、记忆触发线索、需要避免的表达方式。
- 照片关联：老人头像路径写入 `users.avatar_path`，同时可在照片表中建一条 `category = avatar` 的记录。

可能涉及的数据库调整：
- 复用已有字段：`name`、`avatar_path`、`birth_year`、`hometown`、`career`、`hobbies`、`food_preference`、`personality`、`taboo`、`dialect`、`metadata`。
- 待确认是否新增字段：`gender`、`current_address`、`care_notes`、`medical_notes`。

### 2. 亲属与周围人信息
根据现有逻辑，`nearby_people` 更适合作为人物关系的缓冲/候选层：先录入或抽取到 `nearby_people`，经过家属确认、补全和分类后，再同步到更正式的表，例如亲属进入 `family_members`。当前代码已经有 `nearby_people` 的冲突确认机制，但还没有完整的“确认后晋升到 `family_members`”流程，需要在本模块补齐。

- 姓名。
- 与老人关系。
- 电话/联系方式。
- 生日。
- 居住地/地址。
- 联系频率。
- 是否紧急联系人。
- 是否在世/是否仍常联系。
- 备注：老人对这位亲属的称呼、记忆点、相处提醒。
- 照片：写入亲属照片路径，并在照片表关联 `family_member_id`。

数据库映射：
- 缓冲层 `nearby_people` 已有：`name`、`relation`、`phone`、`address`、`note`、`is_emergency_contact`、`metadata`。
- 正式亲属表 `family_members` 已有：`name`、`relation`、`photo_path`、`birthday`、`location`、`contact_freq`、`notes`、`is_active`。
- `relation_conflicts` 已用于 `nearby_people` 上的信息冲突确认。

### 3. 重要经历
写入 `memory_events`，并尽量沿用聊天抽取逻辑已有字段。

- 事件时间。
- 地点。
- 简短标题。
- 一段话概括/详细描述。
- 涉及人物。
- 情绪/感受。
- 重要程度 1-5。
- 信息来源：家属录入。
- 是否家属确认。
- 关联照片：可选多张，照片路径进入 `photo_paths`，同时在照片表中关联 `memory_event_id`。

数据库映射：
- `memory_events` 已有：`event_time`、`title`、`description`、`location`、`people_involved`、`emotion`、`photo_paths`、`video_path`、`importance`、`source`、`verified`。

### 4. 照片录入
建议新增表 `profile_photos`，用来承载“家庭照片/记忆照片/头像/亲属照片”的统一管理。

建议表结构：

| 字段 | 类型 | 用途 |
|------|------|------|
| `id` | TEXT PRIMARY KEY | 照片 ID |
| `owner_user_id` | TEXT NOT NULL | 所属老人 |
| `file_path` | TEXT NOT NULL | 复制到应用数据目录后的稳定路径 |
| `storage_type` | TEXT | `file_path` / `web_local`，区分端上文件路径与 Web 本地持久化 |
| `category` | TEXT | `avatar` / `family` / `memory` / `daily` / `other` |
| `caption` | TEXT | 照片标题或说明 |
| `photo_time` | TEXT | 拍摄时间或大致年代 |
| `location` | TEXT | 拍摄地点 |
| `people_involved` | TEXT | 照片里的人 |
| `family_member_id` | INTEGER | 可选，关联亲属 |
| `memory_event_id` | INTEGER | 可选，关联经历 |
| `is_favorite` | INTEGER DEFAULT 0 | 是否重点照片 |
| `metadata` | TEXT | 扩展 JSON |
| `created_at` | TEXT | 创建时间 |
| `updated_at` | TEXT | 更新时间 |

## 实施任务清单

### A. 数据库与数据层
- [x] 将 `LocalDatabase._dbVersion` 从 5 升到 6。
- [x] 在 `_createSchema` 中新增 `profile_photos` 表。
- [x] 在 `_upgradeSchema` 的 `oldVersion < 6` 中补建 `profile_photos` 表。
- [x] 新增照片表索引：`owner_user_id`、`category`、`family_member_id`、`memory_event_id`。
- [x] 新增方法：`insertProfilePhoto`、`updateProfilePhoto`、`deleteProfilePhoto`、`listProfilePhotosForUser`。
- [x] 新增 `ProfilePhotoModel`。
- [x] 视需求给 `users` 增加 `gender` 等显式字段，或写入 `metadata`。
- [x] 保留现有 `owner_user_id` / `users.id` 外键结构，但预录入写入固定的当前老人档案，不新增多档案管理逻辑。
- [x] 明确并实现 `nearby_people` 到 `family_members` 的确认/同步方法，例如 `confirmNearbyPersonAsFamilyMember`。
- [x] 同步时保留 `nearby_people` 记录作为来源/缓冲记录，或在 `metadata` 中标记已同步，避免重复晋升。

### B. 前端入口改造
- [x] 修改 `_AppView`，新增数据预录入视图，例如 `preEntry`。
- [x] 在设置页移除“本地守护”四个静态行。
- [x] 增加一个统一入口：“数据预录入”。
- [x] 点击入口进入新的预录入模块。
- [x] 保留“周围人信息”的能力，但移到新模块内部。
- [x] 移除或隐藏设置页中“使用者与数据划分”的新增/切换入口，避免单老人产品中出现多档案概念。

### C. 新预录入界面
- [x] 新建独立文件，例如 `lib/ui/screens/data_preentry_screen.dart`，避免继续撑大 `home_screen.dart`。
- [x] 建立四段式页面：老人信息、亲属信息、重要经历、照片。
- [x] 页面布局按手机屏幕优先设计，并保证 Flutter Web 预览时在窄屏和桌面浏览器中都能正常显示。
- [x] 老人信息支持读取当前唯一老人 `users` 数据并回填表单。
- [x] 亲属与周围人信息先进入候选列表，支持补全、确认、删除或编辑。
- [x] 对明确属于亲属/家人的候选项，提供“确认入亲属表”的动作，同步写入 `family_members`。
- [x] 重要经历支持多条新增、列表展示、删除或编辑。
- [x] 照片支持系统文件选择、填写说明、分类、关联亲属或经历，并复制到应用数据目录。
- [x] 保存后给出成功/失败提示。

### D. 照片文件处理
- [x] 确认照片存储策略：复制到应用数据目录，数据库保存稳定路径。
- [x] 选择或填写本机图片路径后复制到应用数据目录，再把复制后的稳定路径写入数据库。
- [x] 添加移动端优先且 Web 可预览的图片选择/读取依赖，并避免 Windows-only 插件路径。
- [x] 为 Web 预览补充浏览器本地长期保存方案；Web 端可在 SQLite Web/IndexedDB 中保存图片 data URI，并用 `storage_type = web_local` 区分。
- [x] 保存头像时同步更新 `users.avatar_path`。
- [x] 保存亲属照片时同步更新 `family_members.photo_path`。
- [x] 保存经历照片时同步更新 `memory_events.photo_paths`。

### E. 聊天记忆接入
- [x] 更新 `ChatProvider._userProfileSummaryForLlm`，让新增字段能进入老人档案摘要。
- [ ] 如新增照片表，决定聊天摘要是否需要包含重点照片说明。
- [ ] 确保问卷录入的亲属和经历与现有抽取逻辑不会重复冲突。

### F. 验证
- [ ] 手动打开数据预录入入口，完成四部分表单。
- [x] 验证 Flutter Web debug 构建可通过，后续可用 `build\web` 预览页面效果。
- [ ] 手机尺寸视口下检查表单、底部操作、图片选择入口不遮挡。
- [ ] 验证 `users` 中老人信息已更新。
- [ ] 验证 `family_members` / `nearby_people` 中亲属信息已写入。
- [ ] 验证 `memory_events` 中重要经历已写入。
- [ ] 验证 `profile_photos` 中照片记录已写入。
- [ ] 验证头像/亲属/经历照片路径同步到已有字段。
- [ ] 验证重新进入页面后能读出已保存数据。
- [ ] 按最终命令验证 Windows 桌面运行：终端 1 设置 `$env:VIVO_APP_KEY=""` 后运行 `python server\local_chat_server.py`；终端 2 运行 `flutter run -d windows`。
- [ ] 避免直接运行可能卡住的 `flutter --version`；需要 Flutter 命令时使用明确超时策略。

## 待确认问题
1. 照片保存策略：已确认复制到应用数据目录后保存稳定路径。
2. 目标平台：已确认移动端优先，Flutter Web 需要能预览页面效果，最终落地为手机软件。
3. Web 预览中的照片长期保存：已确认“能长期保存最好”，设计为浏览器本地持久化优先。
4. 最终运行/验收命令：已确认两终端启动，终端 1 `$env:VIVO_APP_KEY=""` 后执行 `python server\local_chat_server.py`，终端 2 执行 `flutter run -d windows`。
5. 老人档案：已确认只管理一位老人档案。
6. 亲属和周围人：已核对现有代码，`nearby_people` 是人物候选/缓冲层；待确认是否在预录入模块中实现“确认后同步到 `family_members`”。
7. 老人基本信息是否必须新增“性别、现居地、照护备注、健康注意事项”等显式数据库字段？
8. 照片是否需要在聊天中作为认知提问素材，例如“这张照片里是谁”？
