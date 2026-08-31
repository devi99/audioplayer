import 'package:flutter/material.dart';

class LibraryArtworkFrame extends StatelessWidget {
  const LibraryArtworkFrame({
    super.key,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.gradient,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: 54,
          color: Colors.white.withValues(alpha: 0.88),
        ),
      ),
    );

    if (imageUrl == null || imageUrl!.isEmpty) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return fallback;
        },
      ),
    );
  }
}

class LibraryErrorState extends StatelessWidget {
  const LibraryErrorState({
    super.key,
    required this.message,
    required this.details,
  });

  final String message;
  final String details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              details,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
