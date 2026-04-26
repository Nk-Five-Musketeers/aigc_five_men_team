# BlueCare AI 集成说明

## 项目概述
BlueCare 是一个老年陪伴应用，已成功集成 vivo 蓝心大模型 AI 聊天功能。

## 新增依赖
- `uuid: ^4.5.3` - 用于生成标准 UUID 请求 ID

## 主要改动

### 1. 配置更新 (`lib/config/constants.dart`)
- 添加 API 基础 URL: `https://api-ai.vivo.com.cn/v1`
- 添加 API Key: `sk-xuanji-2026594139-WVlSb0F5YXdwQ1dwQ2V1dA==`
- 设置模型 ID: `Volc-DeepSeek-V3.2`
- 定义系统提示词: 老年陪伴助手的人设

### 2. API 客户端更新 (`lib/core/api_client.dart`)
- 添加 `Authorization: Bearer {apiKey}` 请求头
- 更新 Content-Type 为 `application/json; charset=utf-8`

### 3. 聊天仓库重构 (`lib/data/repositories/chat_repository.dart`)
- 完全重写，实现 `fetchReply()` 方法
- 使用 Dio 发送 POST 请求到 `/chat/completions`
- 生成 UUID 作为 `request_id` 查询参数
- 构造包含 system 和 user 角色的 messages
- 解析 API 响应，提取 AI 回复内容
- 添加详细的错误处理和调试日志

### 4. 聊天提供者更新 (`lib/logic/chat_provider.dart`)
- 修改 `sendMessage()` 方法，调用 `ChatRepository.fetchReply()`
- 添加 `isLoading` 状态管理
- 异步处理 AI 请求，避免 UI 阻塞
- 错误时显示友好提示

### 5. 聊天界面优化 (`lib/ui/screens/chat_screen.dart`)
- 添加加载指示器（CircularProgressIndicator）
- 在请求期间禁用发送按钮和快捷输入
- 显示“AI 正在思考，请稍候...”提示

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
# 桌面应用（推荐，避免 CORS 问题）
flutter run -d windows

# Web 应用（有 CORS 限制，不推荐）
flutter run -d chrome
```

## 调试信息
- 控制台会输出请求 ID 和响应状态
- 网络错误会显示详细的 DioException 信息
- 成功时显示完整的 API 响应数据

## 注意事项
- 仅在桌面/移动平台运行，Web 平台有 CORS 限制
- API Key 已硬编码在代码中，生产环境建议使用安全存储
- 当前实现单轮对话，如需多轮上下文需扩展 messages 历史

## 未来扩展
- 添加 Function Call 支持（天气查询、健康提醒等）
- 实现流式响应
- 添加图片理解功能
- 集成语音输入输出