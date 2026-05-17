import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
    );
    _logoScale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.82, curve: Curves.easeOutBack),
      ),
    );
    _taglineFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.36, 1, curve: Curves.easeOutCubic),
    );

    _controller.forward();

    Timer(AppDurations.splashMinimumDuration, () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoWidth = math.min(size.width * 0.76, 320.0);

    return Scaffold(
      backgroundColor: SplashColors.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            const _SubtleGroceryPattern(),
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 10),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FadeTransition(
                            opacity: _logoFade,
                            child: ScaleTransition(
                              scale: _logoScale,
                              child: _GkMartLogo(width: logoWidth),
                            ),
                          ),
                          const SizedBox(height: 18),
                          FadeTransition(
                            opacity: _taglineFade,
                            child: const _Tagline(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const _BottomGroceryShowcase(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GkMartLogo extends StatelessWidget {
  const _GkMartLogo({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: width * 0.22,
                height: width * 0.2,
                child: const CustomPaint(painter: _CartLogoPainter()),
              ),
              SizedBox(width: width * 0.02),
              Text(
                'GK',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: width * 0.22,
                  height: 0.9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(width: width * 0.03),
              Text(
                'MART',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: width * 0.118,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _LogoRule(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'SUPERMARKET',
                  style: TextStyle(
                    color: SplashColors.deepGreen,
                    fontSize: width * 0.052,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
              ),
              const _LogoRule(),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogoRule extends StatelessWidget {
  const _LogoRule();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 42,
      child: Divider(
        color: AppColors.primary,
        thickness: 1.7,
        height: 1,
      ),
    );
  }
}

class _CartLogoPainter extends CustomPainter {
  const _CartLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cart = Path()
      ..moveTo(size.width * 0.12, size.height * 0.12)
      ..quadraticBezierTo(
        size.width * 0.08,
        size.height * 0.38,
        size.width * 0.12,
        size.height * 0.62,
      )
      ..lineTo(size.width * 0.78, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.92,
        size.height * 0.6,
        size.width * 0.94,
        size.height * 0.45,
      );

    canvas.drawPath(cart, paint);
    canvas.drawLine(
      Offset(size.width * 0.14, size.height * 0.78),
      Offset(size.width * 0.78, size.height * 0.78),
      paint,
    );

    final wheelPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    canvas
      ..drawCircle(
        Offset(size.width * 0.28, size.height * 0.93),
        size.width * 0.085,
        wheelPaint,
      )
      ..drawCircle(
        Offset(size.width * 0.76, size.height * 0.93),
        size.width * 0.085,
        wheelPaint,
      );

    final leafPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    final leaf = Path()
      ..moveTo(size.width * 0.74, size.height * 0.1)
      ..cubicTo(
        size.width * 0.92,
        size.height * -0.02,
        size.width * 1.05,
        size.height * 0.1,
        size.width * 0.94,
        size.height * 0.29,
      )
      ..cubicTo(
        size.width * 0.83,
        size.height * 0.23,
        size.width * 0.77,
        size.height * 0.19,
        size.width * 0.74,
        size.height * 0.1,
      );
    canvas.drawPath(leaf, leafPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Smart Shopping',
            style: TextStyle(color: AppColors.primary),
          ),
          TextSpan(
            text: ', ',
            style: TextStyle(color: AppColors.primary),
          ),
          TextSpan(
            text: 'Better Living',
            style: TextStyle(color: AppColors.accent),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class _BottomGroceryShowcase extends StatelessWidget {
  const _BottomGroceryShowcase();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          const _GroceryProductVisuals(),
          const SizedBox(height: 12),
          Divider(
            color: Colors.white.withValues(alpha: 0.2),
            height: 1,
            thickness: 1,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              14,
              14,
              14 + MediaQuery.paddingOf(context).bottom,
            ),
            child: const Row(
              children: [
                Expanded(
                  child: _HighlightItem(
                    icon: Icons.verified_rounded,
                    label: 'Best Quality\nProducts',
                  ),
                ),
                _HighlightDivider(),
                Expanded(
                  child: _HighlightItem(
                    icon: Icons.local_offer_rounded,
                    label: 'Best Prices\nEveryday',
                  ),
                ),
                _HighlightDivider(),
                Expanded(
                  child: _HighlightItem(
                    icon: Icons.delivery_dining_rounded,
                    label: 'Fast & Reliable\nDelivery',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroceryProductVisuals extends StatelessWidget {
  const _GroceryProductVisuals();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: 286,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            bottom: 4,
            child: _RiceSack(),
          ),
          const Positioned(
            left: 92,
            bottom: 7,
            child: _AttaBag(),
          ),
          const Positioned(
            bottom: 7,
            child: _GheeJar(),
          ),
          const Positioned(
            right: 92,
            bottom: 7,
            child: _OilBottle(),
          ),
          const Positioned(
            right: 24,
            bottom: 5,
            child: _MilkCarton(),
          ),
        ],
      ),
    );
  }
}

class _RiceSack extends StatelessWidget {
  const _RiceSack();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE7C38B),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Center(
            child: Icon(Icons.rice_bowl_rounded, color: Colors.white, size: 28),
          ),
        ),
        Container(
          width: 62,
          height: 26,
          decoration: const BoxDecoration(
            color: Color(0xFFD5A965),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _AttaBag extends StatelessWidget {
  const _AttaBag();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFFF3DEB5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8B57A), width: 1.4),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.grass_rounded, color: AppColors.primary, size: 25),
          SizedBox(height: 8),
          Text(
            'ATTA',
            style: TextStyle(
              color: Color(0xFF6B4A1E),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'WHOLE WHEAT',
            style: TextStyle(
              color: Color(0xFF6B4A1E),
              fontSize: 7,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GheeJar extends StatelessWidget {
  const _GheeJar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 68,
      decoration: BoxDecoration(
        color: const Color(0xFFFFE08A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: const Center(
        child: Text(
          'Ghee',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _OilBottle extends StatelessWidget {
  const _OilBottle();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 16,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
        Container(
          width: 50,
          height: 86,
          decoration: BoxDecoration(
            color: const Color(0xFFFFC857),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: const Center(
            child:
                Icon(Icons.water_drop_rounded, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }
}

class _MilkCarton extends StatelessWidget {
  const _MilkCarton();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.04,
      child: Container(
        width: 58,
        height: 84,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFB7D8FF), width: 2),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_drink_rounded, color: Color(0xFF1976D2), size: 25),
            SizedBox(height: 5),
            Text(
              'Milk',
              style: TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightItem extends StatelessWidget {
  const _HighlightItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 27),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _HighlightDivider extends StatelessWidget {
  const _HighlightDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 46,
      color: Colors.white.withValues(alpha: 0.24),
    );
  }
}

class _SubtleGroceryPattern extends StatelessWidget {
  const _SubtleGroceryPattern();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: const [
          _PatternIcon(icon: Icons.shopping_bag_outlined, left: 34, top: 62),
          _PatternIcon(icon: Icons.shopping_cart_outlined, right: 36, top: 96),
          _PatternIcon(icon: Icons.eco_outlined, left: 38, top: 232),
          _PatternIcon(icon: Icons.local_drink_outlined, right: 48, top: 260),
          _PatternIcon(icon: Icons.local_offer_outlined, left: 44, bottom: 252),
          _PatternIcon(
            icon: Icons.inventory_2_outlined,
            right: 42,
            bottom: 286,
          ),
        ],
      ),
    );
  }
}

class _PatternIcon extends StatelessWidget {
  const _PatternIcon({
    required this.icon,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  final IconData icon;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: Icon(
        icon,
        color: AppColors.primary.withValues(alpha: 0.055),
        size: 54,
      ),
    );
  }
}

class SplashColors {
  const SplashColors._();

  static const background = Color(0xFFFFFCF4);
  static const deepGreen = Color(0xFF1B5E20);
}
