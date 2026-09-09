import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class CardFace extends StatelessWidget {
  const CardFace(
    this.markdown, {
    super.key,
    required this.style,
    this.align = WrapAlignment.start,
  });

  final String markdown;
  final TextStyle? style;
  final WrapAlignment align;

  @override
  Widget build(BuildContext context) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return MarkdownBody(
      data: markdown,
      selectable: false,
      styleSheet: base.copyWith(
        p: base.p?.merge(style),
        listBullet: base.listBullet?.merge(style),
        textAlign: align,
      ),
    );
  }
}
