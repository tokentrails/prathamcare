import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class EncounterAiDetailsCard extends StatelessWidget {
  const EncounterAiDetailsCard({
    super.key,
    required this.data,
    this.title = 'AI Extraction',
  });

  final Map<String, dynamic> data;
  final String title;

  @override
  Widget build(BuildContext context) {
    final extracted = (data['extracted_entities'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final vitals = (extracted['vitals'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final alerts = ((data['clinical_alerts'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final symptoms = ((extracted['symptoms'] as List?) ?? const []).map((e) => '$e').toList();
    final symptomDetails = ((extracted['symptom_details'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    final nextSteps = ((extracted['asha_next_steps'] as List?) ?? const []).map((e) => '$e').toList();
    final followUps = ((extracted['follow_up_recommendations'] as List?) ?? const []).map((e) => '$e').toList();
    final redFlags = ((extracted['red_flags'] as List?) ?? const []).map((e) => '$e').toList();
    final meds = ((extracted['medications_mentioned'] as List?) ?? const []).map((e) => '$e').toList();
    final pregnancyRaw = (extracted['pregnancy_context'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final immunizationRaw =
        (extracted['immunization_context'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final pregnancy = _meaningfulMap(pregnancyRaw);
    final immunization = _meaningfulMap(immunizationRaw);
    final summary = '${extracted['clinical_summary'] ?? ''}'.trim();
    final referralUrgency = '${extracted['referral_urgency'] ?? 'routine'}'.trim();
    final translation = '${data['translation'] ?? ''}'.trim();
    final transcription = '${data['transcription'] ?? ''}'.trim();
    final detectedLanguage = '${data['detected_language'] ?? ''}'.trim();
    final detectedLanguageScoreRaw = data['detected_language_score'];
    final detectedLanguageScore = detectedLanguageScoreRaw is num ? detectedLanguageScoreRaw.toDouble() : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F756D),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeroHeader(extracted, referralUrgency),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (alerts.isNotEmpty) ...[
                  ...alerts.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildAlertBanner(a),
                  )),
                  const SizedBox(height: 8),
                ],
                if (summary.isNotEmpty) ...[
                  _buildSectionHeader('Clinical Summary', Icons.summarize_rounded, AppColors.primary),
                  const SizedBox(height: 12),
                  _bodyText(summary),
                  const _Divider(),
                ],
                if (transcription.isNotEmpty || translation.isNotEmpty) ...[
                  _buildSectionHeader('Conversation', Icons.forum_rounded, AppColors.accent),
                  const SizedBox(height: 12),
                  if (detectedLanguage.isNotEmpty) ...[
                    _textBlockWithLabel(
                      'Detected Language',
                      detectedLanguageScore == null
                          ? detectedLanguage
                          : '$detectedLanguage (${(detectedLanguageScore * 100).toStringAsFixed(1)}%)',
                    ),
                    const SizedBox(height: 16),
                  ],
                  _textBlockWithLabel('Transcription', transcription),
                  const SizedBox(height: 16),
                  _textBlockWithLabel('Translation (English)', translation),
                  const _Divider(),
                ],
                if (vitals.isNotEmpty) ...[
                  _buildSectionHeader('Vitals', Icons.monitor_heart_rounded, AppColors.lightError),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: vitals.entries.map((e) => _vitalItem(e.key, '${e.value}')).toList(),
                  ),
                  const _Divider(),
                ],
                if (symptoms.isNotEmpty || symptomDetails.isNotEmpty) ...[
                  _buildSectionHeader('Symptoms', Icons.sick_rounded, AppColors.lightWarning),
                  const SizedBox(height: 16),
                  if (symptoms.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: symptoms.map(_chip).toList(),
                    ),
                  if (symptoms.isNotEmpty && symptomDetails.isNotEmpty) const SizedBox(height: 16),
                  if (symptomDetails.isNotEmpty)
                    ...symptomDetails.map((item) => _detailRow('${item['symptom'] ?? '-'}', '${item['description'] ?? '-'}')),
                  const _Divider(),
                ],
                if (redFlags.isNotEmpty) ...[
                  _buildSectionHeader('Red Flags', Icons.warning_rounded, AppColors.lightError),
                  const SizedBox(height: 16),
                  ...redFlags.map((flag) => _bullet(flag, iconColor: AppColors.lightError)),
                  const _Divider(),
                ],
                if (nextSteps.isNotEmpty) ...[
                  _buildSectionHeader('ASHA Next Steps', Icons.directions_walk_rounded, AppColors.primary),
                  const SizedBox(height: 16),
                  ...nextSteps.map((step) => _bullet(step)),
                  const _Divider(),
                ],
                if (followUps.isNotEmpty) ...[
                  _buildSectionHeader('Follow-up Recommendations', Icons.replay_circle_filled_rounded, AppColors.accent),
                  const SizedBox(height: 16),
                  ...followUps.map((item) => _bullet(item, iconColor: AppColors.accent)),
                  const _Divider(),
                ],
                if (meds.isNotEmpty) ...[
                  _buildSectionHeader('Medications Mentioned', Icons.medication_rounded, AppColors.primary),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: meds.map((m) => _chip(m, color: AppColors.primary)).toList(),
                  ),
                  const _Divider(),
                ],
                if (pregnancy.isNotEmpty) ...[
                  _buildSectionHeader('Pregnancy Context', Icons.pregnant_woman_rounded, AppColors.lightTextMuted),
                  const SizedBox(height: 16),
                  ...pregnancy.entries.map((e) => _summaryRow(e.key, '${e.value}')),
                  const _Divider(),
                ],
                if (immunization.isNotEmpty) ...[
                  _buildSectionHeader('Immunization Context', Icons.vaccines_rounded, AppColors.lightTextMuted),
                  const SizedBox(height: 16),
                  ...immunization.entries.map((e) => _summaryRow(e.key, '${e.value}')),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(Map<String, dynamic> extracted, String referralUrgency) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${extracted['patient_name'] ?? data['patient_id'] ?? '-'}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Patient Encounter',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _heroMetricItem(
                  'Visit Type',
                  '${extracted['visit_type'] ?? data['visit_type'] ?? '-'}',
                  Icons.event_note_outlined,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.white.withValues(alpha: 0.2),
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(
                child: _heroMetricItem(
                  'Referral',
                  referralUrgency.isEmpty ? '-' : _titleCase(referralUrgency),
                  Icons.local_hospital_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMetricItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color iconColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.lightTextPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildAlertBanner(Map<String, dynamic> a) {
    final severity = '${a['severity'] ?? 'unknown'}'.trim().toLowerCase();
    return Container(
      decoration: BoxDecoration(
        color: _severitySurfaceColor(severity),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: _severityChipTextColor(severity),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Clinical Alert',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _severityChipTextColor(severity),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _severityBadge(severity),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${a['message'] ?? ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.lightTextSecondary.withValues(alpha: 0.9),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                if ('${a['recommended_action'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.subdirectory_arrow_right_rounded, size: 18, color: _severityChipTextColor(severity).withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recommended Action',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _severityChipTextColor(severity).withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${a['recommended_action']}',
                              style: const TextStyle(
                                color: AppColors.lightTextPrimary,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textBlockWithLabel(String title, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.lightTextMuted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text.isEmpty ? 'No data' : text,
          style: const TextStyle(
            color: AppColors.lightTextSecondary,
            fontSize: 15,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 12),
            child: Icon(Icons.arrow_right_alt_rounded, size: 20, color: AppColors.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.lightTextPrimary,
                    fontSize: 15,
                  ),
                ),
                if (desc.isNotEmpty && desc != '-') ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      color: AppColors.lightTextSecondary,
                      height: 1.5,
                      fontSize: 15,
                    ),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              _titleCase(label.replaceAll('_', ' ')),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.lightTextPrimary,
                fontSize: 15,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                color: AppColors.lightTextSecondary,
                height: 1.5,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vitalItem(String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.lightInputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.lightTextPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _titleCase(key.replaceAll('_', ' ')),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color color = AppColors.lightTextPrimary}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.lightInputBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _severityBadge(String severity) {
    final label = severity.trim().isEmpty ? 'unknown' : severity.trim().toLowerCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _severityChipBackground(label),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _titleCase(label),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _severityChipTextColor(label),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _severityChipBackground(String severity) {
    switch (severity) {
      case 'low':
        return AppColors.lightSuccessSoft;
      case 'moderate':
        return AppColors.lightWarningSoft;
      case 'high':
      case 'critical':
        return AppColors.lightError.withValues(alpha: 0.15);
      default:
        return const Color(0xFFE2E8F0);
    }
  }

  Color _severityChipTextColor(String severity) {
    switch (severity) {
      case 'low':
        return AppColors.lightSuccess;
      case 'moderate':
        return const Color(0xFFB45309);
      case 'high':
      case 'critical':
        return AppColors.lightError;
      default:
        return AppColors.lightTextMuted;
    }
  }

  Color _severitySurfaceColor(String severity) {
    switch (severity.trim().toLowerCase()) {
      case 'low':
        return AppColors.lightSuccessSoft.withValues(alpha: 0.5);
      case 'moderate':
        return AppColors.lightWarningSoft;
      case 'high':
      case 'critical':
        return AppColors.lightErrorSoft;
      default:
        return const Color(0xFFF8FAFC);
    }
  }

  String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input.split(' ').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  Widget _bullet(String text, {Color iconColor = AppColors.primary}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12),
            child: Icon(Icons.check_circle_rounded, size: 20, color: iconColor),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.lightTextPrimary,
                height: 1.5,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(
      text.isEmpty ? 'No data' : text,
      style: const TextStyle(
        color: AppColors.lightTextSecondary,
        height: 1.6,
        fontSize: 15,
      ),
    );
  }

  Map<String, dynamic> _meaningfulMap(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (_isMeaningful(value)) {
        out[key] = value;
      }
    });
    return out;
  }

  bool _isMeaningful(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty && value.trim().toLowerCase() != 'null';
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Divider(color: AppColors.lightBorder, height: 1, thickness: 1),
    );
  }
}
