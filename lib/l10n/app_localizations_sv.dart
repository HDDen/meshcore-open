// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swedish (`sv`).
class AppLocalizationsSv extends AppLocalizations {
  AppLocalizationsSv([String locale = 'sv']) : super(locale);

  @override
  String get appTitle => 'MeshCore Open (Advanced mod)';

  @override
  String get nav_contacts => 'Kontakter';

  @override
  String get nav_channels => 'Kanaler';

  @override
  String get nav_map => 'Karta';

  @override
  String get common_cancel => 'Avbryt';

  @override
  String get common_ok => 'Okej';

  @override
  String get common_connect => 'Anslut';

  @override
  String get common_unknownDevice => 'Okänd enhet';

  @override
  String get common_save => 'Spara';

  @override
  String get common_delete => 'Radera';

  @override
  String get common_deleteAll => 'Ta bort alla';

  @override
  String get common_close => 'Stäng';

  @override
  String get common_done => 'Klar';

  @override
  String get common_edit => 'Redigera';

  @override
  String get common_add => 'Lägg till';

  @override
  String get common_settings => 'Inställningar';

  @override
  String get common_disconnect => 'Koppla från';

  @override
  String get common_connected => 'Ansluten';

  @override
  String get common_disconnected => 'Frånkopplad';

  @override
  String get common_create => 'Skapa';

  @override
  String get common_continue => 'Fortsätt';

  @override
  String get common_share => 'Dela';

  @override
  String get common_copy => 'Kopiera';

  @override
  String get common_retry => 'Försök igen';

  @override
  String get common_hide => 'Dölj';

  @override
  String get common_remove => 'Ta bort';

  @override
  String get common_enable => 'Aktivera';

  @override
  String get common_disable => 'Inaktivera';

  @override
  String get common_undo => 'Ångra';

  @override
  String get messageStatus_sent => 'Skickat';

  @override
  String get messageStatus_delivered => 'Levererat';

  @override
  String get messageStatus_pending => 'Skickas';

  @override
  String get messageStatus_failed => 'Misslyckades med att skicka';

  @override
  String get messageStatus_repeated => 'Upprepning hörd';

  @override
  String get common_reboot => 'Starta om';

  @override
  String get common_loading => 'Laddar...';

  @override
  String get common_notAvailable => '—';

  @override
  String common_voltageValue(String volts) {
    return '$volts V';
  }

  @override
  String common_percentValue(int percent) {
    return '$percent%';
  }

  @override
  String get common_autoRefresh => 'Automatisk uppdatering';

  @override
  String get common_interval => 'Intervall';

  @override
  String get common_default => 'Standard';

  @override
  String get common_clear => 'Rensa';

  @override
  String get common_send => 'Skicka';

  @override
  String get common_apply => 'Verkställ';

  @override
  String get scanner_title => 'MeshCore Open (Advanced mod)';

  @override
  String get connectionChoiceUsbLabel => 'USB';

  @override
  String get connectionChoiceBluetoothLabel => 'Bluetooth';

  @override
  String get connectionChoiceTcpLabel => 'TCP';

  @override
  String get tcpScreenTitle => 'Anslut via TCP';

  @override
  String get tcpHostLabel => 'IP-adress';

  @override
  String get tcpHostHint => '192.168.40.10 / example.com';

  @override
  String get tcpPortLabel => 'Port';

  @override
  String get tcpPortHint => '5000';

  @override
  String get tcpStatus_notConnected => 'Ange slutpunkt och anslut';

  @override
  String tcpStatus_connectingTo(String endpoint) {
    return 'Ansluter till $endpoint...';
  }

  @override
  String get tcpErrorHostRequired => 'IP-adress krävs.';

  @override
  String get tcpErrorPortInvalid => 'Porten måste vara mellan 1 och 65535.';

  @override
  String get tcpErrorUnsupported =>
      'TCP-transport fungerar inte på denna plattform.';

  @override
  String get tcpErrorTimedOut => 'TCP-anslutningens tidsgräns överskreds.';

  @override
  String tcpConnectionFailed(String error) {
    return 'Fel vid TCP-anslutning: $error';
  }

  @override
  String get tcpBookmarksLabel => 'Senaste anslutningar';

  @override
  String get tcpBookmarksSetName => 'Ange namn för bokmärke';

  @override
  String get tcpBookmarksFavouritesSubtitle =>
      'När den är markerad som favorit tas den inte bort från anslutningshistoriken';

  @override
  String get usbScreenTitle => 'Anslut via USB';

  @override
  String get usbScreenSubtitle =>
      'Välj en detekterad seriell enhet och anslut direkt till din MeshCore-nod.';

  @override
  String get usbScreenStatus => 'Välj en USB-enhet';

  @override
  String get usbScreenNote =>
      'USB-seriell kommunikation är aktiv på stödda Android-enheter och på skrivbordsplattformar.';

  @override
  String get usbScreenEmptyState =>
      'Inga USB-enheter hittades. Anslut en och uppdatera.';

  @override
  String get usbErrorPermissionDenied => 'Tillgången via USB nekas.';

  @override
  String get usbErrorDeviceMissing =>
      'Den valda USB-enheten är inte längre tillgänglig.';

  @override
  String get usbErrorInvalidPort => 'Välj en giltig USB-enhet.';

  @override
  String get usbErrorBusy =>
      'En annan förfrågan om USB-anslutning är redan pågående.';

  @override
  String get usbErrorNotConnected => 'Ingen USB-enhet är ansluten.';

  @override
  String get usbErrorOpenFailed =>
      'Misslyckades med att öppna den valda USB-enheten.';

  @override
  String get usbErrorConnectFailed =>
      'Kunde inte ansluta till den valda USB-enheten.';

  @override
  String get usbErrorUnsupported =>
      'USB-seriell kommunikation stöds inte på denna plattform.';

  @override
  String get usbErrorAlreadyActive => 'En USB-anslutning är redan aktiv.';

  @override
  String get usbErrorNoDeviceSelected => 'Ingen USB-enhet valdes.';

  @override
  String get usbErrorPortClosed => 'USB-anslutningen är inte aktiv.';

  @override
  String get usbErrorConnectTimedOut =>
      'Anslutningens tidsgräns överskreds. Se till att enheten har USB Companion-firmware.';

  @override
  String get usbFallbackDeviceName => 'Web Serial-enhet';

  @override
  String get usbStatus_notConnected => 'Välj en USB-enhet';

  @override
  String get usbStatus_connecting => 'Ansluter till USB-enhet...';

  @override
  String get usbStatus_searching => 'Söker efter USB-enheter...';

  @override
  String usbConnectionFailed(String error) {
    return 'Fel vid USB-anslutning: $error';
  }

  @override
  String get scanner_scanning => 'Söker efter enheter...';

  @override
  String get scanner_connecting => 'Ansluter...';

  @override
  String get scanner_disconnecting => 'Anslutning bryts...';

  @override
  String get scanner_notConnected => 'Inte ansluten';

  @override
  String scanner_connectedTo(String deviceName) {
    return 'Ansluten till $deviceName';
  }

  @override
  String get scanner_searchingDevices => 'Söker efter MeshCore-enheter...';

  @override
  String get scanner_tapToScan =>
      'Tryck på Skanna för att hitta MeshCore-enheter';

  @override
  String scanner_connectionFailed(String error) {
    return 'Anslutning misslyckades: $error';
  }

  @override
  String get scanner_stop => 'Stoppa';

  @override
  String get scanner_scan => 'Skanna';

  @override
  String get scanner_bluetoothOff => 'Bluetooth är avstängt';

  @override
  String get scanner_bluetoothOffMessage =>
      'Vänligen aktivera Bluetooth för att söka efter enheter.';

  @override
  String get scanner_chromeRequired => 'Chrome-webbläsare krävs';

  @override
  String get scanner_chromeRequiredMessage =>
      'Denna webbapplikation kräver Google Chrome eller en Chromium-baserad webbläsare för Bluetooth-stöd.';

  @override
  String get scanner_enableBluetooth => 'Aktivera Bluetooth';

  @override
  String get scanner_bluetoothWebUnsupported =>
      'Bluetooth är inte tillgängligt i webbläsaren. Anslut istället via USB.';

  @override
  String get device_quickSwitch => 'Snabbväxling';

  @override
  String get device_meshcore => 'MeshCore';

  @override
  String get settings_title => 'Inställningar';

  @override
  String get settings_deviceInfo => 'Enhetens information';

  @override
  String get settings_appSettings => 'Appinställningar';

  @override
  String get settings_appSettingsSubtitle =>
      'Meddelanden, notiser och kartinställningar';

  @override
  String get settings_nodeSettings => 'Nodinställningar';

  @override
  String get settings_nodeName => 'Nodnamn';

  @override
  String get settings_nodeNameNotSet => 'Inte angivet';

  @override
  String get settings_nodeNameHint => 'Ange nodnamn';

  @override
  String get settings_nodeNameUpdated => 'Namn uppdaterat';

  @override
  String get settings_radioSettings => 'Radioinställningar';

  @override
  String get settings_radioSettingsSubtitle =>
      'Frekvens, effekt, spridningsfaktor';

  @override
  String get settings_radioSettingsUpdated =>
      'Radioinställningarna har uppdaterats';

  @override
  String get settings_regionSettings => 'Regioner';

  @override
  String get settings_regionSettingsSubtitle => 'Hantera sparade regioner';

  @override
  String get settings_regionManagement_screenTitle => 'Regionhantering';

  @override
  String get settings_regionNameHint => 'Ange regionens namn';

  @override
  String get settings_regionAddRegion => 'Lägg till region';

  @override
  String get settings_regionFetchRegions => 'Hämta regioner från repeatrar';

  @override
  String get settings_regionFetchRegionsFail => 'Inga regioner hittades';

  @override
  String get settings_regionFetchRegionsAlreadyExists =>
      'Den här regionen är redan tillagd';

  @override
  String get settings_regionName => 'Regionens namn';

  @override
  String get settings_regionDeleted => 'Regionen har tagits bort';

  @override
  String get settings_deleteRegion => 'Ta bort region';

  @override
  String settings_deleteRegionConfirm(String region) {
    return 'Ta bort \"$region\" från listan med regioner?';
  }

  @override
  String get settings_location => 'Plats';

  @override
  String get settings_locationSubtitle => 'GPS-koordinater';

  @override
  String get settings_locationUpdated =>
      'Plats och GPS-inställningar uppdaterade';

  @override
  String get settings_locationBothRequired => 'Ange både latitud och longitud.';

  @override
  String get settings_locationInvalid => 'Ogiltig latitud eller longitud.';

  @override
  String get settings_locationGPSEnable => 'Aktivera GPS';

  @override
  String get settings_locationGPSEnableSubtitle =>
      'Aktivera automatiska uppdateringar av platsen med hjälp av GPS.';

  @override
  String get settings_locationIntervalSec => 'Intervall för GPS (sekunder)';

  @override
  String get settings_locationIntervalInvalid =>
      'Intervallet måste vara minst 60 sekunder och mindre än 86400 sekunder.';

  @override
  String get settings_latitude => 'Latitud';

  @override
  String get settings_longitude => 'Längdgrad';

  @override
  String get settings_contactSettings => 'Kontaktinställningar';

  @override
  String get settings_contactSettingsSubtitle =>
      'Inställningar för hur kontakter läggs till.';

  @override
  String get settings_privacyMode => 'Privatläge';

  @override
  String get settings_privacyModeSubtitle => 'Dölj namn/plats i adverts';

  @override
  String get settings_privacyModeToggle =>
      'Aktivera privatläge för att dölja ditt namn och din plats i adverts.';

  @override
  String get settings_privacyModeEnabled => 'Privatläget är aktiverat';

  @override
  String get settings_privacyModeDisabled => 'Privatläget är avstängt';

  @override
  String get settings_privacy => 'Inställningar för sekretess';

  @override
  String get settings_privacySubtitle =>
      'Kontrollera vilken information som delas.';

  @override
  String get settings_privacySettingsDescription =>
      'Välj vilken information din enhet delar med andra.';

  @override
  String get settings_denyAll => 'Neka alla';

  @override
  String get settings_allowByContact => 'Tillåt via kontaktflaggor';

  @override
  String get settings_allowAll => 'Tillåt alla';

  @override
  String get settings_telemetryBaseMode => 'Telemetribasläge';

  @override
  String get settings_telemetryLocationMode => 'Telemetritillstånd för plats';

  @override
  String get settings_telemetryEnvironmentMode => 'Telemetriläge för miljö';

  @override
  String get settings_advertLocation => 'Plats i adverten';

  @override
  String get settings_advertLocationSubtitle => 'Inkludera plats i adverten.';

  @override
  String get settings_autoZeroHopAdvertOnGpsUpdate =>
      'Automatisk zero-hop-advert vid GPS-uppdatering';

  @override
  String get settings_autoZeroHopAdvertOnGpsUpdateSubtitle =>
      'När GPS-positionen ändras, skicka en zero-hop-advert (kräver plats i adverten).';

  @override
  String get settings_multiAck => 'Flera bekräftelser';

  @override
  String get settings_telemetryModeUpdated => 'Telemetri-läge uppdaterat';

  @override
  String get settings_actions => 'Åtgärder';

  @override
  String get settings_deleteAllPaths => 'Ta bort alla rutter';

  @override
  String get settings_deleteAllPathsSubtitle =>
      'Rensa alla lokala ruttdata från kontakter. Rutter på noden påverkas inte.';

  @override
  String get settings_sendAdvertisement => 'Skicka advert';

  @override
  String get settings_sendAdvertisementSubtitle => 'Meddela din närvaro nu';

  @override
  String get settings_advertisementSent => 'Advert skickad';

  @override
  String get settings_syncTime => 'Synkronisera tid';

  @override
  String get settings_syncTimeSubtitle => 'Ställ enheten till telefonens tid';

  @override
  String get settings_timeSynchronized => 'Tiden har synkroniserats';

  @override
  String get settings_refreshContacts => 'Uppdatera kontakter';

  @override
  String get settings_refreshContactsSubtitle =>
      'Ladda om kontaktlistan från enheten';

  @override
  String get settings_rebootDevice => 'Starta om enheten';

  @override
  String get settings_rebootDeviceSubtitle => 'Starta om MeshCore-enheten';

  @override
  String get settings_rebootDeviceConfirm =>
      'Är du säker på att du vill starta om enheten? Du kommer att kopplas från.';

  @override
  String get settings_debug => 'Felsökning';

  @override
  String get settings_companionDebugLog => 'Companion-felsökningslogg';

  @override
  String get settings_companionDebugLogSubtitle =>
      'BLE/TCP/USB-kommandon, svar och rådata';

  @override
  String get settings_appDebugLog => 'Appens felsökningslogg';

  @override
  String get settings_appDebugLogSubtitle =>
      'Applikationens felsökningsmeddelanden';

  @override
  String get settings_about => 'Om';

  @override
  String settings_aboutVersion(String version) {
    return 'MeshCore Open (Advanced mod) version $version';
  }

  @override
  String get settings_aboutLegalese => '2026 MeshCore Open Source Project';

  @override
  String get settings_aboutDescription =>
      'En Flutter-klient med öppen källkod för MeshCore LoRa-meshnätverksenheter.';

  @override
  String get settings_aboutModDescription =>
      'Modifieringen «Advanced» bygger på det ursprungliga meshcore_open och innehåller ändringar som har föreslagits i den ursprungliga applikationens repository eller som är specifika för användningsområdet och därför inte har skickats in som pull request.';

  @override
  String get settings_aboutModLink =>
      'Utgåvor på Github: \nhttps://github.com/HDDen/meshcore-open/releases \nModifieringens grupp på Telegram: \nhttps://t.me/mcoadvanced \nModifieringens webbplats: \nhttps://mcoadvanced.ru';

  @override
  String get settings_aboutOpenMeteoAttribution =>
      'LOS-höjddata: Open-Meteo (CC BY 4.0)';

  @override
  String get settings_infoName => 'Namn';

  @override
  String get settings_infoId => 'ID';

  @override
  String get settings_infoDeviceName => 'Kortets namn';

  @override
  String get settings_infoStatus => 'Status';

  @override
  String get settings_infoBattery => 'Batteri';

  @override
  String get settings_infoPublicKey => 'Publik nyckel';

  @override
  String get settings_infoContactsCount => 'Antal kontakter';

  @override
  String get settings_infoChannelCount => 'Kanalantal';

  @override
  String get settings_infoFirmware => 'Firmwareversion';

  @override
  String get settings_presets => 'Fördefinierade inställningar';

  @override
  String get settings_frequency => 'Frekvens (MHz)';

  @override
  String get settings_frequencyHelper => '150.0 - 2500.0';

  @override
  String get settings_frequencyInvalid => 'Ogiltig frekvens (150-2500 MHz)';

  @override
  String get settings_bandwidth => 'Bandbredd';

  @override
  String get settings_spreadingFactor => 'Spridningsfaktor';

  @override
  String get settings_codingRate => 'Kodningsgrad';

  @override
  String get settings_txPower => 'TX-effekt (dBm)';

  @override
  String get settings_txPowerHelper => '0 – 22';

  @override
  String get settings_txPowerInvalid => 'Ogiltig TX-effekt (0-22 dBm)';

  @override
  String get settings_clientRepeat => 'Off-grid-repetering';

  @override
  String get settings_clientRepeatSubtitle =>
      'Låt enheten repetera nätpaket för andra användare.';

  @override
  String get settings_clientRepeatFreqWarning =>
      'Off-grid-repetering kräver frekvensen 433, 869.495 eller 918 MHz';

  @override
  String settings_error(String message) {
    return 'Fel: $message';
  }

  @override
  String get settings_channelResendTimeoutTitle =>
      'Fördröjning för manuell omsändning';

  @override
  String get settings_channelResendTimeoutSubtitle =>
      'Påverkar också den interna mekanismen som tar bort dubbla visningar av utgående meddelanden';

  @override
  String get settings_channelMaxbytesOutgoingTitle =>
      'Begränsa utgående payload för kanaler, byte';

  @override
  String get settings_channelMaxbytesOutgoingSubtitle =>
      'Gränsen tar hänsyn till meddelandetexten plus avsändarens namn. Det har observerats att när ett meddelande överstiger ett visst antal byte slutar bekräftelser för paketupprepning att överföras. Detta märks särskilt med BLE-anslutningar. Den ungefärliga tröskeln där bekräftelser fortfarande fungerar är 139 byte. För TCP/USB är gränsen cirka 150 byte.';

  @override
  String get settings_quickAnswersTitle => 'Snabbsvar';

  @override
  String get settings_quickAnswersSubtitle =>
      'En lista med fraser som kan väljas som snabbsvar. De tilldelas kontakter/kanaler i deras inställningar.';

  @override
  String get settings_quickAnswersAddText => 'Ange din text';

  @override
  String get settings_quickAnswersEditText => 'Redigera svar';

  @override
  String get settings_quickAnswersSelect => 'Aktivera dessa svar';

  @override
  String get settings_quickAnswersExists => 'Finns redan';

  @override
  String get settings_quickAnswersNotAdded =>
      'Du har inte lagt till några snabbsvar för den här chatten ännu!';

  @override
  String get settings_quickAnswersSendAtSelect => 'Skicka vid val';

  @override
  String get appSettings_title => 'Appinställningar';

  @override
  String get appSettings_appearance => 'Utseende';

  @override
  String get appSettings_theme => 'Tema';

  @override
  String get appSettings_themeSystem => 'Systemstandard';

  @override
  String get appSettings_themeLight => 'Ljus';

  @override
  String get appSettings_themeDark => 'Mörk';

  @override
  String get appSettings_language => 'Språk';

  @override
  String get appSettings_languageSystem => 'Systemstandard';

  @override
  String get appSettings_languageEn => 'Engelska';

  @override
  String get appSettings_languageFr => 'Franska';

  @override
  String get appSettings_languageEs => 'Spanska';

  @override
  String get appSettings_languageDe => 'Tyska';

  @override
  String get appSettings_languagePl => 'Polska';

  @override
  String get appSettings_languageSl => 'Sloveniska';

  @override
  String get appSettings_languagePt => 'Portugisiska';

  @override
  String get appSettings_languageIt => 'Italienska';

  @override
  String get appSettings_languageZh => 'Kinesiska';

  @override
  String get appSettings_languageSv => 'Svenska';

  @override
  String get appSettings_languageNl => 'Nederländska';

  @override
  String get appSettings_languageSk => 'Slovakiska';

  @override
  String get appSettings_languageBg => 'Bulgariska';

  @override
  String get appSettings_languageRu => 'Ryska';

  @override
  String get appSettings_languageUk => 'Ukrainska';

  @override
  String get repeater_pathHashModeOption0 => '1 byte';

  @override
  String get repeater_pathHashModeOption1 => '2 byte';

  @override
  String get repeater_pathHashModeOption2 => '3 byte';

  @override
  String get repeater_pathHashModeOption3 => '4 byte';

  @override
  String get appSettings_enableMessageTracing => 'Aktivera meddelandespårning';

  @override
  String get appSettings_enableMessageTracingSubtitle =>
      'Visa detaljerade metadata om dirigering och tider för meddelanden';

  @override
  String get appSettings_enableTimeSeconds =>
      'Visa sekunder i meddelandeinformationen';

  @override
  String get appSettings_showKeyboardHidingButton =>
      'Visa knapp för att dölja tangentbordet';

  @override
  String get appSettings_notifications => 'Notiser';

  @override
  String get appSettings_enableNotifications => 'Aktivera notifikationer';

  @override
  String get appSettings_enableNotificationsSubtitle =>
      'Ta emot notiser för meddelanden och adverts';

  @override
  String get appSettings_notificationPermissionDenied =>
      'Tillåtelse för notifikationer nekad';

  @override
  String get appSettings_notificationsEnabled => 'Notifikationer aktiverade';

  @override
  String get appSettings_notificationsDisabled => 'Notifikationer är avstängda';

  @override
  String get appSettings_messageNotifications => 'Notiser för meddelanden';

  @override
  String get appSettings_messageNotificationsSubtitle =>
      'Visa notis när nya meddelanden tas emot';

  @override
  String get appSettings_channelMessageNotifications =>
      'Notiser för kanalmeddelanden';

  @override
  String get appSettings_channelMessageNotificationsSubtitle =>
      'Visa notis när meddelanden i kanal mottas';

  @override
  String get appSettings_advertisementNotifications => 'Notiser för adverts';

  @override
  String get appSettings_advertisementNotificationsSubtitle =>
      'Visa notis när nya noder upptäcks';

  @override
  String get appSettings_messaging => 'Meddelanden';

  @override
  String get appSettings_clearPathOnMaxRetry =>
      'Rensa vägen vid max antal försök';

  @override
  String get appSettings_clearPathOnMaxRetrySubtitle =>
      'Återställ kontaktväg efter 5 misslyckade försök att skicka';

  @override
  String get appSettings_pathsWillBeCleared =>
      'Sökvägar kommer att tömmas efter 5 misslyckade försök.';

  @override
  String get appSettings_pathsWillNotBeCleared =>
      'Sökvägar kommer inte att rensas automatiskt.';

  @override
  String get appSettings_autoRouteRotation => 'Automatisk ruttrotation';

  @override
  String get appSettings_autoRouteRotationSubtitle =>
      'Växla mellan de bästa vägarna och läget flood';

