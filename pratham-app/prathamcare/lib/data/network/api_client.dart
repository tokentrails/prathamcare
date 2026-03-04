import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../repositories/cognito_auth_repository.dart';

class ApiClient {
  ApiClient({http.Client? client, this.baseUrl = AppConstants.apiBaseUrl})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> getSyncStatus({String? bearerToken}) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/sync/status'),
      headers: _headers(token),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> getVoiceHistory({
    String? bearerToken,
    int limit = 25,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/voice/history?limit=$limit'),
      headers: _headers(token),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> getEncounterHistory({
    String? bearerToken,
    int limit = 25,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/encounters/history?limit=$limit'),
      headers: _headers(token),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> getEncounterByID({
    String? bearerToken,
    required String encounterId,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/encounters/$encounterId'),
      headers: _headers(token),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> replaySync({
    String? bearerToken,
    int maxItems = 10,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/sync/replay'),
      headers: _headers(token),
      body: jsonEncode({'max_items': maxItems}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> createVoicePresign({
    String? bearerToken,
    required String contentType,
    required int fileSizeBytes,
    required String context,
    required String patientId,
    required String language,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/voice/presign'),
      headers: _headers(token),
      body: jsonEncode({
        'content_type': contentType,
        'file_size_bytes': fileSizeBytes,
        'context': context,
        'patient_id': patientId,
        'language': language,
      }),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> transcribeVoice({
    String? bearerToken,
    required String objectKey,
    required String language,
    required String context,
    required String patientId,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/voice/transcribe'),
      headers: _headers(token),
      body: jsonEncode({
        'object_key': objectKey,
        'language': language,
        'context': context,
        'patient_id': patientId,
      }),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> getVoiceTranscriptionStatus({
    String? bearerToken,
    required String voiceJobId,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/voice/transcribe/$voiceJobId'),
      headers: _headers(token),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> getVoiceTranscriptionStatusByJob({
    String? bearerToken,
    required String transcriptionJobId,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/voice/transcribe/job/$transcriptionJobId'),
      headers: _headers(token),
    );
    return _decode(res);
  }

  Future<void> uploadVoiceBytes({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final res = await _client.put(
      Uri.parse(uploadUrl),
      headers: {
        'Content-Type': contentType,
      },
      body: bytes,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        statusCode: res.statusCode,
        code: 'UPLOAD_FAILED',
        message: 'S3 upload failed with status ${res.statusCode}',
      );
    }
  }

  Future<Map<String, dynamic>> submitEncounter({
    String? bearerToken,
    required String patientId,
    required String visitType,
    required String occurredAt,
    required String transcription,
    String? translation,
    String? sourceAudioKey,
    required Map<String, dynamic> extractedEntities,
    dynamic medicalEntities,
    required List<dynamic> clinicalAlerts,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/encounters'),
      headers: _headers(token),
      body: jsonEncode({
        'patient_id': patientId,
        'visit_type': visitType,
        'occurred_at': occurredAt,
        'transcription': transcription,
        if (translation != null && translation.isNotEmpty) 'translation': translation,
        if (sourceAudioKey != null && sourceAudioKey.isNotEmpty) 'source_audio_key': sourceAudioKey,
        'extracted_entities': extractedEntities,
        if (medicalEntities != null) 'medical_entities': medicalEntities,
        'clinical_alerts': clinicalAlerts,
      }),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> createPatient({
    String? bearerToken,
    required Map<String, dynamic> payload,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.post(
      Uri.parse('$baseUrl/api/v1/patients'),
      headers: _headers(token),
      body: jsonEncode(payload),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> searchPatients({
    String? bearerToken,
    String? q,
    String? phone,
    String? abha,
    int limit = 10,
  }) async {
    final token = await _resolveToken(bearerToken);
    final params = <String, String>{
      'limit': '$limit',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (abha != null && abha.trim().isNotEmpty) 'abha': abha.trim(),
    };
    final uri = Uri.parse('$baseUrl/api/v1/patients/search').replace(queryParameters: params);
    final res = await _client.get(uri, headers: _headers(token));
    return _decode(res);
  }

  Future<Map<String, dynamic>> getPatientById({
    String? bearerToken,
    required String patientId,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/patients/$patientId'),
      headers: _headers(token),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> updatePatient({
    String? bearerToken,
    required String patientId,
    required Map<String, dynamic> payload,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.put(
      Uri.parse('$baseUrl/api/v1/patients/$patientId'),
      headers: _headers(token),
      body: jsonEncode(payload),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> getRecentPatients({
    String? bearerToken,
    int limit = 10,
  }) async {
    final token = await _resolveToken(bearerToken);
    final res = await _client.get(
      Uri.parse('$baseUrl/api/v1/patients/recent?limit=$limit'),
      headers: _headers(token),
    );
    return _decode(res);
  }

  Map<String, String> _headers(String bearerToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $bearerToken',
      };

  Future<String> _resolveToken(String? bearerToken) async {
    if (bearerToken != null && bearerToken.isNotEmpty) {
      return bearerToken;
    }
    final token = await CognitoAuthRepository.instance.getAccessToken();
    if (token == null || token.isEmpty) {
      throw ApiException(
        statusCode: 401,
        code: 'AUTHENTICATION_FAILED',
        message: 'No active Cognito session. Please sign in again.',
      );
    }
    return token;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final error = body['error'];
    if (error is Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        code: '${error['code'] ?? 'API_ERROR'}',
        message: '${error['message'] ?? 'Request failed'}',
      );
    }

    throw ApiException(
      statusCode: response.statusCode,
      code: 'API_ERROR',
      message: 'Request failed',
    );
  }
}

class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}
