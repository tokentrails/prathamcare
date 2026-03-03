import 'dart:typed_data';
import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../data/network/api_client.dart';

class VoiceVisitScreen extends StatefulWidget {
  const VoiceVisitScreen({super.key, this.patientId});

  final String? patientId;

  @override
  State<VoiceVisitScreen> createState() => _VoiceVisitScreenState();
}

class _VoiceVisitScreenState extends State<VoiceVisitScreen> {
  final ApiClient _apiClient = ApiClient();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final TextEditingController _patientIdController = TextEditingController();

  PlatformFile? _selectedAudio;
  Uint8List? _selectedAudioBytes;
  bool _loading = false;
  bool _submitting = false;
  bool _recording = false;
  String? _objectKey;
  String? _voiceJobId;
  String? _transcriptionJobId;
  String? _recordingPath;
  String _recordingExtension = 'wav';
  Map<String, dynamic>? _transcribeResponse;
  String? _processingStatus;
  String? _error;
  String? _selectedPatientHint;

  static const List<Map<String, String>> _suggestedPatients = [
    {'id': 'demo-ka-patient-0001', 'name': 'Meena Devi (Demo)'},
  ];

  @override
  void initState() {
    super.initState();
    _patientIdController.text = (widget.patientId?.trim().isNotEmpty ?? false)
        ? widget.patientId!.trim()
        : _suggestedPatients.first['id']!;
    _selectedPatientHint = _suggestedPatients.first['name'];
  }

