import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../data/network/api_client.dart';

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
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _error = '${e.code}: ${e.message}');
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      final processed = (out['processed'] as num?)?.toInt() ?? 0;
      final failed = (out['failed'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Replay complete: $processed processed, $failed failed')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = '${e.code}: ${e.message}');
    } catch (e) {
      if (!mounted) return;
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
      backgroundColor: const Color(0xFFF7FBFA),
      appBar: AppBar(
        title: const Text('Jobs'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0B1220),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_error != null) _ErrorCard(message: _error!),
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: AppPillButton(
                        onPressed: _replaying ? null : _replayFHIRSync,
                        icon: Icons.sync_rounded,
                        label: _replaying ? 'Replaying...' : 'Retry FHIR Sync',
                        variant: AppPillButtonVariant.primary,
                      ),
                    ),
                  ),
                  _buildViewSwitcher(),
                  const SizedBox(height: 10),
                  if (_warnings.isNotEmpty) _WarningCard(lines: _warnings),
                  _buildCurrentView(),
                ],
              ),
            ),
    );
  }

  Widget _buildViewSwitcher() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ViewChip(
          label: 'Jobs',
          selected: _view == ASHAJobsView.overview,
          onTap: () => setState(() => _view = ASHAJobsView.overview),
        ),
        _ViewChip(
          label: 'Queued',
          selected: _view == ASHAJobsView.queued,
          onTap: () => setState(() => _view = ASHAJobsView.queued),
        ),
        _ViewChip(
          label: 'Encounters',
          selected: _view == ASHAJobsView.encounters,
          onTap: () => setState(() => _view = ASHAJobsView.encounters),
        ),
        _ViewChip(
          label: 'Transcriptions',
          selected: _view == ASHAJobsView.transcriptions,
          onTap: () => setState(() => _view = ASHAJobsView.transcriptions),
        ),
      ],
    );
  }

  Widget _buildCurrentView() {
    switch (_view) {
      case ASHAJobsView.overview:
        return _SectionCard(
          title: 'Jobs',
          subtitle: 'Open a category',
          child: Column(
            children: [
              _OverviewTile(
                title: 'Queued Encounters',
                subtitle: '${_queued.length} pending items',
                onTap: () => setState(() => _view = ASHAJobsView.queued),
              ),
              _OverviewTile(
                title: 'Encounters',
                subtitle: '${_encounters.length} completed records',
                onTap: () => setState(() => _view = ASHAJobsView.encounters),
              ),
              _OverviewTile(
                title: 'Transcriptions',
                subtitle: '${_voiceItems.length} transcription jobs',
                onTap: () => setState(() => _view = ASHAJobsView.transcriptions),
              ),
            ],
          ),
        );
      case ASHAJobsView.queued:
        return _SectionCard(
          title: 'Queued Encounters',
          subtitle: '${_queued.length} pending',
          child: _queued.isEmpty
              ? const _EmptyState(text: 'No queued encounters')
              : Column(
                  children: _queued
                      .map(
                        (q) => _ListTileCard(
                          title: 'Queue ${q['queue_id'] ?? '-'}',
                          subtitle:
                              'Type: ${q['resource_type'] ?? '-'} • Patient: ${q['patient_id'] ?? '-'} • ${q['status'] ?? '-'}',
                          trailing: _formatDate(q['created_at']),
                        ),
                      )
                      .toList(),
                ),
        );
      case ASHAJobsView.encounters:
        return _SectionCard(
          title: 'Encounter History',
          subtitle: '${_encounters.length} records',
          child: _encounters.isEmpty
              ? const _EmptyState(text: 'No encounter records yet')
              : Column(
                  children: _encounters
                      .map(
                        (e) => _ListTileCard(
                          title: '${e['visit_type'] ?? 'visit'}',
                          subtitle:
                              'Patient: ${e['patient_id'] ?? '-'} • Sync: ${e['sync_status'] ?? '-'}',
                          trailing: _formatDate(e['created_at']),
                        ),
                      )
                      .toList(),
                ),
        );
      case ASHAJobsView.transcriptions:
        return _SectionCard(
          title: 'Transcription History',
          subtitle: '${_voiceItems.length} jobs',
          child: _voiceItems.isEmpty
              ? const _EmptyState(text: 'No transcription jobs persisted yet')
              : Column(
                  children: _voiceItems
                      .map(
                        (v) => _ListTileCard(
                          title: 'Job ${v['transcription_job'] ?? '-'}',
                          subtitle:
                              'Status: ${v['processing_status'] ?? '-'} • Patient: ${v['patient_id'] ?? '-'}',
                          trailing: _formatDate(v['created_at']),
                        ),
                      )
                      .toList(),
                ),
        );
    }
  }

  static List<Map<String, dynamic>> _asMapList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static List<String> _asStringList(dynamic v) {
    if (v is! List) return const [];
    return v.map((e) => '$e').toList();
  }

  static String _formatDate(dynamic v) {
    final raw = '$v';
    if (raw.isEmpty || raw == 'null') return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF334155),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}

class _ListTileCard extends StatelessWidget {
  const _ListTileCard({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(trailing, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF64748B))),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.lightError)),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('• $line', style: const TextStyle(color: Color(0xFF92400E))),
                ))
            .toList(),
      ),
    );
  }
}
