import 'dart:convert';

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
    required String mockTranscription,
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
        'mock_transcription': mockTranscription,
      }),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> submitEncounter({
    String? bearerToken,
    required String patientId,
    required String visitType,
    required String occurredAt,
    required String transcription,
    required Map<String, dynamic> extractedEntities,
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
        'extracted_entities': extractedEntities,
        'clinical_alerts': clinicalAlerts,
      }),
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
