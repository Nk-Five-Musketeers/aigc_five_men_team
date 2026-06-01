# 对话语音朗读 TTS 接入方案

## 1. 目标与首版建议

在老人和“拾忆”的聊天过程中，为“拾忆”的文字回复提供可点击的语音朗读能力。

已确认的第一版范围：

- 在“拾忆”的文字回复旁显示朗读按钮。
- 点击后合成并播放当前消息；再次点击停止。
- 同一时间只播放一条消息，点击另一条时先停止上一条。
- 暂不自动播放新消息，避免突然发声。
- 设置页开放语速和音量调节，默认值均为 `50`。
- 默认音色固定为 `yunye`（云野-温柔）。
- 首版由服务端完整合成 WAV 后再返回 Flutter，优先保证稳定性。

## 2. 官方文档摘要

来源：[新建 DOCX 文档 (2).docx](<D:/桌面/新建 DOCX 文档 (2).docx>)

文档标题为“音频生成”，更新时间为 `2026-04-22 06:01:19`。

### 2.1 WebSocket 接口

```text
wss://api-ai.vivo.com.cn/tts
```

握手 Header：

```text
Authorization: Bearer AppKey
X-AI-GATEWAY-SIGNATURE: developers-aigc
```

URL 查询参数：

| 参数 | 说明 |
| --- | --- |
| `engineid` | 合成引擎 |
| `system_time` | 秒级时间戳 |
| `user_id` | 32 位数字和小写字母组成的字符串 |
| `model` | 客户端模型信息 |
| `product` | 产品信息 |
| `package` | 包名 |
| `client_version` | 客户端版本 |
| `system_version` | 系统版本 |
| `sdk_version` | SDK 版本 |
| `android_version` | Android 版本 |
| `requestId` | UUID |

聊天朗读推荐使用短音频引擎：

```text
short_audio_synthesis_jovi
```

### 2.2 合成请求

WebSocket 建立后发送 JSON：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `aue` | int | `0` 为 PCM，`1` 为 Opus；首版使用 `0` |
| `auf` | string | 使用 `audio/L16;rate=24000` |
| `vcn` | string | 音色 |
| `speed` | int | 可选，范围 `0-100`，默认 `50` |
| `volume` | int | 可选，范围 `1-100`，默认 `50` |
| `text` | string | UTF-8 文本经过 Base64 编码 |
| `encoding` | string | 使用 `utf8` |
| `reqId` | long | 请求 ID |

文本在 Base64 编码前最多为 `2048` 个 UTF-8 字节。超过限制时，服务端需要优先沿中文标点分段，并保证每段不超限。

### 2.3 合成响应

| 字段 | 说明 |
| --- | --- |
| `error_code` | `0` 表示成功 |
| `error_msg` | 异常信息 |
| `sid` | 会话 ID |
| `data.audio` | Base64 编码的 PCM 音频分片 |
| `data.status` | `0` 首帧、`1` 中间帧、`2` 结束帧 |

首版服务端收到 `status=2` 后，将 PCM 分片按顺序拼接，并包装为单声道、16 bit、`24000 Hz` 的 WAV 文件，再返回 Flutter。

### 2.4 可选音色

短文本引擎提供：

| `vcn` | 音色 |
| --- | --- |
| `vivoHelper` | 奕雯 |
| `yunye` | 云野-温柔 |
| `wanqing` | 婉清-御姐 |
| `xiaofu` | 晓芙-少女 |
| `yige_child` | 小萌-女童 |
| `yige` | 依格 |
| `yiyi` | 依依 |
| `xiaoming` | 小茗 |

已确认默认使用 `yunye`（云野-温柔）。

### 2.5 需要真实联调确认的文档差异

官方参数表要求 `X-AI-GATEWAY-SIGNATURE`，但官方 Python 示例只明确传入 `Authorization`。此外，示例配置中出现了 `APP_ID`，但可见的 URL 和 Header 示例未使用它。

已提供 `APP_ID=2026594139`。开发开始时应先用真实账号权限执行最小请求测试，确认线上实际规则以及 AppKey 是否已开通 TTS 权限。

## 3. 复用现有架构

项目已有 ASR 本地代理：

```text
Flutter
  -> POST /api/asr/transcribe
  -> server/local_chat_server.py
  -> Vivo ASR WebSocket
```

TTS 复用同一思路：

```text
Flutter 点击朗读
  -> POST /api/tts/synthesize
  -> server/local_chat_server.py
  -> Vivo TTS WebSocket
  -> PCM 分片拼接为 WAV
  -> Flutter 播放 WAV 字节
```

这样 `VIVO_APP_KEY` 继续只存在于 Python 代理进程，不会进入 Flutter 安装包。

## 4. 服务端设计

### 4.1 新增文件

```text
server/speech_synthesis.py
server/tts_http.py
```

`server/speech_synthesis.py`：

- 生成 WebSocket URL、查询参数和握手 Header。
- 对长文本按 UTF-8 字节数安全分段。
- 请求合成并接收响应帧。
- 合并 PCM 分片，包装为 WAV 字节。
- 映射 Vivo 错误码。

