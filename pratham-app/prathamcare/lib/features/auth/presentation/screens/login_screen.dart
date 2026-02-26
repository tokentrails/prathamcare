import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int selectedRole = 0;
  bool rememberMe = false;
  bool obscurePassword = true;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

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
                                    onPressed: () {},
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
      height: 54,
      child: ElevatedButton(
        onPressed: () {
          if (selectedRole == 0) {
            Navigator.of(context).pushReplacementNamed('/physician');
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Only Physician dashboard is enabled right now.'),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.2),
          shape: const StadiumBorder(),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Sign In',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 18),
          ],
        ),
      ),
    );
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
