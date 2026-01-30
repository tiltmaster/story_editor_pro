import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/story_editor_config.dart';
import 'config/story_editor_strings.dart';
import 'config/story_editor_theme.dart';

/// Instagram Story "Create Mode" style GradientTextEditor
/// Select background from preset gradients
class GradientTextEditor extends StatefulWidget {
  /// Called when completed (async supported)
  final Future<void> Function(String text, LinearGradient gradient)? onComplete;

  /// Called when cancelled
  final VoidCallback? onCancel;

  const GradientTextEditor({
    super.key,
    this.onComplete,
    this.onCancel,
  });

  @override
  State<GradientTextEditor> createState() => _GradientTextEditorState();
}

class _GradientTextEditorState extends State<GradientTextEditor> {
  // Text controller
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Processing state
  bool _isProcessing = false;

  // Selected gradient index
  int _selectedGradientIndex = 0;

  // Gradient direction
  Alignment _begin = Alignment.topLeft;
  Alignment _end = Alignment.bottomRight;

  // Color balance (stops) - initialized in initState from config
  late double _balance;

  // Gradient direction index
  int _directionIndex = 0;

  // Gradient directions
  static const List<Map<String, Alignment>> _directions = [
    {'begin': Alignment.topLeft, 'end': Alignment.bottomRight},
    {'begin': Alignment.topCenter, 'end': Alignment.bottomCenter},
    {'begin': Alignment.topRight, 'end': Alignment.bottomLeft},
    {'begin': Alignment.centerLeft, 'end': Alignment.centerRight},
    {'begin': Alignment.bottomLeft, 'end': Alignment.topRight},
    {'begin': Alignment.bottomCenter, 'end': Alignment.topCenter},
  ];

