# Task Plan: 数据预录入模块改造

## Goal
把现有“本地守护”入口改造成阿尔兹海默症干预聊天软件的数据预录入模块，并形成可落地的前后端、数据库实现计划。

## Current Phase
Phase 2

## Phases

### Phase 1: 项目浏览与现状梳理
- [x] 浏览项目结构、启动方式、前后端技术栈
- [x] 定位现有“本地守护”界面
- [x] 定位数据库模型、迁移方式、读写接口
- [x] 把发现写入 `findings.md`
- **Status:** complete

### Phase 2: 需求澄清与设计边界
- [x] 明确老人基本信息问卷字段范围
- [ ] 明确亲属/周围人信息字段范围与是否支持多人
- [ ] 明确重要经历录入字段、数量、展示和编辑方式
- [x] 明确照片录入的存储方式、元数据字段和关联关系
- [x] 列出需要用户确认的问题
- **Status:** in_progress

### Phase 3: 技术方案与实施任务文档
- [x] 根据现有数据库逻辑设计新增/调整的数据结构
- [x] 设计后端接口、校验、错误处理和存储流程
- [x] 设计前端入口、问卷步骤、照片上传和状态反馈
- [x] 写出详细待办清单与验证方式
- **Status:** complete

### Phase 4: 用户确认后实施
- [ ] 移除或替换现有“本地守护”界面入口
- [ ] 实现数据预录入前端流程
- [ ] 实现后端数据写入和照片逻辑
- [ ] 补充必要测试或手动验证流程
- **Status:** pending

### Phase 5: 验证与交付
- [ ] 验证问卷提交后数据能进入数据库
- [ ] 验证照片上传/保存/读取逻辑
- [ ] 验证页面可用性和异常提示
- [ ] 更新文档并交付结果
- **Status:** pending

## Key Questions
1. 照片应保存为本地文件路径、数据库二进制、还是对象存储/URL？（已确认：复制到应用数据目录，数据库保存稳定路径）
2. 目标平台是什么？（已确认：移动端优先，Flutter Web 需要能预览页面效果且照片最好能长期保存；最终验收以 Windows 桌面运行，两终端启动）
3. 老人基本信息是否只有一位老人，还是系统需要支持多位老人档案？（已确认：只管理一位老人档案）
4. 亲属信息是否允许录入多位亲属，是否需要联系方式、生日、提醒偏好等字段？（已核对：`nearby_people` 是人物候选/缓冲层，但当前缺少自动同步到 `family_members` 的完整流程）
5. 重要经历是否需要支持多条记录、照片关联、标签/情绪等信息？
6. 数据预录入入口是否作为独立页面，还是作为首次进入应用的引导流程？

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| 先只生成任务与发现文档，不直接改业务代码 | 用户明确要求先浏览项目并生成要做事项文档，未确认细节前避免实现偏差 |
| 优先把预录入写入 Flutter 本地 SQLite | 当前主应用档案逻辑在 `LocalDatabase`，Python 本地代理只负责聊天转发 |
| 新增独立照片表 `profile_photos` | 现有库只有头像、亲属单图、经历多图字段，缺统一照片库和照片元数据 |
| 照片文件复制到应用数据目录，数据库保存复制后的稳定路径 | 用户已确认；避免原始文件被移动/删除后路径失效，也不把大图片二进制塞进 SQLite |
| UI 与数据录入按移动端优先设计，同时保留 Flutter Web 预览能力 | 用户希望看到网页效果，但最终会落地为手机软件；实现应避免 Windows 专属路径和交互 |
| Web 预览照片尽量做浏览器本地长期保存 | 用户希望长期保存最好；Web 端没有应用数据目录路径语义，需用浏览器本地存储/SQLite Web 方案兜底 |
| 数据预录入模块只管理一位老人档案 | 用户已确认；界面不需要多老人新增/切换，数据库可保留 `owner_user_id` 兼容现有结构 |
| 亲属/周围人录入先进入 `nearby_people` 缓冲层 | 用户指出该表是缓冲层；代码核对显示它承接人物线索和冲突确认，但需要补齐确认后同步正式表的流程 |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| 在外层 `D:\桌面\vivo-project` 运行 `git status --short` 报错：当前目录不是 Git 仓库 | 1 | 用户确认真正项目在 `aigc_five_men_team`；已切换到该目录并确认分支为 `terryi-new` |
| 从外层目录移动规划文档到项目目录时沙箱拒绝访问 | 1 | 按工具规则请求授权后完成移动 |
| 初次 `rg` 搜索 `nearby_people|family_members|...` 时 PowerShell 将管道符误解析 | 1 | 改用单引号包住正则后成功搜索 |

## Notes
- 不运行可能卡住的 `flutter --version`，除非后续确实需要并有替代/超时策略。
- 所有探索发现要同步写入 `findings.md`，阶段进展写入 `progress.md`。
- 详细待办见 `data_preentry_todo.md`。
- 后续所有命令工作目录使用 `D:\桌面\vivo-project\aigc_five_men_team`。
- 当前分支：`terryi-new`。
- 最终运行/验收命令：
  - 终端 1：`$env:VIVO_APP_KEY=""`，然后 `python server\local_chat_server.py`
  - 终端 2：`flutter run -d windows`

## Implementation Update
- Phase 4 已完成：已新增数据预录入页面、入口替换、SQLite v6 schema、照片表与照片复制逻辑、`nearby_people` 确认入 `family_members` 流程。
- 已隐藏设置页多使用者切换与旧“本地守护”四行入口，只保留统一“数据预录入”入口。
- 验证结果：
  - `dart.exe analyze ...` 通过，只有 `home_screen.dart` 既有 `withOpacity` info。
  - `flutter_tools.dart test test\profile_photo_model_test.dart test\pre_entry_mapper_test.dart test\widget_test.dart` 通过，4 项测试全部通过。
  - `flutter_tools.dart build windows --debug` 通过，生成 Windows Debug 可执行文件。
  - `flutter_tools.dart build web --debug` 通过，生成 Web Debug 产物。
- 暂未完成：系统文件选择器插件和 Web 图片二进制长期保存仍保留为后续增强；当前照片录入通过本机路径复制到应用数据目录。
