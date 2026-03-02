import 'dart:typed_data';
import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
      allowedExtensions: const ['wav', 'mp3'],
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
        if (path == null || path.isEmpty) {
          setState(() {
            _error = 'Recording stop failed.';
            _recording = false;
          });
          return;
        }
        final bytes = await XFile(path).readAsBytes();
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
            name: 'recorded_visit.wav',
            size: bytes.length,
            path: path,
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
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: 'recorded_visit.wav',
      );
      setState(() {
        _recording = true;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _recording = false;
        _error = 'Failed to start recording: $e';
      });
    }
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
        language: 'hi-IN',
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
        language: 'hi-IN',
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
    final alerts = (data['clinical_alerts'] as List?) ?? const [];

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
          _kv('Patient', '${extracted['patient_name'] ?? '-'}'),
          _kv('Visit Type', '${extracted['visit_type'] ?? '-'}'),
          _kv('Transcription', '${data['transcription'] ?? '-'}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: vitals.entries
                .map(
                  (e) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x1A0F756D),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${e.key}: ${e.value}'),
                  ),
                )
                .toList(),
          ),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...alerts.map(
              (a) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.lightErrorSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${(a as Map)['message'] ?? ''}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: AppColors.lightTextSecondary, height: 1.45),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
