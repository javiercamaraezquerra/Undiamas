import 'package:flutter/material.dart';

/// Readable editor feedback over the illustrated background, at any text size.
class JournalFeedbackCard extends StatelessWidget {
  const JournalFeedbackCard({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.info_outline,
    this.isError = false,
    this.isBusy = false,
    this.compact = false,
    this.onDismiss,
    this.actions = const [],
  });

  final String message;
  final String? title;
  final IconData icon;
  final bool isError;
  final bool isBusy;
  final bool compact;
  final VoidCallback? onDismiss;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isError
                  ? scheme.error.withAlpha(100)
                  : scheme.outlineVariant),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(icon,
                            size: 20,
                            color: isError
                                ? scheme.error
                                : scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title ?? message,
                        style: (compact
                                ? theme.textTheme.bodySmall
                                : theme.textTheme.bodyMedium)
                            ?.copyWith(
                                color: scheme.onSurface,
                                fontWeight:
                                    title == null ? null : FontWeight.w600,
                                fontSize: compact ? 14 : null,
                                height: 1.35)),
                  ),
                  if (onDismiss != null)
                    IconButton(
                      tooltip: 'Cerrar aviso',
                      onPressed: onDismiss,
                      icon: const Icon(Icons.close, size: 20),
                      color: scheme.onSurfaceVariant,
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      padding: const EdgeInsets.all(8),
                    ),
                ],
              ),
              if (title != null) ...[
                const SizedBox(height: 4),
                Text(message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurface, height: 1.35)),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
