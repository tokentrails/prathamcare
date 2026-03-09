import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../core/widgets/app_select_field.dart';
import '../../../../data/network/api_client.dart';
import '../widgets/encounter_ai_details_card.dart';

class EncounterDetailScreen extends StatefulWidget {
  const EncounterDetailScreen({
    super.key,
    required this.encounterId,
  });

  final String encounterId;

  @override
  State<EncounterDetailScreen> createState() => _EncounterDetailScreenState();
}

class _EncounterDetailScreenState extends State<EncounterDetailScreen> {
  static const List<AppSelectOption<String>> _summaryLanguageOptions = [
    AppSelectOption<String>(label: 'English (Original)', value: 'en'),
    AppSelectOption<String>(label: 'Kannada', value: 'kn'),
    AppSelectOption<String>(label: 'Hindi', value: 'hi'),
    AppSelectOption<String>(label: 'Tamil', value: 'ta'),
    AppSelectOption<String>(label: 'Telugu', value: 'te'),
    AppSelectOption<String>(label: 'Malayalam', value: 'ml'),
    AppSelectOption<String>(label: 'Gujarati', value: 'gu'),
  ];

  final ApiClient _apiClient = ApiClient();

  bool _loading = true;
  bool _summaryTranslating = false;
  String? _error;
  String? _summaryTranslateError;
  String _selectedSummaryLanguage = 'en';
  String _appliedSummaryLanguage = 'en';
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _dataOriginal;
  final Map<String, String> _summaryTranslateCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _summaryTranslateError = null;
    });
    try {
      final details = await _apiClient.getEncounterByID(encounterId: widget.encounterId);
      if (!mounted) return;
      final original = _cloneResponse(details);
      setState(() {
        _dataOriginal = original;
        _data = _cloneResponse(original);
        _selectedSummaryLanguage = 'en';
        _appliedSummaryLanguage = 'en';
        _summaryTranslateCache.clear();
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

  Map<String, dynamic> _cloneResponse(Map<String, dynamic> value) {
    return (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  }

  bool _hasTranslatableAiDetails() {
    final source = _dataOriginal ?? _data;
    if (source == null) {
      return false;
    }
    final extracted = (source['extracted_entities'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final summary = '${extracted['clinical_summary'] ?? ''}'.trim();
    final symptoms = (extracted['symptoms'] as List?) ?? const [];
    final nextSteps = (extracted['asha_next_steps'] as List?) ?? const [];
    final followUps = (extracted['follow_up_recommendations'] as List?) ?? const [];
    final alerts = (source['clinical_alerts'] as List?) ?? const [];
    return summary.isNotEmpty || symptoms.isNotEmpty || nextSteps.isNotEmpty || followUps.isNotEmpty || alerts.isNotEmpty;
  }

  String _translationCacheKey(String targetLanguage, String text) {
    return '$targetLanguage::$text';
  }

  Future<String> _translateTextForView({required String text, required String targetLanguage}) async {
    final normalized = text.trim();
    if (normalized.isEmpty || targetLanguage == 'en') {
      return normalized;
    }

    final cacheKey = _translationCacheKey(targetLanguage, normalized);
    final cached = _summaryTranslateCache[cacheKey];
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    final translated = await _apiClient.translateClinicalSummary(
      text: normalized,
      sourceLanguage: 'en',
      targetLanguage: targetLanguage,
    );
    final translatedText = '${translated['translated_text'] ?? ''}'.trim();
    if (translatedText.isEmpty) {
      throw const FormatException('Empty translation returned by backend.');
    }

    _summaryTranslateCache[cacheKey] = translatedText;
    return translatedText;
  }

  Future<List<dynamic>> _translateStringListForView({
    required List<dynamic> values,
    required String targetLanguage,
  }) async {
    final futures = values.map((item) async {
      final text = '$item'.trim();
      return _translateTextForView(text: text, targetLanguage: targetLanguage);
    }).toList();
    return await Future.wait(futures);
  }

  Future<Map<String, dynamic>> _buildTranslatedAiViewPayload({
    required Map<String, dynamic> source,
    required String targetLanguage,
  }) async {
    final next = _cloneResponse(source);
    final extracted = (next['extracted_entities'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    if (extracted.containsKey('clinical_summary')) {
      extracted['clinical_summary'] = await _translateTextForView(
        text: '${extracted['clinical_summary'] ?? ''}',
        targetLanguage: targetLanguage,
      );
    }

    for (final key in const ['chief_complaint', 'visit_type', 'body_site']) {
      if (extracted.containsKey(key)) {
        extracted[key] = await _translateTextForView(
          text: '${extracted[key] ?? ''}',
          targetLanguage: targetLanguage,
        );
      }
    }

    for (final key in const [
      'symptoms',
      'asha_next_steps',
      'follow_up_recommendations',
      'red_flags',
      'medications_mentioned',
      'suspected_conditions',
      'risk_factors',
    ]) {
      final values = (extracted[key] as List?)?.toList() ?? const [];
      extracted[key] = await _translateStringListForView(values: values, targetLanguage: targetLanguage);
    }

    final symptomDetailsRaw = (extracted['symptom_details'] as List?)?.toList() ?? const [];
    final symptomDetailsOut = <Map<String, dynamic>>[];
    for (final item in symptomDetailsRaw) {
      final map = (item as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      symptomDetailsOut.add({
        ...map,
        if (map.containsKey('symptom'))
          'symptom': await _translateTextForView(text: '${map['symptom'] ?? ''}', targetLanguage: targetLanguage),
        if (map.containsKey('description'))
          'description': await _translateTextForView(text: '${map['description'] ?? ''}', targetLanguage: targetLanguage),
      });
    }
    extracted['symptom_details'] = symptomDetailsOut;

    next['extracted_entities'] = extracted;

    if (next.containsKey('translation')) {
      next['translation'] = await _translateTextForView(
        text: '${next['translation'] ?? ''}',
        targetLanguage: targetLanguage,
      );
    }

    final alertsRaw = (next['clinical_alerts'] as List?)?.toList() ?? const [];
    final alertsOut = <Map<String, dynamic>>[];
    for (final item in alertsRaw) {
      final map = (item as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      alertsOut.add({
        ...map,
        if (map.containsKey('message'))
          'message': await _translateTextForView(text: '${map['message'] ?? ''}', targetLanguage: targetLanguage),
        if (map.containsKey('recommended_action'))
          'recommended_action': await _translateTextForView(
            text: '${map['recommended_action'] ?? ''}',
            targetLanguage: targetLanguage,
          ),
      });
    }
    next['clinical_alerts'] = alertsOut;

    return next;
  }

  Future<void> _translateAiDetailsForView() async {
    final source = _dataOriginal ?? _data;
    if (source == null || !_hasTranslatableAiDetails()) {
      setState(() {
        _summaryTranslateError = 'AI details are unavailable for translation.';
      });
      return;
    }

    final targetLanguage = _selectedSummaryLanguage;
    if (targetLanguage == 'en') {
      setState(() {
        _data = _cloneResponse(source);
        _appliedSummaryLanguage = 'en';
        _summaryTranslateError = null;
      });
      return;
    }

    setState(() {
      _summaryTranslating = true;
      _summaryTranslateError = null;
    });

    try {
      final translatedPayload = await _buildTranslatedAiViewPayload(
        source: source,
        targetLanguage: targetLanguage,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _data = translatedPayload;
        _appliedSummaryLanguage = targetLanguage;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _summaryTranslateError = '${e.code}: ${e.message}';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _summaryTranslateError = 'Unable to translate AI details right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _summaryTranslating = false;
        });
      }
    }
  }

  String _summaryLanguageLabel(String code) {
    for (final option in _summaryLanguageOptions) {
      if (option.value == code) {
        return option.label;
      }
    }
    return 'English (Original)';
  }

  Widget _buildSummaryTranslationCard() {
    final hasSummary = _hasTranslatableAiDetails();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x140F756D), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Translation',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.lightTextPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            hasSummary
                ? 'Translate all AI details for view only. Stored encounter data remains unchanged.'
                : 'AI details are unavailable for translation.',
            style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppSelectField<String>(
                  label: 'Language',
                  value: _selectedSummaryLanguage,
                  options: _summaryLanguageOptions,
                  enabled: !_summaryTranslating && hasSummary,
                  onChanged: (value) {
                    setState(() {
                      _selectedSummaryLanguage = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                height: 50,
                child: AppPillButton(
                  onPressed: (_summaryTranslating || !hasSummary) ? null : _translateAiDetailsForView,
                  icon: Icons.translate_rounded,
                  label: _summaryTranslating ? 'Translating...' : 'Translate',
                  variant: AppPillButtonVariant.light,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Showing: ${_summaryLanguageLabel(_appliedSummaryLanguage)}',
            style: const TextStyle(
              color: AppColors.lightTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_summaryTranslateError != null) ...[
            const SizedBox(height: 6),
            Text(
              _summaryTranslateError!,
              style: const TextStyle(color: AppColors.lightError, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text(
          'Encounter Details',
          style: TextStyle(
            color: AppColors.lightTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Text(_error!, style: const TextStyle(color: AppColors.lightError)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    final data = _data;
    if (data == null || data.isEmpty) {
      return const Center(
        child: Text(
          'No encounter details available.',
          style: TextStyle(color: AppColors.lightTextMuted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryTranslationCard(),
        const SizedBox(height: 12),
        EncounterAiDetailsCard(data: data),
      ],
    );
  }
}
