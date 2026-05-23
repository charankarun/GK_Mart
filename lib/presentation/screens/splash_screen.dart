import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.startup,
    required this.onRetry,
  });

  final Future<void> startup;
  final VoidCallback onRetry;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _markScale;
  late final Animation<Offset> _slide;

  Object? _startupError;
  bool _isLoading = true;
  int _startupAttempt = 0;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.82, curve: Curves.easeOutCubic),
    );
    _markScale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.78, curve: Curves.easeOutBack),
      ),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.12, 1, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
    unawaited(_beginStartup());
  }

  @override
  void didUpdateWidget(covariant SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startup != widget.startup) {
      unawaited(_beginStartup());
    }
  }

  Future<void> _beginStartup() async {
    final attempt = ++_startupAttempt;
    setState(() {
      _isLoading = true;
      _startupError = null;
    });

    try {
      await Future.wait<void>([
        widget.startup,
        Future<void>.delayed(AppDurations.splashMinimumDuration),
      ]);

      if (!mounted || attempt != _startupAttempt) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
      );
    } catch (error) {
      if (!mounted || attempt != _startupAttempt) return;

      setState(() {
        _isLoading = false;
        _startupError = error;
      });
    }
  }

  void _retryStartup() {
    setState(() {
      _isLoading = true;
      _startupError = null;
    });
    widget.onRetry();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: SplashColors.background,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactHeight = constraints.maxHeight < 620;
            final horizontalPadding = constraints.maxWidth < 360 ? 20.0 : 28.0;
            final availableWidth =
                math.max(0.0, constraints.maxWidth - horizontalPadding * 2);
            final maxContentWidth = math.min(availableWidth, 420.0);
            final markSize = compactHeight ? 88.0 : 104.0;

            return Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _SplashBackgroundPainter()),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    compactHeight ? 18 : 28,
                    horizontalPadding,
                    24 + mediaPadding.bottom,
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxContentWidth,
                        ),
                        child: FadeTransition(
                          opacity: _fade,
                          child: SlideTransition(
                            position: _slide,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ScaleTransition(
                                  scale: _markScale,
                                  child: _BrandMark(size: markSize),
                                ),
                                SizedBox(height: compactHeight ? 18 : 24),
                                const _Wordmark(),
                                const SizedBox(height: 10),
                                const _SplashTagline(),
                                SizedBox(height: compactHeight ? 18 : 26),
                                const _DeliveryPill(),
                                SizedBox(height: compactHeight ? 22 : 34),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: _startupError == null
                                      ? _LoadingStatus(isLoading: _isLoading)
                                      : _StartupRetry(
                                          onRetry: _retryStartup,
                                        ),
                                ),
                              ],
                            ),
                          ),
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

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'GK',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.42,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          Positioned(
            top: size * 0.16,
            right: size * 0.16,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Icons.eco_rounded,
                color: Colors.white,
                size: size * 0.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        const TextSpan(
          children: [
            TextSpan(
              text: 'GK ',
              style: TextStyle(color: AppColors.primary),
            ),
            TextSpan(
              text: 'MART',
              style: TextStyle(color: AppColors.accent),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 44,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SplashTagline extends StatelessWidget {
  const _SplashTagline();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Fresh groceries. Fast delivery.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: SplashColors.deepGreen,
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _DeliveryPill extends StatelessWidget {
  const _DeliveryPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, color: AppColors.accent, size: 19),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Daily essentials ready',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingStatus extends StatelessWidget {
  const _LoadingStatus({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('loading'),
      height: 44,
      child: Center(
        child: AnimatedOpacity(
          opacity: isLoading ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppColors.primary,
              backgroundColor: AppColors.softGreen,
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupRetry extends StatelessWidget {
  const _StartupRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('retry'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Unable to start GK Mart.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

class _SplashBackgroundPainter extends CustomPainter {
  const _SplashBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final topBand = Paint()..color = AppColors.softGreen;
    final topPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.22)
      ..quadraticBezierTo(
        size.width * 0.56,
        size.height * 0.32,
        0,
        size.height * 0.24,
      )
      ..close();
    canvas.drawPath(topPath, topBand);

    final accentPaint = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    final accentPath = Path()
      ..moveTo(size.width * 0.12, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.48,
        size.height * 0.72,
        size.width * 0.9,
        size.height * 0.82,
      );
    canvas.drawPath(accentPath, accentPaint);

    final greenLinePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final greenPath = Path()
      ..moveTo(size.width * 0.08, size.height * 0.18)
      ..quadraticBezierTo(
        size.width * 0.44,
        size.height * 0.12,
        size.width * 0.86,
        size.height * 0.2,
      );
    canvas.drawPath(greenPath, greenLinePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SplashColors {
  const SplashColors._();

  static const background = Color(0xFFFFFCF4);
  static const deepGreen = Color(0xFF1B5E20);
}