`server/tts_http.py`：

- 校验 HTTP 请求参数。
- 填充默认音色、语速和音量。
- 调用 TTS 客户端。
- 返回 WAV 字节或结构化错误。

### 4.2 HTTP 路由

在 `server/local_chat_server.py` 增加：

```text
POST /api/tts/synthesize
```

请求：

```json
{
  "text": "今天想和您聊聊年轻时的故事。",
  "voice": "yunye",
  "speed": 50,
  "volume": 50
}
```

成功响应：

```text
Content-Type: audio/wav
Body: WAV bytes
```

同时为 `/health` 增加 `vivo_tts` 状态。

## 5. Flutter 设计

### 5.1 播放依赖

建议接入 [`audioplayers`](https://pub.dev/packages/audioplayers)。官方页面说明它支持 Android、iOS、Linux、macOS、Web 和 Windows；[`BytesSource`](https://pub.dev/documentation/audioplayers/latest/audioplayers/BytesSource-class.html) 支持直接播放内存字节，适合本项目返回的 WAV。

### 5.2 新增模块

```text
lib/core/voice_output/tts_repository.dart
lib/core/voice_output/voice_output_service.dart
lib/logic/voice_output_provider.dart
```

| 文件 | 职责 |
| --- | --- |
| `tts_repository.dart` | 使用 Dio 请求 `/api/tts/synthesize` 并获得 WAV 字节 |
| `voice_output_service.dart` | 管理播放器，提供播放、停止和资源释放 |
| `voice_output_provider.dart` | 保存当前加载中和播放中的消息 ID |

### 5.3 页面交互

在聊天消息渲染层统一为目标消息增加朗读操作区：

```text
idle -> loading -> playing -> idle
                   |
                   -> stop -> idle
```

异常时恢复 `idle`，使用 Snackbar 给出简短提示，不影响文字聊天。

### 5.4 缓存

首版建议做内存缓存：

```text
文本 + 音色 + 语速 + 音量 -> WAV bytes
```

重复点击同一句时不必再次请求 Vivo TTS。应用退出后缓存释放，不额外落地音频文件。

## 6. 文件级修改清单

| 文件 | 修改内容 |
| --- | --- |
| `server/speech_synthesis.py` | 新增 Vivo TTS WebSocket 客户端 |
| `server/tts_http.py` | 新增 HTTP 参数校验和 WAV 响应封装 |
| `server/local_chat_server.py` | 注册 `/api/tts/synthesize`，扩展 `/health` |
| `pubspec.yaml` | 增加 Flutter 音频播放依赖 |
| `lib/core/voice_output/tts_repository.dart` | 新增 TTS HTTP 仓库 |
| `lib/core/voice_output/voice_output_service.dart` | 新增播放器服务 |
| `lib/logic/voice_output_provider.dart` | 新增播放状态管理 |
| `lib/main.dart` | 注册播放状态 Provider |
| `lib/ui/screens/home_screen.dart` | 为目标消息增加朗读按钮 |
| `README.md` | 补充 TTS 启动和验证说明 |

## 7. 验证方案

服务端：

- 短文本返回有效 WAV。
- 超过 `2048` UTF-8 字节的中文文本能够安全分段。
- 空文本、非法 `speed`、非法 `volume` 返回清楚错误。
- 缺少 `VIVO_APP_KEY` 时错误可读。
- 用真实 AppKey 确认签名 Header 和 `APP_ID` 的实际要求。

Flutter：

- 点击目标消息可以播放。
- 重复点击同一消息可以停止。
- 播放中点击另一消息时切换正确。
- 请求失败不影响继续聊天。
- 长消息能够完整播放。
- Windows 验收后，在 Android 真机验证音频播放和网络地址配置。

运行方式：

终端一：

```powershell
$env:VIVO_APP_KEY=""
python server\local_chat_server.py
```

终端二：

```powershell
flutter run -d windows
```

## 8. 已确认的产品决策

| 项目 | 决策 |
| --- | --- |
| 朗读范围 | 仅朗读“拾忆”的回复 |
| 播放方式 | 仅点击后朗读，不自动播放 |
| 默认音色 | `yunye`（云野-温柔） |
| 设置页 | 开放语速和音量调节 |
| 默认参数 | `speed=50`、`volume=50` |
| Vivo APP_ID | `2026594139` |
| 首版验收 | 先完成 Windows 双终端验收，代码结构兼顾 Android / Web |
| Git 分支 | 在 `main` 上继续 |

尚待联调确认：现有 AppKey 是否已经开通 TTS 权限，以及线上是否要求同时使用 `APP_ID` 和签名 Header。

## 9. 推荐实施顺序

1. 用真实 AppKey 完成最小 TTS WebSocket 请求，确认签名规则。
2. 完成 Python TTS 客户端和 HTTP 路由。
3. 增加 Flutter 播放模块和消息级播放状态。
4. 在聊天消息旁接入朗读按钮。
5. 验证长文本、异常状态和 Windows 端行为。
6. 在 Android 真机验证，为手机软件落地做准备。
