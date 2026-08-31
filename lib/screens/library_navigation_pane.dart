import 'package:flutter/material.dart';

export 'library_navigation_pane.dart' show LibrarySection;

enum LibrarySection { artists, albums, songs }

class LibraryNavigationPane extends StatelessWidget {
  const LibraryNavigationPane({
    super.key,
    required this.paneWidth,
    required this.selectedSection,
    required this.collapsed,
    required this.onSelectSection,
    required this.onResize,
  });

  final double paneWidth;
  final LibrarySection selectedSection;
  final bool collapsed;
  final ValueChanged<LibrarySection> onSelectSection;
  final ValueChanged<DragUpdateDetails> onResize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface.withValues(alpha: 0.92);
    final outline = theme.colorScheme.outlineVariant.withValues(alpha: 0.75);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: paneWidth,
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          right: BorderSide(color: outline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: <Color>[
                        Color(0xFF52C0A8),
                        Color(0xFF3C8DAD),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                  ),
                ),
                if (!collapsed) ...<Widget>[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Library',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Artists and albums',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          _NavigationItem(
            collapsed: collapsed,
            selected: selectedSection == LibrarySection.artists,
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: 'Artists',
            onTap: () => onSelectSection(LibrarySection.artists),
          ),
          _NavigationItem(
            collapsed: collapsed,
            selected: selectedSection == LibrarySection.albums,
            icon: Icons.album_outlined,
            selectedIcon: Icons.album_rounded,
            label: 'Albums',
            onTap: () => onSelectSection(LibrarySection.albums),
          ),
          _NavigationItem(
            collapsed: collapsed,
            selected: selectedSection == LibrarySection.songs,
            icon: Icons.music_note_outlined,
            selectedIcon: Icons.music_note_rounded,
            label: 'Songs',
            onTap: () => onSelectSection(LibrarySection.songs),
          ),
          const Spacer(),
          _ResizeHandle(onDragUpdate: onResize),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.collapsed,
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool collapsed;
  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primaryContainer;
    final selectedForeground = theme.colorScheme.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: selected ? selectedColor.withValues(alpha: 0.7) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 14 : 16,
              vertical: collapsed ? 14 : 16,
            ),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: <Widget>[
                Icon(
                  selected ? selectedIcon : icon,
                  color: selected
                      ? selectedForeground
                      : theme.colorScheme.onSurfaceVariant,
                ),
                if (!collapsed) ...<Widget>[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? selectedForeground
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDragUpdate});

  final ValueChanged<DragUpdateDetails> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: onDragUpdate,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Container(
              width: 40,
              height: 6,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
