import 'dart:ui';

import 'mcoa_theme_options.dart';

// Compiled preset from assets/themes/meshcore-liam-dark/meshcore-liam-dark.jsonl.
// The asset/preset equality test keeps the synchronous startup palette in sync.
const liamDarkThemeId = 'preset:meshcore_liam_dark';
const liamDarkThemeName = 'MeshCore Liam (dark)';
const liamDarkBackground = Color(0xFF111419);
const liamDarkAccent = Color(0xFFFFFFFF);
const liamDarkMcoa = McoaThemeOptions(
  colors: {
    'status_bar': Color(0xFF202938),
    'header': Color(0xFF202938),
    'composer_action_icon': Color(0xFFFFFFFF),
    'composer_input_border': Color(0xFF2F3035),
    'composer_input_background': Color(0xFF2F3035),
    'composer_input_text': Color(0xFFFFFFFF),
    'composer_send_background': Color(0xFF2F3035),
    'composer_send_icon': Color(0xFFC5C5CF),
    'attention': Color(0xFFF59E0B),
    'warning': Color(0xFFEF4444),
    'incoming_border': Color(0xFFE0E0E0),
    'incoming_background': Color(0xFFE0E0E0),
    'incoming_text': Color(0xFF000000),
    'incoming_badges': Color(0xFFB4B4B4),
    'incoming_quote_background': Color(0xFFC1C1C1),
    'incoming_quote_text': Color(0xFF000000),
    'incoming_mention_border': Color(0xFFFFFFFF),
    'incoming_mention_background': Color(0xFFFFFFFF),
    'incoming_mention_text': Color(0xFF000000),
    'incoming_link': Color(0xFF204BD0),
    'incoming_metadata_background': Color(0x6632383B),
    'outgoing_border': Color(0xFF1449B2),
    'outgoing_background': Color(0xFF1449B2),
    'outgoing_badges': Color(0xFFB4B4B4),
    'outgoing_quote_background': Color(0x3B000000),
    'outgoing_quote_text': Color(0xFFFFFFFF),
    'outgoing_mention_border': Color(0xFFFFFFFF),
    'outgoing_mention_background': Color(0xFFFFFFFF),
    'outgoing_mention_text': Color(0xFF1B45A1),
    'outgoing_link': Color(0xFFEA8408),
    'outgoing_metadata_background': Color(0x6632383B),
    'chats_border': Color(0xFF1E2227),
    'chats_background': Color(0xFF1E2227),
    'chats_index_border': Color(0x4D69CBF7),
    'chats_search_border': Color(0xFF32353A),
    'chats_search_background': Color(0x00000000),
    'chats_search_contacts_background': Color(0x00000000),
    'chats_search_text': Color(0xFFFFFFFF),
    'chats_search_hint_icons': Color(0xFFC6C9D0),
  },
  incomingMetadataTopPadding: 4,
  outgoingMetadataTopPadding: 4,
  separateIncomingMetadata: true,
  separateOutgoingMetadata: true,
  incomingMetadataSpacing: 2,
  incomingSenderNameBrightness: -29,
  uiScalePercent: 100,
  senderNameScalePercent: 130,
  simplifiedMentions: false,
  showChannelIndices: false,
);
