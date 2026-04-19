# aigc_five_men_team
lib/
├── main.dart                 # App 入口，初始化配置
├── config/                   # 配置中心
│   ├── constants.dart        # 存放 API 地址、模型名称等
│   └── theme.dart            # 你们设计的“暖心大按钮”UI 样式主题
├── core/                     # 核心通用工具
│   ├── api_client.dart       # 封装 Dio 请求（对应你提供的蓝心参数表）
│   └── utils/                # 语音处理、权限申请等工具
├── data/                     # 数据层（离线隐私的核心）
│   ├── models/               # 数据模型（如 ChatMessage, MemoryItem）
│   ├── local_db/             # Sqflite 数据库配置（存储老人往事）
│   └── repositories/         # 数据仓库：决定数据是从 API 拿还是从本地拿
├── logic/                    # 业务逻辑层 (推荐使用 Provider)
│   ├── chat_provider.dart    # 控制 AI 对话逻辑
│   └── memory_provider.dart  # 控制往事检索、照片加载逻辑
└── ui/                       # UI 表现层
    ├── screens/              # 完整的页面
    │   ├── home_screen.dart  # 首页（那4个大方块）
    │   ├── chat_screen.dart  # 对话页
    │   └── gallery_screen.dart # 记忆画册页
    └── widgets/              # 可复用的组件
        ├── big_button.dart   # 你们标志性的超大功能按键
        └── chat_bubble.dart  # 适配大字体的气泡
