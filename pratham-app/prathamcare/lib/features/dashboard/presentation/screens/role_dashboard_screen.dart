import 'package:flutter/material.dart';

import '../../../../core/widgets/app_shell.dart';
import '../../../../data/repositories/cognito_auth_repository.dart';
import '../../../admin/presentation/screens/admin_doctor_list_screen.dart';
import '../../../asha/presentation/screens/asha_home_screen.dart';
import '../../../physician/presentation/screens/physician_home_screen.dart';
import '../../../shared/widgets/section_card.dart';

class RoleDashboardScreen extends StatefulWidget {
  const RoleDashboardScreen({super.key});

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  final CognitoAuthRepository _authRepository = CognitoAuthRepository.instance;
  String _role = '';

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = (await _authRepository.getRoleFromIdToken() ?? '').trim().toLowerCase();
    if (!mounted) {
      return;
    }
    setState(() => _role = role);
  }

  bool get _isAdmin => _role == 'clinic_admin' || _role == 'ops_admin' || _role == 'admin';

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'PrathamCare',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Select role workspace',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'ASHA Worker',
            subtitle: 'Voice-first field operations and offline capture',
            onTap: () => _open(context, const ASHAHomeScreen()),
          ),
          SectionCard(
            title: 'Physician',
            subtitle: 'EMR, pre-consult summaries, and scheduling',
            onTap: () => _open(context, const PhysicianHomeScreen()),
          ),
          if (_isAdmin)
            SectionCard(
              title: 'Doctors',
              subtitle: 'Admin doctor list, create, edit, and status management',
              onTap: () => _open(context, const AdminDoctorListScreen()),
            ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
