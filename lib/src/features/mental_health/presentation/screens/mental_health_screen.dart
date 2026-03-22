import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/mental_health_repository.dart';

class MentalHealthScreen extends ConsumerWidget {
  const MentalHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(mentalHealthDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mental Health'),
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
            onRetry: () => ref.invalidate(mentalHealthDashboardProvider)),
        data: (data) => _Dashboard(data: data),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _Dashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data['total_sessions'] as int? ?? 0;
    final avgOverall = (data['average_mood_overall'] as num?)?.toDouble() ?? 0;
    final daily = (data['daily'] as List?) ?? [];
    final weekly = (data['weekly'] as List?) ?? [];
    final monthly = (data['monthly'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Stats row
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Total Sessions',
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
        const SizedBox(height: 24),

        if (total == 0) ...[
          _EmptyState(),
        ] else ...[
          // Daily chart
          if (daily.isNotEmpty) ...[
            Text('Last 7 Days', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _MoodChart(dataPoints: daily, color: AppColors.primary),
            const SizedBox(height: 24),
          ],

          // Weekly chart
          if (weekly.isNotEmpty) ...[
            Text('Weekly Averages',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _MoodChart(dataPoints: weekly, color: AppColors.accent),
            const SizedBox(height: 24),
          ],

          // Monthly chart
          if (monthly.isNotEmpty) ...[
            Text('Monthly Averages',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _MoodChart(dataPoints: monthly, color: const Color(0xFF7C6BD3)),
            const SizedBox(height: 24),
          ],

          // Mood legend
          _MoodLegend(),
        ],

        const SizedBox(height: 12),
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
      ],
    );
  }

  Color _moodColor(double score) {
    if (score >= 8) return const Color(0xFF4CAF50);
    if (score >= 6) return const Color(0xFF8BC34A);
    if (score >= 4) return const Color(0xFFFFC107);
    return AppColors.error;
  }
}

class _MoodChart extends StatelessWidget {
  final List dataPoints;
  final Color color;

  const _MoodChart({required this.dataPoints, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = dataPoints.asMap().entries.map((entry) {
      final point = entry.value as Map<String, dynamic>;
      final avg = (point['average_mood'] as num?)?.toDouble() ?? 0;
      return FlSpot(entry.key.toDouble(), avg);
    }).toList();

    if (spots.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 10,
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Theme.of(context).colorScheme.secondary, strokeWidth: 1),
            drawVerticalLine: false,
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                reservedSize: 28,
                getTitlesWidget: (v, meta) => Text(
                  v.toInt().toString(),
                  style: TextStyle(
                      fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= dataPoints.length) return const SizedBox();
                  final point = dataPoints[i] as Map<String, dynamic>;
                  final label =
                      (point['date'] ?? point['week'] ?? point['month'])
                              ?.toString() ??
                          '';
                  final short = label.length > 5
                      ? label.substring(label.length - 5)
                      : label;
                  return Text(short,
                      style: TextStyle(
                          fontSize: 9, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)));
                },
              ),
            ),
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
              color: color,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: color ?? Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  )),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MoodLegend extends StatelessWidget {
  const _MoodLegend();

  @override
  Widget build(BuildContext context) {
    const entries = [
      (color: Color(0xFF4CAF50), label: '8–10: Great'),
      (color: Color(0xFF8BC34A), label: '6–7: Good'),
      (color: Color(0xFFFFC107), label: '4–5: Neutral'),
      (color: Color(0xFFFF9800), label: '2–3: Low'),
      (color: Color(0xFFD94F4F), label: '0–1: Very low'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: entries
          .map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: e.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(e.label,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontSize: 11)),
                ],
              ))
          .toList(),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Could not load dashboard',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Check your connection and try again.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.self_improvement_rounded,
                size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No data yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Talk to Orbz to start tracking your mood. Your progress will appear here.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
