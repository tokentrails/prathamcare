import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../core/widgets/app_select_field.dart';
import '../../../../data/network/api_client.dart';
import '../../../shared/prefill/demo_prefill_data.dart';
import '../../../shared/widgets/demo_prefill_button.dart';
import '../widgets/encounter_ai_details_card.dart';
import '../widgets/patient_form_section.dart';
import '../widgets/patient_result_tile.dart';
import '../widgets/patient_search_field.dart';
import '../widgets/patient_summary_card.dart';

class VoiceVisitScreen extends StatefulWidget {
  const VoiceVisitScreen({
    super.key,
    this.patientId,
    this.appointmentId,
    this.appointmentContext,
  });

  final String? patientId;
  final String? appointmentId;
  final Map<String, dynamic>? appointmentContext;

  @override
  State<VoiceVisitScreen> createState() => _VoiceVisitScreenState();
}

class _VoiceVisitScreenState extends State<VoiceVisitScreen> {
  static const List<AppSelectOption<String>> _languageOptions = [
    AppSelectOption<String>(
      label: 'Auto (English/Kannada)',
      value: '',
    ),
    AppSelectOption<String>(
      label: 'English (en-IN)',
      value: 'en-IN',
    ),
    AppSelectOption<String>(
      label: 'Kannada (kn-IN)',
      value: 'kn-IN',
    ),
  ];

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
  final AudioRecorder _audioRecorder = AudioRecorder();
  final TextEditingController _patientSearchController = TextEditingController();

  PlatformFile? _selectedAudio;
  Uint8List? _selectedAudioBytes;
  bool _loading = false;
  bool _submitting = false;
  bool _recording = false;
  bool _patientSearchLoading = false;
  bool _patientResolving = false;
  String? _objectKey;
  String? _voiceJobId;
  String? _transcriptionJobId;
  String? _recordingPath;
  String _recordingExtension = 'wav';
  Map<String, dynamic>? _transcribeResponse;
  Map<String, dynamic>? _transcribeResponseOriginal;
  Map<String, dynamic>? _selectedPatient;
  List<Map<String, dynamic>> _searchResults = const [];
  List<Map<String, dynamic>> _recentPatients = const [];
  String? _processingStatus;
  String? _detectedLanguage;
  String? _error;
  String? _patientError;
  String _selectedTranscriptionLanguage = '';
  String _selectedSummaryLanguage = 'en';
  String _appliedSummaryLanguage = 'en';
  bool _summaryTranslating = false;
  final Map<String, String> _summaryTranslateCache = <String, String>{};
  String? _summaryTranslateError;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadInitialPatients();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _patientSearchController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadInitialPatients() async {
    await _loadRecentPatients();
    final id = widget.patientId?.trim() ?? '';
    if (id.isNotEmpty) {
      await _selectPatientById(id);
    }
  }

  Future<void> _loadRecentPatients() async {
    try {
      final res = await _apiClient.getRecentPatients(limit: 10);
      final list = (res['results'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (!mounted) {
        return;
      }
      setState(() {
        _recentPatients = list;
      });
    } catch (_) {
      // Ignore recent failures; search remains available.
    }
  }

  Future<void> _selectPatientById(String patientId) async {
    if (patientId.trim().isEmpty) {
      return;
    }
    setState(() {
      _patientResolving = true;
      _patientError = null;
    });
    try {
      final patient = await _apiClient.getPatientById(patientId: patientId.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedPatient = patient;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _patientError = '${e.code}: ${e.message}';
      });
    } finally {
      if (mounted) {
        setState(() => _patientResolving = false);
      }
    }
  }

  void _onPatientSearchChanged(String value) {
    if (mounted) {
      setState(() {});
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runPatientSearch(value);
    });
  }

