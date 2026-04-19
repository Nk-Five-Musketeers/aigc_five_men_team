# aigc_five_men_team
lib/
├── main.dart                 # App 入口：负责全局初始化（API Key、数据库、Provider 绑定）
├── config/                   # 配置中心
│   ├── constants.dart        # 环境变量：存放蓝心大模型 API 地址、模型 ID (Volc-DeepSeek-V3.2)
│   └── theme.dart            # 全局样式：定义“暖心大按钮”配色、超大字体规范 (30sp+)
├── core/                     # 核心工具 (Core)
│   ├── api_client.dart       # 网络封装：基于 Dio 封装蓝心 API 请求（处理 Header 与签名）
│   └── utils/                # 通用工具：语音转文字 (ASR)、权限申请、日期处理
├── data/                     # 数据层 (Data)
│   ├── models/               # 数据模型：定义 ChatMessage, StoryItem 等 JSON 解析类
│   ├── local_db/             # 本地数据库：Sqflite 存储逻辑，实现“往事记忆”隐私不出本地
│   └── repositories/         # 数据仓库：逻辑中转站，决定从 API 还是从本地 DB 读取数据
├── logic/                    # 业务逻辑 (Logic/Provider)
│   ├── chat_provider.dart    # AI 对话：控制聊天状态、流式回复接收、System Prompt 拼接
│   └── memory_provider.dart  # 记忆管理：控制往事检索、老照片加载逻辑
└── ui/                       # UI 表现层 (Presentation)
    ├── screens/              # 页面级组件
    │   ├── home_screen.dart  # 首页：核心 4 宫格“暖心大按钮”布局
    │   ├── chat_screen.dart  # 对话页：大字体、语音波纹动画交互界面
    │   └── gallery_screen.dart # 记忆画册：单卡片流式展示老照片与 AI 故事
    └── widgets/              # 可复用小零件
        ├── big_button.dart   # 自定义组件：带震动反馈和高对比度的超大按键
        └── chat_bubble.dart  # 自定义组件：适配老年人阅读习惯的单侧大气泡
