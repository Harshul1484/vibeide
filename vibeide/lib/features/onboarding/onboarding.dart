import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/shared/codicons.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';

const _onboardedKey = 'onboarded_v1';
const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Whether the user has completed first-run onboarding.
final onboardedProvider = FutureProvider<bool>((ref) async {
  final v = await _storage.read(key: _onboardedKey);
  return v == 'true';
});

Future<void> _markOnboarded(WidgetRef ref) async {
  await _storage.write(key: _onboardedKey, value: 'true');
  ref.invalidate(onboardedProvider);
}

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide(this.icon, this.title, this.body);
}

const _slides = <_Slide>[
  _Slide(
    Codicons.symbolFile,
    'Welcome to VibeIDE',
    'A full developer sandbox on your phone — clone repos, edit code, run '
        'git, Node, Python and more, all in an isolated Linux environment.',
  ),
  _Slide(
    Codicons.cloudDownload,
    'Clone & edit any repo',
    'Sign in with GitHub, clone a repository, and edit it with a VS Code-style '
        'editor — file tree, tabs, syntax highlighting, terminal.',
  ),
  _Slide(
    Codicons.robot,
    'Vibe-code with AI',
    'Turn on Agent mode and ask the AI to make changes. It edits the files '
        'directly, then you review the diff and open a pull request.',
  ),
  _Slide(
    Codicons.library,
    'Real tools, installed on demand',
    'Add languages and tools (Node, Python, Go, Rust, Prettier, ESLint…) from '
        'the Extensions panel. They install into your sandbox and just work.',
  ),
];

/// First-run onboarding: intro slides, then a one-time sandbox setup step.
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _setupRunning = false;
  bool _setupDone = false;
  String? _setupError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSetup() async {
    setState(() {
      _setupRunning = true;
      _setupError = null;
    });
    try {
      await ref.read(sandboxProvider.notifier).extractOnly();
      setState(() {
        _setupRunning = false;
        _setupDone = true;
      });
    } catch (e) {
      setState(() {
        _setupRunning = false;
        _setupError = e.toString();
      });
    }
  }

  Future<void> _finish() async {
    await _markOnboarded(ref);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final isLast = _page == _slides.length; // last index = setup page

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: Text('Skip', style: TextStyle(color: c.fgMuted)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _slides.length + 1, // +1 = setup page
                itemBuilder: (context, i) {
                  if (i < _slides.length) {
                    return _SlideView(slide: _slides[i], colors: c);
                  }
                  return _SetupView(
                    colors: c,
                    running: _setupRunning,
                    done: _setupDone,
                    error: _setupError,
                    onRun: _runSetup,
                  );
                },
              ),
            ),
            // Dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length + 1, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active ? c.accent : c.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            // Action button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _setupRunning
                      ? null
                      : () {
                          if (!isLast) {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          } else if (_setupDone || _setupError != null) {
                            _finish();
                          } else {
                            _runSetup();
                          }
                        },
                  child: Text(
                    _setupRunning
                        ? 'Setting up…'
                        : !isLast
                            ? 'Next'
                            : _setupDone
                                ? 'Start coding'
                                : _setupError != null
                                    ? 'Continue anyway'
                                    : 'Set up sandbox',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  final VsCodeColors colors;
  const _SlideView({required this.slide, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(slide.icon, size: 48, color: c.accent),
          ),
          const SizedBox(height: 32),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.fg, fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.fgMuted, fontSize: 14, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _SetupView extends StatelessWidget {
  final VsCodeColors colors;
  final bool running;
  final bool done;
  final String? error;
  final VoidCallback onRun;
  const _SetupView({
    required this.colors,
    required this.running,
    required this.done,
    required this.error,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: (done ? const Color(0xFF3FB950) : c.accent)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: running
                ? Center(
                    child: CircularProgressIndicator(color: c.accent),
                  )
                : Icon(
                    done ? Codicons.check : Codicons.terminal,
                    size: 48,
                    color: done ? const Color(0xFF3FB950) : c.accent,
                  ),
          ),
          const SizedBox(height: 32),
          Text(
            done
                ? 'You\'re all set'
                : running
                    ? 'Setting up your sandbox'
                    : 'One-time setup',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.fg, fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Text(
            error != null
                ? 'Setup hit a snag, but you can continue — it will retry when '
                    'you open a project.\n\n$error'
                : done
                    ? 'Your Alpine Linux sandbox is ready. Clone a repo and '
                        'start building.'
                    : running
                        ? 'Extracting the Linux environment into private '
                            'storage. This happens once and takes a few seconds.'
                        : 'VibeIDE bundles a full Linux sandbox. Tap below to '
                            'extract it now so your first clone is instant.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: error != null ? const Color(0xFFF85149) : c.fgMuted,
                fontSize: 13,
                height: 1.45),
          ),
        ],
      ),
    );
  }
}
