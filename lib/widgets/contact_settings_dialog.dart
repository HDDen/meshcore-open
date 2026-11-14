import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../services/app_settings_service.dart';
import 'quick_answers_selection_dialog.dart';

Future<void> showContactSettingsDialog(
  BuildContext context, {
  required MeshCoreConnector connector,
  required Contact contact,
  bool canEditTelemetry = true,
}) {
  final appSettingsService = context.read<AppSettingsService>();
  connector.ensureContactMcmpSettingLoaded(contact.publicKeyHex);
  connector.ensureContactMCOtxtSettingLoaded(contact.publicKeyHex);
  connector.ensureContactSmazSettingLoaded(contact.publicKeyHex);
  connector.ensureContactCyr2LatSettingLoaded(contact.publicKeyHex);
  connector.ensureContactSendingDelaySettingLoaded(
    contact.publicKeyHex,
  );
  connector.ensureContactQuickAnswerIdsLoaded(contact.publicKeyHex);
  bool mcmpEnabled = connector.isContactMcmpEnabled(contact.publicKeyHex);
  bool mcotxtEnabled = connector.isContactMCOtxtEnabled(contact.publicKeyHex);
  bool mcotxtPlainWhenSmaller = connector.isContactMCOtxtPlainWhenSmaller(
    contact.publicKeyHex,
  );
  int selectedMcmpVersion = connector.contactMcmpVersion(
    contact.publicKeyHex,
  );
  bool mcmpUseSign = connector.contactMcmpUseSign(contact.publicKeyHex);
  bool smazEnabled = connector.isContactSmazEnabled(contact.publicKeyHex);
  bool cyr2latEnabled = connector.isContactCyr2LatEnabled(
    contact.publicKeyHex,
  );
  bool urlImagesEnabled = connector.isContactUrlImagesEnabled(
    contact.publicKeyHex,
  );
  bool sendingDelayEnabled = connector.isContactSendingDelayEnabled(
    contact.publicKeyHex,
  );
  List<String> selectedQuickAnswerIds = connector.getContactQuickAnswerIds(
    contact.publicKeyHex,
  );
  String? selectedCyr2LatProfileId = connector.getContactCyr2LatProfileId(
    contact.publicKeyHex,
  );
  bool teleBaseEnabled = contact.teleBaseEnabled;
  bool teleLocEnabled = contact.teleLocEnabled;
  bool teleEnvEnabled = contact.teleEnvEnabled;
  // Each toggle is committed at once, like the compression switches, so
  // dismissing the dialog by tapping outside keeps the change. All three
  // flags go every time so overlapping writes cannot undo each other.
  void commitTelemetryFlags() {
    if (!canEditTelemetry) return;
    connector.setContactFlags(
      contact,
      teleBase: teleBaseEnabled,
      teleLoc: teleLocEnabled,
      teleEnv: teleEnvEnabled,
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.contact_settings),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (contact.hasLocation) ...[
                ContactInfoRow(
                  context.l10n.chat_location,
                  '${contact.latitude?.toStringAsFixed(4)}, ${contact.longitude?.toStringAsFixed(4)}',
                ),
                const Divider(height: 8),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.channels_mcmpCompression),
                subtitle: Text(
                  context.l10n.channels_mcmpCompressionDescription,
                ),
                value: mcmpEnabled,
                onChanged: (value) {
                  connector.setContactMcmpEnabled(
                    contact.publicKeyHex,
                    value,
                  );
                  if (value) {
                    connector.setContactSmazEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                    connector.setContactMCOtxtEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                    connector.setContactCyr2LatEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                  }
                  setDialogState(() {
                    mcmpEnabled = value;
                    if (mcmpEnabled) {
                      mcotxtEnabled = false;
                      smazEnabled = false;
                      cyr2latEnabled = false;
                    }
                  });
                },
              ),
              if (mcmpEnabled) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  child: DropdownButtonFormField<int>(
                    initialValue: selectedMcmpVersion,
                    decoration: InputDecoration(
                      labelText: context.l10n.settings_mcmp_version,
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 2, child: Text('v2 (legacy)')),
                      DropdownMenuItem(value: 3, child: Text('v3')),
                    ],
                    onChanged: (value) {
                      final normalized = value == 3 ? 3 : 2;
                      connector.setContactMcmpVersion(
                        contact.publicKeyHex,
                        normalized,
                      );
                      setDialogState(() {
                        selectedMcmpVersion = normalized;
                      });
                    },
                  ),
                ),
                if (contact.type == advTypeRoom && selectedMcmpVersion == 3)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                    child: DropdownButtonFormField<bool>(
                      initialValue: mcmpUseSign,
                      decoration: InputDecoration(
                        labelText: context.l10n.settings_mcmp_useSign,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: true,
                          child: Text(context.l10n.settings_mcmp_signed),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text(context.l10n.settings_mcmp_noSign),
                        ),
                      ],
                      onChanged: (value) {
                        final normalized = value ?? true;
                        connector.setContactMcmpUseSign(
                          contact.publicKeyHex,
                          normalized,
                        );
                        setDialogState(() {
                          mcmpUseSign = normalized;
                        });
                      },
                    ),
                  ),
              ],
              const Divider(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.channels_smazCompression),
                subtitle: Text(context.l10n.chat_compressOutgoingMessages),
                value: smazEnabled,
                onChanged: (value) {
                  connector.setContactSmazEnabled(
                    contact.publicKeyHex,
                    value,
                  );
                  connector.setContactMcmpEnabled(
                    contact.publicKeyHex,
                    false,
                  );
                  connector.setContactMCOtxtEnabled(
                    contact.publicKeyHex,
                    false,
                  );
                  connector.setContactCyr2LatEnabled(
                    contact.publicKeyHex,
                    false,
                  );
                  setDialogState(() {
                    smazEnabled = value;
                    if (smazEnabled) {
                      mcmpEnabled = false;
                      mcotxtEnabled = false;
                      cyr2latEnabled = false;
                    }
                  });
                },
              ),
              const Divider(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.channels_cyr2latCompression),
                subtitle: Text(context.l10n.channels_cyr2latCompressionDscr),
                value: cyr2latEnabled,
                onChanged: (value) {
                  connector.setContactCyr2LatEnabled(
                    contact.publicKeyHex,
                    value,
                  );
                  connector.setContactMcmpEnabled(
                    contact.publicKeyHex,
                    false,
                  );
                  connector.setContactMCOtxtEnabled(
                    contact.publicKeyHex,
                    false,
                  );
                  connector.setContactSmazEnabled(
                    contact.publicKeyHex,
                    false,
                  );
                  setDialogState(() {
                    cyr2latEnabled = value;
                    if (cyr2latEnabled) {
                      mcmpEnabled = false;
                      mcotxtEnabled = false;
                      smazEnabled = false;
                    }
                  });
                },
              ),
              if (cyr2latEnabled) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  child: DropdownButtonFormField<String>(
                    // Keep full profile names readable in the field and menu.
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    initialValue: selectedCyr2LatProfileId,
                    decoration: InputDecoration(
                      labelText:
                          context.l10n.channels_cyr2latSettingsSubheading,
                      border: const OutlineInputBorder(),
                    ),
                    items: appSettingsService.settings.cyr2latProfiles.map((
                      profile,
                    ) {
                      return DropdownMenuItem(
                        value: profile.id,
                        child: Text(profile.name, softWrap: true),
                      );
                    }).toList(),
                    onChanged: (value) {
                      connector.setContactCyr2LatProfileId(
                        contact.publicKeyHex,
                        value,
                      );
                      setDialogState(() {
                        selectedCyr2LatProfileId = value;
                      });
                    },
                  ),
                ),
              ],
              const Divider(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.channels_mcotxtCompression),
                value: mcotxtEnabled,
                onChanged: (value) {
                  connector.setContactMCOtxtEnabled(
                    contact.publicKeyHex,
                    value,
                  );
                  if (value) {
                    connector.setContactMcmpEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                    connector.setContactSmazEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                    connector.setContactCyr2LatEnabled(
                      contact.publicKeyHex,
                      false,
                    );
                  }
                  setDialogState(() {
                    mcotxtEnabled = value;
                    if (mcotxtEnabled) {
                      mcmpEnabled = false;
                      smazEnabled = false;
                      cyr2latEnabled = false;
                    }
                  });
                },
              ),
              if (mcotxtEnabled)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.l10n.channels_mcotxtPlainWhenSmaller,
                  ),
                  value: mcotxtPlainWhenSmaller,
                  onChanged: (value) {
                    connector.setContactMCOtxtPlainWhenSmaller(
                      contact.publicKeyHex,
                      value,
                    );
                    setDialogState(() {
                      mcotxtPlainWhenSmaller = value;
                    });
                  },
                ),
              const Divider(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.settings_useSendingDelay),
                value: sendingDelayEnabled,
                onChanged: (value) {
                  connector.setContactSendingDelayEnabled(
                    contact.publicKeyHex,
                    value,
                  );
                  setDialogState(() {
                    sendingDelayEnabled = value;
                  });
                },
              ),
              const Divider(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.quickreply_outlined),
                title: Text(context.l10n.settings_quickAnswersTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final selection = await showQuickAnswersSelectionDialog(
                    context,
                    settingsService: appSettingsService,
                    selectedAnswerIds: selectedQuickAnswerIds,
                  );
                  if (selection == null || !context.mounted) return;
                  await connector.setContactQuickAnswerIds(
                    contact.publicKeyHex,
                    selection,
                  );
                  if (!context.mounted) return;
                  setDialogState(() {
                    selectedQuickAnswerIds = selection;
                  });
                },
              ),
              const Divider(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.urlImage_enable),
                subtitle: appSettingsService.settings.loadLinkImages
                    ? null
                    : Text(context.l10n.urlImage_disabledInAppSettings),
                value: urlImagesEnabled,
                onChanged: appSettingsService.settings.loadLinkImages
                    ? (value) {
                        connector.setContactUrlImagesEnabled(
                          contact.publicKeyHex,
                          value,
                        );
                        setDialogState(() => urlImagesEnabled = value);
                      }
                    : null,
              ),
              const Divider(height: 8),
              if (!canEditTelemetry)
                Text(
                  context.l10n.contacts_notInNodeMemory,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.contact_teleBase),
                subtitle: Text(context.l10n.contact_teleBaseSubtitle),
                value: teleBaseEnabled,
                onChanged: canEditTelemetry
                    ? (value) {
                        setDialogState(() => teleBaseEnabled = value);
                        commitTelemetryFlags();
                      }
                    : null,
              ),
              const Divider(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.contact_teleLoc),
                subtitle: Text(context.l10n.contact_teleLocSubtitle),
                value: teleLocEnabled,
                onChanged: canEditTelemetry
                    ? (value) {
                        setDialogState(() => teleLocEnabled = value);
                        commitTelemetryFlags();
                      }
                    : null,
              ),
              const Divider(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.contact_teleEnv),
                subtitle: Text(context.l10n.contact_teleEnvSubtitle),
                value: teleEnvEnabled,
                onChanged: canEditTelemetry
                    ? (value) {
                        setDialogState(() => teleEnvEnabled = value);
                        commitTelemetryFlags();
                      }
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              commitTelemetryFlags();
              Navigator.pop(context);
            },
            child: Text(context.l10n.common_close),
          ),
        ],
      ),
    ),
  );
}

class ContactInfoRow extends StatelessWidget {
  const ContactInfoRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(color: Colors.grey[600])),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}
