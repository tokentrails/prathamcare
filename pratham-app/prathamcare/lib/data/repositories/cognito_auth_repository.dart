import 'dart:convert';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import '../models/user_profile.dart' as app_model;

class CognitoAuthRepository {
  CognitoAuthRepository._();

  static final CognitoAuthRepository instance = CognitoAuthRepository._();

  Future<AuthSignInOutcome> signIn({required String username, required String password}) async {
    final result = await Amplify.Auth.signIn(username: username, password: password);
    final step = result.nextStep.signInStep;
    return AuthSignInOutcome(
      isSignedIn: result.isSignedIn,
      nextStep: step.name,
      additionalInfo: result.nextStep.additionalInfo,
    );
  }

  Future<AuthSignInOutcome> confirmSignIn({
    required String confirmationValue,
    String? fullName,
  }) async {
    final options = fullName != null && fullName.trim().isNotEmpty
        ? ConfirmSignInOptions(
            pluginOptions: CognitoConfirmSignInPluginOptions(
              userAttributes: {
                CognitoUserAttributeKey.name: fullName.trim(),
              },
            ),
          )
        : const ConfirmSignInOptions();

    final result = await Amplify.Auth.confirmSignIn(
      confirmationValue: confirmationValue,
      options: options,
    );
    final step = result.nextStep.signInStep;
    return AuthSignInOutcome(
      isSignedIn: result.isSignedIn,
      nextStep: step.name,
      additionalInfo: result.nextStep.additionalInfo,
    );
  }

  Future<void> signOut() {
    return Amplify.Auth.signOut();
  }

  Future<bool> isSignedIn() async {
    final session = await Amplify.Auth.fetchAuthSession();
    return session.isSignedIn;
  }

  Future<String?> getAccessToken() async {
    final session = await Amplify.Auth.fetchAuthSession();
    if (!session.isSignedIn) {
      return null;
    }

    if (session is CognitoAuthSession) {
      final tokensResult = session.userPoolTokensResult;
      if (tokensResult is AuthSuccessResult<CognitoUserPoolTokens>) {
        return tokensResult.value.accessToken.raw;
      }
    }

    return null;
  }

  Future<String?> getRoleFromIdToken() async {
    final session = await Amplify.Auth.fetchAuthSession();
    if (!session.isSignedIn) {
      return null;
    }

    if (session is CognitoAuthSession) {
      final tokensResult = session.userPoolTokensResult;
      if (tokensResult is AuthSuccessResult<CognitoUserPoolTokens>) {
        final idToken = tokensResult.value.idToken.raw;
        return _extractRole(idToken);
      }
    }

    return null;
  }

  Future<app_model.UserProfile?> getUserProfile() async {
    final session = await Amplify.Auth.fetchAuthSession();
    if (!session.isSignedIn) {
      return null;
    }

    final attributes = await Amplify.Auth.fetchUserAttributes();
    String email = '';
    String name = '';
    String phone = '';
    String userId = '';

    for (final attribute in attributes) {
      final key = attribute.userAttributeKey.key;
      switch (key) {
        case 'email':
          email = attribute.value;
          break;
        case 'name':
          name = attribute.value;
          break;
        case 'phone_number':
          phone = attribute.value;
          break;
        case 'sub':
          userId = attribute.value;
          break;
      }
    }

    final role = await getRoleFromIdToken() ?? 'unknown';

    return app_model.UserProfile(
      userId: userId,
      email: email,
      name: name,
      phone: phone,
      role: role,
    );
  }

  Future<void> updateDisplayName(String name) async {
    if (name.trim().isEmpty) {
      return;
    }
    await Amplify.Auth.updateUserAttribute(
      userAttributeKey: CognitoUserAttributeKey.name,
      value: name.trim(),
    );
  }

  String? _extractRole(String jwtToken) {
    final parts = jwtToken.split('.');
    if (parts.length < 2) {
      return null;
    }
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final data = jsonDecode(decoded) as Map<String, dynamic>;

    final customRole = data['custom:role'];
    if (customRole is String && customRole.isNotEmpty) {
      return customRole;
    }

    final role = data['role'];
    if (role is String && role.isNotEmpty) {
      return role;
    }

    final groups = data['cognito:groups'];
    if (groups is List && groups.isNotEmpty && groups.first is String) {
      return groups.first as String;
    }

    return null;
  }
}

class AuthSignInOutcome {
  const AuthSignInOutcome({
    required this.isSignedIn,
    required this.nextStep,
    required this.additionalInfo,
  });

  final bool isSignedIn;
  final String nextStep;
  final Map<String, dynamic> additionalInfo;

  bool get requiresNewPassword => nextStep == 'confirmSignInWithNewPassword';
}
