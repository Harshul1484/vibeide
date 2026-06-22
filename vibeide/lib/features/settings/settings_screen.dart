import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/ai/ai_client.dart';
import 'package:vibeide/features/ai/ai_provider.dart';
import 'package:vibeide/features/auth/auth_provider.dart';
import 'package:vibeide/features/auth/github_auth.dart';

const _models = {
  AiProvider.claude: [
    'claude-opus-4-7',
    'claude-sonnet-4-6',
    'claude-haiku-4-5',
  ],
  AiProvider.openai: ['gpt-4o', 'gpt-4o-mini'],
  AiProvider.gemini: ['gemini-2.0-flash', 'gemini-1.5-pro'],
};

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() =>
      _SettingsScreenState();
}

class _SettingsScreenState
    extends ConsumerState<SettingsScreen> {
  late TextEditingController _keyCtrl;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(
        text: ref.read(aiConfigProvider).apiKey);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final config = ref.watch(aiConfigProvider);
    final auth = ref.watch(authProvider);
    final budget = ref.watch(tokenBudgetProvider);
    final used = budget.valueOrNull ?? 0;
    final limit = config.dailyTokenLimit;

    return Container(
      color: c.sidebar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ─── AI ASSISTANT ───────────────────────────
          _sectionHeader('AI ASSISTANT', c),
          const SizedBox(height: 8),

          // Provider dropdown
          _label('Provider', c),
          DropdownButtonFormField<AiProvider>(
            initialValue: config.provider,
            dropdownColor: c.bg,
            decoration: _inputDecor(c),
            style: TextStyle(color: c.fg, fontSize: 13),
            items: AiProvider.values
                .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                          p.name[0].toUpperCase() +
                              p.name.substring(1),
                          style: TextStyle(color: c.fg)),
                    ))
                .toList(),
            onChanged: (p) {
              if (p == null) return;
              final newModel = _models[p]!.first;
              ref.read(aiConfigProvider.notifier).state =
                  config.copyWith(
                      provider: p, model: newModel);
            },
          ),
          const SizedBox(height: 8),

          // Model dropdown
          _label('Model', c),
          DropdownButtonFormField<String>(
            initialValue: (_models[config.provider] ?? [])
                    .contains(config.model)
                ? config.model
                : (_models[config.provider] ?? [''])
                    .first,
            dropdownColor: c.bg,
            decoration: _inputDecor(c),
            style: TextStyle(color: c.fg, fontSize: 13),
            items: (_models[config.provider] ?? [])
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m,
                          style: TextStyle(
                              color: c.fg,
                              fontSize: 12)),
                    ))
                .toList(),
            onChanged: (m) {
              if (m == null) return;
              ref.read(aiConfigProvider.notifier).state =
                  config.copyWith(model: m);
            },
          ),
          const SizedBox(height: 8),

          // API Key
          _label('API Key', c),
          TextFormField(
            controller: _keyCtrl,
            obscureText: _obscure,
            style: TextStyle(
                color: c.fg,
                fontSize: 13,
                fontFamily: 'monospace'),
            decoration: _inputDecor(c).copyWith(
              hintText: 'sk-...',
              hintStyle: TextStyle(color: c.fgMuted),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: c.fgMuted,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (v) {
              ref.read(aiConfigProvider.notifier).state =
                  config.copyWith(apiKey: v);
            },
          ),
          const SizedBox(height: 8),

          // Daily token limit
          _label('Daily Token Limit', c),
          DropdownButtonFormField<int>(
            initialValue: [
              50000,
              100000,
              200000,
              500000,
            ].contains(limit)
                ? limit
                : 100000,
            dropdownColor: c.bg,
            decoration: _inputDecor(c),
            style: TextStyle(color: c.fg, fontSize: 13),
            items: [
              DropdownMenuItem(
                  value: 50000,
                  child: Text('50k',
                      style: TextStyle(color: c.fg))),
              DropdownMenuItem(
                  value: 100000,
                  child: Text('100k',
                      style: TextStyle(color: c.fg))),
              DropdownMenuItem(
                  value: 200000,
                  child: Text('200k',
                      style: TextStyle(color: c.fg))),
              DropdownMenuItem(
                  value: 500000,
                  child: Text('500k',
                      style: TextStyle(color: c.fg))),
            ],
            onChanged: (v) {
              if (v == null) return;
              ref.read(aiConfigProvider.notifier).state =
                  config.copyWith(dailyTokenLimit: v);
            },
          ),
          const SizedBox(height: 8),

          // Token usage bar
          _label('Usage Today', c),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: limit > 0 ? (used / limit).clamp(0, 1) : 0,
              backgroundColor: c.border,
              valueColor:
                  AlwaysStoppedAnimation<Color>(c.accent),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_fmt(used)} / ${_fmt(limit)} tokens',
            style: TextStyle(color: c.fgMuted, fontSize: 11),
          ),

          const SizedBox(height: 24),

          // ─── GITHUB ───────────────────────────────
          _sectionHeader('GITHUB', c),
          const SizedBox(height: 8),

          auth.when(
            loading: () => const Center(
                child: CircularProgressIndicator()),
            error: (e, _) => Text('Auth error: $e',
                style: TextStyle(color: c.fgMuted)),
            data: (token) => token != null
                ? _GitHubConnected(token: token)
                : const _GitHubSignIn(),
          ),

          const SizedBox(height: 24),

          // ─── ABOUT ───────────────────────────────
          _sectionHeader('ABOUT', c),
          const SizedBox(height: 8),
          Text('VibeIDE v1.0.0',
              style: TextStyle(color: c.fgMuted, fontSize: 12)),
          Text('VS Code-style mobile IDE for Android',
              style:
                  TextStyle(color: c.fgMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text, VsCodeColors c) =>
      Text(text,
          style: TextStyle(
              color: c.fgMuted,
              fontSize: 10,
              letterSpacing: 1.2));

  Widget _label(String text, VsCodeColors c) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                color: c.fgMuted, fontSize: 11)),
      );

  InputDecoration _inputDecor(VsCodeColors c) =>
      InputDecoration(
        isDense: true,
        filled: true,
        fillColor: c.bg,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(
              color: Color(0xFF0078D4)),
        ),
      );

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return '$n';
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }
}