  Future<void> _runPatientSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = const [];
        _patientError = null;
      });
      return;
    }

    setState(() {
      _patientSearchLoading = true;
      _patientError = null;
    });

    try {
      final digitsOnly = query.replaceAll(RegExp(r'[^0-9]'), '');
      final phone = digitsOnly.length >= 10 && digitsOnly.length <= 12 ? digitsOnly : null;
      final abha = digitsOnly.length == 14 ? digitsOnly : null;
      final res = await _apiClient.searchPatients(
        q: query,
        phone: phone,
        abha: abha,
        limit: 10,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _searchResults = (res['results'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _patientError = '${e.code}: ${e.message}';
        _searchResults = const [];
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _patientError = 'Unable to search patients. Check connectivity and retry.';
        _searchResults = const [];
      });
    } finally {
      if (mounted) {
        setState(() => _patientSearchLoading = false);
      }
    }
  }

  Future<void> _openPatientForm({Map<String, dynamic>? existing}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AddOrEditPatientSheet(
        apiClient: _apiClient,
        existingPatient: existing,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _selectedPatient = result;
      _patientError = null;
      _patientSearchController.clear();
      _searchResults = const [];
    });
    await _loadRecentPatients();
  }

  Future<void> _pickAudioFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const ['wav', 'mp3', 'm4a'],
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _error = 'Selected audio file could not be read.';
      });
      return;
    }
    if (bytes.length > 10 * 1024 * 1024) {
      setState(() {
        _error = 'Audio file must be <= 10 MB.';
      });
      return;
    }

    setState(() {
      _selectedAudio = file;
      _selectedAudioBytes = bytes;
      _transcribeResponse = null;
      _transcribeResponseOriginal = null;
      _resetSummaryTranslationState();
      _voiceJobId = null;
      _transcriptionJobId = null;
      _processingStatus = null;
      _detectedLanguage = null;
      _error = null;
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      try {
        final path = await _audioRecorder.stop();
        final resolvedPath = (path == null || path.isEmpty) ? _recordingPath : path;
        _recordingPath = null;
        if (resolvedPath == null || resolvedPath.isEmpty) {
          setState(() {
            _error = 'Recording stop failed.';
            _recording = false;
          });
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final bytes = await XFile(resolvedPath).readAsBytes();
        if (bytes.isEmpty) {
          setState(() {
            _error = 'Recorded file is empty.';
            _recording = false;
          });
          return;
        }
        setState(() {
          _recording = false;
          _error = null;
          _transcribeResponse = null;
          _transcribeResponseOriginal = null;
          _resetSummaryTranslationState();
          _voiceJobId = null;
          _transcriptionJobId = null;
          _processingStatus = null;
          _detectedLanguage = null;
          _selectedAudio = PlatformFile(
            name: 'recorded_visit.$_recordingExtension',
            size: bytes.length,
            path: resolvedPath,
          );
          _selectedAudioBytes = bytes;
        });
      } catch (e) {
        setState(() {
          _recording = false;
          _error = 'Failed to finalize recording: $e';
        });
      }
      return;
    }

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        setState(() {
          _error = 'Microphone permission denied.';
        });
        return;
      }
      final useWebSafeEncoder = kIsWeb;
      final encoder = useWebSafeEncoder ? AudioEncoder.aacLc : AudioEncoder.wav;
      final extension = useWebSafeEncoder ? 'm4a' : 'wav';
      final recordingPath = await _buildRecordingPath(extension);
      await _audioRecorder.start(
        RecordConfig(
          encoder: encoder,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: recordingPath,
      );
      setState(() {
        _recording = true;
        _recordingPath = recordingPath;
        _recordingExtension = extension;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _recording = false;
        _error = 'Failed to start recording: $e';
      });
    }
  }

  Future<String> _buildRecordingPath(String extension) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb) {
      return 'recorded_visit_$stamp.$extension';
    }
    final dir = await getTemporaryDirectory();
    final base = dir.path.replaceAll('\\', '/');
    return '$base/recorded_visit_$stamp.$extension';
  }

  void _resetSummaryTranslationState() {
    _selectedSummaryLanguage = 'en';
    _appliedSummaryLanguage = 'en';
    _summaryTranslating = false;
    _summaryTranslateError = null;
    _summaryTranslateCache.clear();
  }

  Map<String, dynamic> _cloneResponse(Map<String, dynamic> value) {
    return (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  }
  bool _hasTranslatableAiDetails() {
    final source = _transcribeResponseOriginal ?? _transcribeResponse;
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
    final source = _transcribeResponseOriginal ?? _transcribeResponse;
    if (source == null || !_hasTranslatableAiDetails()) {
      setState(() {
        _summaryTranslateError = 'AI details are unavailable for translation.';
      });
      return;
    }

    final targetLanguage = _selectedSummaryLanguage;
    if (targetLanguage == 'en') {
      setState(() {
        _transcribeResponse = _cloneResponse(source);
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
        _transcribeResponse = translatedPayload;
        _appliedSummaryLanguage = targetLanguage;
        _summaryTranslateError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _summaryTranslateError = '${e.code}: ${e.message}';
      });
    } catch (e) {
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

  Future<void> _runAiExtract() async {
    final selectedPatientId = '${_selectedPatient?['patient_id'] ?? ''}'.trim();
    if (selectedPatientId.isEmpty) {
      setState(() {
        _error = 'Select a patient before processing encounter.';
      });
      return;
    }

    if (_selectedAudio == null || _selectedAudioBytes == null) {
      setState(() {
        _error = 'Please choose an audio file first.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _transcribeResponse = null;
      _transcribeResponseOriginal = null;
      _resetSummaryTranslationState();
      _voiceJobId = null;
      _transcriptionJobId = null;
      _processingStatus = 'uploading';
      _detectedLanguage = null;
    });

    try {
      final contentType = _contentTypeFromFileName(_selectedAudio!.name);
      final presign = await _apiClient.createVoicePresign(
        contentType: contentType,
        fileSizeBytes: _selectedAudioBytes!.lengthInBytes,
        context: 'asha_home_visit',
        patientId: selectedPatientId,
        language: _selectedTranscriptionLanguage,
      );

      final uploadUrl = '${presign['upload_url'] ?? ''}';
      _objectKey = '${presign['object_key'] ?? ''}';
      if (uploadUrl.isEmpty || _objectKey == null || _objectKey!.isEmpty) {
        throw const FormatException('Invalid presign response from backend.');
      }

      await _apiClient.uploadVoiceBytes(
        uploadUrl: uploadUrl,
        bytes: _selectedAudioBytes!,
        contentType: contentType,
      );

      final transcribed = await _apiClient.transcribeVoice(
        objectKey: _objectKey!,
        language: _selectedTranscriptionLanguage,
        context: 'asha_home_visit',
        patientId: selectedPatientId,
      );

      final voiceJobId = '${transcribed['voice_job_id'] ?? ''}';
      final transcriptionJobId = '${transcribed['transcription_job'] ?? ''}';
      if (voiceJobId.isEmpty && transcriptionJobId.isEmpty) {
        throw Exception('No job identifier returned by backend.');
      }
      setState(() {
        _voiceJobId = voiceJobId;
        _transcriptionJobId = transcriptionJobId;
        _processingStatus = '${transcribed['processing_status'] ?? 'transcribing'}';
      });
      await _pollTranscriptionResult();
    } on ApiException catch (e) {
      setState(() {
        _error = '${e.code}: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pollTranscriptionResult() async {
    final voiceJobId = _voiceJobId;
    final transcriptionJobId = _transcriptionJobId;
    if ((voiceJobId == null || voiceJobId.isEmpty) &&
        (transcriptionJobId == null || transcriptionJobId.isEmpty)) {
      return;
    }

    const maxAttempts = 40;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final statusRes = (voiceJobId != null && voiceJobId.isNotEmpty)
          ? await _apiClient.getVoiceTranscriptionStatus(voiceJobId: voiceJobId)
          : await _apiClient.getVoiceTranscriptionStatusByJob(
              transcriptionJobId: transcriptionJobId!,
            );
      final status = '${statusRes['processing_status'] ?? ''}'.toLowerCase();
      if (!mounted) {
        return;
      }

      setState(() {
        _processingStatus = status;
        _detectedLanguage = '${statusRes['detected_language'] ?? ''}'.trim().isEmpty
            ? _detectedLanguage
            : '${statusRes['detected_language'] ?? ''}'.trim();
      });

      if (status == 'completed') {
        final original = _cloneResponse(statusRes);
        setState(() {
          _transcribeResponseOriginal = original;
          _transcribeResponse = _cloneResponse(original);
          _resetSummaryTranslationState();
        });
        return;
      }
      if (status == 'failed') {
        setState(() {
          _error = '${statusRes['error'] ?? 'Transcription failed'}';
        });
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }

    if (mounted) {
      setState(() {
        _error = 'Transcription is taking longer than expected. Please retry in a moment.';
      });
    }
  }

  Future<void> _submitEncounter() async {
    final data = _transcribeResponseOriginal ?? _transcribeResponse;
    if (data == null) {
      return;
    }
    final patientId = '${_selectedPatient?['patient_id'] ?? ''}'.trim();
    if (patientId.isEmpty) {
      setState(() {
        _error = 'Select a patient before submitting encounter.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final extractedPayload = <String, dynamic>{
        ...(data['extracted_entities'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      };
      final medicalEntities = data['medical_entities'];

      final encounterRes = await _apiClient.submitEncounter(
        patientId: patientId,
        appointmentId: widget.appointmentId,
        visitType: '${(data['extracted_entities'] as Map<String, dynamic>?)?['visit_type'] ?? 'home_visit'}',
        occurredAt: DateTime.now().toUtc().toIso8601String(),
        transcription: '${data['transcription'] ?? ''}',
        translation: '${data['translation'] ?? ''}',
        sourceAudioKey: _objectKey,
        extractedEntities: extractedPayload,
        medicalEntities: medicalEntities,
        clinicalAlerts: (data['clinical_alerts'] as List?) ?? const [],
      );

      if (!mounted) {
        return;
      }
      final encounterId = '${encounterRes['encounter_id'] ?? ''}'.trim();
      if ((widget.appointmentId ?? '').trim().isNotEmpty && encounterId.isNotEmpty) {
        await _apiClient.completeAppointment(
          appointmentId: widget.appointmentId!.trim(),
          encounterId: encounterId,
        );
      }
      final syncStatus = '${encounterRes['sync_status'] ?? ''}'.toLowerCase();
      final queued = syncStatus == 'queued' || syncStatus == 'pending';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Encounter submitted and queued for sync.'
                : 'Encounter submitted and synced.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _error = '${e.code}: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _contentTypeFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp3')) {
      return 'audio/mpeg';
    }
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) {
      return 'audio/mp4';
    }
    return 'audio/wav';
  }

  @override
  Widget build(BuildContext context) {
    final patientSelected = _selectedPatient != null;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Create Encounter'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if ((widget.appointmentId ?? '').trim().isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5F3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFC6E4DE)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_note_rounded, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Appointment context: ${widget.appointmentContext?['reason_label'] ?? widget.appointmentContext?['reason_code'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildPatientSelectorCard(),
                const SizedBox(height: 12),
                _buildAudioPickerCard(),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: AppPillButton(
                    onPressed: (!patientSelected || _loading || _patientResolving || _transcribeResponse != null)
                        ? null
                        : _runAiExtract,
                    icon: Icons.auto_awesome_rounded,
                    label: _loading ? 'Processing...' : 'Process Encounter With AI',
                    variant: AppPillButtonVariant.primary,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.lightError),
                  ),
                ],
                if (_processingStatus != null && _transcribeResponse == null) ...[
                  const SizedBox(height: 10),
                  _buildTranscribeStatusCard(),
                ],
                const SizedBox(height: 16),
                if (_transcribeResponse != null) ...[
                  _buildSummaryTranslationCard(),
                  const SizedBox(height: 12),
                  _buildResultCard(_transcribeResponse!),
                ],
                if (_transcribeResponse != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: AppPillButton(
                      onPressed: (_submitting || !patientSelected) ? null : _submitEncounter,
                      icon: Icons.check_rounded,
                      label: _submitting ? 'Submitting...' : 'Confirm & Submit Encounter',
                      variant: AppPillButtonVariant.dark,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTranscribeStatusCard() {
    final status = (_processingStatus ?? '').toLowerCase();
    String label = 'Processing';
    if (status == 'uploading') {
      label = 'Uploading audio';
    } else if (status == 'transcribing') {
      label = 'Transcribing audio';
    } else if (status == 'extracting') {
      label = 'Extracting clinical entities';
    }

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
          Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$label... ${_voiceJobId ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Language: ${_selectedLanguageLabel()}',
            style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
          ),
          if (_detectedLanguage != null && _detectedLanguage!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Detected: $_detectedLanguage',
              style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String _selectedLanguageLabel() {
    for (final option in _languageOptions) {
      if (option.value == _selectedTranscriptionLanguage) {
        return option.label;
      }
    }
    return _languageOptions.first.label;
  }

  Widget _buildPatientSelectorCard() {
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
          if (_selectedPatient != null)
            PatientSummaryCard(
              patient: _selectedPatient!,
              onChange: () {
                setState(() {
                  _selectedPatient = null;
                });
              },
              onEdit: () => _openPatientForm(existing: _selectedPatient),
            )
          else ...[
            PatientSearchField(
              controller: _patientSearchController,
              loading: _patientSearchLoading,
              onChanged: _onPatientSearchChanged,
              onAddNew: () => _openPatientForm(),
              onClear: () {
                _patientSearchController.clear();
                _runPatientSearch('');
              },
            ),
            if (_recentPatients.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentPatients.map((p) {
                  final label = '${p['name'] ?? 'Patient'}'.trim();
                  return InkWell(
                    onTap: () => _selectPatientById('${p['patient_id'] ?? ''}'),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.lightInputBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.lightBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.history_rounded, size: 14, color: AppColors.lightTextMuted),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label.isEmpty ? 'Patient' : label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.lightTextPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            if (_searchResults.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final patient = _searchResults[index];
                    return PatientResultTile(
                      patient: patient,
                      onTap: () => _selectPatientById('${patient['patient_id'] ?? ''}'),
                    );
                  },
                ),
              )
            else if (_patientSearchController.text.trim().isNotEmpty && !_patientSearchLoading)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'No matching patients found. You can add a new patient.',
                  style: TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
                ),
              ),
          ],
          if (_patientResolving) ...[
            const SizedBox(height: 8),
            const Text(
              'Loading patient details...',
              style: TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
            ),
          ],
          if (_patientError != null) ...[
            const SizedBox(height: 8),
            Text(
              _patientError!,
              style: const TextStyle(color: AppColors.lightError, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioPickerCard() {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Encounter Audio',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.lightTextPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _recording
                          ? 'Recording in progress...'
                          : _selectedAudio != null
                              ? '${_selectedAudio!.name} (${(_selectedAudio!.size / 1024).toStringAsFixed(1)} KB)'
                              : 'Record or upload audio',
                      style: TextStyle(
                        color: _recording ? AppColors.lightError : AppColors.lightTextSecondary,
                        fontSize: 13,
                        fontWeight: _recording ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: _toggleRecording,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _recording ? AppColors.lightErrorSoft : const Color(0x1A0F756D),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _recording ? Icons.stop_rounded : Icons.mic_none_rounded,
                        color: _recording ? AppColors.lightError : AppColors.primary,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _pickAudioFile,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _selectedAudio == null ? AppColors.lightInputBg : const Color(0x1A0F756D),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedAudio == null ? AppColors.lightBorder : Colors.transparent,
                        ),
                      ),
                      child: Icon(
                        Icons.upload_file_rounded,
                        color: _selectedAudio == null ? AppColors.lightTextSecondary : AppColors.primary,
                        size: 24,
                      ),
                    ),
                  ),
                  if (_selectedAudio != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedAudio = null;
                          _selectedAudioBytes = null;
                          _transcribeResponse = null;
                          _transcribeResponseOriginal = null;
                          _resetSummaryTranslationState();
                          _voiceJobId = null;
                          _transcriptionJobId = null;
                          _processingStatus = null;
                          _detectedLanguage = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: AppColors.lightErrorSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.lightError,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          AppSelectField<String>(
            label: 'Transcription Language',
            value: _selectedTranscriptionLanguage,
            options: _languageOptions,
            enabled: !_loading && !_recording,
            onChanged: (value) {
              setState(() {
                _selectedTranscriptionLanguage = value;
              });
            },
          ),
        ],
      ),
    );
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
            'Summary Translation',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.lightTextPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            hasSummary
                ? 'Translate all AI details for view only. Original encounter data is submitted unchanged.'
                : 'AI details are unavailable for translation.',
            style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppSelectField<String>(
                  label: 'Summary Language',
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

  String _summaryLanguageLabel(String code) {
    for (final option in _summaryLanguageOptions) {
      if (option.value == code) {
        return option.label;
      }
    }
    return 'English (Original)';
  }

  Widget _buildResultCard(Map<String, dynamic> data) {
    return EncounterAiDetailsCard(data: data);
  }
}

class _AddOrEditPatientSheet extends StatefulWidget {
  const _AddOrEditPatientSheet({
    required this.apiClient,
    this.existingPatient,
  });

  final ApiClient apiClient;
  final Map<String, dynamic>? existingPatient;

  @override
  State<_AddOrEditPatientSheet> createState() => _AddOrEditPatientSheetState();
}

class _AddOrEditPatientSheetState extends State<_AddOrEditPatientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _abhaCtrl = TextEditingController();
  final _abhaAddressCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _address1Ctrl = TextEditingController();
  final _address2Ctrl = TextEditingController();
  final _villageCtrl = TextEditingController();
  final _gramCtrl = TextEditingController();
  final _blockCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();

  String _gender = 'female';
  bool _submitting = false;
  String? _error;
  int _currentStep = 0;

  bool get _editing => widget.existingPatient != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingPatient;
    if (existing != null) {
      _firstNameCtrl.text = '${existing['first_name'] ?? ''}';
      _middleNameCtrl.text = '${existing['middle_name'] ?? ''}';
      _lastNameCtrl.text = '${existing['last_name'] ?? ''}';
      _phoneCtrl.text = '${existing['phone_number'] ?? ''}';
      _dobCtrl.text = '${existing['date_of_birth'] ?? ''}';
      _ageCtrl.text = '${existing['age_years'] ?? ''}'.replaceAll('null', '');
      _abhaCtrl.text = '${existing['abha_number'] ?? ''}';
      _abhaAddressCtrl.text = '${existing['abha_address'] ?? ''}';
      _emailCtrl.text = '${existing['email'] ?? ''}';
      _address1Ctrl.text = '${existing['address_line1'] ?? ''}';
      _address2Ctrl.text = '${existing['address_line2'] ?? ''}';
      _villageCtrl.text = '${existing['village_or_ward'] ?? ''}';
      _gramCtrl.text = '${existing['gram_panchayat'] ?? ''}';
      _blockCtrl.text = '${existing['block_or_taluk'] ?? ''}';
      _districtCtrl.text = '${existing['district'] ?? ''}';
      _stateCtrl.text = '${existing['state'] ?? ''}';
      _pincodeCtrl.text = '${existing['pincode'] ?? ''}';
      _landmarkCtrl.text = '${existing['landmark'] ?? ''}';
      final candidate = '${existing['gender'] ?? 'female'}'.toLowerCase();
      _gender = const {'male', 'female', 'other', 'unknown'}.contains(candidate) ? candidate : 'female';
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    _ageCtrl.dispose();
    _abhaCtrl.dispose();
    _abhaAddressCtrl.dispose();
    _emailCtrl.dispose();
    _address1Ctrl.dispose();
    _address2Ctrl.dispose();
    _villageCtrl.dispose();
    _gramCtrl.dispose();
    _blockCtrl.dispose();
    _districtCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _landmarkCtrl.dispose();
    super.dispose();
  }

  void _nextStep() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    setState(() {
      _currentStep++;
      _error = null;
    });
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _error = null;
      });
    }
  }

  void _prefillPatientDemoData() {
    final preset = DemoPrefillData.patient;
    setState(() {
      _firstNameCtrl.text = preset.firstName;
      _middleNameCtrl.text = preset.middleName;
      _lastNameCtrl.text = preset.lastName;
      _gender = preset.gender;
      _phoneCtrl.text = preset.phoneNumber;
      _dobCtrl.text = preset.dateOfBirth;
      _ageCtrl.text = preset.ageYears;
      _abhaCtrl.text = preset.abhaNumber;
      _abhaAddressCtrl.text = preset.abhaAddress;
      _emailCtrl.text = preset.email;
      _address1Ctrl.text = preset.addressLine1;
      _address2Ctrl.text = preset.addressLine2;
      _villageCtrl.text = preset.villageOrWard;
      _gramCtrl.text = preset.gramPanchayat;
      _blockCtrl.text = preset.blockOrTaluk;
      _districtCtrl.text = preset.district;
      _stateCtrl.text = preset.state;
      _pincodeCtrl.text = preset.pincode;
      _landmarkCtrl.text = preset.landmark;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    if (_dobCtrl.text.trim().isEmpty && _ageCtrl.text.trim().isEmpty) {
      setState(() {
        _error = 'Provide either Date of Birth or Age.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'first_name': _firstNameCtrl.text.trim(),
      'middle_name': _middleNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      'gender': _gender,
      'phone_number': _phoneCtrl.text.trim(),
      'address_line1': _address1Ctrl.text.trim(),
      'address_line2': _address2Ctrl.text.trim(),
      'village_or_ward': _villageCtrl.text.trim(),
      'gram_panchayat': _gramCtrl.text.trim(),
      'block_or_taluk': _blockCtrl.text.trim(),
      'district': _districtCtrl.text.trim(),
      'state': _stateCtrl.text.trim(),
      'pincode': _pincodeCtrl.text.trim(),
      'landmark': _landmarkCtrl.text.trim(),
      if (_dobCtrl.text.trim().isNotEmpty) 'date_of_birth': _dobCtrl.text.trim(),
      if (_ageCtrl.text.trim().isNotEmpty) 'age_years': int.tryParse(_ageCtrl.text.trim()) ?? 0,
      if (_abhaCtrl.text.trim().isNotEmpty) 'abha_number': _abhaCtrl.text.trim(),
      if (_abhaAddressCtrl.text.trim().isNotEmpty) 'abha_address': _abhaAddressCtrl.text.trim(),
      if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
      'consent_flags': {
        'data_sharing_consent': true,
        'abha_link_consent': _abhaCtrl.text.trim().isNotEmpty,
      },
    };

    try {
      final result = _editing
          ? await widget.apiClient.updatePatient(
              patientId: '${widget.existingPatient?['patient_id'] ?? ''}',
              payload: payload,
            )
          : await widget.apiClient.createPatient(payload: payload);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '${e.code}: ${e.message}';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Network issue. Unable to save patient right now.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _editing ? 'Edit Patient' : 'Add New Patient',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.lightTextPrimary),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DemoPrefillButton(
                          onPressed: _prefillPatientDemoData,
                          label: 'Prefill',
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, color: AppColors.lightTextPrimary),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildStepper(),
                const SizedBox(height: 24),
                if (_currentStep == 0)
                PatientFormSection(
                  title: 'Basic Details',
                  child: Column(
                    children: [
                      _textField(_firstNameCtrl, 'First Name *', validator: _required('First name is required')),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField(_middleNameCtrl, 'Middle Name')),
                          const SizedBox(width: 10),
                          Expanded(child: _textField(_lastNameCtrl, 'Last Name')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gender *',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _gender,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.lightTextMuted),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.lightTextPrimary,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.lightInputBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.lightBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.lightBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'male', child: Text('Male')),
                              DropdownMenuItem(value: 'female', child: Text('Female')),
                              DropdownMenuItem(value: 'other', child: Text('Other')),
                              DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() => _gender = value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField(
                        _phoneCtrl,
                        'Phone Number *',
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          final v = (value ?? '').replaceAll(RegExp(r'[^0-9+]'), '').trim();
                          if (v.isEmpty) {
                            return 'Phone number is required';
                          }
                          final digits = v.replaceAll('+', '');
                          if (digits.length < 10 || digits.length > 12) {
                            return 'Enter valid Indian mobile number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              _dobCtrl,
                              'Date of Birth (YYYY-MM-DD)',
                              keyboardType: TextInputType.datetime,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              _ageCtrl,
                              'Age (Years)',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
                else if (_currentStep == 1)
                  PatientFormSection(
                  title: 'Address',
                  child: Column(
                    children: [
                      _textField(_address1Ctrl, 'Address Line 1 *', validator: _required('Address is required')),
                      const SizedBox(height: 10),
                      _textField(_address2Ctrl, 'Address Line 2'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField(_villageCtrl, 'Village / Ward')),
                          const SizedBox(width: 10),
                          Expanded(child: _textField(_gramCtrl, 'Gram Panchayat')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField(_blockCtrl, 'Block / Taluk')),
                          const SizedBox(width: 10),
                          Expanded(child: _textField(_districtCtrl, 'District *', validator: _required('District is required'))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _textField(_stateCtrl, 'State *', validator: _required('State is required'))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              _pincodeCtrl,
                              'Pincode *',
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                final v = (value ?? '').trim();
                                if (v.isEmpty) {
                                  return 'Pincode is required';
                                }
                                if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                                  return 'Pincode must be 6 digits';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _textField(_landmarkCtrl, 'Landmark'),
                    ],
                  ),
                )
                else if (_currentStep == 2)
                  PatientFormSection(
                  title: 'ABDM/Contact (Optional)',
                  child: Column(
                    children: [
                      _textField(
                        _abhaCtrl,
                        'ABHA Number (14 digits)',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final v = (value ?? '').replaceAll(RegExp(r'\D'), '');
                          if (v.isEmpty) {
                            return null;
                          }
                          if (!RegExp(r'^\d{14}$').hasMatch(v)) {
                            return 'ABHA number must be 14 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _textField(_abhaAddressCtrl, 'ABHA Address (e.g. name@abdm)'),
                      const SizedBox(height: 10),
                      _textField(
                        _emailCtrl,
                        'Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty) {
                            return null;
                          }
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                            return 'Enter valid email';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: AppColors.lightError)),
                ],
                const SizedBox(height: 24),
                if (_currentStep == 0)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: AppPillButton(
                      onPressed: _submitting ? null : _nextStep,
                      icon: Icons.arrow_forward_rounded,
                      label: 'Continue',
                      variant: AppPillButtonVariant.primary,
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 52,
                          child: AppPillButton(
                            onPressed: _submitting ? null : _previousStep,
                            icon: Icons.arrow_back_rounded,
                            label: 'Back',
                            variant: AppPillButtonVariant.light,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 52,
                          child: AppPillButton(
                            onPressed: _submitting 
                                ? null 
                                : (_currentStep < 2 ? _nextStep : _submit),
                            icon: _currentStep < 2 ? Icons.arrow_forward_rounded : Icons.arrow_outward_rounded,
                            label: _submitting
                                ? (_editing ? 'Saving...' : 'Submitting...')
                                : (_currentStep < 2 ? 'Continue' : (_editing ? 'Save Changes' : 'Submit')),
                            variant: AppPillButtonVariant.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepper() {
    final steps = ['Basic Info', 'Address', 'Contact'];
    final children = <Widget>[];

    for (int i = 0; i < steps.length; i++) {
      final isActive = i == _currentStep;
      final isCompleted = i < _currentStep;
      
      if (isActive) {
        children.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A), // Dark navy as per UI
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  steps[i],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${i + 1}',
              style: TextStyle(
                color: isCompleted ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      
      if (i < steps.length - 1) {
        children.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: const Color(0xFFE2E8F0),
            ),
          ),
        );
      }
    }
    
    return Row(children: children);
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.lightTextPrimary,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.lightInputBg,
            hintText: 'Enter ${label.replaceAll('*', '').trim()}',
            hintStyle: const TextStyle(
              fontSize: 14,
              color: AppColors.lightPlaceholder,
              fontWeight: FontWeight.w400,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lightBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lightBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lightError),
            ),
          ),
        ),
      ],
    );
  }

  FormFieldValidator<String> _required(String message) {
    return (value) => (value ?? '').trim().isEmpty ? message : null;
  }
}
















