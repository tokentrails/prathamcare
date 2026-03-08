import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../data/repositories/cognito_auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final CognitoAuthRepository _authRepository = CognitoAuthRepository.instance;
  static const Duration _authTimeout = Duration(seconds: 20);

  int selectedRole = 0;
  bool rememberMe = false;
  bool obscurePassword = true;
  bool isSigningIn = false;
  String? signInError;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restoreExistingSession();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 384),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),
                              _buildLogo(),
                              const SizedBox(height: 40),
                              _buildRoleTabs(),
                              const SizedBox(height: 32),
                              const Text(
                                'Welcome back, Doctor',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Please enter your credentials to access patient records.',
                                style: TextStyle(
                                  color: AppColors.lightTextMuted,
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _buildInputLabel('Email or Medical ID'),
                              const SizedBox(height: 6),
                              _buildInput(
                                controller: emailController,
                                hint: 'e.g. dr.sharma@pratham.care',
                                prefixIcon: Icons.badge_outlined,
                              ),
                              const SizedBox(height: 20),
                              _buildInputLabel('Password'),
                              const SizedBox(height: 6),
                              _buildInput(
                                controller: passwordController,
                                hint: '••••••••',
                                prefixIcon: Icons.lock_outline_rounded,
                                suffixIcon:
                                    obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                obscureText: obscurePassword,
                                onSuffixTap: () => setState(() => obscurePassword = !obscurePassword),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => setState(() => rememberMe = !rememberMe),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(color: const Color(0xFFCBD5E1)),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: rememberMe
                                              ? const Icon(Icons.check, size: 14, color: AppColors.primary)
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Remember me',
                                          style: TextStyle(
                                            color: Color(0xFF475569),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: _handleForgotPassword,
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.accent,
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _buildSignInButton(),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).pushNamed('/public/appointments/request'),
                                  child: const Text('Need ASHA home visit? Request appointment'),
                                ),
                              ),
                              if (signInError != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  signInError!,
                                  style: const TextStyle(color: AppColors.lightError, fontSize: 13),
                                ),
                              ],
                              const SizedBox(height: 32),
                              _buildOrLoginWith(),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: SizedBox(
        width: 254,
        height: 128,
        child: Image.asset(
          'assets/images/pratham-logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildRoleTabs() {
    const roles = ['Physician', 'ASHA', 'Admin'];
    const outerHeight = 56.0;
    const inset = 6.0;
    const gap = 4.0;
    const segmentRadius = 24.0;
    const segmentHeight = outerHeight - (inset * 2);

    return SizedBox(
      height: outerHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = (constraints.maxWidth - (inset * 2) - (gap * 2)) / 3;
          final selectedLeft = inset + selectedRole * (segmentWidth + gap);

          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: const Color(0x99E2E8F0),
              child: Stack(
                children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  top: inset,
                  left: selectedLeft,
                  width: segmentWidth,
                  height: segmentHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(segmentRadius),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 0,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(inset),
                      child: Row(
                        children: [
                          for (var i = 0; i < roles.length; i++) ...[
                            if (i > 0) const SizedBox(width: gap),
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => selectedRole = i),
                                borderRadius: BorderRadius.circular(segmentRadius),
                                child: Center(
                                  child: Text(
                                    roles[i],
                                    style: TextStyle(
                                      color: i == selectedRole ? AppColors.primary : const Color(0xFF475569),
                                      fontSize: 14,
                                      height: 20 / 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.lightTextSecondary,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    IconData? suffixIcon,
    bool obscureText = false,
    VoidCallback? onSuffixTap,
  }) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(prefixIcon, size: 20, color: AppColors.lightPlaceholder),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              style: const TextStyle(
                color: AppColors.lightTextPrimary,
                fontSize: 16,
                height: 20 / 16,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: const TextStyle(
                  color: AppColors.lightPlaceholder,
                  fontSize: 16,
                  height: 20 / 16,
                ),
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (suffixIcon != null) ...[
            InkWell(
              onTap: onSuffixTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(suffixIcon, size: 20, color: AppColors.lightPlaceholder),
              ),
            ),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: AppPillButton(
        onPressed: isSigningIn ? null : _handleCognitoSignIn,
        icon: Icons.arrow_upward_rounded,
        label: isSigningIn ? 'Signing In...' : 'Sign In',
        variant: AppPillButtonVariant.primary,
      ),
    );
  }

  Future<void> _handleCognitoSignIn() async {
    setState(() {
      isSigningIn = true;
      signInError = null;
    });

    try {
      final username = emailController.text.trim();
      final password = passwordController.text.trim();
      if (username.isEmpty || password.isEmpty) {
        throw Exception('Username and password are required.');
      }

      if (await _authRepository.isSignedIn()) {
        await _authRepository.signOut();
      }

      final signInOutcome = await _authRepository
          .signIn(username: username, password: password)
          .timeout(_authTimeout, onTimeout: () {
        throw Exception(
          'Sign-in timed out. Check internet/Cognito config and try again.',
        );
      });
      if (!signInOutcome.isSignedIn) {
        if (signInOutcome.requiresNewPassword) {
          final challengeInput = await _collectNewPasswordChallengeInput();
          if (challengeInput == null) {
            throw Exception('Sign-in cancelled. New password is required.');
          }

          final confirmOutcome = await _authRepository
              .confirmSignIn(
                confirmationValue: challengeInput.newPassword,
                fullName: challengeInput.fullName,
              )
              .timeout(_authTimeout, onTimeout: () {
            throw Exception(
              'Password challenge timed out. Please retry.',
            );
          });
          if (!confirmOutcome.isSignedIn) {
            throw Exception(
              'Challenge step pending: ${confirmOutcome.nextStep}. Please complete the required step in Cognito.',
            );
          }
          await _authRepository.updateDisplayName(challengeInput.fullName);
        } else {
          throw Exception('Additional auth challenge required: ${signInOutcome.nextStep}.');
        }
      }

      final tokenRole = await _authRepository
          .getRoleFromIdToken()
          .timeout(_authTimeout, onTimeout: () => null);
      _syncSelectedRoleFromToken(tokenRole);

      if (!mounted) {
        return;
      }
      _routeByRole(tokenRole);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        final message = e.toString().replaceFirst('Exception: ', '');
        if (message.contains('already signed in')) {
          signInError = null;
        } else {
          signInError = message;
        }
      });
      if (e.toString().contains('already signed in')) {
        await _restoreExistingSession();
      }
    } finally {
      if (mounted) {
        setState(() => isSigningIn = false);
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final username = emailController.text.trim();
    if (username.isEmpty) {
      setState(() {
        signInError = 'Enter your email first, then tap Forgot Password.';
      });
      return;
    }

    try {
      final start = await _authRepository
          .startForgotPassword(username: username)
          .timeout(_authTimeout, onTimeout: () {
        throw Exception(
          'Reset password request timed out. Please try again.',
        );
      });
      if (start.isComplete) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset is already complete. Please sign in.')),
        );
        return;
      }

      if (!mounted) {
        return;
      }
      final reset = await _collectForgotPasswordInput(start);
      if (reset == null) {
        return;
      }

      await _authRepository
          .confirmForgotPassword(
            username: username,
            confirmationCode: reset.code,
            newPassword: reset.newPassword,
          )
          .timeout(_authTimeout, onTimeout: () {
        throw Exception(
          'Password reset confirmation timed out. Please retry.',
        );
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset successful. Please sign in with new password.')),
      );
      setState(() {
        signInError = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        signInError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<_NewPasswordChallengeInput?> _collectNewPasswordChallengeInput() async {
    final fullNameController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? validationError;

    final result = await showDialog<_NewPasswordChallengeInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Set New Password'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'Enter your full name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: const TextStyle(color: AppColors.lightError, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = fullNameController.text.trim();
                    final pass = newPasswordController.text.trim();
                    final confirm = confirmPasswordController.text.trim();

                    if (name.isEmpty) {
                      setDialogState(() => validationError = 'Full name is required.');
                      return;
                    }
                    if (pass.length < 8) {
                      setDialogState(() => validationError = 'Password must be at least 8 characters.');
                      return;
                    }
                    if (pass != confirm) {
                      setDialogState(() => validationError = 'Passwords do not match.');
                      return;
                    }

                    Navigator.of(context).pop(
                      _NewPasswordChallengeInput(fullName: name, newPassword: pass),
                    );
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    fullNameController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    return result;
  }

  Future<_ForgotPasswordInput?> _collectForgotPasswordInput(PasswordResetStartOutcome start) async {
    final codeController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? validationError;

    final result = await showDialog<_ForgotPasswordInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reset Password'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      start.destination.isNotEmpty
                          ? 'Verification code sent via ${start.deliveryMedium} to ${start.destination}'
                          : 'Enter the verification code and your new password.',
                      style: const TextStyle(fontSize: 13, color: AppColors.lightTextMuted),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'Verification Code',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: const TextStyle(color: AppColors.lightError, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final code = codeController.text.trim();
                    final pass = newPasswordController.text.trim();
                    final confirm = confirmPasswordController.text.trim();

                    if (code.isEmpty) {
                      setDialogState(() => validationError = 'Verification code is required.');
                      return;
                    }
                    if (pass.length < 8) {
                      setDialogState(() => validationError = 'Password must be at least 8 characters.');
                      return;
                    }
                    if (pass != confirm) {
                      setDialogState(() => validationError = 'Passwords do not match.');
                      return;
                    }

                    Navigator.of(context).pop(
                      _ForgotPasswordInput(code: code, newPassword: pass),
                    );
                  },
                  child: const Text('Reset'),
                ),
              ],
            );
          },
        );
      },
    );

    codeController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    return result;
  }

  Future<void> _restoreExistingSession() async {
    try {
      final signedIn = await _authRepository.isSignedIn();
      if (!signedIn || !mounted) {
        return;
      }

      final tokenRole = await _authRepository.getRoleFromIdToken();
      _syncSelectedRoleFromToken(tokenRole);
      _routeByRole(tokenRole);
    } catch (_) {
      // Keep user on login screen if session restore fails.
    }
  }

  void _syncSelectedRoleFromToken(String? tokenRole) {
    if (tokenRole == null || tokenRole.isEmpty) {
      return;
    }
    final normalized = tokenRole.trim().toLowerCase();
    final nextRoleIndex = switch (normalized) {
      'doctor' => 0,
      'asha_worker' => 1,
      'asha' => 1,
      _ => 2,
    };

    if (mounted && selectedRole != nextRoleIndex) {
      setState(() => selectedRole = nextRoleIndex);
    }
  }

  void _routeByRole(String? tokenRole) {
    final normalized = (tokenRole ?? '').trim().toLowerCase();
    if (!mounted) {
      return;
    }
    switch (normalized) {
      case 'doctor':
        Navigator.of(context).pushReplacementNamed('/physician');
        return;
      case 'asha_worker':
      case 'asha':
        Navigator.of(context).pushReplacementNamed('/asha');
        return;
      case 'clinic_admin':
      case 'ops_admin':
      case 'admin':
        Navigator.of(context).pushReplacementNamed('/dashboard');
        return;
      default:
        Navigator.of(context).pushReplacementNamed('/dashboard');
        return;
    }
  }

  Widget _buildOrLoginWith() {
    return Column(
      children: [
        Row(
          children: const [
            Expanded(child: Divider(color: Color(0xFFE2E8F0))),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR LOGIN WITH',
                style: TextStyle(
                  color: AppColors.lightPlaceholder,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Expanded(child: Divider(color: Color(0xFFE2E8F0))),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(Icons.fingerprint, color: AppColors.lightTextSecondary),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.verified_user_outlined, color: Color(0xCC0F766E), size: 14),
              SizedBox(width: 8),
              Text(
                'CLINICAL USE ONLY',
                style: TextStyle(
                  color: Color(0xCC0F766E),
                  fontSize: 12,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            textAlign: TextAlign.center,
            TextSpan(
              style: const TextStyle(
                color: AppColors.lightPlaceholder,
                fontSize: 12,
                height: 1.4,
              ),
              children: const [
                TextSpan(text: 'By logging in, you agree to the '),
                TextSpan(
                  text: 'Terms of Service',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
                TextSpan(text: ' & '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
                TextSpan(text: '.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewPasswordChallengeInput {
  const _NewPasswordChallengeInput({
    required this.fullName,
    required this.newPassword,
  });

  final String fullName;
  final String newPassword;
}

class _ForgotPasswordInput {
  const _ForgotPasswordInput({
    required this.code,
    required this.newPassword,
  });

  final String code;
  final String newPassword;
}
