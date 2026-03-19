import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/join_clinic_screen.dart';
import '../../features/auth/presentation/waiting_approval_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/dashboard/presentation/dashboard_layout.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      if (authState.isLoading) return '/splash';

      final isAuth = authState.value != null;
      final isLoggingIn =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/join';
      final isSplash = state.matchedLocation == '/splash';

      if (!isAuth) {
        return isLoggingIn ? null : '/login';
      }

      final userProviderState = ref.watch(currentUserProvider);

      // If logged in but user data is still loading
      if (userProviderState.isLoading) {
        return isSplash ? null : '/splash';
      }

      final user = userProviderState.value;
      if (user == null) {
        // Document didn't exist or errored.
        return isLoggingIn ? null : '/login';
      }

      // Check approval status
      if (!user.isApproved) {
        if (state.matchedLocation != '/waiting-approval') {
          return '/waiting-approval';
        }
        return null;
      }

      if (isLoggingIn ||
          isSplash ||
          state.matchedLocation == '/waiting-approval') {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/join',
        builder: (context, state) => const JoinClinicScreen(),
      ),
      GoRoute(
        path: '/waiting-approval',
        builder: (context, state) => const WaitingApprovalScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardLayout(),
      ),
    ],
  );
});
