import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Real decoded video frames with draggable in/out handles and tap-to-seek.
class VideoTrimTimeline extends StatefulWidget {
  const VideoTrimTimeline({
    super.key,
    required this.path,
    required this.durationMs,
    required this.startMs,
    required this.endMs,
    required this.onChanged,
    required this.onSeek,
    this.mirrored = false,
  });
  final String path;
  final int durationMs, startMs, endMs;
  final bool mirrored;
  final ValueChanged<RangeValues> onChanged;
  final ValueChanged<int> onSeek;
  @override
  State<VideoTrimTimeline> createState() => _VideoTrimTimelineState();
}

class _VideoTrimTimelineState extends State<VideoTrimTimeline> {
  late Future<List<Uint8List>> _frames;
  void _load() {
    _frames = const MethodChannel('story_editor_pro')
        .invokeListMethod<Uint8List>('getVideoThumbnails', {
          'path': widget.path,
          'count': 10,
        })
        .then((value) {
          if (value == null || value.isEmpty) {
            throw StateError('No video frames were decoded');
          }
          return value;
        });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final accent = Theme.of(context).colorScheme.primary;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth - 24;
          final left = 12 + width * widget.startMs / widget.durationMs;
          final right = 12 + width * widget.endMs / widget.durationMs;
          void adjust(bool start, double dx) {
            final delta = dx * widget.durationMs / width;
            final a = start
                ? (widget.startMs + delta)
                      .clamp(0, widget.endMs - 250)
                      .toDouble()
                : widget.startMs.toDouble();
            final b = start
                ? widget.endMs.toDouble()
                : (widget.endMs + delta)
                      .clamp(widget.startMs + 250, widget.durationMs)
                      .toDouble();
            widget.onChanged(RangeValues(a, b));
            widget.onSeek((start ? a : b).round());
          }

          Widget handle(bool start) => Semantics(
            label: start
                ? (rtl ? 'بداية المقطع' : 'Clip start')
                : (rtl ? 'نهاية المقطع' : 'Clip end'),
            value:
                '${((start ? widget.startMs : widget.endMs) / 1000).toStringAsFixed(1)} s',
            slider: true,
            increasedValue:
                '${((start ? (widget.startMs + 250).clamp(0, widget.endMs - 250) : (widget.endMs + 250).clamp(widget.startMs + 250, widget.durationMs)) / 1000).toStringAsFixed(1)} s',
            decreasedValue:
                '${((start ? (widget.startMs - 250).clamp(0, widget.endMs - 250) : (widget.endMs - 250).clamp(widget.startMs + 250, widget.durationMs)) / 1000).toStringAsFixed(1)} s',
            onIncrease: () => adjust(start, width * 250 / widget.durationMs),
            onDecrease: () => adjust(start, -width * 250 / widget.durationMs),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (event) => adjust(start, event.delta.dx),
              child: SizedBox(
                width: 28,
                height: 88,
                child: Center(
                  child: Container(
                    width: 16,
                    height: 76,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Icon(
                      Icons.drag_indicator,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
          return SizedBox(
            height: 88,
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  top: 8,
                  bottom: 8,
                  child: GestureDetector(
                    onTapDown: (event) => widget.onSeek(
                      (event.localPosition.dx / width * widget.durationMs)
                          .round()
                          .clamp(widget.startMs, widget.endMs),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: FutureBuilder<List<Uint8List>>(
                        future: _frames,
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return TextButton.icon(
                              onPressed: () => setState(_load),
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                rtl ? 'إعادة تحميل الإطارات' : 'Reload frames',
                              ),
                            );
                          }
                          final frames = snap.data;
                          if (frames == null) {
                            return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          }
                          return Row(
                            children: [
                              for (final frame in frames)
                                Expanded(
                                  child: Transform.flip(
                                    flipX: widget.mirrored,
                                    child: Image.memory(
                                      frame,
                                      height: 72,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  width: (left - 12).clamp(0, width),
                  top: 8,
                  bottom: 8,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Colors.black54),
                  ),
                ),
                Positioned(
                  left: right,
                  right: 12,
                  top: 8,
                  bottom: 8,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Colors.black54),
                  ),
                ),
                Positioned(
                  left: left,
                  width: right - left,
                  top: 7,
                  bottom: 7,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: accent, width: 3),
                          bottom: BorderSide(color: accent, width: 3),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(left: left - 14, child: handle(true)),
                Positioned(left: right - 14, child: handle(false)),
              ],
            ),
          );
        },
      ),
    );
  }
}
