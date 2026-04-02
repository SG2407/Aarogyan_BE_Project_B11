import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/profile/data/profile_repository.dart';
import '../../data/mental_health_repository.dart';

// ─── Emotion meta ─────────────────────────────────────────────────────────────
class _EmotionMeta {
  final String label;
  final String emoji;
  final Color color;
  const _EmotionMeta(this.label, this.emoji, this.color);
}

const _emotions = {
  'happy': _EmotionMeta('Happy', '😊', Color(0xFF4CAF50)),
  'sad': _EmotionMeta('Sad', '😢', Color(0xFF42A5F5)),
  'angry': _EmotionMeta('Angry', '😠', Color(0xFFEF5350)),
  'neutral': _EmotionMeta('Neutral', '😐', Color(0xFF78909C)),
};

// ─── Screen ───────────────────────────────────────────────────────────────────
class MentalHealthScreen extends ConsumerWidget {
  const MentalHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(mentalHealthDashboardProvider);
    final filter = ref.watch(dashboardFilterProvider);
    final lang = ref.watch(preferredLanguageProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(appStr(lang, 'mental_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(mentalHealthDashboardProvider),
          ),
        ],
      ),
      body: dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
            lang: lang,
            onRetry: () => ref.invalidate(mentalHealthDashboardProvider)),
        data: (data) => _Dashboard(data: data, filter: filter, lang: lang),
      ),
    );
  }
}