  @override
  String get appSettings_autoRouteRotationEnabled =>
      'Automatisk ruttrotation är aktiverad';

  @override
  String get appSettings_autoRouteRotationDisabled =>
      'Automatisk ruttrotation är avstängd';

  @override
  String get appSettings_maxRouteWeight => 'Maximal tillåten vikt för rutten';

  @override
  String get appSettings_maxRouteWeightSubtitle =>
      'Maximal vikt som en leveransväg kan ackumulera från framgångsrika leveranser.';

  @override
  String get appSettings_initialRouteWeight => 'Initial vikt för rutt';

  @override
  String get appSettings_initialRouteWeightSubtitle =>
      'Initial vikt för nyligen upptäckta vägar';

  @override
  String get appSettings_routeWeightSuccessIncrement =>
      'Ökning av vikt för framgång';

  @override
  String get appSettings_routeWeightSuccessIncrementSubtitle =>
      'Vikt läggs till en väg efter en lyckad leverans.';

  @override
  String get appSettings_routeWeightFailureDecrement =>
      'Minskning av vikten för misslyckande';

  @override
  String get appSettings_routeWeightFailureDecrementSubtitle =>
      'Vikt som tagits bort från en väg efter ett misslyckat leveransförsök';

  @override
  String get appSettings_maxMessageRetries => 'Maximalt antal försök';

  @override
  String get appSettings_maxMessageRetriesSubtitle =>
      'Antal försök att skicka om ett meddelande innan det markeras som misslyckat.';

  @override
  String get appSettings_battery => 'Batteri';

  @override
  String get appSettings_batteryChemistry => 'Batterikemi';

  @override
  String appSettings_batteryChemistryPerDevice(String deviceName) {
    return 'Ställ in per enhet ($deviceName)';
  }

  @override
  String get appSettings_batteryChemistryConnectFirst =>
      'Anslut till en enhet för att välja';

  @override
  String get appSettings_batteryNmc => '18650 NMC (3,0-4,2V)';

  @override
  String get appSettings_batteryLifepo4 => 'LiFePO4 (2,6–3,65V)';

  @override
  String get appSettings_batteryLipo => 'LiPo (3,0-4,2V)';

  @override
  String get appSettings_mapDisplay => 'Kartvisning';

  @override
  String get appSettings_showRepeaters => 'Visa repeatrar';

  @override
  String get appSettings_showRepeatersSubtitle =>
      'Visa repeaternoder på kartan';

  @override
  String get appSettings_showChatNodes => 'Visa chattnoder';

  @override
  String get appSettings_showChatNodesSubtitle => 'Visa chattnoder på kartan';

  @override
  String get appSettings_showOtherNodes => 'Visa andra noder';

  @override
  String get appSettings_showOtherNodesSubtitle =>
      'Visa andra nodtyper på kartan';

  @override
  String get appSettings_timeFilter => 'Tidsfilter';

  @override
  String get appSettings_timeFilterShowAll => 'Visa alla noder';

  @override
  String appSettings_timeFilterShowLast(int hours) {
    return 'Visa noder från de senaste $hours timmarna';
  }

  @override
  String get appSettings_mapTimeFilter => 'Tidsfilter för kartan';

  @override
  String get appSettings_showNodesDiscoveredWithin =>
      'Visa noder som upptäckts inom:';

  @override
  String get appSettings_allTime => 'All tid';

  @override
  String get appSettings_lastHour => 'Senaste timmen';

  @override
  String get appSettings_last6Hours => 'De senaste 6 timmarna';

  @override
  String get appSettings_last24Hours => 'De senaste 24 timmarna';

  @override
  String get appSettings_lastWeek => 'Senaste veckan';

  @override
  String get appSettings_rasterTileSource => 'Källa för rasterplattor';

  @override
  String get appSettings_stadiaEndpoint => 'Stadia-slutpunkt';

  @override
  String get appSettings_stadiaApiKey => 'Stadia API-nyckel';

  @override
  String get appSettings_stadiaApiKeyRequired =>
      'Krävs för att använda Stadia Maps';

  @override
  String appSettings_stadiaApiKeyConfigured(String maskedKey) {
    return 'Konfigurerad: $maskedKey';
  }

  @override
  String get appSettings_stadiaApiKeyDialogDescription =>
      'Ange din Stadia Maps API-nyckel. Appen använder den för förfrågningar om rasterplattor.';

  @override
  String get appSettings_offlineMapCache => 'Offline-kartcache';

  @override
  String get appSettings_unitsTitle => 'Enheter';

  @override
  String get appSettings_unitsMetric => 'Metriskt (m/km)';

  @override
  String get appSettings_unitsImperial => 'Imperialt (ft / mi)';

  @override
  String get appSettings_noAreaSelected => 'Ingen area markerad';

  @override
  String appSettings_areaSelectedZoom(int minZoom, int maxZoom) {
    return 'Område markerat (zoom $minZoom-$maxZoom)';
  }

  @override
  String get appSettings_debugCard => 'Felsökning';

  @override
  String get appSettings_appDebugLogging => 'App-felsökning och loggning';

  @override
  String get appSettings_appDebugLoggingSubtitle =>
      'Logga appens felsökningsmeddelanden för felsökning';

  @override
  String get appSettings_appDebugLoggingEnabled =>
      'Appens felsökningsloggning aktiverad';

  @override
  String get appSettings_appDebugLoggingDisabled =>
      'Appens felsökningsloggning avstängd';

  @override
  String get contacts_title => 'Kontakter';

  @override
  String get contacts_noContacts => 'Inga kontakter ännu';

  @override
  String get contacts_contactsWillAppear =>
      'Kontakter kommer att visas när enheter skickar adverts';

  @override
  String get contacts_unread => 'Oläst';

  @override
  String get contacts_searchContactsNoNumber => 'Sök kontakter...';

  @override
  String contacts_searchContacts(int number, String str) {
    return 'Sök $number$str kontakter...';
  }

  @override
  String contacts_searchFavorites(int number, String str) {
    return 'Sök $number$str favoriter...';
  }

  @override
  String contacts_searchUsers(int number, String str) {
    return 'Sök $number$str användare...';
  }

  @override
  String contacts_searchRepeaters(int number, String str) {
    return 'Sök $number$str repeatrar...';
  }

  @override
  String contacts_searchRoomServers(int number, String str) {
    return 'Sök $number$str rumsservrar...';
  }

  @override
  String get contacts_noUnreadContacts => 'Inga olästa kontakter';

  @override
  String get contacts_noContactsFound =>
      'Inga kontakter eller grupper hittades.';

  @override
  String get contacts_deleteContact => 'Ta bort kontakt';

  @override
  String contacts_removeConfirm(String contactName) {
    return 'Ta bort $contactName från kontakter?';
  }

  @override
  String get contacts_manageRepeater => 'Hantera repeater';

  @override
  String get contacts_requestRegions => 'Begär regioner';

  @override
  String get contacts_manageRoom => 'Hantera rumsserver';

  @override
  String get contacts_roomLogin => 'Inloggning på rumsserver';

  @override
  String get contacts_openChat => 'Öppna chatt';

  @override
  String get contacts_editGroup => 'Redigera grupp';

  @override
  String get contacts_deleteGroup => 'Ta bort grupp';

  @override
  String contacts_deleteGroupConfirm(String groupName) {
    return 'Ta bort $groupName?';
  }

  @override
  String get contacts_newGroup => 'Ny grupp';

  @override
  String get contacts_newGroupDescription =>
      'Samlar kanaler/kontakter i en mapp';

  @override
  String get contacts_moreOptions => 'Fler alternativ';

  @override
  String get contacts_searchOpen => 'Sök efter kontakter';

  @override
  String get contacts_searchClose => 'Stäng sökning';

  @override
  String get contacts_groupName => 'Gruppnamn';

  @override
  String get contacts_groupNameRequired => 'Gruppnamnet är obligatoriskt';

  @override
  String get contacts_groupNameReserved => 'Detta gruppnamn är reserverat';

  @override
  String contacts_groupAlreadyExists(String name) {
    return 'Gruppen \"$name\" finns redan.';
  }

  @override
  String get contacts_filterContacts => 'Filtrera kontakter...';

  @override
  String get contacts_noContactsMatchFilter =>
      'Inga kontakter matchar ditt filter';

  @override
  String get contacts_noMembers => 'Inga medlemmar';

  @override
  String get contacts_lastSeenNow => 'nyligen';

  @override
  String contacts_lastSeenMinsAgo(int minutes) {
    return 'för $minutes min sedan';
  }

  @override
  String get contacts_lastSeenHourAgo => 'för 1 timme sedan';

  @override
  String contacts_lastSeenHoursAgo(int hours) {
    return 'för $hours timmar sedan';
  }

  @override
  String get contacts_lastSeenDayAgo => 'för 1 dag sedan';

  @override
  String contacts_lastSeenDaysAgo(int days) {
    return 'för $days dagar sedan';
  }

  @override
  String get contact_info => 'Kontaktinformation';

  @override
  String get contact_settings => 'Kontaktinställningar';

  @override
  String get contact_telemetry => 'Telemetri';

  @override
  String get contact_lastSeen => 'Senast sedd';

  @override
  String get contact_clearChat => 'Rensa chatt';

  @override
  String get contact_clearChatConfirm => 'Ta bort meddelandena från chatten?';

  @override
  String get contact_teleBase => 'Telemetribas';

  @override
  String get contact_teleBaseSubtitle =>
      'Tillåt delning av batterinivå och grundläggande telemetri';

  @override
  String get contact_teleLoc => 'Platstelemetri';

  @override
  String get contact_teleLocSubtitle => 'Tillåt delning av platsdata';

  @override
  String get contact_teleEnv => 'Miljötelemetri';

  @override
  String get contact_teleEnvSubtitle => 'Tillåt delning av miljösensordata';

  @override
  String get channels_title => 'Kanaler';

  @override
  String get channels_noChannelsConfigured => 'Inga kanaler konfigurerade';

  @override
  String get channels_addPublicChannel => 'Lägg till publik kanal';

  @override
  String get channels_searchChannels => 'Sök kanaler...';

  @override
  String get channels_noChannelsFound => 'Inga kanaler hittades';

  @override
  String channels_channelIndex(int index) {
    return 'Kanal $index';
  }

  @override
  String get channels_public => 'Offentlig';

  @override
  String channels_via(String path) {
    return 'via $path';
  }

  @override
  String get channels_private => 'Privat';

  @override
  String get channels_editChannel => 'Redigera kanal';

  @override
  String get channels_muteChannel => 'Tysta, utom omnämnanden';

  @override
  String get channels_unmuteChannel => 'Slå på ljud för kanal';

  @override
  String get channels_deleteChannel => 'Ta bort kanal';

  @override
  String channels_deleteChannelConfirm(String name) {
    return 'Radera \"$name\"? Detta kan inte ångras.';
  }

  @override
  String channels_channelDeleteFailed(String name) {
    return 'Det gick inte att ta bort kanalen \"$name\"';
  }

  @override
  String channels_channelDeleted(String name) {
    return 'Kanalen \"$name\" raderad';
  }

  @override
  String get channels_addChannel => 'Lägg till kanal';

  @override
  String get channels_channelIndexLabel => 'Kanalindex';

  @override
  String get channels_channelName => 'Kanalnamn';

  @override
  String get channels_usePublicChannel => 'Använd publik kanal';

  @override
  String get channels_standardPublicPsk => 'Publik standard-PSK';

  @override
  String get channels_pskHex => 'PSK (hex)';

  @override
  String get channels_generateRandomPsk => 'Generera slumpmässig PSK';

  @override
  String get channels_enterChannelName => 'Ange ett kanalnamn';

  @override
  String get channels_pskMustBe32Hex => 'PSK måste vara 32 hexadecimala tecken';

  @override
  String channels_channelAdded(String name) {
    return 'Kanalen \"$name\" har lagts till';
  }

  @override
  String channels_editChannelTitle(int index) {
    return 'Redigera kanal $index';
  }

  @override
  String get channels_smazCompression => 'SMAZ-komprimering';

  @override
  String get channels_cyr2latCompression => 'Cyr2Lat-komprimering';

  @override
  String get channels_cyr2latCompressionDscr =>
      'Ersätter vissa kyrilliska tecken med latinska tecken när du skickar.';

  @override
  String get channels_mcotxtCompression => 'MCOtxt-komprimering';

  @override
  String get channels_cyr2latSettingsHeading => 'Inställningar för Cyr2Lat';

  @override
  String get channels_cyr2latSettingsSubheading => 'Ersättningslista';

  @override
  String get channels_cyr2latSettingsDscr =>
      'Redigera JSON-konfigurationen för teckenersättning';

  @override
  String get channels_cyr2latSettingsDialogHint => 'JSON-ersättningskarta';

  @override
  String channels_cyr2latSettingsDialogWrongJSON(Object error) {
    return 'Felaktig JSON: $error';
  }

  @override
  String channels_channelUpdated(String name) {
    return 'Kanalen \"$name\" har uppdaterats';
  }

  @override
  String get channels_changeWidgetColor => 'Widgetens färg';

  @override
  String get channels_changeWidgetTextColor => 'Widgetens textfärg';

  @override
  String get channels_changeGroupEmpty => 'Det är tomt här än så länge';

  @override
  String get channels_allowOrderingInGroup =>
      'Tillåt sortering av kanaler i gruppen';

  @override
  String get settings_cyr2latProfileAdd => 'Lägg till Cyr2Lat-profil';

  @override
  String get settings_cyr2latProfileName => 'Profilnamn';

  @override
  String get settings_cyr2latProfileNameEmpty =>
      'Profilnamnet får inte vara tomt';

  @override
  String get settings_cyr2latProfileAdded => 'Profilen har lagts till';

  @override
  String get settings_cyr2latProfileUpdated => 'Profilen har uppdaterats';

  @override
  String get settings_cyr2latProfileEdit => 'Redigera Cyr2Lat-profil';

  @override
  String get settings_cyr2latProfileDelete => 'Ta bort Cyr2Lat-profil';

  @override
  String get settings_cyr2latProfileDeleted => 'Profilen har tagits bort';

  @override
  String settings_cyr2latProfileDeleteDscr(String name) {
    return 'Är du säker på att du vill ta bort profilen \"$name\"?';
  }

  @override
  String get settings_mcmpTextLimit => 'Gräns för inklistrad MCMP-text';

  @override
  String get settings_sendingDelayForCancellation =>
      'Sändningsfördröjning för avbrytning';

  @override
  String get settings_useSendingDelay => 'Använd sändningsfördröjning';

  @override
  String get chat_cancelSend => 'avbryt sändning';

  @override
  String get settings_doNotFilterMessagesOnChannels =>
      'Betrakta meddelanden i dessa kanaler som säkert levererade';

  @override
  String get settings_doNotFilterMessagesOnChannelsSubtitle =>
      'Meddelanden till de listade kanalerna skickas utan att vänta på nodens bekräftelse och utan omsändningar.';

  @override
  String get channels_publicChannelAdded => 'Publik kanal tillagd';

  @override
  String get channels_sortBy => 'Sortera efter';

  @override
  String get channels_sortManual => 'Manuell';

  @override
  String get channels_sortAZ => 'A-Z';

  @override
  String get channels_sortLatestMessages => 'Senaste meddelanden';

  @override
  String get channels_sortUnread => 'Oläst';

  @override
  String get channels_createPrivateChannel => 'Skapa en privat kanal';

  @override
  String get channels_createPrivateChannelDesc =>
      'Skyddad med en hemlig nyckel.';

  @override
  String get channels_joinPrivateChannel => 'Gå med i en privat kanal';

  @override
  String get channels_joinPrivateChannelDesc =>
      'Ange en hemlig nyckel manuellt.';

  @override
  String get channels_joinPublicChannel => 'Gå med i den offentliga kanalen';

  @override
  String get channels_joinPublicChannelDesc =>
      'Vem som helst kan gå med i denna kanal.';

  @override
  String get channels_joinHashtagChannel => 'Gå med i en hashtagkanal';

  @override
  String get channels_joinHashtagChannelDesc =>
      'Vem som helst kan gå med i hashtagkanaler.';

  @override
  String get channels_scanQrCode => 'Skanna en QR-kod';

  @override
  String get channels_scanQrCodeComingSoon => 'Kommer snart';

  @override
  String get channels_enterHashtag => 'Ange hashtag';

  @override
  String get channels_hashtagHint => 't.ex. #team';

  @override
  String get channels_hashtagMcoaHint => 'Versaler och ”_” stöds endast i MCOa';

  @override
  String channels_regionSetTo(String region) {
    return 'Region: $region';
  }

  @override
  String get channels_regionNotSet => 'Region: ingen';

  @override
  String get channels_regionSelect_Title => 'Tilldela region';

  @override
  String get channels_clearRegion => 'Rensa regionen';

  @override
  String get chat_noMessages => 'Inga meddelanden ännu';

  @override
  String get chat_sendMessage => 'Skicka meddelande';

  @override
  String chat_sendMessageTo(String contactName) {
    return 'Skicka ett meddelande till $contactName';
  }

  @override
  String get chat_sendMessageToStart =>
      'Skicka ett meddelande för att komma igång';

  @override
  String get chat_originalMessageNotFound =>
      'Originalt meddelande hittades inte';

  @override
  String chat_replyingTo(String name) {
    return 'Svarar $name';
  }

  @override
  String chat_replyTo(String name) {
    return 'Svara $name';
  }

  @override
  String get chat_location => 'Plats';

  @override
  String get chat_typeMessage => 'Skriv ett meddelande...';

  @override
  String chat_messageTooLong(int maxBytes) {
    return 'Meddelandet är för långt (max $maxBytes byte).';
  }

  @override
  String get chat_messageCopied => 'Meddelandet kopierades';

  @override
  String get chat_messageDeleted => 'Meddelandet raderat';

  @override
  String get chat_retryingMessage => 'Försöker igen';

  @override
  String chat_retryingMessageWait(Object seconds) {
    return 'Vänta $seconds sekunder innan du skickar igen';
  }

  @override
  String chat_retryCount(int current, int max) {
    return 'Försök $current/$max';
  }

  @override
  String get chat_sendGif => 'Skicka GIF';

  @override
  String get chat_receivedGif => 'GIF mottagen';

  @override
  String get chat_reply => 'Svara';

  @override
  String get chat_addReaction => 'Lägg till reaktion';

  @override
  String get chat_me => 'Jag';

  @override
  String get emojiCategorySmileys => 'Smileys';

  @override
  String get emojiCategoryGestures => 'Gestikuleringar';

  @override
  String get emojiCategoryHearts => 'Hjärtan';

  @override
  String get emojiCategoryObjects => 'Objekt';

  @override
  String get gifPicker_title => 'Välj en GIF';

  @override
  String get gifPicker_searchHint => 'Sök GIF:ar...';

  @override
  String get gifPicker_poweredBy => 'Drivet av GIPHY';

  @override
  String get gifPicker_noGifsFound => 'Inga GIF-filer hittades';

  @override
  String get gifPicker_failedLoad => 'Kunde inte ladda GIF-filer';

  @override
  String get gifPicker_failedSearch => 'Sökningen misslyckades.';

  @override
  String get gifPicker_noInternet => 'Ingen internetanslutning';

  @override
  String get debugLog_appTitle => 'Appens felsökningslogg';

  @override
  String get debugLog_bleTitle => 'BLE-felsökningslogg';

  @override
  String get debugLog_copyLog => 'Kopiera logg';

  @override
  String get debugLog_clearLog => 'Rensa logg';

  @override
  String get debugLog_copied => 'Felsökningslogg kopierad';

  @override
  String get debugLog_bleCopied => 'BLE-logg kopierad';

  @override
  String get debugLog_noEntries => 'Inga felsökningsloggar ännu';

  @override
  String get debugLog_enableInSettings =>
      'Aktivera appens felsökningsloggning i inställningarna';

  @override
  String get debugLog_frames => 'Ramar';

  @override
  String get debugLog_rawLogRx => 'Rå Log-RX';

  @override
  String get debugLog_noBleActivity => 'Ingen BLE-aktivitet ännu';

  @override
  String debugFrame_length(int count) {
    return 'Ramstorlek: $count byte';
  }

  @override
  String debugFrame_command(String value) {
    return 'Kommando: 0x$value';
  }

  @override
  String get debugFrame_textMessageHeader => 'Textmeddelanderam:';

  @override
  String debugFrame_destinationPubKey(String pubKey) {
    return '– Destination PubKey: $pubKey';
  }

  @override
  String debugFrame_timestamp(int timestamp) {
    return '- Tidsstämpel: $timestamp';
  }

  @override
  String debugFrame_flags(String value) {
    return '- Flaggor: 0x$value';
  }

  @override
  String debugFrame_textType(int type, String label) {
    return '- Texttyp: $type ($label)';
  }

  @override
  String get debugFrame_textTypeCli => 'Kommandorad';

  @override
  String get debugFrame_textTypePlain => 'Enkel';

  @override
  String debugFrame_text(String text) {
    return '- Text: \"$text\"';
  }

  @override
  String get debugFrame_hexDump => 'Hexdump:';

