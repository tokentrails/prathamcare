import 'package:flutter/material.dart';

import '../../../../core/widgets/app_shell.dart';

class ASHAHomeScreen extends StatelessWidget {
  const ASHAHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShell(
      title: 'ASHA Workspace',
      body: Center(child: Text('ASHA home placeholder')),
    );
  }
}
