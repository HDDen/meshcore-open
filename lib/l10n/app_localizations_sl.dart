// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Slovenian (`sl`).
class AppLocalizationsSl extends AppLocalizations {
  AppLocalizationsSl([String locale = 'sl']) : super(locale);

  @override
  String get appTitle => 'MeshCore Open (Advanced mod)';

  @override
  String get nav_contacts => 'Stiki';

  @override
  String get nav_channels => 'Kanali';

  @override
  String get nav_map => 'Zemljevid';

  @override
  String get common_cancel => 'Prekliči';

  @override
  String get common_ok => 'V redu';

  @override
  String get common_connect => 'Poveži se';

  @override
  String get common_unknownDevice => 'Neznana naprava';

  @override
  String get common_save => 'Shrani';

  @override
  String get common_delete => 'Izbriši';

  @override
  String get common_deleteAll => 'Izbriši vse';

  @override
  String get common_close => 'Zapri';

  @override
  String get common_done => 'Končano';

  @override
  String get common_edit => 'Uredi';

  @override
  String get common_add => 'Dodaj';

  @override
  String get common_settings => 'Nastavitve';

  @override
  String get common_disconnect => 'Prekini povezavo';

  @override
  String get common_connected => 'Povezano';

  @override
  String get common_disconnected => 'Odklopljeno';

  @override
  String get common_create => 'Ustvari';

  @override
  String get common_continue => 'Nadaljuj';

  @override
  String get common_share => 'Deli';

  @override
  String get common_copy => 'Kopiraj';

  @override
  String get common_retry => 'Poskusi znova';

  @override
  String get common_hide => 'Skrij';

  @override
  String get common_remove => 'Odstrani';

  @override
  String get common_enable => 'Omogoči';

  @override
  String get common_disable => 'Onemogoči';

  @override
  String get common_undo => 'Razveljavi';

  @override
  String get messageStatus_sent => 'Poslano';

  @override
  String get messageStatus_delivered => 'Dostavljeno';

  @override
  String get messageStatus_pending => 'Pošiljanje';

  @override
  String get messageStatus_failed => 'Pošiljanje ni uspelo';

  @override
  String get messageStatus_repeated => 'Slišana ponovitev';

  @override
  String get common_reboot => 'Znova zaženi';

  @override
  String get common_loading => 'Nalaganje...';

  @override
  String get common_notAvailable => '—';

  @override
  String common_voltageValue(String volts) {
    return '$volts V';
  }

  @override
  String common_percentValue(int percent) {
    return '$percent %';
  }

  @override
  String get common_autoRefresh => 'Samodejno osveževanje';

  @override
  String get common_interval => 'Časovni interval';

  @override
  String get common_default => 'Privzeto';

  @override
  String get common_clear => 'Počisti';

  @override
  String get common_send => 'Pošlji';

  @override
  String get common_apply => 'Uporabi';

  @override
  String get scanner_title => 'MeshCore Open (Advanced mod)';

  @override
  String get connectionChoiceUsbLabel => 'USB';

  @override
  String get connectionChoiceBluetoothLabel => 'Bluetooth';

  @override
  String get connectionChoiceTcpLabel => 'TCP';

  @override
  String get tcpScreenTitle => 'Povezava prek TCP';

  @override
  String get tcpHostLabel => 'IP naslov';

  @override
  String get tcpHostHint => '192.168.40.10 / example.com';

  @override
  String get tcpPortLabel => 'Vrata';

  @override
  String get tcpPortHint => '5000';

  @override
  String get tcpStatus_notConnected => 'Vnesite končni naslov in se povežite';

  @override
  String tcpStatus_connectingTo(String endpoint) {
    return 'Povezava z $endpoint...';
  }

  @override
  String get tcpErrorHostRequired => 'Potreben je naslov gostitelja.';

  @override
  String get tcpErrorPortInvalid => 'Port mora biti med 1 in 65535.';

  @override
  String get tcpErrorUnsupported =>
      'Transport preko protokola TCP ni podprt na tej platformi.';

  @override
  String get tcpErrorTimedOut => 'Časovna omejitev povezave TCP je potekla.';

  @override
  String tcpConnectionFailed(String error) {
    return 'Napaka pri povezavi TCP: $error';
  }

  @override
  String get tcpBookmarksLabel => 'Zadnje povezave';

  @override
  String get tcpBookmarksSetName => 'Nastavi ime zaznamka';

  @override
  String get tcpBookmarksFavouritesSubtitle =>
      'Ko je označena kot priljubljena, se ne odstrani iz zgodovine povezav';

  @override
  String get usbScreenTitle => 'Povežite preko USB';

  @override
  String get usbScreenSubtitle =>
      'Izberite zaznano serijsko napravo in se neposredno povežite z vašo MeshCore napravo.';

  @override
  String get usbScreenStatus => 'Izberite napravo USB';

  @override
  String get usbScreenNote =>
      'USB serijska povezava je aktivna na podprtih napravah Android in na namiznih platformah.';

  @override
  String get usbScreenEmptyState =>
      'Ni najdenih naprav USB. Priključite eno in osvežite.';

  @override
  String get usbErrorPermissionDenied =>
      'Dovoljenje za dostop preko USB-ja je bilo zavrnjeno.';

  @override
  String get usbErrorDeviceMissing => 'Izbrana naprava USB ni več na voljo.';

  @override
  String get usbErrorInvalidPort => 'Izberite veljavno napravo USB.';

  @override
  String get usbErrorBusy => 'Že je v teku zahteva za povezavo preko USB.';

  @override
  String get usbErrorNotConnected => 'Ni priklopljene naprave USB.';

  @override
  String get usbErrorOpenFailed =>
      'Izbrane naprave USB ni bilo mogoče odpreti.';

  @override
  String get usbErrorConnectFailed =>
      'Povezave z izbrano napravo USB ni bilo mogoče vzpostaviti.';

  @override
  String get usbErrorUnsupported =>
      'USB serijska komunikacija ni podprta na tej platformi.';

  @override
  String get usbErrorAlreadyActive => 'USB povezava je že aktivirana.';

  @override
  String get usbErrorNoDeviceSelected => 'Izbrana ni bila nobena naprava USB.';

  @override
  String get usbErrorPortClosed => 'USB povezava ni aktivirana.';

  @override
  String get usbErrorConnectTimedOut =>
      'Časovna omejitev povezave je potekla. Prepričajte se, da je na napravi nameščena vdelana programska oprema USB Companion.';

  @override
  String get usbFallbackDeviceName => 'Naprava Web Serial';

  @override
  String get usbStatus_notConnected => 'Izberite napravo USB';

  @override
  String get usbStatus_connecting => 'Povezava z USB napravo...';

  @override
  String get usbStatus_searching => 'Iskanje USB naprav...';

  @override
  String usbConnectionFailed(String error) {
    return 'Napaka pri povezavi preko USB: $error';
  }

  @override
  String get scanner_scanning => 'Iskanje naprav...';

  @override
  String get scanner_connecting => 'Povezujem se...';

  @override
  String get scanner_disconnecting => 'Odklapljam se...';

  @override
  String get scanner_notConnected => 'Ni povezano';

  @override
  String scanner_connectedTo(String deviceName) {
    return 'Povezan s $deviceName';
  }

  @override
  String get scanner_searchingDevices => 'Iskanje naprav MeshCore...';

  @override
  String get scanner_tapToScan =>
      'Tapnite »Skeniraj«, da poiščete naprave MeshCore';

  @override
  String scanner_connectionFailed(String error) {
    return 'Povezava ni uspela: $error';
  }

  @override
  String get scanner_stop => 'Ustavi';

  @override
  String get scanner_scan => 'Skeniraj';

  @override
  String get scanner_bluetoothOff => 'Bluetooth je izklopljen';

  @override
  String get scanner_bluetoothOffMessage =>
      'Prosimo, vklopite Bluetooth, da lahko poiščete naprave.';

  @override
  String get scanner_chromeRequired => 'Zahtevan brskalnik Chrome';

  @override
  String get scanner_chromeRequiredMessage =>
      'Ta spletna aplikacija za podporo Bluetooth zahteva Google Chrome ali brskalnik na osnovi Chromiuma.';

  @override
  String get scanner_enableBluetooth => 'Omogočite Bluetooth';

  @override
  String get scanner_bluetoothWebUnsupported =>
      'Funkcija Bluetooth v brskalniku ni na voljo. Povežite se preko USB-ja namesto tega.';

  @override
  String get device_quickSwitch => 'Hiter preklop';

  @override
  String get device_meshcore => 'MeshCore';

  @override
  String get settings_title => 'Nastavitve';

  @override
  String get settings_deviceInfo => 'Informacije o napravi';

  @override
  String get settings_appSettings => 'Nastavitve aplikacije';

  @override
  String get settings_appSettingsSubtitle =>
      'Obvestila, sporočila in nastavitve zemljevida';

  @override
  String get settings_nodeSettings => 'Nastavitve vozlišča';

  @override
  String get settings_nodeName => 'Ime vozlišča';

  @override
  String get settings_nodeNameNotSet => 'Ni nastavljeno';

  @override
  String get settings_nodeNameHint => 'Vnesite ime vozlišča';

  @override
  String get settings_nodeNameUpdated => 'Ime posodobljeno';

  @override
  String get settings_radioSettings => 'Nastavitve radija';

  @override
  String get settings_radioSettingsSubtitle =>
      'Frekvenca, moč, razširitveni faktor';

  @override
  String get settings_radioSettingsUpdated => 'Radio nastavitve posodobljene';

  @override
  String get settings_regionSettings => 'Regije';

  @override
  String get settings_regionSettingsSubtitle => 'Upravljanje shranjenih regij';

  @override
  String get settings_regionManagement_screenTitle => 'Upravljanje regij';

  @override
  String get settings_regionNameHint => 'Vnesite ime regije';

  @override
  String get settings_regionAddRegion => 'Dodaj regijo';

  @override
  String get settings_regionFetchRegions => 'Pridobi regije od repetitorjev';

  @override
  String get settings_regionFetchRegionsFail => 'Nobena regija ni bila najdena';

  @override
  String get settings_regionFetchRegionsAlreadyExists =>
      'Ta regija je že dodana';

  @override
  String get settings_regionName => 'Ime regije';

  @override
  String get settings_regionDeleted => 'Regija je izbrisana';

  @override
  String get settings_deleteRegion => 'Izbriši regijo';

  @override
  String settings_deleteRegionConfirm(String region) {
    return 'Ali naj se \"$region\" odstrani s seznama regij?';
  }

  @override
  String get settings_location => 'Lokacija';

  @override
  String get settings_locationSubtitle => 'GPS koordinate';

  @override
  String get settings_locationUpdated =>
      'Lokacija in nastavitve GPS posodobljene';

  @override
  String get settings_locationBothRequired => 'Vnesite širino in dolžino.';

  @override
  String get settings_locationInvalid =>
      'Neveljavna zemljepisna širina ali dolžina.';

  @override
  String get settings_locationGPSEnable => 'Omogoči GPS';

  @override
  String get settings_locationGPSEnableSubtitle =>
      'Omogoči samodejno posodabljanje lokacije z GPS-jem.';

  @override
  String get settings_locationIntervalSec => 'Interval za GPS (Sekunde)';

  @override
  String get settings_locationIntervalInvalid =>
      'Interval mora biti vsaj 60 sekund in manj kot 86400 sekund.';

  @override
  String get settings_latitude => 'Širina';

  @override
  String get settings_longitude => 'Dolžina';

  @override
  String get settings_contactSettings => 'Nastavitve stikov';

  @override
  String get settings_contactSettingsSubtitle =>
      'Nastavitve za dodajanje stikov.';

  @override
  String get settings_privacyMode => 'Način zasebnosti';

  @override
  String get settings_privacyModeSubtitle => 'Skrij ime/lokacijo v advertih';

  @override
  String get settings_privacyModeToggle =>
      'Omogoči način zasebnosti, da skriješ svoje ime in lokacijo v advertih.';

  @override
  String get settings_privacyModeEnabled => 'Privatni način je omogočen.';

  @override
  String get settings_privacyModeDisabled => 'Privatni način je onemogočen.';

  @override
  String get settings_privacy => 'Nastavitve zasebnosti';

  @override
  String get settings_privacySubtitle =>
      'Kontrolirajte, katere informacije so deljene.';

  @override
  String get settings_privacySettingsDescription =>
      'Izberite, katere informacije vaša naprava deli z drugimi.';

  @override
  String get settings_denyAll => 'Zavrni vse';

  @override
  String get settings_allowByContact => 'Dovoli glede na zastavice stikov';

  @override
  String get settings_allowAll => 'Dovoli vse';

  @override
  String get settings_telemetryBaseMode => 'Osnovni način telemetrije';

  @override
  String get settings_telemetryLocationMode => 'Način telemetrije lokacije';

  @override
  String get settings_telemetryEnvironmentMode => 'Način telemetrije okolja';

  @override
  String get settings_advertLocation => 'Lokacija v advertu';

  @override
  String get settings_advertLocationSubtitle => 'Vključi lokacijo v advert.';

  @override
  String get settings_autoZeroHopAdvertOnGpsUpdate =>
      'Samodejni zero-hop advert ob posodobitvi GPS';

  @override
  String get settings_autoZeroHopAdvertOnGpsUpdateSubtitle =>
      'Ko se GPS lokacija spremeni, pošlji zero-hop advert (zahteva lokacijo v advertu).';

  @override
  String get settings_multiAck => 'Več potrdil';

  @override
  String get settings_telemetryModeUpdated => 'Način telemetrije posodobljen';

  @override
  String get settings_actions => 'Akcije';

  @override
  String get settings_deleteAllPaths => 'Izbriši vse poti';

  @override
  String get settings_deleteAllPathsSubtitle =>
      'Počisti vse lokalne podatke o poteh v stikih. Poti na vozlišču ne bodo spremenjene.';

  @override
  String get settings_sendAdvertisement => 'Pošlji advert';

  @override
  String get settings_sendAdvertisementSubtitle =>
      'Takoj oddaj svojo prisotnost';

  @override
  String get settings_advertisementSent => 'Advert poslan';

  @override
  String get settings_syncTime => 'Nastavi uro';

  @override
  String get settings_syncTimeSubtitle => 'Nastavi uro naprave na čas telefona';

  @override
  String get settings_timeSynchronized => 'Ura sinhronizirana';

  @override
  String get settings_refreshContacts => 'Osveži stike';

  @override
  String get settings_refreshContactsSubtitle =>
      'Ponovno naloži seznam stikov iz naprave';

  @override
  String get settings_rebootDevice => 'Ponovni zagon naprave';

  @override
  String get settings_rebootDeviceSubtitle => 'Ponovno zaženi MeshCore napravo';

  @override
  String get settings_rebootDeviceConfirm =>
      'Ste prepričani, da želite ponovno zagnati napravo? Povezava bo prekinjena.';

  @override
  String get settings_debug => 'Odpravljanje napak';

  @override
  String get settings_companionDebugLog =>
      'Dnevnik odpravljanja napak spremljevalca';

  @override
  String get settings_companionDebugLogSubtitle =>
      'Ukazi, odgovori in surovi podatki BLE/TCP/USB';

  @override
  String get settings_appDebugLog => 'Dnevnik odpravljanja napak aplikacije';

  @override
  String get settings_appDebugLogSubtitle =>
      'Sporočila za odpravljanje napak aplikacije';

  @override
  String get settings_about => 'O aplikaciji';

  @override
  String settings_aboutVersion(String version) {
    return 'MeshCore Open (Advanced mod), različica $version';
  }

  @override
  String get settings_aboutLegalese => 'Odprtokodni projekt MeshCore 2026';

  @override
  String get settings_aboutDescription =>
      'Odprtokodni Flutter klient za naprave za LoRa omrežje MeshCore.';

  @override
  String get settings_aboutModDescription =>
      'Modifikacija «Advanced» temelji na izvirnem meshcore_open in vsebuje spremembe, predlagane v repozitoriju izvirne aplikacije ali specifične za območje uporabe, zato niso bile oddane kot pull request.';

  @override
  String get settings_aboutModLink =>
      'Izdaje na Githubu: \nhttps://github.com/HDDen/meshcore-open/releases \nSkupina modifikacije na Telegramu: \nhttps://t.me/mcoadvanced \nSpletna stran modifikacije: \nhttps://mcoadvanced.ru';

  @override
  String get settings_aboutOpenMeteoAttribution =>
      'Podatki o višini LOS: Open-Meteo (CC BY 4.0)';

  @override
  String get settings_infoName => 'Ime';

  @override
  String get settings_infoId => 'ID';

  @override
  String get settings_infoDeviceName => 'Ime plošče';

  @override
  String get settings_infoStatus => 'Stanje';

  @override
  String get settings_infoBattery => 'Baterija';

  @override
  String get settings_infoPublicKey => 'Javni ključ';

  @override
  String get settings_infoContactsCount => 'Število stikov';

  @override
  String get settings_infoChannelCount => 'Število kanalov';

  @override
  String get settings_infoFirmware => 'Različica vdelane programske opreme';

  @override
  String get settings_presets => 'Prednastavitve';

  @override
  String get settings_frequency => 'Frekvenca (MHz)';

  @override
  String get settings_frequencyHelper => '300.0 - 2500.0';

  @override
  String get settings_frequencyInvalid => 'Neveljavna frekvenca (150-2500 MHz)';

  @override
  String get settings_bandwidth => 'Pasovna širina';

  @override
  String get settings_spreadingFactor => 'Razširitveni faktor';

  @override
  String get settings_codingRate => 'Kodno razmerje';

  @override
  String get settings_txPower => 'TX Moč (dBm)';

  @override
  String get settings_txPowerHelper => '0 – 22';

  @override
  String get settings_txPowerInvalid => 'Neveljavna TX moč (0-22 dBm)';

  @override
  String get settings_clientRepeat => 'Ponavljanje izven omrežja';

  @override
  String get settings_clientRepeatSubtitle =>
      'Omogočite tej napravi, da za druge ponavlja pakete omrežja mesh.';

  @override
  String get settings_clientRepeatFreqWarning =>
      'Ponavljanje izven omrežja zahteva frekvenco 433, 869.495 ali 918 MHz';

  @override
  String settings_error(String message) {
    return 'Napaka: $message';
  }

  @override
  String get settings_channelResendTimeoutTitle =>
      'Zakasnitev ročnega ponovnega pošiljanja';

  @override
  String get settings_channelResendTimeoutSubtitle =>
      'Vpliva tudi na notranji mehanizem za odpravljanje podvojenega prikaza odhodnih sporočil';

  @override
  String get settings_channelMaxbytesOutgoingTitle =>
      'Omeji odhodni payload kanalov, bajti';

  @override
  String get settings_channelMaxbytesOutgoingSubtitle =>
      'Omejitev upošteva besedilo sporočila in ime pošiljatelja. Opaženo je bilo, da se po preseženi določeni velikosti sporočila v bajtih potrditve ponavljanja paketov prenehajo prenašati. To je posebej opazno pri povezavah BLE. Približni prag, pri katerem potrditve še delujejo, je 139 bajtov. Za TCP/USB je ta omejitev približno 150 bajtov.';

  @override
  String get settings_quickAnswersTitle => 'Hitri odgovori';

  @override
  String get settings_quickAnswersSubtitle =>
      'Seznam fraz, ki jih je mogoče izbrati kot hitre odgovore. Dodelijo se stikom/kanalom v njihovih nastavitvah.';

  @override
  String get settings_quickAnswersAddText => 'Vnesite besedilo';

  @override
  String get settings_quickAnswersEditText => 'Uredi odgovor';

  @override
  String get settings_quickAnswersSelect => 'Omogoči te odgovore';

  @override
  String get settings_quickAnswersExists => 'Že obstaja';

  @override
  String get settings_quickAnswersNotAdded =>
      'Za ta klepet še niste dodali hitrih odgovorov!';

  @override
  String get settings_quickAnswersSendAtSelect => 'Pošlji ob izbiri';

  @override
  String get appSettings_title => 'Nastavitve aplikacije';

  @override
  String get appSettings_appearance => 'Videz';

  @override
  String get appSettings_theme => 'Tema';

  @override
  String get appSettings_themeSystem => 'Sistemska tema';

  @override
  String get appSettings_themeLight => 'Svetla';

  @override
  String get appSettings_themeDark => 'Temna';

  @override
  String get appSettings_language => 'Jezik';

  @override
  String get appSettings_languageSystem => 'Sistemska privzeta vrednost';

  @override
  String get appSettings_languageEn => 'Angleščina';

  @override
  String get appSettings_languageFr => 'Francoščina';

  @override
  String get appSettings_languageEs => 'Španščina';

  @override
  String get appSettings_languageDe => 'Nemščina';

  @override
  String get appSettings_languagePl => 'Poljščina';

  @override
  String get appSettings_languageSl => 'Slovenščina';

  @override
  String get appSettings_languagePt => 'Portugalščina';

  @override
  String get appSettings_languageIt => 'Italijanščina';

  @override
  String get appSettings_languageZh => '中文';

  @override
  String get appSettings_languageSv => 'Švedščina';

  @override
  String get appSettings_languageNl => 'Nizozemščina';

  @override
  String get appSettings_languageSk => 'Slovaščina';

  @override
  String get appSettings_languageBg => 'Български';

  @override
  String get appSettings_languageRu => 'Ruščina';

  @override
  String get appSettings_languageUk => 'Ukrajinščina';

  @override
  String get repeater_pathHashModeOption0 => '1 bajt';

  @override
  String get repeater_pathHashModeOption1 => '2 bajta';

  @override
  String get repeater_pathHashModeOption2 => '3 bajti';

  @override
  String get repeater_pathHashModeOption3 => '4 bajti';

  @override
  String get appSettings_enableMessageTracing => 'Omogoči sledenje sporočilom';

  @override
  String get appSettings_enableMessageTracingSubtitle =>
      'Prikaži podrobne metapodatke o usmerjanju in časovnem usklajevanju sporočil';

  @override
  String get appSettings_enableTimeSeconds =>
      'Prikaži sekunde v informacijah o sporočilu';

  @override
  String get appSettings_showKeyboardHidingButton =>
      'Prikaži gumb za skrivanje tipkovnice';

  @override
  String get appSettings_notifications => 'Obvestila';

  @override
  String get appSettings_enableNotifications => 'Omogoči obvestila';

  @override
  String get appSettings_enableNotificationsSubtitle =>
      'Prejmite obvestila o sporočilih in advertih';

  @override
  String get appSettings_notificationPermissionDenied =>
      'Dovoljenje za obvestila zavrnjeno';

  @override
  String get appSettings_notificationsEnabled => 'Obvestila omogočena';

  @override
  String get appSettings_notificationsDisabled => 'Obvestila so izklopljena';

  @override
  String get appSettings_messageNotifications => 'Obvestila o sporočilih';

  @override
  String get appSettings_messageNotificationsSubtitle =>
      'Pokaži obvestilo ob prejemu novih sporočil.';

  @override
  String get appSettings_channelMessageNotifications =>
      'Obvestila o sporočilih kanala';

  @override
  String get appSettings_channelMessageNotificationsSubtitle =>
      'Pokaži obvestilo ob prejemanju sporočil kanala';

  @override
  String get appSettings_advertisementNotifications => 'Obvestila o advertih';

  @override
  String get appSettings_advertisementNotificationsSubtitle =>
      'Pokaži obvestilo, ko so najdene nove naprave.';

  @override
  String get appSettings_messaging => 'Komuniciranje';

  @override
  String get appSettings_clearPathOnMaxRetry =>
      'Počisti pot ob največjem številu poskusov';

  @override
  String get appSettings_clearPathOnMaxRetrySubtitle =>
      'Ponastavi pot stika po 5 neuspešnih poskusih pošiljanja';

  @override
  String get appSettings_pathsWillBeCleared =>
      'Poti bodo počiščene po 5 neuspešnih poskusih.';

  @override
  String get appSettings_pathsWillNotBeCleared =>
      'Poti ne bodo samodejno čiščene.';

