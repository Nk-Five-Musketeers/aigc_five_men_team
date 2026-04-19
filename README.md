#  BlueCare - 阿尔兹海默症早期陪伴系统

本项目是基于 **Flutter** 和 **蓝心大模型 (BlueLM)** 开发的智慧养老陪伴应用，旨在通过 AIGC 技术为老年人提供情感陪伴、记忆唤醒及安全守护。

---

## 📂 项目目录结构 (Project Architecture)

我们将代码分为四大核心层次，请成员按分工在对应目录开发：

### 1. 核心与配置 (Core & Config)
* `lib/main.dart` - **App 入口**：负责全局初始化（API Key、数据库、Provider 绑定）。
* `lib/config/` - **配置中心**：
    * `constants.dart`：存放 API 地址、模型 ID (`Volc-DeepSeek-V3.2`)。
    * `theme.dart`：定义“暖心大按钮”配色、超大字体规范 (30sp+)。
* `lib/core/` - **核心工具**：
    * `api_client.dart`：封装 Dio 请求（处理蓝心 API Header 与签名）。
    * `utils/`：语音转文字 (ASR)、权限申请、日期处理工具。

### 2. 数据层 (Data - 隐私安全核心)
* `lib/data/models/` - **数据模型**：定义 ChatMessage, StoryItem 等解析类。
* `lib/data/local_db/` - **本地数据库**：Sqflite 存储，实现“往事记忆”隐私不出本地。
* `lib/data/repositories/` - **仓库层**：决定数据是从 API 获取还是本地 DB 读取。

### 3. 业务逻辑层 (Logic - Provider 状态管理)
* `lib/logic/chat_provider.dart` - **AI 对话逻辑**：控制聊天状态、流式回复、System Prompt 拼接。
* `lib/logic/memory_provider.dart` - **记忆管理**：控制往事检索、老照片加载。

### 4. UI 表现层 (UI - 老年人适配)
* `lib/ui/screens/` - **页面级组件**：
    * `home_screen.dart`：首页 4 宫格“暖心大按钮”布局。
    * `chat_screen.dart`：对话页，支持语音波纹交互。
    * `gallery_screen.dart`：记忆画册，单卡片流式展示。
* `lib/ui/widgets/` - **可复用组件**：
    * `big_button.dart`：带震动反馈的高对比度超大按键。
    * `chat_bubble.dart`：适配老年人阅读习惯的单侧气泡。

---
