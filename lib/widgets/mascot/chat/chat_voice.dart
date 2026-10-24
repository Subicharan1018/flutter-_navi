import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where voice input plugs into the chat. The mic button shows only when
/// [available]; a speech-to-text implementation can replace [NoVoiceInput] by
/// overriding [chatVoiceInputProvider].
abstract class ChatVoiceInput {
  const ChatVoiceInput();

  /// Whether this device can listen right now (permission, engine present).
  bool get available;

  /// Listens until the user stops talking and returns what was said, or null
  /// when nothing was heard or they cancelled.
  Future<String?> listen();
}

/// Text only, for now.
class NoVoiceInput extends ChatVoiceInput {
  const NoVoiceInput();

  @override
  bool get available => false;

  @override
  Future<String?> listen() async => null;
}

final chatVoiceInputProvider = Provider<ChatVoiceInput>((ref) => const NoVoiceInput());
