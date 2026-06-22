/// How a tool is installed into the Alpine sandbox.
///
/// All installs are GLOBAL: apk/pip/npm-global write into the shared Alpine
/// rootfs (/usr/...), so a tool installed once is available in every project
/// and persists across sessions — same as VS Code's global extensions.
enum InstallVia { apk, npm, pip }

/// A curated installable developer tool ("extension").
class DevTool {
  final String id; // unique key, e.g. 'nodejs'
  final String name; // display name, e.g. 'Node.js'
  final String description;
  final String category; // 'Runtimes' | 'Formatters & Linters' | 'Utilities'
  final InstallVia via;
  final String package; // package name(s) passed to the installer
  final String checkCmd; // shell command whose exit 0 means "installed"

  /// URL to the tool's official logo (PNG). Shown in the Extensions tile,
  /// falls back to a colored category glyph if it fails to load.
  final String? iconUrl;

  /// Formatter: command template to format a file in place. {file} is
  /// substituted with the absolute path. null if not a formatter.
  final String? formatCmd;

  /// File extensions this formatter applies to (lowercase, with dot).
  final List<String> formatExtensions;

  /// Linter: command template to lint a file. {file} -> absolute path.
  /// The command should print diagnostics to stdout/stderr. null if not a linter.
  final String? lintCmd;

  /// File extensions this linter applies to.
  final List<String> lintExtensions;

  /// Runtime: command template to RUN a file. {file} -> absolute path.
  /// e.g. 'node "{file}"'. null if this tool can't run files directly.
  final String? runCmd;

  /// File extensions this runtime can execute.
  final List<String> runExtensions;

  const DevTool({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.via,
    required this.package,
    required this.checkCmd,
    this.iconUrl,
    this.formatCmd,
    this.formatExtensions = const [],
    this.lintCmd,
    this.lintExtensions = const [],
    this.runCmd,
    this.runExtensions = const [],
  });
}