  @override
  void dispose() {
    _patientIdController.dispose();
    _audioRecorder.dispose();
    super.dispose();
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
      _voiceJobId = null;
      _transcriptionJobId = null;
      _processingStatus = null;
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
        // Give recorder a moment to flush buffers before reading.
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
          _voiceJobId = null;
          _transcriptionJobId = null;
          _processingStatus = null;
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

  Future<void> _runAiExtract() async {
    final patientId = _patientIdController.text.trim();
    if (patientId.isEmpty) {
      setState(() {
        _error = 'Please select or enter a patient ID.';
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
      _voiceJobId = null;
      _transcriptionJobId = null;
      _processingStatus = 'uploading';
    });

    try {
      final contentType = _contentTypeFromFileName(_selectedAudio!.name);
      final presign = await _apiClient.createVoicePresign(
        contentType: contentType,
        fileSizeBytes: _selectedAudioBytes!.lengthInBytes,
        context: 'asha_home_visit',
        patientId: patientId,
        language: '',
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
        language: '',
        context: 'asha_home_visit',
        patientId: patientId,
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
      });

      if (status == 'completed') {
        setState(() {
          _transcribeResponse = statusRes;
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
    final data = _transcribeResponse;
    if (data == null) {
      return;
    }
    final patientId = _patientIdController.text.trim();
    if (patientId.isEmpty) {
      setState(() {
        _error = 'Please select or enter a patient ID.';
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
                _buildPatientSelectorCard(),
                const SizedBox(height: 12),
                _buildAudioPickerCard(),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: AppPillButton(
                    onPressed: _loading ? null : _runAiExtract,
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
                if (_transcribeResponse != null) _buildResultCard(_transcribeResponse!),
                if (_transcribeResponse != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: AppPillButton(
                      onPressed: _submitting ? null : _submitEncounter,
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
      child: Row(
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
    );
  }

  Widget _buildPatientSelectorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Patient',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _suggestedPatients.any((p) => p['id'] == _patientIdController.text.trim())
                ? _patientIdController.text.trim()
                : null,
            decoration: const InputDecoration(
              hintText: 'Choose from suggested patients',
            ),
            items: _suggestedPatients
                .map(
                  (p) => DropdownMenuItem<String>(
                    value: p['id'],
                    child: Text('${p['name']} - ${p['id']}'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              final selected = _suggestedPatients.firstWhere((p) => p['id'] == value, orElse: () => {'name': ''});
              setState(() {
                _patientIdController.text = value;
                _selectedPatientHint = selected['name'];
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _patientIdController,
            decoration: const InputDecoration(
              labelText: 'Patient ID',
              hintText: 'e.g. demo-ka-patient-0001',
            ),
          ),
          if (_selectedPatientHint != null && _selectedPatientHint!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Selected: $_selectedPatientHint',
              style: const TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
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
      child: Row(
        children: [
          Column(
            children: [
              InkWell(
                onTap: _toggleRecording,
                borderRadius: BorderRadius.circular(999),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: _recording ? AppColors.lightErrorSoft : const Color(0x1A0F756D),
                  child: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _recording ? AppColors.lightError : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickAudioFile,
                borderRadius: BorderRadius.circular(999),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: _selectedAudio == null ? AppColors.lightErrorSoft : const Color(0x1A0F756D),
                  child: Icon(
                    Icons.upload_file_rounded,
                    color: _selectedAudio == null ? AppColors.lightError : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Encounter Audio (Record or Upload)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _recording
                      ? 'Recording in progress... tap mic to stop.'
                      : _selectedAudio != null
                      ? 'Selected: ${_selectedAudio!.name}'
                      : 'Use mic to record or upload .wav/.mp3 file (<=10 MB).',
                  style: const TextStyle(color: AppColors.lightTextMuted),
                ),
              ],
            ),
          ),
          Text(
            _selectedAudio != null ? '${(_selectedAudio!.size / 1024).toStringAsFixed(1)} KB' : 'No File',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> data) {
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
          const Text('AI Extraction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _topFieldCard('Patient', '${extracted['patient_name'] ?? '-'}'),
              _topFieldCard('Visit Type', '${extracted['visit_type'] ?? '-'}'),
              _topFieldCard('Referral', referralUrgency.isEmpty ? '-' : referralUrgency),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            _sectionTitle('Clinical Summary'),
            _bodyText(summary),
          ],
          const SizedBox(height: 10),
          _sectionTitle('Conversation'),
          _textBlock('Transcription', transcription),
          const SizedBox(height: 8),
          _textBlock('Translation (English)', translation),
          const SizedBox(height: 8),
          if (symptoms.isNotEmpty) ...[
            _sectionTitle('Symptoms'),
            Wrap(spacing: 8, runSpacing: 8, children: symptoms.map(_chip).toList()),
            const SizedBox(height: 10),
          ],
          if (symptomDetails.isNotEmpty) ...[
            _sectionTitle('Symptom Details'),
            ...symptomDetails.map((item) => _bullet('${item['symptom'] ?? '-'}: ${item['description'] ?? '-'}')),
            const SizedBox(height: 10),
          ],
          if (vitals.isNotEmpty) ...[
            _sectionTitle('Vitals'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: vitals.entries.map((e) => _chip('${e.key}: ${e.value}')).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (nextSteps.isNotEmpty) ...[
            _sectionTitle('ASHA Next Steps'),
            ...nextSteps.map(_bullet),
            const SizedBox(height: 10),
          ],
          if (followUps.isNotEmpty) ...[
            _sectionTitle('Follow-up Recommendations'),
            ...followUps.map(_bullet),
            const SizedBox(height: 10),
          ],
          if (redFlags.isNotEmpty) ...[
            _sectionTitle('Red Flags'),
            ...redFlags.map(_bullet),
            const SizedBox(height: 10),
          ],
          if (meds.isNotEmpty) ...[
            _sectionTitle('Medications Mentioned'),
            Wrap(spacing: 8, runSpacing: 8, children: meds.map(_chip).toList()),
            const SizedBox(height: 10),
          ],
          if (pregnancy.isNotEmpty) ...[
            _sectionTitle('Pregnancy Context'),
            ...pregnancy.entries.map((e) => _summaryRow(e.key, '${e.value}')),
            const SizedBox(height: 10),
          ],
          if (immunization.isNotEmpty) ...[
            _sectionTitle('Immunization Context'),
            ...immunization.entries.map((e) => _summaryRow(e.key, '${e.value}')),
            const SizedBox(height: 10),
          ],
          if (alerts.isNotEmpty) ...[
            _sectionTitle('Clinical Alerts'),
            ...alerts.map(
              (a) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _severitySurfaceColor('${a['severity'] ?? 'unknown'}'),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _severityBorderColor('${a['severity'] ?? 'unknown'}')),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _severityChip('${a['severity'] ?? 'unknown'}'),
                    const SizedBox(height: 4),
                    Text(
                      '${a['message'] ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    if ('${a['recommended_action'] ?? ''}'.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Recommended Action',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.lightTextMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${a['recommended_action']}',
                              style: const TextStyle(color: AppColors.lightTextSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }

  Widget _textBlock(String title, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            text.isEmpty ? '-' : text,
            style: const TextStyle(color: AppColors.lightTextSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(color: AppColors.lightTextSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topFieldCard(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x1A0F756D),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text),
    );
  }

  Widget _severityChip(String severity) {
    final label = severity.trim().isEmpty ? 'unknown' : severity.trim().toLowerCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _severityChipBackground(label),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _titleCase(label),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _severityChipTextColor(label),
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
        return AppColors.lightErrorSoft;
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
        return const Color(0xFFF3FBF6);
      case 'moderate':
        return const Color(0xFFFFFAF0);
      case 'high':
      case 'critical':
        return AppColors.lightErrorSoft;
      default:
        return const Color(0xFFF8FAFC);
    }
  }

  Color _severityBorderColor(String severity) {
    switch (severity.trim().toLowerCase()) {
      case 'low':
        return const Color(0xFF86EFAC);
      case 'moderate':
        return const Color(0xFFFCD34D);
      case 'high':
      case 'critical':
        return const Color(0xFFFCA5A5);
      default:
        return const Color(0xFFE2E8F0);
    }
  }

  String _titleCase(String input) {
    if (input.isEmpty) {
      return input;
    }
    return '${input[0].toUpperCase()}${input.substring(1)}';
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 7, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.lightTextSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(
      text.isEmpty ? '-' : text,
      style: const TextStyle(color: AppColors.lightTextSecondary, height: 1.4),
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
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty && value.trim().toLowerCase() != 'null';
    }
    if (value is List) {
      return value.isNotEmpty;
    }
    if (value is Map) {
      return value.isNotEmpty;
    }
    return true;
  }
}
