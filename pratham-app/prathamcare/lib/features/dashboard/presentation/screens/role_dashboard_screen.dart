import 'package:flutter/material.dart';

import '../../../../core/widgets/app_shell.dart';
import '../../../asha/presentation/screens/asha_home_screen.dart';
import '../../../physician/presentation/screens/physician_home_screen.dart';
import '../../../shared/widgets/section_card.dart';

class RoleDashboardScreen extends StatelessWidget {
  const RoleDashboardScreen({super.key});

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
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