// ─── Dashboard ────────────────────────────────────────────────────────────────
class _Dashboard extends ConsumerWidget {
  final Map<String, dynamic> data;
  final int filter;
  final String lang;
  const _Dashboard(
      {required this.data, required this.filter, required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = data['total_sessions'] as int? ?? 0;
    final avgOverall = (data['average_mood_overall'] as num?)?.toDouble() ?? 0;
    final daily = (data['daily'] as List?) ?? [];
    final heatmap = (data['heatmap'] as List?) ?? [];
    final emotionDist = (data['emotion_distribution'] as Map?) ?? {};
    final latestSession = data['latest_session'] as Map?;
    final dominantEmotion = (data['dominant_emotion'] as String?) ?? 'neutral';
    final convSessions = (data['conversation_sessions'] as List?) ?? [];

    debugPrint(
        '[MentalHealth] total=$total daily=${daily.length} heatmap=${heatmap.length} emotions=$emotionDist');

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // ── Time filter chips ──────────────────────────────────────────────
        _TimeFilterChips(selected: filter),
        const SizedBox(height: 20),

        // ── Hero: Latest Emotion Card (#9) ─────────────────────────────────
        if (latestSession != null) ...[
          _LatestEmotionCard(session: latestSession, lang: lang),
          const SizedBox(height: 20),
        ],

        // ── Stat cards ─────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Sessions',
                value: '$total',
                icon: Icons.self_improvement_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Avg Mood',
                value: avgOverall > 0 ? avgOverall.toStringAsFixed(1) : '—',
                icon: Icons.sentiment_satisfied_alt_rounded,
                color: _moodColor(avgOverall),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Dominant emotion card ──────────────────────────────────────────
        if (total > 0) ...[
          _DominantEmotionCard(emotion: dominantEmotion),
          const SizedBox(height: 24),
        ],

        if (total == 0) ...[
          _EmptyState(lang: lang),
        ] else ...[
          // ── Mood Trend Line (#1) ─────────────────────────────────────────
          _SectionTitle(appStr(lang, 'mood_trend')),
          const SizedBox(height: 12),
          _MoodTrendChart(dataPoints: daily),
          const SizedBox(height: 24),

          // ── Emotion Donut (#2) ────────────────────────────────────────
          _SectionTitle(appStr(lang, 'emotion_breakdown')),
          const SizedBox(height: 12),
          _EmotionDonutChart(distribution: emotionDist),
          const SizedBox(height: 24),

          // ── Conversation Sessions ────────────────────────────────────────
          if (convSessions.isNotEmpty) ...[
            _SectionTitle('Conversation Sessions'),
            const SizedBox(height: 12),
            _ConversationSessionsList(sessions: convSessions),
            const SizedBox(height: 24),
          ],

          // ── Heatmap Calendar (#4) ────────────────────────────────────────
          _SectionTitle(appStr(lang, 'mood_calendar')),
          const SizedBox(height: 12),
          _MoodHeatmap(heatmap: heatmap),
          const SizedBox(height: 24),

          // ── Session Activity Bar (#7) ──────────────────────────────────
          _SectionTitle(appStr(lang, 'session_activity')),
          const SizedBox(height: 12),
          _SessionActivityChart(dataPoints: daily),
          const SizedBox(height: 24),

          // ── Mood legend ──────────────────────────────────────────────────
          _MoodLegend(),
          const SizedBox(height: 16),
        ],

        // ── Tip card ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.tips_and_updates_rounded,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Talk to Orbz regularly to track your mental wellbeing over time.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Color _moodColor(double score) {
    if (score >= 7) return const Color(0xFF4CAF50);
    if (score >= 4) return const Color(0xFFFFC107);
    return AppColors.error;
  }
}

// ─── Time Filter Chips ────────────────────────────────────────────────────────
class _TimeFilterChips extends ConsumerWidget {
  final int selected;
  const _TimeFilterChips({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = [
      (label: '7 Days', days: 7),
      (label: '30 Days', days: 30),
      (label: '90 Days', days: 90),
      (label: 'All Time', days: 0),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((o) {
          final active = selected == o.days;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(o.label),
              selected: active,
              onSelected: (_) {
                ref.read(dashboardFilterProvider.notifier).state = o.days;
                ref.invalidate(mentalHealthDashboardProvider);
              },
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: active ? Colors.white : null,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Latest Emotion Card (#9) ─────────────────────────────────────────────────
class _LatestEmotionCard extends StatelessWidget {
  final Map session;
  final String lang;
  const _LatestEmotionCard({required this.session, required this.lang});

  @override
  Widget build(BuildContext context) {
    // Prefer ML-detected emotion from emotion_probs if available
    String emotion;
    final ep = session['emotion_probs'];
    if (ep != null && ep is Map && ep.isNotEmpty) {
      emotion = (ep.entries
              .reduce((a, b) => (a.value as num) >= (b.value as num) ? a : b))
          .key as String;
    } else {
      final raw = ((session['emotion'] as String?) ?? 'neutral').toLowerCase();
      const remap = {
        'fearful': 'sad',
        'disgusted': 'angry',
        'surprised': 'happy'
      };
      emotion = remap[raw] ?? raw;
    }
    final meta = _emotions[emotion] ?? _emotions['neutral']!;
    final score = (session['mood_score'] as num?)?.toDouble() ?? 0;
    final createdAt = session['created_at'] as String? ?? '';
    String timeStr = '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      timeStr =
          '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            meta.color.withValues(alpha: 0.15),
            meta.color.withValues(alpha: 0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border:
            Border.all(color: meta.color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Text(meta.emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appStr(lang, 'latest_session'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55))),
                const SizedBox(height: 4),
                Text(meta.label,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: meta.color, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Mood ${score.toStringAsFixed(0)}/10',
                          style: TextStyle(
                              color: meta.color,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                  ],
                ),
                if (timeStr.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(timeStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.45))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dominant Emotion Card ────────────────────────────────────────────────────
class _DominantEmotionCard extends StatelessWidget {
  final String emotion;
  const _DominantEmotionCard({required this.emotion});

  @override
  Widget build(BuildContext context) {
    final meta = _emotions[emotion] ?? _emotions['neutral']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: meta.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Text(meta.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dominant Mood',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55))),
              Text(meta.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: meta.color, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Conversation Sessions List ───────────────────────────────────────────────
class _ConversationSessionsList extends StatelessWidget {
  final List sessions;
  const _ConversationSessionsList({required this.sessions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _cardDecor(context),
      child: Column(
        children: [
          for (int i = 0; i < sessions.length; i++) ...[
            _ConversationSessionTile(
                session: sessions[i] as Map<String, dynamic>),
            if (i < sessions.length - 1)
              Divider(
                  height: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.06)),
          ],
        ],
      ),
    );
  }
}

class _ConversationSessionTile extends StatelessWidget {
  final Map<String, dynamic> session;
  const _ConversationSessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final dominant = (session['dominant_emotion'] as String?) ?? 'neutral';
    final meta = _emotions[dominant] ?? _emotions['neutral']!;
    final msgCount = (session['message_count'] as num?)?.toInt() ?? 0;
    final stability = (session['stability_score'] as num?)?.toInt() ?? 0;
    final avgMood = (session['average_mood'] as num?)?.toDouble() ?? 0;
    final insight = session['insight_summary'] as String? ?? '';
    final startedAt = session['started_at'] as String? ?? '';

    String timeStr = '';
    try {
      final dt = DateTime.parse(startedAt).toLocal();
      timeStr =
          '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(meta.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: meta.color,
                          fontSize: 14),
                    ),
                    if (timeStr.isNotEmpty)
                      Text(timeStr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.45),
                                  fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${avgMood.toStringAsFixed(1)}/10',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _moodColorStatic(avgMood))),
                  Text('$msgCount msgs · $stability% stable',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.45),
                          fontSize: 10)),
                ],
              ),
            ],
          ),
          if (insight.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(insight,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                    fontSize: 12,
                    height: 1.3)),
          ],
        ],
      ),
    );
  }

  static Color _moodColorStatic(double score) {
    if (score >= 7) return const Color(0xFF4CAF50);
    if (score >= 4) return const Color(0xFFFFC107);
    return AppColors.error;
  }
}

// ─── Mood Trend Line Chart (#1) ───────────────────────────────────────────────
class _MoodTrendChart extends StatelessWidget {
  final List dataPoints;
  const _MoodTrendChart({required this.dataPoints});

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) return const _NoDataPlaceholder();
    final spots = dataPoints.asMap().entries.map((e) {
      final avg = (e.value['average_mood'] as num?)?.toDouble() ?? 0;
      return FlSpot(e.key.toDouble(), avg);
    }).toList();

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: _cardDecor(context),
      child: LineChart(
        LineChartData(
          minY: 0, maxY: 10,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 2,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.07),
              strokeWidth: 1,
            ),
          ),
          // Shaded zones: red 0–4, yellow 4–7, green 7–10
          rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
            HorizontalRangeAnnotation(
                y1: 0, y2: 4, color: AppColors.error.withValues(alpha: 0.05)),
            HorizontalRangeAnnotation(
                y1: 4,
                y2: 7,
                color: const Color(0xFFFFC107).withValues(alpha: 0.05)),
            HorizontalRangeAnnotation(
                y1: 7,
                y2: 10,
                color: const Color(0xFF4CAF50).withValues(alpha: 0.07)),
          ]),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
                sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45))),
            )),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: math.max(1, (dataPoints.length / 5).ceil()).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= dataPoints.length) return const SizedBox();
                final raw = (dataPoints[i]['date'] ?? '').toString();
                final short = raw.length >= 5 ? raw.substring(5) : raw;
                return Text(short,
                    style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.45)));
              },
            )),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: AppColors.primary,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    AppColors.primary.withValues(alpha: 0.0)
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Emotion Donut Chart (#2) ─────────────────────────────────────────────────
class _EmotionDonutChart extends StatefulWidget {
  final Map distribution;
  const _EmotionDonutChart({required this.distribution});

  @override
  State<_EmotionDonutChart> createState() => _EmotionDonutChartState();
}

class _EmotionDonutChartState extends State<_EmotionDonutChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final total = widget.distribution.values
        .fold<int>(0, (s, v) => s + ((v as num?)?.toInt() ?? 0));
    if (total == 0) return const _NoDataPlaceholder();

    final sections = <PieChartSectionData>[];
    int i = 0;
    for (final entry in _emotions.entries) {
      final count = (widget.distribution[entry.key] as num?)?.toInt() ?? 0;
      if (count == 0) {
        i++;
        continue;
      }
      final pct = count / total * 100;
      final isTouched = i == _touched;
      sections.add(PieChartSectionData(
        value: count.toDouble(),
        color: entry.value.color,
        radius: isTouched ? 68 : 56,
        title: isTouched ? '${pct.toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
      ));
      i++;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(context),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 38,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (_, res) => setState(() {
                    _touched = res?.touchedSection?.touchedSectionIndex ?? -1;
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: _emotions.entries.map((e) {
                final count =
                    (widget.distribution[e.key] as num?)?.toInt() ?? 0;
                if (count == 0) return const SizedBox.shrink();
                final pct = (count / total * 100).toStringAsFixed(0);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: e.value.color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${e.value.emoji} ${e.value.label}',
                        style: const TextStyle(fontSize: 12)),
                    const Spacer(),
                    Text('$pct%',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: e.value.color)),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mood Heatmap Calendar (#4) ───────────────────────────────────────────────
class _MoodHeatmap extends StatelessWidget {
  final List heatmap;
  const _MoodHeatmap({required this.heatmap});

  @override
  Widget build(BuildContext context) {
    if (heatmap.isEmpty) return const _NoDataPlaceholder();

    // Build a lookup map date → mood
    final moodByDate = <String, double>{};
    for (final h in heatmap) {
      final d = h['date'] as String?;
      final m = (h['mood'] as num?)?.toDouble();
      if (d != null && m != null) moodByDate[d] = m;
    }

    // Determine grid range: cover from the earliest session date up to today,
    // always using a multiple of 7 rows (capped at 13 weeks = 91 days).
    final today = DateTime.now();
    DateTime earliest = today;
    for (final h in heatmap) {
      try {
        final d = DateTime.parse(h['date'] as String);
        if (d.isBefore(earliest)) earliest = d;
      } catch (_) {}
    }
    final daySpan = today.difference(earliest).inDays + 1;
    // Round up to a full week row, minimum 7 days, maximum 91 days
    final totalCells = math.min(91, ((math.max(7, daySpan) + 6) ~/ 7) * 7);
    final numRows = totalCells ~/ 7;

    final cells = List.generate(totalCells, (i) {
      final day = today.subtract(Duration(days: totalCells - 1 - i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      return (day: day, mood: moodByDate[key]);
    });

    const weekLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: weekLabels
                .map((l) => Expanded(
                      child: Center(
                        child: Text(l,
                            style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.45))),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          ...List.generate(numRows, (row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: List.generate(7, (col) {
                  final cell = cells[row * 7 + col];
                  final mood = cell.mood;
                  Color cellColor;
                  if (mood == null) {
                    cellColor = Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.06);
                  } else if (mood >= 7) {
                    cellColor = const Color(0xFF4CAF50)
                        .withValues(alpha: 0.15 + mood / 10 * 0.65);
                  } else if (mood >= 4) {
                    cellColor = const Color(0xFFFFC107)
                        .withValues(alpha: 0.3 + mood / 10 * 0.5);
                  } else {
                    cellColor = AppColors.error
                        .withValues(alpha: 0.3 + (4 - mood) / 4 * 0.45);
                  }
                  final isToday = cell.day.year == today.year &&
                      cell.day.month == today.month &&
                      cell.day.day == today.day;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 30,
                      decoration: BoxDecoration(
                        color: cellColor,
                        borderRadius: BorderRadius.circular(6),
                        border: isToday
                            ? Border.all(color: AppColors.primary, width: 1.5)
                            : null,
                      ),
                      child: mood != null
                          ? Center(
                              child: Text(mood.toStringAsFixed(0),
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600)))
                          : null,
                    ),
                  );
                }),
              ),
            );
          }),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _HeatLegendDot(
                  color: AppColors.error.withValues(alpha: 0.55), label: 'Low'),
              const SizedBox(width: 10),
              _HeatLegendDot(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.6),
                  label: 'Mid'),
              const SizedBox(width: 10),
              _HeatLegendDot(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.7),
                  label: 'High'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _HeatLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10)),
    ]);
  }
}