/// The curated list shown in the Extensions panel.
const devToolCatalog = <DevTool>[
  // ── Runtimes (apk) ──
  DevTool(
    id: 'nodejs',
    name: 'Node.js',
    description: 'JavaScript runtime + npm. Run .js files.',
    category: 'Runtimes',
    via: InstallVia.apk,
    package: 'nodejs npm',
    checkCmd: 'command -v node',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/nodejs/nodejs-original.svg',
    runCmd: 'node "{file}"',
    runExtensions: ['.js', '.cjs', '.mjs'],
  ),
  DevTool(
    id: 'python3',
    name: 'Python 3',
    description: 'Python interpreter + pip. Run .py files.',
    category: 'Runtimes',
    via: InstallVia.apk,
    package: 'python3 py3-pip',
    checkCmd: 'command -v python3',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/python/python-original.svg',
    runCmd: 'python3 "{file}"',
    runExtensions: ['.py'],
  ),
  DevTool(
    id: 'go',
    name: 'Go',
    description: 'Go compiler & tooling. Run .go files.',
    category: 'Runtimes',
    via: InstallVia.apk,
    package: 'go',
    checkCmd: 'command -v go',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/go/go-original-wordmark.svg',
    runCmd: 'go run "{file}"',
    runExtensions: ['.go'],
  ),
  DevTool(
    id: 'php',
    name: 'PHP',
    description: 'PHP interpreter. Run .php files.',
    category: 'Runtimes',
    via: InstallVia.apk,
    package: 'php',
    checkCmd: 'command -v php',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/php/php-original.svg',
    runCmd: 'php "{file}"',
    runExtensions: ['.php'],
  ),
  DevTool(
    id: 'ruby',
    name: 'Ruby',
    description: 'Ruby interpreter. Run .rb files.',
    category: 'Runtimes',
    via: InstallVia.apk,
    package: 'ruby',
    checkCmd: 'command -v ruby',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/ruby/ruby-original.svg',
    runCmd: 'ruby "{file}"',
    runExtensions: ['.rb'],
  ),
  DevTool(
    id: 'bash',
    name: 'Bash',
    description: 'GNU Bash shell. Run .sh scripts.',
    category: 'Runtimes',
    via: InstallVia.apk,
    package: 'bash',
    checkCmd: 'command -v bash',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/bash/bash-original.svg',
    runCmd: 'bash "{file}"',
    runExtensions: ['.sh', '.bash'],
  ),
  DevTool(
    id: 'lua',
    name: 'Lua',
    description: 'Lightweight scripting language. Run .lua files.',
    category: 'Runtimes',
    via: InstallVia.apk,
    package: 'lua5.4',
    checkCmd: 'command -v lua5.4',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/lua/lua-original.svg',
    runCmd: 'lua5.4 "{file}"',
    runExtensions: ['.lua'],
  ),

  // ── Languages (compiled / SDK toolchains) ──
  DevTool(
    id: 'dart',
    name: 'Dart',
    description: 'Dart SDK. Run/analyze/test .dart files.',
    category: 'Languages',
    via: InstallVia.apk,
    package: 'dart',
    checkCmd: 'command -v dart',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/dart/dart-original.svg',
    runCmd: 'dart run "{file}"',
    runExtensions: ['.dart'],
  ),
  DevTool(
    id: 'flutter',
    name: 'Flutter',
    description: 'Flutter SDK — create, pub, analyze, test, build web. '
        '(Native APK builds need a device SDK, not available in-sandbox.)',
    category: 'Languages',
    via: InstallVia.apk,
    package: 'flutter',
    checkCmd: 'command -v flutter',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/flutter/flutter-original.svg',
  ),
  DevTool(
    id: 'rust',
    name: 'Rust',
    description: 'Rust compiler + Cargo. Compile & run .rs files.',
    category: 'Languages',
    via: InstallVia.apk,
    package: 'rust cargo',
    checkCmd: 'command -v rustc',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/rust/rust-original.svg',
    // Compile then run; output binary alongside the source.
    runCmd: 'rustc "{file}" -o /tmp/rustout && /tmp/rustout',
    runExtensions: ['.rs'],
  ),
  DevTool(
    id: 'openjdk',
    name: 'Java (OpenJDK)',
    description: 'OpenJDK 17 — compile & run Java. Large download.',
    category: 'Languages',
    via: InstallVia.apk,
    package: 'openjdk17',
    checkCmd: 'command -v java',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/java/java-original.svg',
    // Compile to /tmp and run by class name.
    runCmd: 'javac -d /tmp "{file}" && java -cp /tmp "\$(basename "{file}" .java)"',
    runExtensions: ['.java'],
  ),
  DevTool(
    id: 'kotlin',
    name: 'Kotlin',
    description: 'Kotlin compiler (needs Java). Compile & run .kt files.',
    category: 'Languages',
    via: InstallVia.apk,
    package: 'kotlin',
    checkCmd: 'command -v kotlinc',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/kotlin/kotlin-original.svg',
    runCmd: 'kotlinc "{file}" -include-runtime -d /tmp/kt.jar && java -jar /tmp/kt.jar',
    runExtensions: ['.kt', '.kts'],
  ),
  DevTool(
    id: 'gcc',
    name: 'C (GCC)',
    description: 'GNU C compiler + make. Compile & run .c files.',
    category: 'Languages',
    via: InstallVia.apk,
    package: 'gcc musl-dev make',
    checkCmd: 'command -v gcc',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/c/c-original.svg',
    runCmd: 'gcc "{file}" -o /tmp/cout && /tmp/cout',
    runExtensions: ['.c'],
  ),
  DevTool(
    id: 'gpp',
    name: 'C++ (g++)',
    description: 'GNU C++ compiler. Compile & run .cpp files.',
    category: 'Languages',
    via: InstallVia.apk,
    package: 'g++ musl-dev make',
    checkCmd: 'command -v g++',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/cplusplus/cplusplus-original.svg',
    runCmd: 'g++ "{file}" -o /tmp/cppout && /tmp/cppout',
    runExtensions: ['.cpp', '.cc', '.cxx'],
  ),
  DevTool(
    id: 'perl',
    name: 'Perl',
    description: 'Perl interpreter. Run .pl files.',
    category: 'Languages',
    via: InstallVia.apk,
    package: 'perl',
    checkCmd: 'command -v perl',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/perl/perl-original.svg',
    runCmd: 'perl "{file}"',
    runExtensions: ['.pl'],
  ),

  // ── Formatters & Linters ──
  DevTool(
    id: 'prettier',
    name: 'Prettier',
    description: 'Opinionated code formatter (JS/TS/CSS/HTML/JSON/MD).',
    category: 'Formatters & Linters',
    via: InstallVia.npm,
    package: 'prettier',
    checkCmd: 'command -v prettier',
    iconUrl: 'https://cdn.jsdelivr.net/npm/simple-icons@13/icons/prettier.svg',
    formatCmd: 'prettier --write "{file}"',
    formatExtensions: [
      '.js', '.ts', '.jsx', '.tsx', '.css', '.scss',
      '.html', '.json', '.md', '.yaml', '.yml',
    ],
  ),
  DevTool(
    id: 'eslint',
    name: 'ESLint',
    description: 'Pluggable JavaScript / TypeScript linter.',
    category: 'Formatters & Linters',
    via: InstallVia.npm,
    package: 'eslint',
    checkCmd: 'command -v eslint',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/eslint/eslint-original.svg',
    lintCmd: 'eslint "{file}"',
    lintExtensions: ['.js', '.jsx', '.ts', '.tsx'],
  ),
  DevTool(
    id: 'typescript',
    name: 'TypeScript',
    description: 'TypeScript compiler (tsc). Type-check .ts files.',
    category: 'Formatters & Linters',
    via: InstallVia.npm,
    package: 'typescript',
    checkCmd: 'command -v tsc',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/typescript/typescript-original.svg',
    lintCmd: 'tsc --noEmit "{file}"',
    lintExtensions: ['.ts', '.tsx'],
  ),
  DevTool(
    id: 'black',
    name: 'Black',
    description: 'Uncompromising Python code formatter.',
    category: 'Formatters & Linters',
    via: InstallVia.pip,
    package: 'black',
    checkCmd: 'command -v black',
    iconUrl: 'https://cdn.jsdelivr.net/npm/simple-icons@13/icons/python.svg',
    formatCmd: 'black "{file}"',
    formatExtensions: ['.py'],
  ),
  DevTool(
    id: 'ruff',
    name: 'Ruff',
    description: 'Extremely fast Python linter & formatter.',
    category: 'Formatters & Linters',
    via: InstallVia.pip,
    package: 'ruff',
    checkCmd: 'command -v ruff',
    iconUrl: 'https://cdn.jsdelivr.net/npm/simple-icons@13/icons/ruff.svg',
    formatCmd: 'ruff format "{file}"',
    formatExtensions: ['.py'],
    lintCmd: 'ruff check "{file}"',
    lintExtensions: ['.py'],
  ),
  DevTool(
    id: 'flake8',
    name: 'Flake8',
    description: 'Python style guide enforcement.',
    category: 'Formatters & Linters',
    via: InstallVia.pip,
    package: 'flake8',
    checkCmd: 'command -v flake8',
    lintCmd: 'flake8 "{file}"',
    lintExtensions: ['.py'],
  ),
  DevTool(
    id: 'shellcheck',
    name: 'ShellCheck',
    description: 'Static analysis for shell scripts.',
    category: 'Formatters & Linters',
    via: InstallVia.apk,
    package: 'shellcheck',
    checkCmd: 'command -v shellcheck',
    iconUrl: 'https://cdn.jsdelivr.net/npm/simple-icons@13/icons/gnubash.svg',
    lintCmd: 'shellcheck "{file}"',
    lintExtensions: ['.sh', '.bash'],
  ),

  // ── Utilities (apk) ──
  DevTool(
    id: 'curl',
    name: 'curl',
    description: 'Transfer data over HTTP and more.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'curl',
    checkCmd: 'command -v curl',
    iconUrl: 'https://cdn.jsdelivr.net/npm/simple-icons@13/icons/curl.svg',
  ),
  DevTool(
    id: 'jq',
    name: 'jq',
    description: 'Command-line JSON processor.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'jq',
    checkCmd: 'command -v jq',
  ),
  DevTool(
    id: 'tree',
    name: 'tree',
    description: 'Recursive directory listing as a tree.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'tree',
    checkCmd: 'command -v tree',
  ),
  DevTool(
    id: 'htop',
    name: 'htop',
    description: 'Interactive process viewer.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'htop',
    checkCmd: 'command -v htop',
  ),
  DevTool(
    id: 'ripgrep',
    name: 'ripgrep',
    description: 'Ultra-fast recursive search (rg).',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'ripgrep',
    checkCmd: 'command -v rg',
    iconUrl: 'https://cdn.jsdelivr.net/npm/simple-icons@13/icons/ripgrep.svg',
  ),
  DevTool(
    id: 'fzf',
    name: 'fzf',
    description: 'Command-line fuzzy finder.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'fzf',
    checkCmd: 'command -v fzf',
  ),
  DevTool(
    id: 'vim',
    name: 'Vim',
    description: 'Vi IMproved terminal text editor.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'vim',
    checkCmd: 'command -v vim',
    iconUrl: 'https://cdn.jsdelivr.net/gh/devicons/devicon/icons/vim/vim-original.svg',
  ),
  DevTool(
    id: 'nano',
    name: 'nano',
    description: 'Simple terminal text editor.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'nano',
    checkCmd: 'command -v nano',
  ),
  DevTool(
    id: 'make',
    name: 'make',
    description: 'Build automation tool.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'make',
    checkCmd: 'command -v make',
  ),
  DevTool(
    id: 'openssh',
    name: 'OpenSSH',
    description: 'SSH client for remote access.',
    category: 'Utilities',
    via: InstallVia.apk,
    package: 'openssh-client',
    checkCmd: 'command -v ssh',
    iconUrl: 'https://cdn.jsdelivr.net/npm/simple-icons@13/icons/openssh.svg',
  ),
];

