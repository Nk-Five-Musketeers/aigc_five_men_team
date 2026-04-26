# BlueCare AI 集成说明

## 项目概述
BlueCare 是一个老年陪伴应用，已接入 vivo 蓝心大模型 AI 聊天接口，并把聊天功能集成到当前主界面中。

## 新增依赖
- `uuid: ^4.5.3` - 用于生成标准 UUID 请求 ID
- `provider` 已用于状态管理
- `dio` 已用于 HTTP 请求

## 主要改动

### 1. 主入口改动 (`lib/main.dart`)
- 使用 `MultiProvider` 注入 `ChatProvider` 和 `MemoryProvider`
- 保持 `HomeScreen` 作为应用主页面

### 2. 配置更新 (`lib/config/constants.dart`)
- API 基础 URL: `https://api-ai.vivo.com.cn/v1`
- API Key: `sk-xuanji-2026594139-WVlSb0F5YXdwQ1dwQ2V1dA==`
- 模型 ID: `Volc-DeepSeek-V3.2`
- 系统提示词改为蓝心陪伴助手人设

### 3. API 客户端更新 (`lib/core/api_client.dart`)
- 增加 `Authorization: Bearer {apiKey}` 请求头
- 设置 `Content-Type: application/json; charset=utf-8`

### 4. 聊天仓库实现 (`lib/data/repositories/chat_repository.dart`)
- 实现 `fetchReply()`，调用 `/chat/completions`
- 使用 UUID 作为 `request_id` 查询参数
- 构造 `messages` 为 `system + user`
- 解析 `choices[0].message.content`
- 增加 `DioException` 异常日志和返回体信息

### 5. 聊天状态管理 (`lib/logic/chat_provider.dart`)
- 使用 `ChatProvider` 管理消息列表和加载状态
- `sendMessage()` 先添加用户消息，再请求 AI 回复
- 请求失败时添加错误提示消息

### 6. 主界面集成 (`lib/ui/screens/home_screen.dart`)
- 将 AI 聊天内容集成到首页：`_ChatPreview` 动态展示真实消息
- 使用 `ChatProvider` 管理消息列表
- 通过 `_TypingPanel` 发送文本消息
- 在请求期间通过 `isLoading` 禁用输入并显示加载指示器

## API 集成详情

### 请求格式
```json
{
  "model": "Volc-DeepSeek-V3.2",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant for an elderly companion app. Be kind, calm and supportive."
    },
    {
      "role": "user",
      "content": "用户输入内容"
    }
  ],
  "temperature": 0.8,
  "max_tokens": 1024,
  "stream": false,
  "reasoning_effort": "low"
}
```

### 响应格式
```json
{
  "choices": [
    {
      "message": {
        "content": "AI 回复内容",
        "role": "assistant"
      }
    }
  ]
}
```

## 运行方式
```bash
cd d:\aigc\aigc_five_men_team
flutter run -d windows
```

> 建议使用 Windows 桌面运行，避免 Flutter Web 的 CORS 限制。

## 调试信息
- 控制台会输出 AI 请求 ID、状态码和返回数据
- 请求失败时会打印 `DioException` 的错误信息和响应体
- 如果 Web 运行出现网络问题，请切换到桌面平台

## 注意事项
- 当前实现为单轮对话：每次请求仅发送系统 + 当前用户消息
- 若需多轮上下文，可扩展 `ChatRepository` 中的 `messages` 构造
- API Key 已硬编码在 `constants.dart`，生产环境建议采用安全存储
- 虚拟环境 `aigc/env` 与当前 Flutter 项目无直接关联，仅是 Python 环境目录

## 未来扩展
- 添加 Function Call 支持（例如天气查询、日程提醒等）
- 实现多轮历史上下文消息传递
- 支持流式响应和图片理解
- 集成语音识别与播放功能
