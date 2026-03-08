import 'package:flutter/material.dart';

import 'config/app_router.dart';
import 'config/app_theme.dart';

class PrathamCareApp extends StatelessWidget {
  const PrathamCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrathamCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
