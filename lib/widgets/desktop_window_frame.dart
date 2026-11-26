import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:onlystream/services/desktop_window_controller.dart';
import 'package:onlystream/theme/app_theme.dart';

/// Monochrome cinema desktop window frame with custom titlebar, caption controls,
/// drag-to-move, double-click maximize/restore, and 8-direction edge resizing.
///
/// Renders [child] directly on mobile/web platforms where native OS chrome is
/// used. Designed to be mounted in `MaterialApp.builder` (above `Overlay`, so
/// it intentionally avoids `Tooltip` in favor of `Semantics`).
class DesktopWindowFrame extends StatefulWidget {
  final Widget child;
  final DesktopWindowController? controller;

  const DesktopWindowFrame({
    super.key,
    required this.child,
    this.controller,
  });

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame> {
  late DesktopWindowController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DesktopWindowController.instance;
    _controller.addListener(_onWindowChanged);
  }

  @override
  void didUpdateWidget(covariant DesktopWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.controller ?? DesktopWindowController.instance;
    if (!identical(next, _controller)) {
      _controller.removeListener(_onWindowChanged);
      _controller = next;
      _controller.addListener(_onWindowChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onWindowChanged);
    super.dispose();
  }

  void _onWindowChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isSupported) {
      return widget.child;
    }

    final showBorder = !_controller.isMaximized && !_controller.isFullscreen;
    final showTitleBar = _controller.showTitleBar;
    final showResizeHandles = showBorder;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: showBorder
            ? Border.all(color: AppColors.border, width: 1)
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(showBorder ? 1 : 0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                if (showTitleBar) _buildTitleBar(),
                Expanded(child: widget.child),
              ],
            ),
            if (showResizeHandles) ..._buildResizeHandles(),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    final focused = _controller.isFocused;
    final titleColor = focused ? AppColors.textPrimary : AppColors.textSecondary;
    final iconColor = focused ? AppColors.textSecondary : AppColors.textMuted;

    return Container(
      key: const Key('desktop_window_titlebar'),
      height: 38,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => _controller.startDragging(),
              onDoubleTap: () => _controller.toggleMaximize(),
              child: SizedBox(
                height: 37,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.play_circle_outline_rounded,
                          size: 18,
                          color: titleColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'OnlyStream',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _WindowCaptionButton(
            key: const Key('window_minimize_button'),
            semanticsLabel: 'Riduci a icona',
            icon: Icons.horizontal_rule_rounded,
            iconColor: iconColor,
            hoverBackground: Colors.white10,
            hoverIconColor: AppColors.textPrimary,
            onPressed: _controller.minimize,
          ),
          _WindowCaptionButton(
            key: const Key('window_maximize_button'),
            semanticsLabel:
                _controller.isMaximized ? 'Ripristina' : 'Massimizza',
            icon: _controller.isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: _controller.isMaximized ? 13 : 15,
            iconColor: iconColor,
            hoverBackground: Colors.white10,
            hoverIconColor: AppColors.textPrimary,
            onPressed: _controller.toggleMaximize,
          ),
          _WindowCaptionButton(
            key: const Key('window_close_button'),
            semanticsLabel: 'Chiudi',
            icon: Icons.close_rounded,
            iconColor: iconColor,
            hoverBackground: AppColors.accent,
            hoverIconColor: AppColors.textPrimary,
            onPressed: _controller.close,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResizeHandles() {
    const double corner = 10;
    const double topEdge = 4;
    const double edge = 6;

    return [
      // Edges (excluding corner squares so diagonal resize takes priority)
      Positioned(
        top: 0,
        left: corner,
        right: corner,
        height: topEdge,
        child: _ResizeHitArea(
          cursor: SystemMouseCursors.resizeUpDown,
          onStartResize: () => _controller.startResizing(WindowResizeEdge.top),
        ),
      ),
      Positioned(
        bottom: 0,
        left: corner,
        right: corner,
        height: edge,
        child: _ResizeHitArea(
          cursor: SystemMouseCursors.resizeUpDown,
          onStartResize: () =>
              _controller.startResizing(WindowResizeEdge.bottom),
        ),
      ),
      Positioned(
        top: corner,
        bottom: corner,
        left: 0,
        width: edge,
        child: _ResizeHitArea(
          cursor: SystemMouseCursors.resizeLeftRight,
          onStartResize: () => _controller.startResizing(WindowResizeEdge.left),
        ),
      ),
      Positioned(
        top: corner,
        bottom: corner,
        right: 0,
        width: edge,
        child: _ResizeHitArea(
          cursor: SystemMouseCursors.resizeLeftRight,
          onStartResize: () =>
              _controller.startResizing(WindowResizeEdge.right),
        ),
      ),
      // Corners
      Positioned(
        top: 0,
        left: 0,
        width: corner,
        height: corner,
        child: _ResizeHitArea(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          onStartResize: () =>
              _controller.startResizing(WindowResizeEdge.topLeft),
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        width: corner,
        height: corner,
        child: _ResizeHitArea(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          onStartResize: () =>
              _controller.startResizing(WindowResizeEdge.topRight),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        width: corner,
        height: corner,
        child: _ResizeHitArea(
          cursor: SystemMouseCursors.resizeUpRightDownLeft,
          onStartResize: () =>
              _controller.startResizing(WindowResizeEdge.bottomLeft),
        ),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        width: corner,
        height: corner,
        child: _ResizeHitArea(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          onStartResize: () =>
              _controller.startResizing(WindowResizeEdge.bottomRight),
        ),
      ),
    ];
  }
}

class _WindowCaptionButton extends StatefulWidget {
  final String semanticsLabel;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final Color hoverBackground;
  final Color hoverIconColor;
  final VoidCallback onPressed;

  const _WindowCaptionButton({
    super.key,
    required this.semanticsLabel,
    required this.icon,
    this.iconSize = 15,
    required this.iconColor,
    required this.hoverBackground,
    required this.hoverIconColor,
    required this.onPressed,
  });

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 44,
            height: 37,
            color: _hovered ? widget.hoverBackground : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered ? widget.hoverIconColor : widget.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeHitArea extends StatelessWidget {
  final MouseCursor cursor;
  final VoidCallback onStartResize;

  const _ResizeHitArea({
    required this.cursor,
    required this.onStartResize,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      opaque: false,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if ((event.buttons & kPrimaryMouseButton) != 0) {
            onStartResize();
          }
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
