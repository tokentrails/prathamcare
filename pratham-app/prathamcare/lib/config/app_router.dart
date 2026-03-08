import 'package:flutter/material.dart';

import '../features/asha/presentation/screens/public_appointment_request_screen.dart';
import '../features/asha/presentation/screens/asha_home_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/dashboard/presentation/screens/role_dashboard_screen.dart';
import '../features/physician/presentation/screens/physician_home_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/dashboard':
        return MaterialPageRoute<void>(
          builder: (_) => const RoleDashboardScreen(),
          settings: settings,
        );
      case '/physician':
        return MaterialPageRoute<void>(
          builder: (_) => const PhysicianHomeScreen(),
          settings: settings,
        );
      case '/asha':
        return MaterialPageRoute<void>(
          builder: (_) => const ASHAHomeScreen(),
          settings: settings,
        );
      case '/public/appointments/request':
        return MaterialPageRoute<void>(
          builder: (_) => const PublicAppointmentRequestScreen(),
          settings: settings,
        );
      case '/profile':
        return MaterialPageRoute<void>(
          builder: (_) => const ProfileScreen(),
          settings: settings,
        );
      case '/':
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const LoginScreen(),
          settings: settings,
        );
    }
  }
}
