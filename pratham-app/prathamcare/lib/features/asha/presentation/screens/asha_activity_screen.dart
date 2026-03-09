import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../data/network/api_client.dart';
import 'encounter_detail_screen.dart';

enum ASHAJobsView {
  overview,
  queued,
  encounters,
  transcriptions,
}

class ASHAActivityScreen extends StatefulWidget {
  const ASHAActivityScreen({super.key, this.initialView = ASHAJobsView.overview});

  final ASHAJobsView initialView;

  @override
  State<ASHAActivityScreen> createState() => _ASHAActivityScreenState();
}

class _ASHAActivityScreenState extends State<ASHAActivityScreen> {
  final ApiClient _apiClient = ApiClient();

  bool _loading = true;
  bool _replaying = false;
  String? _error;
  List<Map<String, dynamic>> _voiceItems = const [];
  List<Map<String, dynamic>> _encounters = const [];
  List<Map<String, dynamic>> _queued = const [];
  List<String> _warnings = const [];
  late ASHAJobsView _view;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _warnings = const [];
    });
    try {
      final voice = await _apiClient.getVoiceHistory(limit: 30);
      final encounter = await _apiClient.getEncounterHistory(limit: 30);
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceItems = _asMapList(voice['items']);
        _encounters = _asMapList(encounter['encounters']);
        _queued = _asMapList(encounter['queued']);
        _warnings = [
          ..._asStringList(voice['warnings']),
          ..._asStringList(encounter['warnings']),
        ];
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '${e.code}: ${e.message}');
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _replayFHIRSync() async {
    setState(() {
      _replaying = true;
      _error = null;
    });
    try {
      final out = await _apiClient.replaySync(maxItems: 10);
      if (!mounted) {
        return;
      }
      final processed = (out['processed'] as num?)?.toInt() ?? 0;
      final failed = (out['failed'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Replay complete: $processed processed, $failed failed')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '${e.code}: ${e.message}');
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _replaying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Jobs'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 880;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSummaryHeader(compact),
                              const SizedBox(height: 12),
                              if (_error != null) ...[
                                _MessageStrip(
                                  message: _error!,
                                  background: const Color(0xFFFEF2F2),
                                  border: const Color(0xFFFCA5A5),
                                  text: AppColors.lightError,
                                  icon: Icons.error_outline_rounded,
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (_warnings.isNotEmpty) ...[
                                _MessageStrip(
                                  message: _warnings.join('\n'),
                                  background: const Color(0xFFFFFBEB),
                                  border: const Color(0xFFFDE68A),
                                  text: const Color(0xFF92400E),
                                  icon: Icons.warning_amber_rounded,
                                ),
                                const SizedBox(height: 10),
                              ],
                              _buildViewSwitcher(),
                              const SizedBox(height: 10),
                              _buildCurrentView(compact),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildSummaryHeader(bool compact) {
    final cards = [
      _MetricCard(
        title: 'Queued',
        value: _queued.length,
        icon: Icons.pending_actions_rounded,
        accent: AppColors.lightWarning,
        onTap: () => setState(() => _view = ASHAJobsView.queued),
      ),
      _MetricCard(
        title: 'Encounters',
        value: _encounters.length,
        icon: Icons.assignment_turned_in_outlined,
        accent: AppColors.primary,
        onTap: () => setState(() => _view = ASHAJobsView.encounters),
      ),
      _MetricCard(
        title: 'Transcriptions',
        value: _voiceItems.length,
        icon: Icons.graphic_eq_rounded,
        accent: AppColors.lightInfo,
        onTap: () => setState(() => _view = ASHAJobsView.transcriptions),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF129186)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x250F766E),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.work_outline_rounded, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Jobs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Track queued sync work, completed encounters, and transcription jobs in one clean view.',
            style: TextStyle(
              color: Color(0xFFE2FFFB),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 52,
                      child: AppPillButton(
                        onPressed: _replaying ? null : _replayFHIRSync,
                        icon: Icons.sync_rounded,
                        label: _replaying ? 'Replaying...' : 'Retry FHIR Sync',
                        variant: AppPillButtonVariant.light,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 52,
                      child: AppPillButton(
                        onPressed: _load,
                        icon: Icons.refresh_rounded,
                        label: 'Refresh Jobs',
                        variant: AppPillButtonVariant.dark,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: AppPillButton(
                          onPressed: _replaying ? null : _replayFHIRSync,
                          icon: Icons.sync_rounded,
                          label: _replaying ? 'Replaying...' : 'Retry FHIR Sync',
                          variant: AppPillButtonVariant.light,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: AppPillButton(
                          onPressed: _load,
                          icon: Icons.refresh_rounded,
                          label: 'Refresh Jobs',
                          variant: AppPillButtonVariant.dark,
                        ),
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards
                .map(
                  (card) => SizedBox(
                    width: compact ? double.infinity : 220,
                    child: card,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ViewChip(
          icon: Icons.grid_view_rounded,
          label: 'Overview',
          selected: _view == ASHAJobsView.overview,
          onTap: () => setState(() => _view = ASHAJobsView.overview),
        ),
        _ViewChip(
          icon: Icons.pending_actions_rounded,
          label: 'Queued',
          selected: _view == ASHAJobsView.queued,
          onTap: () => setState(() => _view = ASHAJobsView.queued),
        ),
        _ViewChip(
          icon: Icons.assignment_turned_in_outlined,
          label: 'Encounters',
          selected: _view == ASHAJobsView.encounters,
          onTap: () => setState(() => _view = ASHAJobsView.encounters),
        ),
        _ViewChip(
          icon: Icons.graphic_eq_rounded,
          label: 'Transcriptions',
          selected: _view == ASHAJobsView.transcriptions,
          onTap: () => setState(() => _view = ASHAJobsView.transcriptions),
        ),
      ],
    );
  }

  Widget _buildCurrentView(bool compact) {
    switch (_view) {
      case ASHAJobsView.overview:
        return _OverviewPanel(
          queuedCount: _queued.length,
          encounterCount: _encounters.length,
          transcriptionCount: _voiceItems.length,
          compact: compact,
          onOpenQueued: () => setState(() => _view = ASHAJobsView.queued),
          onOpenEncounters: () => setState(() => _view = ASHAJobsView.encounters),
          onOpenTranscriptions: () => setState(() => _view = ASHAJobsView.transcriptions),
        );
      case ASHAJobsView.queued:
        return _ListPanel(
          title: 'Queued Encounters',
          subtitle: '${_queued.length} pending',
          empty: 'No queued encounters',
          children: _queued
              .map(
                (q) => _SimpleListRow(
                  title: 'Queue ${q['queue_id'] ?? '-'}',
                  subtitle:
                      'Type: ${q['resource_type'] ?? '-'} - Patient: ${q['patient_id'] ?? '-'} - ${q['status'] ?? '-'}',
                  trailing: _formatDate(q['created_at']),
                ),
              )
              .toList(),
        );
      case ASHAJobsView.encounters:
        return _ListPanel(
          title: 'Encounter History',
          subtitle: '${_encounters.length} records',
          empty: 'No encounter records yet',
          children: _encounters
              .map(
                (e) => _EncounterHistoryRow(
                  patientId: '${e['patient_id'] ?? ''}',
                  visitType: '${e['visit_type'] ?? ''}',
                  syncStatus: '${e['sync_status'] ?? ''}',
                  status: '${e['status'] ?? ''}',
                  occurredAt: '${e['occurred_at'] ?? ''}',
                  createdAt: '${e['created_at'] ?? ''}',
                  onTap: () {
                    final encounterId = '${e['encounter_id'] ?? ''}'.trim();
                    if (encounterId.isEmpty) {
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EncounterDetailScreen(encounterId: encounterId),
                      ),
                    );
                  },
                ),
              )
              .toList(),
        );
      case ASHAJobsView.transcriptions:
        return _ListPanel(
          title: 'Transcription History',
          subtitle: '${_voiceItems.length} jobs',
          empty: 'No transcription jobs persisted yet',
          children: _voiceItems
              .map(
                (v) => _SimpleListRow(
                  title: 'Job ${v['transcription_job'] ?? '-'}',
                  subtitle:
                      'Status: ${v['processing_status'] ?? '-'} - Patient: ${v['patient_id'] ?? '-'}',
                  trailing: _formatDate(v['created_at']),
                ),
              )
              .toList(),
        );
    }
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static List<String> _asStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
  }

  static String _formatDate(dynamic value) {
    final raw = '$value';
    if (raw.isEmpty || raw == 'null') {
      return '';
    }
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }
}

class _MessageStrip extends StatelessWidget {
  const _MessageStrip({
    required this.message,
    required this.background,
    required this.border,
    required this.text,
    required this.icon,
  });

  final String message;
  final Color background;
  final Color border;
  final Color text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: text),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: text, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final int value;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: accent.withOpacity(0.14),
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
                  ),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.lightPlaceholder),
          ],
        ),
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : AppColors.lightTextMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.lightTextSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({
    required this.queuedCount,
    required this.encounterCount,
    required this.transcriptionCount,
    required this.compact,
    required this.onOpenQueued,
    required this.onOpenEncounters,
    required this.onOpenTranscriptions,
  });

  final int queuedCount;
  final int encounterCount;
  final int transcriptionCount;
  final bool compact;
  final VoidCallback onOpenQueued;
  final VoidCallback onOpenEncounters;
  final VoidCallback onOpenTranscriptions;

  @override
  Widget build(BuildContext context) {
    final items = [
      _OverviewItem(
        title: 'Queued Encounters',
        subtitle: '$queuedCount pending items',
        icon: Icons.pending_actions_rounded,
        accent: AppColors.lightWarning,
        onTap: onOpenQueued,
      ),
      _OverviewItem(
        title: 'Encounters',
        subtitle: '$encounterCount completed records',
        icon: Icons.assignment_turned_in_outlined,
        accent: AppColors.primary,
        onTap: onOpenEncounters,
      ),
      _OverviewItem(
        title: 'Transcriptions',
        subtitle: '$transcriptionCount transcription jobs',
        icon: Icons.graphic_eq_rounded,
        accent: AppColors.lightInfo,
        onTap: onOpenTranscriptions,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items
            .map(
              (item) => SizedBox(
                width: compact ? double.infinity : 330,
                child: item,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _OverviewItem extends StatelessWidget {
  const _OverviewItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withOpacity(0.14),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.lightTextMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.lightPlaceholder),
          ],
        ),
      ),
    );
  }
}

class _ListPanel extends StatelessWidget {
  const _ListPanel({
    required this.title,
    required this.subtitle,
    required this.empty,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12.5, color: AppColors.lightTextMuted),
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            _EmptyState(text: empty)
          else
            ...children,
        ],
      ),
    );
  }
}

