import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/network/api_client.dart';

class VoiceVisitScreen extends StatefulWidget {
  const VoiceVisitScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<VoiceVisitScreen> createState() => _VoiceVisitScreenState();
}

class _VoiceVisitScreenState extends State<VoiceVisitScreen> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _transcriptController = TextEditingController(
    text: 'Today completed ANC visit for Meena Devi. Weight 65 kg, BP 140/90, mild headache.',
  );

  bool _recording = false;
  bool _loading = false;
  bool _submitting = false;
  int _seconds = 0;
  Timer? _recordingTimer;
  String? _objectKey;
  Map<String, dynamic>? _transcribeResponse;
  String? _error;

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _transcriptController.dispose();
    super.dispose();
  }

  Future<void> _runAiExtract() async {
    setState(() {
      _loading = true;
      _error = null;
      _transcribeResponse = null;
    });

    try {
      final presign = await _apiClient.createVoicePresign(
        contentType: 'audio/wav',
        fileSizeBytes: 1024 * 512,
        context: 'asha_home_visit',
        patientId: widget.patientId,
        language: 'hi-IN',
      );
      _objectKey = '${presign['object_key'] ?? ''}';

      final transcribed = await _apiClient.transcribeVoice(
        objectKey: _objectKey!,
        language: 'hi-IN',
        context: 'asha_home_visit',
        patientId: widget.patientId,
        mockTranscription: _transcriptController.text,
      );

      setState(() {
        _transcribeResponse = transcribed;
      });
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

  Future<void> _submitEncounter() async {
    final data = _transcribeResponse;
    if (data == null) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _apiClient.submitEncounter(
        patientId: widget.patientId,
        visitType: '${(data['extracted_entities'] as Map<String, dynamic>?)?['visit_type'] ?? 'home_visit'}',
        occurredAt: DateTime.now().toUtc().toIso8601String(),
        transcription: '${data['transcription'] ?? ''}',
        extractedEntities: (data['extracted_entities'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
        clinicalAlerts: (data['clinical_alerts'] as List?) ?? const [],
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encounter submitted and synced.')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Voice Visit'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildRecorderCard(),
                const SizedBox(height: 12),
                _buildTranscriptInput(),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _runAiExtract,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: const Text('Process With AI'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.lightError),
                  ),
                ],
                const SizedBox(height: 16),
                if (_transcribeResponse != null) _buildResultCard(_transcribeResponse!),
                if (_transcribeResponse != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitEncounter,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Confirm & Submit Encounter'),
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

  Widget _buildRecorderCard() {
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
          InkWell(
            onTap: () {
              setState(() {
                _recording = !_recording;
                if (_recording) {
                  _seconds = 0;
                  _recordingTimer?.cancel();
                  _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
                    if (!mounted || !_recording) {
                      return;
                    }
                    setState(() => _seconds += 1);
                  });
                } else {
                  _recordingTimer?.cancel();
                }
              });
            },
            borderRadius: BorderRadius.circular(999),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: _recording ? AppColors.lightErrorSoft : const Color(0x1A0F756D),
              child: Icon(
                _recording ? Icons.stop_rounded : Icons.mic_none_rounded,
                color: _recording ? AppColors.lightError : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Visit Recording',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _recording ? 'Recording in progress...' : 'Tap microphone to simulate recording.',
                  style: const TextStyle(color: AppColors.lightTextMuted),
                ),
              ],
            ),
          ),
          Text(
            _recording ? '${_seconds}s' : 'Ready',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptInput() {
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
            'Transcript (editable)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _transcriptController,
            minLines: 4,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Enter or paste ASHA voice transcript...',
            ),
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