/// Returns the lowercase file extension (with dot) for a path, or '' if none.
String fileExt(String path) =>
    path.contains('.') ? '.${path.split('.').last.toLowerCase()}' : '';

/// The installed formatter for [path], or null.
DevTool? formatterFor(String path, Set<String> installedIds) {
  final ext = fileExt(path);
  if (ext.isEmpty) return null;
  for (final t in devToolCatalog) {
    if (t.formatCmd != null &&
        t.formatExtensions.contains(ext) &&
        installedIds.contains(t.id)) {
      return t;
    }
  }
  return null;
}

/// The installed linter for [path], or null.
DevTool? linterFor(String path, Set<String> installedIds) {
  final ext = fileExt(path);
  if (ext.isEmpty) return null;
  for (final t in devToolCatalog) {
    if (t.lintCmd != null &&
        t.lintExtensions.contains(ext) &&
        installedIds.contains(t.id)) {
      return t;
    }
  }
  return null;
}

/// The installed runtime for [path], or null.
DevTool? runtimeFor(String path, Set<String> installedIds) {
  final ext = fileExt(path);
  if (ext.isEmpty) return null;
  for (final t in devToolCatalog) {
    if (t.runCmd != null &&
        t.runExtensions.contains(ext) &&
        installedIds.contains(t.id)) {
      return t;
    }
  }
  return null;
}