  @override
  String get appSettings_autoRouteRotation => 'Samodejna rotacija poti';

  @override
  String get appSettings_autoRouteRotationSubtitle =>
      'Menjaj med najboljšimi potmi in flood načinom';

  @override
  String get appSettings_autoRouteRotationEnabled =>
      'Samodejna rotacija poti omogočena';

  @override
  String get appSettings_autoRouteRotationDisabled =>
      'Samodejna rotacija poti je onemogočena';

  @override
  String get appSettings_maxRouteWeight => 'Največja dovoljena teža poti';

  @override
  String get appSettings_maxRouteWeightSubtitle =>
      'Največja teža, ki jo lahko pot nabere z uspešnimi dostavami.';

  @override
  String get appSettings_initialRouteWeight => 'Začetna teža poti';

  @override
  String get appSettings_initialRouteWeightSubtitle =>
      'Začetna teža za na novo odkrite poti';

  @override
  String get appSettings_routeWeightSuccessIncrement =>
      'Povečanje teže ob uspehu';

  @override
  String get appSettings_routeWeightSuccessIncrementSubtitle =>
      'Teža, dodana poti po uspešni dostavi';

  @override
  String get appSettings_routeWeightFailureDecrement =>
      'Zmanjšanje teže ob neuspehu';

  @override
  String get appSettings_routeWeightFailureDecrementSubtitle =>
      'Teža, odvzeta poti po neuspešni dostavi';

  @override
  String get appSettings_maxMessageRetries =>
      'Največje število ponovnih poskusov sporočila';

  @override
  String get appSettings_maxMessageRetriesSubtitle =>
      'Število ponovnih poskusov pošiljanja, preden se sporočilo označi kot neuspešno';

  @override
  String get appSettings_battery => 'Baterija';

  @override
  String get appSettings_batteryChemistry => 'Kemija baterije';

  @override
  String appSettings_batteryChemistryPerDevice(String deviceName) {
    return 'Nastavitev za napravo ($deviceName)';
  }

  @override
  String get appSettings_batteryChemistryConnectFirst =>
      'Za izbiro se poveži z napravo';

  @override
  String get appSettings_batteryNmc => '18650 NMC (3,0-4,2V)';

  @override
  String get appSettings_batteryLifepo4 => 'LiFePO4 (2,6–3,65 V)';

  @override
  String get appSettings_batteryLipo => 'LiPo (3,0-4,2V)';

  @override
  String get appSettings_mapDisplay => 'Prikaz zemljevida';

  @override
  String get appSettings_showRepeaters => 'Prikaži repetitorje';

  @override
  String get appSettings_showRepeatersSubtitle =>
      'Prikaži repetitorje na zemljevidu';

  @override
  String get appSettings_showChatNodes => 'Prikaži naprave za klepet';

  @override
  String get appSettings_showChatNodesSubtitle =>
      'Prikaži naprave za klepet na zemljevidu';

  @override
  String get appSettings_showOtherNodes => 'Pokaži druge naprave';

  @override
  String get appSettings_showOtherNodesSubtitle =>
      'Pokaži druge vrste naprav na zemljevidu.';

  @override
  String get appSettings_timeFilter => 'Filter po času';

  @override
  String get appSettings_timeFilterShowAll => 'Pokaži vse naprave';

  @override
  String appSettings_timeFilterShowLast(int hours) {
    return 'Pokaži naprave v zadnjih $hours urah';
  }

  @override
  String get appSettings_mapTimeFilter => 'Filter časa na zemljevidu';

  @override
  String get appSettings_showNodesDiscoveredWithin =>
      'Pokaži naprave odkrite v:';

  @override
  String get appSettings_allTime => 'Brez omejitev';

  @override
  String get appSettings_lastHour => 'V zadnji uri';

  @override
  String get appSettings_last6Hours => 'Zadnjih 6 ur';

  @override
  String get appSettings_last24Hours => 'Zadnjih 24 ur';

  @override
  String get appSettings_lastWeek => 'Zadnji teden';

  @override
  String get appSettings_rasterTileSource => 'Vir rastrskih ploščic';

  @override
  String get appSettings_stadiaEndpoint => 'Končna točka Stadia';

  @override
  String get appSettings_stadiaApiKey => 'Ključ API Stadia';

  @override
  String get appSettings_stadiaApiKeyRequired =>
      'Obvezno za uporabo Stadia Maps';

  @override
  String appSettings_stadiaApiKeyConfigured(String maskedKey) {
    return 'Nastavljeno: $maskedKey';
  }

  @override
  String get appSettings_stadiaApiKeyDialogDescription =>
      'Vnesite svoj ključ API za Stadia Maps. Aplikacija ga uporablja za zahteve rastrskih ploščic.';

  @override
  String get appSettings_offlineMapCache => 'Shramba zemljevidov brez povezave';

  @override
  String get appSettings_unitsTitle => 'Enote';

  @override
  String get appSettings_unitsMetric => 'Metrična (m/km)';

  @override
  String get appSettings_unitsImperial => 'Imperialna (ft / mi)';

  @override
  String get appSettings_noAreaSelected => 'Območje ni izbrano';

  @override
  String appSettings_areaSelectedZoom(int minZoom, int maxZoom) {
    return 'Izbrano območje (povečava $minZoom-$maxZoom)';
  }

  @override
  String get appSettings_debugCard => 'Razhroščevanje';

  @override
  String get appSettings_appDebugLogging => 'Programski dnevnik';

  @override
  String get appSettings_appDebugLoggingSubtitle =>
      'Beleži razhroščevalna sporočila aplikacije za odpravljanje težav';

  @override
  String get appSettings_appDebugLoggingEnabled =>
      'Beleženje napak v aplikaciji omogočeno';

  @override
  String get appSettings_appDebugLoggingDisabled =>
      'Beleženje napak v aplikaciji onemogočeno.';

  @override
  String get contacts_title => 'Stiki';

  @override
  String get contacts_noContacts => 'Ni stikov.';

  @override
  String get contacts_contactsWillAppear =>
      'Stiki se bodo prikazali, ko bodo naprave poslale advert.';

  @override
  String get contacts_unread => 'Neprebrano';

  @override
  String get contacts_searchContactsNoNumber => 'Iskanje stikov...';

  @override
  String contacts_searchContacts(int number, String str) {
    return 'Išči $number$str stikov...';
  }

  @override
  String contacts_searchFavorites(int number, String str) {
    return 'Iskanje $number$str priljubljenih...';
  }

  @override
  String contacts_searchUsers(int number, String str) {
    return 'Išči $number$str uporabnikov...';
  }

  @override
  String contacts_searchRepeaters(int number, String str) {
    return 'Išči $number$str ponavljalnikov...';
  }

  @override
  String contacts_searchRoomServers(int number, String str) {
    return 'Išči $number$str strežnikov sob...';
  }

  @override
  String get contacts_noUnreadContacts => 'Ni neprebranih stikov.';

  @override
  String get contacts_noContactsFound => 'Ni najdenih stikov ali skupin.';

  @override
  String get contacts_deleteContact => 'Izbriši stik';

  @override
  String contacts_removeConfirm(String contactName) {
    return 'Izbrišem $contactName iz stikov?';
  }

  @override
  String get contacts_manageRepeater => 'Upravljaj ponovitelja';

  @override
  String get contacts_requestRegions => 'Zahtevaj regije';

  @override
  String get contacts_manageRoom => 'Upravljajte strežnik sobe';

  @override
  String get contacts_roomLogin => 'Prijava v sobo';

  @override
  String get contacts_openChat => 'Odpri klepet';

  @override
  String get contacts_editGroup => 'Uredi skupino';

  @override
  String get contacts_deleteGroup => 'Izbriši skupino';

  @override
  String contacts_deleteGroupConfirm(String groupName) {
    return 'Izbriši $groupName?';
  }

  @override
  String get contacts_newGroup => 'Nova skupina';

  @override
  String get contacts_newGroupDescription => 'Združi kanale/stike v mapo';

  @override
  String get contacts_moreOptions => 'Več možnosti';

  @override
  String get contacts_searchOpen => 'Iskanje kontaktov';

  @override
  String get contacts_searchClose => 'Izklopi iskanje';

  @override
  String get contacts_groupName => 'Ime skupine';

  @override
  String get contacts_groupNameRequired => 'Ime skupine je obvezno.';

  @override
  String get contacts_groupNameReserved => 'To ime skupine je rezervirano';

  @override
  String contacts_groupAlreadyExists(String name) {
    return 'Skupina \"$name\" že obstaja';
  }

  @override
  String get contacts_filterContacts => 'Filtriraj stike...';

  @override
  String get contacts_noContactsMatchFilter =>
      'Noben stik ne ustreza vašemu kriteriju.';

  @override
  String get contacts_noMembers => 'Ni članov.';

  @override
  String get contacts_lastSeenNow => 'Nazadnje viden zdaj';

  @override
  String contacts_lastSeenMinsAgo(int minutes) {
    return 'Zadnjič viden pred $minutes minutami';
  }

  @override
  String get contacts_lastSeenHourAgo => 'Zadnjič viden pred 1 uro.';

  @override
  String contacts_lastSeenHoursAgo(int hours) {
    return 'Zadnjič viden pred $hours urami';
  }

  @override
  String get contacts_lastSeenDayAgo => 'Zadnjič viden pred 1 dnem';

  @override
  String contacts_lastSeenDaysAgo(int days) {
    return 'Zadnjič viden pred $days dnevi';
  }

  @override
  String get contact_info => 'Kontaktni podatki';

  @override
  String get contact_settings => 'Nastavitve stika';

  @override
  String get contact_telemetry => 'Telemetrija';

  @override
  String get contact_lastSeen => 'Zadnjič videno';

  @override
  String get contact_clearChat => 'Počisti klepet';

  @override
  String get contact_clearChatConfirm =>
      'Ali naj se sporočila izbrišejo iz klepeta?';

  @override
  String get contact_teleBase => 'Baza telemetrije';

  @override
  String get contact_teleBaseSubtitle =>
      'Dovoli deljenje stanja baterije in osnovne telemetrije';

  @override
  String get contact_teleLoc => 'Lokacija telemetrije';

  @override
  String get contact_teleLocSubtitle => 'Dovoli deljenje podatkov o lokaciji';

  @override
  String get contact_teleEnv => 'Okolje telemetrije';

  @override
  String get contact_teleEnvSubtitle =>
      'Dovoli deljenje podatkov okoljskih senzorjev';

  @override
  String get channels_title => 'Kanali';

  @override
  String get channels_noChannelsConfigured => 'Kanali še niso konfigurirani';

  @override
  String get channels_addPublicChannel => 'Dodaj javni kanal';

  @override
  String get channels_searchChannels => 'Poišči kanale...';

  @override
  String get channels_noChannelsFound => 'Ne najdem kanalov.';

  @override
  String channels_channelIndex(int index) {
    return 'Kanal $index';
  }

  @override
  String get channels_public => 'Javni';

  @override
  String channels_via(String path) {
    return 'via $path';
  }

  @override
  String get channels_private => 'Zasebni';

  @override
  String get channels_editChannel => 'Uredi kanal';

  @override
  String get channels_muteChannel => 'Utišaj, razen omemb';

  @override
  String get channels_unmuteChannel => 'Vklopi obvestila kanala';

  @override
  String get channels_deleteChannel => 'Izbriši kanal';

  @override
  String channels_deleteChannelConfirm(String name) {
    return 'Izbrišem \"$name\"? To se ne da povrniti.';
  }

  @override
  String channels_channelDeleteFailed(String name) {
    return 'Kanala $name ni bilo mogoče izbrisati';
  }

  @override
  String channels_channelDeleted(String name) {
    return 'Kanal \"$name\" izbrisan.';
  }

  @override
  String get channels_addChannel => 'Dodaj Kanal';

  @override
  String get channels_channelIndexLabel => 'Indeks kanala';

  @override
  String get channels_channelName => 'Ime kanala';

  @override
  String get channels_usePublicChannel => 'Uporabi javni kanal';

  @override
  String get channels_standardPublicPsk => 'Standardni javni PSK';

  @override
  String get channels_pskHex => 'PSK (šestnajstiško)';

  @override
  String get channels_generateRandomPsk => 'Generiraj naključni PSK';

  @override
  String get channels_enterChannelName => 'Vnesi ime kanala';

  @override
  String get channels_pskMustBe32Hex =>
      'PSK mora biti 32 heksadecimalnih znakov.';

  @override
  String channels_channelAdded(String name) {
    return 'Kanal \"$name\" dodan';
  }

  @override
  String channels_editChannelTitle(int index) {
    return 'Uredi Kanal $index';
  }

  @override
  String get channels_smazCompression => 'Kompresija SMAZ';

  @override
  String get channels_cyr2latCompression => 'Kompresija Cyr2Lat';

  @override
  String get channels_cyr2latCompressionDscr =>
      'Pri pošiljanju nekatere cirilične znake nadomesti z latiničnimi.';

  @override
  String get channels_mcotxtCompression => 'Kompresija MCOtxt';

  @override
  String get channels_cyr2latSettingsHeading => 'Nastavitve Cyr2Lat';

  @override
  String get channels_cyr2latSettingsSubheading => 'Seznam zamenjav';

  @override
  String get channels_cyr2latSettingsDscr =>
      'Uredi JSON-konfiguracijo zamenjav znakov';

  @override
  String get channels_cyr2latSettingsDialogHint => 'JSON-tabela zamenjav';

  @override
  String channels_cyr2latSettingsDialogWrongJSON(Object error) {
    return 'Nepravilen JSON: $error';
  }

  @override
  String channels_channelUpdated(String name) {
    return 'Kanal $name je bil posodobljen';
  }

  @override
  String get channels_changeWidgetColor => 'Barva gradnika';

  @override
  String get channels_changeWidgetTextColor => 'Barva besedila gradnika';

  @override
  String get channels_changeGroupEmpty => 'Tukaj je za zdaj prazno';

  @override
  String get channels_allowOrderingInGroup =>
      'Dovoli razvrščanje kanalov v skupini';

  @override
  String get settings_cyr2latProfileAdd => 'Dodaj profil Cyr2Lat';

  @override
  String get settings_cyr2latProfileName => 'Ime profila';

  @override
  String get settings_cyr2latProfileNameEmpty =>
      'Ime profila ne sme biti prazno';

  @override
  String get settings_cyr2latProfileAdded => 'Profil je bil uspešno dodan';

  @override
  String get settings_cyr2latProfileUpdated =>
      'Profil je bil uspešno posodobljen';

  @override
  String get settings_cyr2latProfileEdit => 'Uredi profil Cyr2Lat';

  @override
  String get settings_cyr2latProfileDelete => 'Izbriši profil Cyr2Lat';

  @override
  String get settings_cyr2latProfileDeleted => 'Profil je bil uspešno izbrisan';

  @override
  String settings_cyr2latProfileDeleteDscr(String name) {
    return 'Ali res želite izbrisati profil \"$name\"?';
  }

  @override
  String get settings_mcmpTextLimit => 'Omejitev lepljenja besedila MCMP';

  @override
  String get settings_sendingDelayForCancellation =>
      'Zakasnitev pošiljanja za preklic';

  @override
  String get settings_useSendingDelay => 'Uporabi zakasnitev pošiljanja';

  @override
  String get chat_cancelSend => 'prekliči pošiljanje';

  @override
  String get settings_doNotFilterMessagesOnChannels =>
      'Sporočila v teh kanalih obravnavaj kot zagotovo dostavljena';

  @override
  String get settings_doNotFilterMessagesOnChannelsSubtitle =>
      'Sporočila v navedene kanale se pošljejo brez čakanja na potrditev vozlišča in brez ponovitev.';

  @override
  String get channels_publicChannelAdded => 'Javni kanal dodan';

  @override
  String get channels_sortBy => 'Sortiraj po';

  @override
  String get channels_sortManual => 'Ročno';

  @override
  String get channels_sortAZ => 'A do Z';

  @override
  String get channels_sortLatestMessages => 'Najnovejše sporočilo';

  @override
  String get channels_sortUnread => 'Neprebrano';

  @override
  String get channels_createPrivateChannel => 'Ustvari zasebni kanal';

  @override
  String get channels_createPrivateChannelDesc =>
      'Varno zaklenjeno s skrivnim ključem.';

  @override
  String get channels_joinPrivateChannel => 'Pridružite se zasebnemu kanalu';

  @override
  String get channels_joinPrivateChannelDesc => 'Ročno vnesite skrivni ključ.';

  @override
  String get channels_joinPublicChannel => 'Pridružite se javnemu kanalu';

  @override
  String get channels_joinPublicChannelDesc =>
      'Temu kanalu se lahko pridruži kdorkoli.';

  @override
  String get channels_joinHashtagChannel => 'Pridružite se Kanalu z Hashtagom';

  @override
  String get channels_joinHashtagChannelDesc =>
      'Hashtag kanalom se lahko pridruži kdorkoli.';

  @override
  String get channels_scanQrCode => 'Skeniraj QR kodo';

  @override
  String get channels_scanQrCodeComingSoon => 'Kmalu na voljo';

  @override
  String get channels_enterHashtag => 'Vnesite hashtag';

  @override
  String get channels_hashtagHint => 'npr. #ekipa';

  @override
  String get channels_hashtagMcoaHint =>
      'Velike črke in »_« so podprte samo v MCOa';

  @override
  String channels_regionSetTo(String region) {
    return 'Regija: $region';
  }

  @override
  String get channels_regionNotSet => 'Regija: brez';

  @override
  String get channels_regionSelect_Title => 'Dodeli regijo';

  @override
  String get channels_clearRegion => 'Počisti regijo';

  @override
  String get chat_noMessages => 'Še ni sporočil.';

  @override
  String get chat_sendMessage => 'Pošlji sporočilo';

  @override
  String chat_sendMessageTo(String contactName) {
    return 'Pošlji sporočilo $contactName';
  }

  @override
  String get chat_sendMessageToStart => 'Pošlji sporočilo za začetek.';

  @override
  String get chat_originalMessageNotFound =>
      'Izvirno sporočilo ni bilo najdeno';

  @override
  String chat_replyingTo(String name) {
    return 'Odgovor za $name';
  }

  @override
  String chat_replyTo(String name) {
    return 'Odgovori $name';
  }

  @override
  String get chat_location => 'Lokacija';

  @override
  String get chat_typeMessage => 'Vnesi sporočilo...';

  @override
  String chat_messageTooLong(int maxBytes) {
    return 'Sporočilo je predolgo (največ $maxBytes bajtov).';
  }

  @override
  String get chat_messageCopied => 'Sporočilo kopirano';

  @override
  String get chat_messageDeleted => 'Sporočilo izbrisano';

  @override
  String get chat_retryingMessage => 'Ponovni poskus.';

  @override
  String chat_retryingMessageWait(Object seconds) {
    return 'Pred ponovnim pošiljanjem počakajte $seconds sekund';
  }

  @override
  String chat_retryCount(int current, int max) {
    return 'Poskus $current/$max';
  }

  @override
  String get chat_sendGif => 'Pošlji GIF';

  @override
  String get chat_receivedGif => 'Prejet GIF';

  @override
  String get chat_reply => 'Odgovori';

  @override
  String get chat_addReaction => 'Dodaj reakcijo';

  @override
  String get chat_me => 'jaz';

  @override
  String get emojiCategorySmileys => 'Smeški';

  @override
  String get emojiCategoryGestures => 'Gestikulacije';

  @override
  String get emojiCategoryHearts => 'Srca';

  @override
  String get emojiCategoryObjects => 'Predmeti';

  @override
  String get gifPicker_title => 'Izberi GIF';

  @override
  String get gifPicker_searchHint => 'Išči GIF-e...';

  @override
  String get gifPicker_poweredBy => 'Poganja GIPHY';

  @override
  String get gifPicker_noGifsFound => 'Ne najdem GIF-ov.';

  @override
  String get gifPicker_failedLoad => 'Neuspešno nalaganje GIF-a';

  @override
  String get gifPicker_failedSearch => 'Iskanje neuspešno.';

  @override
  String get gifPicker_noInternet => 'Ni internetne povezave';

  @override
  String get debugLog_appTitle => 'Dnevnik odpravljanja napak aplikacije';

  @override
  String get debugLog_bleTitle => 'Dnevnik odpravljanja napak BLE';

  @override
  String get debugLog_copyLog => 'Kopiraj dnevnik';

  @override
  String get debugLog_clearLog => 'Počisti dnevnik';

  @override
  String get debugLog_copied => 'Dnevnik odpravljanja napak kopiran.';

  @override
  String get debugLog_bleCopied => 'Dnevnik BLE kopiran';

  @override
  String get debugLog_noEntries => 'Še ni zapisov za odpravljanje napak.';

  @override
  String get debugLog_enableInSettings =>
      'Omogoči beleženje napak v nastavitvah aplikacije';

  @override
  String get debugLog_frames => 'Okvirji';

  @override
  String get debugLog_rawLogRx => 'Surovi Log-RX';

  @override
  String get debugLog_noBleActivity => 'Ni BLE aktivnosti.';

  @override
  String debugFrame_length(int count) {
    return 'Dolžina okvirja: $count bajtov';
  }

  @override
  String debugFrame_command(String value) {
    return 'Ukaz: 0x$value';
  }

  @override
  String get debugFrame_textMessageHeader => 'Okvir besedilnega sporočila:';

  @override
  String debugFrame_destinationPubKey(String pubKey) {
    return '- Javni ključ prejemnika: $pubKey';
  }

  @override
  String debugFrame_timestamp(int timestamp) {
    return '- Časovni žig: $timestamp';
  }

  @override
  String debugFrame_flags(String value) {
    return '- Zastavice: 0x$value';
  }

  @override
  String debugFrame_textType(int type, String label) {
    return '- Tip besedila: $type ($label)';
  }

  @override
  String get debugFrame_textTypeCli => 'CLI';

  @override
  String get debugFrame_textTypePlain => 'Navadno';

  @override
  String debugFrame_text(String text) {
    return '- Tekst: \"$text\"';
  }

  @override
  String get debugFrame_hexDump => 'Izpis heksadecimalnih vrednosti:';

