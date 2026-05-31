part of '../home_screen.dart';

class _MemoryPhotoImage extends StatelessWidget {
  const _MemoryPhotoImage({required this.photo});

  final ProfilePhotoModel photo;

  @override
  Widget build(BuildContext context) {
    final path = photo.filePath;
    if (path.startsWith('data:image/')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _MemoryPhotoFallback(),
      );
    }
    if (kIsWeb) {
      return const _MemoryPhotoFallback(hint: 'Web 暂不可预览');
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _MemoryPhotoFallback(),
    );
  }
}

class _MemoryPhotoFallback extends StatelessWidget {
  const _MemoryPhotoFallback({this.hint});

  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.image_outlined,
            color: AppTheme.textCaption,
            size: 28,
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 17,
                color: AppTheme.textCaption,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