class _SimpleListRow extends StatelessWidget {
  const _SimpleListRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (trailing.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                trailing,
                style: const TextStyle(color: AppColors.lightPlaceholder, fontSize: 11),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: AppColors.lightPlaceholder, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _EncounterHistoryRow extends StatelessWidget {
  const _EncounterHistoryRow({
    required this.patientId,
    required this.visitType,
    required this.syncStatus,
    required this.status,
    required this.occurredAt,
    required this.createdAt,
    required this.onTap,
  });

  final String patientId;
  final String visitType;
  final String syncStatus;
  final String status;
  final String occurredAt;
  final String createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final normalizedSync = syncStatus.trim().toLowerCase();
    final normalizedStatus = status.trim().toLowerCase();
    final happenedAt = _ASHAActivityScreenState._formatDate(
      occurredAt.trim().isEmpty ? createdAt : occurredAt,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _patientLabel(patientId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_visitTypeLabel(visitType)} - $happenedAt',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.lightTextMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _chip(_syncLabel(normalizedSync), _syncChipColor(normalizedSync)),
            if (normalizedStatus.isNotEmpty) ...[
              const SizedBox(width: 6),
              _chip(_statusLabel(normalizedStatus), const Color(0xFFE2E8F0)),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.lightPlaceholder, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  static String _patientLabel(String patientId) {
    final cleaned = patientId.trim();
    if (cleaned.isEmpty) {
      return 'Patient -';
    }
    if (cleaned.length <= 12) {
      return 'Patient $cleaned';
    }
    return 'Patient ${cleaned.substring(0, 8)}';
  }

  static String _visitTypeLabel(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) {
      return 'Visit';
    }
    final withSpaces = cleaned.replaceAll('_', ' ');
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }

  static String _syncLabel(String sync) {
    switch (sync) {
      case 'synced':
        return 'Synced';
      case 'queued':
      case 'pending':
        return 'Queued';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  static Color _syncChipColor(String sync) {
    switch (sync) {
      case 'synced':
        return const Color(0xFFDCFCE7);
      case 'queued':
      case 'pending':
        return const Color(0xFFFEF3C7);
      case 'failed':
        return const Color(0xFFFEE2E2);
      default:
        return const Color(0xFFE2E8F0);
    }
  }

  static String _statusLabel(String status) {
    if (status.isEmpty) {
      return '';
    }
    return status[0].toUpperCase() + status.substring(1);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.lightTextMuted),
      ),
    );
  }
}
