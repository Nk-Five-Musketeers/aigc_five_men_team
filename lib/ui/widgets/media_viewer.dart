import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../config/theme.dart';
import '../../core/services/local_media_path.dart';
import '../../data/models/profile_photo.dart';

/// 全屏查看图片或播放视频。
Future<void> showMediaViewer(
  BuildContext context, {
  required String path,
  required bool isVideo,
  String? title,
}) {
  if (isVideo) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _VideoViewerDialog(path: path, title: title),
    );
  }
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => _ImageViewerDialog(path: path, title: title),
  );
}

Future<void> showMediaViewerForPhoto(
  BuildContext context,
  ProfilePhotoModel photo, {
  String? title,
}) {
  return showMediaViewer(
    context,
    path: photo.filePath,
    isVideo: photo.isVideo,
    title: title,
  );
}

class _ImageViewerDialog extends StatelessWidget {
  const _ImageViewerDialog({required this.path, this.title});

  final String path;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            if (title != null && title!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
              ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Center(child: _buildImage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (path.startsWith('data:image/')) {
      return Image.network(path, fit: BoxFit.contain);
    }
    if (kIsWeb) {
      return const Text('Web 暂不可预览', style: TextStyle(color: Colors.white70));
    }
    return Image.file(File(path), fit: BoxFit.contain);
  }
}

class _VideoViewerDialog extends StatefulWidget {
  const _VideoViewerDialog({required this.path, this.title});

  final String path;
  final String? title;

  @override
  State<_VideoViewerDialog> createState() => _VideoViewerDialogState();
}

class _VideoViewerDialogState extends State<_VideoViewerDialog> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (widget.path.startsWith('data:')) {
        setState(() => _error = '暂不支持在此预览该视频');
        return;
      }

      final resolvedPath = await LocalMediaPath.resolveForPlayback(widget.path);
      late final VideoPlayerController controller;
      if (kIsWeb) {
        controller = VideoPlayerController.networkUrl(Uri.parse(resolvedPath));
      } else {
        controller = VideoPlayerController.file(File(resolvedPath));
      }

      controller.addListener(_onControllerUpdate);
      await controller.initialize();

      if (!mounted) {
        controller.removeListener(_onControllerUpdate);
        await controller.dispose();
        return;
      }

      if (controller.value.hasError) {
        setState(() {
          _error = _friendlyVideoError(controller.value.errorDescription);
        });
        controller.removeListener(_onControllerUpdate);
        await controller.dispose();
        return;
      }

      if (!controller.value.isInitialized) {
        setState(() {
          _error = _friendlyVideoError('视频未能初始化');
        });
        controller.removeListener(_onControllerUpdate);
        await controller.dispose();
        return;
      }

      setState(() => _controller = controller);
      await controller.play();
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyVideoError(e));
      }
    }
  }

  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.value.hasError) {
      setState(() {
        _error = _friendlyVideoError(controller.value.errorDescription);
      });
    } else {
      setState(() {});
    }
  }

  String _friendlyVideoError(Object? raw) {
    final text = raw?.toString() ?? '';
    if (text.contains('UnimplementedError')) {
      return '当前平台暂不支持内置播放，请重新编译 Windows 版本后再试';
    }
    if (text.contains('open file failed') ||
        text.contains('找不到视频') ||
        text.contains('FileSystemException')) {
      return '找不到视频文件，可能已被移动或删除';
    }
    if (text.contains('decode') || text.contains('Media Foundation')) {
      return '系统无法解码该视频，请尝试 H.264 编码的 MP4 文件';
    }
    if (text.isEmpty) return '视频暂时无法播放';
    return text;
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onControllerUpdate);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                if (controller != null && controller.value.isInitialized)
                  IconButton(
                    tooltip: controller.value.isPlaying ? '暂停' : '播放',
                    onPressed: () {
                      setState(() {
                        controller.value.isPlaying
                            ? controller.pause()
                            : controller.play();
                      });
                    },
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
            if (widget.title != null && widget.title!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  widget.title!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
              ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '视频暂时打不开：$_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      )
                    : controller == null || !controller.value.isInitialized
                        ? const CircularProgressIndicator(color: Colors.white)
                        : FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: controller.value.size.width,
                              height: controller.value.size.height,
                              child: VideoPlayer(controller),
                            ),
                          ),
              ),
            ),
            if (controller != null && controller.value.isInitialized)
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: AppTheme.primary,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            if (!kIsWeb && Platform.isWindows && _error != null)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '提示：Windows 需使用 H.264 编码的 MP4，并重新运行 flutter run 以加载视频插件。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 缩略图点击后打开全屏查看。
class TappableMediaThumbnail extends StatelessWidget {
  const TappableMediaThumbnail({
    super.key,
    required this.path,
    required this.isVideo,
    required this.child,
    this.title,
  });

  final String path;
  final bool isVideo;
  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showMediaViewer(
          context,
          path: path,
          isVideo: isVideo,
          title: title,
        ),
        child: child,
      ),
    );
  }
}