  @override
  String chat_hopsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'skokov',
      few: 'skoki',
      two: 'skoka',
      one: 'skok',
    );
    return '$count $_temp0';
  }

  @override
  String get chat_removePath => 'Izbriši pot';

  @override
  String get chat_noPathHistoryYet =>
      'Ni shranjenih poti.\nPošlji sporočilo za odkrivanje poti.';

  @override
  String get chat_pathCleared =>
      'Pot je izbrisana. Naslednje sporočilo bo ponovno odkrilo pot.';

  @override
  String get chat_fullPath => 'Polna pot';

  @override
  String get routing_title => 'Usmerjanje';

  @override
  String get routing_modeAuto => 'Avto';

  @override
  String get routing_modeFlood => 'Flood';

  @override
  String get routing_modeManual => 'Ročno';

  @override
  String get routing_modeAutoHint =>
      'Samodejno izbere najboljšo znano pot; ko nobena ni znana, uporabi način flood.';

  @override
  String get routing_modeFloodHint =>
      'Oddaja prek vseh repetitorjev. Najzanesljivejši način, vendar porabi več časa oddajanja.';

  @override
  String get routing_modeManualHint =>
      'Vedno pošilja natančno po poti, ki ste jo določili.';

  @override
  String get routing_currentRoute => 'Trenutna pot';

  @override
  String get routing_directNoHops =>
      'Neposredno – brez skokov prek ponoviteljev';

  @override
  String get routing_noPathYet =>
      'Poti še ni. Naslednje sporočilo bo poslano v načinu flood, dokler ne bo odkrita pot.';

  @override
  String get routing_floodBroadcast => 'Oddaja prek vseh repetitorjev';

  @override
  String get routing_editPath => 'Uredi pot';

  @override
  String get routing_forgetPath => 'Pozabi na pot';

  @override
  String get routing_knownPaths => 'Znane poti';

  @override
  String get routing_knownPathsHint => 'Kliknite na pot, da jo izberete.';

  @override
  String get routing_inUse => 'V uporabi';

  @override
  String get routing_qualityStrong => 'Močan prvi skok';

  @override
  String get routing_qualityGood => 'Dober prvi skok';

  @override
  String get routing_qualityFair => 'Srednji prvi skok';

  @override
  String get routing_qualityWorked => 'Že dostavila';

  @override
  String get routing_qualityFlood => 'Slišano v načinu flood';

  @override
  String get routing_qualityUntested => 'Nepreizkušena';

  @override
  String routing_lastWorked(String when) {
    return 'delovala $when';
  }

  @override
  String get routing_neverWorked => 'nikoli ni bilo potrjeno';

  @override
  String routing_deliveryCounts(int successes, int failures) {
    return '$successes dostavljenih, $failures neuspešnih';
  }

  @override
  String get routing_floodDelivery => 'Flood dostava';

  @override
  String get pathEditor_title => 'Izgradnja poti';

  @override
  String pathEditor_hopCounter(int count) {
    return '$count od 64 skokov';
  }

  @override
  String get pathEditor_noHops =>
      'Skokov še ni. Tapnite ponovitelje spodaj, da jih dodate po vrsti, ali shranite brez skokov za neposredno pošiljanje.';

  @override
  String get pathEditor_addHops => 'Dodajte skoke po vrsti';

  @override
  String get pathEditor_searchRepeaters => 'Iskanje ponoviteljev';

  @override
  String get pathEditor_advancedHex => 'Napredno: surova šestnajstiška pot';

  @override
  String get pathEditor_hexLabel => 'Šestnajstiške predpone';

  @override
  String get pathEditor_hexHelper =>
      'Dva šestnajstiška znaka na skok, ločena z vejicami';

  @override
  String pathEditor_invalidTokens(String tokens) {
    return 'Neveljaven: $tokens';
  }

  @override
  String get pathEditor_tooManyHops => 'Največ 64 skokov';

  @override
  String get pathEditor_usePath => 'Uporabite to pot';

  @override
  String get pathEditor_removeHop => 'Odstrani skok';

  @override
  String get pathEditor_unknownHop => 'Neznani ponovitelj';

  @override
  String get chat_pathSavedLocally =>
      'Shranjeno lokalno. Povežite se za sinhronizacijo.';

  @override
  String get chat_pathDeviceConfirmed => 'Naprava je potrdila.';

  @override
  String get chat_pathDeviceNotConfirmed => 'Naprava še ni potrdila.';

  @override
  String get chat_type => 'Vrsta';

  @override
  String get chat_path => 'Pot';

  @override
  String get chat_publicKey => 'Javni ključ';

  @override
  String get chat_compressOutgoingMessages => 'Stiskaj odhodna sporočila';

  @override
  String get chat_floodForced => 'Flood (prisilno)';

  @override
  String get chat_directForced => 'Neposredno (prisilno)';

  @override
  String chat_hopsForced(int count) {
    return 'Skoki: $count (prisilno)';
  }

  @override
  String get chat_floodAuto => 'Flood (samodejno)';

  @override
  String get chat_direct => 'Neposredni';

  @override
  String get chat_poiShared => 'Točka zanimivosti deljena';

  @override
  String chat_unread(int count) {
    return 'Neprebrano: $count';
  }

  @override
  String get chat_markAsUnread => 'Označi kot neprebrano';

  @override
  String get chat_newMessages => 'Nova sporočila';

  @override
  String get chat_openLink => 'Odpreti povezavo?';

  @override
  String get chat_openLinkConfirmation =>
      'Ali želite odpreti to povezavo v brskalniku?';

  @override
  String get chat_open => 'Odpri';

  @override
  String chat_couldNotOpenLink(String url) {
    return 'Povezave ni bilo mogoče odpreti: $url';
  }

  @override
  String get chat_invalidLink => 'Neveljavna oblika povezave';

  @override
  String get map_title => 'Zemljevid vozlišč';

  @override
  String get map_searchHint => 'Iščite ime ali ID vozlišča';

  @override
  String get map_activity => 'Dejavnost';

  @override
  String get map_online => 'V omrežju';

  @override
  String get map_recent => 'Nedavni';

  @override
  String get map_stale => 'Zastarelo';

  @override
  String get map_visible => 'Vidno';

  @override
  String get map_hidden => 'Skrit';

  @override
  String get map_centerOnNode => 'Centriraj na vozlišče';

  @override
  String get map_details => 'Podrobnosti';

  @override
  String get map_noGps => 'Brez GPS';

  @override
  String get map_noResults => 'Ni ujemajočih se vozlišč';

  @override
  String get map_lineOfSight => 'Linija vida';

  @override
  String get map_losScreenTitle => 'Linija vida';

  @override
  String get map_noNodesWithLocation => 'Ni vozlišč s podatki o lokaciji';

  @override
  String get map_nodesNeedGps =>
      'Vozlišča morajo deliti svoje koordinate GPS,\nda se prikažejo na zemljevidu';

  @override
  String map_nodesCount(int count) {
    return 'Vozlišča: $count';
  }

  @override
  String map_pinsCount(int count) {
    return 'Oznake: $count';
  }

  @override
  String get map_chat => 'Klepet';

  @override
  String get map_repeater => 'Ponovitelj';

  @override
  String get map_room => 'Soba';

  @override
  String get map_sensor => 'Senzor';

  @override
  String get map_pinDm => 'Oznaka (DM)';

  @override
  String get map_pinPrivate => 'Oznaka (zasebna)';

  @override
  String get map_pinPublic => 'Oznaka (javna)';

  @override
  String get map_lastSeen => 'Zadnjič viden';

  @override
  String get map_disconnectConfirm =>
      'Ste prepričani, da se želite odklopiti od te naprave?';

  @override
  String get map_from => 'Od';

  @override
  String get map_source => 'Vir';

  @override
  String get map_flags => 'Zastavice';

  @override
  String get map_type => 'Vrsta';

  @override
  String get map_path => 'Pot';

  @override
  String get map_location => 'Lokacija';

  @override
  String get map_estLocation => 'Ocenj. lokacija';

  @override
  String get map_publicKey => 'Javni ključ';

  @override
  String get map_publicKeyPrefixHint => 'npr. ab12';

  @override
  String get map_shareMarkerHere => 'Delite oznako tukaj';

  @override
  String get map_setAsMyLocation => 'Nastavite to kot mojo lokacijo';

  @override
  String get map_pinLabel => 'Napis oznake';

  @override
  String get map_label => 'Oznaka';

  @override
  String get map_pointOfInterest => 'Točka zanimivosti';

  @override
  String get map_sendToContact => 'Pošlji stiku';

  @override
  String get map_sendToChannel => 'Pošlji v kanal';

  @override
  String get map_noChannelsAvailable => 'Ni razpoložljivih kanalov.';

  @override
  String get map_publicLocationShare => 'Javno deljenje lokacije';

  @override
  String map_publicLocationShareConfirm(String channelLabel) {
    return 'Delili boste lokacijo v $channelLabel. Ta kanal je javen in vsak, ki ima PSK, jo lahko vidi.';
  }

  @override
  String get map_connectToShareMarkers =>
      'Povežite se z napravo za deljenje oznak.';

  @override
  String get map_filterNodes => 'Filtriraj vozlišča';

  @override
  String get map_nodeTypes => 'Vrste vozlišč';

  @override
  String get map_chatNodes => 'Vozlišča za klepet';

  @override
  String get map_repeaters => 'Ponovitelji';

  @override
  String get map_otherNodes => 'Druga vozlišča';

  @override
  String get map_showOverlaps => 'Prekrivanja ključev ponoviteljev';

  @override
  String get map_keyPrefix => 'Predpona ključa';

  @override
  String get map_filterByKeyPrefix => 'Filtriraj po predponi ključa';

  @override
  String get map_publicKeyPrefix => 'Predpona javnega ključa';

  @override
  String get map_markers => 'Oznake';

  @override
  String get map_showSharedMarkers => 'Pokaži deljene oznake';

  @override
  String get map_showGuessedLocations => 'Pokaži domnevne lokacije vozlišč';

  @override
  String get map_showDiscoveryContacts => 'Prikaži odkrite stike';

  @override
  String get map_guessedLocation => 'Predpostavljena lokacija';

  @override
  String get map_lastSeenTime => 'Čas zadnje zaznave';

  @override
  String get map_sharedPin => 'Deljena oznaka';

  @override
  String get map_sharedAt => 'Deljeno';

  @override
  String get map_joinRoom => 'Pridruži se sobi';

  @override
  String get map_manageRepeater => 'Upravljaj ponovitelja';

  @override
  String get map_tapToAdd => 'Pritisnite na vozlišča, da jih dodate poti.';

  @override
  String get map_runTrace => 'Zaženi sledenje poti';

  @override
  String get map_runTraceWithReturnPath => 'Vrni se nazaj po isti poti.';

  @override
  String get map_removeLast => 'Odstrani Zadnji';

  @override
  String get map_pathTraceCancelled => 'Spremljanje poti je prekinjeno.';

  @override
  String get map_regionRequestPathMustEndWithTarget =>
      'Pot se mora končati s ciljnim repetitorjem.';

  @override
  String get map_wardrive => 'Wardrive';

  @override
  String get map_wardriveStart => 'Začni';

  @override
  String get map_wardriveStop => 'Ustavi';

  @override
  String get map_wardriveZeroHopDiscovery => 'Zero-hop odkrivanje';

  @override
  String get map_wardriveDiscoverySent =>
      'Zahteva za wardrive odkrivanje je poslana.';

  @override
  String get map_wardriveUploadCancelled => 'Nalaganje wardrive je preklicano.';

  @override
  String map_wardriveDiscoveryFailed(String error) {
    return 'Wardrive odkrivanje ni uspelo: $error';
  }

  @override
  String map_wardriveRequests(int requests, int responses) {
    return 'Zahteve: $requests  Odgovori: $responses';
  }

  @override
  String map_wardriveLastRequest(String time) {
    return 'Zadnja zahteva: $time';
  }

  @override
  String get map_wardrivePhoneGpsNotUpdated =>
      'GPS telefona: še ni posodobljen';

  @override
  String map_wardrivePhoneGpsError(String error) {
    return 'GPS telefona: $error';
  }

  @override
  String map_wardrivePhoneGps(String latitude, String longitude) {
    return 'GPS telefona: $latitude, $longitude';
  }

  @override
  String get map_wardriveNoResponses => 'Ni še odgovorov odkrivanja.';

  @override
  String get map_wardriveDataTooltip => 'Wardrive podatki';

  @override
  String get map_wardriveUploadData => 'Naloži podatke';

  @override
  String get map_wardriveManageUploadSites => 'Upravljanje mest za nalaganje';

  @override
  String get map_wardriveAutoUpload => 'Samodejno nalaganje';

  @override
  String get map_wardriveReUpload => 'Znova naloži';

  @override
  String get map_wardriveScreenWakelock => 'Ne ugašaj zaslona';

  @override
  String get map_wardriveExport => 'Izvoz';

  @override
  String get map_wardriveImport => 'Uvoz';

  @override
  String get map_wardriveAutoDiscovery => 'Samodejno odkrivanje';

  @override
  String get map_wardriveSecondsSuffix => 's';

  @override
  String get map_wardriveSamplesNoNew => 'Ni novih vzorcev za nalaganje';

  @override
  String map_wardriveSamplesSaved(int count) {
    return 'Shranjeni vzorci: $count';
  }

  @override
  String map_wardriveAutoDiscoveryError(String error) {
    return 'Samodejno odkrivanje: $error';
  }

  @override
  String map_wardriveSampleSaveError(String error) {
    return 'Shranjevanje vzorca: $error';
  }

  @override
  String map_wardriveCoverageCells(int count) {
    return 'Celice pokritosti: $count';
  }

  @override
  String get map_wardriveCoverageResolution => 'Podrobnost pokritosti';

  @override
  String get map_wardriveCoverageResolutionPrompt =>
      'Izberite velikost blokov pokritosti (velikost = stranica bloka):';

  @override
  String get map_wardriveCoverageRegional => 'Regionalno';

  @override
  String get map_wardriveCoverageRegionalSubtitle => '~20 km (natančnost 4)';

  @override
  String get map_wardriveCoverageCity => 'Raven mesta';

  @override
  String get map_wardriveCoverageCitySubtitle => '~5 km (natančnost 5)';

  @override
  String get map_wardriveCoverageNeighborhood => 'Soseska';

  @override
  String get map_wardriveCoverageNeighborhoodSubtitle =>
      '~1,2 km (natančnost 6)';

  @override
  String get map_wardriveCoverageStreet => 'Raven ulice';

  @override
  String get map_wardriveCoverageStreetSubtitle => '~153 m (natančnost 7)';

  @override
  String get map_wardriveCoverageBuilding => 'Raven stavbe';

  @override
  String get map_wardriveCoverageBuildingSubtitle => '~38 m (natančnost 8)';

  @override
  String get map_wardriveAutoUploadEnabled => 'Samodejno nalaganje omogočeno.';

  @override
  String get map_wardriveAutoUploadDisabled =>
      'Samodejno nalaganje onemogočeno.';

  @override
  String get map_wardriveNoSamplesToUpload =>
      'Ni wardrive vzorcev za nalaganje.';

  @override
  String get map_wardriveUploadingSamples => 'Nalaganje vzorcev...';

  @override
  String map_wardriveUploadingTo(String site) {
    return 'Nalaganje na $site...';
  }

  @override
  String map_wardriveUploadBatch(int current, int total) {
    return 'Paket $current od $total';
  }

  @override
  String map_wardriveUploadSamplesProgress(int sent, int total) {
    return 'Pošiljanje $sent od $total';
  }

  @override
  String map_wardriveUploadTarget(String site) {
    return 'Cilj: $site';
  }

  @override
  String get map_wardriveUploadWaitingConnection => 'Čakanje na povezavo';

  @override
  String get map_wardriveUploadConnectionEstablished =>
      'Povezava vzpostavljena, nalaganje';

  @override
  String get map_wardriveUploadProcessingServer =>
      'Podatki naloženi, strežnik obdeluje';

  @override
  String map_wardriveUploadServerResponse(int statusCode) {
    return 'Strežnik je obdelal podatke, odgovor $statusCode';
  }

  @override
  String get map_wardriveUploadTimeoutTreatedAsSuccess =>
      'Nalaganje je poteklo; za to mesto označeno kot poslano';

  @override
  String map_wardriveUploadServerError(int statusCode) {
    return 'Napaka strežnika $statusCode';
  }

  @override
  String map_wardriveUploadRequestError(String error) {
    return 'Napaka nalaganja: $error';
  }

  @override
  String map_wardriveUploadFailed(String error) {
    return 'Nalaganje wardrive ni uspelo: $error';
  }

  @override
  String get map_wardriveUploadComplete => 'Nalaganje končano';

  @override
  String get map_wardriveUploadResults => 'Rezultati nalaganja';

  @override
  String map_wardriveSamplesUploaded(int count) {
    return 'Naloženih vzorcev: $count';
  }

  @override
  String get map_wardriveSelectUploadSites => 'Izberite mesta za nalaganje:';

  @override
  String get map_wardriveNoUploadSitesConfigured =>
      'Ni nastavljenih mest za nalaganje';

  @override
  String get map_wardriveAddSite => 'Dodaj mesto';

  @override
  String get map_wardriveUploadSitesUpdated =>
      'Mesta za nalaganje posodobljena.';

  @override
  String get map_wardriveAddUploadSite => 'Dodaj mesto za nalaganje';

  @override
  String get map_wardriveEditUploadSite => 'Uredi mesto za nalaganje';

  @override
  String get map_wardriveNameLabel => 'Ime';

  @override
  String get map_wardriveUrlLabel => 'URL';

  @override
  String get map_wardriveUploadBatchSize => 'Velikost paketa nalaganja';

  @override
  String map_wardriveUploadBatchSizeInvalid(int min, int max) {
    return 'Uporabite vrednost od $min do $max';
  }

  @override
  String get map_wardriveTreatTimeoutAsSuccess =>
      'Časovno omejitev obravnavaj kot uspeh';

  @override
  String get map_wardriveNameRequired => 'Ime je obvezno';

  @override
  String get map_wardriveNameExists => 'Ime že obstaja';

  @override
  String get map_wardriveValidUrlRequired => 'Zahtevan je veljaven URL';

  @override
  String get map_wardriveDeleteSite => 'Izbriši mesto';

  @override
  String map_wardriveDeleteSiteConfirm(String name) {
    return 'Izbrisati »$name«?';
  }

  @override
  String get map_wardriveNoSamplesToExport => 'Ni wardrive vzorcev za izvoz.';

  @override
  String get map_wardriveExportShareText => 'wardrive vzorci meshcore-open';

  @override
  String get map_wardriveSamplesExported =>
      'Wardrive vzorci izvoženi kot JSON datoteka.';

  @override
  String map_wardriveExportFailed(String error) {
    return 'Izvoz wardrive ni uspel: $error';
  }

  @override
  String get map_wardriveImportSamples => 'Uvozi wardrive vzorce';

  @override
  String get map_wardriveImportHint => 'Sem prilepite izvoženi wardrive JSON';

  @override
  String get map_wardriveNoNewSamplesImported =>
      'Ni bilo uvoženih novih wardrive vzorcev.';

  @override
  String map_wardriveSamplesImported(int count) {
    return 'Uvoženih wardrive vzorcev: $count.';
  }

  @override
  String map_wardriveImportFailed(String error) {
    return 'Uvoz wardrive ni uspel: $error';
  }

  @override
  String get map_wardriveNoSamplesToClear => 'Ni wardrive vzorcev za brisanje.';

  @override
  String get map_wardriveClearSamplesTitle => 'Izbrisati wardrive vzorce?';

  @override
  String map_wardriveClearSamplesConfirm(int count) {
    return 'To bo iz te naprave izbrisalo $count shranjenih vzorcev.';
  }

  @override
  String get map_wardriveSamplesCleared => 'Wardrive vzorci izbrisani.';

  @override
  String get map_wardriveRepNoLocation =>
      'Repetitor ni sporočil svoje lokacije';

  @override
  String map_wardriveDiscoveryWait(Object seconds) {
    return 'Počakajte $seconds sekund pred ponovnim poskusom';
  }

  @override
  String get map_wardriveFollowMe => 'Sledi moji lokaciji';

  @override
  String get map_wardriveDeleteBlock => 'Izbriši blok';

  @override
  String get map_wardriveInBackground => 'Izvajaj v ozadju';

  @override
  String get map_wardriveContinuousGPS => 'Neprekinjena lokacija GPS';

  @override
  String get map_wardriveShowRepeaterCoverage => 'Prikaži bloke pokritosti';

  @override
  String get map_wardriveHideRepeaterCoverage => 'Skrij bloke pokritosti';

  @override
  String get mapCache_title => 'Predpomnilnik zemljevidov brez povezave';

  @override
  String get mapCache_selectAreaFirst =>
      'Najprej izberite območje za predpomnjenje';

  @override
  String get mapCache_noTilesToDownload => 'Za to območje ni ploščic za prenos';

  @override
  String get mapCache_downloadTilesTitle => 'Naloži ploščice';

  @override
  String mapCache_downloadTilesPrompt(int count) {
    return 'Želite prenesti $count ploščic za uporabo brez povezave?';
  }

  @override
  String get mapCache_downloadAction => 'Naloži';

  @override
  String mapCache_cachedTiles(int count) {
    return 'Shranjenih ploščic: $count';
  }

  @override
  String mapCache_cachedTilesWithFailed(int downloaded, int failed) {
    return 'Shranjenih ploščic: $downloaded (neuspešnih: $failed)';
  }

  @override
  String get mapCache_clearOfflineCacheTitle =>
      'Počisti predpomnilnik brez povezave';

  @override
  String get mapCache_clearOfflineCachePrompt =>
      'Želite odstraniti vse predpomnjene ploščice zemljevida?';

  @override
  String get mapCache_offlineCacheCleared =>
      'Predpomnilnik brez povezave je počiščen';

  @override
  String get mapCache_noAreaSelected => 'Območje ni izbrano';

  @override
  String get mapCache_cacheArea => 'Območje predpomnjenja';

  @override
  String get mapCache_useCurrentView => 'Uporabi trenutni prikaz';

  @override
  String get mapCache_zoomRange => 'Razpon povečave';

  @override
  String mapCache_estimatedTiles(int count) {
    return 'Predvideno število ploščic: $count';
  }

  @override
  String mapCache_downloadedTiles(int completed, int total) {
    return 'Naloženo $completed / $total';
  }

  @override
  String get mapCache_downloadTilesButton => 'Naloži ploščice';

  @override
  String get mapCache_clearCacheButton => 'Počisti predpomnilnik';

  @override
  String mapCache_failedDownloads(int count) {
    return 'Neuspešni prenosi: $count';
  }

  @override
  String get mapCache_cachedTilesLabel => 'Ploščice v predpomnilniku';

  @override
  String get mapCache_cachedTileSummaryLabel =>
      'Povzetek ploščic v predpomnilniku';

  @override
  String mapCache_bulkDownloadDisabledForSource(String source) {
    return 'Množično prenašanje za uporabo brez povezave je za $source onemogočeno.';
  }

  @override
  String mapCache_bulkDownloadDisabledInConfig(String source) {
    return 'Množično prenašanje za uporabo brez povezave je za $source v tej konfiguraciji aplikacije onemogočeno.';
  }

  @override
  String mapCache_summarySource(String source) {
    return 'Vir: $source';
  }

  @override
  String mapCache_summaryCachedTilesForSource(int count) {
    return 'Ploščice v predpomnilniku za vir: $count';
  }

  @override
  String mapCache_summaryCachedInSelection(int count) {
    return 'V predpomnilniku na izbranem območju/povečavi: $count';
  }

  @override
  String mapCache_summaryApproxCacheSize(String size) {
    return 'Približna velikost predpomnilnika: $size';
  }

  @override
  String mapCache_boundsLabel(
    String north,
    String south,
    String east,
    String west,
  ) {
    return 'S $north, J $south, V $east, Z $west';
  }

  @override
  String get time_justNow => 'Pravkar';

  @override
  String time_minutesAgo(int minutes) {
    return 'pred $minutes min';
  }

  @override
  String time_hoursAgo(int hours) {
    return 'pred $hours h';
  }

  @override
  String time_daysAgo(int days) {
    return 'pred $days d';
  }

  @override
  String get time_hour => 'ura';

  @override
  String get time_hours => 'ur';

  @override
  String get time_day => 'dan';

  @override
  String get time_days => 'dni';

  @override
  String get time_week => 'teden';

  @override
  String get time_weeks => 'tedni';

  @override
  String get time_month => 'mesec';

  @override
  String get time_months => 'meseci';

  @override
  String get time_minutes => 'minut';

  @override
  String get time_allTime => 'Vse časovno obdobje';

  @override
  String get dialog_disconnect => 'Prekini povezavo';

  @override
  String get dialog_disconnectConfirm =>
      'Ste prepričani, da se želite odklopiti od te naprave?';

  @override
  String get login_repeaterLogin => 'Prijava v ponovitelja';

  @override
  String get login_roomLogin => 'Prijava v strežnik sobe';

  @override
  String get login_password => 'Geslo';

  @override
  String get login_enterPassword => 'Vnesite geslo';

  @override
  String get login_savePassword => 'Shrani geslo';

  @override
  String get login_savePasswordSubtitle =>
      'Geslo bo varno shranjeno na tej napravi';

  @override
  String get login_repeaterDescription =>
      'Vnesite geslo ponovitelja za dostop gosta ali skrbnika.';

  @override
  String get login_roomDescription =>
      'Vnesite geslo sobe za dostop gosta ali skrbnika.';

  @override
  String get login_routing => 'Usmerjanje';

  @override
  String get login_routingMode => 'Način usmerjanja';

  @override
  String get login_autoUseSavedPath => 'Avto (uporabi shranjeno pot)';

  @override
  String get login_forceFloodMode => 'Prisilni način flood';

  @override
  String get login_managePaths => 'Upravljaj poti';

  @override
  String get login_login => 'Prijava';

  @override
  String login_attempt(int current, int max) {
    return 'Poskus $current/$max';
  }

  @override
  String login_failed(String error) {
    return 'Prijava je bila neuspešna: $error';
  }

  @override
  String get login_failedMessage =>
      'Prijava je bila neuspešna. Geslo je napačno ali pa je repetitor nedosegljiv.';

  @override
  String get common_reload => 'Ponovno naloži';

  @override
  String get path_currentPathLabel => 'Trenutna pot';

  @override
  String get path_noRepeatersFound =>
      'Ni najdenih ponoviteljev ali strežnikov sob.';

  @override
  String get repeater_management => 'Upravljanje ponovitelja';

  @override
  String get room_management => 'Upravljanje strežnika sobe';

  @override
  String get repeater_guest => 'Informacije o ponovitelju';

  @override
  String get room_guest => 'Informacije o strežniku';

  @override
  String get repeater_managementTools => 'Orodja za upravljanje';

  @override
  String get repeater_guestTools => 'Orodja za goste';

  @override
  String get repeater_status => 'Stanje';

  @override
  String get repeater_statusSubtitle =>
      'Oglejte si stanje, statistiko in sosede ponovitelja';

  @override
  String get repeater_telemetry => 'Telemetrija';

  @override
  String get repeater_telemetrySubtitle =>
      'Oglejte si telemetrijo senzorjev in sistemsko statistiko';

  @override
  String get repeater_cli => 'CLI';

  @override
  String get repeater_cliSubtitle => 'Pošlji ukaze ponovitelju';

  @override
  String get repeater_neighbors => 'Sosedi';

  @override
  String get repeater_neighborsSubtitle => 'Oglejte si sosede brez skokov.';

  @override
  String get repeater_settings => 'Nastavitve';

  @override
  String get repeater_settingsSubtitle =>
      'Konfigurirajte parametre ponovitelja';

  @override
  String get repeater_clockSyncAfterLogin => 'Sinhronizacija ure po prijavi';

  @override
  String get repeater_clockSyncAfterLoginSubtitle =>
      'Po uspešni prijavi samodejno pošlji \"clock sync\"';

  @override
  String get repeater_statusTitle => 'Status ponovitelja';

  @override
  String get repeater_routingMode => 'Način usmerjanja';

  @override
  String get repeater_refresh => 'Osveži';

  @override
  String get repeater_statusRequestTimeout => 'Zahteva za stanje je potekla.';

  @override
  String repeater_errorLoadingStatus(String error) {
    return 'Napaka pri nalaganju stanja: $error';
  }

  @override
  String get repeater_systemInformation => 'Informacije o sistemu';

  @override
  String get repeater_battery => 'Baterija';

  @override
  String get repeater_clockAtLogin => 'Ura (ob prijavi)';

  @override
  String get repeater_uptime => 'Čas delovanja';

  @override
  String get repeater_queueLength => 'Dolžina čakalne vrste';

  @override
  String get repeater_debugFlags => 'Zastavice za odpravljanje napak';

  @override
  String get repeater_radioStatistics => 'Radio Statistika';

  @override
  String get repeater_lastRssi => 'Zadnji RSSI';

  @override
  String get repeater_lastSnr => 'Zadnji SNR';

  @override
  String get repeater_noiseFloor => 'Raven šuma';

  @override
  String get repeater_txAirtime => 'Čas oddajanja TX';

  @override
  String get repeater_rxAirtime => 'Čas sprejema RX';

  @override
  String get repeater_chanUtil => 'Uporaba kanala';

  @override
  String get repeater_packetStatistics => 'Statistika paketov';

  @override
  String get repeater_sent => 'Poslano';

  @override
  String get repeater_received => 'Prejeto';

  @override
  String get repeater_duplicates => 'Duplikati';

  @override
  String get repeater_packetErrors => 'Napake paketov';

  @override
  String repeater_daysHoursMinsSecs(
    int days,
    int hours,
    int minutes,
    int seconds,
  ) {
    return '$days dni ${hours}h ${minutes}m ${seconds}s';
  }

  @override
  String repeater_packetTxTotal(int total, String flood, String direct) {
    return 'Skupno: $total, Flood: $flood, Neposredno: $direct';
  }

  @override
  String repeater_packetRxTotal(int total, String flood, String direct) {
    return 'Skupno: $total, Flood: $flood, Neposredno: $direct';
  }

  @override
  String repeater_duplicatesFloodDirect(String flood, String direct) {
    return 'Flood: $flood, Neposredni: $direct';
  }

  @override
  String repeater_duplicatesTotal(int total) {
    return 'Skupno: $total';
  }

  @override
  String get repeater_settingsTitle => 'Nastavitve ponovitelja';

  @override
  String get repeater_basicSettings => 'Osnovne nastavitve';

  @override
  String get repeater_repeaterName => 'Ime ponovitelja';

  @override
  String get repeater_repeaterNameHelper => 'Prikazno ime tega ponovitelja';

  @override
  String get repeater_adminPassword => 'Admin geslo';

  @override
  String get repeater_adminPasswordHelper => 'Geslo za poln dostop';

  @override
  String get repeater_guestPassword => 'Geslo za goste';

  @override
  String get repeater_guestPasswordHelper => 'Geslo za dostop samo za branje';

  @override
  String get repeater_radioSettings => 'Nastavitve Radija';

  @override
  String get repeater_frequencyMhz => 'Frekvenca (MHz)';

  @override
  String get repeater_frequencyHelper => '300–2500 MHz';

  @override
  String get repeater_txPower => 'TX Moč';

  @override
  String get repeater_txPowerHelper => '1-30 dBm';

  @override
  String get repeater_bandwidth => 'Pasovna širina';

  @override
  String get repeater_spreadingFactor => 'Razširitveni faktor';

  @override
  String get repeater_codingRate => 'Kodno razmerje';

  @override
  String get repeater_locationSettings => 'Nastavitve lokacije';

  @override
  String get repeater_latitude => 'Širina';

  @override
  String get repeater_latitudeHelper => 'Decimalne stopinje (npr. 37.7749)';

  @override
  String get repeater_longitude => 'Dolžina';

  @override
  String get repeater_longitudeHelper => 'Decimalne stopinje (npr. -122.4194)';

  @override
  String get repeater_features => 'Funkcije';

  @override
  String get repeater_packetForwarding => 'Posredovanje paketov';

  @override
  String get repeater_packetForwardingSubtitle =>
      'Dovoli ponovitelju posredovanje paketov';

  @override
  String get repeater_guestAccess => 'Dostop za goste';

  @override
  String get repeater_guestAccessSubtitle =>
      'Dovoli gostom dostop samo za branje';

  @override
  String get repeater_privacyMode => 'Privatni način';

  @override
  String get repeater_privacyModeSubtitle => 'Skrij ime/lokacijo v advertih';

  @override
  String get repeater_advertisementSettings => 'Nastavitve advertov';

  @override
  String get repeater_localAdvertInterval => 'Interval lokalnih advertov';

  @override
  String repeater_localAdvertIntervalMinutes(int minutes) {
    return '$minutes minut';
  }

  @override
  String get repeater_floodAdvertInterval => 'Interval flood advertov';

  @override
  String repeater_floodAdvertIntervalHours(int hours) {
    return '$hours ur';
  }

  @override
  String get repeater_encryptedAdvertInterval => 'Interval šifriranih advertov';

  @override
  String get repeater_dangerZone => 'Nevarno območje';

  @override
  String get repeater_rebootRepeater => 'Ponovni zagon ponovitelja';

  @override
  String get repeater_rebootRepeaterSubtitle => 'Ponovni zagon ponovitelja.';

  @override
  String get repeater_rebootRepeaterConfirm =>
      'Ste prepričani, da želite znova zagnati tega ponovitelja?';

  @override
  String get repeater_regenerateIdentityKey => 'Znova ustvari ključ identitete';

  @override
  String get repeater_regenerateIdentityKeySubtitle =>
      'Ustvarite nov par javnega/zasebnega ključa';

  @override
  String get repeater_regenerateIdentityKeyConfirm =>
      'To bo ustvarilo novo identiteto ponovitelja. Želite nadaljevati?';

  @override
  String get repeater_eraseFileSystem => 'Izbriši datotečni sistem';

  @override
  String get repeater_eraseFileSystemSubtitle =>
      'Formatiraj datotečni sistem ponovitelja';

  @override
  String get repeater_eraseFileSystemConfirm =>
      'OPOZORILO: To bo izbrisalo vse podatke na ponovitelju. Tega ni mogoče razveljaviti!';

  @override
  String get repeater_eraseSerialOnly =>
      'Brisanje je na voljo samo preko serijske konzole.';

  @override
  String repeater_commandSent(String command) {
    return 'Ukaz poslan: $command';
  }

  @override
  String repeater_errorSendingCommand(String error) {
    return 'Napaka pri pošiljanju ukaza: $error';
  }

  @override
  String get repeater_confirm => 'Potrdi';

  @override
  String get repeater_settingsSaved => 'Nastavitve so shranjene uspešno.';

  @override
  String get repeater_rxGain => 'Povečano ojačanje RX';

  @override
  String get repeater_rxGainHelper =>
      'Večja občutljivost, večji porabljeni tok (velja samo za SX1262/SX1268)';

  @override
  String get repeater_refreshRxGain => 'Osveži povečano ojačanje RX';

  @override
  String get repeater_multiAcks => 'Več potrdil';

  @override
  String get repeater_multiAcksSubtitle =>
      'Potrjuj sporočila po več poteh za boljšo dostavo';

  @override
  String get repeater_refreshMultiAcks => 'Osveži več potrdil';

  @override
  String get repeater_networkHealth => 'Stanje omrežja';

  @override
  String get repeater_loopDetect => 'Detekcija ciklov';

  @override
  String get repeater_loopDetectHelper =>
      'Zavrže flood pakete, ki so videti kot zanke usmerjanja';

  @override
  String get repeater_loopDetectOff => 'Izklopljeno';

  @override
  String get repeater_loopDetectMinimal => 'Minimalen';

  @override
  String get repeater_loopDetectModerate => 'Zmeren';

  @override
  String get repeater_loopDetectStrict => 'Strogi';

  @override
  String get repeater_dutyCycle => 'Ciklus delovanja';

  @override
  String get repeater_dutyCycleHelper => 'Največji odstotek časa oddajanja';

  @override
  String repeater_dutyCyclePercent(int percent) {
    return '$percent %';
  }

  @override
  String get repeater_ownerInfo => 'Informacije o operaterju';

  @override
  String get repeater_ownerInfoHelper => 'javni podatki o tej napravi';

  @override
  String get repeater_refreshOwnerInfo => 'Osveži informacije o operaterju';

  @override
  String get repeater_floodMax => 'Največ skokov flood';

  @override
  String get repeater_floodMaxHelper =>
      'Največje število skokov, ki jih lahko opravi flood paket (0-64)';

  @override
  String get repeater_advancedSettings => 'Napredno';

  @override
  String get repeater_advancedSettingsSubtitle =>
      'Gumbi za nastavljanje za izkušene uporabnike';

  @override
  String get repeater_pathHashMode => 'Način ustvarjanja hash-a poti';

  @override
  String get repeater_pathHashModeHelper =>
      'Bajti, uporabljeni za kodiranje ID-ja tega repetitorja v oznakah flood poti/zaznavanja zank. 0=1 bajt (256 ID-jev, do 64 skokov), 1=2 bajta (65.000 ID-jev, do 32 skokov), 2=3 bajti (16 milijonov ID-jev, do 21 skokov). Vdelana programska oprema pred v1.14 je vedno uporabljala 1-bajtne poti; v1.14 in novejše je mogoče nastaviti na 2- ali 3-bajtne poti.';

  @override
  String get repeater_keySettings => 'Sprememba ključev vozlišča';

  @override
  String get repeater_keySettingsSubtitle =>
      'Spremeni par javnega in zasebnega ključa';

  @override
  String get repeater_prvKey => 'Zasebni ključ';

  @override
  String get repeater_prvKeyHelper =>
      'Nov zasebni ključ repetitorja — šestnajstiški niz s 128 znaki.';

  @override
  String get repeater_generatePrvKey => 'Ustvari naključni par ključev';

  @override
  String get repeater_stopGeneratingPrvKey => 'Prekini iskanje para ključev';

  @override
  String get repeater_pubKey => 'Javni ključ';

  @override
  String get repeater_pubKeyHelper =>
      'To je javni ključ, ki pripada ustvarjenemu zasebnemu ključu. Ni ga mogoče nastaviti neposredno.';

  @override
  String get repeater_pubKeyPrefix => 'Želena predpona';

  @override
  String repeater_pubKeyPrefixHelper(int tries) {
    return 'Iskanje javnega ključa, ki se začne s temi šestnajstiškimi znaki. Pričakovano število poskusov: $tries.';
  }

  @override
  String get repeater_txDelay => 'Zakasnitev TX za flood promet';

  @override
  String get repeater_txDelayHelper =>
      'Razmik med ponovnimi oddajami za flood promet kot večkratnik časa oddaje paketa (0-2, privzeto 0,5). Višja vrednost = manj kolizij, a počasnejša dostava.';

  @override
  String get repeater_directTxDelay => 'Zakasnitev TX za neposredni promet';

  @override
  String get repeater_directTxDelayHelper =>
      'Razmik med ponovnimi oddajami za neposredni (ne flood) promet kot večkratnik časa oddaje paketa (0-2, privzeto 0,3).';

  @override
  String get repeater_intThresh => 'Prag motenj';

  @override
  String get repeater_intThreshHelper =>
      'Prag, ki se posreduje kalibraciji ravni šuma radia, da radio zavrne motnje nad to ravnjo. 0 onemogoči – zvišajte ga le, če v šumnem pasu opazite napake RX.';

  @override
  String get repeater_agcResetInterval => 'Interval ponastavitve AGC';

  @override
  String get repeater_agcResetIntervalHelper =>
      'Kako pogosto ponastaviti samodejno regulacijo ojačanja radia, da se obnovi iz zataknjenega stanja. V sekundah, zaokroženo navzdol na večkratnik števila 4. 0 onemogoči periodične ponastavitve.';

  @override
  String get repeater_actionsTitle => 'Dejanja';

  @override
  String get repeater_sendAdvert => 'Pošlji flood advert';

  @override
  String get repeater_sendAdvertSubtitle => 'Razpošlji flood advert po omrežju';

  @override
  String get repeater_sendAdvertZeroHop => 'Pošlji zero-hop advert';

  @override
  String get repeater_sendAdvertZeroHopSubtitle =>
      'Razpošlji advert z enim skokom (brez ponoviteljev)';

  @override
  String get repeater_clockSync => 'Sinhroniziraj uro zdaj';

  @override
  String get repeater_clockSyncSubtitle => 'Pošlji čas telefona ponovitelju';

  @override
  String repeater_actionSucceeded(String action) {
    return '$action: uspešno';
  }

  @override
  String repeater_actionFailed(String action, String error) {
    return '$action ni bilo uspešno: $error';
  }

  @override
  String get repeater_settingsSavedRebootNeeded =>
      'Nastavitve shranjene – znova zaženite repetitor, da jih uveljavite';

  @override
  String repeater_settingsPartialFailure(String failures) {
    return 'Nekaterih nastavitev ni bilo mogoče uveljaviti: $failures';
  }

  @override
  String repeater_errorSavingSettings(String error) {
    return 'Napaka pri shranjevanju nastavitev: $error';
  }

  @override
  String get repeater_refreshBasicSettings => 'Osveži osnovne nastavitve';

  @override
  String get repeater_refreshRadioSettings => 'Osveži nastavitve radia';

  @override
  String get repeater_refreshTxPower => 'Osveži moč TX';

  @override
  String get repeater_refreshPacketForwarding => 'Osveži posredovanje paketov';

  @override
  String get repeater_refreshGuestAccess => 'Osveži dostop za goste';

  @override
  String get repeater_refreshPrivacyMode => 'Osveži način zasebnosti';

  @override
  String repeater_refreshed(String label) {
    return '$label je bil/a posodobljen/a';
  }

  @override
  String repeater_errorRefreshing(String label) {
    return 'Napaka pri osveževanju $label';
  }

  @override
  String get repeater_cliTitle => 'CLI ponovitelja';

  @override
  String get repeater_debugNextCommand => 'Razhrošči naslednji ukaz';

  @override
  String get repeater_commandHelp => 'Pomoč za ukaze';

  @override
  String get repeater_clearHistory => 'Počisti zgodovino';

  @override
  String get repeater_noCommandsSent => 'Še ni poslanih ukazov';

  @override
  String get repeater_typeCommandOrUseQuick =>
      'Vnesite ukaz spodaj ali uporabite hitre ukaze';

  @override
  String get repeater_enterCommandHint => 'Vnesite ukaz...';

  @override
  String get repeater_previousCommand => 'Prejšnji ukaz';

  @override
  String get repeater_nextCommand => 'Naslednji ukaz';

  @override
  String get repeater_enterCommandFirst => 'Vnesite ukaz najprej';

  @override
  String get repeater_cliCommandFrameTitle => 'Okvir ukaza CLI';

  @override
  String repeater_cliCommandError(String error) {
    return 'Napaka: $error';
  }

  @override
  String get repeater_cliQuickGetName => 'Pridobi ime';

  @override
  String get repeater_cliQuickGetRadio => 'Pridobi radio';

  @override
  String get repeater_cliQuickGetTx => 'Pridobi TX';

  @override
  String get repeater_cliQuickNeighbors => 'Sosedi';

  @override
  String get repeater_cliQuickVersion => 'Različica';

  @override
  String get repeater_cliQuickAdvertise => 'Pošlji advert';

  @override
  String get repeater_cliQuickClock => 'Ura';

  @override
  String get repeater_cliQuickClockSync => 'Usklajevanje ure';

  @override
  String get repeater_cliQuickDiscovery => 'Odkrijte sosede';

  @override
  String get repeater_cliHelpAdvert => 'Pošlje advert paket';

  @override
  String get repeater_cliHelpReboot =>
      'Znova zažene napravo. (Opomba: verjetno boste prejeli \'Timeout\', kar je normalno)';

  @override
  String get repeater_cliHelpClock => 'Prikaže trenutno uro po uri naprave.';

  @override
  String get repeater_cliHelpPassword =>
      'Nastavi novo skrbniško geslo za napravo.';

  @override
  String get repeater_cliHelpVersion =>
      'Prikaže različico naprave in datum izdelave vdelane programske opreme.';

  @override
  String get repeater_cliHelpClearStats =>
      'Ponastavi različne števce statistike na nič.';

  @override
  String get repeater_cliHelpSetAf =>
      'Nastavi faktor časa oddajanja (air-time-factor).';

  @override
  String get repeater_cliHelpSetTx =>
      'Nastavi moč oddajanja LoRa v dBm. (za uveljavitev je potreben ponovni zagon)';

  @override
  String get repeater_cliHelpSetRepeat =>
      'Omogoči ali onemogoči vlogo ponovitelja za to vozlišče.';

  @override
  String get repeater_cliHelpSetAllowReadOnly =>
      '(Strežnik sobe) Če je \'on\', je dovoljena prijava s praznim geslom, vendar objavljanje v sobi ni mogoče. (samo branje)';

  @override
  String get repeater_cliHelpSetFloodMax =>
      'Nastavi največje število skokov za dohodni flood paket (če je >= maks, paket ni posredovan)';

  @override
  String get repeater_cliHelpSetIntThresh =>
      'Nastavi Prag Interferencij (v dB). Privzeto je 14. Nastavi na 0 za onemogočitev zaznavanja interferenc kanalov.';

  @override
  String get repeater_cliHelpSetAgcResetInterval =>
      'Nastavi interval za ponastavitev samodejne regulacije ojačanja (AGC). Nastavi na 0, da onemogočiš.';

  @override
  String get repeater_cliHelpSetMultiAcks =>
      'Omogoči ali onemogoči funkcijo \"dvojnih potrdil\".';

  @override
  String get repeater_cliHelpSetAdvertInterval =>
      'Nastavi interval časovnika v minutah za pošiljanje lokalnega (zero-hop) adverta. Nastavi na 0, da onemogočiš.';

  @override
  String get repeater_cliHelpSetFloodAdvertInterval =>
      'Nastavi interval časovnika v urah za pošiljanje flood adverta. Nastavi na 0, da onemogočiš.';

  @override
  String get repeater_cliHelpSetGuestPassword =>
      'Nastavi/posodobi geslo za goste. (pri ponoviteljih lahko gostje po prijavi pošljejo zahtevo \"Get Stats\")';

  @override
  String get repeater_cliHelpSetName => 'Nastavi ime v advertu.';

  @override
  String get repeater_cliHelpSetLat =>
      'Nastavi zemljepisno širino v advertu za zemljevid. (decimalne stopinje)';

  @override
  String get repeater_cliHelpSetLon =>
      'Nastavi zemljepisno dolžino v advertu za zemljevid. (decimalne stopinje)';

  @override
  String get repeater_cliHelpSetRadio =>
      'Nastavi popolnoma nove radijske parametre in jih shrani v nastavitve. Za uveljavitev je potreben ukaz \"reboot\".';

  @override
  String get repeater_cliHelpSetRxDelay =>
      'Nastavi (eksperimentalno) osnovo (mora biti > 1, da ima učinek) za rahlo zakasnitev prejetih paketov glede na moč signala/oceno. Nastavite na 0, da onemogočite.';

  @override
  String get repeater_cliHelpSetTxDelay =>
      'Nastavi faktor, ki se pomnoži s časom oddaje paketa v načinu flood in z naključnim sistemom rež, da zakasni njegovo posredovanje. (da se zmanjša verjetnost kolizij)';

  @override
  String get repeater_cliHelpSetDirectTxDelay =>
      'Enako kot txdelay, vendar za naključno zakasnitev pri posredovanju paketov v neposrednem načinu.';

  @override
  String get repeater_cliHelpSetBridgeEnabled => 'Omogoči/onemogoči most.';

  @override
  String get repeater_cliHelpSetBridgeDelay =>
      'Nastavi zakasnitev pred ponovnim oddajanjem paketov.';

  @override
  String get repeater_cliHelpSetBridgeSource =>
      'Izberite, ali bo most ponovno oddajal prejete ali oddane pakete.';

  @override
  String get repeater_cliHelpSetBridgeBaud =>
      'Nastavi hitrost serijske povezave za mostove rs232.';

  @override
  String get repeater_cliHelpSetBridgeSecret =>
      'Nastavi skrivnost mostu za mostove ESPNOW.';

  @override
  String get repeater_cliHelpSetAdcMultiplier =>
      'Nastavi faktor po meri za prilagoditev sporočene napetosti baterije (podprto le na nekaterih ploščah).';

  @override
  String get repeater_cliHelpTempRadio =>
      'Nastavi začasne radio parametre za določeno časovno obdobje, kar po preteku časa vrne originalne radio parametre. (ne shranjuje v preferencije).';

  @override
  String get repeater_cliHelpSetPerm =>
      'Spremeni ACL. Odstrani ustrezen vnos (po predponi pubkey), če je \"permissions\" enako nič. Doda nov vnos, če je pubkey-hex polne dolžine in ga v ACL še ni. Posodobi vnos z ujemajočo se predpono pubkey. Biti dovoljenj se razlikujejo glede na vlogo vdelane programske opreme, spodnja 2 bita pa sta: 0 (gost), 1 (samo branje), 2 (branje in pisanje), 3 (skrbnik)';

  @override
  String get repeater_cliHelpGetBridgeType =>
      'Pridobi vrsto mostu: none, rs232, espnow';

  @override
  String get repeater_cliHelpLogStart =>
      'Začne beleženje paketov v datotečni sistem.';

  @override
  String get repeater_cliHelpLogStop =>
      'Ustavi beleženje paketov v datotečni sistem.';

  @override
  String get repeater_cliHelpLogErase =>
      'Izbriše dnevnike paketov iz datotečnega sistema.';

  @override
  String get repeater_cliHelpNeighbors =>
      'Prikaže seznam drugih ponoviteljev, slišanih prek advertov brez skokov. Vsaka vrstica je id-prefix-hex:timestamp:snr-times-4';

  @override
  String get repeater_cliHelpNeighborRemove =>
      'Odstrani prvi ustrezni vnos (po predponi pubkey (hex)) s seznama sosedov.';

  @override
  String get repeater_cliHelpRegion =>
      '(samo prek serijske povezave) Navede vse določene regije in trenutna dovoljenja za flood.';

  @override
  String get repeater_cliHelpRegionLoad =>
      'OPOMBA: to je poseben večukazni klic. Vsak naslednji ukaz je ime regije (zamaknjeno s presledki za prikaz nadrejene hierarhije, vsaj z enim presledkom). Konča se s pošiljanjem prazne vrstice/ukaza.';

  @override
  String get repeater_cliHelpRegionGet =>
      'Išče regijo s podano predpono imena (ali \"*\" za globalni obseg). Odgovori s \"-> region-name (parent-name) \'F\'\"';

  @override
  String get repeater_cliHelpRegionPut =>
      'Dodaja ali posodobi regijsko definicijo s podanim imenom.';

  @override
  String get repeater_cliHelpRegionRemove =>
      'Izbriše definicijo regije s podanim imenom. (mora se popolnoma ujemati in ne sme imeti podregij)';

  @override
  String get repeater_cliHelpRegionAllowf =>
      'Nastavi dovoljenje \'F\'lood za podano regijo. (\'*\' za globalni/starejši obseg)';

  @override
  String get repeater_cliHelpRegionDenyf =>
      'Odstrani dovoljenje \'F\'lood za podano regijo. (OPOMBA: trenutno NI priporočljivo uporabiti na globalnem/starejšem obsegu!!)';

  @override
  String get repeater_cliHelpRegionHome =>
      'Odgovori s trenutno \'domačo\' regijo. (Še se nikjer ne uporablja, rezervirano za prihodnost)';

  @override
  String get repeater_cliHelpRegionHomeSet => 'Nastavi \'domačo\' regijo.';

  @override
  String get repeater_cliHelpRegionSave =>
      'Shrani seznam/zemljevid regij v pomnilnik.';

  @override
  String get repeater_cliHelpGps =>
      'Pokaže status GPS-ja. Če je GPS izklopljen, odgovori samo \"off\", če je vklopljen, odgovori z \"on\", statusom, \"fix\" in številom satelitov.';

  @override
  String get repeater_cliHelpGpsOnOff => 'Preklopi stanje napajanja GPS.';

  @override
  String get repeater_cliHelpGpsSync => 'Sinhronizira čas vozlišča z uro GPS.';

  @override
  String get repeater_cliHelpGpsSetLoc =>
      'Nastavi položaj vozlišča na koordinate GPS in shrani nastavitve.';

  @override
  String get repeater_cliHelpGpsAdvert =>
      'Prikaže nastavitev lokacije v advertih vozlišča:\n- none: ne vključi lokacije v adverte\n- share: deli lokacijo GPS (iz SensorManager)\n- prefs: v advertu objavi lokacijo, shranjeno v nastavitvah';

  @override
  String get repeater_cliHelpGpsAdvertSet =>
      'Nastavi konfiguracijo lokacije v advertih.';

  @override
  String get repeater_commandsListTitle => 'Seznam ukazov';

  @override
  String get repeater_commandsListNote =>
      'OPOMBA: za različne ukaze \"set ...\" obstaja tudi ukaz \"get ...\".';

  @override
  String get repeater_general => 'Splošno';

  @override
  String get repeater_settingsCategory => 'Nastavitve';

  @override
  String get repeater_bridge => 'Most';

  @override
  String get repeater_logging => 'Beleženje';

  @override
  String get repeater_neighborsRepeaterOnly => 'Sosedi (le za repetitorje)';

  @override
  String get repeater_regionManagementRepeaterOnly =>
      'Upravljanje regij (zgolj za repetitorje)';

  @override
  String get repeater_regionNote =>
      'Regijski ukazi so bili uvedeni za upravljanje definicij regij in dovoljenj.';

  @override
  String get repeater_gpsManagement => 'Upravljanje GPS';

  @override
  String get repeater_gpsNote =>
      'Ukaz gps je bil uveden za upravljanje nastavitev, povezanih z lokacijo.';

  @override
  String get repeater_getCategory => 'Dobite vrednosti';

  @override
  String get repeater_powerMgmt => 'Upravljanje z energijo';

  @override
  String get repeater_sensors => 'Senzori';

  @override
  String get repeater_cliHelpPowerOff =>
      'Izklopi napravo. (odziva ni pričakovati)';

  @override
  String get repeater_cliHelpClkReboot =>
      'Ponastavi uro na znano epoho in znova zažene napravo.';

  @override
  String get repeater_cliHelpAdvertZeroHop =>
      'Pošlje zero-hop advert (samo neposrednim sosedom).';

  @override
  String get repeater_cliHelpStartOta =>
      'Začne posodobitev vdelane programske opreme po zraku (OTA) na podprtih ploščah.';

  @override
  String get repeater_cliHelpTime =>
      'Nastavi uro naprave na podano število sekund Unixove epohe. Ura ne more iti nazaj.';

  @override
  String get repeater_cliHelpBoard =>
      'Prikaže proizvajalca plošče / identifikator strojne opreme.';

  @override
  String get repeater_cliHelpDiscoverNeighbors =>
      'Pošlje zahtevo za odkrivanje sosednjih vozlišč. (Samo za ponovitelje)';

  @override
  String get repeater_cliHelpPowersaving =>
      'Prikaže, ali je vklopljen način varčevanja z energijo.';

  @override
  String get repeater_cliHelpPowersavingOnOff =>
      'Omogoča ali onemogoča način varčevanja z energijo (če je podprt).';

  @override
  String get repeater_cliHelpErase =>
      '(Samo prek serijske povezave) Formatira datotečni sistem naprave. Izbriše vse nastavitve in stike.';

  @override
  String get repeater_cliHelpSetDutyCycle =>
      'Nastavi največji dovoljeni obratovalni cikel oddajanja v odstotkih (1-100). Interno prilagodi faktor časa oddajanja.';

  @override
  String get repeater_cliHelpSetPrvKey =>
      'Nadomesti zasebni ključ identitete naprave. Za uveljavitev je potreben ponovni zagon. Ustvari nov javni ključ.';

  @override
  String get repeater_cliHelpSetRadioRxGain =>
      '(Samo za SX126x) Preklopi povečano ojačanje RX za boljšo občutljivost ob večji porabi toka.';

  @override
  String get repeater_cliHelpSetOwnerInfo =>
      'Nastavi niz s kontaktnimi podatki lastnika, ki je vključen v adverte. Za nove vrstice uporabite \'|\'.';

  @override
  String get repeater_cliHelpSetPathHashMode =>
      'Nastavi način path-hash. 0 = starejši, 1 = standardni, 2 = strogi. Vpliva na to, kako se ujemajo poti usmerjanja.';

  @override
  String get repeater_cliHelpSetLoopDetect =>
      'Nastavi občutljivost zaznavanja zank usmerjanja: off, minimal, moderate ali strict.';

  @override
  String get repeater_cliHelpSetFreq =>
      '(Samo prek serijske povezave) Hitro nastavi samo frekvenco. Potreben je ponovni zagon. Za vse radijske parametre raje uporabite \"set radio\".';

  @override
  String get repeater_cliHelpSetBridgeChannel =>
      '(Samo za most ESPNow) Nastavlja kanal WiFi-ja (1-14), ki ga uporablja most.';

  @override
  String get repeater_cliHelpGetName => 'Prikaže nastavljeno ime vozlišča.';

  @override
  String get repeater_cliHelpGetRole =>
      'Prikaže vlogo vdelane programske opreme (ponovitelj, strežnik sobe itd.).';

  @override
  String get repeater_cliHelpGetPublicKey => 'Prikazuje javni ključ naprave.';

  @override
  String get repeater_cliHelpGetPrvKey =>
      '(Samo prek serijske povezave) Prikaže zasebni ključ naprave. Obravnavajte ga kot skrivnost.';

  @override
  String get repeater_cliHelpGetRepeat =>
      'Pokaže, ali je omogočeno posredovanje paketov (delovanje kot repetitor).';

  @override
  String get repeater_cliHelpGetTx => 'Prikazuje trenutno moč TX v dBm.';

  @override
  String get repeater_cliHelpGetFreq => 'Prikaže nastavljeno frekvenco v MHz.';

  @override
  String get repeater_cliHelpGetRadio =>
      'Prikaže vse parametre radija: frekvenco, širino pasu, faktor razširjanja, kodno razmerje.';

  @override
  String get repeater_cliHelpGetRadioRxGain =>
      '(Samo za SX126x) Prikaže stanje povečanega ojačanja RX.';

  @override
  String get repeater_cliHelpGetAf => 'Prikaže trenutni faktor časa oddajanja.';

  @override
  String get repeater_cliHelpGetDutyCycle =>
      'Prikazuje trenutno dovoljeno stopnjo delovanja kot odstotek.';

  @override
  String get repeater_cliHelpGetIntThresh =>
      'Prikazuje prag medsebojnega vpliva kanala v dB.';

  @override
  String get repeater_cliHelpGetAgcResetInterval =>
      'Prikaže interval ponastavitve AGC v sekundah.';

  @override
  String get repeater_cliHelpGetMultiAcks =>
      'Pokaže, ali je vklopljen način dvojnega potrdila (1) ali je izklopljen (0).';

  @override
  String get repeater_cliHelpGetAllowReadOnly =>
      'Pokaže, ali je gostom dovoljen dostop samo za branje.';

  @override
  String get repeater_cliHelpGetAdvertInterval =>
      'Prikaže interval lokalnih advertov v minutah.';

  @override
  String get repeater_cliHelpGetFloodAdvertInterval =>
      'Prikaže interval flood advertov v urah.';

  @override
  String get repeater_cliHelpGetGuestPassword =>
      'Prikaže nastavljeno geslo za goste.';

  @override
  String get repeater_cliHelpGetLat => 'Prikaže določeno zemljepisno širino.';

  @override
  String get repeater_cliHelpGetLon =>
      'Prikaže nastavljeno zemljepisno dolžino.';

  @override
  String get repeater_cliHelpGetRxDelay =>
      'Prikazuje osnovno vrednost RX odlašanja.';

  @override
  String get repeater_cliHelpGetTxDelay =>
      'Prikaže faktor txdelay v načinu flood.';

  @override
  String get repeater_cliHelpGetDirectTxDelay =>
      'Prikaže faktor txdelay v neposrednem načinu.';

  @override
  String get repeater_cliHelpGetFloodMax =>
      'Prikaže največje število skokov za flood pakete.';

  @override
  String get repeater_cliHelpGetOwnerInfo =>
      'Prikazuje niz z informacijami o lastniku.';

  @override
  String get repeater_cliHelpGetPathHashMode =>
      'Prikaže način delovanja z hashjem poti (0/1/2).';

  @override
  String get repeater_cliHelpGetLoopDetect =>
      'Prikazuje občutljivost na zaznavanje ciklov.';

  @override
  String get repeater_cliHelpGetAcl =>
      '(Samo prek serijske povezave) Navede vnose za nadzor dostopa na ponovitelju.';

  @override
  String get repeater_cliHelpGetBridgeEnabled =>
      'Pokaže, ali je most omogočen.';

  @override
  String get repeater_cliHelpGetBridgeDelay =>
      'Prikazuje zamik mosta v milisekundah.';

  @override
  String get repeater_cliHelpGetBridgeSource =>
      'Pokaže, ali most prenaša pakete RX ali TX.';

  @override
  String get repeater_cliHelpGetBridgeBaud =>
      '(Samo za most RS232) Prikazuje hitrost prenosa podatkov na mostu.';

  @override
  String get repeater_cliHelpGetBridgeChannel =>
      '(Samo za most ESPNow) Prikazuje kanal WiFi mosta.';

  @override
  String get repeater_cliHelpGetBridgeSecret =>
      '(Samo za most ESPNow) Prikaže skupno skrivnost mostu.';

  @override
  String get repeater_cliHelpGetBootloaderVer =>
      '(Samo za NRF52) Prikaže različico zagonskega nalagalnika.';

  @override
  String get repeater_cliHelpGetAdcMultiplier =>
      'Prikazuje pomnoževalnik ADC (skaliranje napetosti baterije).';

  @override
  String get repeater_cliHelpGetPwrMgtSupport =>
      'Sporoči, ali plošča podpira upravljanje napajanja.';

  @override
  String get repeater_cliHelpGetPwrMgtSource =>
      'Prikaže trenutni vir napajanja: zunanji ali baterija.';

  @override
  String get repeater_cliHelpGetPwrMgtBootReason =>
      'Prikaže zadnje razloge za ponastavitev in izklop.';

  @override
  String get repeater_cliHelpGetPwrMgtBootMv =>
      'Prikazuje napetost baterije v mV ob zagonu.';

  @override
  String get repeater_cliHelpSensorGet =>
      'Prebere nastavitev senzorja po meri glede na ključ.';

  @override
  String get repeater_cliHelpSensorSet =>
      'Ustvari prilagojeno nastavitev za senzor.';

  @override
  String get repeater_cliHelpSensorList =>
      'Navede vse nastavitve senzorjev po meri, razdeljene na strani od izbirnega začetnega indeksa.';

  @override
  String get repeater_cliHelpRegionDefault =>
      'Prikaže trenutno privzeto območje.';

  @override
  String get repeater_cliHelpRegionDefaultSet =>
      'Določi privzeto območje. Za izbris uporabite \"<null>\".';

  @override
  String get repeater_cliHelpRegionListAllowed =>
      'Navede regije, ki dovoljujejo flood promet.';

  @override
  String get repeater_cliHelpRegionListDenied =>
      'Navede regije, ki zavračajo flood promet.';

  @override
  String get repeater_cliHelpStatsPackets =>
      '(Samo za serijske povezave) Prikazuje statistiko na nivoju paketov.';

  @override
  String get repeater_cliHelpStatsRadio =>
      '(Samo prek serijske povezave) Prikazuje statistične podatke o radiju.';

  @override
  String get repeater_cliHelpStatsCore =>
      '(Samo prek serijske povezave) Prikazuje statistiko jedra vdelane programske opreme.';

  @override
  String get telemetry_receivedData => 'Prejeti telemetrični podatki';

  @override
  String get telemetry_requestTimeout => 'Zahteva za telemetrijo je potekla.';

  @override
  String telemetry_errorLoading(String error) {
    return 'Napaka pri nalaganju telemetrije: $error';
  }

  @override
  String get telemetry_noData => 'Niso na voljo podatki o telemetriji.';

  @override
  String telemetry_channelTitle(int channel) {
    return 'Kanal $channel';
  }

  @override
  String get telemetry_batteryLabel => 'Baterija';

  @override
  String get telemetry_voltageLabel => 'Napetost';

  @override
  String get telemetry_mcuTemperatureLabel => 'MCU Temperatura';

  @override
  String get telemetry_temperatureLabel => 'Temperatura';

  @override
  String get telemetry_currentLabel => 'Tok';

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
  String get telemetry_digitalInputLabel => 'Digitalni vhod';

  @override
  String get telemetry_digitalOutputLabel => 'Digitalni izhod';

  @override
  String get telemetry_analogInputLabel => 'Analogni vhod';

  @override
  String get telemetry_analogOutputLabel => 'Analogni izhod';

  @override
  String get telemetry_genericLabel => 'Splošni senzor';

  @override
  String get telemetry_luminosityLabel => 'Osvetljenost';

  @override
  String get telemetry_presenceLabel => 'Prisotnost';

  @override
  String get telemetry_humidityLabel => 'Vlažnost';

  @override
  String get telemetry_accelerometerLabel => 'Merilnik pospeška';

  @override
  String get telemetry_pressureLabel => 'Tlak';

  @override
  String get telemetry_altitudeLabel => 'Nadmorska višina';

  @override
  String get telemetry_frequencyLabel => 'Frekvenca';

  @override
  String get telemetry_percentageLabel => 'Odstotek';

  @override
  String get telemetry_concentrationLabel => 'Koncentracija';

  @override
  String get telemetry_powerLabel => 'Moč';

  @override
  String get telemetry_distanceLabel => 'Razdalja';

  @override
  String get telemetry_energyLabel => 'Energija';

  @override
  String get telemetry_directionLabel => 'Smer';

  @override
  String get telemetry_timeLabel => 'Čas';

  @override
  String get telemetry_gyrometerLabel => 'Žiroskop';

  @override
  String get telemetry_colourLabel => 'Barva';

  @override
  String get telemetry_gpsLabel => 'GPS';

  @override
  String get telemetry_switchLabel => 'Stikalo';

  @override
  String get telemetry_polylineLabel => 'Polilinija';

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
  String get telemetry_autoFetchQuantity => 'Število zahtev';

  @override
  String get telemetry_error => 'Podatkov ni bilo mogoče pridobiti';

  @override
  String get neighbors_receivedData => 'Prejeti podatki o sosedih';

  @override
  String get neighbors_requestTimedOut => 'Zahteva za sosede je potekla.';

  @override
  String neighbors_errorLoading(String error) {
    return 'Napaka pri nalaganju sosedov: $error';
  }

  @override
  String get neighbors_repeatersNeighbors => 'Sosedje ponavljalnika';

  @override
  String get neighbors_noData => 'Niso na voljo podatki o sosedih.';

  @override
  String neighbors_unknownContact(String pubkey) {
    return 'Nepoznano $pubkey';
  }

  @override
  String neighbors_heardAgo(String time) {
    return 'Slišan: pred $time';
  }

  @override
  String get channelPath_title => 'Pot paketa';

  @override
  String get channelPath_viewMap => 'Prikaži zemljevid';

  @override
  String get channelPath_otherObservedPaths => 'Druge opazovane poti';

  @override
  String get channelPath_repeaterHops => 'Skoki prek ponoviteljev';

  @override
  String get channelPath_repeaterHopsHighTimeout =>
      'Podaljšana časovna omejitev sledenja poti (10 s × skoki)';

  @override
  String get channelPath_noHopDetails =>
      'Podrobnosti o skokih za ta paket niso na voljo.';

  @override
  String get channelPath_messageDetails => 'Podrobnosti sporočila';

  @override
  String get channelPath_senderLabel => 'Pošiljatelj';

  @override
  String get channelPath_timeLabel => 'Čas (prejema)';

  @override
  String get channelPath_repeatsLabel => 'Ponovitve';

  @override
  String channelPath_pathLabel(int index) {
    return 'Pot $index';
  }

  @override
  String get channelPath_observedLabel => 'Opazovani';

  @override
  String channelPath_observedPathTitle(int index, String hops) {
    return 'Opazovana pot $index • $hops';
  }

  @override
  String get channelPath_noLocationData => 'Ni podatkov o lokaciji';

  @override
  String channelPath_timeWithDate(int day, int month, String time) {
    return '$day/$month $time';
  }

  @override
  String channelPath_timeOnly(String time) {
    return '$time';
  }

  @override
  String get channelPath_unknownPath => 'Neznano';

  @override
  String get channelPath_floodPath => 'Flood';

  @override
  String get channelPath_directPath => 'Neposredni';

  @override
  String channelPath_observedZeroOf(int total) {
    return '0 od $total skokov';
  }

  @override
  String channelPath_observedSomeOf(int observed, int total) {
    return '$observed od $total skokov';
  }

  @override
  String get channelPath_mapTitle => 'Potni zemljevid';

  @override
  String get channelPath_noRepeaterLocations =>
      'Za to pot ni na voljo nobenih lokacij ponoviteljev.';

  @override
  String channelPath_primaryPath(int index) {
    return 'Pot $index (Glavna)';
  }

  @override
  String get channelPath_pathLabelTitle => 'Pot';

  @override
  String get channelPath_observedPathHeader => 'Opazovana pot';

  @override
  String channelPath_selectedPathLabel(String label, String prefixes) {
    return '$label • $prefixes';
  }

  @override
  String get channelPath_noHopDetailsAvailable =>
      'Za ta paket ni na voljo podrobnosti o skokih.';

  @override
  String get channelPath_unknownRepeater => 'Neznani ponovitelj';

  @override
  String get channelPath_outgoingSentByRadioAt =>
      'Čakanje na prenos prek radia, s';

  @override
  String get community_title => 'Skupnost';

  @override
  String get community_create => 'Ustvari skupnost';

  @override
  String get community_createDesc =>
      'Ustvari novo skupnost in jo deli preko QR kode.';

  @override
  String get community_join => 'Pridruži se';

  @override
  String get community_joinTitle => 'Pridružite se skupnosti';

  @override
  String community_joinConfirmation(String name) {
    return 'Želiš se pridružiti skupnosti \"$name\"?';
  }

  @override
  String get community_scanQr => 'Skeniraj QR kodo skupnosti';

  @override
  String get community_scanInstructions =>
      'Kamero usmerite v QR kodo skupnosti';

  @override
  String get community_showQr => 'Pokaži QR kodo';

  @override
  String get community_publicChannel => 'Javni kanal skupnosti';

  @override
  String get community_hashtagChannel => 'Skupnostni hashtag';

  @override
  String get community_name => 'Ime skupnosti';

  @override
  String get community_enterName => 'Vnesite ime skupnosti';

  @override
  String community_created(String name) {
    return 'Skupnost \"$name\" je bila ustvarjena';
  }

  @override
  String community_joined(String name) {
    return 'Pridružili ste se skupnosti \"$name\"';
  }

  @override
  String get community_qrTitle => 'Delite skupnost';

  @override
  String community_qrInstructions(String name) {
    return 'Skenirajte to QR kodo, da se pridružite skupnosti \"$name\"';
  }

  @override
  String get community_hashtagPrivacyHint =>
      'Hashtag kanali skupnosti so dostopni samo članom skupnosti';

  @override
  String get community_invalidQrCode => 'Neveljavna QR koda skupnosti';

  @override
  String get community_alreadyMember => 'Že član';

  @override
  String community_alreadyMemberMessage(String name) {
    return 'Že ste član skupnosti \"$name\".';
  }

  @override
  String get community_addPublicChannel => 'Dodaj javni kanal skupnosti';

  @override
  String get community_addPublicChannelHint =>
      'Samodejno dodaj javni kanal za to skupnost.';

  @override
  String get community_noCommunities =>
      'Niste se še pridružili nobeni skupnosti';

  @override
  String get community_scanOrCreate =>
      'Skeniraj QR kodo ali ustvari skupnost za začetek.';

  @override
  String get community_manageCommunities => 'Upravljanje skupnosti';

  @override
  String get community_delete => 'Zapusti skupnost';

  @override
  String community_deleteConfirm(String name) {
    return 'Zapusti \"$name\"?';
  }

  @override
  String community_deleteChannelsWarning(int count) {
    return 'To bo izbrisalo tudi $count kanal/kanalov in njihova sporočila.';
  }

  @override
  String community_deleted(String name) {
    return 'Zapustili ste skupnost \"$name\"';
  }

  @override
  String get community_regenerateSecret => 'Ponovno ustvari skrivnost';

  @override
  String community_regenerateSecretConfirm(String name) {
    return 'Ponovno ustvarim skrivni ključ za \"$name\"? Vsi člani bodo morali skenirati novo QR kodo, da bodo lahko nadaljevali komunikacijo.';
  }

  @override
  String get community_regenerate => 'Ponovno ustvari';

  @override
  String community_secretRegenerated(String name) {
    return 'Skrivnost za \"$name\" ponovno ustvarjena';
  }

  @override
  String get community_updateSecret => 'Ažuriraj ključ';

  @override
  String community_secretUpdated(String name) {
    return 'Skrivnost za \"$name\" posodobljena';
  }

  @override
  String community_scanToUpdateSecret(String name) {
    return 'Skeniraj novo QR kodo za posodabljanje ključa za $name';
  }

  @override
  String get community_addHashtagChannel => 'Dodaj hashtag kanal';

  @override
  String get community_addHashtagChannelDesc =>
      'Dodajte hashtag kanal za to skupnost.';

  @override
  String get community_selectCommunity => 'Izberi skupnost';

  @override
  String get community_regularHashtag => 'Navaden hashtag';

  @override
  String get community_regularHashtagDesc =>
      'Javni hashtag (pridruži se lahko kdorkoli)';

  @override
  String get community_communityHashtag => 'Skupnostni hashtag';

  @override
  String get community_communityHashtagDesc => 'Zasebno za člane skupnosti';

  @override
  String community_forCommunity(String name) {
    return 'Za $name';
  }

  @override
  String get listFilter_tooltip => 'Filtriranje in razvrščanje';

  @override
  String get listFilter_sortBy => 'Sortiraj po';

  @override
  String get listFilter_latestMessages => 'Najnovejše sporočilo';

  @override
  String get listFilter_heardRecently => 'Nedavno slišan';

  @override
  String get listFilter_az => 'A do Z';

  @override
  String get listFilter_filters => 'Filtri';

  @override
  String get listFilter_all => 'Vse';

  @override
  String get listFilter_favorites => 'Priljubljene';

  @override
  String get listFilter_addToFavorites => 'Dodaj v priljubljene';

  @override
  String get listFilter_removeFromFavorites => 'Odstrani iz priljubljenih';

  @override
  String get listFilter_removeFromWardrive => 'Prezri v Wardrive';

  @override
  String get listFilter_returnToWardrive => 'Upoštevaj v Wardrive';

  @override
  String get listFilter_users => 'Uporabniki';

  @override
  String get listFilter_repeaters => 'Ponovitelji';

  @override
  String get listFilter_roomServers => 'Strežniki sob';

  @override
  String get listFilter_unreadOnly => 'Samo neprebrano';

  @override
  String get listFilter_newGroup => 'Nova skupina';

  @override
  String get pathTrace_you => 'Ti';

  @override
  String get pathTrace_failed => 'Sledenje poti ni uspelo.';

  @override
  String get pathTrace_notAvailable => 'Sledenje poti ni na voljo.';

  @override
  String get pathTrace_refreshTooltip => 'Osveži sledenje poti.';

  @override
  String get pathTrace_hopConfirmedNoDirectEchoTooltip =>
      'Skok potrjen, odmev ni bil slišan neposredno';

  @override
  String get pathTrace_someHopsNoLocation =>
      'Enemu ali več skokom manjka lokacija!';

  @override
  String get pathTrace_clearTooltip => 'Počisti pot';

  @override
  String get losSelectStartEnd => 'Izberite začetno in končno vozlišče za LOS.';

  @override
  String losRunFailed(String error) {
    return 'Preverjanje linije vida ni uspelo: $error';
  }

  @override
  String get losClearAllPoints => 'Počisti vse točke';

  @override
  String get losRunToViewElevationProfile =>
      'Zaženite LOS za ogled višinskega profila';

  @override
  String get losMenuTitle => 'LOS meni';

  @override
  String get losMenuSubtitle =>
      'Tapnite vozlišča ali dolgo pritisnite na zemljevid za točke po meri';

  @override
  String get losShowDisplayNodes => 'Pokaži prikazna vozlišča';

  @override
  String get losCustomPoints => 'Točke po meri';

  @override
  String losCustomPointLabel(int index) {
    return 'Po meri $index';
  }

  @override
  String get losPointA => 'Točka A';

  @override
  String get losPointB => 'Točka B';

  @override
  String losAntennaA(String value, String unit) {
    return 'Antena A: $value $unit';
  }

  @override
  String losAntennaB(String value, String unit) {
    return 'Antena B: $value $unit';
  }

  @override
  String get losRun => 'Zaženi LOS';

  @override
  String get losNoElevationData => 'Ni podatkov o višini';

  @override
  String losProfileClear(
    String distance,
    String distanceUnit,
    String clearance,
    String heightUnit,
  ) {
    return '$distance $distanceUnit, čisti LOS, najmanjša razdalja $clearance $heightUnit';
  }

  @override
  String losProfileBlocked(
    String distance,
    String distanceUnit,
    String obstruction,
    String heightUnit,
  ) {
    return '$distance $distanceUnit, blokirano zaradi $obstruction $heightUnit';
  }

  @override
  String get losStatusChecking => 'LOS: preverjam ...';

  @override
  String get losStatusNoData => 'LOS: ni podatkov';

  @override
  String losStatusSummary(int clear, int total, int blocked, int unknown) {
    return 'LOS: $clear/$total prosto, $blocked blokirano, $unknown neznano';
  }

  @override
  String get losErrorElevationUnavailable =>
      'Podatki o nadmorski višini niso na voljo za enega ali več vzorcev.';

  @override
  String get losErrorInvalidInput =>
      'Neveljavni podatki o točkah/višini za izračun LOS.';

  @override
  String get losRenameCustomPoint => 'Preimenujte točko po meri';

  @override
  String get losPointName => 'Ime točke';

  @override
  String get losShowPanelTooltip => 'Pokaži ploščo LOS';

  @override
  String get losHidePanelTooltip => 'Skrij ploščo LOS';

  @override
  String get losElevationAttribution =>
      'Podatki o višini: Open-Meteo (CC BY 4.0)';

  @override
  String get losLegendRadioHorizon => 'Radijski horizont';

  @override
  String get losLegendLosBeam => 'Linija vidnosti';

  @override
  String get losLegendTerrain => 'Teren';

  @override
  String get losBlockedSpotsTitle => 'Blokirana mesta';

  @override
  String get losBlockedSpotsHint =>
      'Dotaknite se blokirane točke, da jo označite na zemljevidu.';

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
  String get losSelectedObstructionTitle => 'Izbrana ovira';

  @override
  String losSelectedObstructionDetails(
    String obstruction,
    String heightUnit,
    String distanceFromA,
    String distanceUnit,
    String distanceFromB,
  ) {
    return 'Blokirano zaradi $obstruction $heightUnit, $distanceFromA od A in $distanceFromB od B ($distanceUnit).';
  }

  @override
  String get losFrequencyLabel => 'Frekvenca';

  @override
  String get losFrequencyInfoTooltip => 'Prikaži podrobnosti izračuna';

  @override
  String get losFrequencyDialogTitle => 'Izračun radijskega horizonta';

  @override
  String losFrequencyDialogDescription(
    double baselineK,
    double baselineFreq,
    double frequencyMHz,
    double kFactor,
  ) {
    return 'Začenši od k=$baselineK pri $baselineFreq MHz, izračun prilagodi k-faktor na $kFactor za trenutni pas $frequencyMHz MHz, ki določa ukrivljeno zgornjo mejo radijskega horizonta.';
  }

  @override
  String get contacts_pathTrace => 'Sledenje poti';

  @override
  String get contacts_ping => 'Pingaj';

  @override
  String get contacts_repeaterPathTrace => 'Sledi poti do ponavljalnika';

  @override
  String get contacts_repeaterPing => 'Pinguj ponavljalnik';

  @override
  String get contacts_roomPathTrace => 'Sledenje poti do strežnika sobe';

  @override
  String get contacts_roomPing => 'Ping strežnik sobe';

  @override
  String get contacts_chatTraceRoute => 'Sledenje poti';

  @override
  String contacts_pathTraceTo(String name) {
    return 'Sledi poti do $name';
  }

  @override
  String get contacts_clipboardEmpty => 'Odložišče je prazno.';

  @override
  String get contacts_invalidAdvertFormat => 'Neveljavni kontaktni podatki';

  @override
  String get contacts_contactImported => 'Kontakt je bil uvožen.';

  @override
  String get contacts_contactImportFailed => 'Kontakt ni bil uspešno uvožen.';

  @override
  String get contacts_zeroHopAdvert => 'Zero-hop advert';

  @override
  String get contacts_floodAdvert => 'Flood advert';

  @override
  String get contacts_copyAdvertToClipboard =>
      'Kopiraj lastno povezavo «meshcore://»';

  @override
  String get contacts_addContactFromClipboard =>
      'Dodaj stik iz povezave «meshcore://» v odložišču';

  @override
  String get contacts_ShareContact => 'Kopiraj stik v Odložišče';

  @override
  String get contacts_ShareContactZeroHop => 'Deli stik prek adverta';

  @override
  String get contacts_zeroHopContactAdvertSent => 'Stik poslan prek adverta.';

  @override
  String get contacts_zeroHopContactAdvertFailed =>
      'Pošiljanje kontakta ni uspelo.';

  @override
  String get contacts_contactAdvertCopied =>
      'Advert je bil kopiran v odložišče.';

  @override
  String get contacts_contactAdvertCopyFailed =>
      'Kopiranje adverta v odložišče je spodletelo.';

  @override
  String get notification_activityTitle => 'Aktivnost MeshCore';

  @override
  String notification_messagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sporočil',
      few: 'sporočila',
      two: 'sporočili',
      one: 'sporočilo',
    );
    return '$count $_temp0';
  }

  @override
  String notification_channelMessagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sporočil kanala',
      few: 'sporočila kanala',
      two: 'sporočili kanala',
      one: 'sporočilo kanala',
    );
    return '$count $_temp0';
  }

  @override
  String notification_newNodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'novih vozlišč',
      few: 'nova vozlišča',
      two: 'novi vozlišči',
      one: 'novo vozlišče',
    );
    return '$count $_temp0';
  }

  @override
  String notification_newTypeDiscovered(String contactType) {
    return 'Odkrito novo vozlišče: $contactType';
  }

  @override
  String get notification_receivedNewMessage => 'Prejeto novo sporočilo';

  @override
  String get settings_gpxExportRepeaters =>
      'Izvoz ponoviteljev / strežnika sobe v GPX';

  @override
  String get settings_gpxExportRepeatersSubtitle =>
      'Izvozi ponovitelje / strežnike sob z lokacijo v datoteko GPX.';

  @override
  String get settings_gpxExportContacts => 'Izvoz spremljevalcev v GPX';

  @override
  String get settings_gpxExportContactsSubtitle =>
      'Izvozi spremljevalce z lokacijo v datoteko GPX.';

  @override
  String get settings_gpxExportAll => 'Izvozi vse kontakte v GPX';

  @override
  String get settings_gpxExportAllSubtitle =>
      'Izvozi vse kontakte z lokacijo v datoteko GPX.';

  @override
  String get settings_gpxExportSuccess =>
      'Datoteka GPX je bila uspešno izvožena.';

  @override
  String get settings_gpxExportNoContacts => 'Ni stikov za izvoz.';

  @override
  String get settings_gpxExportNotAvailable =>
      'Ni podprto na vaši napravi/operacijskem sistemu';

  @override
  String get settings_gpxExportError => 'Pri izvozu je prišlo do napake.';

  @override
  String get settings_gpxExportRepeatersRoom =>
      'Lokacije ponoviteljev in strežnikov sob';

  @override
  String get settings_gpxExportChat => 'Lokacije spremljevalcev';

  @override
  String get settings_gpxExportAllContacts => 'Lokacije vseh stikov';

  @override
  String get settings_gpxExportShareText =>
      'Podatki kart izvoženi iz meshcore-open';

  @override
  String get settings_gpxExportShareSubject =>
      'meshcore-open izvoz podatkov GPX karte';

  @override
  String get snrIndicator_nearByRepeaters => 'Bližnji ponovitelji';

  @override
  String get snrIndicator_lastSeen => 'Zadnjič videno';

  @override
  String get contactsSettings_title => 'Nastavitve stikov';

  @override
  String get contactsSettings_autoAddTitle => 'Avtomatsko odkrivanje';

  @override
  String get contactsSettings_otherTitle => 'Druge nastavitve v zvezi s stiki';

  @override
  String get contactsSettings_autoAddUsersTitle =>
      'Avtomatsko dodaj uporabnike';

  @override
  String get contactsSettings_autoAddUsersSubtitle =>
      'Dovoli spremljevalcu, da samodejno doda odkrite uporabnike.';

  @override
  String get contactsSettings_autoAddRepeatersTitle =>
      'Avtomatsko dodaj ponovitelje';

  @override
  String get contactsSettings_autoAddRepeatersSubtitle =>
      'Dovoli spremljevalcu, da samodejno doda odkrite ponovitelje.';

  @override
  String get contactsSettings_autoAddRoomServersTitle =>
      'Avtomatsko dodaj strežnike sob';

  @override
  String get contactsSettings_autoAddRoomServersSubtitle =>
      'Dovoli spremljevalcu, da samodejno doda odkrite strežnike sob.';

  @override
  String get contactsSettings_autoAddSensorsTitle =>
      'Avtomatsko dodaj senzorje';

  @override
  String get contactsSettings_autoAddSensorsSubtitle =>
      'Dovoli spremljevalcu, da samodejno doda odkrite senzorje.';

  @override
  String get contactsSettings_overwriteOldestTitle => 'Prepiši najstarejše';

  @override
  String get contactsSettings_overwriteOldestSubtitle =>
      'Ko je seznam stikov poln, bo zamenjan najstarejši stik, ki ni med priljubljenimi.';

  @override
  String get discoveredContacts_Title => 'Dodaj odkrite stike';

  @override
  String get discoveredContacts_noMatching => 'Ni ujemajočih stikov';

  @override
  String get discoveredContacts_searchHint => 'Išči odkrite stike';

  @override
  String get discoveredContacts_contactAdded => 'Kontakt dodan';

  @override
  String get discoveredContacts_addContact => 'Dodaj stik';

  @override
  String get discoveredContacts_copyContact => 'Kopiraj stik v odložišče';

  @override
  String get discoveredContacts_deleteContact => 'Izbriši stik';

  @override
  String get discoveredContacts_deleteContactAll =>
      'Izbriši vse odkrite kontakte';

  @override
  String get discoveredContacts_discoverDevices => 'Odkrij naprave';

  @override
  String get discoveredContacts_requestName => 'Zahtevaj ime';

  @override
  String get discoveredContacts_nameRequestFailed =>
      'Imena ponovitelja ni bilo mogoče zahtevati';

  @override
  String discoveredContacts_discoveryFailed(String error) {
    return 'Naprav ni bilo mogoče odkriti: $error';
  }

  @override
  String get discoveredContacts_deleteContactAllContent =>
      'Ste prepričani, da želite izbrisati vse odkrite kontakte?';

  @override
  String get chat_sendCooldown =>
      'Prosimo, počakajte trenutek, preden pošljete ponovno.';

  @override
  String get appSettings_jumpToOldestUnread =>
      'Skoči na najstarejše neprebrano sporočilo';

  @override
  String get appSettings_jumpToOldestUnreadSubtitle =>
      'Ko odpirate klepet z neprebranimi sporočili, se premaknite na prvo neprebrano sporočilo, namesto najnovejšega.';

  @override
  String get appSettings_languageHu => 'Madžarščina';

  @override
  String get appSettings_languageJa => 'Japonščina';

  @override
  String get appSettings_languageKo => 'Korejščina';

  @override
  String get radioStats_tooltip => 'Statistike za radio in mrežo';

  @override
  String get radioStats_screenTitle => 'Radijske statistike';

  @override
  String get radioStats_notConnected =>
      'Povežite se z napravo, da si ogledate statistiko o radiju.';

  @override
  String get radioStats_firmwareTooOld =>
      'Statistika radia zahteva vdelano programsko opremo companion v8 ali novejšo.';

  @override
  String get radioStats_waiting => 'Čakam na podatke…';

  @override
  String radioStats_noiseFloor(int noiseDbm) {
    return 'Raven šuma: $noiseDbm dBm';
  }

  @override
  String radioStats_lastRssi(int rssiDbm) {
    return 'Zadnji RSSI: $rssiDbm dBm';
  }

  @override
  String radioStats_lastSnr(String snr) {
    return 'Zadnji SNR: $snr dB';
  }

  @override
  String radioStats_txAir(int seconds) {
    return 'Čas na TX (skupno): $seconds s';
  }

  @override
  String radioStats_rxAir(int seconds) {
    return 'Čas, namenjen RX-ju (skupno): $seconds s';
  }

  @override
  String get radioStats_chartCaption => 'Raven šuma (dBm) v zadnjih vzorcih.';

  @override
  String radioStats_stripNoise(int noiseDbm) {
    return 'Raven šuma: $noiseDbm dBm';
  }

  @override
  String get radioStats_stripWaiting => 'Prejemanje statistike o radiju…';

  @override
  String get radioStats_settingsTile => 'Radijske statistike';

  @override
  String get radioStats_settingsSubtitle =>
      'Raven šuma, RSSI, SNR in čas oddajanja';

  @override
  String get translation_title => 'Prevod';

  @override
  String get translation_enableTitle => 'Omogočite prevod';

  @override
  String get translation_enableSubtitle =>
      'Prevajaj dohodna sporočila in omogoči prevajanje pred pošiljanjem.';

  @override
  String get translation_composerTitle => 'Prevedi pred pošiljanjem';

  @override
  String get translation_composerSubtitle =>
      'Določa privzeto stanje ikone za prevod v urejevalniku sporočil.';

  @override
  String get translation_autoIncomingTitle => 'Samodejno prevajaj sporočila';

  @override
  String get translation_autoIncomingSubtitle =>
      'Samodejno prevaja sporočila za obvestila ter za klepete ali kanale.';

  @override
  String get translation_translateMessage => 'Prevedi sporočilo';

  @override
  String get translation_targetLanguage => 'Ciljni jezik';

  @override
  String get translation_useAppLanguage => 'Uporabite jezik aplikacije';

  @override
  String get translation_downloadedModelLabel => 'Naložen model';

  @override
  String get translation_presetModelLabel =>
      'Prednastavljeni model Hugging Face';

  @override
  String get translation_manualUrlLabel => 'URL modela (ročni vnos)';

  @override
  String get translation_downloadModel => 'Prenesite model';

  @override
  String get translation_downloading => 'Prenašanje...';

  @override
  String get translation_working => 'V teku...';

  @override
  String get translation_stop => 'Ustavi';

  @override
  String get translation_mergingChunks =>
      'Združevanje prenesenih delov v končno datoteko...';

  @override
  String get translation_downloadedModels => 'Naloženi modeli';

  @override
  String get translation_deleteModel => 'Izbriši model';

  @override
  String get translation_modelDownloaded =>
      'Model za prevajanje je bil naložen.';

  @override
  String get translation_downloadStopped => 'Prenos je bil prekinjen.';

  @override
  String translation_downloadFailed(String error) {
    return 'Prenos ni uspel: $error';
  }

  @override
  String get translation_enterUrlFirst => 'Najprej vnesite URL modela.';

  @override
  String get scanner_linuxPairingShowPin => 'Prikaži PIN';

  @override
  String get scanner_linuxPairingHidePin => 'Skrij PIN';

  @override
  String get scanner_linuxPairingPinTitle => 'Bluetooth PIN za seznanjanje';

  @override
  String scanner_linuxPairingPinPrompt(String deviceName) {
    return 'Vnesite PIN za $deviceName (pustite prazno, če ga ni).';
  }

  @override
  String get translation_messageTranslation => 'Prevod sporočila';

  @override
  String get translation_translateBeforeSending => 'Prevedi pred pošiljanjem';

  @override
  String get translation_composerEnabledHint =>
      'Vsebina sporočil bo prevedena, preden jih pošljemo.';

  @override
  String get translation_composerDisabledHint =>
      'Pošljite sporočila v originalnem tipkanem jeziku.';

  @override
  String translation_translateTo(String language) {
    return 'Prevedi v $language';
  }

  @override
  String get translation_translationOptions => 'Možnosti prevoda';

  @override
  String get translation_systemLanguage => 'Jezik sistema';

  @override
  String get background_serviceTitle => 'MeshCore se izvaja';

  @override
  String get background_serviceText => 'Ohranjanje povezave z vozliščem';

  @override
  String appSettings_translationModelDeleted(String name) {
    return '$name izbrisano';
  }

  @override
  String appSettings_translationModelDeleteFailed(String error) {
    return 'Brisanje ni uspelo: $error';
  }

  @override
  String channels_channelUpdateFailed(String error) {
    return 'Kanala ni bilo mogoče posodobiti: $error';
  }

  @override
  String get channels_mcmpCompression => 'Stiskanje MCMP';

  @override
  String get channels_mcmpCompressionDescription =>
      'Uporaba modela mesh-compressor';

  @override
  String get channels_copyPath => 'Kopiraj pot sporočila';

  @override
  String get channels_copyPathExtended => 'Kopiraj pot sporočila (razširjeno)';

  @override
  String get channels_copiedPath => 'Pot sporočila je kopirana';

  @override
  String get channels_copyPathFailed =>
      'Poti sporočila ni bilo mogoče kopirati';

  @override
  String get settings_copyMsgPathTitle => 'Nastavitev kopiranja poti sporočila';

  @override
  String get settings_copyMsgPathDscr =>
      'Uredi predlogo za sestavljanje informacij o poti sporočila iz kanala';

  @override
  String get settings_copyMsgPathEditTemplateTitle => 'Urejanje predloge';

  @override
  String get settings_copyMsgPathEditTemplateDscr =>
      'Uporabite nadomestne predloge:\n%hopInd% - zaporedje skoka\n%hopKey% - ključ skoka\n%hopName% - ime skoka\n%collisionMarker% - oznaka trka repetitorjev\n%div% - ločilo (pri zadnjem skoku se izpusti)\n%hops% - število skokov\n\\n - prelom vrstice';

  @override
  String get settings_copyMsgPathEditFinalTitle => 'Končno sporočilo';

  @override
  String get settings_copyMsgPathEditFinalDscr =>
      'Razpoložljive predloge:\n%senderName% - ime pošiljatelja\n%path% - sestavljena pot\n%hops% - število skokov\n\\n - prelom vrstice';

  @override
  String get settings_channelsSendAsBinary =>
      'Pošiljaj razširjene formate binarno (kanali)';

  @override
  String get settings_dmSendAsBinary =>
      'Pošiljaj razširjene formate binarno (zasebna sporočila)';

  @override
  String get contact_typeChat => 'Klepet';

  @override
  String get contact_typeRepeater => 'Ponovitelj';

  @override
  String get contact_typeRoom => 'Soba';

  @override
  String get contact_typeSensor => 'Senzor';

  @override
  String get contact_typeUnknown => 'Neznano';

  @override
  String get map_zoomIn => 'Povečaj';

  @override
  String get map_zoomOut => 'Pomanjšaj';

  @override
  String get map_centerMap => 'Centriraj zemljevid';

  @override
  String get chrome_bluetoothRequiresChromium =>
      'Web Bluetooth zahteva brskalnik Chromium.';

  @override
  String channels_communityShortId(String id) {
    return 'ID: $id...';
  }

  @override
  String get pathTrace_legendGpsConfirmed => 'Potrjeno z GPS';

  @override
  String get pathTrace_legendInferred => 'Izpeljana lokacija';

  @override
  String get pathMap_viewSingle => 'Posamično';

  @override
  String get pathMap_viewCombined => 'Skupno';

  @override
  String get pathMap_play => 'Predvajaj';

  @override
  String get pathMap_pause => 'Premor';

  @override
  String get pathMap_replay => 'Ponovno predvajaj';

  @override
  String get pathMap_stepBack => 'Prejšnji skok';

  @override
  String get pathMap_stepForward => 'Naslednji skok';

  @override
  String get pathMap_animationOn => 'Prikaži animacijo paketa';

  @override
  String get pathMap_animationOff => 'Skrij animacijo paketa';

  @override
  String pathMap_hopOf(int current, int total) {
    return 'Skok $current od $total';
  }

  @override
  String pathMap_observedPaths(int count) {
    return 'Opazovane poti: $count';
  }

  @override
  String get pathMap_primary => 'Primarna';

  @override
  String pathMap_alternate(int index) {
    return 'Alternativa $index';
  }

  @override
  String pathMap_hopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count skokov',
      few: '$count skoki',
      two: '$count skoka',
      one: '$count skok',
    );
    return '$_temp0';
  }

  @override
  String pathMap_gpsCount(int confirmed, int total) {
    return '$confirmed/$total GPS';
  }

  @override
  String get pathMap_legendShared => 'Deljen segment';

  @override
  String get pathMap_legendEstimated => 'Ocenjen segment';

  @override
  String pathMap_sharedNodeCount(int count) {
    return 'Uporablja ga $count poti';
  }

  @override
  String pathMap_partialAnimation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count skokov nima lokacije — prikazana pot je delna',
      few: '$count skoki nimajo lokacije — prikazana pot je delna',
      two: '$count skoka nimata lokacije — prikazana pot je delna',
      one: '$count skok nima lokacije — prikazana pot je delna',
    );
    return '$_temp0';
  }

  @override
  String get pathMap_showAllPaths => 'Pokaži vse';

  @override
  String get pathMap_hidePath => 'Skrij pot';

  @override
  String get pathMap_showPath => 'Pokaži pot';

  @override
  String get pathMap_collapsePanel => 'Strni ploščo';

  @override
  String get pathMap_expandPanel => 'Razširi ploščo';

  @override
  String get pathMap_noLocation => 'Brez lokacije';

  @override
  String get pathMap_followPacket => 'Zakleni pogled na paket';

  @override
  String get pathMap_unfollowPacket => 'Odkleni pogled od paketa';

  @override
  String get chat_canvas => 'Platno MCOimg';

  @override
  String get chat_canvasV4Title => 'Vektorsko platno MCOimg v4';

  @override
  String get chat_canvasV4SetupTitle => 'Novo vektorsko platno';

  @override
  String get chat_canvasV4Grid => 'Koordinatna mreža';

  @override
  String get chat_canvasV4GridDescription =>
      'Manjša mreža zmanjša payload, večja poveča natančnost postavitve likov.';

  @override
  String get chat_canvasV4Background => 'Ozadje';

  @override
  String get chat_canvasV4Transparent => 'Prosojno';

  @override
  String get chat_canvasV4Fill => 'Polnilo';

  @override
  String get chat_canvasV4Stroke => 'Obris';

  @override
  String get chat_canvasV4StrokeWidth => 'Debelina obrisa';

  @override
  String get chat_canvasV4Closed => 'Zapri lik';

  @override
  String get chat_canvasV4HideFigure => 'Skrij lik';

  @override
  String get chat_canvasV4ShowFigure => 'Pokaži lik';

  @override
  String get chat_canvasV4MoveUp => 'Premakni navzgor';

  @override
  String get chat_canvasV4MoveDown => 'Premakni navzdol';

  @override
  String get chat_canvasV4Objects => 'Liki';

  @override
  String get chat_canvasV4NoObjects => 'Na platnu še ni likov';

  @override
  String get chat_canvasV4Calculate => 'Izračunaj končno sliko';

  @override
  String get chat_canvasV4Redo => 'Ponovi';

  @override
  String get chat_canvasV4CanvasSettings => 'Nastavitve platna';

  @override
  String get chat_canvasV4InvalidSize => 'Od 1 do 256';

  @override
  String get chat_canvasV4LoadReference => 'Naloži referenčno sliko';

  @override
  String get chat_canvasV4HideReference => 'Skrij referenčno sliko';

  @override
  String get chat_canvasV4ShowReference => 'Pokaži referenčno sliko';

  @override
  String get chat_canvasV4RemoveReference => 'Odstrani referenčno sliko';

  @override
  String get chat_canvasV4ReferenceNotEncoded =>
      'Referenčna slika ni vključena v payload';

  @override
  String get chat_canvasV4PaletteFull => 'Dokument že uporablja 64 barv';

  @override
  String chat_canvasV4Payload(int bytes) {
    return 'Payload: $bytes bajtov';
  }

  @override
  String chat_canvasV4PayloadTooLarge(int bytes) {
    return 'Payload presega razpoložljivo velikost za $bytes bajtov';
  }

  @override
  String get chat_canvasV4ApplyStyle => 'Uporabi slog';

  @override
  String get chat_canvasV4WaveHint => 'Določite začetek, konec in globino vala';

  @override
  String get chat_canvasV4ToolSelect => 'Izberi in premakni';

  @override
  String get chat_canvasV4ToolDot => 'Točka';

  @override
  String get chat_canvasV4ToolPencil => 'Svinčnik';

  @override
  String get chat_canvasV4ToolLine => 'Črta';

  @override
  String get chat_canvasV4ToolPolyline => 'Lomljena črta';

  @override
  String get chat_canvasV4PolylineHint =>
      'Postavljajte oglišča obrisa. Tapnite prvo oglišče ali izberite način zaključka.';

  @override
  String get chat_canvasV4FinishOpen => 'Zaključi odprto';

  @override
  String get chat_canvasV4FinishClosed => 'Zapri';

  @override
  String get chat_canvasV4ToolRect => 'Pravokotnik';

  @override
  String get chat_canvasV4ToolEllipse => 'Elipsa';

  @override
  String get chat_canvasV4ToolCircle => 'Krog';

  @override
  String get chat_canvasV4ToolWave => 'Val';

  @override
  String get chat_canvasCrop => 'Obreži/razširi';

  @override
  String get chat_canvasResize => 'Stisni/raztegni';

  @override
  String get chat_canvasUnlockSize => 'Odkleni velikost platna';

  @override
  String get chat_canvasFormatVer => 'Različica kodeka';

  @override
  String get chat_canvasPalette => 'Paleta';

  @override
  String get chat_canvasPaletteShow => 'Prikaži paleto';

  @override
  String get chat_canvasPaletteMode => 'Profil palete';

  @override
  String get chat_canvasPaletteDynamic => 'Dinamična';

  @override
  String get chat_canvasPaletteDynamicProfile =>
      'Osnovni nabor za dinamično paleto';

  @override
  String get chat_canvasPaletteDynamicUsed => 'Dejansko uporabljene barve';

  @override
  String get chat_canvasPaletteDynamicDscr =>
      'Pozor! Dinamično paleto uporabljajte premišljeno! Namenjena je predvsem slikam s prehodi, da se zgradi manjša paleta in uporabijo barve, ki ne pripadajo isti osnovni paleti. Za orientacijo: manjša osnovna paleta zniža stroške kodiranja informacij o uporabljenih odtenkih, manjše skupno število barv pa zniža stroške vsakega slikovnega elementa na platnu.';

  @override
  String get chat_canvasPaletteAlpha => 'Barva prosojnosti';

  @override
  String get chat_canvasChangeSize => 'Spremeni velikost platna';

  @override
  String get chat_canvasTrim => 'Obreži prazen prostor';

  @override
  String get chat_canvasWidth => 'Širina';

  @override
  String get chat_canvasHeight => 'Višina';

  @override
  String get chat_canvasGridShow => 'Prikaži mrežo';

  @override
  String get chat_canvasRulerShow => 'Prikaži ravnilo';

  @override
  String get chat_canvasGridColor => 'Barva mreže';

  @override
  String get chat_canvasSave => 'Shrani v datoteko';

  @override
  String get chat_canvasLoad => 'Naloži iz datoteke';

  @override
  String get chat_formatBold => 'Krepko';

  @override
  String get chat_formatItalic => 'Ležeče';

  @override
  String get chat_formatUnderline => 'Podčrtano';

  @override
  String get chat_formatStrikethrough => 'Prečrtano';

  @override
  String get chat_formatMono => 'Enakomerna pisava';

  @override
  String get chat_formatColor => 'Barva besedila';

  @override
  String chat_canvasSendPayloadExceed(int count) {
    return 'Pošiljanje ni uspelo — payload je presežen za $count bajtov. Zmanjšajte število podrobnosti ali velikost platna.';
  }

  @override
  String chat_canvasCurrentPayload(int payload) {
    return 'Trenutni payload: $payload';
  }

  @override
  String get chat_canvasActive => 'Prikaži platno';

  @override
  String get chat_canvasShowLockBtn => 'Prikaži gumb za zaklepanje platna';

  @override
  String get chat_canvasSendToEdit => 'Pošlji na platno';

  @override
  String get chat_canvasSendToGallery => 'Shrani v galerijo';

  @override
  String get chat_canvasGalleryShowPNG => 'Prikaži izvirnik (PNG)';

  @override
  String get chat_canvasGalleryShowBIN => 'Prikaži kot Bin';

  @override
  String get chat_canvasGalleryRemove => 'Odstrani';

  @override
  String get chat_canvasGalleryRemoveConfirm =>
      'Ali naj se slika odstrani iz galerije?';

  @override
  String chat_canvasFormatNotSupported(int received, int current) {
    return 'Različica MCOimg: $received, trenutni kodek podpira do $current';
  }

  @override
  String get chat_canvasSaveBinary => 'Shrani v binarno datoteko';

  @override
  String chat_canvasCannotSend(int count) {
    return 'Pošiljanje ni uspelo — payload je presežen za $count bajtov. Uredite sliko in poskusite znova.';
  }

  @override
  String get chat_canvasCompressionLevel => 'Raven stiskanja';

  @override
  String get chat_canvasCompressionLevelNormal => 'Običajna';

  @override
  String get chat_canvasCompressionLevelHigh => 'Visoka';

  @override
  String get chat_canvasCompressionLevelExtreme => 'Ekstremna';

  @override
  String get chat_showHops => 'Prikaži skoke';

  @override
  String get settings_modSettings => 'Nastavitve modifikacije';

  @override
  String get settings_modSettingsSubtitle =>
      'V tem razdelku so zbrane možnosti, ki jih v izvirnem meshcore_open ni';

  @override
  String get settings_modSettingsVisual => 'Videz';

  @override
  String get settings_modSettingsMessaging => 'Sporočila';

  @override
  String get settings_modSettingsMCMP => 'MCMP';

  @override
  String get settings_mcmp_version => 'Različica';

  @override
  String get settings_mcmp_useSign => 'Podpisovanje sporočil';

  @override
  String get settings_mcmp_signed => 'S preverjanjem podpisa';

  @override
  String get settings_mcmp_noSign => 'Brez podpisa';

  @override
  String get settings_mcmp_senderNameCollision =>
      'Ime pošiljatelja ni enolično!';

  @override
  String get chat_mcmpSignatureValid => 'Podpis je veljaven';

  @override
  String get chat_mcmpSignatureInvalid => 'Neveljaven podpis!';

  @override
  String get chat_mcmpSignatureUnverifiable =>
      'Podpisa ni mogoče preveriti — pošiljatelja ni med stiki';

  @override
  String get chat_mcmpSignatureTransport => 'Potrjeno s šifriranjem prenosa';

  @override
  String get chat_mcmpManualRecheckSign => 'Znova preveri podpis';

  @override
  String get chat_mcmpSignatureCheckStatus => 'Preverjanje podpisa';

  @override
  String get chat_mcmpSigningFailed => 'Sporočila ni bilo mogoče podpisati';

  @override
  String get chat_mcmpAnswerTo => 'Odgovor MCMPv3 na';

  @override
  String get chat_mcmpSignedTimestamp => 'Časovni žig MCMP';

  @override
  String chat_mcmpTimestampQueerly(int time) {
    return 'Časovni žig MCMP se od časovnega žiga paketa razlikuje za $time sekund';
  }

  @override
  String chat_mcmpTimestampQueerlyReceived(int time) {
    return 'Podpisani časovni žig MCMP se močno razlikuje od časa prejema, za $time sekund';
  }

  @override
  String get chat_timestampPacket => 'Časovni žig paketa';

  @override
  String get settings_modSettingsMCOimg => 'MCOimg';

  @override
  String get settings_modSettingsVisualShowMCOimgFormat =>
      'MCOimg: prikaži značko različice formata';

  @override
  String get settings_modSettingsVisualShowMCOimgAlgo =>
      'MCOimg: prikaži značko algoritma kodiranja';

  @override
  String get settings_modSettingsVisualShowMCOimgBytes =>
      'MCOimg: prikaži velikost slike (bajti)';

  @override
  String get settings_modSettingsVisualShowMCOimgResolution =>
      'MCOimg: prikaži ločljivost';

  @override
  String get settings_modSettingsMCOimg_showReplacements =>
      'Prikaži izvirnike slik namesto različic za LoRa';

  @override
  String get settings_modSettingsMCOimg_replacementsScale =>
      'Prilagodi velikost izvirnikov v klepetih';

  @override
  String get settings_modSettingsMCOimg_replacementsLottieScale =>
      'Omejitev velikosti nadomestkov lottie';

  @override
  String get settings_modSettingsMCOimg_scaleNearestNeighbor =>
      'Prilagodi velikost z Nearest Neighbor';

  @override
  String get settings_modSettingsMCOimg_replacementsSharp =>
      'Izostri izvirnike v klepetih';

  @override
  String get settings_modSettingsMCOimg_replacementsSharpDscr =>
      'Pozor! Onemogoči animacijo GIF!';

  @override
  String get settings_modSettingsHideChInd => 'Skrij indeks kanala';

  @override
  String get settings_modSettingsHideRadioStats =>
      'Skrij radijsko statistiko v glavi';

  @override
  String get settings_modSettingsSNRindicatorAllRepActivity =>
      'Indikator SNR: odzovi se na vse odgovore repetitorjev, ne le na adverte';

  @override
  String get settings_modSettingsIncomingQuoteAsMentions =>
      'Prikaži citate v dohodnih sporočilih kot omembe';

  @override
  String get settings_modSettingsSimplifiedMentions =>
      'Poenostavljen slog omemb v sporočilih';

  @override
  String get settings_modSettingsSharedMsgHistory =>
      'Skupna zgodovina sporočil';

  @override
  String get settings_modSettingsSharedMsgHistoryDscr =>
      'Združevanje zgodovine sporočil, prejete z različnih naprav; končna zgodovina se hrani samo v aplikaciji';

  @override
  String get settings_modSettingsSharedMsgHistoryDisabled => 'Onemogočeno';

  @override
  String get settings_modSettingsSharedMsgHistoryChannels => 'Samo kanali';

  @override
  String get settings_modSettingsSharedMsgHistoryContacts => 'Samo stiki';

  @override
  String get settings_modSettingsSharedMsgHistoryAll => 'Vsi klepeti';

  @override
  String get settings_modSettingsMessagingShowCompressionRatio =>
      'Prikaži stopnjo stiskanja';

  @override
  String get settings_modSettingsMessagingCompressionRatioWithSendername =>
      'Upoštevaj tudi ime vozlišča';

  @override
  String get settings_modSettingsVisualHideMapZoomControls =>
      'Skrij ploščo za povečavo na zemljevidu';

  @override
  String get settings_modSettingsVisualShowMsgRegion =>
      'Prikaži regijo sporočila';

  @override
  String channels_messageRegion(String region) {
    return 'Regija: $region';
  }

  @override
  String get channels_messageRegionUnknown => 'neznana';

  @override
  String get channels_messageRegionNotMatchesWithKnown => 'ni ujemanja';

  @override
  String get channels_messageRegionEmpty => 'ni nastavljena';

  @override
  String get settings_defaultRegionScope => 'Privzeta regija vozlišča';

  @override
  String get settings_defaultRegionScopeChanged =>
      'Privzeta regija je spremenjena';

  @override
  String get settings_defaultRegionScopeChangeFailed =>
      'Regije ni bilo mogoče spremeniti';

  @override
  String get settings_defaultRegionScopeEmpty => 'Ni nastavljena';

  @override
  String get settings_defaultRegionScopeWaitForSync =>
      'Počakajte na konec sinhronizacije';

  @override
  String get common_reset => 'Ponastavi';

  @override
  String get connection_autoconnect => 'Samodejna povezava';

  @override
  String settings_modSettingsNoRetraInfo(int time) {
    return 'Že $time s ni bilo slišati retransmisij.';
  }

  @override
  String get settings_modSettingsNoRetraHeading =>
      'Označi sporočila kot neposlana, če v toliko sekundah ni slišati retransmisij:';

  @override
  String get settings_modSettingsNoRetraDscr =>
      'Pozor! Zaradi mehanizma v vdelani programski opremi vozlišča sporočila za kanale, večja od ~133 bajtov, fizično ne morejo prejemati potrditev in bodo vedno označena kot neuspešna! To možnost uporabljajte skupaj z omejitvijo payloada v nastavitvah aplikacije!';

  @override
  String get settings_selfTelemetryShow => 'Ogled senzorjev';

  @override
  String get settings_modSettingsVisualChannelsUnreadSorting =>
      'Razvrščanje kanalov po neprebranih sporočilih';

  @override
  String get settings_modSettingsMessagingBackgroundTCP =>
      'Ohrani povezavo TCP v ozadju';

  @override
  String get settings_modSettingsDPIchange => 'Prilagoditev DPI';

  @override
  String get settings_modSettingsDPIchangeToIcons => 'Uporabi za ikone';

  @override
  String get settings_modSettingsMonochromeSenderNames =>
      'Enobarvna imena pošiljateljev';

  @override
  String get chat_MCOimgOpenGallery => 'Odpri galerijo MCOimg';

  @override
  String get chat_additionalActions => 'Meni dejanj';

  @override
  String get mcogallery_common => 'Splošno';

  @override
  String get mcogallery_addPack => 'Dodaj paket';

  @override
  String get mcogallery_removePack => 'Odstrani paket';

  @override
  String mcogallery_removePackConfirm(String name) {
    return 'Potrdite odstranitev paketa «$name»';
  }

  @override
  String get mcogallery_addGroup => 'Dodaj skupino';

  @override
  String get mcogallery_removeGroup => 'Odstrani skupino';

  @override
  String get mcogallery_showLora => 'Prikaži različico za LoRa';

  @override
  String get mcogallery_showPacked => 'Prikaži izboljšano različico';

  @override
  String get chat_sendSelfContact => 'Pošlji svoj stik';

  @override
  String get chat_sendContact => 'Deli stik';

  @override
  String get chat_addContact => 'Dodaj stik';

  @override
  String get chat_sureToReplaceContact =>
      'Stik že obstaja, ali naj se zamenja?';

  @override
  String get contacts_addContactByPubkey => 'Dodaj stik po ključu';

  @override
  String get contacts_addContactByPubkey_contactType => 'Vrsta stika';

  @override
  String get chat_contactIsYou => 'To je vaš lastni stik';

  @override
  String chat_contactType(String contacttype) {
    return 'Vrsta stika: $contacttype';
  }

  @override
  String get chat_contactTypeNode => 'Vozlišče';

  @override
  String get chat_contactTypeRepeater => 'Repetitor';

  @override
  String get chat_contactTypeRoom => 'Strežnik sobe';

  @override
  String get chat_contactTypeSensor => 'Senzor';

  @override
  String get chat_myLocation => 'Pošlji mojo lokacijo';

  @override
  String get chat_locationFromMap => 'Pošlji koordinate z zemljevida';

  @override
  String get settings_modSettingsRoomServer => 'Strežniki sob in stiki';

  @override
  String get settings_modSettingsRoomServerShowNotemptyOnChatscreen =>
      'Prikaži strežnike z zgodovino na istem zaslonu kot kanale';

  @override
  String get settings_modSettingsRoomServerShowNotemptyContactsOnChatscreen =>
      'Prikaži stike z zgodovino na istem zaslonu kot kanale';

  @override
  String get settings_modSettingsRoomServerDisableRoomAndContactsSorting =>
      'Ohrani dosedanje delovanje povleci-in-spusti: sprememba vrstnega reda kanalov spremeni njihov vrstni red na vozlišču, stikov in strežnikov pa ni mogoče razvrščati';

  @override
  String get settings_modSettingsMapAndLocation => 'Zemljevid in lokacija';

  @override
  String get settings_modSettingsAlwaysRequestMapLocation =>
      'Ob odpiranju zemljevida vedno zahtevaj lokacijo';

  @override
  String get settings_modSettingsExactQuote =>
      'Uporabi natančno citiranje za navadna sporočila';

  @override
  String get settings_modSettingsExactQuoteLimit =>
      'Omejitev bajtov za sestavo citata';

  @override
  String get settings_modSettingsExactQuoteLimitDscr =>
      'Privzeta omejitev je 30. Poleg omejitve se citatu doda še 5 bajtov, ki ga oblikujejo za odjemalce brez podpore te funkcije';

  @override
  String get settings_appSettingsCustomChemistry => 'Po meri';

  @override
  String get map_clearDiscoveredContactsCache =>
      'Počisti lokalni predpomnilnik vozlišč';

  @override
  String get map_clearDiscoveredContactsCacheDisclaimer =>
      'Ali res želite počistiti predpomnilnik odkritih stikov? To ne bo vplivalo na stike na samem vozlišču.';

  @override
  String get snrIndicator_v2_nearByRepeaters => 'Dejavnost repetitorjev';

  @override
  String get app_connectionLostReconnect =>
      'Povezava z vozliščem je bila izgubljena, poteka ponovno povezovanje ...';

  @override
  String get app_connectionLostReconnected =>
      'Povezava z vozliščem je obnovljena';

  @override
  String get app_connectionLostBreaked => 'Povezava z vozliščem je prekinjena';

  @override
  String get contacts_batchOperations => 'Množične operacije';

  @override
  String get contacts_batchOperations_notSelected =>
      'Niste izbrali nobenega stika za obdelavo!';

  @override
  String get contacts_batchOperations_removeConfirm =>
      'Ali naj se izbrani stiki odstranijo iz pomnilnika vozlišča?';

  @override
  String get contacts_batchOperations_removeSuccess =>
      'Izbrani stiki so bili odstranjeni';

  @override
  String get contacts_batchOperations_removeFail =>
      'Stikov ni bilo mogoče odstraniti — znova preverite seznam';

  @override
  String get contacts_batchOperations_commonSuccess =>
      'Operacija je bila uspešna';

  @override
  String get contacts_batchOperations_commonFail =>
      'Operacije ni bilo mogoče dokončati';

  @override
  String get contacts_batchOperations_selectFiltered => 'Izberi filtrirane';

  @override
  String get chat_searchMessages => 'Iskanje sporočil';

  @override
  String get chat_searchMessages_placeholder =>
      'Od 3 znakov, brez razlikovanja velikih in malih črk';

  @override
  String get chat_searchMessages_results => 'Rezultati iskanja';

  @override
  String chat_searchMessages_results_found(int count) {
    return 'Najdenih $count sporočil';
  }

  @override
  String chat_searchMessages_results_channel(String name) {
    return 'Kanal $name';
  }

  @override
  String chat_searchMessages_results_room(String name) {
    return 'Soba $name';
  }

  @override
  String chat_searchMessages_results_contact(String name) {
    return 'Pogovor z $name';
  }

  @override
  String get app_offline => 'Brez povezave';

  @override
  String get app_offline_unableToMessage =>
      'V načinu brez povezave ne morete pošiljati sporočil ali izvajati drugih dejanj';

  @override
  String get app_offline_sharedMode => 'Združena zgodovina';

  @override
  String get settings_infoHardware => 'Hardver';

  @override
  String get appSettings_batteryLipoHv => 'LiPo HV (3,0–4,35 V)';

  @override
  String get chat_sendImage => 'Pošlji sliko';

  @override
  String get chat_imagePickFailed => 'Te slike ni bilo mogoče odpreti';

  @override
  String get imageMessages_enableTitle => 'Omogoči slikovna sporočila';

  @override
  String get imageMessages_enableSubtitle =>
      'Pošiljajte slike prek omrežja mesh. Zahteva enkraten prenos modela za slike.';

  @override
  String get imageMessages_modelSectionTitle => 'Model za slike';

  @override
  String get imageMessages_downloadModel => 'Prenesi';

  @override
  String get imageMessages_cancelDownload => 'Prekliči';

  @override
  String get imageMessages_removeModel => 'Odstrani model';

  @override
  String get imageMessages_modelReady => 'Pripravljen';

  @override
  String get imageMessages_modelNotPublished =>
      'Še ni objavljen — ta različica ga ne more prenesti.';

  @override
  String get imageMessages_downloadFailed =>
      'Modela za slike ni bilo mogoče prenesti.';

  @override
  String get imageMessages_autoProcessTitle => 'Samodejno obdelaj slike';

  @override
  String get imageMessages_autoProcessSubtitle =>
      'Vsako sliko rekonstruiraj takoj, ko prispe. Vsakič za približno sekundo porabi okoli 2 GB pomnilnika; pusti izklopljeno, če želiš rekonstrukcijo s tapom.';

  @override
  String get imageSend_title => 'Pošlji sliko';

  @override
  String get imageSend_cropNote =>
      'Spremenjeno na 512 × 512 · razmerje stranic ni ohranjeno';

  @override
  String get imageSend_originalSize => 'Izvirnik';

  @override
  String get imageSend_onAirSize => 'V etru';

  @override
  String get imageSend_quality => 'Kakovost';

  @override
  String get imageSend_qualityStandard => 'Standardna';

  @override
  String get imageSend_qualityHigh => 'Visoka';

  @override
  String get imageSend_packetsLabel => 'Paketi';

  @override
  String get imageSend_airtimeLabel => 'Čas v etru';

  @override
  String get imageSend_sizeLabel => 'Uporabni podatki';

  @override
  String imageSend_packetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'paketov',
      few: 'paketi',
      two: 'paketa',
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
  String get imageSend_radioUnknownTitle => 'Nastavitve radia so neznane';

  @override
  String get imageSend_radioUnknownBody =>
      'Poveži se z napravo, da je mogoče izračunati čas oddajanja.';

  @override
  String get imageSend_longSendTitle => 'Dolgo oddajanje';

  @override
  String imageSend_longSendBody(String duration) {
    return 'To bo zasedlo kanal približno $duration.';
  }

  @override
  String get imageSend_floodNote =>
      'Flood usmerjanje: vsak ponovitelj v dosegu znova odda vsak paket, zato kanal ostane zaseden dlje od tega.';

  @override
  String get imageSend_parityTitle => 'Dodaj obnovitveni paket';

  @override
  String get imageSend_paritySubtitle =>
      'En dodaten paket. Skupinska sporočila niso potrjena, zato lahko prejemnik z njim obnovi sliko, če se izgubi en sam paket.';

  @override
  String get imageSend_send => 'Pošlji';

  @override
  String get imageSend_cancel => 'Prekliči';

  @override
  String get imageSend_encodeFailed => 'Te slike ni bilo mogoče kodirati.';

  @override
  String get imageSend_codecDownloading => 'Model za slike se še prenaša.';

  @override
  String get imageSend_codecUnavailable =>
      'Pošiljanje slik na tej napravi ni na voljo.';

  @override
  String get imageSend_codecDisabled =>
      'Slikovna sporočila so v nastavitvah izklopljena.';

  @override
  String get imageSend_deviceUnsupported =>
      'Ta radio ne more pošiljati slikovnih paketov. Poveži napravo s companion vdelano programsko opremo 13 ali novejšo.';

  @override
  String get imageSend_directMessagesUnsupported =>
      'Slike potujejo kot skupinski podatki, zato jih je mogoče poslati samo v kanal — ne v neposrednem sporočilu.';

  @override
  String get imageSend_tooLarge =>
      'Ta slika se je kodirala v več paketov, kot jih dovoljuje format mesh.';

  @override
  String imageSend_sentConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'paketov',
      few: 'paketi',
      two: 'paketa',
      one: 'paket',
    );
    return 'Slika poslana kot $count $_temp0.';
  }

  @override
  String imageSend_sendFailed(String error) {
    return 'Slike ni bilo mogoče poslati: $error';
  }

  @override
  String imageSend_sendingProgress(int sent, int total) {
    return 'Pošiljanje slike — paket $sent od $total';
  }

  @override
  String receivedImage_senderPrefix(String prefix) {
    return 'Vozlišče $prefix';
  }

  @override
  String receivedImage_incoming(int received, int total) {
    return '$received od $total paketov';
  }

  @override
  String get receivedImage_queued => 'Čakanje na dekodiranje';

  @override
  String get receivedImage_tapToDecode => 'Tapnite za dekodiranje';

  @override
  String get receivedImage_decoding => 'Rekonstrukcija… približno 1 s';

  @override
  String receivedImage_incomplete(int received, int total) {
    return 'Slika ni popolna — prispelo je $received od $total paketov';
  }

  @override
  String get receivedImage_corrupt => 'Slike ni bilo mogoče rekonstruirati';

  @override
  String get receivedImage_decoderMissing =>
      'Slika prejeta — dekodiranje slik je izklopljeno';

  @override
  String get receivedImage_evicted => 'Slika ni več shranjena';

  @override
  String get receivedImage_retry => 'Poskusite znova';

  @override
  String get receivedImage_decodeAgain => 'Dekodiraj ponovno';

  @override
  String get receivedImage_openSettings => 'Nastavite';

  @override
  String get receivedImage_tapToProcess => 'Tapnite za obdelavo';

  @override
  String receivedImage_awaiting(int bytes, int packets) {
    String _temp0 = intl.Intl.pluralLogic(
      packets,
      locale: localeName,
      other: 'paketov',
      few: 'paketi',
      two: 'paketa',
      one: 'paket',
    );
    return '$bytes bajtov · $packets $_temp0';
  }

  @override
  String imageSend_secondsValue(String seconds) {
    return '$seconds s';
  }

  @override
  String imageSend_minutesSecondsValue(String minutes, String seconds) {
    return '$minutes m $seconds s';
  }

  @override
  String get map_copyCoordsFromMap => 'Kopiraj koordinate';

  @override
  String get map_coordsCopied => 'Koordinate kopirane';

  @override
  String get appSettings_yandexApiKey => 'Ključ Yandex Tiles API';

  @override
  String get appSettings_yandexApiKeyMissing =>
      'Ni nastavljen – prikazan je OpenStreetMap';

  @override
  String get appSettings_yandexApiKeyDialogDescription =>
      'Vnesite svoj ključ iz razvijalske nadzorne plošče Yandex. Brezplačni paket Tiles API dovoljuje do 30 zahtev na sekundo. Podatki zemljevida © Yandex.';

  @override
  String get appSettings_yandexSigningSecret => 'Skrivnost za podpis Yandex';

  @override
  String get appSettings_yandexSigningSecretMissing =>
      'Ni nastavljena – zahteve gredo brez podpisa';

  @override
  String get appSettings_yandexSigningSecretDialogDescription =>
      'Neobvezno. Prilepite skrivnost za podpis, vezano na vaš ključ v konzoli Yandex. Pri neobveznem načinu podpisa delujejo tudi nepodpisane zahteve.';

  @override
  String get appSettings_yandexTileScale => 'Ločljivost ploščic Yandex';

  @override
  String appSettings_yandexTileScaleSubtitle(String scale) {
    return 'Trenutno: $scale';
  }

  @override
  String get appSettings_yandexTileScaleDescription =>
      'Višje vrednosti zahtevajo isto ploščico v večji velikosti — ostreje na gostih zaslonih, a več prometa in prostora v predpomnilniku.';

  @override
  String get settings_aboutYandexMapsTerms =>
      'Ploščice zemljevida: Yandex Maps. Pogoji uporabe: \nhttps://yandex.ru/legal/maps_termsofuse/';

  @override
  String get map_showMarksFromChannels => 'Prikaži oznake iz...';

  @override
  String get map_markerStyleTitle => 'Slog oznake';

  @override
  String get map_markerStyleColor => 'Barva polnila';

  @override
  String get map_markerStyleIcon => 'Ikona';

  @override
  String get map_removeMarkerForEveryone => 'Odstrani za vse';

  @override
  String get chat_poiRemoved => 'Točka zanimivosti odstranjena';

  @override
  String get chat_blockSender => 'Blokiraj pošiljatelja';

  @override
  String get chat_unblockSender => 'Odblokiraj pošiljatelja';

  @override
  String get chat_senderBlocked => 'pošiljatelj blokiran';

  @override
  String get chat_blockedSenders => 'Blokirani pošiljatelji';

  @override
  String get chat_blockedSendersEmpty => 'Ni blokiranih pošiljateljev';

  @override
  String get chat_blockedSendersAllChannels => 'Vsi kanali';

  @override
  String get chat_blockSenderName => 'Ime pošiljatelja';

  @override
  String get chat_hideBlockedSenderMessages => 'Skrij vrstice sporočil';

  @override
  String get chat_showBlockedSenderMessages => 'Prikaži vrstice sporočil';

  @override
  String get imageSend_previewShowAsReceived => 'Prikaži kot pri prejemnikih';

  @override
  String get imageSend_previewShowOriginal => 'Prikaži izvirnik';

  @override
  String get imageSend_previewAsReceived => 'Tako bodo sliko videli prejemniki';

  @override
  String get imageSend_previewDecodeFailed =>
      'Predogleda ni bilo mogoče dekodirati';

  @override
  String get settings_modSettingsLastHopSignal =>
      'Prikaži SNR/RSSI zadnjega skoka v kanalih';

  @override
  String get repeater_cliClearNeighbors => 'Počisti seznam sosedov';

  @override
  String get settings_backgroundPermissions =>
      'Znova zahtevaj dovoljenja za delovanje v ozadju';

  @override
  String get settings_backgroundPermissionsSubtitle =>
      'Preveri izjemo pri optimizaciji baterije in jo znova zahtevaj';

  @override
  String get settings_backgroundPermissionsGranted =>
      'Dovoljenje je že podeljeno';

  @override
  String get chat_selectSendAction => 'Izberite dejanje pošiljanja';

  @override
  String get chat_sendImageLora => 'Pošlji sliko prek MeshCore';

  @override
  String get reaction_report => 'Reakcije z emoji';

  @override
  String get messageHistoryMigrationWarningTitle =>
      'Zgodovina sporočil je bila prenesena le delno';

  @override
  String messageHistoryMigrationWarningDescription(
    int histories,
    int messages,
  ) {
    return 'Med prenosom ni bilo mogoče obnoviti $histories pogovorov in $messages posameznih sporočil. Preostala zgodovina je ohranjena.';
  }

  @override
  String get messageHistoryMigrationManage => 'Upravljanje shrambe';

  @override
  String get settings_modSettingsMessageStorage => 'Shramba sporočil';

  @override
  String get messageHistoryDatabaseTitle => 'Upravljanje podatkovne baze';

  @override
  String get messageHistoryDatabaseSubtitle =>
      'Statistika, obnovitev in vzdrževanje zgodovine sporočil';

  @override
  String get messageHistoryDatabaseOverview => 'Stanje podatkovne baze';

  @override
  String get messageHistoryDatabasePath => 'Pot do podatkovne baze';

  @override
  String get messageHistoryDatabaseFileSize => 'Velikost datoteke';

  @override
  String get messageHistoryDatabaseDirectCount => 'Neposredna sporočila';

  @override
  String get messageHistoryDatabaseChannelCount => 'Sporočila kanalov';

  @override
  String get messageHistoryDatabaseReclaimable => 'Mogoče sprostiti';

  @override
  String get messageHistoryDatabaseQuarantine => 'Karantena prenosa';

  @override
  String messageHistoryDatabaseQuarantineCount(int count, String size) {
    return 'Zavrnjeni zapisi: $count · $size';
  }

  @override
  String get messageHistoryDatabaseQuarantineEmpty => 'Ni zavrnjenih zapisov';

  @override
  String get messageHistoryDatabaseRetry => 'Znova poskusi obnoviti';

  @override
  String get messageHistoryDatabaseRetryDescription =>
      'Znova preveri karanteno s trenutnim razčlenjevalnikom in vrni popravljena sporočila v zgodovino.';

  @override
  String messageHistoryDatabaseRetryResult(int restored, int remaining) {
    return 'Obnovljeno: $restored, ostalo: $remaining';
  }

  @override
  String get messageHistoryDatabaseDiagnostic => 'Izvozi diagnostiko';

  @override
  String get messageHistoryDatabaseDiagnosticDescription =>
      'Ustvari poročilo brez besedila sporočil in ključev stikov.';

  @override
  String get messageHistoryDatabaseRecovery => 'Izvozi podatke za obnovitev';

  @override
  String get messageHistoryDatabaseRecoveryDescription =>
      'Ustvari datoteko samo z zavrnjenimi zapisi. Vsebuje lahko zasebne pogovore.';

  @override
  String get messageHistoryDatabaseRecoveryWarningTitle =>
      'Izvoz zaupnih podatkov';

  @override
  String get messageHistoryDatabaseRecoveryWarningDescription =>
      'Datoteka za obnovitev vsebuje izvirno besedilo zavrnjenih sporočil in identifikatorje pogovorov. Preglej jo, preden jo komu posreduješ.';

  @override
  String get messageHistoryDatabaseDeleteAfterExportTitle =>
      'Izbrišem karanteno po izvozu?';

  @override
  String get messageHistoryDatabaseDeleteAfterExportDescription =>
      'Datoteka za obnovitev je shranjena. Ali naj se izvoženi zavrnjeni podatki izbrišejo iz baze?';

  @override
  String get messageHistoryDatabaseClearQuarantine => 'Izbriši karanteno';

  @override
  String get messageHistoryDatabaseClearQuarantineDescription =>
      'Izbriši zavrnjene podatke brez možnosti obnovitve.';

  @override
  String get messageHistoryDatabaseClearWarningTitle =>
      'Izbrišem zavrnjene podatke?';

  @override
  String get messageHistoryDatabaseClearWarningDescription =>
      'Po izbrisu sporočil iz karantene ne bo več mogoče obnoviti ali izvoziti.';

  @override
  String get messageHistoryDatabaseMaintenance => 'Vzdrževanje';

  @override
  String get messageHistoryDatabaseIncrementalVacuum =>
      'Sprosti neuporabljen prostor';

  @override
  String get messageHistoryDatabaseIncrementalVacuumDescription =>
      'Postopoma vrni operacijskemu sistemu neuporabljene strani SQLite.';

  @override
  String get messageHistoryDatabaseIncrementalVacuumUnavailableDescription =>
      'Ta podatkovna baza najprej zahteva popolni VACUUM.';

  @override
  String get messageHistoryDatabaseFullVacuum =>
      'VACUUM (popolnoma obnovi bazo)';

  @override
  String get messageHistoryDatabaseFullVacuumDescription =>
      'Popolnoma obnovi datoteko podatkovne baze. Postopek lahko traja in zahteva dodaten prostor.';

  @override
  String get messageHistoryDatabaseFullVacuumWarningTitle =>
      'Popolnoma obnovim podatkovno bazo?';

  @override
  String get messageHistoryDatabaseFullVacuumWarningDescription =>
      'Ne zapiraj aplikacije, dokler se postopek ne konča. SQLite bo morda potreboval dodaten prostor v velikosti trenutne baze.';

  @override
  String get messageHistoryDatabaseCopyPath => 'Kopiraj pot';

  @override
  String get messageHistoryDatabasePathCopied => 'Pot kopirana';

  @override
  String messageHistoryDatabaseExportSaved(String path) {
    return 'Datoteka shranjena: $path';
  }

  @override
  String get messageHistoryDatabaseExportShared =>
      'Datoteka posredovana sistemskemu meniju za deljenje';

  @override
  String messageHistoryDatabaseDeleted(int count) {
    return 'Izbrisani zapisi: $count';
  }

  @override
  String get messageHistoryDatabaseOperationComplete => 'Postopek končan';

  @override
  String messageHistoryDatabaseOperationFailed(String error) {
    return 'Postopek ni uspel: $error';
  }

  @override
  String get settings_supportDevelopment => 'Podprite razvoj';

  @override
  String get donate_intro =>
      'Hvala, da ste se oglasili!\nČe vam je ta modifikacija všeč, lahko z donacijo podprete njen razvoj.';

  @override
  String get donate_tipLinkLabel => 'Povezava za napitnino:';

  @override
  String get donate_upstreamAuthor =>
      'Avtor izvirnega meshcore_open — zjs81 — sprejema donacije tukaj:';

  @override
  String get chat_canvasV4ToolText => 'Besedilo';

  @override
  String get chat_canvasV4TextAlignLeft => 'Levo';

  @override
  String get chat_canvasV4TextAlignCenter => 'Sredinsko';

  @override
  String get chat_canvasV4TextAlignRight => 'Desno';

  @override
  String chat_canvasV4TextWidth(int cells) {
    return 'Širina območja: $cells';
  }

  @override
  String chat_canvasV4TextFontSize(int size) {
    return 'Velikost pisave: $size';
  }

  @override
  String get channels_mcotxtPlainWhenSmaller =>
      'Pošlji navadno sporočilo, če je manjše';

  @override
  String get settings_modSettingsRecoverLongEchoes =>
      'Obnavljaj ponovitve dolgih paketov';

  @override
  String get settings_modSettingsRecoverLongEchoesDscr =>
      'Prepoznaj kopijo našega kanalskega sporočila iz dnevnika RX, ki jo je odrezala omejitev okvirja BLE';

  @override
  String get chat_canvasV4TextSize => 'Velikost besedila';

  @override
  String chat_unknownAppDataPlaceholder(
    String namespace,
    int subtype,
    int version,
  ) {
    return 'Prejet paket neznanega podtipa ($namespace, podtip $subtype različica $version); morda je treba posodobiti aplikacijo';
  }

  @override
  String chat_unknownAppDataPlaceholderNamespace(String namespace) {
    return 'Prejet paket v obliki, ki je ta aplikacija ne zna prebrati ($namespace); morda je treba posodobiti aplikacijo';
  }

  @override
  String get chat_showWithoutMarkdown => 'Prikaži brez Markdowna';

  @override
  String get chat_showWithMarkdown => 'Prikaži z Markdownom';

  @override
  String get channels_scanQrInstructions => 'Usmerite kamero v QR kodo kanala';

  @override
  String get channels_invalidQrCode => 'To ni QR koda kanala';

  @override
  String channels_qrAlreadyAdded(String name) {
    return 'Kanal \"$name\" je že dodan';
  }

  @override
  String get channels_shareQrHint => 'Skenirajte QR kodo, da dodate kanal.';

  @override
  String get channels_shareSecretKey => 'Skrivni ključ';

  @override
  String get channels_shareRegionScope => 'Regija kanala';

  @override
  String get channels_shareKeyCopied => 'Skrivni ključ kopiran';

  @override
  String get channels_shareLinkCopied => 'Povezava kopirana';

  @override
  String get channels_shareQrTapToCopy =>
      'Tapnite QR kodo, da jo kopirate kot sliko.';

  @override
  String get channels_shareQrTapToShare =>
      'Tapnite QR kodo, da jo shranite ali delite kot sliko.';

  @override
  String get channels_shareQrImageCopied => 'QR koda kopirana kot slika';

  @override
  String get channels_shareQrImageFailed =>
      'Slike s QR kodo ni bilo mogoče pripraviti';

  @override
  String channels_qrUpdateExisting(String name) {
    return 'Kanal $name že obstaja. Želite posodobiti njegove lastnosti?';
  }

  @override
  String get settings_modSettingsDirectEchoRecovery =>
      'Prejemaj zasebna sporočila brez čakanja na prehod celotne poti';

  @override
  String get settings_modSettingsDirectEchoRecoveryDscr =>
      'Pozor! Zasebni ključ vozlišča bo izvožen v pomnilnik aplikacije, da paket dešifrira aplikacija sama in ne vozlišče.';

  @override
  String get settings_modSettingsDirectEchoRecoveryPrompt =>
      'Želite vklopiti pospešeno prejemanje zasebnih sporočil?\nZa to se bo zasebni ključ vozlišča prenašal v delovni pomnilnik aplikacije.';

  @override
  String get channelPath_incompletePaths => 'Nepopolne poti';

  @override
  String channelPath_incompletePathTitle(int index, String hops) {
    return 'Nepopolna pot $index • $hops';
  }

  @override
  String get channelPath_copyInvertedPath => 'Kopiraj obratno pot';

  @override
  String get channelPath_invertedPathCopied => 'Obratna pot kopirana';

  @override
  String get discoveredContacts_alreadyAdded => 'Vozlišče je že med stiki';

  @override
  String get chat_floodRegionNode => 'Regija vozlišča';

  @override
  String chat_floodRegionNodeWith(String region) {
    return 'Regija vozlišča: $region';
  }

  @override
  String get chat_floodRegionNone => 'Brez regije';

  @override
  String get chat_stopSending => 'ustavi pošiljanje';

  @override
  String get urlImage_enable => 'Omogoči slike iz URL';

  @override
  String get urlImage_possible =>
      'Mogoča slika iz URL; omogočite jo v Nastavitvah.';

  @override
  String get settings_radioSettingsNotApplied =>
      'Radio teh nastavitev ni uveljavil';

  @override
  String get settings_publicKeyCopied => 'Javni ključ kopiran';

  @override
  String get channels_noFreeSlots => 'Vsa mesta za kanale so zasedena';

  @override
  String get repeater_frequencyRangeHelper => '150-2500 MHz';

  @override
  String get repeater_frequencyInvalid => 'Neveljavna frekvenca (150-2500 MHz)';

  @override
  String get repeater_txPowerRangeHelper => '-9 do 30 dBm';

  @override
  String get repeater_recvErrors => 'Napake sprejema';

  @override
  String get room_postsStored => 'Objave';

  @override
  String get room_postsPushed => 'Poslane objave';

  @override
  String get repeater_cliRegionLoadActive =>
      'Način nalaganja regij: pošljite eno ime regije na vrstico, zamaknjeno s presledki pod nadrejeno regijo (dodajte F za imenom, da dovolite flood). Vrstice ne prejmejo odgovora. Pošljite prazno vrstico za konec, nato pa \"region save\", da shranite rezultat.';

  @override
  String get repeater_cliRegionLoadHint =>
      'Vrstica regije ali prazna vrstica za konec';

  @override
  String get repeater_cliRegionLoadEnd => '(konec nalaganja regij)';

  @override
  String get repeater_cliHelpRegionDef =>
      'Definira verigo regij z enim ukazom: vsako ime se doda pod prejšnje; \"name,parent\" doda ime in nato nadaljuje pod navedeno nadrejeno regijo. Odgovori s seznamom regij.';

  @override
  String get repeater_cliHelpSetFloodMaxUnscoped =>
      'Nastavi največje število skokov za posredovanje flood paketov brez določenega regijskega obsega (0-64).';

  @override
  String get repeater_cliHelpSetFloodMaxAdvert =>
      'Nastavi največje število skokov za posredovanje flood advertov (0-64).';

  @override
  String get repeater_cliHelpGetFloodMaxUnscoped =>
      'Prikaže največje število skokov za flood pakete brez določenega regijskega obsega.';

  @override
  String get repeater_cliHelpGetFloodMaxAdvert =>
      'Prikaže največje število skokov za flood adverte.';

  @override
  String get repeater_cliHelpSetRadioFemRxGain =>
      'Preklopi RX ojačanje (LNA) LoRa front-end modula. Plošče brez njega odgovorijo z \"Error: unsupported\".';

  @override
  String get repeater_cliHelpSetRadioFemTxGain =>
      'Preklopi TX ojačanje (PA) LoRa front-end modula. Plošče brez njega odgovorijo z \"Error: unsupported\".';

  @override
  String get repeater_cliHelpGetRadioFemRxGain =>
      'Prikaže, ali je RX ojačanje LoRa front-end modula vklopljeno.';

  @override
  String get repeater_cliHelpGetRadioFemTxGain =>
      'Prikaže, ali je TX ojačanje LoRa front-end modula vklopljeno.';

  @override
  String get repeater_bridgeNote =>
      'Na voljo samo v vdelani programski opremi, zgrajeni z mostom (RS232 ali ESP-NOW).';

  @override
  String chat_longMessageRetryNote(int count) {
    return 'Nad 158 bajtov: poslano največ $count-krat';
  }

  @override
  String get contacts_notInNodeMemory => 'Ni dodan v pomnilnik vozlišča';

  @override
  String get contacts_addToNodeTitle => 'Dodam v pomnilnik vozlišča?';

  @override
  String contacts_addToNodeMessage(String contactName) {
    return 'Stik $contactName pozna samo aplikacija. Za prijavo, zahteve, deljenje in sporočila mora biti v pomnilniku vozlišča.';
  }

  @override
  String get contacts_addToNodeFailed =>
      'Dodajanje v pomnilnik vozlišča ni uspelo';

  @override
  String get contacts_addToNodeFull => 'Pomnilnik vozlišča je poln';
}
