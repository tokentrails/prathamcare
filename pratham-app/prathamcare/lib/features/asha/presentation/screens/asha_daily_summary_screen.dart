import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/network/api_client.dart';

class ASHADailySummaryScreen extends StatefulWidget {
  const ASHADailySummaryScreen({super.key, this.initialData});

  final Map<String, dynamic>? initialData;

  @override
  State<ASHADailySummaryScreen> createState() => _ASHADailySummaryScreenState();
}

class _ASHADailySummaryScreenState extends State<ASHADailySummaryScreen> {
  final ApiClient _apiClient = ApiClient();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.initialData;
    _loading = widget.initialData == null;
    _load(showLoader: widget.initialData == null);
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }

    try {
      final res = await _apiClient.getASHADaySummary();
      if (!mounted) return;
      setState(() {
        _summary = res;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _summary?['totals'] is Map ? (_summary!['totals'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final ranked = _asMapList(_summary?['ranked_appointments']);
    final focus = _asStringList(_summary?['top_focus_points']);
    final warnings = _asStringList(_summary?['warnings']);
    final riskNotes = _asStringList(_summary?['risk_notes']);
    final summaryTextFull = '${_summary?['summary_text_full'] ?? ''}'.trim();
    final totalAppointments = (totals['appointments'] as num?)?.toInt() ?? ranked.length;

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Daily Priority Summary'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0B1220),
      ),
      body: _loading && _summary == null
          ? _buildLoadingSkeleton()
          : RefreshIndicator(
              onRefresh: () => _load(showLoader: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (_error != null) ...[
                    _ErrorCard(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  if (warnings.isNotEmpty) ...[
                    _WarningBanner(message: warnings.join('\n')),
                    const SizedBox(height: 12),
                  ],
                  _KpiRow(totals: totals),
                  const SizedBox(height: 12),
                  if (totalAppointments == 0)
                    _buildEmptyState()
                  else ...[
                    _SectionCard(
                      title: 'Narrative',
                      child: Text(
                        summaryTextFull.isEmpty ? 'Summary not available.' : summaryTextFull,
                        style: const TextStyle(
                          color: AppColors.lightTextSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Top Focus Points',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: focus.isEmpty
                            ? const [
                                Text(
                                  'No focus points available.',
                                  style: TextStyle(color: AppColors.lightTextMuted),
                                ),
                              ]
                            : focus
                                .map(
                                  (point) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 6),
                                          child: Icon(Icons.circle, size: 7, color: AppColors.primary),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            point,
                                            style: const TextStyle(
                                              color: AppColors.lightTextSecondary,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    if (riskNotes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Risk Notes',
                        child: Column(
                          children: riskNotes
                              .map(
                                (note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.lightWarning),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          note,
                                          style: const TextStyle(
                                            color: AppColors.lightTextSecondary,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Ranked Appointments',
                      child: Column(
                        children: ranked
                            .map(
                              (item) => _RankedAppointmentCard(
                                name: '${item['patient_name'] ?? '-'}',
                                score: (item['priority_score'] as num?)?.toInt() ?? 0,
                                level: '${item['priority_level'] ?? 'low'}',
                                reasons: _asStringList(item['reasons']),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(height: 72, decoration: _skeletonBox()),
        const SizedBox(height: 12),
        Container(height: 120, decoration: _skeletonBox()),
        const SizedBox(height: 12),
        Container(height: 160, decoration: _skeletonBox()),
        const SizedBox(height: 12),
        Container(height: 260, decoration: _skeletonBox()),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_busy_outlined, color: AppColors.lightTextMuted),
          SizedBox(height: 8),
          Text(
            'No appointments today',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'Pull to refresh for latest updates.',
            style: TextStyle(color: AppColors.lightTextMuted),
          ),
        ],
      ),
    );
  }

  BoxDecoration _skeletonBox() {
    return BoxDecoration(
      color: const Color(0xFFE8EFEF),
      borderRadius: BorderRadius.circular(14),
    );
  }

  static List<Map<String, dynamic>> _asMapList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static List<String> _asStringList(dynamic v) {
    if (v is! List) return const [];
    return v.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.totals});

  final Map<String, dynamic> totals;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _KpiChip(label: 'Total', value: (totals['appointments'] as num?)?.toInt() ?? 0, color: AppColors.primary),
        _KpiChip(label: 'Critical', value: (totals['critical'] as num?)?.toInt() ?? 0, color: AppColors.lightError),
        _KpiChip(label: 'High', value: (totals['high'] as num?)?.toInt() ?? 0, color: AppColors.lightWarning),
        _KpiChip(label: 'Medium', value: (totals['medium'] as num?)?.toInt() ?? 0, color: AppColors.lightInfo),
        _KpiChip(label: 'Low', value: (totals['low'] as num?)?.toInt() ?? 0, color: AppColors.lightTextMuted),
      ],
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text('$label: $value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _RankedAppointmentCard extends StatelessWidget {
  const _RankedAppointmentCard({
    required this.name,
    required this.score,
    required this.level,
    required this.reasons,
  });

  final String name;
  final int score;
  final String level;
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final chipColor = _priorityColor(level);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${level.toUpperCase()} · $score',
                  style: TextStyle(fontWeight: FontWeight.w700, color: chipColor, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...reasons.map(
            (reason) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: AppColors.lightTextMuted)),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13.2, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _priorityColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
        return AppColors.lightError;
      case 'high':
        return AppColors.lightWarning;
      case 'medium':
        return AppColors.lightInfo;
      default:
        return AppColors.lightTextMuted;
    }
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightWarningSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFDDA0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.lightWarning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.lightError, fontWeight: FontWeight.w600),
      ),
    );
  }
}
