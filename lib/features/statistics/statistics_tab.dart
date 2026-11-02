import 'dart:math' as math;

import 'package:anki_core/anki_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/study_day.dart';
import '../../theme/app_theme.dart';
import '../deck/card_status.dart';
import 'stats.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

class StatisticsTab extends ConsumerWidget {
  const StatisticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reviewsProvider);
    final cards = ref.watch(allCardsProvider);
    final now = ref.watch(nowProvider);
    final today = dayOf(now);
    final perDay = reviewsPerDay(reviews);
    final monthAgo = addDays(today, -29);
    final lastMonth = [
      for (final r in reviews)
        if (!dayOf(r.reviewedAt).isBefore(monthAgo)) r,
    ];
    final recall = retention(lastMonth);
    final phases = phaseCounts(cards);
    final streak = currentStreak(perDay, today);

    final tiles = [
      _StatTile(
        key: const Key('stat-today'),
        label: 'Reviewed today',
        value: '${perDay[today] ?? 0}',
        detail: '${_plural(lastMonth.length, 'review')} in 30 days',
      ),
      _StatTile(
        key: const Key('stat-streak'),
        label: 'Current streak',
        value: _plural(streak, 'day'),
        detail: 'Longest ${_plural(longestStreak(perDay), 'day')}',
      ),
      _StatTile(
        key: const Key('stat-retention'),
        label: 'Retention · 30 days',
        value: recall == null ? '—' : '${(recall * 100).round()}%',
        detail: 'Reviews not rated Again',
      ),
      _StatTile(
        key: const Key('stat-cards'),
        label: 'Cards',
        value: '${cards.length}',
        detail:
            '${phases[CardPhase.fresh]} new · '
            '${phases[CardPhase.learning]} learning · '
            '${phases[CardPhase.review]} review',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final tileWidth = wide
            ? (math.min(constraints.maxWidth, 1040) - 48 - 3 * 16) / 4
            : (constraints.maxWidth - 48 - 16) / 2;
        final ratings = _Panel(
          title: 'Ratings',
          subtitle: 'All time',
          child: _RatingBars(counts: ratingCounts(reviews)),
        );
        final upcoming = _Panel(
          title: 'Upcoming',
          subtitle: 'Cards due in the next 14 days',
          child: _ForecastBars(
            counts: dueForecast(cards, now, 14),
            today: studyDayOf(now),
          ),
        );
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final t in tiles)
                      SizedBox(width: math.max(tileWidth, 140), child: t),
                  ],
                ),
                const SizedBox(height: 16),
                _Panel(
                  title: 'Activity',
                  subtitle:
                      '${_plural(_lastYearTotal(perDay, today), 'review')} '
                      'in the last year',
                  child: ActivityHeatmap(perDay: perDay, today: today),
                ),
                const SizedBox(height: 16),
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: ratings),
                        const SizedBox(width: 16),
                        Expanded(child: upcoming),
                      ],
                    ),
                  )
                else ...[
                  ratings,
                  const SizedBox(height: 16),
                  upcoming,
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static int _lastYearTotal(Map<DateTime, int> perDay, DateTime today) {
    final from = addDays(today, -ActivityHeatmap.weeks * 7);
    var total = 0;
    for (final MapEntry(:key, :value) in perDay.entries) {
      if (key.isAfter(from) && !key.isAfter(today)) total += value;
    }
    return total;
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => _Surface(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

/// Columns are Monday-first weeks ending with the current one.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key, required this.perDay, required this.today});

  final Map<DateTime, int> perDay;
  final DateTime today;

  static const weeks = 53;
  static const _cell = 12.0;
  static const _gap = 3.0;
  static const _pitch = _cell + _gap;
  static const _empty = AppColors.surfaceHover;

  /// Validated as a monotone single-hue ramp against [AppColors.surface].
  static const ramp = [
    Color(0xFF3A5E42),
    Color(0xFF4E8258),
    Color(0xFF69A672),
    Color(0xFF93D09B),
  ];

  static Color colorFor(int count, int max) => count == 0 || max == 0
      ? _empty
      : ramp[((count / max) * ramp.length).ceil().clamp(1, ramp.length) - 1];

  @override
  Widget build(BuildContext context) {
    final start = addDays(today, -(today.weekday - 1) - (weeks - 1) * 7);
    var max = 0;
    for (var i = 0; i < weeks * 7; i++) {
      max = math.max(max, perDay[addDays(start, i)] ?? 0);
    }
    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: weeks * _pitch,
          height: 18,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var w = 0; w < weeks; w++)
                if (_monthStartsIn(addDays(start, w * 7)) case final month?)
                  Positioned(
                    left: w * _pitch,
                    child: Text(
                      _months[month - 1],
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var w = 0; w < weeks; w++)
              Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: Column(
                  children: [
                    for (var d = 0; d < 7; d++)
                      _cellAt(addDays(start, w * 7 + d), max),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var d = 0; d < 7; d++)
                    SizedBox(
                      height: _pitch,
                      child: d.isEven && d < 6
                          ? Text(
                              _weekdays[d],
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.1,
                                color: AppColors.textMuted,
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Align(alignment: Alignment.centerLeft, child: grid),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              'Less',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(width: 6),
            for (final c in [_empty, ...ramp])
              Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: _swatch(c),
              ),
            const SizedBox(width: 3),
            const Text(
              'More',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  int? _monthStartsIn(DateTime weekStart) {
    for (var d = 0; d < 7; d++) {
      final day = addDays(weekStart, d);
      if (day.day == 1 && !day.isAfter(today)) return day.month;
    }
    return null;
  }

  Widget _cellAt(DateTime day, int max) {
    if (day.isAfter(today)) return const SizedBox(width: _cell, height: _pitch);
    final count = perDay[day] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Tooltip(
        message:
            '${count == 0 ? 'No reviews' : _plural(count, 'review')} · '
            '${_date(day)}',
        waitDuration: const Duration(milliseconds: 150),
        child: _swatch(colorFor(count, max)),
      ),
    );
  }

  static Widget _swatch(Color color) => Container(
    width: _cell,
    height: _cell,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2.5),
    ),
  );
}

class _RatingBars extends StatelessWidget {
  const _RatingBars({required this.counts});

  final Map<Rating, int> counts;

  static const _labels = {
    Rating.again: 'Again',
    Rating.hard: 'Hard',
    Rating.good: 'Good',
    Rating.easy: 'Easy',
  };

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    final max = counts.values.fold(0, math.max);
    return Column(
      children: [
        for (final r in Rating.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    _labels[r]!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 10,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: max == 0 ? 0 : counts[r]! / max,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.cool,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    total == 0
                        ? '0'
                        : '${counts[r]} · ${(counts[r]! * 100 / total).round()}%',
                    key: Key('rating-${r.name}'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ForecastBars extends StatelessWidget {
  const _ForecastBars({required this.counts, required this.today});

  final List<int> counts;
  final DateTime today;

  static const _height = 96.0;

  @override
  Widget build(BuildContext context) {
    final max = counts.fold(0, math.max);
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < counts.length; i++)
                Expanded(
                  child: Tooltip(
                    message:
                        '${_plural(counts[i], 'card')} · '
                        '${i == 0 ? 'today (incl. overdue)' : _date(addDays(today, i))}',
                    waitDuration: const Duration(milliseconds: 150),
                    child: Container(
                      color: Colors.transparent,
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        height: max == 0
                            ? 2
                            : math.max(2, _height * counts[i] / max),
                        decoration: BoxDecoration(
                          color: counts[i] == 0
                              ? AppColors.surfaceRaised
                              : AppColors.cool,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.border),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < counts.length; i++)
              Expanded(
                child: Text(
                  i == 0
                      ? 'Today'
                      : i % 7 == 0
                      ? _weekdays[addDays(today, i).weekday - 1]
                      : '',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
