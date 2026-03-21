import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/auth_notifier.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/profile/presentation/screens/profile_setup_screen.dart';
import '../../features/home/main_shell.dart';
import '../../features/home/home_screen.dart';
import '../../features/consultation/presentation/screens/consultations_screen.dart';
import '../../features/consultation/presentation/screens/consultation_detail_screen.dart';
import '../../features/consultation/presentation/screens/session_detail_screen.dart';
import '../../features/assistant/presentation/screens/assistant_screen.dart';
import '../../features/assistant/presentation/screens/chat_screen.dart';
import '../../features/document/presentation/screens/document_screen.dart';
import '../../features/buddy/presentation/screens/buddy_screen.dart';
import '../../features/mental_health/presentation/screens/mental_health_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoading =
          authState.isLoading || authState.value?.status == AuthStatus.unknown;

      // While auth is resolving, stay on splash
      if (isLoading) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }

      final isAuthenticated =
          authState.value?.status == AuthStatus.authenticated;
      final loc = state.matchedLocation;
      final isOnAuthPage = loc.startsWith('/auth');

      // Not authenticated and not on a login/signup page → go to login
      if (!isAuthenticated && !isOnAuthPage) return '/auth/login';
      // Authenticated but still on splash or auth pages → go home
      if (isAuthenticated && (loc == '/splash' || isOnAuthPage)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),

      // Auth routes
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/signup', builder: (_, __) => const SignUpScreen()),
      GoRoute(
        path: '/auth/profile-setup',
        builder: (_, __) => const ProfileSetupScreen(),
      ),

      // Main app shell
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/consultations',
            builder: (_, __) => const ConsultationsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => ConsultationDetailScreen(
                    consultationId: s.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'sessions/:sessionId',
                    builder: (_, s) => SessionDetailScreen(
                      consultationId: s.pathParameters['id']!,
                      sessionId: s.pathParameters['sessionId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/assistant',
            builder: (_, __) => const AssistantScreen(),
            routes: [
              GoRoute(
                path: ':conversationId',
                builder: (_, s) => ChatScreen(
                    conversationId: s.pathParameters['conversationId']!),
              ),
            ],
          ),
          GoRoute(
              path: '/documents', builder: (_, __) => const DocumentScreen()),
          GoRoute(path: '/buddy', builder: (_, __) => const BuddyScreen()),
          GoRoute(
            path: '/mental-health',
            builder: (_, __) => const MentalHealthScreen(),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});