// ─── Session Activity Bar (#7) ────────────────────────────────────────────────
class _SessionActivityChart extends StatelessWidget {
  final List dataPoints;
  const _SessionActivityChart({required this.dataPoints});

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) return const _NoDataPlaceholder();

    final maxCount = dataPoints.fold<int>(
        0, (m, p) => math.max(m, (p['session_count'] as num?)?.toInt() ?? 0));
    if (maxCount == 0) return const _NoDataPlaceholder();

    final barGroups = dataPoints.asMap().entries.map((e) {
      final count = (e.value['session_count'] as num?)?.toDouble() ?? 0;
      return BarChartGroupData(x: e.key, barRods: [
        BarChartRodData(
          toY: count,
          color: AppColors.primary,
          width: dataPoints.length > 20 ? 6 : 14,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: maxCount.toDouble(),
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
          ),
        ),
      ]);
    }).toList();

    return Container(
      height: 150,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: _cardDecor(context),
      child: BarChart(
        BarChartData(
          maxY: maxCount.toDouble() + 0.5,
          barGroups: barGroups,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.07),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
                sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 24,
              getTitlesWidget: (v, _) => v == v.floorToDouble()
                  ? Text(v.toInt().toString(),
                      style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.45)))
                  : const SizedBox(),
            )),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: math.max(1, (dataPoints.length / 5).ceil()).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= dataPoints.length) return const SizedBox();
                final raw = (dataPoints[i]['date'] ?? '').toString();
                final short = raw.length >= 5 ? raw.substring(5) : raw;
                return Text(short,
                    style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.45)));
              },
            )),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
BoxDecoration _cardDecor(BuildContext context) => BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
    );

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _NoDataPlaceholder extends StatelessWidget {
  const _NoDataPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: _cardDecor(context),
      child: Center(
        child: Text('Not enough data yet',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4))),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color ?? AppColors.primary)),
          const SizedBox(height: 2),
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55))),
        ],
      ),
    );
  }
}

class _MoodLegend extends StatelessWidget {
  const _MoodLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mood Score Guide',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Row(
            children: [
              _LegendDot(color: AppColors.error, label: '1–3  Low'),
              const SizedBox(width: 16),
              _LegendDot(color: const Color(0xFFFFC107), label: '4–6  Medium'),
              const SizedBox(width: 16),
              _LegendDot(color: const Color(0xFF4CAF50), label: '7–10 Good'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  final String lang;
  const _EmptyState({required this.lang});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: _cardDecor(context),
      child: Column(
        children: [
          const Text('🤗', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(appStr(lang, 'no_sessions'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(appStr(lang, 'no_sessions_sub'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String lang;
  final VoidCallback onRetry;
  const _ErrorState({required this.lang, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(appStr(lang, 'could_not_load')),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: onRetry, child: Text(appStr(lang, 'retry'))),
        ],
      ),
    );
  }
}