  @override
  String chat_hopsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hopp',
      one: 'hopp',
    );
    return '$count $_temp0';
  }

  @override
  String get chat_removePath => 'Ta bort sökväg';

  @override
  String get chat_noPathHistoryYet =>
      'Ingen sökvägshistorik ännu.\nSkicka ett meddelande för att upptäcka sökvägar.';

  @override
  String get chat_pathCleared =>
      'Rutten har rensats. Nästa meddelande kommer att upptäcka rutten igen.';

  @override
  String get chat_fullPath => 'Fullständig sökväg';

  @override
  String get routing_title => 'Ruttplanering';

  @override
  String get routing_modeAuto => 'Auto';

  @override
  String get routing_modeFlood => 'Flood';

  @override
  String get routing_modeManual => 'Manuell';

  @override
  String get routing_modeAutoHint =>
      'Väljer automatiskt den bästa kända vägen och använder flood om ingen väg är känd.';

  @override
  String get routing_modeFloodHint =>
      'Sänder via alla repeatrar. Det mest pålitliga alternativet, men kräver mer sändtid.';

  @override
  String get routing_modeManualHint =>
      'Skickar alltid längs exakt den väg du har angett.';

  @override
  String get routing_currentRoute => 'Nuvarande rutt';

  @override
  String get routing_directNoHops => 'Direkt – utan mellanliggande repeatrar';

  @override
  String get routing_noPathYet =>
      'Ingen väg hittad ännu. Nästa meddelande skickas via flood tills en rutt har upptäckts.';

  @override
  String get routing_floodBroadcast => 'Sänds via alla repeatrar';

  @override
  String get routing_editPath => 'Redigera sökväg';

  @override
  String get routing_forgetPath => 'Glöm vägen';

  @override
  String get routing_knownPaths => 'Kända vägar';

  @override
  String get routing_knownPathsHint => 'Välj en väg för att byta till den.';

  @override
  String get routing_inUse => 'I användning';

  @override
  String get routing_qualityStrong => 'Starkt första hopp';

  @override
  String get routing_qualityGood => 'Bra första hopp';

  @override
  String get routing_qualityFair => 'Hyfsat första hopp';

  @override
  String get routing_qualityWorked => 'Har levererat';

  @override
  String get routing_qualityFlood => 'Hörd via flood';

  @override
  String get routing_qualityUntested => 'Ej testat';

  @override
  String routing_lastWorked(String when) {
    return 'fungerade $when';
  }

  @override
  String get routing_neverWorked => 'aldrig bekräftat';

  @override
  String routing_deliveryCounts(int successes, int failures) {
    return '$successes levererade, $failures misslyckade';
  }

  @override
  String get routing_floodDelivery => 'Leverans via flood';

  @override
  String get pathEditor_title => 'Skapa väg';

  @override
  String pathEditor_hopCounter(int count) {
    return '$count av 64 hopp';
  }

  @override
  String get pathEditor_noHops =>
      'Inga hopp ännu. Tryck på repeatrar nedan för att lägga till dem i ordning, eller spara utan hopp för att skicka direkt.';

  @override
  String get pathEditor_addHops => 'Lägg till hopp i ordning';

  @override
  String get pathEditor_searchRepeaters => 'Sök repeatrar';

  @override
  String get pathEditor_advancedHex => 'Avancerat: rå hex-sökväg';

  @override
  String get pathEditor_hexLabel => 'Hex-prefix';

  @override
  String get pathEditor_hexHelper =>
      'Två hex-tecken per steg, separerade med kommatecken.';

  @override
  String pathEditor_invalidTokens(String tokens) {
    return 'Ogiltigt: $tokens';
  }

  @override
  String get pathEditor_tooManyHops => 'Högst 64 hopp';

  @override
  String get pathEditor_usePath => 'Använd denna väg';

  @override
  String get pathEditor_removeHop => 'Ta bort hopp';

  @override
  String get pathEditor_unknownHop => 'Okänd repeater';

  @override
  String get chat_pathSavedLocally =>
      'Sparat lokalt. Anslut för att synkronisera.';

  @override
  String get chat_pathDeviceConfirmed => 'Bekräftad av enheten.';

  @override
  String get chat_pathDeviceNotConfirmed => 'Inte bekräftad av enheten ännu.';

  @override
  String get chat_type => 'Typ';

  @override
  String get chat_path => 'Sökväg';

  @override
  String get chat_publicKey => 'Publik nyckel';

  @override
  String get chat_compressOutgoingMessages => 'Komprimera utgående meddelanden';

  @override
  String get chat_floodForced => 'Flood (tvingad)';

  @override
  String get chat_directForced => 'Direkt (tvingad)';

  @override
  String chat_hopsForced(int count) {
    return '$count hopp (tvingat)';
  }

  @override
  String get chat_floodAuto => 'Flood (auto)';

  @override
  String get chat_direct => 'Direkt';

  @override
  String get chat_poiShared => 'Delad POI';

  @override
  String chat_unread(int count) {
    return 'Olästa: $count';
  }

  @override
  String get chat_markAsUnread => 'Markera som oläst';

  @override
  String get chat_newMessages => 'Nya meddelanden';

  @override
  String get chat_openLink => 'Öppna länk?';

  @override
  String get chat_openLinkConfirmation =>
      'Vill du öppna den här länken i din webbläsare?';

  @override
  String get chat_open => 'Öppna';

  @override
  String chat_couldNotOpenLink(String url) {
    return 'Kunde inte öppna länken: $url';
  }

  @override
  String get chat_invalidLink => 'Ogiltigt länkformat';

  @override
  String get map_title => 'Nodkarta';

  @override
  String get map_searchHint => 'Sök efter nodens namn eller ID';

  @override
  String get map_activity => 'Aktivitet';

  @override
  String get map_online => 'Online';

  @override
  String get map_recent => 'Nyligen';

  @override
  String get map_stale => 'Inaktuell';

  @override
  String get map_visible => 'Synlig';

  @override
  String get map_hidden => 'Dold';

  @override
  String get map_centerOnNode => 'Centrera på nod';

  @override
  String get map_details => 'Detaljer';

  @override
  String get map_noGps => 'Ingen GPS';

  @override
  String get map_noResults => 'Inga matchande noder';

  @override
  String get map_lineOfSight => 'Synlinje';

  @override
  String get map_losScreenTitle => 'Synlinje';

  @override
  String get map_noNodesWithLocation => 'Inga noder med platsinformation';

  @override
  String get map_nodesNeedGps =>
      'Noder måste dela sina GPS-koordinater\nför att visas på kartan';

  @override
  String map_nodesCount(int count) {
    return 'Noder: $count';
  }

  @override
  String map_pinsCount(int count) {
    return 'Nålar: $count';
  }

  @override
  String get map_chat => 'Chatt';

  @override
  String get map_repeater => 'Repeater';

  @override
  String get map_room => 'Rum';

  @override
  String get map_sensor => 'Sensor';

  @override
  String get map_pinDm => 'Nål (DM)';

  @override
  String get map_pinPrivate => 'Nål (privat)';

  @override
  String get map_pinPublic => 'Nål (offentlig)';

  @override
  String get map_lastSeen => 'Senast sedd';

  @override
  String get map_disconnectConfirm =>
      'Är du säker på att du vill koppla från enheten?';

  @override
  String get map_from => 'Från';

  @override
  String get map_source => 'Källa';

  @override
  String get map_flags => 'Flaggor';

  @override
  String get map_type => 'Typ';

  @override
  String get map_path => 'Rutt';

  @override
  String get map_location => 'Plats';

  @override
  String get map_estLocation => 'Ungef. plats';

  @override
  String get map_publicKey => 'Publik nyckel';

  @override
  String get map_publicKeyPrefixHint => 't.ex. ab12';

  @override
  String get map_shareMarkerHere => 'Dela markör här';

  @override
  String get map_setAsMyLocation => 'Ange som min plats';

  @override
  String get map_pinLabel => 'Nålens etikett';

  @override
  String get map_label => 'Etikett';

  @override
  String get map_pointOfInterest => 'Plats av intresse';

  @override
  String get map_sendToContact => 'Skicka till kontakt';

  @override
  String get map_sendToChannel => 'Skicka till kanal';

  @override
  String get map_noChannelsAvailable => 'Inga kanaler tillgängliga';

  @override
  String get map_publicLocationShare => 'Offentlig platsdelning';

  @override
  String map_publicLocationShareConfirm(String channelLabel) {
    return 'Du håller på att dela en plats i $channelLabel. Denna kanal är offentlig och alla med PSK kan se den.';
  }

  @override
  String get map_connectToShareMarkers =>
      'Anslut till en enhet för att dela markörer';

  @override
  String get map_filterNodes => 'Filtrera noder';

  @override
  String get map_nodeTypes => 'Nodtyper';

  @override
  String get map_chatNodes => 'Chattnoder';

  @override
  String get map_repeaters => 'Repeatrar';

  @override
  String get map_otherNodes => 'Andra noder';

  @override
  String get map_showOverlaps => 'Repeater-nyckelöverlappningar';

  @override
  String get map_keyPrefix => 'Nyckelprefix';

  @override
  String get map_filterByKeyPrefix => 'Filtrera efter nyckelprefix';

  @override
  String get map_publicKeyPrefix => 'Prefix för publik nyckel';

  @override
  String get map_markers => 'Markörer';

  @override
  String get map_showSharedMarkers => 'Visa delade markörer';

  @override
  String get map_showGuessedLocations => 'Visa gissade nodplatser';

  @override
  String get map_showDiscoveryContacts => 'Visa Discovery-kontakter';

  @override
  String get map_guessedLocation => 'Gissad plats';

  @override
  String get map_lastSeenTime => 'Tid senast sedd';

  @override
  String get map_sharedPin => 'Delad nål';

  @override
  String get map_sharedAt => 'Delad';

  @override
  String get map_joinRoom => 'Gå med i rum';

  @override
  String get map_manageRepeater => 'Hantera repeater';

  @override
  String get map_tapToAdd =>
      'Tryck på noder för att lägga till dem i sökvägen.';

  @override
  String get map_runTrace => 'Kör sökvägsspårning';

  @override
  String get map_runTraceWithReturnPath => 'Gå tillbaka på samma väg';

  @override
  String get map_removeLast => 'Ta bort sista';

  @override
  String get map_pathTraceCancelled => 'Sökvägsspårning avbruten.';

  @override
  String get map_regionRequestPathMustEndWithTarget =>
      'Rutten måste sluta vid målrepeatern.';

  @override
  String get map_wardrive => 'Wardrive';

  @override
  String get map_wardriveStart => 'Starta';

  @override
  String get map_wardriveStop => 'Stoppa';

  @override
  String get map_wardriveZeroHopDiscovery => 'Upptäckt utan hopp';

  @override
  String get map_wardriveDiscoverySent =>
      'Wardrive discovery-begäran har skickats.';

  @override
  String get map_wardriveUploadCancelled =>
      'Wardrive-uppladdningen har avbrutits.';

  @override
  String map_wardriveDiscoveryFailed(String error) {
    return 'Wardrive discovery misslyckades: $error';
  }

  @override
  String map_wardriveRequests(int requests, int responses) {
    return 'Begäranden: $requests  Svar: $responses';
  }

  @override
  String map_wardriveLastRequest(String time) {
    return 'Senaste begäran: $time';
  }

  @override
  String get map_wardrivePhoneGpsNotUpdated =>
      'Telefonens GPS: inte uppdaterad än';

  @override
  String map_wardrivePhoneGpsError(String error) {
    return 'Telefonens GPS: $error';
  }

  @override
  String map_wardrivePhoneGps(String latitude, String longitude) {
    return 'Telefonens GPS: $latitude, $longitude';
  }

  @override
  String get map_wardriveNoResponses => 'Inga discovery-svar ännu.';

  @override
  String get map_wardriveDataTooltip => 'Wardrive-data';

  @override
  String get map_wardriveUploadData => 'Ladda upp data';

  @override
  String get map_wardriveManageUploadSites => 'Hantera uppladdningsplatser';

  @override
  String get map_wardriveAutoUpload => 'Automatisk uppladdning';

  @override
  String get map_wardriveReUpload => 'Ladda upp igen';

  @override
  String get map_wardriveScreenWakelock => 'Håll skärmen tänd';

  @override
  String get map_wardriveExport => 'Exportera';

  @override
  String get map_wardriveImport => 'Importera';

  @override
  String get map_wardriveAutoDiscovery => 'Automatisk discovery';

  @override
  String get map_wardriveSecondsSuffix => 's';

  @override
  String get map_wardriveSamplesNoNew => 'Inga nya sampel att ladda upp';

  @override
  String map_wardriveSamplesSaved(int count) {
    return 'Sparade sampel: $count';
  }

  @override
  String map_wardriveAutoDiscoveryError(String error) {
    return 'Automatisk discovery: $error';
  }

  @override
  String map_wardriveSampleSaveError(String error) {
    return 'Sparande av sampel: $error';
  }

  @override
  String map_wardriveCoverageCells(int count) {
    return 'Täckningsceller: $count';
  }

  @override
  String get map_wardriveCoverageResolution => 'Täckningens detaljnivå';

  @override
  String get map_wardriveCoverageResolutionPrompt =>
      'Välj storlek på täckningsblocken (storlek = blockets sida):';

  @override
  String get map_wardriveCoverageRegional => 'Regional';

  @override
  String get map_wardriveCoverageRegionalSubtitle => '~20 km (precision 4)';

  @override
  String get map_wardriveCoverageCity => 'Stadsnivå';

  @override
  String get map_wardriveCoverageCitySubtitle => '~5 km (precision 5)';

  @override
  String get map_wardriveCoverageNeighborhood => 'Stadsdel';

  @override
  String get map_wardriveCoverageNeighborhoodSubtitle =>
      '~1,2 km (precision 6)';

  @override
  String get map_wardriveCoverageStreet => 'Gatunivå';

  @override
  String get map_wardriveCoverageStreetSubtitle => '~153 m (precision 7)';

  @override
  String get map_wardriveCoverageBuilding => 'Byggnadsnivå';

  @override
  String get map_wardriveCoverageBuildingSubtitle => '~38 m (precision 8)';

  @override
  String get map_wardriveAutoUploadEnabled =>
      'Automatisk uppladdning aktiverad.';

  @override
  String get map_wardriveAutoUploadDisabled =>
      'Automatisk uppladdning inaktiverad.';

  @override
  String get map_wardriveNoSamplesToUpload =>
      'Inga wardrive-sampel att ladda upp.';

  @override
  String get map_wardriveUploadingSamples => 'Laddar upp sampel...';

  @override
  String map_wardriveUploadingTo(String site) {
    return 'Laddar upp till $site...';
  }

  @override
  String map_wardriveUploadBatch(int current, int total) {
    return 'Batch $current av $total';
  }

  @override
  String map_wardriveUploadSamplesProgress(int sent, int total) {
    return 'Skickar $sent av $total';
  }

  @override
  String map_wardriveUploadTarget(String site) {
    return 'Mål: $site';
  }

  @override
  String get map_wardriveUploadWaitingConnection => 'Väntar på anslutning';

  @override
  String get map_wardriveUploadConnectionEstablished =>
      'Anslutningen är upprättad, laddar upp';

  @override
  String get map_wardriveUploadProcessingServer =>
      'Data har laddats upp, servern bearbetar dem';

  @override
  String map_wardriveUploadServerResponse(int statusCode) {
    return 'Servern har bearbetat data, svar $statusCode';
  }

  @override
  String get map_wardriveUploadTimeoutTreatedAsSuccess =>
      'Uppladdningen överskred timeouten; markerad som skickad för den här platsen';

  @override
  String map_wardriveUploadServerError(int statusCode) {
    return 'Serverfel $statusCode';
  }

  @override
  String map_wardriveUploadRequestError(String error) {
    return 'Uppladdningsfel: $error';
  }

  @override
  String map_wardriveUploadFailed(String error) {
    return 'Wardrive-uppladdningen misslyckades: $error';
  }

  @override
  String get map_wardriveUploadComplete => 'Uppladdningen är klar';

  @override
  String get map_wardriveUploadResults => 'Uppladdningsresultat';

  @override
  String map_wardriveSamplesUploaded(int count) {
    return 'Uppladdade sampel: $count';
  }

  @override
  String get map_wardriveSelectUploadSites =>
      'Välj vilka platser som data ska laddas upp till:';

  @override
  String get map_wardriveNoUploadSitesConfigured =>
      'Inga uppladdningsplatser har konfigurerats';

  @override
  String get map_wardriveAddSite => 'Lägg till webbplats';

  @override
  String get map_wardriveUploadSitesUpdated =>
      'Uppladdningsplatserna har uppdaterats.';

  @override
  String get map_wardriveAddUploadSite => 'Lägg till uppladdningsplats';

  @override
  String get map_wardriveEditUploadSite => 'Redigera uppladdningsplats';

  @override
  String get map_wardriveNameLabel => 'Namn';

  @override
  String get map_wardriveUrlLabel => 'URL';

  @override
  String get map_wardriveUploadBatchSize => 'Storlek på uppladdningsbatchen';

  @override
  String map_wardriveUploadBatchSizeInvalid(int min, int max) {
    return 'Använd ett värde från $min till $max';
  }

  @override
  String get map_wardriveTreatTimeoutAsSuccess => 'Betrakta timeout som lyckad';

  @override
  String get map_wardriveNameRequired => 'Namnet är obligatoriskt';

  @override
  String get map_wardriveNameExists => 'Namnet finns redan';

  @override
  String get map_wardriveValidUrlRequired => 'En giltig URL krävs';

  @override
  String get map_wardriveDeleteSite => 'Ta bort webbplats';

  @override
  String map_wardriveDeleteSiteConfirm(String name) {
    return 'Ta bort «$name»?';
  }

  @override
  String get map_wardriveNoSamplesToExport =>
      'Inga wardrive-sampel att exportera.';

  @override
  String get map_wardriveExportShareText =>
      'wardrive-sampel från meshcore-open';

  @override
  String get map_wardriveSamplesExported =>
      'Wardrive-sampel har exporterats till en JSON-fil.';

  @override
  String map_wardriveExportFailed(String error) {
    return 'Wardrive-exporten misslyckades: $error';
  }

  @override
  String get map_wardriveImportSamples => 'Importera wardrive-sampel';

  @override
  String get map_wardriveImportHint =>
      'Klistra in den exporterade wardrive-JSON:en här';

  @override
  String get map_wardriveNoNewSamplesImported =>
      'Inga nya wardrive-sampel har importerats.';

  @override
  String map_wardriveSamplesImported(int count) {
    return 'Importerade wardrive-sampel: $count.';
  }

  @override
  String map_wardriveImportFailed(String error) {
    return 'Wardrive-importen misslyckades: $error';
  }

  @override
  String get map_wardriveNoSamplesToClear => 'Inga wardrive-sampel att rensa.';

  @override
  String get map_wardriveClearSamplesTitle => 'Rensa wardrive-sampel?';

  @override
  String map_wardriveClearSamplesConfirm(int count) {
    return 'Detta tar bort $count sparade sampel från den här enheten.';
  }

  @override
  String get map_wardriveSamplesCleared => 'Wardrive-sampel har rensats.';

  @override
  String get map_wardriveRepNoLocation =>
      'Repeatern har inte angett sin position';

  @override
  String map_wardriveDiscoveryWait(Object seconds) {
    return 'Vänta $seconds sekunder innan du försöker igen';
  }

  @override
  String get map_wardriveFollowMe => 'Följ min position';

  @override
  String get map_wardriveDeleteBlock => 'Ta bort block';

  @override
  String get map_wardriveInBackground => 'Kör i bakgrunden';

  @override
  String get map_wardriveContinuousGPS => 'Kontinuerlig GPS-position';

  @override
  String get map_wardriveShowRepeaterCoverage => 'Visa täckningsblocken';

  @override
  String get map_wardriveHideRepeaterCoverage => 'Dölj täckningsblocken';

  @override
  String get mapCache_title => 'Offline-kartcache';

  @override
  String get mapCache_selectAreaFirst => 'Välj ett område att cachera först';

  @override
  String get mapCache_noTilesToDownload =>
      'Inga rutor att ladda ner för detta område';

  @override
  String get mapCache_downloadTilesTitle => 'Ladda ner rutor';

  @override
  String mapCache_downloadTilesPrompt(int count) {
    return 'Ladda ner $count rutor för offlineanvändning?';
  }

  @override
  String get mapCache_downloadAction => 'Ladda ner';

  @override
  String mapCache_cachedTiles(int count) {
    return '$count rutor cachade';
  }

  @override
  String mapCache_cachedTilesWithFailed(int downloaded, int failed) {
    return '$downloaded rutor cachade ($failed misslyckades)';
  }

  @override
  String get mapCache_clearOfflineCacheTitle => 'Rensa offline-cache';

  @override
  String get mapCache_clearOfflineCachePrompt =>
      'Ta bort alla cachade kartrutor?';

  @override
  String get mapCache_offlineCacheCleared => 'Offline-cache rensad';

  @override
  String get mapCache_noAreaSelected => 'Ingen area markerad';

  @override
  String get mapCache_cacheArea => 'Cacheområde';

  @override
  String get mapCache_useCurrentView => 'Använd aktuell vy';

  @override
  String get mapCache_zoomRange => 'Zoomintervall';

  @override
  String mapCache_estimatedTiles(int count) {
    return 'Uppskattat antal rutor: $count';
  }

  @override
  String mapCache_downloadedTiles(int completed, int total) {
    return 'Nedladdat $completed / $total';
  }

  @override
  String get mapCache_downloadTilesButton => 'Ladda ner rutor';

  @override
  String get mapCache_clearCacheButton => 'Rensa cache';

  @override
  String mapCache_failedDownloads(int count) {
    return 'Misslyckade nedladdningar: $count';
  }

  @override
  String get mapCache_cachedTilesLabel => 'Cachade rutor';

  @override
  String get mapCache_cachedTileSummaryLabel =>
      'Sammanfattning av cachade rutor';

  @override
  String mapCache_bulkDownloadDisabledForSource(String source) {
    return 'Offline-massnedladdningar är avstängda för $source.';
  }

  @override
  String mapCache_bulkDownloadDisabledInConfig(String source) {
    return 'Offline-massnedladdningar för $source är avstängda i den här appkonfigurationen.';
  }

  @override
  String mapCache_summarySource(String source) {
    return 'Källa: $source';
  }

  @override
  String mapCache_summaryCachedTilesForSource(int count) {
    return 'Cachade rutor för källan: $count';
  }

  @override
  String mapCache_summaryCachedInSelection(int count) {
    return 'Cachade i valt område/zoom: $count';
  }

  @override
  String mapCache_summaryApproxCacheSize(String size) {
    return 'Ungefärlig cachestorlek: $size';
  }

  @override
  String mapCache_boundsLabel(
    String north,
    String south,
    String east,
    String west,
  ) {
    return 'N $north, S $south, Ö $east, V $west';
  }

  @override
  String get time_justNow => 'Precis nu';

  @override
  String time_minutesAgo(int minutes) {
    return '$minutes min sedan';
  }

  @override
  String time_hoursAgo(int hours) {
    return '$hours tim sedan';
  }

  @override
  String time_daysAgo(int days) {
    return '$days d sedan';
  }

  @override
  String get time_hour => 'timme';

  @override
  String get time_hours => 'timmar';

  @override
  String get time_day => 'dag';

  @override
  String get time_days => 'dagar';

  @override
  String get time_week => 'vecka';

  @override
  String get time_weeks => 'veckor';

  @override
  String get time_month => 'månad';

  @override
  String get time_months => 'månader';

  @override
  String get time_minutes => 'minuter';

  @override
  String get time_allTime => 'Alla tider';

  @override
  String get dialog_disconnect => 'Koppla från';

  @override
  String get dialog_disconnectConfirm =>
      'Är du säker på att du vill koppla från enheten?';

  @override
  String get login_repeaterLogin => 'Inloggning på repeater';

  @override
  String get login_roomLogin => 'Inloggning på rumsserver';

  @override
  String get login_password => 'Lösenord';

  @override
  String get login_enterPassword => 'Ange lösenord';

  @override
  String get login_savePassword => 'Spara lösenord';

  @override
  String get login_savePasswordSubtitle =>
      'Lösenord kommer att lagras säkert på enheten.';

  @override
  String get login_repeaterDescription =>
      'Ange repeaterns lösenord för gäst- eller administratörsåtkomst.';

  @override
  String get login_roomDescription =>
      'Ange rummets lösenord för gäst- eller administratörsåtkomst.';

  @override
  String get login_routing => 'Routning';

  @override
  String get login_routingMode => 'Ruttläge';

  @override
  String get login_autoUseSavedPath => 'Automatisk (använd sparad sökväg)';

  @override
  String get login_forceFloodMode => 'Tvinga läget flood';

  @override
  String get login_managePaths => 'Hantera sökvägar';

  @override
  String get login_login => 'Logga in';

  @override
  String login_attempt(int current, int max) {
    return 'Försök $current/$max';
  }

  @override
  String login_failed(String error) {
    return 'Inloggning misslyckades: $error';
  }

  @override
  String get login_failedMessage =>
      'Inloggning misslyckades. Antingen är lösenordet fel eller så går det inte att nå repeatern.';

  @override
  String get common_reload => 'Ladda om';

  @override
  String get path_currentPathLabel => 'Nuvarande sökväg';

  @override
  String get path_noRepeatersFound =>
      'Inga repeatrar eller rumsservrar hittades.';

  @override
  String get repeater_management => 'Repeaterhantering';

  @override
  String get room_management => 'Rumsserverhantering';

  @override
  String get repeater_guest => 'Information om repeatern';

  @override
  String get room_guest => 'Information om servern';

  @override
  String get repeater_managementTools => 'Administrationsverktyg';

  @override
  String get repeater_guestTools => 'Gästverktyg';

  @override
  String get repeater_status => 'Status';

  @override
  String get repeater_statusSubtitle =>
      'Visa repeaterns status, statistik och grannar';

  @override
  String get repeater_telemetry => 'Telemetri';

  @override
  String get repeater_telemetrySubtitle =>
      'Visa telemetri för sensorer och systemstatistik';

  @override
  String get repeater_cli => 'CLI';

  @override
  String get repeater_cliSubtitle => 'Skicka kommandon till repeatern';

  @override
  String get repeater_neighbors => 'Grannar';

  @override
  String get repeater_neighborsSubtitle => 'Visa zero-hop-grannar.';

  @override
  String get repeater_settings => 'Inställningar';

  @override
  String get repeater_settingsSubtitle => 'Konfigurera repeaterns parametrar';

  @override
  String get repeater_clockSyncAfterLogin =>
      'Synkronisera klockan efter inloggning';

  @override
  String get repeater_clockSyncAfterLoginSubtitle =>
      'Skicka automatiskt \"clock sync\" efter en lyckad inloggning.';

  @override
  String get repeater_statusTitle => 'Repeaterstatus';

  @override
  String get repeater_routingMode => 'Ruttläge';

  @override
  String get repeater_refresh => 'Uppdatera';

  @override
  String get repeater_statusRequestTimeout =>
      'Tidsgränsen för statusförfrågan överskreds.';

  @override
  String repeater_errorLoadingStatus(String error) {
    return 'Fel vid inläsning av status: $error';
  }

  @override
  String get repeater_systemInformation => 'Systeminformation';

  @override
  String get repeater_battery => 'Batteri';

  @override
  String get repeater_clockAtLogin => 'Klocka (vid inloggning)';

  @override
  String get repeater_uptime => 'Drifttid';

  @override
  String get repeater_queueLength => 'Köns längd';

  @override
  String get repeater_debugFlags => 'Felsökningsflaggor';

  @override
  String get repeater_radioStatistics => 'Radiostatistik';

  @override
  String get repeater_lastRssi => 'Senaste RSSI';

  @override
  String get repeater_lastSnr => 'Senaste SNR';

  @override
  String get repeater_noiseFloor => 'Brusgolv';

  @override
  String get repeater_txAirtime => 'TX-sändningstid';

  @override
  String get repeater_rxAirtime => 'RX-mottagningstid';

  @override
  String get repeater_chanUtil => 'Användning av kanal';

  @override
  String get repeater_packetStatistics => 'Paketstatistik';

  @override
  String get repeater_sent => 'Skickat';

  @override
  String get repeater_received => 'Mottaget';

  @override
  String get repeater_duplicates => 'Dubbletter';

  @override
  String get repeater_packetErrors => 'Paketfel';

  @override
  String repeater_daysHoursMinsSecs(
    int days,
    int hours,
    int minutes,
    int seconds,
  ) {
    return '$days dagar $hours timmar $minutes minuter $seconds sekunder';
  }

  @override
  String repeater_packetTxTotal(int total, String flood, String direct) {
    return 'Totalt: $total, Flood: $flood, Direkt: $direct';
  }

  @override
  String repeater_packetRxTotal(int total, String flood, String direct) {
    return 'Totalt: $total, Flood: $flood, Direkt: $direct';
  }

  @override
  String repeater_duplicatesFloodDirect(String flood, String direct) {
    return 'Flood: $flood, Direkt: $direct';
  }

  @override
  String repeater_duplicatesTotal(int total) {
    return 'Totalt: $total';
  }

  @override
  String get repeater_settingsTitle => 'Repeaterinställningar';

  @override
  String get repeater_basicSettings => 'Grundinställningar';

  @override
  String get repeater_repeaterName => 'Repeaterns namn';

  @override
  String get repeater_repeaterNameHelper => 'Visningsnamn för denna repeater';

  @override
  String get repeater_adminPassword => 'Adminlösenord';

  @override
  String get repeater_adminPasswordHelper => 'Lösenord med full åtkomst';

  @override
  String get repeater_guestPassword => 'Gästlösenord';

  @override
  String get repeater_guestPasswordHelper =>
      'Lösenord för skrivskyddad åtkomst';

  @override
  String get repeater_radioSettings => 'Radioinställningar';

  @override
  String get repeater_frequencyMhz => 'Frekvens (MHz)';

  @override
  String get repeater_frequencyHelper => '300–2500 MHz';

  @override
  String get repeater_txPower => 'TX-effekt';

  @override
  String get repeater_txPowerHelper => '1-30 dBm';

  @override
  String get repeater_bandwidth => 'Bandbredd';

  @override
  String get repeater_spreadingFactor => 'Spridningsfaktor';

  @override
  String get repeater_codingRate => 'Kodningsgrad';

  @override
  String get repeater_locationSettings => 'Platsinställningar';

  @override
  String get repeater_latitude => 'Latitud';

  @override
  String get repeater_latitudeHelper => 'Decimalgrader (t.ex. 37.7749)';

  @override
  String get repeater_longitude => 'Längdgrad';

  @override
  String get repeater_longitudeHelper => 'Decimalgrader (t.ex. -122.4194)';

  @override
  String get repeater_features => 'Funktioner';

  @override
  String get repeater_packetForwarding => 'Vidarebefordran av paket';

  @override
  String get repeater_packetForwardingSubtitle =>
      'Låt repeatern vidarebefordra paket';

  @override
  String get repeater_guestAccess => 'Gäståtkomst';

  @override
  String get repeater_guestAccessSubtitle =>
      'Tillåt läsbehörigheter för gäster.';

  @override
  String get repeater_privacyMode => 'Privatläge';

  @override
  String get repeater_privacyModeSubtitle => 'Dölj namn/plats i adverts';

  @override
  String get repeater_advertisementSettings => 'Advertinställningar';

  @override
  String get repeater_localAdvertInterval => 'Lokalt advertintervall';

  @override
  String repeater_localAdvertIntervalMinutes(int minutes) {
    return '$minutes minuter';
  }

  @override
  String get repeater_floodAdvertInterval => 'Flood-advertintervall';

  @override
  String repeater_floodAdvertIntervalHours(int hours) {
    return '$hours timmar';
  }

  @override
  String get repeater_encryptedAdvertInterval => 'Krypterat advertintervall';

  @override
  String get repeater_dangerZone => 'Faraområde';

  @override
  String get repeater_rebootRepeater => 'Starta om repeatern';

  @override
  String get repeater_rebootRepeaterSubtitle => 'Starta om repeaterenheten';

  @override
  String get repeater_rebootRepeaterConfirm =>
      'Är du säker på att du vill starta om denna repeater?';

  @override
  String get repeater_regenerateIdentityKey => 'Generera om identitetsnyckel';

  @override
  String get repeater_regenerateIdentityKeySubtitle =>
      'Generera ett nytt publikt/privat nyckelpar';

  @override
  String get repeater_regenerateIdentityKeyConfirm =>
      'Detta kommer att generera en ny identitet för repeatern. Fortsätta?';

  @override
  String get repeater_eraseFileSystem => 'Radera filsystem';

  @override
  String get repeater_eraseFileSystemSubtitle =>
      'Formatera repeaterns filsystem';

  @override
  String get repeater_eraseFileSystemConfirm =>
      'VARNING: Detta kommer att radera all data på repeatern. Detta kan inte ångras!';

  @override
  String get repeater_eraseSerialOnly =>
      'Radering är endast tillgänglig via seriell konsol.';

  @override
  String repeater_commandSent(String command) {
    return 'Kommandot skickades: $command';
  }

  @override
  String repeater_errorSendingCommand(String error) {
    return 'Fel vid skickande av kommando: $error';
  }

  @override
  String get repeater_confirm => 'Bekräfta';

  @override
  String get repeater_settingsSaved =>
      'Inställningarna sparades framgångsrikt.';

  @override
  String get repeater_rxGain => 'Förhöjd RX-förstärkning';

  @override
  String get repeater_rxGainHelper =>
      'Ökad känslighet, högre strömförbrukning (endast för SX1262/SX1268)';

  @override
  String get repeater_refreshRxGain => 'Uppdatera förhöjd RX-förstärkning';

  @override
  String get repeater_multiAcks => 'Flera bekräftelser';

  @override
  String get repeater_multiAcksSubtitle =>
      'Bekräfta meddelanden via flera vägar för bättre leverans.';

  @override
  String get repeater_refreshMultiAcks => 'Uppdatera multi-ACK';

  @override
  String get repeater_networkHealth => 'Nätverkets hälsa';

  @override
  String get repeater_loopDetect => 'Identifiering av loopar';

  @override
  String get repeater_loopDetectHelper =>
      'Kasta flood-paket som ser ut som routingloopar';

  @override
  String get repeater_loopDetectOff => 'Av';

  @override
  String get repeater_loopDetectMinimal => 'Minimal';

  @override
  String get repeater_loopDetectModerate => 'Måttlig';

  @override
  String get repeater_loopDetectStrict => 'Strikt';

  @override
  String get repeater_dutyCycle => 'Arbetscykel';

  @override
  String get repeater_dutyCycleHelper => 'Maximal procentandel av sändningstid';

  @override
  String repeater_dutyCyclePercent(int percent) {
    return '$percent%';
  }

  @override
  String get repeater_ownerInfo => 'Information om operatören';

  @override
  String get repeater_ownerInfoHelper =>
      'Offentliga metadata för denna repeater';

  @override
  String get repeater_refreshOwnerInfo => 'Uppdatera information om operatören';

  @override
  String get repeater_floodMax => 'Max antal hopp för flood';

  @override
  String get repeater_floodMaxHelper =>
      'Maximalt antal hopp ett flood-paket kan färdas (0-64)';

  @override
  String get repeater_advancedSettings => 'Avancerad';

  @override
  String get repeater_advancedSettingsSubtitle =>
      'Finjusteringar för erfarna operatörer';

  @override
  String get repeater_pathHashMode => 'Hash-läge för sökväg';

  @override
  String get repeater_pathHashModeHelper =>
      'Byte som används för att koda denna repeaters ID i taggar för flood-väg/loopdetektering. 0=1 byte (256 ID:n, upp till 64 hopp), 1=2 byte (65 000 ID:n, upp till 32 hopp), 2=3 byte (16 miljoner ID:n, upp till 21 hopp). Firmware före v1.14 använde alltid 1-byte-vägar; v1.14 och nyare kan konfigureras för 2- eller 3-byte-vägar.';

  @override
  String get repeater_keySettings => 'Ändra identitetsnycklar';

  @override
  String get repeater_keySettingsSubtitle =>
      'Ändra det publika/privata nyckelparet';

  @override
  String get repeater_prvKey => 'Privat nyckel';

  @override
  String get repeater_prvKeyHelper =>
      'En ny privat nyckel för repeatern, en hexadecimal sträng med 128 tecken.';

  @override
  String get repeater_generatePrvKey => 'Generera ett slumpmässigt nyckelpar';

  @override
  String get repeater_stopGeneratingPrvKey =>
      'Avbryt sökningen efter nyckelpar';

  @override
  String get repeater_pubKey => 'Publik nyckel';

  @override
  String get repeater_pubKeyHelper =>
      'Detta är den publika nyckeln som hör till den genererade privata nyckeln. Den kan inte anges direkt.';

  @override
  String get repeater_pubKeyPrefix => 'Önskat prefix';

  @override
  String repeater_pubKeyPrefixHelper(int tries) {
    return 'Sök efter en publik nyckel som börjar med dessa hexadecimala tecken. Förväntat antal försök: $tries.';
  }

  @override
  String get repeater_txDelay => 'TX-fördröjning för flood';

  @override
  String get repeater_txDelayHelper =>
      'Återöverföringsintervall för flood-trafik, som en multiplikator av paketets överföringstid (0-2, standard 0,5). Högre värde = färre kollisioner, men långsammare leverans.';

  @override
  String get repeater_directTxDelay => 'Direkt TX-fördröjning';

  @override
  String get repeater_directTxDelayHelper =>
      'Återöverföringsintervall för direkt (icke-flood) trafik, som en multiplikator av paketets överföringstid (0-2, standard 0,3).';

  @override
  String get repeater_intThresh => 'Tröskelvärde för störning';

  @override
  String get repeater_intThreshHelper =>
      'Tröskelvärde som skickas till radions kalibrering av brusgolvet så att den filtrerar bort störningar över denna nivå. 0 stänger av – höj bara om du ser RX-fel i ett störningsfyllt frekvensband.';

  @override
  String get repeater_agcResetInterval => 'Återställningsintervall för AGC';

  @override
  String get repeater_agcResetIntervalHelper =>
      'Hur ofta radions automatiska förstärkningsreglering ska återställas för att återhämta sig från ett fastlåst förstärkningsläge. Sekunder, avrundat nedåt till en multipel av 4. 0 stänger av periodiska återställningar.';

  @override
  String get repeater_actionsTitle => 'Åtgärder';

  @override
  String get repeater_sendAdvert => 'Skicka flood-advert';

  @override
  String get repeater_sendAdvertSubtitle =>
      'Sänd en flood-advert genom nätverket';

  @override
  String get repeater_sendAdvertZeroHop => 'Skicka zero-hop-advert';

  @override
  String get repeater_sendAdvertZeroHopSubtitle =>
      'Sänd en advert på ett hopp (utan reläer)';

  @override
  String get repeater_clockSync => 'Synkronisera klockan nu';

  @override
  String get repeater_clockSyncSubtitle =>
      'Ställ din telefons tid till repeatern.';

  @override
  String repeater_actionSucceeded(String action) {
    return '$action lyckades';
  }

  @override
  String repeater_actionFailed(String action, String error) {
    return '$action misslyckades: $error';
  }

  @override
  String get repeater_settingsSavedRebootNeeded =>
      'Inställningar sparade – starta om repeatern för att tillämpa dem';

  @override
  String repeater_settingsPartialFailure(String failures) {
    return 'Vissa inställningar misslyckades: $failures';
  }

  @override
  String repeater_errorSavingSettings(String error) {
    return 'Fel vid sparande av inställningar: $error';
  }

  @override
  String get repeater_refreshBasicSettings => 'Uppdatera grundinställningar';

  @override
  String get repeater_refreshRadioSettings => 'Uppdatera radioinställningar';

  @override
  String get repeater_refreshTxPower => 'Uppdatera TX-effekt';

  @override
  String get repeater_refreshPacketForwarding =>
      'Uppdatera vidarebefordran av paket';

  @override
  String get repeater_refreshGuestAccess => 'Uppdatera gäståtkomst';

  @override
  String get repeater_refreshPrivacyMode => 'Uppdatera privatläge';

  @override
  String repeater_refreshed(String label) {
    return '$label har uppdaterats';
  }

  @override
  String repeater_errorRefreshing(String label) {
    return 'Fel vid uppdatering av $label';
  }

  @override
  String get repeater_cliTitle => 'Repeaterns CLI';

  @override
  String get repeater_debugNextCommand => 'Felsök nästa kommando';

  @override
  String get repeater_commandHelp => 'Kommandohjälp';

  @override
  String get repeater_clearHistory => 'Rensa historik';

  @override
  String get repeater_noCommandsSent => 'Inga kommandon har skickats ännu';

  @override
  String get repeater_typeCommandOrUseQuick =>
      'Skriv ett kommando nedan eller använd snabbkommandon';

  @override
  String get repeater_enterCommandHint => 'Ange kommando...';

  @override
  String get repeater_previousCommand => 'Tidigare kommando';

  @override
  String get repeater_nextCommand => 'Nästa kommando';

  @override
  String get repeater_enterCommandFirst => 'Ange ett kommando först';

  @override
  String get repeater_cliCommandFrameTitle => 'CLI-kommandoram';

  @override
  String repeater_cliCommandError(String error) {
    return 'Fel: $error';
  }

  @override
  String get repeater_cliQuickGetName => 'Hämta namn';

  @override
  String get repeater_cliQuickGetRadio => 'Hämta radio';

  @override
  String get repeater_cliQuickGetTx => 'Hämta TX';

  @override
  String get repeater_cliQuickNeighbors => 'Grannar';

  @override
  String get repeater_cliQuickVersion => 'Version';

  @override
  String get repeater_cliQuickAdvertise => 'Skicka advert';

  @override
  String get repeater_cliQuickClock => 'Klocka';

  @override
  String get repeater_cliQuickClockSync => 'Synkronisera klocka';

  @override
  String get repeater_cliQuickDiscovery => 'Upptäck grannar';

  @override
  String get repeater_cliHelpAdvert => 'Skickar ett advert-paket';

  @override
  String get repeater_cliHelpReboot =>
      'Startar om enheten. (notera, du får kanske \'Timeout\' vilket är normalt)';

  @override
  String get repeater_cliHelpClock =>
      'Visar aktuell tid enligt enhetens klocka.';

  @override
  String get repeater_cliHelpPassword =>
      'Ställer in ett nytt administratörslösenord för enheten.';

  @override
  String get repeater_cliHelpVersion =>
      'Visar enhetsversion och firmwarens byggdatum.';

  @override
  String get repeater_cliHelpClearStats =>
      'Återställer olika statistikräknare till noll.';

  @override
  String get repeater_cliHelpSetAf => 'Ställer in sändningstidsfaktorn.';

  @override
  String get repeater_cliHelpSetTx =>
      'Ställer LoRa-sändningseffekten i dBm. (starta om för att tillämpa)';

  @override
  String get repeater_cliHelpSetRepeat =>
      'Aktiverar eller inaktiverar repeaterrollen för denna nod.';

  @override
  String get repeater_cliHelpSetAllowReadOnly =>
      '(Rumsserver) Om \'on\' tillåts inloggning med tomt lösenord, men det går inte att posta i rummet. (endast läsning)';

  @override
  String get repeater_cliHelpSetFloodMax =>
      'Ställer in det maximala antalet hopp för inkommande flood-paket (om >= max vidarebefordras inte paketet).';

  @override
  String get repeater_cliHelpSetIntThresh =>
      'Ställer in interferensgränsen (i dB). Standardvärdet är 14. Ställ in den på 0 för att inaktivera detektion av kanalinterferens.';

  @override
  String get repeater_cliHelpSetAgcResetInterval =>
      'Ställer in intervallet för att återställa den automatiska förstärkningsregleringen. Ställ in till 0 för att inaktivera.';

  @override
  String get repeater_cliHelpSetMultiAcks =>
      'Aktiverar eller inaktiverar funktionen \'dubbla ACKs\'.';

  @override
  String get repeater_cliHelpSetAdvertInterval =>
      'Ställer in tidsintervallet i minuter för att skicka ett lokalt (zero-hop) advert-paket. Ställ in på 0 för att inaktivera.';

  @override
  String get repeater_cliHelpSetFloodAdvertInterval =>
      'Ställer in tidsintervallet i timmar för att skicka ett advert-paket via flood. Ställ in på 0 för att inaktivera.';

  @override
  String get repeater_cliHelpSetGuestPassword =>
      'Ställer in/uppdaterar gästlösenordet. (för repeatrar kan gästinloggningar skicka \"Get Stats\"-förfrågan)';

  @override
  String get repeater_cliHelpSetName => 'Ställer in namnet i adverten.';

  @override
  String get repeater_cliHelpSetLat =>
      'Ställer in latituden som adverten visar på kartan. (decimalgrader)';

  @override
  String get repeater_cliHelpSetLon =>
      'Ställer in longituden som adverten visar på kartan (decimalgrader).';

  @override
  String get repeater_cliHelpSetRadio =>
      'Ställer in helt nya radioparametrar och sparar dem i inställningar. Kräver kommandot \"reboot\" för att tillämpas.';

  @override
  String get repeater_cliHelpSetRxDelay =>
      'Ställer in ett (experimentellt) basvärde (måste vara > 1 för effekt) för att applicera en liten fördröjning på mottagna paket, baserat på signalstyrka/poäng. Ställ in på 0 för att inaktivera.';

  @override
  String get repeater_cliHelpSetTxDelay =>
      'Ställer in en faktor som multipliceras med sändningstiden för ett paket i läget flood och med ett slumpmässigt slot-system för att fördröja dess vidarebefordran (för att minska risken för kollisioner).';

  @override
  String get repeater_cliHelpSetDirectTxDelay =>
      'Samma som txdelay, men för att applicera en slumpmässig fördröjning vid vidarebefordran av direktlägespaket.';

  @override
  String get repeater_cliHelpSetBridgeEnabled => 'Aktivera/Inaktivera brygga.';

  @override
  String get repeater_cliHelpSetBridgeDelay =>
      'Ställ in fördröjning innan paket sänds om.';

  @override
  String get repeater_cliHelpSetBridgeSource =>
      'Välj om bryggan ska återsända mottagna eller skickade paket.';

  @override
  String get repeater_cliHelpSetBridgeBaud =>
      'Ställ in baudhastigheten för seriell länk för rs232-bryggor.';

  @override
  String get repeater_cliHelpSetBridgeSecret =>
      'Ställ in bryggans hemlighet för espnow-bryggor.';

  @override
  String get repeater_cliHelpSetAdcMultiplier =>
      'Ställer in anpassad faktor för att justera rapporterad batterispänning (endast stödd på utvalda kort).';

  @override
  String get repeater_cliHelpTempRadio =>
      'Ställer temporära radioparametrar för det angivna antalet minuter, vilket återgår till de ursprungliga radioparametrarna efteråt. (sparar inte i inställningar).';

  @override
  String get repeater_cliHelpSetPerm =>
      'Ändrar ACL. Tar bort matchande post (efter pubkey-prefix) om \"permissions\" är noll. Lägger till en ny post om pubkey-hex har full längd och inte redan finns i ACL. Uppdaterar posten med matchande pubkey-prefix. Behörighetsbitarna varierar med firmware-rollen, men de två lägsta bitarna är: 0 (gäst), 1 (endast läsning), 2 (läsning och skrivning), 3 (administratör).';

  @override
  String get repeater_cliHelpGetBridgeType =>
      'Hämtar bryggtyp: none, rs232, espnow';

  @override
  String get repeater_cliHelpLogStart =>
      'Startar paketloggning till filsystemet.';

  @override
  String get repeater_cliHelpLogStop => 'Stoppar paketloggning till filsystem.';

  @override
  String get repeater_cliHelpLogErase =>
      'Raderar paketloggarna från filsystemet.';

  @override
  String get repeater_cliHelpNeighbors =>
      'Visar en lista över andra repeaternoder som hörts via zero-hop-adverts. Varje rad är id-prefix-hex:tidsstämpel:snr×4';

  @override
  String get repeater_cliHelpNeighborRemove =>
      'Tar bort den första matchande posten (efter pubkey-prefix (hex)) från grannlistan.';

  @override
  String get repeater_cliHelpRegion =>
      '(endast seriellt) Listar alla definierade regioner och aktuella flood-behörigheter.';

  @override
  String get repeater_cliHelpRegionLoad =>
      'OBS: detta är ett specialanrop med flera kommandon. Varje efterföljande kommando är ett regionsnamn (indenterat med blanksteg för att indikera en hierarkisk relation, med minst ett blanksteg). Avslutas genom att skicka en tom rad/kommando.';

  @override
  String get repeater_cliHelpRegionGet =>
      'Söker efter region med det givna namnprefixet (eller \"*\" för det globala scopet). Svarar med \"-> regionnamn (föräldernamn) \'F\'\"';

  @override
  String get repeater_cliHelpRegionPut =>
      'Lägger till eller uppdaterar en regionsdefinition med det angivna namnet.';

  @override
  String get repeater_cliHelpRegionRemove =>
      'Tar bort en regionsdefinition med det angivna namnet. (måste matcha exakt och inte ha några barnregioner)';

  @override
  String get repeater_cliHelpRegionAllowf =>
      'Ställer in \'F\'lood-behörigheten för den angivna regionen. (\'*\' för det globala/gamla scopet)';

  @override
  String get repeater_cliHelpRegionDenyf =>
      'Tar bort \'F\'lood-behörigheten för det angivna området. (OBS: rekommenderas inte att använda detta i detta skede på den globala/gamla omfattningen!!).';

  @override
  String get repeater_cliHelpRegionHome =>
      'Svarar med den aktuella \'hem\'-regionen. (Notera att detta ännu inte har tillämpats, reserverat för framtida användning).';

  @override
  String get repeater_cliHelpRegionHomeSet => 'Ställer in \'hemregionen\'.';

  @override
  String get repeater_cliHelpRegionSave =>
      'Sparar regionlistan/kartan till lagring.';

  @override
  String get repeater_cliHelpGps =>
      'Visar GPS-status. Om GPS är avstängd svarar den endast med \"off\", annars svarar den med \"on\", status, fix, antal satelliter.';

  @override
  String get repeater_cliHelpGpsOnOff =>
      'Aktiverar/inaktiverar GPS-strömsättningen.';

  @override
  String get repeater_cliHelpGpsSync =>
      'Synkroniserar nodens tid med GPS-klockan.';

  @override
  String get repeater_cliHelpGpsSetLoc =>
      'Ställer nodens position till GPS-koordinater och sparar inställningar.';

  @override
  String get repeater_cliHelpGpsAdvert =>
      'Visar nodens konfiguration för plats i adverts:\n- none: inkludera inte plats i adverts\n- share: dela GPS-plats (från SensorManager)\n- prefs: använd platsen som sparats i inställningarna i adverts';

  @override
  String get repeater_cliHelpGpsAdvertSet =>
      'Ställer in konfigurationen för plats i adverts.';

  @override
  String get repeater_commandsListTitle => 'Kommandolista';

  @override
  String get repeater_commandsListNote =>
      'OBS: för de olika \"set ...\"-kommandona finns det även ett \"get ...\"-kommando.';

  @override
  String get repeater_general => 'Allmänt';

  @override
  String get repeater_settingsCategory => 'Inställningar';

  @override
  String get repeater_bridge => 'Brygga';

  @override
  String get repeater_logging => 'Loggning';

  @override
  String get repeater_neighborsRepeaterOnly => 'Grannar (endast repeater)';

  @override
  String get repeater_regionManagementRepeaterOnly =>
      'Regionhantering (endast repeater)';

  @override
  String get repeater_regionNote =>
      'Regionkommandon har införts för att hantera regiondefinitioner och behörigheter.';

  @override
  String get repeater_gpsManagement => 'GPS-hantering';

  @override
  String get repeater_gpsNote =>
      'Kommandot gps har införts för att hantera platsrelaterade ämnen.';

  @override
  String get repeater_getCategory => 'Hämta värden';

  @override
  String get repeater_powerMgmt => 'Energihantering';

  @override
  String get repeater_sensors => 'Sensorer';

  @override
  String get repeater_cliHelpPowerOff =>
      'Stänger av enheten. (ingen respons förväntas)';

  @override
  String get repeater_cliHelpClkReboot =>
      'Återställer klockan till en känd tidpunkt och startar om enheten.';

  @override
  String get repeater_cliHelpAdvertZeroHop =>
      'Skickar en zero-hop-advert (endast närmaste grannar).';

  @override
  String get repeater_cliHelpStartOta =>
      'Startar en firmware-uppdatering via luft, på kompatibla enheter.';

  @override
  String get repeater_cliHelpTime =>
      'Ställer in enhetens klocka till det angivna antalet sekunder sedan Unix-epoken. Klockan kan inte gå bakåt.';

  @override
  String get repeater_cliHelpBoard =>
      'Visar tillverkaren av moderkortet / hårdvaru-identifieraren.';

  @override
  String get repeater_cliHelpDiscoverNeighbors =>
      'Skickar en förfrågan om att upptäcka närliggande noder. (Endast för repeatrar)';

  @override
  String get repeater_cliHelpPowersaving =>
      'Visar om energisparläget är aktiverat eller avstängt.';

  @override
  String get repeater_cliHelpPowersavingOnOff =>
      'Aktiverar eller inaktiverar energisparläget (om det stöds).';

  @override
  String get repeater_cliHelpErase =>
      '(Endast för seriell kommunikation) Formaterar enhetens filsystem. Raderar alla inställningar och kontakter.';

  @override
  String get repeater_cliHelpSetDutyCycle =>
      'Anger den maximala tillåtna arbetscykeln för sändning i procent (1-100). Justerar internt sändningstidsfaktorn.';

  @override
  String get repeater_cliHelpSetPrvKey =>
      'Ersätter enhetens privata identitetsnyckel. Återstart krävs för att tillämpa. Genererar en ny publik nyckel.';

  @override
  String get repeater_cliHelpSetRadioRxGain =>
      '(Endast SX126x) Växlar förhöjd RX-förstärkning för bättre känslighet vid högre strömförbrukning.';

  @override
  String get repeater_cliHelpSetOwnerInfo =>
      'Anger ägarens kontaktinformation som inkluderas i adverts. Använd \'|\' för radbrytningar.';

  @override
  String get repeater_cliHelpSetPathHashMode =>
      'Ställer in hash-läget för sökvägen: hur många byte av varje hopps hash som hamnar i sökvägen för flood-paket som den här noden skickar. 0 = 1 byte, 1 = 2 byte, 2 = 3 byte.';

  @override
  String get repeater_cliHelpSetLoopDetect =>
      'Ställer in känsligheten för att detektera loopar i routningen: off, minimal, moderate eller strict.';

  @override
  String get repeater_cliHelpSetFreq =>
      '(Endast för seriell kommunikation) Ställer snabbt in bara frekvensen. Kräver omstart. Använd hellre \"set radio\" för alla radioparametrar.';

  @override
  String get repeater_cliHelpSetBridgeChannel =>
      '(Endast ESPNow-brygga) Anger WiFi-kanalen (1-14) som används av bryggan.';

  @override
  String get repeater_cliHelpGetName => 'Visar det konfigurerade nodnamnet.';

  @override
  String get repeater_cliHelpGetRole =>
      'Visar firmware-rollen (Repeater, Room Server, etc.).';

  @override
  String get repeater_cliHelpGetPublicKey => 'Visar enhetens publika nyckel.';

  @override
  String get repeater_cliHelpGetPrvKey =>
      '(Endast för seriell användning) Visar enhetens privata nyckel. Behandla detta som en hemlighet.';

  @override
  String get repeater_cliHelpGetRepeat =>
      'Visar om funktionen för att vidarebefordra paket (som en repeater) är aktiverad eller inaktiverad.';

  @override
  String get repeater_cliHelpGetTx => 'Visar aktuell TX-effekt i dBm.';

  @override
  String get repeater_cliHelpGetFreq =>
      'Visar den konfigurerade radiofrekvensen i MHz.';

  @override
  String get repeater_cliHelpGetRadio =>
      'Visar alla radioparametrar: frekvens, bandbredd, spridningsfaktor, kodningsgrad.';

  @override
  String get repeater_cliHelpGetRadioRxGain =>
      '(Endast för SX126x) Visar tillståndet för förhöjd RX-förstärkning.';

  @override
  String get repeater_cliHelpGetAf => 'Visar aktuell sändningstidsfaktor.';

  @override
  String get repeater_cliHelpGetDutyCycle =>
      'Visar den aktuella tillåtna arbetscykeln i procent.';

  @override
  String get repeater_cliHelpGetIntThresh =>
      'Visar gränsen för kanalinterferens i dB.';

  @override
  String get repeater_cliHelpGetAgcResetInterval =>
      'Visar återställningsintervallet för AGC i sekunder.';

  @override
  String get repeater_cliHelpGetMultiAcks =>
      'Visar om dubbelbekräftelseläget är aktiverat (1) eller avstängt (0).';

  @override
  String get repeater_cliHelpGetAllowReadOnly =>
      'Visar om skrivskyddad gäståtkomst är tillåten.';

  @override
  String get repeater_cliHelpGetAdvertInterval =>
      'Visar det lokala advertintervallet i minuter.';

  @override
  String get repeater_cliHelpGetFloodAdvertInterval =>
      'Visar intervallet för flood-adverts i timmar.';

  @override
  String get repeater_cliHelpGetGuestPassword =>
      'Visar det angivna gästlösenordet.';

  @override
  String get repeater_cliHelpGetLat => 'Visar den angivna latituden.';

  @override
  String get repeater_cliHelpGetLon => 'Visar den angivna longituden.';

  @override
  String get repeater_cliHelpGetRxDelay => 'Visar grundvärdet för rxdelay.';

  @override
  String get repeater_cliHelpGetTxDelay =>
      'Visar txdelay-faktorn i läget flood.';

  @override
  String get repeater_cliHelpGetDirectTxDelay =>
      'Visar faktorn för fördröjning i direktläge.';

  @override
  String get repeater_cliHelpGetFloodMax =>
      'Visar det maximala antalet hopp för flood.';

  @override
  String get repeater_cliHelpGetOwnerInfo =>
      'Visar strängen med kontaktinformation för ägaren.';

  @override
  String get repeater_cliHelpGetPathHashMode =>
      'Visar sökvägens hash-läge (0/1/2).';

  @override
  String get repeater_cliHelpGetLoopDetect =>
      'Visar känsligheten för att detektera loopar.';

  @override
  String get repeater_cliHelpGetAcl =>
      '(Endast seriellt) Listar åtkomstkontrollposterna på en repeater.';

  @override
  String get repeater_cliHelpGetBridgeEnabled =>
      'Visar om bryggan är aktiverad.';

  @override
  String get repeater_cliHelpGetBridgeDelay =>
      'Visar bryggans fördröjning i millisekunder.';

  @override
  String get repeater_cliHelpGetBridgeSource =>
      'Visar om bryggan skickar RX- eller TX-paket.';

  @override
  String get repeater_cliHelpGetBridgeBaud =>
      '(Enbart RS232-brygga) Visar bryggans baud-hastighet.';

  @override
  String get repeater_cliHelpGetBridgeChannel =>
      '(Endast ESPNow-brygga) Visar WiFi-kanal för bryggan.';

  @override
  String get repeater_cliHelpGetBridgeSecret =>
      '(Endast ESPNow-brygga) Visar bryggans delade hemlighet.';

  @override
  String get repeater_cliHelpGetBootloaderVer =>
      '(Endast för NRF52) Visar versionen av bootloadern.';

  @override
  String get repeater_cliHelpGetAdcMultiplier =>
      'Visar ADC-multiplikatorn (skalning av batterispänning).';

  @override
  String get repeater_cliHelpGetPwrMgtSupport =>
      'Anger om kortet har stöd för energihantering.';

  @override
  String get repeater_cliHelpGetPwrMgtSource =>
      'Visar aktuell strömkälla: extern eller batteri.';

  @override
  String get repeater_cliHelpGetPwrMgtBootReason =>
      'Visar de senaste orsakerna till återställning och avstängning.';

  @override
  String get repeater_cliHelpGetPwrMgtBootMv =>
      'Visar batterispänningen vid start i millivolt (mV).';

  @override
  String get repeater_cliHelpSensorGet =>
      'Läser en anpassad sensorinställning efter nyckel.';

  @override
  String get repeater_cliHelpSensorSet =>
      'Skriver en anpassad sensorinställning.';

  @override
  String get repeater_cliHelpSensorList =>
      'Listar alla anpassade sensorinställningar, sidindelade från ett valfritt startindex.';

  @override
  String get repeater_cliHelpRegionDefault =>
      'Visar det aktuella standardområdet.';

  @override
  String get repeater_cliHelpRegionDefaultSet =>
      'Ställer in standardområdet. Använd \"<null>\" för att rensa.';

  @override
  String get repeater_cliHelpRegionListAllowed =>
      'Listar regioner som tillåter flood-trafik.';

  @override
  String get repeater_cliHelpRegionListDenied =>
      'Listar regioner som nekar flood-trafik.';

  @override
  String get repeater_cliHelpStatsPackets =>
      '(Endast för seriell kommunikation) Visar statistik på paketnivå.';

  @override
  String get repeater_cliHelpStatsRadio =>
      '(Enbart för seriell kommunikation) Visar radiostatistik.';

  @override
  String get repeater_cliHelpStatsCore =>
      '(Enbart för seriell kommunikation) Visar statistik för firmwarens kärna.';

  @override
  String get telemetry_receivedData => 'Mottagen telemetridata';

  @override
  String get telemetry_requestTimeout =>
      'Tidsgränsen för telemetriförfrågan överskreds.';

  @override
  String telemetry_errorLoading(String error) {
    return 'Fel vid laddning av telemetri: $error';
  }

  @override
  String get telemetry_noData => 'Inga telemetridata tillgängliga.';

  @override
  String telemetry_channelTitle(int channel) {
    return 'Kanal $channel';
  }

  @override
  String get telemetry_batteryLabel => 'Batteri';

  @override
  String get telemetry_voltageLabel => 'Spänning';

  @override
  String get telemetry_mcuTemperatureLabel => 'MCU-temperatur';

  @override
  String get telemetry_temperatureLabel => 'Temperatur';

  @override
  String get telemetry_currentLabel => 'Ström';

  @override
  String telemetry_batteryValue(int percent, String volts) {
    return '$percent% / ${volts}V';
  }

  @override
  String telemetry_voltageValue(String volts) {
    return '${volts}V';
  }

  @override
  String telemetry_currentValue(String amps) {
    return '${amps}A';
  }

  @override
  String telemetry_temperatureValue(String celsius, String fahrenheit) {
    return '$celsius°C / $fahrenheit°F';
  }

  @override
  String get telemetry_digitalInputLabel => 'Digital ingång';

  @override
  String get telemetry_digitalOutputLabel => 'Digital utgång';

  @override
  String get telemetry_analogInputLabel => 'Analog ingång';

  @override
  String get telemetry_analogOutputLabel => 'Analog utgång';

  @override
  String get telemetry_genericLabel => 'Allmän sensor';

  @override
  String get telemetry_luminosityLabel => 'Ljusstyrka';

  @override
  String get telemetry_presenceLabel => 'Närvaro';

  @override
  String get telemetry_humidityLabel => 'Luftfuktighet';

  @override
  String get telemetry_accelerometerLabel => 'Accelerometer';

  @override
  String get telemetry_pressureLabel => 'Tryck';

  @override
  String get telemetry_altitudeLabel => 'Höjd';

  @override
  String get telemetry_frequencyLabel => 'Frekvens';

  @override
  String get telemetry_percentageLabel => 'Procent';

  @override
  String get telemetry_concentrationLabel => 'Koncentration';

  @override
  String get telemetry_powerLabel => 'Effekt';

  @override
  String get telemetry_distanceLabel => 'Avstånd';

  @override
  String get telemetry_energyLabel => 'Energi';

  @override
  String get telemetry_directionLabel => 'Riktning';

  @override
  String get telemetry_timeLabel => 'Tid';

  @override
  String get telemetry_gyrometerLabel => 'Gyrometer';

  @override
  String get telemetry_colourLabel => 'Färg';

  @override
  String get telemetry_gpsLabel => 'GPS';

  @override
  String get telemetry_switchLabel => 'Brytare';

  @override
  String get telemetry_polylineLabel => 'Polylinje';

  @override
  String telemetry_altitudeValue(String meters) {
    return '$meters m';
  }

  @override
  String telemetry_frequencyValue(String hertz) {
    return '$hertz Hz';
  }

  @override
  String telemetry_pressureValue(String hpa) {
    return '$hpa hPa';
  }

  @override
  String telemetry_luminosityValue(String lux) {
    return '$lux lx';
  }

  @override
  String telemetry_powerValue(String watts) {
    return '$watts W';
  }

  @override
  String telemetry_distanceValue(String meters) {
    return '$meters m';
  }

  @override
  String telemetry_energyValue(String kilowattHours) {
    return '$kilowattHours kWh';
  }

  @override
  String telemetry_directionValue(String degrees) {
    return '$degrees°';
  }

  @override
  String telemetry_concentrationValue(String ppm) {
    return '$ppm ppm';
  }

  @override
  String telemetry_percentageValue(String percent) {
    return '$percent%';
  }

  @override
  String telemetry_analogValue(String value) {
    return '$value';
  }

  @override
  String get telemetry_autoFetchQuantity => 'Antal förfrågningar';

  @override
  String get telemetry_error => 'Det gick inte att hämta data';

  @override
  String get neighbors_receivedData => 'Mottagna data om grannar';

  @override
  String get neighbors_requestTimedOut =>
      'Tidsgränsen för förfrågan om grannar överskreds.';

  @override
  String neighbors_errorLoading(String error) {
    return 'Fel vid inläsning av grannar: $error';
  }

  @override
  String get neighbors_repeatersNeighbors => 'Repeaterns grannar';

  @override
  String get neighbors_noData => 'Inga grannuppgifter finns tillgängliga.';

  @override
  String neighbors_unknownContact(String pubkey) {
    return 'Okänd $pubkey';
  }

  @override
  String neighbors_heardAgo(String time) {
    return 'Hördes: $time sedan';
  }

  @override
  String get channelPath_title => 'Paketväg';

  @override
  String get channelPath_viewMap => 'Visa karta';

  @override
  String get channelPath_otherObservedPaths => 'Övriga observerade sökvägar';

  @override
  String get channelPath_repeaterHops => 'Repeaterhopp';

  @override
  String get channelPath_repeaterHopsHighTimeout =>
      'Förlängd timeout för spårning av sökvägen (10 s × hopp)';

  @override
  String get channelPath_noHopDetails =>
      'Hoppdetaljer finns inte för detta paket.';

  @override
  String get channelPath_messageDetails => 'Meddelandets detaljer';

  @override
  String get channelPath_senderLabel => 'Avsändare';

  @override
  String get channelPath_timeLabel => 'Tid för mottagning/skapande';

  @override
  String get channelPath_repeatsLabel => 'Upprepningar';

  @override
  String channelPath_pathLabel(int index) {
    return 'Sökväg $index';
  }

  @override
  String get channelPath_observedLabel => 'Observerat';

  @override
  String channelPath_observedPathTitle(int index, String hops) {
    return 'Observerad sökväg $index • $hops';
  }

  @override
  String get channelPath_noLocationData => 'Ingen platsdata';

  @override
  String channelPath_timeWithDate(int day, int month, String time) {
    return '$day/$month kl. $time';
  }

  @override
  String channelPath_timeOnly(String time) {
    return '$time';
  }

  @override
  String get channelPath_unknownPath => 'Okänt';

  @override
  String get channelPath_floodPath => 'Flood';

  @override
  String get channelPath_directPath => 'Direkt';

  @override
  String channelPath_observedZeroOf(int total) {
    return '0 av $total hopp';
  }

  @override
  String channelPath_observedSomeOf(int observed, int total) {
    return '$observed av $total hopp';
  }

  @override
  String get channelPath_mapTitle => 'Sökvägskarta';

  @override
  String get channelPath_noRepeaterLocations =>
      'Inga repeaterpositioner finns tillgängliga för denna sökväg.';

  @override
  String channelPath_primaryPath(int index) {
    return 'Sökväg $index (Primär)';
  }

  @override
  String get channelPath_pathLabelTitle => 'Sökväg';

  @override
  String get channelPath_observedPathHeader => 'Observerad sökväg';

  @override
  String channelPath_selectedPathLabel(String label, String prefixes) {
    return '$label • $prefixes';
  }

  @override
  String get channelPath_noHopDetailsAvailable =>
      'Inga hoppdetaljer finns tillgängliga för detta paket.';

  @override
  String get channelPath_unknownRepeater => 'Okänd repeater';

  @override
  String get channelPath_outgoingSentByRadioAt =>
      'Väntade på sändning via radio, s';

  @override
  String get community_title => 'Gemenskap';

  @override
  String get community_create => 'Skapa gemenskap';

  @override
  String get community_createDesc =>
      'Skapa en ny gemenskap och dela via QR-kod.';

  @override
  String get community_join => 'Gå med';

  @override
  String get community_joinTitle => 'Gå med i gemenskapen';

  @override
  String community_joinConfirmation(String name) {
    return 'Vill du gå med i communityn \"$name\"?';
  }

  @override
  String get community_scanQr => 'Skanna gemenskapens QR-kod';

  @override
  String get community_scanInstructions =>
      'Rikta kameran mot en gemenskaps QR-kod';

  @override
  String get community_showQr => 'Visa QR-kod';

  @override
  String get community_publicChannel => 'Gemenskapens publika kanal';

  @override
  String get community_hashtagChannel => 'Hashtag för gemenskapen';

  @override
  String get community_name => 'Gemenskapens namn';

  @override
  String get community_enterName => 'Ange gemenskapens namn';

  @override
  String community_created(String name) {
    return 'Community \"$name\" har skapats';
  }

  @override
  String community_joined(String name) {
    return 'Medlem i communityn \"$name\"';
  }

  @override
  String get community_qrTitle => 'Dela gemenskap';

  @override
  String community_qrInstructions(String name) {
    return 'Skanna denna QR-kod för att gå med i \"$name\"';
  }

  @override
  String get community_hashtagPrivacyHint =>
      'Community-hashtagkanaler kan endast nås av medlemmar i communityn';

  @override
  String get community_invalidQrCode => 'Ogiltig QR-kod för gemenskap';

  @override
  String get community_alreadyMember => 'Är redan medlem';

  @override
  String community_alreadyMemberMessage(String name) {
    return 'Du är redan medlem i \"$name\".';
  }

  @override
  String get community_addPublicChannel =>
      'Lägg till gemenskapens publika kanal';

  @override
  String get community_addPublicChannelHint =>
      'Lägg automatiskt till den offentliga kanalen för denna community';

  @override
  String get community_noCommunities =>
      'Du har inte gått med i någon gemenskap ännu';

  @override
  String get community_scanOrCreate =>
      'Skanna en QR-kod eller skapa en community för att komma igång';

  @override
  String get community_manageCommunities => 'Hantera gemenskaper';

  @override
  String get community_delete => 'Lämna gemenskap';

  @override
  String community_deleteConfirm(String name) {
    return 'Lämna \"$name\"?';
  }

  @override
  String community_deleteChannelsWarning(int count) {
    return 'Detta kommer också att radera $count kanal/kanaler och deras meddelanden.';
  }

  @override
  String community_deleted(String name) {
    return 'Lämnade community \"$name\"';
  }

  @override
  String get community_regenerateSecret => 'Regenerera hemlig kod';

  @override
  String community_regenerateSecretConfirm(String name) {
    return 'Regenerera den hemliga nyckeln för \"$name\"? Alla medlemmar måste scanna den nya QR-koden för att fortsätta kommunicera.';
  }

  @override
  String get community_regenerate => 'Regenerera';

  @override
  String community_secretRegenerated(String name) {
    return 'Hemlighet återskapad för \"$name\"';
  }

  @override
  String get community_updateSecret => 'Uppdatera hemlighet';

  @override
  String community_secretUpdated(String name) {
    return 'Hemlighet uppdaterad för \"$name\"';
  }

  @override
  String community_scanToUpdateSecret(String name) {
    return 'Skanna den nya QR-koden för att uppdatera hemligheten för \"$name\"';
  }

  @override
  String get community_addHashtagChannel => 'Lägg till gemenskapens hashtag';

  @override
  String get community_addHashtagChannelDesc =>
      'Lägg till en hashtag-kanal för denna community';

  @override
  String get community_selectCommunity => 'Välj gemenskap';

  @override
  String get community_regularHashtag => 'Vanlig hashtag';

  @override
  String get community_regularHashtagDesc =>
      'Offentlig hashtag (alla kan gå med)';

  @override
  String get community_communityHashtag => 'Gemenskaps-hashtag';

  @override
  String get community_communityHashtagDesc => 'Endast för medlemmar';

  @override
  String community_forCommunity(String name) {
    return 'För $name';
  }

  @override
  String get listFilter_tooltip => 'Filtrera och sortera';

  @override
  String get listFilter_sortBy => 'Sortera efter';

  @override
  String get listFilter_latestMessages => 'Senaste meddelanden';

  @override
  String get listFilter_heardRecently => 'Hörts nyligen';

  @override
  String get listFilter_az => 'A-Z';

  @override
  String get listFilter_filters => 'Filteralternativ';

  @override
  String get listFilter_all => 'Alla';

  @override
  String get listFilter_favorites => 'Favoriter';

  @override
  String get listFilter_addToFavorites => 'Lägg till i favoriter';

  @override
  String get listFilter_removeFromFavorites => 'Ta bort från favoriter';

  @override
  String get listFilter_removeFromWardrive => 'Ignorera i Wardrive';

  @override
  String get listFilter_returnToWardrive => 'Ta med i Wardrive';

  @override
  String get listFilter_users => 'Användare';

  @override
  String get listFilter_repeaters => 'Repeatrar';

  @override
  String get listFilter_roomServers => 'Rumsservrar';

  @override
  String get listFilter_unreadOnly => 'Endast olästa';

  @override
  String get listFilter_newGroup => 'Ny grupp';

  @override
  String get pathTrace_you => 'Du';

  @override
  String get pathTrace_failed => 'Sökvägsspårning misslyckades.';

  @override
  String get pathTrace_notAvailable => 'Sökvägsspårning inte tillgänglig.';

  @override
  String get pathTrace_refreshTooltip => 'Uppdatera sökvägsspårning';

  @override
  String get pathTrace_hopConfirmedNoDirectEchoTooltip =>
      'Hoppet bekräftat, ekot hördes inte direkt';

  @override
  String get pathTrace_someHopsNoLocation =>
      'Ett eller flera av hoppen saknar plats!';

  @override
  String get pathTrace_clearTooltip => 'Rensa väg';

  @override
  String get losSelectStartEnd => 'Välj start- och slutnoder för LOS.';

  @override
  String losRunFailed(String error) {
    return 'Synlinjekontroll misslyckades: $error';
  }

  @override
  String get losClearAllPoints => 'Rensa alla punkter';

  @override
  String get losRunToViewElevationProfile => 'Kör LOS för att se höjdprofil';

  @override
  String get losMenuTitle => 'LOS-menyn';

  @override
  String get losMenuSubtitle =>
      'Tryck på noder eller tryck länge på kartan för anpassade punkter';

  @override
  String get losShowDisplayNodes => 'Visa displaynoder';

  @override
  String get losCustomPoints => 'Anpassade punkter';

  @override
  String losCustomPointLabel(int index) {
    return 'Anpassad $index';
  }

  @override
  String get losPointA => 'Punkt A';

  @override
  String get losPointB => 'Punkt B';

  @override
  String losAntennaA(String value, String unit) {
    return 'Antenn A: $value $unit';
  }

  @override
  String losAntennaB(String value, String unit) {
    return 'Antenn B: $value $unit';
  }

  @override
  String get losRun => 'Kör LOS';

  @override
  String get losNoElevationData => 'Inga höjddata';

  @override
  String losProfileClear(
    String distance,
    String distanceUnit,
    String clearance,
    String heightUnit,
  ) {
    return '$distance $distanceUnit, fri sikt, minsta marginal $clearance $heightUnit';
  }

  @override
  String losProfileBlocked(
    String distance,
    String distanceUnit,
    String obstruction,
    String heightUnit,
  ) {
    return '$distance $distanceUnit, blockerad av $obstruction $heightUnit';
  }

  @override
  String get losStatusChecking => 'LOS: kollar...';

  @override
  String get losStatusNoData => 'LOS: inga data';

  @override
  String losStatusSummary(int clear, int total, int blocked, int unknown) {
    return 'LOS: $clear/$total fria, $blocked blockerade, $unknown okända';
  }

  @override
  String get losErrorElevationUnavailable =>
      'Höjddata är inte tillgänglig för ett eller flera prover.';

  @override
  String get losErrorInvalidInput =>
      'Ogiltiga punkter/höjddata för LOS-beräkning.';

  @override
  String get losRenameCustomPoint => 'Byt namn på anpassad punkt';

  @override
  String get losPointName => 'Punktnamn';

  @override
  String get losShowPanelTooltip => 'Visa LOS-panelen';

  @override
  String get losHidePanelTooltip => 'Dölj LOS-panelen';

  @override
  String get losElevationAttribution => 'Höjddata: Open-Meteo (CC BY 4.0)';

  @override
  String get losLegendRadioHorizon => 'Radiohorisont';

  @override
  String get losLegendLosBeam => 'Siktlinje';

  @override
  String get losLegendTerrain => 'Terräng';

  @override
  String get losBlockedSpotsTitle => 'Blockerade punkter';

  @override
  String get losBlockedSpotsHint =>
      'Tryck på en blockerad punkt för att markera den på kartan.';

  @override
  String losBlockedSpotChip(
    String distance,
    String distanceUnit,
    String obstruction,
    String heightUnit,
  ) {
    return '$distance $distanceUnit • $obstruction $heightUnit';
  }

  @override
  String get losSelectedObstructionTitle => 'Valt hinder';

  @override
  String losSelectedObstructionDetails(
    String obstruction,
    String heightUnit,
    String distanceFromA,
    String distanceUnit,
    String distanceFromB,
  ) {
    return 'Blockerad av $obstruction $heightUnit, $distanceFromA från A och $distanceFromB från B ($distanceUnit).';
  }

  @override
  String get losFrequencyLabel => 'Frekvens';

  @override
  String get losFrequencyInfoTooltip => 'Visa detaljer om beräkningen';

  @override
  String get losFrequencyDialogTitle => 'Beräkning av radiohorisonten';

  @override
  String losFrequencyDialogDescription(
    double baselineK,
    double baselineFreq,
    double frequencyMHz,
    double kFactor,
  ) {
    return 'Med start från k=$baselineK vid $baselineFreq MHz justerar beräkningen k-faktorn till $kFactor för det aktuella $frequencyMHz MHz-bandet, som definierar den böjda radiohorisonten.';
  }

  @override
  String get contacts_pathTrace => 'Spårning';

  @override
  String get contacts_ping => 'Ping';

  @override
  String get contacts_repeaterPathTrace => 'Vägspårning till repeater';

  @override
  String get contacts_repeaterPing => 'Pinga repeater';

  @override
  String get contacts_roomPathTrace => 'Vägspårning till rumsserver';

  @override
  String get contacts_roomPing => 'Pinga rumsserver';

  @override
  String get contacts_chatTraceRoute => 'Spåra rutt';

  @override
  String contacts_pathTraceTo(String name) {
    return 'Spåra rutt till $name';
  }

  @override
  String get contacts_clipboardEmpty => 'Urklipp är tomt.';

  @override
  String get contacts_invalidAdvertFormat => 'Ogiltiga kontaktuppgifter';

  @override
  String get contacts_contactImported => 'Kontakten har importerats.';

  @override
  String get contacts_contactImportFailed => 'Kontakten kunde inte importeras.';

  @override
  String get contacts_zeroHopAdvert => 'Zero-hop-advert';

  @override
  String get contacts_floodAdvert => 'Flood-advert';

  @override
  String get contacts_copyAdvertToClipboard =>
      'Kopiera egen länk «meshcore://»';

  @override
  String get contacts_addContactFromClipboard =>
      'Lägg till kontakt från «meshcore://»-länk i urklipp';

  @override
  String get contacts_ShareContact => 'Kopiera kontakt till Urklipp';

  @override
  String get contacts_ShareContactZeroHop => 'Dela kontakt via advert';

  @override
  String get contacts_zeroHopContactAdvertSent =>
      'Kontakten skickades via advert.';

  @override
  String get contacts_zeroHopContactAdvertFailed =>
      'Misslyckades med att skicka kontakt.';

  @override
  String get contacts_contactAdvertCopied => 'Advert kopierad till Urklipp.';

  @override
  String get contacts_contactAdvertCopyFailed =>
      'Kopiering av advert till Urklipp misslyckades.';

  @override
  String get notification_activityTitle => 'MeshCore-aktivitet';

  @override
  String notification_messagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'meddelanden',
      one: 'meddelande',
    );
    return '$count $_temp0';
  }

  @override
  String notification_channelMessagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'kanalmeddelanden',
      one: 'kanalmeddelande',
    );
    return '$count $_temp0';
  }

  @override
  String notification_newNodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'nya noder',
      one: 'ny nod',
    );
    return '$count $_temp0';
  }

  @override
  String notification_newTypeDiscovered(String contactType) {
    return 'Ny $contactType upptäckt';
  }

  @override
  String get notification_receivedNewMessage => 'Nytt meddelande mottaget';

  @override
  String get settings_gpxExportRepeaters =>
      'Exportera repeatrar / rumsservrar till GPX';

  @override
  String get settings_gpxExportRepeatersSubtitle =>
      'Exporterar repeatrar / rumsservrar med plats till GPX-fil.';

  @override
  String get settings_gpxExportContacts =>
      'Exportera companion-enheter till GPX';

  @override
  String get settings_gpxExportContactsSubtitle =>
      'Exporterar companion-enheter med en plats till GPX-fil.';

  @override
  String get settings_gpxExportAll => 'Exportera alla kontakter till GPX';

  @override
  String get settings_gpxExportAllSubtitle =>
      'Exporterar alla kontakter med en plats till GPX-fil.';

  @override
  String get settings_gpxExportSuccess => 'GPX-filen har exporterats.';

  @override
  String get settings_gpxExportNoContacts => 'Inga kontakter att exportera.';

  @override
  String get settings_gpxExportNotAvailable =>
      'Stöds inte på din enhet/operativsystem';

  @override
  String get settings_gpxExportError =>
      'Det uppstod ett fel när data exporterades.';

  @override
  String get settings_gpxExportRepeatersRoom =>
      'Repeater- och rumsserverplatser';

  @override
  String get settings_gpxExportChat => 'Platser för companion-enheter';

  @override
  String get settings_gpxExportAllContacts => 'Alla kontakters platser';

  @override
  String get settings_gpxExportShareText =>
      'Kartdata exporterad från meshcore-open';

  @override
  String get settings_gpxExportShareSubject =>
      'meshcore-open export av GPX-kartdata';

  @override
  String get snrIndicator_nearByRepeaters => 'Närliggande repeatrar';

  @override
  String get snrIndicator_lastSeen => 'Senast sedd';

  @override
  String get contactsSettings_title => 'Kontaktinställningar';

  @override
  String get contactsSettings_autoAddTitle => 'Automatisk upptäckt';

  @override
  String get contactsSettings_otherTitle =>
      'Andra inställningar relaterade till kontakter';

  @override
  String get contactsSettings_autoAddUsersTitle =>
      'Lägg till användare automatiskt';

  @override
  String get contactsSettings_autoAddUsersSubtitle =>
      'Tillåt companion-radion att automatiskt lägga till upptäckta användare.';

  @override
  String get contactsSettings_autoAddRepeatersTitle =>
      'Lägg till repeatrar automatiskt';

  @override
  String get contactsSettings_autoAddRepeatersSubtitle =>
      'Tillåt companion-radion att automatiskt lägga till upptäckta repeatrar.';

  @override
  String get contactsSettings_autoAddRoomServersTitle =>
      'Lägg automatiskt till rumsservrar';

  @override
  String get contactsSettings_autoAddRoomServersSubtitle =>
      'Tillåt companion-radion att automatiskt lägga till upptäckta rumsservrar.';

  @override
  String get contactsSettings_autoAddSensorsTitle =>
      'Lägg till sensorer automatiskt';

  @override
  String get contactsSettings_autoAddSensorsSubtitle =>
      'Tillåt companion-radion att automatiskt lägga till upptäckta sensorer.';

  @override
  String get contactsSettings_overwriteOldestTitle => 'Skriv över den äldsta';

  @override
  String get contactsSettings_overwriteOldestSubtitle =>
      'När kontaktlistan är full ersätts den äldsta icke-favoriterade kontakten.';

  @override
  String get discoveredContacts_Title => 'Lägg till upptäckta kontakter';

  @override
  String get discoveredContacts_noMatching => 'Inga matchande kontakter';

  @override
  String get discoveredContacts_searchHint => 'Sök upptäckta kontakter';

  @override
  String get discoveredContacts_contactAdded => 'Kontakt tillagd';

  @override
  String get discoveredContacts_addContact => 'Lägg till kontakt';

  @override
  String get discoveredContacts_copyContact => 'Kopiera kontakt till urklipp';

  @override
  String get discoveredContacts_deleteContact => 'Ta bort kontakt';

  @override
  String get discoveredContacts_deleteContactAll =>
      'Ta bort alla upptäckta kontakter';

  @override
  String get discoveredContacts_discoverDevices => 'Upptäck enheter';

  @override
  String get discoveredContacts_requestName => 'Begär namn';

  @override
  String get discoveredContacts_nameRequestFailed =>
      'Det gick inte att begära repeaterns namn';

  @override
  String discoveredContacts_discoveryFailed(String error) {
    return 'Det gick inte att upptäcka enheter: $error';
  }

  @override
  String get discoveredContacts_deleteContactAllContent =>
      'Är du säker på att du vill ta bort alla upptäckta kontakter?';

  @override
  String get chat_sendCooldown =>
      'Vänligen vänta en stund innan du skickar igen.';

  @override
  String get appSettings_jumpToOldestUnread =>
      'Gå direkt till det äldsta olästa meddelandet';

  @override
  String get appSettings_jumpToOldestUnreadSubtitle =>
      'När du öppnar en chatt med olästa meddelanden, scrolla till det första olästa meddelandet istället för det senaste.';

  @override
  String get appSettings_languageHu => 'Ungerska';

  @override
  String get appSettings_languageJa => 'Japanska';

  @override
  String get appSettings_languageKo => 'Koreanska';

  @override
  String get radioStats_tooltip => 'Radio- och mesh-statistik';

  @override
  String get radioStats_screenTitle => 'Radiostatistik';

  @override
  String get radioStats_notConnected =>
      'Anslut till en enhet för att visa radiostatistik.';

  @override
  String get radioStats_firmwareTooOld =>
      'Radiostatistik kräver companion-firmware v8 eller senare.';

  @override
  String get radioStats_waiting => 'Väntar på data…';

  @override
  String radioStats_noiseFloor(int noiseDbm) {
    return 'Brusgolv: $noiseDbm dBm';
  }

  @override
  String radioStats_lastRssi(int rssiDbm) {
    return 'Senaste RSSI-värde: $rssiDbm dBm';
  }

  @override
  String radioStats_lastSnr(String snr) {
    return 'Senaste SNR: $snr dB';
  }

  @override
  String radioStats_txAir(int seconds) {
    return 'TX-tid (total): $seconds sekunder';
  }

  @override
  String radioStats_rxAir(int seconds) {
    return 'RX-tid (total): $seconds s';
  }

  @override
  String get radioStats_chartCaption =>
      'Brusgolv (dBm) för de senaste mätningarna.';

  @override
  String radioStats_stripNoise(int noiseDbm) {
    return 'Brusgolv: $noiseDbm dBm';
  }

  @override
  String get radioStats_stripWaiting => 'Hämtar radiostatistik…';

  @override
  String get radioStats_settingsTile => 'Radiostatistik';

  @override
  String get radioStats_settingsSubtitle =>
      'Brusgolv, RSSI, SNR och sändningstid';

  @override
  String get translation_title => 'Översättning';

  @override
  String get translation_enableTitle => 'Aktivera översättning';

  @override
  String get translation_enableSubtitle =>
      'Översätt inkommande meddelanden och möjliggör översättning före avsändning.';

  @override
  String get translation_composerTitle => 'Översätt innan du skickar';

  @override
  String get translation_composerSubtitle =>
      'Styr standardläget för översättningsikonen i meddelandefältet.';

  @override
  String get translation_autoIncomingTitle =>
      'Översätt meddelanden automatiskt';

  @override
  String get translation_autoIncomingSubtitle =>
      'Översätter meddelanden automatiskt för aviseringar och för chattar eller kanaler.';

  @override
  String get translation_translateMessage => 'Översätt meddelande';

  @override
  String get translation_targetLanguage => 'Målspråk';

  @override
  String get translation_useAppLanguage => 'Använd appens språk';

  @override
  String get translation_downloadedModelLabel => 'Nedladdad modell';

  @override
  String get translation_presetModelLabel =>
      'Fördefinierad Hugging Face-modell';

  @override
  String get translation_manualUrlLabel => 'Manuell modell-URL';

  @override
  String get translation_downloadModel => 'Ladda ner modellen';

  @override
  String get translation_downloading => 'Nedladdning...';

  @override
  String get translation_working => 'Arbetar...';

  @override
  String get translation_stop => 'Stopp';

  @override
  String get translation_mergingChunks =>
      'Slår samman de nedladdade delarna till en slutlig fil...';

  @override
  String get translation_downloadedModels => 'Nedladdade modeller';

  @override
  String get translation_deleteModel => 'Ta bort modell';

  @override
  String get translation_modelDownloaded =>
      'Översättningsmodellen har laddats ner.';

  @override
  String get translation_downloadStopped => 'Nedladdningen avbruten.';

  @override
  String translation_downloadFailed(String error) {
    return 'Nedladdning misslyckades: $error';
  }

  @override
  String get translation_enterUrlFirst =>
      'Ange först en URL för en specifik modell.';

  @override
  String get scanner_linuxPairingShowPin => 'Visa PIN';

  @override
  String get scanner_linuxPairingHidePin => 'Dölj PIN';

  @override
  String get scanner_linuxPairingPinTitle => 'Bluetooth‑parnings‑PIN';

  @override
  String scanner_linuxPairingPinPrompt(String deviceName) {
    return 'Ange PIN för $deviceName (lämna tomt om ingen).';
  }

  @override
  String get translation_messageTranslation => 'Meddelandets översättning';

  @override
  String get translation_translateBeforeSending => 'Översätt innan du skickar';

  @override
  String get translation_composerEnabledHint =>
      'Meddelandena kommer att översättas innan de skickas.';

  @override
  String get translation_composerDisabledHint =>
      'Skicka meddelanden på det språk de ursprungligen skrevs på.';

  @override
  String translation_translateTo(String language) {
    return 'Översätt till $language';
  }

  @override
  String get translation_translationOptions => 'Översättningsalternativ';

  @override
  String get translation_systemLanguage => 'Språk för systemet';

  @override
  String get background_serviceTitle => 'MeshCore körs';

  @override
  String get background_serviceText => 'Håller noden ansluten';

  @override
  String appSettings_translationModelDeleted(String name) {
    return '$name borttagen';
  }

  @override
  String appSettings_translationModelDeleteFailed(String error) {
    return 'Det gick inte att ta bort: $error';
  }

  @override
  String channels_channelUpdateFailed(String error) {
    return 'Det gick inte att uppdatera kanalen: $error';
  }

  @override
  String get channels_mcmpCompression => 'MCMP-komprimering';

  @override
  String get channels_mcmpCompressionDescription =>
      'Använder modellen mesh-compressor';

  @override
  String get channels_copyPath => 'Kopiera meddelandets sökväg';

  @override
  String get channels_copyPathExtended =>
      'Kopiera meddelandets sökväg (utökad)';

  @override
  String get channels_copiedPath => 'Meddelandets sökväg har kopierats';

  @override
  String get channels_copyPathFailed =>
      'Det gick inte att kopiera meddelandets sökväg';

  @override
  String get settings_copyMsgPathTitle =>
      'Konfigurera kopiering av meddelandets sökväg';

  @override
  String get settings_copyMsgPathDscr =>
      'Redigera mallen som används för att sätta samman sökvägsinformationen för ett kanalmeddelande';

  @override
  String get settings_copyMsgPathEditTemplateTitle => 'Redigera mallen';

  @override
  String get settings_copyMsgPathEditTemplateDscr =>
      'Använd ersättningsmallarna:\n%hopInd% - hoppets ordning\n%hopKey% - hoppets nyckel\n%hopName% - hoppets namn\n%collisionMarker% - markering för repeaterkollision\n%div% - avgränsare (utesluts för sista hoppet)\n%hops% - antal hopp\n\\n - radbrytning';

  @override
  String get settings_copyMsgPathEditFinalTitle => 'Slutligt meddelande';

  @override
  String get settings_copyMsgPathEditFinalDscr =>
      'Tillgängliga mallar:\n%senderName% - avsändarens namn\n%path% - sammansatt sökväg\n%hops% - antal hopp\n\\n - radbrytning';

  @override
  String get settings_channelsSendAsBinary =>
      'Skicka utökade format binärt (kanaler)';

  @override
  String get settings_dmSendAsBinary =>
      'Skicka utökade format binärt (direktmeddelanden)';

  @override
  String get contact_typeChat => 'Chatt';

  @override
  String get contact_typeRepeater => 'Repeater';

  @override
  String get contact_typeRoom => 'Rum';

  @override
  String get contact_typeSensor => 'Sensor';

  @override
  String get contact_typeUnknown => 'Okänd';

  @override
  String get map_zoomIn => 'Zooma in';

  @override
  String get map_zoomOut => 'Zooma ut';

  @override
  String get map_centerMap => 'Centrera karta';

  @override
  String get chrome_bluetoothRequiresChromium =>
      'Web Bluetooth kräver en Chromium-baserad webbläsare.';

  @override
  String channels_communityShortId(String id) {
    return 'ID: $id...';
  }

  @override
  String get pathTrace_legendGpsConfirmed => 'GPS-verifierat';

  @override
  String get pathTrace_legendInferred => 'Antagen position';

  @override
  String get pathMap_viewSingle => 'Enskild';

  @override
  String get pathMap_viewCombined => 'Kombinerat';

  @override
  String get pathMap_play => 'Spela';

  @override
  String get pathMap_pause => 'Pausa';

  @override
  String get pathMap_replay => 'Återspela';

  @override
  String get pathMap_stepBack => 'Föregående hopp';

  @override
  String get pathMap_stepForward => 'Nästa hopp';

  @override
  String get pathMap_animationOn => 'Visa paketanimering';

  @override
  String get pathMap_animationOff => 'Dölj paketanimering';

  @override
  String pathMap_hopOf(int current, int total) {
    return 'Hopp $current av $total';
  }

  @override
  String pathMap_observedPaths(int count) {
    return 'Observerade vägar: $count';
  }

  @override
  String get pathMap_primary => 'Primär';

  @override
  String pathMap_alternate(int index) {
    return 'Alternativ $index';
  }

  @override
  String pathMap_hopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hopp',
      one: '1 hopp',
    );
    return '$_temp0';
  }

  @override
  String pathMap_gpsCount(int confirmed, int total) {
    return '$confirmed/$total GPS';
  }

  @override
  String get pathMap_legendShared => 'Delat segment';

  @override
  String get pathMap_legendEstimated => 'Uppskattat segment';

  @override
  String pathMap_sharedNodeCount(int count) {
    return 'Används av $count vägar';
  }

  @override
  String pathMap_partialAnimation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hopp saknar position — den visade vägen är ofullständig',
      one: '1 hopp saknar position — den visade vägen är ofullständig',
    );
    return '$_temp0';
  }

  @override
  String get pathMap_showAllPaths => 'Visa allt';

  @override
  String get pathMap_hidePath => 'Dölj väg';

  @override
  String get pathMap_showPath => 'Visa väg';

  @override
  String get pathMap_collapsePanel => 'Fäll ihop panel';

  @override
  String get pathMap_expandPanel => 'Expandera panel';

  @override
  String get pathMap_noLocation => 'Ingen position';

  @override
  String get pathMap_followPacket => 'Lås vy till paket';

  @override
  String get pathMap_unfollowPacket => 'Lås upp vy från paket';

  @override
  String get chat_canvas => 'MCOimg-canvas';

  @override
  String get chat_canvasV4Title => 'MCOimg v4 vektorcanvas';

  @override
  String get chat_canvasV4SetupTitle => 'Ny vektorcanvas';

  @override
  String get chat_canvasV4Grid => 'Koordinatrutnät';

  @override
  String get chat_canvasV4GridDescription =>
      'Ett mindre rutnät minskar payloaden, ett större ökar precisionen när figurer placeras ut.';

  @override
  String get chat_canvasV4Background => 'Bakgrund';

  @override
  String get chat_canvasV4Transparent => 'Transparent';

  @override
  String get chat_canvasV4Fill => 'Fyllning';

  @override
  String get chat_canvasV4Stroke => 'Kontur';

  @override
  String get chat_canvasV4StrokeWidth => 'Konturtjocklek';

  @override
  String get chat_canvasV4Closed => 'Slut figuren';

  @override
  String get chat_canvasV4HideFigure => 'Dölj figur';

  @override
  String get chat_canvasV4ShowFigure => 'Visa figur';

  @override
  String get chat_canvasV4MoveUp => 'Flytta upp';

  @override
  String get chat_canvasV4MoveDown => 'Flytta ned';

  @override
  String get chat_canvasV4Objects => 'Figurer';

  @override
  String get chat_canvasV4NoObjects =>
      'Det finns inga figurer på canvasen ännu';

  @override
  String get chat_canvasV4Calculate => 'Beräkna slutbilden';

  @override
  String get chat_canvasV4Redo => 'Gör om';

  @override
  String get chat_canvasV4CanvasSettings => 'Canvasinställningar';

  @override
  String get chat_canvasV4InvalidSize => 'Från 1 till 256';

  @override
  String get chat_canvasV4LoadReference => 'Läs in referensbild';

  @override
  String get chat_canvasV4HideReference => 'Dölj referensbild';

  @override
  String get chat_canvasV4ShowReference => 'Visa referensbild';

  @override
  String get chat_canvasV4RemoveReference => 'Ta bort referensbild';

  @override
  String get chat_canvasV4ReferenceNotEncoded =>
      'Referensbilden ingår inte i payloaden';

  @override
  String get chat_canvasV4PaletteFull => 'Dokumentet använder redan 64 färger';

  @override
  String chat_canvasV4Payload(int bytes) {
    return 'Payload: $bytes byte';
  }

  @override
  String chat_canvasV4PayloadTooLarge(int bytes) {
    return 'Payloaden överskrider tillgänglig storlek med $bytes byte';
  }

  @override
  String get chat_canvasV4ApplyStyle => 'Använd stil';

  @override
  String get chat_canvasV4WaveHint => 'Ange vågens början, slut och djup';

  @override
  String get chat_canvasV4ToolSelect => 'Markera och flytta';

  @override
  String get chat_canvasV4ToolDot => 'Punkt';

  @override
  String get chat_canvasV4ToolPencil => 'Penna';

  @override
  String get chat_canvasV4ToolLine => 'Linje';

  @override
  String get chat_canvasV4ToolPolyline => 'Polylinje';

  @override
  String get chat_canvasV4PolylineHint =>
      'Placera konturens punkter. Tryck på den första punkten eller välj hur du avslutar.';

  @override
  String get chat_canvasV4FinishOpen => 'Avsluta öppen';

  @override
  String get chat_canvasV4FinishClosed => 'Slut formen';

  @override
  String get chat_canvasV4ToolRect => 'Rektangel';

  @override
  String get chat_canvasV4ToolEllipse => 'Ellips';

  @override
  String get chat_canvasV4ToolCircle => 'Cirkel';

  @override
  String get chat_canvasV4ToolWave => 'Våg';

  @override
  String get chat_canvasCrop => 'Beskär/utöka';

  @override
  String get chat_canvasResize => 'Komprimera/sträck ut';

  @override
  String get chat_canvasUnlockSize => 'Lås upp canvasstorleken';

  @override
  String get chat_canvasFormatVer => 'Codecversion';

  @override
  String get chat_canvasPalette => 'Palett';

  @override
  String get chat_canvasPaletteShow => 'Visa paletten';

  @override
  String get chat_canvasPaletteMode => 'Palettprofil';

  @override
  String get chat_canvasPaletteDynamic => 'Dynamisk';

  @override
  String get chat_canvasPaletteDynamicProfile =>
      'Bassats för den dynamiska paletten';

  @override
  String get chat_canvasPaletteDynamicUsed => 'Färger som faktiskt används';

  @override
  String get chat_canvasPaletteDynamicDscr =>
      'Observera! Använd den dynamiska paletten med förnuft! Den är främst avsedd för bilder med gradienter, för att bygga en mindre palett och använda färger som inte hör till samma baspalett. Som referens: en mindre baspalett minskar kostnaden för att koda informationen om de använda nyanserna, och ett lägre totalt antal färger minskar kostnaden för varje pixel på canvasen.';

  @override
  String get chat_canvasPaletteAlpha => 'Transparensfärg';

  @override
  String get chat_canvasChangeSize => 'Ändra canvasstorleken';

  @override
  String get chat_canvasTrim => 'Beskär tomt utrymme';

  @override
  String get chat_canvasWidth => 'Bredd';

  @override
  String get chat_canvasHeight => 'Höjd';

  @override
  String get chat_canvasGridShow => 'Visa rutnätet';

  @override
  String get chat_canvasRulerShow => 'Visa linjalen';

  @override
  String get chat_canvasGridColor => 'Rutnätets färg';

  @override
  String get chat_canvasSave => 'Spara till fil';

  @override
  String get chat_canvasLoad => 'Läs in från fil';

  @override
  String get chat_formatBold => 'Fet';

  @override
  String get chat_formatItalic => 'Kursiv';

  @override
  String get chat_formatUnderline => 'Understruken';

  @override
  String get chat_formatStrikethrough => 'Genomstruken';

  @override
  String get chat_formatMono => 'Fast bredd';

  @override
  String get chat_formatColor => 'Textfärg';

  @override
  String chat_canvasSendPayloadExceed(int count) {
    return 'Det gick inte att skicka: payloaden överskreds med $count byte. Minska antalet detaljer eller canvasstorleken.';
  }

  @override
  String chat_canvasCurrentPayload(int payload) {
    return 'Aktuell payload: $payload';
  }

  @override
  String get chat_canvasActive => 'Visa canvasen';

  @override
  String get chat_canvasShowLockBtn => 'Visa canvasens låsknapp';

  @override
  String get chat_canvasSendToEdit => 'Skicka till canvasen';

  @override
  String get chat_canvasSendToGallery => 'Spara i galleriet';

  @override
  String get chat_canvasGalleryShowPNG => 'Visa originalet (PNG)';

  @override
  String get chat_canvasGalleryShowBIN => 'Visa som Bin';

  @override
  String get chat_canvasGalleryRemove => 'Ta bort';

  @override
  String get chat_canvasGalleryRemoveConfirm =>
      'Ta bort bilden från galleriet?';

  @override
  String chat_canvasFormatNotSupported(int received, int current) {
    return 'MCOimg-version: $received, den nuvarande codecen stöder upp till $current';
  }

  @override
  String get chat_canvasSaveBinary => 'Spara till binär fil';

  @override
  String chat_canvasCannotSend(int count) {
    return 'Det gick inte att skicka: payloaden överskreds med $count byte. Redigera bilden och försök igen.';
  }

  @override
  String get chat_canvasCompressionLevel => 'Komprimeringsnivå';

  @override
  String get chat_canvasCompressionLevelNormal => 'Normal';

  @override
  String get chat_canvasCompressionLevelHigh => 'Hög';

  @override
  String get chat_canvasCompressionLevelExtreme => 'Extrem';

  @override
  String get chat_showHops => 'Visa hopp';

  @override
  String get settings_modSettings => 'Inställningar för modifieringen';

  @override
  String get settings_modSettingsSubtitle =>
      'Det här avsnittet samlar alternativ som saknas i det ursprungliga meshcore_open';

  @override
  String get settings_modSettingsVisual => 'Utseende';

  @override
  String get settings_modSettingsMessaging => 'Meddelanden';

  @override
  String get settings_modSettingsMCMP => 'MCMP';

  @override
  String get settings_mcmp_version => 'Version';

  @override
  String get settings_mcmp_useSign => 'Meddelandesignering';

  @override
  String get settings_mcmp_signed => 'Med signaturkontroll';

  @override
  String get settings_mcmp_noSign => 'Utan signaturkontroll';

  @override
  String get settings_mcmp_senderNameCollision =>
      'Avsändarens namn är inte unikt!';

  @override
  String get chat_mcmpSignatureValid => 'Signaturen är giltig';

  @override
  String get chat_mcmpSignatureInvalid => 'Ogiltig signatur!';

  @override
  String get chat_mcmpSignatureUnverifiable =>
      'Signaturen kan inte kontrolleras — avsändaren finns inte bland kontakterna';

  @override
  String get chat_mcmpSignatureTransport =>
      'Verifierad genom transportens kryptering';

  @override
  String get chat_mcmpManualRecheckSign => 'Kontrollera signaturen igen';

  @override
  String get chat_mcmpSignatureCheckStatus => 'Signaturkontroll';

  @override
  String get chat_mcmpSigningFailed => 'Det gick inte att signera meddelandet';

  @override
  String get chat_mcmpAnswerTo => 'MCMPv3-svar på';

  @override
  String get chat_mcmpSignedTimestamp => 'MCMP-tidsstämpel';

  @override
  String chat_mcmpTimestampQueerly(int time) {
    return 'MCMP-tidsstämpeln skiljer sig $time sekunder från paketets tidsstämpel';
  }

  @override
  String chat_mcmpTimestampQueerlyReceived(int time) {
    return 'Den signerade MCMP-tidsstämpeln skiljer sig avsevärt från mottagningstiden, med $time sekunder';
  }

  @override
  String get chat_timestampPacket => 'Paketets tidsstämpel';

  @override
  String get settings_modSettingsMCOimg => 'MCOimg';

  @override
  String get settings_modSettingsVisualShowMCOimgFormat =>
      'MCOimg: visa märket för formatversion';

  @override
  String get settings_modSettingsVisualShowMCOimgAlgo =>
      'MCOimg: visa märket för kodningsalgoritm';

  @override
  String get settings_modSettingsVisualShowMCOimgBytes =>
      'MCOimg: visa bildens storlek (byte)';

  @override
  String get settings_modSettingsVisualShowMCOimgResolution =>
      'MCOimg: visa upplösningen';

  @override
  String get settings_modSettingsMCOimg_showReplacements =>
      'Visa bildernas original i stället för LoRa-versionerna';

  @override
  String get settings_modSettingsMCOimg_replacementsScale =>
      'Skala originalen i chattarna';

  @override
  String get settings_modSettingsMCOimg_replacementsLottieScale =>
      'Storleksbegränsning för lottie-ersättningar';

  @override
  String get settings_modSettingsMCOimg_scaleNearestNeighbor =>
      'Skala som Nearest Neighbor';

  @override
  String get settings_modSettingsMCOimg_replacementsSharp =>
      'Skärp originalen i chattarna';

  @override
  String get settings_modSettingsMCOimg_replacementsSharpDscr =>
      'Observera! Inaktiverar GIF-animeringen!';

  @override
  String get settings_modSettingsHideChInd => 'Dölj kanalindexet';

  @override
  String get settings_modSettingsHideRadioStats =>
      'Dölj radiostatistiken i rubriken';

  @override
  String get settings_modSettingsSNRindicatorAllRepActivity =>
      'SNR-indikator: utlös vid alla svar från repeatrar, inte bara vid adverts';

  @override
  String get settings_modSettingsIncomingQuoteAsMentions =>
      'Visa citat i inkommande meddelanden som omnämnanden';

  @override
  String get settings_modSettingsSimplifiedMentions =>
      'Förenklad stil för omnämnanden i meddelanden';

  @override
  String get settings_modSettingsSharedMsgHistory => 'Delad meddelandehistorik';

  @override
  String get settings_modSettingsSharedMsgHistoryDscr =>
      'Sammanslagning av meddelandehistoriken som tagits emot från olika enheter; den slutliga historiken lagras endast i applikationen';

  @override
  String get settings_modSettingsSharedMsgHistoryDisabled => 'Inaktiverad';

  @override
  String get settings_modSettingsSharedMsgHistoryChannels => 'Endast kanaler';

  @override
  String get settings_modSettingsSharedMsgHistoryContacts => 'Endast kontakter';

  @override
  String get settings_modSettingsSharedMsgHistoryAll => 'Alla chattar';

  @override
  String get settings_modSettingsMessagingShowCompressionRatio =>
      'Visa komprimeringsgraden';

  @override
  String get settings_modSettingsMessagingCompressionRatioWithSendername =>
      'Ta även med nodens namn';

  @override
  String get settings_modSettingsVisualHideMapZoomControls =>
      'Dölj zoompanelen på kartan';

  @override
  String get settings_modSettingsVisualShowMsgRegion =>
      'Visa meddelandets region';

  @override
  String channels_messageRegion(String region) {
    return 'Region: $region';
  }

  @override
  String get channels_messageRegionUnknown => 'okänd';

  @override
  String get channels_messageRegionNotMatchesWithKnown => 'ingen träff';

  @override
  String get channels_messageRegionEmpty => 'inte angiven';

  @override
  String get settings_defaultRegionScope => 'Nodens standardregion';

  @override
  String get settings_defaultRegionScopeChanged =>
      'Standardregionen har ändrats';

  @override
  String get settings_defaultRegionScopeChangeFailed =>
      'Det gick inte att ändra regionen';

  @override
  String get settings_defaultRegionScopeEmpty => 'Inte angiven';

  @override
  String get settings_defaultRegionScopeWaitForSync =>
      'Vänta tills synkroniseringen är klar';

  @override
  String get common_reset => 'Återställ';

  @override
  String get connection_autoconnect => 'Anslut automatiskt';

  @override
  String settings_modSettingsNoRetraInfo(int time) {
    return 'Inga vidaresändningar har hörts på $time s.';
  }

  @override
  String get settings_modSettingsNoRetraHeading =>
      'Markera meddelanden som inte skickade om inga vidaresändningar hörs inom så här många sekunder:';

  @override
  String get settings_modSettingsNoRetraDscr =>
      'Observera! På grund av en mekanism i nodens firmware kan kanalmeddelanden större än ~133 byte fysiskt inte få bekräftelser och kommer alltid att markeras som misslyckade! Använd det här alternativet tillsammans med payloadgränsen i appens inställningar!';

  @override
  String get settings_selfTelemetryShow => 'Visa sensorerna';

  @override
  String get settings_modSettingsVisualChannelsUnreadSorting =>
      'Sortera kanalerna efter olästa meddelanden';

  @override
  String get settings_modSettingsMessagingBackgroundTCP =>
      'Behåll TCP-anslutningen i bakgrunden';

  @override
  String get settings_modSettingsDPIchange => 'DPI-justering';

  @override
  String get settings_modSettingsDPIchangeToIcons => 'Tillämpa på ikoner';

  @override
  String get settings_modSettingsMonochromeSenderNames =>
      'Enfärgade avsändarnamn';

  @override
  String get chat_MCOimgOpenGallery => 'Öppna MCOimg-galleriet';

  @override
  String get chat_additionalActions => 'Åtgärdsmeny';

  @override
  String get mcogallery_common => 'Allmänt';

  @override
  String get mcogallery_addPack => 'Lägg till paket';

  @override
  String get mcogallery_removePack => 'Ta bort paket';

  @override
  String mcogallery_removePackConfirm(String name) {
    return 'Bekräfta borttagningen av paketet «$name»';
  }

  @override
  String get mcogallery_addGroup => 'Lägg till grupp';

  @override
  String get mcogallery_removeGroup => 'Ta bort grupp';

  @override
  String get mcogallery_showLora => 'Visa LoRa-varianten';

  @override
  String get mcogallery_showPacked => 'Visa den förbättrade varianten';

  @override
  String get chat_sendSelfContact => 'Skicka min kontakt';

  @override
  String get chat_sendContact => 'Dela kontakt';

  @override
  String get chat_addContact => 'Lägg till kontakt';

  @override
  String get chat_sureToReplaceContact => 'Kontakten finns redan, ersätta den?';

  @override
  String get contacts_addContactByPubkey => 'Lägg till kontakt via nyckel';

  @override
  String get contacts_addContactByPubkey_contactType => 'Kontakttyp';

  @override
  String get chat_contactIsYou => 'Det är din egen kontakt';

  @override
  String chat_contactType(String contacttype) {
    return 'Kontakttyp: $contacttype';
  }

  @override
  String get chat_contactTypeNode => 'Nod';

  @override
  String get chat_contactTypeRepeater => 'Repeater';

  @override
  String get chat_contactTypeRoom => 'Rumsserver';

  @override
  String get chat_contactTypeSensor => 'Sensor';

  @override
  String get chat_myLocation => 'Skicka min position';

  @override
  String get chat_locationFromMap => 'Skicka koordinater från kartan';

  @override
  String get settings_modSettingsRoomServer => 'Rumsservrar och kontakter';

  @override
  String get settings_modSettingsRoomServerShowNotemptyOnChatscreen =>
      'Visa rumsservrar med meddelandehistorik på samma skärm som kanalerna';

  @override
  String get settings_modSettingsRoomServerShowNotemptyContactsOnChatscreen =>
      'Visa kontakter med historik på samma skärm som kanalerna';

  @override
  String get settings_modSettingsRoomServerDisableRoomAndContactsSorting =>
      'Behåll den tidigare dra-och-släpp-funktionen: att ändra kanalernas ordning ändrar deras ordning på noden, och kontakter eller servrar kan inte sorteras';

  @override
  String get settings_modSettingsMapAndLocation => 'Karta och plats';

  @override
  String get settings_modSettingsAlwaysRequestMapLocation =>
      'Begär alltid plats när kartan öppnas';

  @override
  String get settings_modSettingsExactQuote =>
      'Använd exakt citering för vanliga meddelanden';

  @override
  String get settings_modSettingsExactQuoteLimit =>
      'Bytegräns för att bygga citatet';

  @override
  String get settings_modSettingsExactQuoteLimitDscr =>
      'Standardgränsen är 30. Utöver gränsen läggs 5 byte till som formaterar citatet för klienter som inte stöder den här funktionen';

  @override
  String get settings_appSettingsCustomChemistry => 'Egen';

  @override
  String get map_clearDiscoveredContactsCache => 'Rensa den lokala nodcachen';

  @override
  String get map_clearDiscoveredContactsCacheDisclaimer =>
      'Är du säker på att du vill rensa cachen med upptäckta kontakter? Detta påverkar inte kontakterna på själva noden.';

  @override
  String get snrIndicator_v2_nearByRepeaters => 'Repeatrarnas aktivitet';

  @override
  String get app_connectionLostReconnect =>
      'Anslutningen till noden har brutits, återansluter...';

  @override
  String get app_connectionLostReconnected =>
      'Anslutningen till noden har återupprättats';

  @override
  String get app_connectionLostBreaked => 'Anslutningen till noden har brutits';

  @override
  String get contacts_batchOperations => 'Massåtgärder';

  @override
  String get contacts_batchOperations_notSelected =>
      'Du har inte valt några kontakter att behandla!';

  @override
  String get contacts_batchOperations_removeConfirm =>
      'Ta bort de valda kontakterna från nodens minne?';

  @override
  String get contacts_batchOperations_removeSuccess =>
      'De valda kontakterna har tagits bort';

  @override
  String get contacts_batchOperations_removeFail =>
      'Det gick inte att ta bort kontakterna – kontrollera listan igen';

  @override
  String get contacts_batchOperations_commonSuccess => 'Åtgärden lyckades';

  @override
  String get contacts_batchOperations_commonFail =>
      'Det gick inte att slutföra åtgärden';

  @override
  String get contacts_batchOperations_selectFiltered => 'Välj de filtrerade';

  @override
  String get chat_searchMessages => 'Sök meddelanden';

  @override
  String get chat_searchMessages_placeholder =>
      'Från 3 tecken, skiftlägesokänsligt';

  @override
  String get chat_searchMessages_results => 'Sökresultat';

  @override
  String chat_searchMessages_results_found(int count) {
    return '$count meddelanden hittades';
  }

  @override
  String chat_searchMessages_results_channel(String name) {
    return 'Kanal $name';
  }

  @override
  String chat_searchMessages_results_room(String name) {
    return 'Rum $name';
  }

  @override
  String chat_searchMessages_results_contact(String name) {
    return 'Konversation med $name';
  }

  @override
  String get app_offline => 'Offline';

  @override
  String get app_offline_unableToMessage =>
      'I offlineläge kan du inte skicka meddelanden eller utföra andra åtgärder';

  @override
  String get app_offline_sharedMode => 'Kombinerad historik';

  @override
  String get settings_infoHardware => 'Hårdvara';

  @override
  String get appSettings_batteryLipoHv => 'LiPo HV (3,0-4,35 V)';

  @override
  String get chat_sendImage => 'Skicka bild';

  @override
  String get chat_imagePickFailed => 'Kunde inte öppna den bilden';

  @override
  String get imageMessages_enableTitle => 'Aktivera bildmeddelanden';

  @override
  String get imageMessages_enableSubtitle =>
      'Skicka bilder över meshnätet. Kräver en engångsnedladdning av bildmodellen.';

  @override
  String get imageMessages_modelSectionTitle => 'Bildmodell';

  @override
  String get imageMessages_downloadModel => 'Ladda ner';

  @override
  String get imageMessages_cancelDownload => 'Avbryt';

  @override
  String get imageMessages_removeModel => 'Ta bort modellen';

  @override
  String get imageMessages_modelReady => 'Färdig';

  @override
  String get imageMessages_modelNotPublished =>
      'Inte publicerad än — den här versionen kan inte ladda ner den.';

  @override
  String get imageMessages_downloadFailed =>
      'Bildmodellen kunde inte laddas ner.';

  @override
  String get imageMessages_autoProcessTitle => 'Bearbeta bilder automatiskt';

  @override
  String get imageMessages_autoProcessSubtitle =>
      'Rekonstruera varje bild så snart den kommer fram. Använder cirka 2 GB minne i ungefär en sekund varje gång; lämna avstängt för att i stället rekonstruera med ett tryck.';

  @override
  String get imageSend_title => 'Skicka bild';

  @override
  String get imageSend_cropNote =>
      'Skalad till 512 × 512 · bildförhållandet bevaras inte';

  @override
  String get imageSend_originalSize => 'Original';

  @override
  String get imageSend_onAirSize => 'I etern';

  @override
  String get imageSend_quality => 'Kvalitet';

  @override
  String get imageSend_qualityStandard => 'Standard';

  @override
  String get imageSend_qualityHigh => 'Hög';

  @override
  String get imageSend_packetsLabel => 'Paket';

  @override
  String get imageSend_airtimeLabel => 'Sändningstid';

  @override
  String get imageSend_sizeLabel => 'Nyttolast';

  @override
  String imageSend_packetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'paket',
      one: 'paket',
    );
    return '$count $_temp0';
  }

  @override
  String imageSend_range(String min, String max) {
    return '$min–$max';
  }

  @override
  String get imageSend_unknownValue => '—';

  @override
  String get imageSend_radioUnknownTitle => 'Radioinställningarna är okända';

  @override
  String get imageSend_radioUnknownBody =>
      'Anslut till en enhet så att sändningstiden kan beräknas.';

  @override
  String get imageSend_longSendTitle => 'Lång sändning';

  @override
  String imageSend_longSendBody(String duration) {
    return 'Det här upptar kanalen i ungefär $duration.';
  }

  @override
  String get imageSend_floodNote =>
      'Flood-routing: varje repeater inom räckhåll sänder om varje paket, så kanalen är upptagen längre än så.';

  @override
  String get imageSend_parityTitle => 'Lägg till återställningspaket';

  @override
  String get imageSend_paritySubtitle =>
      'Ett extra paket. Gruppmeddelanden kvitteras inte, så det här låter mottagaren återskapa bilden om ett enstaka paket går förlorat.';

  @override
  String get imageSend_send => 'Skicka';

  @override
  String get imageSend_cancel => 'Avbryt';

  @override
  String get imageSend_encodeFailed => 'Den här bilden kunde inte kodas.';

  @override
  String get imageSend_codecDownloading => 'Bildmodellen hämtas fortfarande.';

  @override
  String get imageSend_codecUnavailable =>
      'Bildsändning är inte tillgänglig på den här enheten.';

  @override
  String get imageSend_codecDisabled =>
      'Bildmeddelanden är avstängda i inställningarna.';

  @override
  String get imageSend_deviceUnsupported =>
      'Den här radion kan inte skicka bildpaket. Anslut en enhet med companion-firmware v1.15.0 eller senare.';

  @override
  String get imageSend_directMessagesUnsupported =>
      'Bilder färdas som gruppdata och kan därför bara skickas till en kanal — inte i ett direktmeddelande.';

  @override
  String get imageSend_tooLarge =>
      'Bilden kodades till fler paket än mesh-formatet tillåter.';

  @override
  String imageSend_sentConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'paket',
      one: 'paket',
    );
    return 'Bilden skickades som $count $_temp0.';
  }

  @override
  String imageSend_sendFailed(String error) {
    return 'Bilden kunde inte skickas: $error';
  }

  @override
  String imageSend_sendingProgress(int sent, int total) {
    return 'Skickar bild — paket $sent av $total';
  }

  @override
  String receivedImage_senderPrefix(String prefix) {
    return 'Nod $prefix';
  }

  @override
  String receivedImage_incoming(int received, int total) {
    return '$received av $total paket';
  }

  @override
  String get receivedImage_queued => 'Väntar på avkodning';

  @override
  String get receivedImage_tapToDecode => 'Tryck för att avkoda';

  @override
  String get receivedImage_decoding => 'Rekonstruerar… cirka 1 s';

  @override
  String receivedImage_incomplete(int received, int total) {
    return 'Bilden är ofullständig — $received av $total paket har kommit fram';
  }

  @override
  String get receivedImage_corrupt => 'Bilden kunde inte rekonstrueras';

  @override
  String get receivedImage_decoderMissing =>
      'Bild mottagen — bildavkodning är avstängd';

  @override
  String get receivedImage_evicted => 'Bild inte lagrad längre';

  @override
  String get receivedImage_retry => 'Försök igen';

  @override
  String get receivedImage_decodeAgain => 'Avkoda igen';

  @override
  String get receivedImage_openSettings => 'Konfigurera';

  @override
  String get receivedImage_tapToProcess => 'Tryck för att bearbeta';

  @override
  String receivedImage_awaiting(int bytes, int packets) {
    String _temp0 = intl.Intl.pluralLogic(
      packets,
      locale: localeName,
      other: 'paket',
      one: 'paket',
    );
    return '$bytes byte · $packets $_temp0';
  }

  @override
  String imageSend_secondsValue(String seconds) {
    return '$seconds sekunder';
  }

  @override
  String imageSend_minutesSecondsValue(String minutes, String seconds) {
    return '$minutes min $seconds s';
  }

  @override
  String get map_copyCoordsFromMap => 'Kopiera koordinater';

  @override
  String get map_coordsCopied => 'Koordinater kopierade';

  @override
  String get appSettings_yandexApiKey => 'API-nyckel för Yandex Tiles';

  @override
  String get appSettings_yandexApiKeyMissing =>
      'Inte angiven – OpenStreetMap visas';

  @override
  String get appSettings_yandexApiKeyDialogDescription =>
      'Ange din egen nyckel från Yandex utvecklarpanel. Den kostnadsfria Tiles API-nivån tillåter upp till 30 förfrågningar per sekund. Kartdata © Yandex.';

  @override
  String get appSettings_yandexSigningSecret =>
      'Signeringshemlighet för Yandex';

  @override
  String get appSettings_yandexSigningSecretMissing =>
      'Inte angiven – förfrågningar skickas osignerade';

  @override
  String get appSettings_yandexSigningSecretDialogDescription =>
      'Valfritt. Klistra in signeringshemligheten som är kopplad till din nyckel i Yandex-konsolen. I valfritt signeringsläge fungerar även osignerade förfrågningar.';

  @override
  String get appSettings_yandexTileScale => 'Upplösning för Yandex-rutor';

  @override
  String appSettings_yandexTileScaleSubtitle(String scale) {
    return 'Nu: $scale';
  }

  @override
  String get appSettings_yandexTileScaleDescription =>
      'Högre värden hämtar samma ruta i större pixelstorlek — skarpare på täta skärmar, men mer trafik och cacheutrymme.';

  @override
  String get settings_aboutYandexMapsTerms =>
      'Kartrutor från Yandex Maps. Användarvillkor: \nhttps://yandex.ru/legal/maps_termsofuse/';

  @override
  String get map_showMarksFromChannels => 'Visa markörer från...';

  @override
  String get map_markerStyleTitle => 'Markörstil';

  @override
  String get map_markerStyleColor => 'Fyllningsfärg';

  @override
  String get map_markerStyleIcon => 'Ikon';

  @override
  String get map_removeMarkerForEveryone => 'Ta bort för alla';

  @override
  String get chat_poiRemoved => 'POI borttagen';

  @override
  String get chat_blockSender => 'Blockera avsändare';

  @override
  String get chat_unblockSender => 'Avblockera avsändare';

  @override
  String get chat_senderBlocked => 'avsändare blockerad';

  @override
  String get chat_blockedSenders => 'Blockerade avsändare';

  @override
  String get chat_blockedSendersEmpty => 'Inga blockerade avsändare';

  @override
  String get chat_blockedSendersAllChannels => 'Alla kanaler';

  @override
  String get chat_blockSenderName => 'Avsändarens namn';

  @override
  String get chat_hideBlockedSenderMessages => 'Dölj meddelanderader';

  @override
  String get chat_showBlockedSenderMessages => 'Visa meddelanderader';

  @override
  String get imageSend_previewShowAsReceived => 'Visa som mottaget';

  @override
  String get imageSend_previewShowOriginal => 'Visa original';

  @override
  String get imageSend_previewAsReceived => 'Så här ser mottagarna bilden';

  @override
  String get imageSend_previewDecodeFailed =>
      'Det gick inte att avkoda förhandsgranskningen';

  @override
  String get settings_modSettingsLastHopSignal =>
      'Visa SNR/RSSI för sista hoppet i kanaler';

  @override
  String get repeater_cliClearNeighbors => 'Rensa grannlistan';

  @override
  String get settings_backgroundPermissions =>
      'Begär bakgrundsbehörigheter på nytt';

  @override
  String get settings_backgroundPermissionsSubtitle =>
      'Kontrollera undantaget från batterioptimering och begär det igen';

  @override
  String get settings_backgroundPermissionsGranted =>
      'Behörigheten är redan beviljad';

  @override
  String get chat_selectSendAction => 'Välj sändningsåtgärd';

  @override
  String get chat_sendImageLora => 'Skicka bild via MeshCore';

  @override
  String get reaction_report => 'Emoji-reaktioner';

  @override
  String get messageHistoryMigrationWarningTitle =>
      'Meddelandehistoriken flyttades bara delvis';

  @override
  String messageHistoryMigrationWarningDescription(
    int histories,
    int messages,
  ) {
    return 'Vid flytten gick det inte att återställa $histories konversationer och $messages enskilda meddelanden. Resten av historiken bevarades.';
  }

  @override
  String get messageHistoryMigrationManage => 'Hantera lagringen';

  @override
  String get settings_modSettingsMessageStorage => 'Meddelandelagring';

  @override
  String get messageHistoryDatabaseTitle => 'Databashantering';

  @override
  String get messageHistoryDatabaseSubtitle =>
      'Statistik, återställning och underhåll av meddelandehistoriken';

  @override
  String get messageHistoryDatabaseOverview => 'Databasens status';

  @override
  String get messageHistoryDatabasePath => 'Sökväg till databasen';

  @override
  String get messageHistoryDatabaseFileSize => 'Filstorlek';

  @override
  String get messageHistoryDatabaseDirectCount => 'Direktmeddelanden';

  @override
  String get messageHistoryDatabaseChannelCount => 'Kanalmeddelanden';

  @override
  String get messageHistoryDatabaseReclaimable => 'Kan frigöras';

  @override
  String get messageHistoryDatabaseQuarantine => 'Migreringskarantän';

  @override
  String messageHistoryDatabaseQuarantineCount(int count, String size) {
    return 'Avvisade poster: $count · $size';
  }

  @override
  String get messageHistoryDatabaseQuarantineEmpty => 'Inga avvisade poster';

  @override
  String get messageHistoryDatabaseRetry => 'Försök återställa igen';

  @override
  String get messageHistoryDatabaseRetryDescription =>
      'Kontrollera karantänen på nytt med den aktuella tolken och lägg tillbaka reparerade meddelanden i historiken.';

  @override
  String messageHistoryDatabaseRetryResult(int restored, int remaining) {
    return 'Återställda: $restored, kvar: $remaining';
  }

  @override
  String get messageHistoryDatabaseDiagnostic => 'Exportera diagnostik';

  @override
  String get messageHistoryDatabaseDiagnosticDescription =>
      'Skapa en rapport utan meddelandetext och kontaktnycklar.';

  @override
  String get messageHistoryDatabaseRecovery => 'Exportera återställningsdata';

  @override
  String get messageHistoryDatabaseRecoveryDescription =>
      'Skapa en fil med enbart de avvisade posterna. Den kan innehålla privata konversationer.';

  @override
  String get messageHistoryDatabaseRecoveryWarningTitle =>
      'Export av känsliga data';

  @override
  String get messageHistoryDatabaseRecoveryWarningDescription =>
      'Återställningsfilen innehåller den ursprungliga texten i de avvisade meddelandena och identifierare för konversationerna. Granska den innan du delar den med någon.';

  @override
  String get messageHistoryDatabaseDeleteAfterExportTitle =>
      'Ta bort karantänen efter exporten?';

  @override
  String get messageHistoryDatabaseDeleteAfterExportDescription =>
      'Återställningsfilen har sparats. Vill du ta bort de exporterade avvisade posterna ur databasen?';

  @override
  String get messageHistoryDatabaseClearQuarantine => 'Ta bort karantänen';

  @override
  String get messageHistoryDatabaseClearQuarantineDescription =>
      'Ta bort de avvisade posterna utan möjlighet till återställning.';

  @override
  String get messageHistoryDatabaseClearWarningTitle =>
      'Ta bort de avvisade posterna?';

  @override
  String get messageHistoryDatabaseClearWarningDescription =>
      'Efter borttagningen går meddelanden i karantän varken att återställa eller exportera.';

  @override
  String get messageHistoryDatabaseMaintenance => 'Underhåll';

  @override
  String get messageHistoryDatabaseIncrementalVacuum =>
      'Frigör oanvänt utrymme';

  @override
  String get messageHistoryDatabaseIncrementalVacuumDescription =>
      'Lämna successivt tillbaka oanvända SQLite-sidor till operativsystemet.';

  @override
  String get messageHistoryDatabaseIncrementalVacuumUnavailableDescription =>
      'Den här databasen kräver först en fullständig VACUUM.';

  @override
  String get messageHistoryDatabaseFullVacuum =>
      'VACUUM (bygg om databasen helt)';

  @override
  String get messageHistoryDatabaseFullVacuumDescription =>
      'Bygg om databasfilen helt. Det kan ta tid och kräva extra ledigt utrymme.';

  @override
  String get messageHistoryDatabaseFullVacuumWarningTitle =>
      'Bygga om databasen helt?';

  @override
  String get messageHistoryDatabaseFullVacuumWarningDescription =>
      'Stäng inte appen förrän åtgärden är klar. SQLite kan behöva extra utrymme motsvarande databasens nuvarande storlek.';

  @override
  String get messageHistoryDatabaseCopyPath => 'Kopiera sökvägen';

  @override
  String get messageHistoryDatabasePathCopied => 'Sökvägen kopierad';

  @override
  String messageHistoryDatabaseExportSaved(String path) {
    return 'Filen sparad: $path';
  }

  @override
  String get messageHistoryDatabaseExportShared =>
      'Filen skickades till systemets delningsmeny';

  @override
  String messageHistoryDatabaseDeleted(int count) {
    return 'Borttagna poster: $count';
  }

  @override
  String get messageHistoryDatabaseOperationComplete => 'Åtgärden slutförd';

  @override
  String messageHistoryDatabaseOperationFailed(String error) {
    return 'Åtgärden misslyckades: $error';
  }

  @override
  String get settings_supportDevelopment => 'Stöd utvecklingen';

  @override
  String get donate_intro =>
      'Tack för att du tittade förbi!\nOm du gillar den här modifieringen kan du stödja utvecklingen med en donation.';

  @override
  String get donate_tipLinkLabel => 'Länk för dricks:';

  @override
  String get donate_upstreamAuthor =>
      'Författaren till det ursprungliga meshcore_open — zjs81 — tar emot donationer här:';

  @override
  String get chat_canvasV4ToolText => 'Text';

  @override
  String get chat_canvasV4TextAlignLeft => 'Vänster';

  @override
  String get chat_canvasV4TextAlignCenter => 'Centrerat';

  @override
  String get chat_canvasV4TextAlignRight => 'Höger';

  @override
  String chat_canvasV4TextWidth(int cells) {
    return 'Områdets bredd: $cells';
  }

  @override
  String chat_canvasV4TextFontSize(int size) {
    return 'Teckenstorlek: $size';
  }

  @override
  String get channels_mcotxtPlainWhenSmaller =>
      'Skicka vanligt meddelande om det är mindre';

  @override
  String get settings_modSettingsRecoverLongEchoes =>
      'Återskapa upprepningar av långa paket';

  @override
  String get settings_modSettingsRecoverLongEchoesDscr =>
      'Känn igen en RX-loggkopia av vårt eget kanalmeddelande som BLE-ramgränsen kapat';

  @override
  String get chat_canvasV4TextSize => 'Textstorlek';

  @override
  String chat_unknownAppDataPlaceholder(
    String namespace,
    int subtype,
    int version,
  ) {
    return 'Tog emot ett paket av okänd undertyp ($namespace, undertyp $subtype version $version); appen kan behöva uppdateras';
  }

  @override
  String chat_unknownAppDataPlaceholderNamespace(String namespace) {
    return 'Tog emot ett paket i ett format som den här appen inte kan läsa ($namespace); appen kan behöva uppdateras';
  }

  @override
  String get chat_showWithoutMarkdown => 'Visa utan Markdown';

  @override
  String get chat_showWithMarkdown => 'Visa med Markdown';

  @override
  String get channels_scanQrInstructions =>
      'Rikta kameran mot en kanals QR-kod';

  @override
  String get channels_invalidQrCode => 'Det här är ingen QR-kod för en kanal';

  @override
  String channels_qrAlreadyAdded(String name) {
    return 'Kanalen \"$name\" är redan tillagd';
  }

  @override
  String get channels_shareQrHint =>
      'Skanna QR-koden för att lägga till kanalen.';

  @override
  String get channels_shareSecretKey => 'Hemlig nyckel';

  @override
  String get channels_shareRegionScope => 'Kanalens region';

  @override
  String get channels_shareKeyCopied => 'Hemlig nyckel kopierad';

  @override
  String get channels_shareLinkCopied => 'Länk kopierad';

  @override
  String get channels_shareQrTapToCopy =>
      'Tryck på QR-koden för att kopiera den som en bild.';

  @override
  String get channels_shareQrTapToShare =>
      'Tryck på QR-koden för att spara eller dela den som en bild.';

  @override
  String get channels_shareQrImageCopied => 'QR-koden kopierad som bild';

  @override
  String get channels_shareQrImageFailed =>
      'Det gick inte att skapa bilden med QR-koden';

  @override
  String channels_qrUpdateExisting(String name) {
    return 'Kanalen $name finns redan. Uppdatera dess egenskaper?';
  }

  @override
  String get settings_modSettingsDirectEchoRecovery =>
      'Ta emot direktmeddelanden utan att vänta på att rutten fullbordas';

  @override
  String get settings_modSettingsDirectEchoRecoveryDscr =>
      'Observera! Nodens privata nyckel exporteras till appens minne, så att appen själv dekrypterar paketet i stället för noden.';

  @override
  String get settings_modSettingsDirectEchoRecoveryPrompt =>
      'Aktivera snabbare mottagning av direktmeddelanden?\nFör detta hämtas nodens privata nyckel till appens arbetsminne.';

  @override
  String get channelPath_incompletePaths => 'Ofullständiga sökvägar';

  @override
  String channelPath_incompletePathTitle(int index, String hops) {
    return 'Ofullständig sökväg $index • $hops';
  }

  @override
  String get channelPath_copyInvertedPath => 'Kopiera omvänd rutt';

  @override
  String get channelPath_invertedPathCopied => 'Omvänd rutt kopierad';

  @override
  String get discoveredContacts_alreadyAdded =>
      'Noden finns redan bland kontakterna';

  @override
  String get chat_floodRegionNode => 'Nodens region';

  @override
  String chat_floodRegionNodeWith(String region) {
    return 'Nodens region: $region';
  }

  @override
  String get chat_floodRegionNone => 'Ingen region';

  @override
  String get chat_stopSending => 'stoppa sändning';

  @override
  String get urlImage_enable => 'Aktivera URL-bilder';

  @override
  String get urlImage_possible =>
      'Möjlig URL-bild; aktivera den i Inställningar.';

  @override
  String get settings_radioSettingsNotApplied =>
      'Radion tillämpade inte dessa inställningar';

  @override
  String get settings_publicKeyCopied => 'Publik nyckel kopierad';

  @override
  String get channels_noFreeSlots => 'Alla kanalplatser är upptagna';

  @override
  String get repeater_frequencyRangeHelper => '150-2500 MHz';

  @override
  String get repeater_frequencyInvalid => 'Ogiltig frekvens (150-2500 MHz)';

  @override
  String get repeater_txPowerRangeHelper => '-9 till 30 dBm';

  @override
  String get repeater_recvErrors => 'Mottagningsfel';

  @override
  String get room_postsStored => 'Inlägg';

  @override
  String get room_postsPushed => 'Skickade inlägg';

  @override
  String get repeater_cliRegionLoadActive =>
      'Regionladdningsläge: skicka ett regionnamn per rad, indraget med blanksteg under sin förälder (lägg till F efter namnet för att tillåta flood). Rader får inget svar. Skicka en tom rad för att avsluta, och sedan \"region save\" för att spara resultatet.';

  @override
  String get repeater_cliRegionLoadHint =>
      'Regionrad, eller tom för att avsluta';

  @override
  String get repeater_cliRegionLoadEnd => '(slut på regionladdning)';

  @override
  String get repeater_cliHelpRegionDef =>
      'Definierar en kedja av regioner i ett kommando: varje namn läggs till under det föregående; \"name,parent\" lägger till namnet och fortsätter sedan under den angivna föräldern. Svarar med regionlistan.';

  @override
  String get repeater_cliHelpSetFloodMaxUnscoped =>
      'Anger det maximala antalet hopp för vidarebefordran av flood-paket utan regionscope (0-64).';

  @override
  String get repeater_cliHelpSetFloodMaxAdvert =>
      'Anger det maximala antalet hopp för vidarebefordran av flood-adverts (0-64).';

  @override
  String get repeater_cliHelpGetFloodMaxUnscoped =>
      'Visar det maximala antalet hopp för flood-paket utan regionscope.';

  @override
  String get repeater_cliHelpGetFloodMaxAdvert =>
      'Visar det maximala antalet hopp för flood-adverts.';

  @override
  String get repeater_cliHelpSetRadioFemRxGain =>
      'Växlar LoRa-frontändmodulens RX-gain (LNA). Kort utan denna modul svarar \"Error: unsupported\".';

  @override
  String get repeater_cliHelpSetRadioFemTxGain =>
      'Växlar LoRa-frontändmodulens TX-gain (PA). Kort utan denna modul svarar \"Error: unsupported\".';

  @override
  String get repeater_cliHelpGetRadioFemRxGain =>
      'Visar om LoRa-frontändmodulens RX-gain är påslagen.';

  @override
  String get repeater_cliHelpGetRadioFemTxGain =>
      'Visar om LoRa-frontändmodulens TX-gain är påslagen.';

  @override
  String get repeater_bridgeNote =>
      'Endast tillgängligt på firmware byggd med en brygga (RS232 eller ESP-NOW).';

  @override
  String chat_longMessageRetryNote(int count) {
    return 'Över 158 byte: skickas högst $count gånger';
  }

  @override
  String get contacts_notInNodeMemory => 'Inte tillagd i nodens minne';

  @override
  String get contacts_addToNodeTitle => 'Lägga till i nodens minne?';

  @override
  String contacts_addToNodeMessage(String contactName) {
    return 'Bara appen känner till $contactName. Inloggning, förfrågningar, delning och meddelanden kräver att kontakten finns i nodens minne.';
  }

  @override
  String get contacts_addToNodeFailed =>
      'Det gick inte att lägga till i nodens minne';

  @override
  String get contacts_addToNodeFull => 'Nodens minne är fullt';

  @override
  String get channels_shareCopyLink => 'Copy link';
}
