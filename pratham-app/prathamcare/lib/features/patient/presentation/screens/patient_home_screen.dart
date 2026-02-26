import 'package:flutter/material.dart';

import '../../../../core/widgets/app_shell.dart';

class PatientHomeScreen extends StatelessWidget {
  const PatientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShell(
      title: 'Patient Workspace',
      body: Center(child: Text('Patient home placeholder')),
    );
  }
}
