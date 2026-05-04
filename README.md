# 拾忆（BlueCare）— 老年人陪伴应用

基于 **Flutter** 的本地陪伴客户端，对话经 **本地 Python 代理** 转发至 vivo 蓝心开放平台聊天接口（默认模型 `Volc-DeepSeek-V3.2`）。聊天记录与档案使用 **SQLite（sqflite）** 保存在本机。

---

## 一、运行前需要安装的环境

### 1. Flutter SDK

- 要求：**Dart SDK ≥ 3.3**（与 `pubspec.yaml` 中 `sdk: ">=3.3.0 <4.0.0"` 一致）。
- 安装：从 [Flutter 官方安装文档](https://docs.flutter.dev/get-started/install) 按你的操作系统安装 **Stable** 渠道，并把 `flutter` 加入 `PATH`。
- 安装后执行：

```bash
flutter doctor -v
```

按提示补齐缺失项（尤其是 **Windows 桌面** 需要 Visual Studio 的「使用 C++ 的桌面开发」工作负载）。

### 2. Python 3（启动本地代理）

- 用于运行 `server/local_chat_server.py`。
- 该脚本**仅使用 Python 标准库**，无需 `pip install` 额外包；任意较新的 Python 3 即可。

### 3. 可选：IDE 与插件

在 **VS Code** 或 **Cursor** 中开发时建议安装：

| 插件 / 扩展 | 说明 |
|-------------|------|
| **Dart** | 语言支持、分析器 |
| **Flutter** | 运行/调试、设备选择、`flutter pub get` 等集成 |

安装插件后重启编辑器，确认命令面板可执行 **Flutter: Run Flutter Doctor** 或终端中 `flutter doctor` 无阻塞性错误。

---

## 二、从仓库克隆到可运行（完整步骤）

### 1. 克隆代码

```bash
git clone <你的仓库 URL>
cd aigc_five_men_team
```

### 2. 拉取 Flutter 依赖

```bash
flutter pub get
```

### 3. 配置密钥并启动本地聊天代理（必做）

客户端**不会**在应用内保存大模型密钥；密钥由 **`server/local_chat_server.py`** 在启动时从环境变量读取，再代你请求上游：

`https://api-ai.vivo.com.cn/v1/chat/completions`

支持的环境变量（任选其一即可）：

- **`VIVO_APP_KEY`**（推荐）
- **`APP_KEY`**

将团队提供的 **AppKey / Bearer Token** 设为上述变量之一。

**Windows（PowerShell）示例**（当前会话有效）：

```powershell
cd D:\AIGC\aigc_five_men_team
$env:VIVO_APP_KEY = "这里粘贴团队提供的密钥"
python server\local_chat_server.py
```

**macOS / Linux（bash）示例**：

```bash
cd /path/to/aigc_five_men_team
export VIVO_APP_KEY="这里粘贴团队提供的密钥"
python3 server/local_chat_server.py
```

默认监听 **`http://127.0.0.1:8000`**。看到类似 `Chat proxy is running on http://127.0.0.1:8000` 且 `Server AppKey loaded: True` 即表示密钥已加载。**保持该终端窗口不要关闭**，再开新终端运行 Flutter。

可选：修改监听地址或端口（仍与 Flutter 默认一致时需同时改 Flutter 侧，见下文）：

```powershell
$env:HOST = "127.0.0.1"
$env:PORT = "8000"
```

### 4. 验证代理是否就绪（可选）

浏览器或另一终端访问：

```text
http://127.0.0.1:8000/health
```

若返回 JSON 中含 `"ok": true` 且 `"has_server_key": true`，说明服务与密钥正常。

### 5. 运行 Flutter 应用

在**新的**终端中（项目根目录）：

```bash
flutter devices
flutter run -d windows
```

也可按需选择设备，例如：

```bash
flutter run -d chrome
flutter run -d android
```

应用默认请求 **`http://127.0.0.1:8000`**（定义在 `lib/config/constants.dart` 的 `API_BASE_URL` 编译期常量，未传参时即此地址）。只要本地代理按上一步在同一台机器、同一端口运行，即可正常对话。

若代理不在本机或端口不同，编译时传入：

```bash
flutter run -d windows --dart-define=API_BASE_URL=http://你的主机:端口
```

### 6. Android 模拟器特别说明

模拟器内的 `127.0.0.1` 指向模拟器自己，一般应使用 **`10.0.2.2`** 访问宿主机。若代理仍在宿主机 `8000` 端口，可：

```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

并确保宿主机防火墙允许该连接。

---

## 三、常见问题

| 现象 | 处理方向 |
|------|----------|
| 应用提示无法连接 / 超时 | 确认代理已启动、`/health` 正常；Windows 注意是否被防火墙拦截。 |
| 代理返回 Missing AppKey | 未设置 `VIVO_APP_KEY` 或 `APP_KEY`，或设置后未在同一终端会话中启动 `python`。 |
| `flutter doctor` 报 Windows 桌面相关错误 | 安装 Visual Studio 并勾选「使用 C++ 的桌面开发」。 |
| Web（Chrome）运行 | 已使用 `sqflite_common_ffi_web`；若遇存储或跨域问题，优先用 Windows/Android 真机或模拟器对照。 |

---

## 四、项目目录结构（便于分工）

### 1. 核心与配置

- `lib/main.dart` — 应用入口，`Provider` 注入 `ChatProvider`。
- `lib/config/constants.dart` — 应用名、默认模型 ID、`API_BASE_URL`（可通过 `--dart-define=API_BASE_URL=...` 覆盖）。
- `lib/config/theme.dart` — 主题与适老化视觉。
- `lib/core/api_client.dart` — `Dio` 客户端，请求发往本地代理或你配置的 `API_BASE_URL`。

### 2. 数据层

- `lib/data/models/` — 聊天消息、抽取的人际关系等模型。
- `lib/data/local_db/local_database.dart` — SQLite 初始化与表结构；桌面使用 `sqflite_common_ffi`，Web 使用 `sqflite_common_ffi_web`。
- `lib/data/repositories/chat_repository.dart` — 调用 `/api/chat` 等与对话相关的仓库逻辑。

### 3. 业务逻辑

- `lib/logic/chat_provider.dart` — 会话状态、发送消息、本地持久化与关系抽取调度。
- `lib/logic/relation_extractor.dart` — 从对话中合并、规范化人际关系线索。

### 4. UI

- `lib/ui/screens/home_screen.dart` — 主界面（陪伴、记忆、设置等）。

### 5. 本地代理

- `server/local_chat_server.py` — 本地 HTTP 代理：读取 `VIVO_APP_KEY` / `APP_KEY`，转发至 vivo 聊天接口。
- `server/database.py` — 服务端辅助脚本（若后续扩展使用）。

---

## 五、版本信息摘要

| 项 | 说明 |
|----|------|
| Flutter / Dart | `environment.sdk: >=3.3.0 <4.0.0` |
| 主要依赖 | `provider`、`dio`、`sqflite`、`sqflite_common_ffi`、`sqflite_common_ffi_web` 等（见 `pubspec.yaml`） |
| 默认模型 | `Volc-DeepSeek-V3.2`（`lib/config/constants.dart` 与代理默认一致） |

按本文 **第二节** 顺序操作：安装 Flutter 与 Python → `flutter pub get` → 设置密钥并启动 `local_chat_server.py` → `flutter run`，即可在拿到团队密钥后从零跑通全流程。
