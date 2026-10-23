import 'dart:async';

import 'package:flutter/material.dart';

OverlayEntry? _activePortalToast;

const portalRoleColors = <String, Color>{
  'admin': Color(0xFF3458D4),
  'collector': Color(0xFF078A6A),
  'member': Color(0xFF8E24AA),
  'other': Color(0xFF7B8494),
};

const portalToastSuccessColor = Color(0xFF078A6A);
const portalToastErrorColor = Color(0xFFD25858);
const portalToastInfoColor = Color(0xFF3458D4);
const portalToastWarningColor = Color(0xFFFFC107);
const portalEditColor = portalToastSuccessColor;
const portalDeleteColor = portalToastErrorColor;

Color portalRoleColor(String role) =>
    portalRoleColors[role.trim().toLowerCase()] ?? portalRoleColors['other']!;

List<Color> portalHeaderGradient(BuildContext context) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.dark) {
    return const [Color(0xFF253B8C), Color(0xFF50346F)];
  }
  return [theme.colorScheme.primary, theme.colorScheme.tertiary];
}

void showPortalToast(
  BuildContext context,
  String message, {
  bool isError = false,
  bool isDestructive = false,
  bool isInfo = false,
  bool isWarning = false,
  Duration duration = const Duration(seconds: 3),
}) {
  if (_activePortalToast?.mounted ?? false) {
    _activePortalToast!.remove();
  }

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _PortalToast(
      message: message,
      isError: isError,
      isDestructive: isDestructive,
      isInfo: isInfo,
      isWarning: isWarning,
      duration: duration,
      onDisposed: () {
        if (identical(_activePortalToast, entry)) {
          _activePortalToast = null;
        }
      },
      onDismiss: () {
        if (!identical(_activePortalToast, entry)) return;
        if (entry.mounted) entry.remove();
        _activePortalToast = null;
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  _activePortalToast = entry;
}

class _PortalToast extends StatefulWidget {
  const _PortalToast({
    required this.message,
    required this.isError,
    required this.isDestructive,
    required this.isInfo,
    required this.isWarning,
    required this.duration,
    required this.onDisposed,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final bool isDestructive;
  final bool isInfo;
  final bool isWarning;
  final Duration duration;
  final VoidCallback onDisposed;
  final VoidCallback onDismiss;

  @override
  State<_PortalToast> createState() => _PortalToastState();
}

class _PortalToastState extends State<_PortalToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -.16),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isError = widget.isError;
    final isDestructive = widget.isDestructive;
    final accentColor = isError || isDestructive
        ? portalToastErrorColor
        : widget.isWarning
            ? portalToastWarningColor
            : widget.isInfo
                ? portalToastInfoColor
                : portalToastSuccessColor;
    final icon = isError
        ? Icons.error_outline_rounded
        : isDestructive
            ? Icons.delete_outline_rounded
            : widget.isWarning
                ? Icons.warning_amber_rounded
                : widget.isInfo
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_outline_rounded;
    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 64,
      left: 16,
      right: 16,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOut,
              ),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  key: const Key('portal-toast'),
                  elevation: 12,
                  color: colors.surfaceContainerHigh,
                  shadowColor: Colors.black.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
                          child: Row(
                            children: [
                              Container(
                                key: const Key('portal-toast-icon-container'),
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  icon,
                                  key: const Key('portal-toast-icon'),
                                  color: accentColor,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  widget.message,
                                  key: const Key('portal-toast-message'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: colors.onSurface,
                                        fontWeight: FontWeight.w600,
                                        height: 1.3,
                                      ),
                                ),
                              ),
                              IconButton(
                                key: const Key('portal-toast-dismiss'),
                                tooltip: 'Dismiss message',
                                onPressed: _dismiss,
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: colors.onSurfaceVariant,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          key: const Key('portal-toast-timeout'),
                          height: 3,
                          color: accentColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PortalGradientBackground extends StatelessWidget {
  const PortalGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: isDark ? .16 : .46),
            isDark ? const Color(0xFF11131A) : const Color(0xFFF8FAFF),
            colors.tertiaryContainer.withValues(alpha: isDark ? .12 : .35),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -90,
            right: -58,
            child: IgnorePointer(
              child: _GradientOrb(
                size: 240,
                color: colors.primary.withValues(alpha: .055),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -84,
            child: IgnorePointer(
              child: _GradientOrb(
                size: 280,
                color: colors.tertiary.withValues(alpha: .055),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GradientOrb extends StatelessWidget {
  const _GradientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      );
}

class PortalPageHeader extends StatelessWidget {
  const PortalPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final gradientColors = portalHeaderGradient(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final icon = Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
          ),
          child: Icon(this.icon, color: Colors.white),
        );
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .84),
                  ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: .20),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 12),
                          Expanded(child: text),
                        ],
                      ),
                      if (trailing != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: trailing!,
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 14),
                      Expanded(child: text),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing!,
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class PortalMetricCard extends StatelessWidget {
  const PortalMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = accent ?? colors.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surface, color.withValues(alpha: .055)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .14)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 160;
          final iconBox = Container(
            width: compact ? 32 : 40,
            height: compact ? 32 : 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(compact ? 11 : 13),
            ),
            child: Icon(icon, color: color, size: compact ? 17 : 20),
          );
          final details = Column(
            crossAxisAlignment:
                compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: compact ? Alignment.center : Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: compact ? 14 : null,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                label,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: compact ? TextAlign.center : TextAlign.start,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: compact ? 10 : null,
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          );

          if (compact) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconBox,
                const SizedBox(height: 6),
                details,
              ],
            );
          }
          return Row(
            children: [
              iconBox,
              const SizedBox(width: 12),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class PortalEmptyState extends StatelessWidget {
  const PortalEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 34, color: colors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class PortalErrorState extends StatelessWidget {
  const PortalErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 42, color: colors.error),
            const SizedBox(height: 14),
            Text(
              'Could not load this page',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
