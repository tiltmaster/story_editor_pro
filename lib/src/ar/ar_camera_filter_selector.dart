import 'package:flutter/material.dart';

import 'ar_filter.dart';
import 'ar_filter_catalog.dart';
import 'ar_filter_controller.dart';

/// Locale-aware, RTL-safe selector for [ArCameraFilterSurface].
class ArCameraFilterSelector extends StatelessWidget {
  const ArCameraFilterSelector({
    super.key,
    required this.controller,
    this.height = 94,
    this.onSelected,
    this.labelBuilder,
  });

  final ArCameraFilterController controller;
  final double height;
  final ValueChanged<ArCameraFilter>? onSelected;

  /// Optional host localization hook, typically
  /// `strings.filterNameForPreset`. Built-in EN/AR labels remain the fallback.
  final String Function(String presetId)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView.separated(
          key: const ValueKey<String>('ar-filter-selector'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
          itemCount: ArCameraFilterCatalog.filters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final filter = ArCameraFilterCatalog.filters[index];
            final selected = filter.id == controller.selectedId;
            final hostLabel = labelBuilder?.call(filter.presetId);
            final name = hostLabel == null || hostLabel.trim().isEmpty
                ? filter.localizedName(locale)
                : hostLabel;
            return Semantics(
              button: true,
              selected: selected,
              label: name,
              child: InkResponse(
                key: ValueKey<String>('ar-filter-${filter.presetId}'),
                radius: 38,
                onTap: () {
                  controller.select(filter.id);
                  onSelected?.call(filter);
                },
                child: SizedBox(
                  width: 66,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: selected ? 56 : 50,
                        height: selected ? 56 : 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: filter.previewColors,
                          ),
                          border: Border.all(
                            color: selected ? Colors.white : Colors.white54,
                            width: selected ? 3 : 1,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(color: Colors.black38, blurRadius: 5),
                          ],
                        ),
                        child: Icon(filter.icon, color: Colors.white, size: 23),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black87, blurRadius: 3),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
