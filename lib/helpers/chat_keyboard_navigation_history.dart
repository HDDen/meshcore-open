import '../models/channel.dart';
import '../models/contact.dart';

enum ChatKeyboardNavigationTargetType { channel, contact }

class ChatKeyboardNavigationTarget {
  final ChatKeyboardNavigationTargetType type;
  final Channel? channel;
  final Contact? contact;

  const ChatKeyboardNavigationTarget._({
    required this.type,
    this.channel,
    this.contact,
  });

  const ChatKeyboardNavigationTarget.channel(Channel channel)
    : this._(type: ChatKeyboardNavigationTargetType.channel, channel: channel);

  const ChatKeyboardNavigationTarget.contact(Contact contact)
    : this._(type: ChatKeyboardNavigationTargetType.contact, contact: contact);
}

class ChatKeyboardNavigationHistory {
  static ChatKeyboardNavigationTarget? _lastTarget;

  static ChatKeyboardNavigationTarget? get lastTarget => _lastTarget;

  static void rememberChannel(Channel channel) {
    _lastTarget = ChatKeyboardNavigationTarget.channel(channel);
  }

  static void rememberContact(Contact contact) {
    _lastTarget = ChatKeyboardNavigationTarget.contact(contact);
  }
}
