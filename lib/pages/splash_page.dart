import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/portal_loading.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static const appName = 'NTCCSL FINANCE SYSTEM';

  static const _purple = Color(0xFF8B4FA5);
  static const _green = Color(0xFF428A3A);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  late final Future<PackageInfo> _packageInfo;

  @override
  void initState() {
    super.initState();
    _packageInfo = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final logoSize =
                (constraints.maxWidth * 0.44).clamp(140.0, 240.0).toDouble();
            return Stack(
              children: [
                Positioned(
                  top: -90,
                  right: -75,
                  child: _Glow(
                    color: SplashPage._purple.withValues(alpha: 0.08),
                    size: 250,
                  ),
                ),
                Positioned(
                  bottom: -110,
                  left: -95,
                  child: _Glow(
                    color: SplashPage._green.withValues(alpha: 0.08),
                    size: 280,
                  ),
                ),
                SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              key: const Key('splash-logo-backdrop'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        colors.primary.withValues(alpha: 0.12),
                                    blurRadius: 32,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/ntccsl_logo.png',
                                key: const Key('splash-logo'),
                                width: logoSize,
                                height: logoSize,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 30),
                            Text(
                              SplashPage.appName,
                              key: const Key('splash-app-name'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: colors.tertiary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'NoFino Thrift & Credit',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Co-Operative Society Ltd.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: colors.tertiary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Seeding Growth, Nurturing Futures',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    letterSpacing: 0.2,
                                  ),
                            ),
                            const SizedBox(height: 34),
                            Container(
                              key: const Key('splash-loading-indicator'),
                              width: 220,
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                16,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const PortalOrbitLoader(
                                    key: Key('splash-orbiting-loader'),
                                    size: 112,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Getting things ready',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'SECURE FINANCE PORTAL',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant
                                              .withValues(alpha: .72),
                                          letterSpacing: 1.1,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            FutureBuilder<PackageInfo>(
                              future: _packageInfo,
                              builder: (context, snapshot) {
                                final versionText = snapshot.hasError
                                    ? 'Version unavailable'
                                    : snapshot.hasData
                                        ? 'Version - ${snapshot.data!.version}'
                                        : 'Loading version...';

                                return Text(
                                  versionText,
                                  key: const Key('splash-app-version'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
