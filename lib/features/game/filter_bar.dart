import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One switch in the filter bar.
class FilterItem {
  const FilterItem({
    required this.id,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.icon,
    this.color = AppColors.player,
  });

  final String id;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  /// Shown as a dot (players) or icon colour; also the selected background.
  final Color color;
}

/// Horizontally scrollable row of filter chips under the header (R-HUNT-01).
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.items});

  final List<FilterItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        key: const Key('filterBar'),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final item = items[i];
          return FilterChip(
            key: Key('filter_${item.id}'),
            selected: item.selected,
            showCheckmark: false,
            onSelected: item.onChanged,
            visualDensity: VisualDensity.compact,
            backgroundColor: AppColors.surface.withValues(alpha: 0.92),
            selectedColor: item.color.withValues(alpha: 0.3),
            side: BorderSide(
              color: item.selected ? item.color : AppColors.outline,
              width: item.selected ? 1.5 : 1,
            ),
            avatar: item.icon != null
                ? Icon(
                    item.icon,
                    size: 16,
                    color: item.selected ? item.color : AppColors.textMuted,
                  )
                : Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                    ),
                  ),
            label: Text(
              item.label,
              style: TextStyle(
                fontSize: 12,
                color: item.selected ? Colors.white : AppColors.textMuted,
              ),
            ),
          );
        },
      ),
    );
  }
}
