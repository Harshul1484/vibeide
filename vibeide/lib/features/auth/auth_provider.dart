import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'github_auth.dart';

const _tokenKey = 'github_access_token';

// Holds the in-progress device auth state so UI can show the code
class DeviceAuthState {
  final bool isLoading;
  final DeviceCodeResponse? deviceCode;
  final String? error;

  const DeviceAuthState({
    this.isLoading = false,
    this.deviceCode,
    this.error,
  });
}

/// Reactive device-flow UI state. The Details pane / settings watch this to
/// show the user code while sign-in is polling.
final deviceAuthProvider =
    StateProvider<DeviceAuthState>((ref) => const DeviceAuthState());

class AuthNotifier extends AsyncNotifier<String?> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final _deviceAuth = GitHubDeviceAuth();

  @override
  Future<String?> build() async {
    return _storage.read(key: _tokenKey);
  }

  Future<void> signIn() async {
    ref.read(deviceAuthProvider.notifier).state =
        const DeviceAuthState(isLoading: true);

    try {
      // Step 1: get device code
      final deviceCode = await _deviceAuth.requestDeviceCode();
      // Show the code immediately so the user can enter it on GitHub.
      ref.read(deviceAuthProvider.notifier).state =
          DeviceAuthState(deviceCode: deviceCode);

      // Step 2: open browser for user to enter code
      await _deviceAuth.openVerificationUrl(deviceCode.verificationUri);

      // Step 3: poll for token (the code stays on screen the whole time)
      final token = await _deviceAuth.pollForToken(deviceCode);

      await _storage.write(key: _tokenKey, value: token);
      ref.read(deviceAuthProvider.notifier).state = const DeviceAuthState();
      state = AsyncData(token);
    } catch (e, st) {
      ref.read(deviceAuthProvider.notifier).state =
          DeviceAuthState(error: e.toString());
      state = AsyncError(e, st);
    }
  }

  /// Dismiss an in-progress / errored device sign-in.
  void cancelSignIn() {
    ref.read(deviceAuthProvider.notifier).state = const DeviceAuthState();
  }

  Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
    ref.read(deviceAuthProvider.notifier).state = const DeviceAuthState();
    state = const AsyncData(null);
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, String?>(AuthNotifier.new);

final githubTokenProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).valueOrNull;
});

final githubApiProvider = Provider<GitHubApi?>((ref) {
  final token = ref.watch(githubTokenProvider);
  return token != null ? GitHubApi(token) : null;
});
