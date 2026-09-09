import 'package:flutter/material.dart';

/// Plays once on mount; give children stable keys so re-renders do not replay.
class StaggeredEntry extends StatefulWidget {
  const StaggeredEntry({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<StaggeredEntry>
    with SingleTickerProviderStateMixin {
  static const _step = Duration(milliseconds: 35);
  static const _maxDelay = Duration(milliseconds: 420);
  static const _curve = Cubic(0.16, 1, 0.3, 1);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: _curve,
  );

  @override
  void initState() {
    super.initState();
    final delay = _step * widget.index;
    Future<void>.delayed(delay > _maxDelay ? _maxDelay : delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (_, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - _t.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}
