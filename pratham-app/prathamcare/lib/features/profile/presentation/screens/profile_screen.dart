import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/user_profile.dart';
import '../../../../data/repositories/cognito_auth_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final CognitoAuthRepository _authRepository = CognitoAuthRepository.instance;

  bool _loading = true;
  String? _error;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _authRepository.getUserProfile();
      if (!mounted) {
        return;
      }
      setState(() => _profile = profile);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Logout'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.lightError)),
                  const SizedBox(height: 12),
                ],
                if (!_loading && _profile == null)
                  const Text('No active session found.', style: TextStyle(color: AppColors.lightTextMuted)),
                if (_profile != null) ...[
                  _ProfileHeader(profile: _profile!),
                  const SizedBox(height: 16),
                  _InfoCard(label: 'Full Name', value: _profile!.name.isEmpty ? '-' : _profile!.name),
                  _InfoCard(label: 'Email', value: _profile!.email.isEmpty ? '-' : _profile!.email),
                  _InfoCard(label: 'Phone', value: _profile!.phone.isEmpty ? '-' : _profile!.phone),
                  _InfoCard(label: 'Role', value: _profile!.role),
                  _InfoCard(label: 'User ID', value: _profile!.userId.isEmpty ? '-' : _profile!.userId),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _authRepository.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final initial = _avatarInitial(profile);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x140F756D), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary,
            child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name.isEmpty ? 'PrathamCare User' : profile.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.email.isEmpty ? 'No email found' : profile.email,
                  style: const TextStyle(color: AppColors.lightTextMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _avatarInitial(UserProfile profile) {
    final source = profile.name.isNotEmpty ? profile.name : profile.email;
    if (source.isEmpty) {
      return 'U';
    }
    return source.trim()[0].toUpperCase();
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.lightTextMuted)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