  @override
  void initState() {
    super.initState();
    // Auto-focus keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // Initialize balance from config
      final config = StoryEditorConfigProvider.read(context);
      setState(() {
        _balance = config.defaultGradientBalance;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize balance from config on first build
    if (!_balanceInitialized) {
      final config = context.storyEditorConfig;
      _balance = config.defaultGradientBalance;
      _balanceInitialized = true;
    }
  }

  bool _balanceInitialized = false;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Get gradient presets from config
  List<List<Color>> get _presetGradients {
    final config = context.storyEditorConfig;
    return config.theme.gradients.presets.map((p) => p.colors).toList();
  }

  /// Get direction icons from config
  List<IconData> get _directionIcons {
    final config = context.storyEditorConfig;
    return config.theme.icons.directionIcons;
  }

  /// Get current gradient
  LinearGradient get _currentGradient {
    final presets = _presetGradients;
    final colors = presets[_selectedGradientIndex % presets.length];
    return LinearGradient(
      colors: colors,
      stops: [_balance, 1.0],
      begin: _begin,
      end: _end,
    );
  }

  /// Get next gradient colors (for preview)
  List<Color> get _nextGradientColors {
    final presets = _presetGradients;
    final nextIndex = (_selectedGradientIndex + 1) % presets.length;
    return presets[nextIndex];
  }

  /// Switch to next gradient
  void _nextGradient() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedGradientIndex = (_selectedGradientIndex + 1) % _presetGradients.length;
    });
  }

  /// Change gradient direction
  void _changeDirection() {
    HapticFeedback.selectionClick();
    setState(() {
      _directionIndex = (_directionIndex + 1) % _directions.length;
      _begin = _directions[_directionIndex]['begin']!;
      _end = _directions[_directionIndex]['end']!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = context.storyEditorConfig;
    final strings = config.strings;
    final theme = config.theme;

    // Is current gradient solid (single color)?
    final presets = _presetGradients;
    final colors = presets[_selectedGradientIndex % presets.length];
    final isSolid = colors[0] == colors[1];
    final isWhite = colors[0] == const Color(0xFFFFFFFF);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Animated Gradient Background
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: _currentGradient,
            ),
          ),

          // UI always visible
          SafeArea(
            child: Column(
              children: [
                // Top Bar - Close and Done buttons
                _buildTopBar(isWhite, strings, theme),

                // Text Field (Expanded) - Satır limiti ile
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Ekran yüksekliğine göre maksimum satır sayısı
                      const fontSize = 32.0;
                      const lineHeight = fontSize * 1.3; // Line height factor
                      final maxLines = (constraints.maxHeight / lineHeight).floor().clamp(3, 12);

                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            textAlign: TextAlign.center,
                            maxLines: maxLines,
                            enabled: !_isProcessing,
                            style: TextStyle(
                              color: isWhite ? Colors.black : Colors.white,
                              fontSize: fontSize,
                              fontWeight: FontWeight.bold,
                              shadows: isWhite
                                  ? null
                                  : [
                                      const Shadow(
                                        color: Colors.black38,
                                        offset: Offset(2, 2),
                                        blurRadius: 8,
                                      ),
                                    ],
                            ),
                            decoration: InputDecoration(
                              hintText: strings.gradientWriteSomething,
                              hintStyle: TextStyle(
                                color: isWhite ? Colors.black38 : Colors.white54,
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            cursorColor: isWhite ? Colors.black : Colors.white,
                            cursorWidth: 3,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Bottom Control Panel
                _buildBottomPanel(isWhite, isSolid, strings, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Top bar - close and done buttons
  Widget _buildTopBar(bool isWhite, StoryEditorStrings strings, StoryEditorTheme theme) {
    final iconColor = isWhite ? Colors.black : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Close button
          IconButton(
            onPressed: _isProcessing
                ? null
                : () {
                    widget.onCancel?.call();
                    Navigator.pop(context);
                  },
            icon: Icon(
              theme.icons.closeIcon,
              color: _isProcessing ? iconColor.withValues(alpha: 0.3) : iconColor,
              size: 28,
            ),
          ),

          // Done button or processing indicator
          _isProcessing
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    strings.gradientProcessingImage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : IconButton(
                  onPressed: () async {
                    final text = _textController.text.trim();
                    if (text.isNotEmpty && widget.onComplete != null) {
                      setState(() => _isProcessing = true);
                      await widget.onComplete!(text, _currentGradient);
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  icon: Icon(
                    theme.icons.checkIcon,
                    color: iconColor,
                    size: 28,
                  ),
                ),
        ],
      ),
    );
  }

  /// Bottom control panel
  Widget _buildBottomPanel(bool isWhite, bool isSolid, StoryEditorStrings strings, StoryEditorTheme theme) {
    final nextColors = _nextGradientColors;
    final nextIsSolid = nextColors[0] == nextColors[1];
    final directionIcons = _directionIcons;

    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Control tools
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Direction Button
                GestureDetector(
                  onTap: _isProcessing ? null : _changeDirection,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isWhite ? Colors.black : Colors.white).withValues(alpha: 0.2),
                      border: Border.all(
                        color: isWhite ? Colors.black38 : Colors.white54,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      directionIcons[_directionIndex % directionIcons.length],
                      color: isWhite ? Colors.black : Colors.white,
                      size: 24,
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Balance Slider
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            strings.gradientBalance,
                            style: TextStyle(
                              color: isWhite ? Colors.black54 : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '${(_balance * 100).toInt()}%',
                            style: TextStyle(
                              color: isWhite ? Colors.black : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: isWhite ? Colors.black : Colors.white,
                          inactiveTrackColor: isWhite ? Colors.black26 : Colors.white30,
                          thumbColor: isWhite ? Colors.black : Colors.white,
                          overlayColor: isWhite ? Colors.black12 : Colors.white24,
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: _balance,
                          min: 0.0,
                          max: 0.9,
                          onChanged: _isProcessing
                              ? null
                              : (value) {
                                  setState(() {
                                    _balance = value;
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Next Gradient Button (shows preview)
                GestureDetector(
                  onTap: _isProcessing ? null : _nextGradient,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: nextIsSolid
                          ? null
                          : LinearGradient(
                              colors: nextColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: nextIsSolid ? nextColors[0] : null,
                      border: Border.all(
                        color: isWhite ? Colors.black38 : Colors.white,
                        width: 2,
                      ),
                    ),
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

/// Helper function to open GradientTextEditor
Future<void> openGradientTextEditor(
  BuildContext context, {
  Future<void> Function(String text, LinearGradient gradient)? onComplete,
  VoidCallback? onCancel,
}) async {
  await Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => GradientTextEditor(
        onComplete: onComplete,
        onCancel: onCancel,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    ),
  );
}
