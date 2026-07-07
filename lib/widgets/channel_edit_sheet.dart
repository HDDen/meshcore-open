import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/channel.dart';
import '../services/app_settings_service.dart';
import 'channel_widget_color_picker.dart';
import 'mesh_ui.dart';
import 'quick_answers_selection_dialog.dart';

void showChannelEditSheet(
  BuildContext context,
  MeshCoreConnector connector,
  Channel channel,
) {
  final appSettingsService = Provider.of<AppSettingsService>(
    context,
    listen: false,
  );
  final nameController = TextEditingController(text: channel.name);
  final pskController = TextEditingController(text: channel.pskHex);
  bool mcmpEnabled = connector.isChannelMcmpEnabled(channel.index);
  int selectedMcmpVersion = connector.channelMcmpVersion(channel.index);
  bool mcmpUseSign = connector.channelMcmpUseSign(channel.index);
  bool smazEnabled = connector.isChannelSmazEnabled(channel.index);
  bool cyr2latEnabled = connector.isChannelCyr2LatEnabled(channel.index);
  bool sendingDelayEnabled = connector.isChannelSendingDelayEnabled(
    channel.index,
  );
  List<String> selectedQuickAnswerIds = connector.getChannelQuickAnswerIds(
    channel.index,
  );
  String? selectedCyr2LatProfileId = connector.getChannelCyr2LatProfileId(
    channel.index,
  );
  int? selectedWidgetColor = connector.getChannelWidgetColor(channel.index);
  int? selectedWidgetTextColor = connector.getChannelWidgetTextColor(
    channel.index,
  );

  showMeshSheet(
    context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Column(
          children: [
            BottomSheetHeader(
              title: sheetContext.l10n.channels_editChannelTitle(
                channel.index,
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: sheetContext.l10n.channels_channelName,
                      border: const OutlineInputBorder(),
                    ),
                    maxLength: 31,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pskController,
                    decoration: InputDecoration(
                      labelText: sheetContext.l10n.channels_pskHex,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.casino),
                        tooltip: sheetContext.l10n.channels_generateRandomPsk,
                        onPressed: () {
                          final random = Random.secure();
                          final bytes = Uint8List(16);
                          for (int i = 0; i < 16; i++) {
                            bytes[i] = random.nextInt(256);
                          }
                          pskController.text = Channel.formatPskHex(bytes);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sheetContext.l10n.channels_mcmpCompression),
                    subtitle: Text(
                      sheetContext.l10n.channels_mcmpCompressionDescription,
                    ),
                    value: mcmpEnabled,
                    onChanged: (value) => setSheetState(() {
                      mcmpEnabled = value;
                      if (mcmpEnabled) {
                        smazEnabled = false;
                        cyr2latEnabled = false;
                      }
                    }),
                  ),
                  if (mcmpEnabled) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedMcmpVersion,
                        decoration: InputDecoration(
                          labelText: sheetContext.l10n.settings_mcmp_version,
                          border: const OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 2,
                            child: Text('v2 (legacy)'),
                          ),
                          DropdownMenuItem(value: 3, child: Text('v3')),
                        ],
                        onChanged: (value) => setSheetState(() {
                          selectedMcmpVersion = value == 3 ? 3 : 2;
                        }),
                      ),
                    ),
                    if (selectedMcmpVersion == 3)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                        child: DropdownButtonFormField<bool>(
                          initialValue: mcmpUseSign,
                          decoration: InputDecoration(
                            labelText: sheetContext.l10n.settings_mcmp_useSign,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: true,
                              child: Text(
                                sheetContext.l10n.settings_mcmp_signed,
                              ),
                            ),
                            DropdownMenuItem(
                              value: false,
                              child: Text(
                                sheetContext.l10n.settings_mcmp_noSign,
                              ),
                            ),
                          ],
                          onChanged: (value) => setSheetState(() {
                            mcmpUseSign = value ?? true;
                          }),
                        ),
                      ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sheetContext.l10n.channels_smazCompression),
                    value: smazEnabled,
                    onChanged: (value) => setSheetState(() {
                      smazEnabled = value;
                      if (smazEnabled) {
                        mcmpEnabled = false;
                        cyr2latEnabled = false;
                      }
                    }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      sheetContext.l10n.channels_cyr2latCompression,
                    ),
                    subtitle: Text(
                      sheetContext.l10n.channels_cyr2latCompressionDscr,
                    ),
                    value: cyr2latEnabled,
                    onChanged: (value) => setSheetState(() {
                      cyr2latEnabled = value;
                      if (cyr2latEnabled) {
                        mcmpEnabled = false;
                        smazEnabled = false;
                      }
                    }),
                  ),
                  if (cyr2latEnabled) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedCyr2LatProfileId,
                        decoration: InputDecoration(
                          labelText: sheetContext
                              .l10n
                              .channels_cyr2latSettingsSubheading,
                          border: const OutlineInputBorder(),
                        ),
                        items: appSettingsService.settings.cyr2latProfiles
                            .map((profile) {
                              return DropdownMenuItem(
                                value: profile.id,
                                child: Text(profile.name),
                              );
                            })
                            .toList(),
                        onChanged: (value) => setSheetState(() {
                          selectedCyr2LatProfileId = value;
                        }),
                      ),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sheetContext.l10n.settings_useSendingDelay),
                    value: sendingDelayEnabled,
                    onChanged: (value) => setSheetState(() {
                      sendingDelayEnabled = value;
                    }),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.quickreply_outlined),
                    title: Text(sheetContext.l10n.settings_quickAnswersTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final selection = await showQuickAnswersSelectionDialog(
                        sheetContext,
                        settingsService: appSettingsService,
                        selectedAnswerIds: selectedQuickAnswerIds,
                      );
                      if (selection == null) return;
                      setSheetState(() {
                        selectedQuickAnswerIds = selection;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sheetContext.l10n.channels_changeWidgetColor),
                    trailing: ChannelWidgetColorValue(
                      colorValue: selectedWidgetColor,
                    ),
                    onTap: () async {
                      final selection = await showChannelWidgetColorPicker(
                        sheetContext,
                        selectedBackgroundColorValue: selectedWidgetColor,
                        selectedTextColorValue: selectedWidgetTextColor,
                      );
                      if (selection == null) return;
                      setSheetState(() {
                        selectedWidgetColor = selection.backgroundColorValue;
                        selectedWidgetTextColor = selection.textColorValue;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: Text(sheetContext.l10n.common_cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final pskHex = pskController.text.trim();

                        Uint8List psk;
                        try {
                          psk = Channel.parsePskHex(pskHex);
                        } on FormatException {
                          showDismissibleSnackBar(
                            sheetContext,
                            content: Text(
                              sheetContext.l10n.channels_pskMustBe32Hex,
                            ),
                          );
                          return;
                        }

                        Navigator.pop(sheetContext);
                        try {
                          await connector.setChannel(channel.index, name, psk);
                          await connector.setChannelMcmpEnabled(
                            channel.index,
                            mcmpEnabled,
                          );
                          await connector.setChannelMcmpVersion(
                            channel.index,
                            selectedMcmpVersion,
                          );
                          await connector.setChannelMcmpUseSign(
                            channel.index,
                            mcmpUseSign,
                          );
                          await connector.setChannelSmazEnabled(
                            channel.index,
                            smazEnabled,
                          );
                          await connector.setChannelCyr2LatEnabled(
                            channel.index,
                            cyr2latEnabled,
                          );
                          await connector.setChannelCyr2LatProfileId(
                            channel.index,
                            selectedCyr2LatProfileId,
                          );
                          await connector.setChannelSendingDelayEnabled(
                            channel.index,
                            sendingDelayEnabled,
                          );
                          await connector.setChannelQuickAnswerIds(
                            channel.index,
                            selectedQuickAnswerIds,
                          );
                          await connector.setChannelWidgetColor(
                            channel.index,
                            selectedWidgetColor,
                          );
                          await connector.setChannelWidgetTextColor(
                            channel.index,
                            selectedWidgetTextColor,
                          );
                          if (!context.mounted) return;
                          showDismissibleSnackBar(
                            context,
                            content: Text(
                              context.l10n.channels_channelUpdated(name),
                            ),
                          );
                        } catch (e, st) {
                          debugPrint(st.toString());
                          if (!context.mounted) return;
                          showDismissibleSnackBar(
                            context,
                            content: Text(
                              context.l10n.channels_channelUpdateFailed('$e'),
                            ),
                          );
                        }
                      },
                      child: Text(sheetContext.l10n.common_save),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
