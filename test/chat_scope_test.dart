import 'package:docchat/models/chat_message.dart';
import 'package:docchat/providers/app_state.dart';
import 'package:docchat/services/model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an empty chat changes scope in place', () {
    final state = AppState(ModelManager());
    final chatId = state.activeChatId;
    expect(state.isScopeLocked, isFalse);

    expect(state.changeScope('doc-1'), isFalse);
    expect(state.activeChatId, chatId);
    expect(state.activeChat.scopeDocumentId, 'doc-1');
  });

  test('a chat with messages keeps its scope; a new scope starts a new chat', () {
    final state = AppState(ModelManager());
    state.changeScope('doc-1');
    final original = state.activeChat;
    original.messages.add(ChatMessage(id: 'm1', text: 'When does the lease end?', isUser: true, timestamp: DateTime.now()));
    expect(state.isScopeLocked, isTrue);

    // Same scope: nothing happens.
    expect(state.changeScope('doc-1'), isFalse);
    expect(state.activeChat, same(original));

    // Different scope: a new chat about it, the original keeps its scope.
    expect(state.changeScope(null), isTrue);
    expect(state.activeChat, isNot(same(original)));
    expect(state.activeChat.scopeDocumentId, isNull);
    expect(state.activeChat.messages, isEmpty);
    expect(original.scopeDocumentId, 'doc-1');
  });
}
