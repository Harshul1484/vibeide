import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/db.dart';
import 'ai_client.dart';

final aiConfigProvider = StateProvider<AiConfig>((ref) => const AiConfig(
      provider: AiProvider.claude,
      apiKey: '',
      model: 'claude-sonnet-4-6',
    ));

final aiClientProvider = Provider<AiClient>((ref) {
  final config = ref.watch(aiConfigProvider);
  return AiClient(config);
});

String _dayKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

class TokenBudgetNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final repo = ref.read(projectRepoProvider);
    return repo.getTokenUsage(_dayKey());
  }

  Future<void> record(int tokens) async {
    final repo = ref.read(projectRepoProvider);
    await repo.recordTokenUsage(_dayKey(), tokens);
    ref.invalidateSelf();
  }

  bool canSend(int estimatedTokens) {
    final limit = ref.read(aiConfigProvider).dailyTokenLimit;
    final used = state.valueOrNull ?? 0;
    return used + estimatedTokens <= limit;
  }
}

final tokenBudgetProvider =
    AsyncNotifierProvider<TokenBudgetNotifier, int>(
        TokenBudgetNotifier.new);