class _GitHubConnected extends ConsumerWidget {
  final String token;
  const _GitHubConnected({required this.token});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return Row(
      children: [
        const Icon(Codicons.check,
            color: Color(0xFF73C991), size: 16),
        const SizedBox(width: 8),
        const Text('Connected',
            style: TextStyle(
                color: Color(0xFF73C991),
                fontSize: 13)),
        const Spacer(),
        TextButton(
          onPressed: () =>
              ref.read(authProvider.notifier).signOut(),
          child: Text('Sign out',
              style: TextStyle(color: c.fgMuted)),
        ),
      ],
    );
  }
}

class _GitHubSignIn extends ConsumerWidget {
  const _GitHubSignIn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final deviceState = ref.watch(deviceAuthProvider);

    // Showing device code — user needs to enter it at github.com/login/device
    if (deviceState.deviceCode != null) {
      final code = deviceState.deviceCode!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter this code at github.com/login/device:',
            style: TextStyle(color: c.fgMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          // Big prominent code display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: const Color(0xFF0078D4), width: 2),
            ),
            child: Text(
              code.userCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0078D4),
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                padding:
                    const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Codicons.link, size: 16),
              label: const Text('Open github.com/login/device'),
              onPressed: () => GitHubDeviceAuth()
                  .openVerificationUrl(code.verificationUri),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waiting for you to approve on GitHub...',
                  style:
                      TextStyle(color: c.fgMuted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                ref.read(authProvider.notifier).signOut(),
            child: Text('Cancel',
                style: TextStyle(color: c.fgMuted)),
          ),
        ],
      );
    }

    // Error state
    if (deviceState.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF5A1D1D),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              deviceState.error!,
              style: TextStyle(color: c.fg, fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
          _connectButton(context, ref, c),
        ],
      );
    }

    // Loading (requesting device code)
    if (deviceState.isLoading) {
      return Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: c.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connecting to GitHub...',
              style: TextStyle(color: c.fgMuted),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      );
    }

    // Default: not connected
    return _connectButton(context, ref, c);
  }

  Widget _connectButton(
      BuildContext context, WidgetRef ref, VsCodeColors c) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF238636),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        icon: const Icon(Codicons.link, size: 16),
        label: const Text('Connect GitHub'),
        onPressed: () =>
            ref.read(authProvider.notifier).signIn(),
      ),
    );
  }
}
