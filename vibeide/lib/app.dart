import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'shared/theme.dart';
import 'features/projects/project_manager_screen.dart';
import 'features/onboarding/onboarding.dart';

class VibeIdeApp extends ConsumerWidget {
  const VibeIdeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'VibeIDE',
      theme: vscodeDark,
      debugShowCheckedModeBanner: false,
      home: const _Root(),
    );
  }
}

/// Shows onboarding on first launch, then the Project Manager.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(onboardedProvider);
    return onboarded.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF1E1E1E),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const ProjectManagerScreen(),
      data: (done) => done
          ? const ProjectManagerScreen()
          : OnboardingScreen(
              onDone: () => ref.invalidate(onboardedProvider),
            ),
    );
  }
}
