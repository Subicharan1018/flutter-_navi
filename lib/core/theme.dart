import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Spotify exact color palette
  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color electricBlue = Color(0xFF1DB954); // Alias for compatibility
  static const Color goldAccent = Color(0xFFE8C547); // For stars/favorites
  static const Color coreBackground = Color(0xFF000000);
  static const Color surfaceLevel = Color(0xFF121212); // Spotify surface
  static const Color cardSurface = Color(0xFF181818);
  static const Color topLevel = Color(0xFF282828);
  
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3); // Spotify secondary text
  static const Color textMuted = Color(0xFF7F7F7F);
  
  static const Color outlineColor = Color(0xFF2A2A2A);

  static TextStyle get technicalSm => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  static TextStyle get technicalXs => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textMuted,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: coreBackground,
      colorScheme: const ColorScheme.dark(
        primary: spotifyGreen,
        surface: coreBackground,
        onSurface: textPrimary,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),

      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 32,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 24,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontWeight: FontWeight.w400,
          fontSize: 15,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: textSecondary,
        ),
        bodySmall: GoogleFonts.inter(
          fontWeight: FontWeight.w400,
          fontSize: 12,
          color: textSecondary,
        ),
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: textPrimary,
        inactiveTrackColor: textPrimary.withOpacity(0.1),
        thumbColor: textPrimary,
        overlayColor: Colors.transparent,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: coreBackground.withOpacity(0.95),
        selectedItemColor: textPrimary,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}

class CupertinoClickable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;

  const CupertinoClickable({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 0.98,
  });

  @override
  State<CupertinoClickable> createState() => _CupertinoClickableState();
}

class _CupertinoClickableState extends State<CupertinoClickable> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleFactor).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => widget.onTap != null ? _controller.forward() : null,
      onTapUp: (_) => widget.onTap != null ? _controller.reverse() : null,
      onTapCancel: () => widget.onTap != null ? _controller.reverse() : null,
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
