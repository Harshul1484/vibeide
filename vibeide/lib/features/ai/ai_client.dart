import 'dart:convert';
import 'package:http/http.dart' as http;

enum AiProvider { claude, openai, gemini }

class AiConfig {
  final AiProvider provider;
  final String apiKey;
  final String model;
  final int dailyTokenLimit;

  const AiConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.dailyTokenLimit = 100000,
  });

  AiConfig copyWith({
    AiProvider? provider,
    String? apiKey,
    String? model,
    int? dailyTokenLimit,
  }) =>
      AiConfig(
        provider: provider ?? this.provider,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        dailyTokenLimit: dailyTokenLimit ?? this.dailyTokenLimit,
      );
}

class AiClient {
  final AiConfig config;
  AiClient(this.config);

  static int estimateTokens(String text) => (text.length / 4).ceil();

  static String buildCommitPrompt(String diff) =>
      'Write a concise conventional commit message (type: description) for this diff. '
      'Return only the commit message, no explanation, no quotes.\n\nDiff:\n$diff';

  static String buildPrPrompt(String diff) =>
      'Write a GitHub PR title and description for this diff. '
      'Return JSON with keys "title" (string, under 70 chars) and '
      '"body" (markdown string with ## Summary and ## Test plan sections).\n\nDiff:\n$diff';

  Stream<String> chat(List<Map<String, String>> messages) {
    return switch (config.provider) {
      AiProvider.claude => _claudeStream(messages),
      AiProvider.openai => _openaiStream(messages),
      AiProvider.gemini => _geminiStream(messages),
    };
  }

  Stream<String> _claudeStream(
      List<Map<String, String>> messages) async* {
    final req = http.Request(
        'POST',
        Uri.parse(
            'https://api.anthropic.com/v1/messages'));
    req.headers.addAll({
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    });
    req.body = jsonEncode({
      'model': config.model,
      'max_tokens': 4096,
      'stream': true,
      'messages': messages,
    });

    final client = http.Client();
    try {
      final res = await client.send(req);
      await for (final chunk
          in res.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') return;
          try {
            final j = jsonDecode(data) as Map<String, dynamic>;
            if (j['type'] == 'content_block_delta') {
              final delta =
                  j['delta'] as Map<String, dynamic>;
              if (delta['type'] == 'text_delta') {
                yield delta['text'] as String? ?? '';
              }
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  Stream<String> _openaiStream(
      List<Map<String, String>> messages) async* {
    final req = http.Request(
        'POST',
        Uri.parse(
            'https://api.openai.com/v1/chat/completions'));
    req.headers.addAll({
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
    });
    req.body = jsonEncode({
      'model': config.model,
      'stream': true,
      'messages': messages,
    });

    final client = http.Client();
    try {
      final res = await client.send(req);
      await for (final chunk
          in res.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') return;
          try {
            final j = jsonDecode(data) as Map<String, dynamic>;
            final choices = j['choices'] as List<dynamic>;
            if (choices.isEmpty) continue;
            final delta =
                choices[0]['delta'] as Map<String, dynamic>;
            final content = delta['content'] as String?;
            if (content != null) yield content;
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  Stream<String> _geminiStream(
      List<Map<String, String>> messages) async* {
    // Gemini uses the last user message for simplicity
    final lastUserMsg = messages
        .lastWhere((m) => m['role'] == 'user',
            orElse: () => messages.last)['content']!;

    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta'
        '/models/${config.model}:streamGenerateContent'
        '?key=${config.apiKey}&alt=sse');
    final req = http.Request('POST', url);
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': lastUserMsg}
          ]
        }
      ]
    });

    final client = http.Client();
    try {
      final res = await client.send(req);
      await for (final chunk
          in res.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          try {
            final j = jsonDecode(data) as Map<String, dynamic>;
            final candidates =
                j['candidates'] as List<dynamic>?;
            if (candidates == null || candidates.isEmpty) continue;
            final parts = (candidates[0]['content']
                    as Map<String, dynamic>)['parts']
                as List<dynamic>;
            for (final p in parts) {
              final text = (p as Map<String, dynamic>)['text']
                  as String?;
              if (text != null) yield text;
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  Future<String> generateCommitMessage(String diff) async {
    final sb = StringBuffer();
    await for (final chunk in chat([
      {'role': 'user', 'content': buildCommitPrompt(diff)}
    ])) {
      sb.write(chunk);
    }
    return sb.toString().trim();
  }

  Future<Map<String, String>> generatePrDescription(
      String diff) async {
    final sb = StringBuffer();
    await for (final chunk in chat([
      {'role': 'user', 'content': buildPrPrompt(diff)}
    ])) {
      sb.write(chunk);
    }
    try {
      final j =
          jsonDecode(sb.toString()) as Map<String, dynamic>;
      return {
        'title': j['title'] as String,
        'body': j['body'] as String,
      };
    } catch (_) {
      return {
        'title': 'Update code',
        'body': sb.toString(),
      };
    }
  }
}
