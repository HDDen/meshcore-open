// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'MeshCore Open (Advanced mod)';

  @override
  String get nav_contacts => 'Contatos';

  @override
  String get nav_channels => 'Canais';

  @override
  String get nav_map => 'Mapa';

  @override
  String get common_cancel => 'Cancelar';

  @override
  String get common_ok => 'OK';

  @override
  String get common_connect => 'Conectar';

  @override
  String get common_unknownDevice => 'Dispositivo Desconhecido';

  @override
  String get common_save => 'Salvar';

  @override
  String get common_delete => 'Excluir';

  @override
  String get common_deleteAll => 'Excluir Tudo';

  @override
  String get common_close => 'Fechar';

  @override
  String get common_done => 'Concluído';

  @override
  String get common_edit => 'Editar';

  @override
  String get common_add => 'Adicionar';

  @override
  String get common_settings => 'Configurações';

  @override
  String get common_disconnect => 'Desconectar';

  @override
  String get common_connected => 'Conectado';

  @override
  String get common_disconnected => 'Desconectado';

  @override
  String get common_create => 'Criar';

  @override
  String get common_continue => 'Continuar';

  @override
  String get common_share => 'Compartilhar';

  @override
  String get common_copy => 'Copiar';

  @override
  String get common_retry => 'Tentar novamente';

  @override
  String get common_hide => 'Esconder';

  @override
  String get common_remove => 'Remover';

  @override
  String get common_enable => 'Ativar';

  @override
  String get common_disable => 'Desativar';

  @override
  String get common_undo => 'Desfazer';

  @override
  String get messageStatus_sent => 'Enviado';

  @override
  String get messageStatus_delivered => 'Entregue';

  @override
  String get messageStatus_pending => 'Enviando';

  @override
  String get messageStatus_failed => 'Falhou ao enviar';

  @override
  String get messageStatus_repeated => 'Repetição ouvida';

  @override
  String get messageStatus_failedChannel =>
      'O seu rádio não conseguiu enviar esta mensagem.';

  @override
  String messageStatus_resending(Object maxResends, Object resends) {
    return 'Ainda não foi ouvido por repetidores suficientes. Reenviado $resends de $maxResends vezes.';
  }

  @override
  String messageStatus_hopsNotReached(Object hops, Object required) {
    return 'Enviado, mas ouvido de volta por apenas $hops de $required repetidores. Pode ter chegado mais longe do que o seu rádio consegue ouvir.';
  }

  @override
  String get messageStatus_sentChannel =>
      'Enviado. Os canais não confirmam a entrega, portanto isto significa apenas que o seu rádio o enviou.';

  @override
  String get messageStatus_sentDirect =>
      'Enviado. À espera da confirmação do contato.';

  @override
  String messageStatus_heardRepeatedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vezes',
      one: 'uma vez',
    );
    return 'Ouvido $_temp0. Os repetidores próximos repassaram-no.';
  }

  @override
  String get common_reboot => 'Reiniciar';

  @override
  String get common_loading => 'Carregando...';

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
  String get common_autoRefresh => 'Atualização automática';

  @override
  String get common_interval => 'Intervalo';

  @override
  String get common_default => 'Padrão';

  @override
  String get common_clear => 'Limpar';

  @override
  String get common_send => 'Enviar';

  @override
  String get common_apply => 'Aplicar';

  @override
  String get scanner_title => 'MeshCore Open (Advanced mod)';

  @override
  String get connectionChoiceUsbLabel => 'USB';

  @override
  String get connectionChoiceBluetoothLabel => 'Bluetooth';

  @override
  String get connectionChoiceTcpLabel => 'TCP';

  @override
  String get tcpScreenTitle => 'Estabelecer conexão via TCP';

  @override
  String get tcpHostLabel => 'Endereço IP';

  @override
  String get tcpHostHint => '192.168.40.10 / example.com';

  @override
  String get tcpPortLabel => 'Porta';

  @override
  String get tcpPortHint => '5000';

  @override
  String get tcpStatus_notConnected => 'Insira o endereço e conecte-se.';

  @override
  String tcpStatus_connectingTo(String endpoint) {
    return 'Conectando a $endpoint...';
  }

  @override
  String get tcpErrorHostRequired => 'É necessário fornecer um endereço IP.';

  @override
  String get tcpErrorPortInvalid => 'A porta deve estar entre 1 e 65535.';

  @override
  String get tcpErrorUnsupported =>
      'O protocolo TCP não é suportado nesta plataforma.';

  @override
  String get tcpErrorTimedOut => 'A conexão TCP expirou.';

  @override
  String tcpConnectionFailed(String error) {
    return 'Falha na conexão TCP: $error';
  }

  @override
  String get tcpBookmarksLabel => 'Últimas conexões';

  @override
  String get tcpBookmarksSetName => 'Definir nome do favorito';

  @override
  String get tcpBookmarksFavouritesSubtitle =>
      'Quando marcado como favorito, não é removido do histórico de conexões';

  @override
  String get usbScreenTitle => 'Conecte via USB';

  @override
  String get usbScreenSubtitle =>
      'Selecione um dispositivo serial detectado e conecte-o diretamente ao seu nó MeshCore.';

  @override
  String get usbScreenStatus => 'Selecione um dispositivo USB';

  @override
  String get usbScreenNote =>
      'A comunicação serial via USB está ativa em dispositivos Android e plataformas de desktop compatíveis.';

  @override
  String get usbScreenEmptyState =>
      'Nenhum dispositivo USB encontrado. Conecte um e atualize.';

  @override
  String get usbErrorPermissionDenied =>
      'A permissão para acesso via USB foi negada.';

  @override
  String get usbErrorDeviceMissing =>
      'O dispositivo USB selecionado não está mais disponível.';

  @override
  String get usbErrorInvalidPort => 'Selecione um dispositivo USB válido.';

  @override
  String get usbErrorBusy =>
      'Já existe uma solicitação de conexão USB em andamento.';

  @override
  String get usbErrorNotConnected => 'Não há nenhum dispositivo USB conectado.';

  @override
  String get usbErrorOpenFailed =>
      'Não foi possível abrir o dispositivo USB selecionado.';

  @override
  String get usbErrorConnectFailed =>
      'Não foi possível conectar ao dispositivo USB selecionado.';

  @override
  String get usbErrorUnsupported =>
      'A comunicação serial via USB não é suportada nesta plataforma.';

  @override
  String get usbErrorAlreadyActive => 'A conexão USB já está ativa.';

  @override
  String get usbErrorNoDeviceSelected =>
      'Nenhum dispositivo USB foi selecionado.';

  @override
  String get usbErrorPortClosed => 'A conexão USB não está ativa.';

  @override
  String get usbErrorConnectTimedOut =>
      'A conexão expirou. Verifique se o dispositivo possui o firmware USB Companion.';

  @override
  String get usbFallbackDeviceName => 'Dispositivo Web Serial';

  @override
  String get usbStatus_notConnected => 'Selecione um dispositivo USB';

  @override
  String get usbStatus_connecting => 'Conectando ao dispositivo USB...';

  @override
  String get usbStatus_searching => 'Procurando por dispositivos USB...';

  @override
  String usbConnectionFailed(String error) {
    return 'Falha na conexão USB: $error';
  }

  @override
  String get scanner_scanning => 'Procurando por dispositivos...';

  @override
  String get scanner_connecting => 'Conectando...';

  @override
  String get scanner_disconnecting => 'Desconectando...';

  @override
  String get scanner_notConnected => 'Não está conectado';

  @override
  String scanner_connectedTo(String deviceName) {
    return 'Conectado a $deviceName';
  }

  @override
  String get scanner_searchingDevices => 'Procurando dispositivos MeshCore...';

  @override
  String get scanner_tapToScan =>
      'Toque em \"Escanear\" para encontrar dispositivos MeshCore';

  @override
  String scanner_connectionFailed(String error) {
    return 'Falha na conexão: $error';
  }

  @override
  String get scanner_stop => 'Pare';

  @override
  String get scanner_scan => 'Escanear';

  @override
  String get scanner_bluetoothOff => 'Bluetooth está desativado';

  @override
  String get scanner_bluetoothOffMessage =>
      'Por favor, ative o Bluetooth para escanear por dispositivos.';

  @override
  String get scanner_chromeRequired => 'Navegador Chrome necessário';

  @override
  String get scanner_chromeRequiredMessage =>
      'Esta aplicação web requer o Google Chrome ou um navegador baseado no Chromium para suporte de Bluetooth.';

  @override
  String get scanner_enableBluetooth => 'Ative o Bluetooth';

  @override
  String get scanner_bluetoothWebUnsupported =>
      'A funcionalidade Bluetooth não está disponível no navegador. Conecte-se via USB em vez disso.';

  @override
  String get device_quickSwitch => 'Mudar rapidamente';

  @override
  String get device_meshcore => 'MeshCore';

  @override
  String get settings_title => 'Configurações';

  @override
  String get settings_deviceInfo => 'Informações do Dispositivo';

  @override
  String get settings_appSettings => 'Configurações do App';

  @override
  String get settings_appSettingsSubtitle =>
      'Notificações, mensagens e preferências de mapa';

  @override
  String get settings_nodeSettings => 'Configurações do Nó';

  @override
  String get settings_nodeName => 'Nome do Nó';

  @override
  String get settings_nodeNameNotSet => 'Não definido';

  @override
  String get settings_nodeNameHint => 'Insira o nome do nó';

  @override
  String get settings_nodeNameUpdated => 'Nome atualizado';

  @override
  String get settings_radioSettings => 'Configurações de Rádio';

  @override
  String get settings_radioSettingsSubtitle =>
      'Frequência, potência, fator de espalhamento';

  @override
  String get settings_radioSettingsUpdated =>
      'Configurações de rádio atualizadas';

  @override
  String get settings_regionSettings => 'Regiões';

  @override
  String get settings_regionSettingsSubtitle => 'Gerenciar as regiões salvas';

  @override
  String get settings_regionEmptyExplanation =>
      'As regiões limitam as mensagens de inundação aos repetidores de uma área. Obtenha-as dos repetidores próximos ou adicione uma pelo nome.';

  @override
  String get settings_regionFetchFromRepeaters =>
      'Obter a partir de repetidores';

  @override
  String get settings_regionDefault => 'Região padrão';

  @override
  String get settings_regionDefaultSubtitle =>
      'Usada pelos canais sem região própria';

  @override
  String get settings_regionDefaultNone => 'Nenhuma';

  @override
  String settings_regionUseRadioDefault(String region) {
    return 'Padrão do rádio ($region)';
  }

  @override
  String get settings_regionNoRegion => 'Sem região (sem escopo)';

  @override
  String get settings_regionRadioDefault => 'Região padrão do rádio';

  @override
  String get settings_regionRadioDefaultSubtitle =>
      'Salva no rádio. Floods enviados sem região a utilizam, a partir deste app e de qualquer outro app conectado ao rádio.';

  @override
  String get settings_regionRadioDefaultUpdated =>
      'Região padrão do rádio atualizada';

  @override
  String get settings_regionRadioDefaultFailed =>
      'Não foi possível atualizar a região padrão do rádio';

  @override
  String get settings_regionManagement_screenTitle =>
      'Gerenciamento de regiões';

  @override
  String get settings_regionNameHint => 'Digite o nome da região';

  @override
  String get settings_regionAddRegion => 'Adicionar região';

  @override
  String get settings_regionFetchRegions => 'Solicitar regiões aos repetidores';

  @override
  String get settings_regionFetchRegionsFail => 'Nenhuma região encontrada';

  @override
  String get settings_regionFetchRegionsAlreadyExists =>
      'Esta região já foi adicionada';

  @override
  String get settings_regionName => 'Nome da região';

  @override
  String get settings_regionDeleted => 'Região excluída';

  @override
  String get settings_deleteRegion => 'Excluir região';

  @override
  String settings_deleteRegionConfirm(String region) {
    return 'Remover \"$region\" da lista de regiões?';
  }

  @override
  String get settings_location => 'Localização';

  @override
  String get settings_locationSubtitle => 'Coordenadas GPS';

  @override
  String get settings_locationUpdated =>
      'Localização e configurações de GPS atualizadas';

  @override
  String get settings_locationBothRequired =>
      'Insira a latitude e a longitude.';

  @override
  String get settings_locationInvalid => 'Latitude ou longitude inválida.';

  @override
  String get settings_locationGPSEnable => 'Ativar GPS';

  @override
  String get settings_locationGPSEnableSubtitle =>
      'Habilita a atualização automática da localização via GPS.';

  @override
  String get settings_locationIntervalSec => 'Intervalo para GPS (Segundos)';

  @override
  String get settings_locationIntervalInvalid =>
      'O intervalo deve ser de pelo menos 60 segundos e inferior a 86400 segundos.';

  @override
  String get settings_latitude => 'Latitude';

  @override
  String get settings_longitude => 'Longitude';

  @override
  String get settings_contactSettings => 'Configurações de Contato';

  @override
  String get settings_contactSettingsSubtitle =>
      'Configurações para como os contatos são adicionados';

  @override
  String get settings_privacyMode => 'Modo de Privacidade';

  @override
  String get settings_privacyModeSubtitle =>
      'Esconder nome/localização em anúncios';

  @override
  String get settings_privacyModeToggle =>
      'Ative o modo de privacidade para ocultar seu nome e localização em anúncios.';

  @override
  String get settings_privacyModeEnabled => 'Modo de privacidade ativado';

  @override
  String get settings_privacyModeDisabled => 'Modo de privacidade desativado';

  @override
  String get settings_privacy => 'Configurações de Privacidade';

  @override
  String get settings_privacySubtitle => 'Controle o que é compartilhado.';

  @override
  String get settings_privacySettingsDescription =>
      'Escolha quais informações o seu dispositivo compartilha com os outros.';

  @override
  String get settings_denyAll => 'Negar todos';

  @override
  String get settings_allowByContact =>
      'Permitir pelos sinalizadores do contato';

  @override
  String get settings_allowAll => 'Permitir todos';

  @override
  String get settings_telemetryBaseMode => 'Modo Base de Telemetria';

  @override
  String get settings_telemetryLocationMode =>
      'Modo de Localização de Telemetria';

  @override
  String get settings_telemetryEnvironmentMode =>
      'Modo de Ambiente de Telemetria';

  @override
  String get settings_telemetryPerContactHint =>
      'Para permitir um contato, abra o chat dele e escolha Configurações de Contato no menu.';

  @override
  String get settings_advertLocation => 'Localização do Anúncio';

  @override
  String get settings_advertLocationSubtitle =>
      'Incluir localização no anúncio';

  @override
  String get settings_autoZeroHopAdvertOnGpsUpdate =>
      'Anúncio zero-hop automático na atualização do GPS';

  @override
  String get settings_autoZeroHopAdvertOnGpsUpdateSubtitle =>
      'Quando a localização GPS mudar, enviar um anúncio zero-hop (requer localização no anúncio).';

  @override
  String get settings_multiAck => 'Multi-ACKs';

  @override
  String get settings_multiAckSubtitle =>
      'Enviar confirmações adicionais para melhorar a entrega; usa mais tempo de transmissão';

  @override
  String get settings_telemetryModeUpdated => 'Modo de telemetria atualizado';

  @override
  String get settings_actions => 'Ações';

  @override
  String get settings_deleteAllPaths => 'Excluir todas as rotas';

  @override
  String get settings_deleteAllPathsSubtitle =>
      'Limpar todos os dados de rota locais dos contatos. As rotas no nó não serão afetadas.';

  @override
  String get settings_sendAdvertisement => 'Enviar Anúncio';

  @override
  String get settings_sendAdvertisementSubtitle => 'Transmitir presença agora';

  @override
  String get settings_advertisementSent => 'Anúncio enviado';

  @override
  String get settings_syncTime => 'Sincronizar Horário';

  @override
  String get settings_syncTimeSubtitle =>
      'Definir o relógio do dispositivo para o horário do telefone';

  @override
  String get settings_timeSynchronized => 'Horário sincronizado';

  @override
  String get settings_refreshContacts => 'Atualizar Contatos';

  @override
  String get settings_refreshContactsSubtitle =>
      'Recarregar a lista de contatos do dispositivo';

  @override
  String get settings_rebootDevice => 'Reiniciar Dispositivo';

  @override
  String get settings_rebootDeviceSubtitle =>
      'Reiniciar o dispositivo MeshCore';

  @override
  String get settings_rebootDeviceConfirm =>
      'Tem certeza de que deseja reiniciar o dispositivo? Você será desconectado.';

  @override
  String get settings_debug => 'Depuração';

  @override
  String get settings_companionDebugLog => 'Registro de depuração auxiliar';

  @override
  String get settings_companionDebugLogSubtitle =>
      'Comandos, respostas e dados brutos para protocolos BLE/TCP/USB';

  @override
  String get settings_appDebugLog => 'Log de Depuração do Aplicativo';

  @override
  String get settings_appDebugLogSubtitle =>
      'Mensagens de depuração do aplicativo';

  @override
  String get settings_about => 'Sobre';

  @override
  String settings_aboutVersion(String version) {
    return 'MeshCore Open (Advanced mod) v$version';
  }

  @override
  String get settings_aboutLegalese => 'Projeto MeshCore de Código Aberto 2026';

  @override
  String get settings_aboutDescription =>
      'Um cliente Flutter de código aberto para dispositivos de rede mesh LoRa MeshCore.';

  @override
  String get settings_aboutModDescription =>
      'A modificação «Advanced» é baseada no meshcore_open original e traz alterações propostas no repositório do aplicativo original ou específicas da área de uso e, por isso, não enviadas como pull requests.';

  @override
  String get settings_aboutModLink =>
      'Versões no Github: \nhttps://github.com/HDDen/meshcore-open/releases \nGrupo da modificação no Telegram: \nhttps://t.me/mcoadvanced \nSite da modificação: \nhttps://mcoadvanced.ru';

  @override
  String get settings_aboutOpenMeteoAttribution =>
      'Dados de elevação LOS: Open-Meteo (CC BY 4.0)';

  @override
  String get settings_infoName => 'Nome';

  @override
  String get settings_infoId => 'ID';

  @override
  String get settings_infoDeviceName => 'Nome da placa';

  @override
  String get settings_infoStatus => 'Estado';

  @override
  String get settings_infoBattery => 'Bateria';

  @override
  String get settings_infoPublicKey => 'Chave Pública';

  @override
  String get settings_infoContactsCount => 'Número de Contatos';

  @override
  String get settings_infoChannelCount => 'Número de Canais';

  @override
  String get settings_infoFirmware => 'Versão do firmware';

  @override
  String get settings_presets => 'Configurações pré-definidas';

  @override
  String get settings_presetCustom => 'Personalizado';

  @override
  String get settings_radioMatchWarning =>
      'Todos os nós com os quais você fala devem usar a mesma frequência, largura de banda e SF. A taxa de codificação (CR) pode ser diferente.';

  @override
  String get settings_frequency => 'Frequência (MHz)';

  @override
  String get settings_frequencyHelper => '150.0 - 2500.0';

  @override
  String get settings_frequencyInvalid => 'Frequência inválida (150-2500 MHz)';

  @override
  String get settings_bandwidth => 'Largura de banda';

  @override
  String get settings_spreadingFactor => 'Fator de Dispersão';

  @override
  String get settings_codingRate => 'Taxa de Codificação';

  @override
  String get settings_txPower => 'Potência de TX (dBm)';

  @override
  String settings_txPowerRangeHelper(int min, int max) {
    return '$min a $max dBm';
  }

  @override
  String get settings_txPowerInvalid => 'Potência de TX inválida (0-22 dBm)';

  @override
  String get settings_clientRepeat => 'Repetição sem rede';

  @override
  String settings_clientRepeatFrequencyNote(String freq) {
    return 'Frequência definida em $freq MHz para a repetição sem rede';
  }

  @override
  String get settings_clientRepeatSubtitle =>
      'Permita que este dispositivo repita pacotes de rede para outros dispositivos.';

  @override
  String get settings_clientRepeatFreqWarning =>
      'A repetição fora da rede requer frequências de 433, 869.495 ou 918 MHz.';

  @override
  String settings_error(String message) {
    return 'Erro: $message';
  }

  @override
  String get settings_channelResendTimeoutTitle => 'Atraso de reenvio manual';

  @override
  String get settings_channelResendTimeoutSubtitle =>
      'Também afeta o mecanismo interno para eliminar renderizações duplicadas de mensagens enviadas';

  @override
  String get settings_channelMaxbytesOutgoingTitle =>
      'Limitar o payload de saída dos canais, bytes';

  @override
  String get settings_channelMaxbytesOutgoingSubtitle =>
      'O limite considera o texto da mensagem mais o nome do remetente. Foi observado que, quando uma mensagem excede certo número de bytes, as confirmações de repetição de pacotes deixam de ser transmitidas. Isso é especialmente perceptível em conexões BLE. O limite aproximado em que as confirmações ainda funcionam é 139 bytes. Para TCP/USB, esse limite é de aproximadamente 150 bytes.';

  @override
  String get settings_quickAnswersTitle => 'Respostas rápidas';

  @override
  String get settings_quickAnswersSubtitle =>
      'Uma lista de frases disponíveis para selecionar como respostas rápidas. Elas são atribuídas a contatos/canais nas respectivas configurações.';

  @override
  String get settings_quickAnswersAddText => 'Digite seu texto';

  @override
  String get settings_quickAnswersEditText => 'Editar resposta';

  @override
  String get settings_quickAnswersSelect => 'Ativar estas respostas';

  @override
  String get settings_quickAnswersExists => 'Já existe';

  @override
  String get settings_quickAnswersNotAdded =>
      'Você ainda não adicionou respostas rápidas para este chat!';

  @override
  String get settings_quickAnswersSendAtSelect => 'Enviar ao selecionar';

  @override
  String get appSettings_title => 'Configurações do App';

  @override
  String get appSettings_appearance => 'Aparência';

  @override
  String get appSettings_theme => 'Tema';

  @override
  String get appSettings_themeSystem => 'Padrão do sistema';

  @override
  String get appSettings_themeLight => 'Claro';

  @override
  String get appSettings_themeDark => 'Escuro';

  @override
  String get appSettings_language => 'Idioma';

  @override
  String get appSettings_languageSystem => 'Padrão do sistema';

  @override
  String get appSettings_languageEn => 'Inglês';

  @override
  String get appSettings_languageFr => 'Francês';

  @override
  String get appSettings_languageEs => 'Espanhol';

  @override
  String get appSettings_languageDe => 'Alemão';

  @override
  String get appSettings_languagePl => 'Polonês';

  @override
  String get appSettings_languageSl => 'Esloveno';

  @override
  String get appSettings_languagePt => 'Português';

  @override
  String get appSettings_languageIt => 'Italiano';

  @override
  String get appSettings_languageZh => 'Chinês';

  @override
  String get appSettings_languageSv => 'Sueco';

  @override
  String get appSettings_languageNl => 'Holandês';

  @override
  String get appSettings_languageSk => 'Eslovaco';

  @override
  String get appSettings_languageBg => 'Búlgaro';

  @override
  String get appSettings_languageRu => 'Russo';

  @override
  String get appSettings_languageUk => 'Ucraniano';

  @override
  String get repeater_pathHashModeOption0 => '1 byte';

  @override
  String get repeater_pathHashModeOption1 => '2 bytes';

  @override
  String get repeater_pathHashModeOption2 => '3 bytes';

  @override
  String get repeater_pathHashModeOption3 => '4 bytes';

  @override
  String get appSettings_enableMessageTracing =>
      'Ativar rastreamento de mensagens';

  @override
  String get appSettings_enableMessageTracingSubtitle =>
      'Mostrar metadados detalhados de roteamento e tempo para as mensagens';

  @override
  String get appSettings_enableTimeSeconds =>
      'Mostrar segundos nas informações da mensagem';

  @override
  String get appSettings_showKeyboardHidingButton =>
      'Mostrar botão para ocultar o teclado';

  @override
  String get settings_pathHashModeHelper =>
      'Tamanho de cada ID de nó registado no caminho dos pacotes de inundação que este rádio envia: 1 byte (256 IDs, até 64 saltos), 2 bytes (65.000 IDs, até 32 saltos), 3 bytes (16 milhões de IDs, até 21 saltos). IDs maiores reduzem as colisões, mas os repetidores com firmware anterior à v1.14 descartam os pacotes com IDs de 2 ou 3 bytes.';

  @override
  String settings_requiresFirmware(Object version) {
    return 'Requer o firmware $version ou mais recente';
  }

  @override
  String get appSettings_channelMinHops =>
      'Reenviar as mensagens de canal até atravessarem repetidores suficientes';

  @override
  String get appSettings_channelMinHopsSubtitle =>
      'Se a sua mensagem não for ouvida de volta por repetidores suficientes, envie-a de novo. Usa mais tempo de transmissão.';

  @override
  String appSettings_channelMinHopsCount(Object count) {
    return 'Saltos necessários: $count';
  }

  @override
  String appSettings_channelMinHopsRetries(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vezes',
      one: '1 vez',
    );
    return 'Reenviar até $_temp0';
  }

  @override
  String get appSettings_channelMinHopsCountRepeaters =>
      'Contar também repetidores próximos diferentes';

  @override
  String appSettings_channelMinHopsRepeaterCount(Object count) {
    return 'Repetidores próximos necessários: $count';
  }

  @override
  String appSettings_channelMinHopsCountRepeatersSubtitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count repetidores próximos diferentes',
      one: '1 repetidor próximo',
    );
    return 'Considerar a mensagem como enviada quando $_temp0 a repetirem, mesmo que você não a ouça avançar mais.';
  }

  @override
  String get appSettings_regionOnHopsLine =>
      'Região ao lado da contagem de saltos';

  @override
  String get appSettings_regionOnHopsLineSubtitle =>
      'Mostra a região de uma mensagem de canal na mesma linha da contagem de saltos, em vez de abaixo dela.';

  @override
  String get appSettings_notifications => 'Notificações';

  @override
  String get appSettings_enableNotifications => 'Ativar Notificações';

  @override
  String get appSettings_enableNotificationsSubtitle =>
      'Receber notificações para mensagens e anúncios';

  @override
  String get appSettings_notificationPermissionDenied =>
      'Permissão de notificação negada';

  @override
  String get appSettings_notificationsEnabled => 'Notificações ativadas';

  @override
  String get appSettings_notificationsDisabled => 'Notificações desativadas';

  @override
  String get appSettings_messageNotifications => 'Notificações de Mensagem';

  @override
  String get appSettings_messageNotificationsSubtitle =>
      'Mostrar notificação ao receber novas mensagens';

  @override
  String get appSettings_batteryOptimization => 'Atividade em segundo plano';

  @override
  String get appSettings_batteryOptimizationSubtitle =>
      'Defina o MeshCore Open como \"Não otimizar\" nas configurações de bateria para que as mensagens continuem a chegar em segundo plano';

  @override
  String get appSettings_channelMessageNotifications =>
      'Notificações de Mensagens do Canal';

  @override
  String get appSettings_channelMessageNotificationsSubtitle =>
      'Mostrar notificação ao receber mensagens do canal';

  @override
  String get appSettings_advertisementNotifications =>
      'Notificações de Anúncios';

  @override
  String get appSettings_advertisementNotificationsSubtitle =>
      'Mostrar notificação quando novos nós forem descobertos';

  @override
  String get appSettings_messaging => 'Mensagens';

  @override
  String get appSettings_clearPathOnMaxRetry =>
      'Limpar Caminho em Tentativas Máximas';

  @override
  String get appSettings_clearPathOnMaxRetrySubtitle =>
      'Redefinir o caminho de contato após 5 tentativas de envio falhas';

  @override
  String get appSettings_pathsWillBeCleared =>
      'Os caminhos serão limpos após 5 tentativas falhas.';

  @override
  String get appSettings_pathsWillNotBeCleared =>
      'Os caminhos não serão limpos automaticamente.';

  @override
  String get appSettings_autoRouteRotation => 'Rotação de Rota Automática';

  @override
  String get appSettings_autoRouteRotationSubtitle =>
      'Alternar entre os melhores caminhos e o modo inundação';

  @override
  String get appSettings_autoRouteRotationEnabled =>
      'Rotação de roteamento automático habilitada';

  @override
  String get appSettings_autoRouteRotationDisabled =>
      'Rotação de roteamento automático desativada';

  @override
  String get appSettings_maxRouteWeight => 'Peso Máximo da Rota';

  @override
  String get appSettings_maxRouteWeightSubtitle =>
      'Peso máximo que um determinado percurso pode acumular com entregas bem-sucedidas.';

  @override
  String get appSettings_initialRouteWeight => 'Peso Inicial da Rota';

  @override
  String get appSettings_initialRouteWeightSubtitle =>
      'Peso inicial para novos caminhos descobertos';

  @override
  String get appSettings_routeWeightSuccessIncrement =>
      'Aumento do peso para indicar sucesso';

  @override
  String get appSettings_routeWeightSuccessIncrementSubtitle =>
      'Peso adicionado a um caminho após a entrega bem-sucedida.';

  @override
  String get appSettings_routeWeightFailureDecrement =>
      'Redução do peso da falha';

  @override
  String get appSettings_routeWeightFailureDecrementSubtitle =>
      'Peso removido de um caminho após uma tentativa de entrega malsucedida.';

  @override
  String get appSettings_maxMessageRetries =>
      'Número máximo de tentativas de envio de mensagens';

  @override
  String get appSettings_maxMessageRetriesSubtitle =>
      'Número de tentativas de reenvio antes de classificar uma mensagem como falha.';

  @override
  String get appSettings_battery => 'Bateria';

  @override
  String get appSettings_batteryChemistry => 'Química da Bateria';

  @override
  String appSettings_batteryChemistryPerDevice(String deviceName) {
    return 'Definir por dispositivo ($deviceName)';
  }

  @override
  String get appSettings_batteryChemistryConnectFirst =>
      'Conecte-se a um dispositivo para escolher';

  @override
  String get appSettings_batteryNmc => '18650 NMC (3,0-4,2V)';

  @override
  String get appSettings_batteryLifepo4 => 'LiFePO4 (2,6-3,65V)';

  @override
  String get appSettings_batteryLipo => 'LiPo (3,0-4,2V)';

  @override
  String get appSettings_mapDisplay => 'Exibição do Mapa';

  @override
  String get appSettings_showRepeaters => 'Mostrar Repetidores';

  @override
  String get appSettings_showRepeatersSubtitle =>
      'Exibir nós de repetidor no mapa';

  @override
  String get appSettings_showChatNodes => 'Mostrar Nós de Chat';

  @override
  String get appSettings_showChatNodesSubtitle => 'Exibir nós de chat no mapa';

  @override
  String get appSettings_showOtherNodes => 'Mostrar Outros Nós';

  @override
  String get appSettings_showOtherNodesSubtitle =>
      'Exibir outros tipos de nó no mapa';

  @override
  String get appSettings_timeFilter => 'Filtro de Tempo';

  @override
  String get appSettings_timeFilterShowAll => 'Mostrar todos os nós';

  @override
  String appSettings_timeFilterShowLast(int hours) {
    return 'Mostrar nós das últimas $hours horas';
  }

  @override
  String get appSettings_mapTimeFilter => 'Filtro de Tempo do Mapa';

  @override
  String get appSettings_showNodesDiscoveredWithin =>
      'Mostrar nós descobertos dentro de:';

  @override
  String get appSettings_allTime => 'Todo o período';

  @override
  String get appSettings_lastHour => 'Última hora';

  @override
  String get appSettings_last6Hours => 'Últimas 6 horas';

  @override
  String get appSettings_last24Hours => 'Últimas 24 horas';

  @override
  String get appSettings_lastWeek => 'Da última semana';

  @override
  String get appSettings_rasterTileSource => 'Fonte de blocos raster';

  @override
  String get appSettings_stadiaEndpoint => 'Endpoint da Stadia';

  @override
  String get appSettings_stadiaApiKey => 'Chave da API Stadia';

  @override
  String get appSettings_stadiaApiKeyRequired =>
      'Obrigatório para usar o Stadia Maps';

  @override
  String appSettings_stadiaApiKeyConfigured(String maskedKey) {
    return 'Configurado: $maskedKey';
  }

  @override
  String get appSettings_stadiaApiKeyDialogDescription =>
      'Insira sua chave da API Stadia Maps. O aplicativo a usa para solicitações de blocos raster.';

  @override
  String get appSettings_offlineMapCache => 'Cache de Mapa Offline';

  @override
  String get appSettings_unitsTitle => 'Unidades';

  @override
  String get appSettings_unitsMetric => 'Métrico (m/km)';

  @override
  String get appSettings_unitsImperial => 'Imperial (ft/mi)';

  @override
  String get appSettings_noAreaSelected => 'Nenhuma área selecionada';

  @override
  String appSettings_areaSelectedZoom(int minZoom, int maxZoom) {
    return 'Área selecionada (zoom $minZoom-$maxZoom)';
  }

  @override
  String get appSettings_debugCard => 'Depuração';

  @override
  String get appSettings_appDebugLogging =>
      'Registro de Depuração do Aplicativo';

  @override
  String get appSettings_appDebugLoggingSubtitle =>
      'Registrar mensagens de depuração do aplicativo para solucionar problemas';

  @override
  String get appSettings_appDebugLoggingEnabled =>
      'Log de depuração do aplicativo habilitado';

  @override
  String get appSettings_appDebugLoggingDisabled =>
      'O registro de depuração do aplicativo está desativado.';

  @override
  String get contacts_title => 'Contatos';

  @override
  String get contacts_noContacts => 'Ainda não existem contatos.';

  @override
  String get contacts_contactsWillAppear =>
      'Os contatos serão exibidos quando os dispositivos anunciarem.';

  @override
  String get contacts_unread => 'Não lido';

  @override
  String get contacts_searchContactsNoNumber => 'Pesquisar Contatos...';

  @override
  String contacts_searchContacts(int number, String str) {
    return 'Pesquisar $number$str contatos...';
  }

  @override
  String contacts_searchFavorites(int number, String str) {
    return 'Pesquisar $number$str Favoritos...';
  }

  @override
  String contacts_searchUsers(int number, String str) {
    return 'Pesquisar $number$str Usuários...';
  }

  @override
  String contacts_searchRepeaters(int number, String str) {
    return 'Pesquisar $number$str Repetidores...';
  }

  @override
  String contacts_searchRoomServers(int number, String str) {
    return 'Pesquisar $number$str servidores de sala...';
  }

  @override
  String get contacts_noUnreadContacts => 'Sem contatos não lidos.';

  @override
  String get contacts_noContactsFound =>
      'Não foram encontrados contatos ou grupos.';

  @override
  String get contacts_storageFull =>
      'O armazenamento de contatos no nó está cheio. Não é possível adicionar novos nós até que contatos sejam removidos.';

  @override
  String get contacts_deleteContact => 'Excluir Contato';

  @override
  String contacts_removeConfirm(String contactName) {
    return 'Remover $contactName dos contatos?';
  }

  @override
  String get contacts_removeFromContacts => 'Remover dos contatos';

  @override
  String contacts_removeFromContactsConfirm(String contactName) {
    return '$contactName passará para os contatos descobertos. O histórico do chat será excluído.';
  }

  @override
  String get contacts_keepChatHistory => 'Manter o histórico do chat';

  @override
  String get contacts_remove => 'Remover';

  @override
  String contacts_discoveredNearby(int count) {
    return 'Descobertos nas proximidades ($count)';
  }

  @override
  String get contacts_noContactsDiscoveredHint =>
      'Os nós que o seu rádio ouve mas que ainda não adicionou estão listados em Contatos descobertos';

  @override
  String get contacts_manageRepeater => 'Gerenciar Repetidor';

  @override
  String get contacts_requestRegions => 'Solicitar regiões';

  @override
  String get contacts_manageRoom => 'Gerenciar Servidor de Sala';

  @override
  String get contacts_roomLogin => 'Login no Servidor de Sala';

  @override
  String get contacts_openChat => 'Abrir Chat';

  @override
  String get contacts_editGroup => 'Editar Grupo';

  @override
  String get contacts_deleteGroup => 'Excluir Grupo';

  @override
  String contacts_deleteGroupConfirm(String groupName) {
    return 'Remover $groupName?';
  }

  @override
  String get contacts_newGroup => 'Novo Grupo';

  @override
  String get contacts_newGroupDescription =>
      'Agrupa canais/contatos em uma pasta';

  @override
  String get contacts_moreOptions => 'Mais opções';

  @override
  String get contacts_searchOpen => 'Pesquisar contatos';

  @override
  String get contacts_searchClose => 'Fechar pesquisa';

  @override
  String get contacts_groupName => 'Nome do grupo';

  @override
  String get contacts_groupNameRequired => 'O nome do grupo é obrigatório.';

  @override
  String get contacts_groupNameReserved => 'Este nome de grupo está reservado';

  @override
  String contacts_groupAlreadyExists(String name) {
    return 'O grupo \"$name\" já existe';
  }

  @override
  String get contacts_filterContacts => 'Filtrar contatos...';

  @override
  String get contacts_noContactsMatchFilter =>
      'Não existem contatos que correspondam ao seu filtro';

  @override
  String get contacts_noMembers => 'Nenhum membro';

  @override
  String get contacts_lastSeenNow => 'Última vez que foi visto agora';

  @override
  String contacts_lastSeenMinsAgo(int minutes) {
    return 'Última vez que foi visto $minutes minutos atrás';
  }

  @override
  String get contacts_lastSeenHourAgo => 'Última vez que foi visto há 1 hora.';

  @override
  String contacts_lastSeenHoursAgo(int hours) {
    return 'Última vez visto $hours horas atrás';
  }

  @override
  String get contacts_lastSeenDayAgo => 'Última vez que foi visto 1 dia atrás';

  @override
  String contacts_lastSeenDaysAgo(int days) {
    return 'Última vez visto $days dias atrás';
  }

  @override
  String get contact_info => 'Informações de Contato';

  @override
  String get contact_settings => 'Configurações de Contato';

  @override
  String get contact_telemetry => 'Telemetria';

  @override
  String get contact_lastSeen => 'Visto pela última vez';

  @override
  String get contact_clearChat => 'Limpar Chat';

  @override
  String get contact_clearChatConfirm => 'Excluir as mensagens do chat?';

  @override
  String get contact_teleBase => 'Base de Telemetria';

  @override
  String get contact_teleBaseSubtitle =>
      'Permitir compartilhamento do nível da bateria e telemetria básica';

  @override
  String get contact_teleLoc => 'Localização de Telemetria';

  @override
  String get contact_teleLocSubtitle =>
      'Permitir compartilhamento de dados de localização';

  @override
  String get contact_teleEnv => 'Ambiente de Telemetria';

  @override
  String get contact_teleEnvSubtitle =>
      'Permitir compartilhamento de dados do sensor de ambiente';

  @override
  String get channels_title => 'Canais';

  @override
  String get channels_noChannelsConfigured => 'Nenhum canal configurado';

  @override
  String get channels_addPublicChannel => 'Adicionar Canal Público';

  @override
  String get channels_searchChannels => 'Pesquisar canais...';

  @override
  String get channels_noChannelsFound => 'Nenhum canal encontrado';

  @override
  String channels_channelIndex(int index) {
    return 'Canal $index';
  }

  @override
  String get channels_public => 'Público';

  @override
  String channels_via(String path) {
    return 'via $path';
  }

  @override
  String get channels_private => 'Privado';

  @override
  String get channels_hashtag => 'Hashtag';

  @override
  String get channels_addSectionJoin => 'Entrar numa existente';

  @override
  String get channels_addSectionCreate => 'Criar nova';

  @override
  String get channels_dragToReorder => 'Arraste para reordenar';

  @override
  String get channels_editChannel => 'Editar canal';

  @override
  String get channels_muteChannel => 'Silenciar, exceto menções';

  @override
  String get channels_unmuteChannel => 'Reativar notificações do canal';

  @override
  String get channels_deleteChannel => 'Excluir canal';

  @override
  String channels_deleteChannelConfirm(String name) {
    return 'Excluir \"$name\"? Não pode ser desfeito.';
  }

  @override
  String channels_channelDeleteFailed(String name) {
    return 'Falha ao excluir o canal \"$name\"';
  }

  @override
  String channels_channelDeleted(String name) {
    return 'Canal \"$name\" excluído';
  }

  @override
  String get channels_addChannel => 'Adicionar Canal';

  @override
  String get channels_channelIndexLabel => 'Índice do Canal';

  @override
  String get channels_channelName => 'Nome do Canal';

  @override
  String get channels_usePublicChannel => 'Usar Canal Público';

  @override
  String get channels_standardPublicPsk => 'PSK público padrão';

  @override
  String get channels_pskHex => 'PSK (Hex)';

  @override
  String get channels_generateRandomPsk => 'Gerar PSK aleatório';

  @override
  String get channels_enterChannelName => 'Por favor, insira um nome de canal';

  @override
  String get channels_pskMustBe32Hex =>
      'O PSK deve ter 32 caracteres hexadecimais.';

  @override
  String channels_channelAdded(String name) {
    return 'Canal \"$name\" adicionado';
  }

  @override
  String channels_editChannelTitle(int index) {
    return 'Editar Canal $index';
  }

  @override
  String get channels_smazCompression => 'Compressão SMAZ';

  @override
  String get channels_cyr2latCompression => 'Compressão Cyr2Lat';

  @override
  String get channels_cyr2latCompressionDscr =>
      'Substitui alguns caracteres cirílicos por caracteres latinos ao enviar.';

  @override
  String get channels_mcotxtCompression => 'Compressão MCOtxt';

  @override
  String get channels_cyr2latSettingsHeading => 'Configuração do Cyr2Lat';

  @override
  String get channels_cyr2latSettingsSubheading => 'Lista de substituições';

  @override
  String get channels_cyr2latSettingsDscr =>
      'Editar a configuração JSON de substituição de caracteres';

  @override
  String get channels_cyr2latSettingsDialogHint => 'Mapa de substituições JSON';

  @override
  String channels_cyr2latSettingsDialogWrongJSON(Object error) {
    return 'JSON incorreto: $error';
  }

  @override
  String channels_channelUpdated(String name) {
    return 'Canal \"$name\" atualizado';
  }

  @override
  String get channels_changeWidgetColor => 'Cor do widget';

  @override
  String get channels_changeWidgetTextColor => 'Cor do texto do widget';

  @override
  String get channels_changeGroupEmpty => 'Ainda está vazio aqui';

  @override
  String get channels_allowOrderingInGroup =>
      'Permitir ordenar canais dentro do grupo';

  @override
  String get settings_cyr2latProfileAdd => 'Adicionar perfil Cyr2Lat';

  @override
  String get settings_cyr2latProfileName => 'Nome do perfil';

  @override
  String get settings_cyr2latProfileNameEmpty =>
      'O nome do perfil não pode estar vazio';

  @override
  String get settings_cyr2latProfileAdded => 'Perfil adicionado com sucesso';

  @override
  String get settings_cyr2latProfileUpdated => 'Perfil atualizado com sucesso';

  @override
  String get settings_cyr2latProfileEdit => 'Editar perfil Cyr2Lat';

  @override
  String get settings_cyr2latProfileDelete => 'Excluir perfil Cyr2Lat';

  @override
  String get settings_cyr2latProfileDeleted => 'Perfil excluído com sucesso';

  @override
  String settings_cyr2latProfileDeleteDscr(String name) {
    return 'Tem certeza de que deseja excluir o perfil \"$name\"?';
  }

  @override
  String get settings_mcmpTextLimit => 'Limite de colagem de texto MCMP';

  @override
  String get settings_sendingDelayForCancellation =>
      'Atraso de envio para cancelamento';

  @override
  String get settings_useSendingDelay => 'Usar atraso de envio';

  @override
  String get chat_cancelSend => 'cancelar envio';

  @override
  String get settings_doNotFilterMessagesOnChannels =>
      'Considerar as mensagens destes canais como definitivamente entregues';

  @override
  String get settings_doNotFilterMessagesOnChannelsSubtitle =>
      'As mensagens para os canais listados são enviadas sem aguardar a confirmação do nó e sem novas tentativas.';

  @override
  String get channels_publicChannelAdded => 'Canal público adicionado';

  @override
  String get channels_sortBy => 'Ordenar por';

  @override
  String get channels_sortManual => 'Manual';

  @override
  String get channels_sortAZ => 'De A a Z';

  @override
  String get channels_sortLatestMessages => 'Últimas mensagens';

  @override
  String get channels_sortUnread => 'Não lido';

  @override
  String get channels_createPrivateChannel => 'Criar um Canal Privado';

  @override
  String get channels_createPrivateChannelDesc =>
      'Protegido com uma chave secreta.';

  @override
  String get channels_joinPrivateChannel => 'Junte-se a um Canal Privado';

  @override
  String get channels_joinPrivateChannelDesc =>
      'Inserir uma chave secreta manualmente.';

  @override
  String get channels_joinPublicChannel => 'Junte-se ao Canal Público';

  @override
  String get channels_joinPublicChannelDesc =>
      'Qualquer pessoa pode entrar neste canal.';

  @override
  String get channels_joinHashtagChannel => 'Junte-se a um Canal com Hashtag';

  @override
  String get channels_joinHashtagChannelDesc =>
      'Qualquer pessoa pode participar de canais com hashtag.';

  @override
  String get channels_scanQrCode => 'Escanear um Código QR';

  @override
  String get channels_scanQrCodeComingSoon => 'Em breve';

  @override
  String get channels_enterHashtag => 'Insira hashtag';

  @override
  String get channels_hashtagHint => 'ex. #equipe';

  @override
  String get channels_hashtagMcoaHint =>
      'Letras maiúsculas e “_” são suportadas apenas no MCOa';

  @override
  String channels_regionSetTo(String region) {
    return 'Região: $region';
  }

  @override
  String get channels_regionNotSet => 'Região: nenhuma';

  @override
  String get channels_regionSelect_Title => 'Atribuir região';

  @override
  String get channels_clearRegion => 'Limpar a região';

  @override
  String get channels_regionDefaultSuffix => '(padrão)';

  @override
  String get channels_regionRadioDefaultSuffix => '(padrão do rádio)';

  @override
  String channels_regionRadioDefaultApplies(String region) {
    return 'Este rádio envia floods sem região na sua região padrão: $region.';
  }

  @override
  String get channels_regionSelectExplanation =>
      'As mensagens de inundação deste canal só serão encaminhadas por repetidores da região selecionada.';

  @override
  String get channels_regionEmpty => 'Ainda não há regiões.';

  @override
  String get channels_manageRegions => 'Gerenciar regiões';

  @override
  String get chat_noMessages => 'Ainda não existem mensagens.';

  @override
  String get chat_sendMessage => 'Enviar mensagem';

  @override
  String chat_sendMessageTo(String contactName) {
    return 'Enviar uma mensagem para $contactName';
  }

  @override
  String get chat_sendMessageToStart => 'Enviar uma mensagem para começar';

  @override
  String get chat_originalMessageNotFound => 'Mensagem original não encontrada';

  @override
  String chat_replyingTo(String name) {
    return 'Respondendo a $name';
  }

  @override
  String chat_replyTo(String name) {
    return 'Responder a $name';
  }

  @override
  String get chat_location => 'Localização';

  @override
  String get chat_typeMessage => 'Digite uma mensagem...';

  @override
  String get chat_futureTimestampWarning =>
      'O horário desta mensagem está no futuro, então o relógio do remetente pode estar errado. Ela é exibida na ordem em que chegou.';

  @override
  String chat_messageTooLong(int maxBytes) {
    return 'Mensagem muito longa (máximo $maxBytes bytes).';
  }

  @override
  String get chat_messageCopied => 'Mensagem copiada';

  @override
  String get chat_messageDeleted => 'Mensagem excluída';

  @override
  String get chat_retryingMessage => 'Tentando novamente';

  @override
  String chat_retryingMessageWait(Object seconds) {
    return 'Aguarde $seconds segundos antes de reenviar';
  }

  @override
  String chat_retryCount(int current, int max) {
    return 'Tentativa $current/$max';
  }

  @override
  String get chat_sendGif => 'Enviar GIF';

  @override
  String get chat_shareMyLocation => 'Compartilhar minha localização';

  @override
  String get chat_noRadioLocation => 'O seu rádio não tem localização definida';

  @override
  String get chat_removeGif => 'Remover GIF';

  @override
  String get chat_cancelReply => 'Cancelar resposta';

  @override
  String get chat_receivedGif => 'GIF recebido';

  @override
  String get chat_reply => 'Responder';

  @override
  String get chat_addReaction => 'Adicionar Reação';

  @override
  String get chat_me => 'Eu';

  @override
  String get emojiCategorySmileys => 'Emojis';

  @override
  String get emojiCategoryGestures => 'Gestos';

  @override
  String get emojiCategoryHearts => 'Corações';

  @override
  String get emojiCategoryObjects => 'Objetos';

  @override
  String get gifPicker_title => 'Escolher um GIF';

  @override
  String get gifPicker_searchHint => 'Pesquisar GIFs...';

  @override
  String get gifPicker_poweredBy => 'Desenvolvido por GIPHY';

  @override
  String get gifPicker_noGifsFound => 'Nenhum GIF encontrado';

  @override
  String get gifPicker_failedLoad => 'Não foi possível carregar os GIFs';

  @override
  String get gifPicker_failedSearch => 'Falha na pesquisa de GIFs';

  @override
  String get gifPicker_noInternet => 'Sem conexão com a internet';

  @override
  String get debugLog_appTitle => 'Log de Depuração do Aplicativo';

  @override
  String get debugLog_bleTitle => 'Log de Depuração BLE';

  @override
  String get debugLog_copyLog => 'Copiar log';

  @override
  String get debugLog_clearLog => 'Limpar log';

  @override
  String get debugLog_copied => 'Log de depuração copiado';

  @override
  String get debugLog_bleCopied => 'Log BLE copiado';

  @override
  String get debugLog_noEntries => 'Ainda não existem logs de depuração.';

  @override
  String get debugLog_enableInSettings =>
      'Ativar o log de depuração do aplicativo nas configurações';

  @override
  String get debugLog_frames => 'Quadros';

  @override
  String get debugLog_rawLogRx => 'Log RX bruto';

  @override
  String get debugLog_noBleActivity => 'Ainda não há atividade BLE.';

  @override
  String debugFrame_length(int count) {
    return 'Comprimento do Quadro: $count bytes';
  }

  @override
  String debugFrame_command(String value) {
    return 'Comando: 0x$value';
  }

  @override
  String get debugFrame_textMessageHeader => 'Quadro de Mensagem de Texto:';

  @override
  String debugFrame_destinationPubKey(String pubKey) {
    return '- Chave pública de destino: $pubKey';
  }

  @override
  String debugFrame_timestamp(int timestamp) {
    return '- Carimbo de data/hora: $timestamp';
  }

  @override
  String debugFrame_flags(String value) {
    return '- Sinalizadores: 0x$value';
  }

  @override
  String debugFrame_textType(int type, String label) {
    return '- Tipo de Texto: $type ($label)';
  }

  @override
  String get debugFrame_textTypeCli => 'Interface de Linha de Comando';

  @override
  String get debugFrame_textTypePlain => 'Simples';

  @override
  String debugFrame_text(String text) {
    return '- Texto: \"$text\"';
  }

  @override
  String get debugFrame_hexDump => 'Dump hexadecimal:';

  @override
  String chat_hopsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'saltos',
      one: 'salto',
    );
    return '$count $_temp0';
  }

  @override
  String get chat_removePath => 'Remover caminho';

  @override
  String get chat_noPathHistoryYet =>
      'Ainda não há histórico de caminhos.\nEnvie uma mensagem para descobrir caminhos.';

  @override
  String get chat_pathCleared =>
      'Caminho limpo. A próxima mensagem redescobrirá a rota.';

  @override
  String get chat_fullPath => 'Caminho Completo';

  @override
  String get routing_title => 'Rotas';

  @override
  String get routing_modeAuto => 'Automático';

  @override
  String get routing_modeFlood => 'Inundação';

  @override
  String get routing_modeManual => 'Manual';

  @override
  String get routing_modeAutoHint =>
      'Seleciona automaticamente o melhor caminho conhecido e usa inundação quando nenhum é conhecido.';

  @override
  String get routing_modeFloodHint =>
      'Transmissão através de todos os repetidores. É a opção mais confiável, mas utiliza mais tempo de transmissão.';

  @override
  String get routing_modeManualHint =>
      'Sempre segue exatamente o caminho que você define.';

  @override
  String get routing_currentRoute => 'Rota atual';

  @override
  String get routing_directNoHops => 'Direto – sem saltos de repetidor';

  @override
  String get routing_noPathYet =>
      'Ainda não há caminho. A próxima mensagem será enviada por inundação até que uma rota seja descoberta.';

  @override
  String get routing_floodBroadcast =>
      'Transmissão através de todos os repetidores';

  @override
  String get routing_editPath => 'Editar caminho';

  @override
  String get routing_forgetPath => 'Esqueça o caminho';

  @override
  String get routing_knownPaths => 'Rotas conhecidas';

  @override
  String get routing_knownPathsHint =>
      'Toque em um caminho para alternar para ele.';

  @override
  String get routing_inUse => 'Em uso';

  @override
  String get routing_qualityStrong => 'Primeiro salto forte';

  @override
  String get routing_qualityGood => 'Primeiro salto bom';

  @override
  String get routing_qualityFair => 'Primeiro salto razoável';

  @override
  String get routing_qualityWorked => 'Já entregou';

  @override
  String get routing_qualityFlood => 'Ouvido via inundação';

  @override
  String get routing_qualityUntested => 'Não testado';

  @override
  String routing_lastWorked(String when) {
    return 'funcionou $when';
  }

  @override
  String get routing_neverWorked => 'nunca confirmado';

  @override
  String routing_deliveryCounts(int successes, int failures) {
    return '$successes entregues, $failures falharam';
  }

  @override
  String get routing_floodDelivery => 'Entrega por inundação';

  @override
  String get pathEditor_title => 'Criar Caminho';

  @override
  String pathEditor_hopCounter(int count) {
    return '$count de 64 saltos';
  }

  @override
  String get pathEditor_noHops =>
      'Ainda não há saltos. Toque nos repetidores abaixo para adicioná-los em ordem ou salve sem saltos para enviar diretamente.';

  @override
  String get pathEditor_addHops => 'Adicione os saltos em ordem';

  @override
  String get pathEditor_searchRepeaters => 'Encontrar repetidores';

  @override
  String get pathEditor_advancedHex => 'Avançado: caminho hexadecimal bruto';

  @override
  String get pathEditor_hexLabel => 'Prefixos hexadecimais';

  @override
  String get pathEditor_hexHelper =>
      'Dois caracteres hexadecimais por salto, separados por vírgulas.';

  @override
  String pathEditor_invalidTokens(String tokens) {
    return 'Inválido: $tokens';
  }

  @override
  String get pathEditor_tooManyHops => 'Máximo de 64 saltos';

  @override
  String get pathEditor_usePath => 'Utilize este caminho.';

  @override
  String get pathEditor_removeHop => 'Remover salto';

  @override
  String get pathEditor_unknownHop => 'Repetidor desconhecido';

  @override
  String get chat_pathSavedLocally =>
      'Salvo localmente. Conectar para sincronizar.';

  @override
  String get chat_pathDeviceConfirmed => 'Confirmado pelo dispositivo.';

  @override
  String get chat_pathDeviceNotConfirmed =>
      'Ainda não confirmado pelo dispositivo.';

  @override
  String get chat_type => 'Tipo';

  @override
  String get chat_path => 'Caminho';

  @override
  String get chat_viewPathOnMap => 'Ver o caminho no mapa';

  @override
  String get chat_publicKey => 'Chave Pública';

  @override
  String get chat_compressOutgoingMessages => 'Comprimir mensagens enviadas';

  @override
  String get chat_floodForced => 'Inundação (forçada)';

  @override
  String get chat_directForced => 'Direto (forçado)';

  @override
  String chat_hopsForced(int count) {
    return '$count saltos (forçado)';
  }

  @override
  String get chat_floodAuto => 'Inundação (automática)';

  @override
  String get chat_direct => 'Direto';

  @override
  String get chat_poiShared => 'Ponto de Interesse Compartilhado';

  @override
  String chat_unread(int count) {
    return 'Não lidas: $count';
  }

  @override
  String get chat_markAsUnread => 'Marcar como não lido';

  @override
  String get chat_newMessages => 'Novas mensagens';

  @override
  String get chat_today => 'Hoje';

  @override
  String get chat_yesterday => 'Ontem';

  @override
  String get chat_openLink => 'Abrir link?';

  @override
  String get chat_openLinkConfirmation =>
      'Deseja abrir este link no seu navegador?';

  @override
  String get chat_open => 'Abrir';

  @override
  String chat_couldNotOpenLink(String url) {
    return 'Não foi possível abrir o link: $url';
  }

  @override
  String get chat_invalidLink => 'Formato de link inválido';

  @override
  String get map_title => 'Mapa de Nós';

  @override
  String get map_searchHint => 'Pesquisar por nome ou ID do nó';

  @override
  String get map_activity => 'Atividade';

  @override
  String get map_online => 'Online';

  @override
  String get map_recent => 'Recente';

  @override
  String get map_stale => 'Desatualizado';

  @override
  String get map_visible => 'Visível';

  @override
  String get map_hidden => 'Escondido';

  @override
  String get map_centerOnNode => 'Centralizar no nó';

  @override
  String get map_centerOnMe => 'Centralizar na minha localização';

  @override
  String get map_details => 'Detalhes';

  @override
  String get map_noGps => 'Sem GPS';

  @override
  String get map_noResults => 'Nenhum nó encontrado';

  @override
  String get map_lineOfSight => 'Linha de visão';

  @override
  String get map_losScreenTitle => 'Linha de visão';

  @override
  String get map_noNodesWithLocation =>
      'Não existem nós com dados de localização.';

  @override
  String get map_noNodesLocationHint =>
      'Nenhum nó com uma localização recente. Amplie o filtro de tempo ou defina a sua localização nas Configurações.';

  @override
  String get map_nodesNeedGps =>
      'Os nós precisam compartilhar suas coordenadas GPS\npara aparecerem no mapa';

  @override
  String map_nodesCount(int count) {
    return 'Nós: $count';
  }

  @override
  String map_pinsCount(int count) {
    return 'Marcadores: $count';
  }

  @override
  String get map_chat => 'Chat';

  @override
  String get map_repeater => 'Repetidor';

  @override
  String get map_room => 'Sala';

  @override
  String get map_sensor => 'Sensor';

  @override
  String get map_pinDm => 'Marcador (DM)';

  @override
  String get map_pinPrivate => 'Marcador (Privado)';

  @override
  String get map_pinPublic => 'Marcador (Público)';

  @override
  String get map_lastSeen => 'Visto pela última vez';

  @override
  String get map_disconnectConfirm =>
      'Tem certeza de que deseja desconectar deste dispositivo?';

  @override
  String get map_from => 'De';

  @override
  String get map_source => 'Fonte';

  @override
  String get map_flags => 'Sinalizadores';

  @override
  String get map_type => 'Tipo';

  @override
  String get map_path => 'Rota';

  @override
  String get map_location => 'Localização';

  @override
  String get map_estLocation => 'Local. estimada';

  @override
  String get map_publicKey => 'Chave pública';

  @override
  String get map_publicKeyPrefixHint => 'ex.: ab12';

  @override
  String get map_shareMarkerHere => 'Compartilhar marcador aqui';

  @override
  String get map_setAsMyLocation => 'Definir como minha localização';

  @override
  String get map_pinLabel => 'Rótulo de marcador';

  @override
  String get map_label => 'Rótulo';

  @override
  String get map_labelUpdateHint =>
      'Usar o mesmo rótulo de antes atualizará o marcador para os destinatários do MeshCore Open.';

  @override
  String get map_pointOfInterest => 'Ponto de interesse';

  @override
  String get map_sendToContact => 'Enviar para o contato';

  @override
  String get map_sendToChannel => 'Enviar para o canal';

  @override
  String get map_noChannelsAvailable => 'Não existem canais disponíveis.';

  @override
  String get map_publicLocationShare =>
      'Compartilhamento público de localização';

  @override
  String map_publicLocationShareConfirm(String channelLabel) {
    return 'Você está prestes a compartilhar uma localização em $channelLabel. Este canal é público e qualquer pessoa com a PSK pode visualizá-lo.';
  }

  @override
  String get map_connectToShareMarkers =>
      'Conecte-se a um dispositivo para compartilhar marcadores';

  @override
  String get map_filterNodes => 'Filtrar Nós';

  @override
  String get map_nodeTypes => 'Tipos de Nó';

  @override
  String get map_chatNodes => 'Nós de Chat';

  @override
  String get map_repeaters => 'Repetidores';

  @override
  String get map_otherNodes => 'Outros Nós';

  @override
  String get map_showOverlaps => 'Sobreposições de Chaves de Repetidores';

  @override
  String get map_keyPrefix => 'Prefixo da Chave';

  @override
  String get map_filterByKeyPrefix => 'Filtrar por prefixo da chave';

  @override
  String get map_publicKeyPrefix => 'Prefixo de chave pública';

  @override
  String get map_markers => 'Marcadores';

  @override
  String get map_showSharedMarkers => 'Mostrar marcadores compartilhados';

  @override
  String get map_showGuessedLocations =>
      'Mostrar as localizações estimadas dos nós';

  @override
  String get map_clusterNodes => 'Agrupar os nós próximos';

  @override
  String get map_groupChip => 'Agrupar';

  @override
  String get map_clusterNodesSubtitle =>
      'Ao afastar o zoom, mostrar os nós próximos como um único círculo numerado';

  @override
  String get map_showDiscoveryContacts => 'Mostrar Contatos de Descoberta';

  @override
  String get map_guessedLocation => 'Localização estimada';

  @override
  String get map_lastSeenTime => 'Visto pela última vez em';

  @override
  String get map_sharedPin => 'Marcador compartilhado';

  @override
  String get map_sharedAt => 'Compartilhado';

  @override
  String get map_joinRoom => 'Junte-se à Sala';

  @override
  String get map_manageRepeater => 'Gerenciar Repetidor';

  @override
  String get map_manageServer => 'Gerenciar o servidor';

  @override
  String get map_tapToAdd => 'Toque nos nós para adicioná-los ao caminho.';

  @override
  String get map_runTrace => 'Executar Traçado de Caminho';

  @override
  String get map_runTraceWithReturnPath => 'Retornar pelo mesmo caminho.';

  @override
  String get map_removeLast => 'Remover Último';

  @override
  String get map_pathTraceCancelled => 'Rastreamento de caminho cancelado.';

  @override
  String get map_regionRequestPathMustEndWithTarget =>
      'A rota deve terminar no repetidor de destino.';

  @override
  String get map_wardrive => 'Wardrive';

  @override
  String get map_wardriveStart => 'Iniciar';

  @override
  String get map_wardriveStop => 'Parar';

  @override
  String get map_wardriveZeroHopDiscovery => 'Descoberta sem saltos';

  @override
  String get map_wardriveDiscoverySent =>
      'Solicitação de wardrive discovery enviada.';

  @override
  String get map_wardriveUploadCancelled => 'Envio do wardrive cancelado.';

  @override
  String map_wardriveDiscoveryFailed(String error) {
    return 'Falha no wardrive discovery: $error';
  }

  @override
  String map_wardriveRequests(int requests, int responses) {
    return 'Solicitações: $requests  Respostas: $responses';
  }

  @override
  String map_wardriveLastRequest(String time) {
    return 'Última solicitação: $time';
  }

  @override
  String get map_wardrivePhoneGpsNotUpdated =>
      'GPS do telefone: ainda não atualizado';

  @override
  String map_wardrivePhoneGpsError(String error) {
    return 'GPS do telefone: $error';
  }

  @override
  String map_wardrivePhoneGps(String latitude, String longitude) {
    return 'GPS do telefone: $latitude, $longitude';
  }

  @override
  String get map_wardriveNoResponses => 'Ainda não há respostas de discovery.';

  @override
  String get map_wardriveDataTooltip => 'Dados do wardrive';

  @override
  String get map_wardriveUploadData => 'Enviar os dados';

  @override
  String get map_wardriveManageUploadSites => 'Gerenciar os sites de envio';

  @override
  String get map_wardriveAutoUpload => 'Envio automático';

  @override
  String get map_wardriveReUpload => 'Enviar novamente';

  @override
  String get map_wardriveScreenWakelock => 'Manter a tela ligada';

  @override
  String get map_wardriveExport => 'Exportar';

  @override
  String get map_wardriveImport => 'Importar';

  @override
  String get map_wardriveAutoDiscovery => 'Discovery automático';

  @override
  String get map_wardriveSecondsSuffix => 's';

  @override
  String get map_wardriveSamplesNoNew => 'Não há novas amostras para enviar';

  @override
  String map_wardriveSamplesSaved(int count) {
    return 'Amostras salvas: $count';
  }

  @override
  String map_wardriveAutoDiscoveryError(String error) {
    return 'Discovery automático: $error';
  }

  @override
  String map_wardriveSampleSaveError(String error) {
    return 'Salvamento da amostra: $error';
  }

  @override
  String map_wardriveCoverageCells(int count) {
    return 'Células de cobertura: $count';
  }

  @override
  String get map_wardriveCoverageResolution => 'Detalhamento da cobertura';

  @override
  String get map_wardriveCoverageResolutionPrompt =>
      'Escolha o tamanho dos blocos de cobertura (tamanho = lado do bloco):';

  @override
  String get map_wardriveCoverageRegional => 'Regional';

  @override
  String get map_wardriveCoverageRegionalSubtitle => '~20 km (precisão 4)';

  @override
  String get map_wardriveCoverageCity => 'Nível de cidade';

  @override
  String get map_wardriveCoverageCitySubtitle => '~5 km (precisão 5)';

  @override
  String get map_wardriveCoverageNeighborhood => 'Bairro';

  @override
  String get map_wardriveCoverageNeighborhoodSubtitle => '~1,2 km (precisão 6)';

  @override
  String get map_wardriveCoverageStreet => 'Nível de rua';

  @override
  String get map_wardriveCoverageStreetSubtitle => '~153 m (precisão 7)';

  @override
  String get map_wardriveCoverageBuilding => 'Nível de edifício';

  @override
  String get map_wardriveCoverageBuildingSubtitle => '~38 m (precisão 8)';

  @override
  String get map_wardriveAutoUploadEnabled => 'Envio automático ativado.';

  @override
  String get map_wardriveAutoUploadDisabled => 'Envio automático desativado.';

  @override
  String get map_wardriveNoSamplesToUpload =>
      'Não há amostras do wardrive para enviar.';

  @override
  String get map_wardriveUploadingSamples => 'Enviando as amostras...';

  @override
  String map_wardriveUploadingTo(String site) {
    return 'Enviando para $site...';
  }

  @override
  String map_wardriveUploadBatch(int current, int total) {
    return 'Lote $current de $total';
  }

  @override
  String map_wardriveUploadSamplesProgress(int sent, int total) {
    return 'Enviando $sent de $total';
  }

  @override
  String map_wardriveUploadTarget(String site) {
    return 'Destino: $site';
  }

  @override
  String get map_wardriveUploadWaitingConnection => 'Aguardando a conexão';

  @override
  String get map_wardriveUploadConnectionEstablished =>
      'Conexão estabelecida, enviando';

  @override
  String get map_wardriveUploadProcessingServer =>
      'Dados enviados, o servidor está processando';

  @override
  String map_wardriveUploadServerResponse(int statusCode) {
    return 'O servidor processou os dados, resposta $statusCode';
  }

  @override
  String get map_wardriveUploadTimeoutTreatedAsSuccess =>
      'O envio excedeu o tempo limite; marcado como enviado para este site';

  @override
  String map_wardriveUploadServerError(int statusCode) {
    return 'Erro do servidor $statusCode';
  }

  @override
  String map_wardriveUploadRequestError(String error) {
    return 'Erro de envio: $error';
  }

  @override
  String map_wardriveUploadFailed(String error) {
    return 'Falha no envio do wardrive: $error';
  }

  @override
  String get map_wardriveUploadComplete => 'Envio concluído';

  @override
  String get map_wardriveUploadResults => 'Resultados do envio';

  @override
  String map_wardriveSamplesUploaded(int count) {
    return 'Amostras enviadas: $count';
  }

  @override
  String get map_wardriveSelectUploadSites =>
      'Selecione os sites para os quais enviar:';

  @override
  String get map_wardriveNoUploadSitesConfigured =>
      'Nenhum site de envio configurado';

  @override
  String get map_wardriveAddSite => 'Adicionar site';

  @override
  String get map_wardriveUploadSitesUpdated => 'Sites de envio atualizados.';

  @override
  String get map_wardriveAddUploadSite => 'Adicionar site de envio';

  @override
  String get map_wardriveEditUploadSite => 'Editar site de envio';

  @override
  String get map_wardriveNameLabel => 'Nome';

  @override
  String get map_wardriveUrlLabel => 'URL';

  @override
  String get map_wardriveUploadBatchSize => 'Tamanho do lote de envio';

  @override
  String map_wardriveUploadBatchSizeInvalid(int min, int max) {
    return 'Use um valor de $min a $max';
  }

  @override
  String get map_wardriveTreatTimeoutAsSuccess =>
      'Tratar o tempo limite como sucesso';

  @override
  String get map_wardriveNameRequired => 'O nome é obrigatório';

  @override
  String get map_wardriveNameExists => 'O nome já existe';

  @override
  String get map_wardriveValidUrlRequired => 'É necessário um URL válido';

  @override
  String get map_wardriveDeleteSite => 'Excluir site';

  @override
  String map_wardriveDeleteSiteConfirm(String name) {
    return 'Excluir «$name»?';
  }

  @override
  String get map_wardriveNoSamplesToExport =>
      'Não há amostras do wardrive para exportar.';

  @override
  String get map_wardriveExportShareText =>
      'amostras do wardrive do meshcore-open';

  @override
  String get map_wardriveSamplesExported =>
      'Amostras do wardrive exportadas em um arquivo JSON.';

  @override
  String map_wardriveExportFailed(String error) {
    return 'Falha na exportação do wardrive: $error';
  }

  @override
  String get map_wardriveImportSamples => 'Importar amostras do wardrive';

  @override
  String get map_wardriveImportHint => 'Cole aqui o JSON do wardrive exportado';

  @override
  String get map_wardriveNoNewSamplesImported =>
      'Nenhuma nova amostra do wardrive importada.';

  @override
  String map_wardriveSamplesImported(int count) {
    return 'Amostras do wardrive importadas: $count.';
  }

  @override
  String map_wardriveImportFailed(String error) {
    return 'Falha na importação do wardrive: $error';
  }

  @override
  String get map_wardriveNoSamplesToClear =>
      'Não há amostras do wardrive para limpar.';

  @override
  String get map_wardriveClearSamplesTitle => 'Limpar as amostras do wardrive?';

  @override
  String map_wardriveClearSamplesConfirm(int count) {
    return 'Isso excluirá $count amostras salvas deste dispositivo.';
  }

  @override
  String get map_wardriveSamplesCleared => 'Amostras do wardrive limpas.';

  @override
  String get map_wardriveRepNoLocation =>
      'O repetidor não informou sua localização';

  @override
  String map_wardriveDiscoveryWait(Object seconds) {
    return 'Aguarde $seconds segundos antes de tentar novamente';
  }

  @override
  String get map_wardriveFollowMe => 'Seguir minha localização';

  @override
  String get map_wardriveDeleteBlock => 'Excluir bloco';

  @override
  String get map_wardriveInBackground => 'Executar em segundo plano';

  @override
  String get map_wardriveContinuousGPS => 'Localização GPS contínua';

  @override
  String get map_wardriveShowRepeaterCoverage =>
      'Mostrar os blocos de cobertura';

  @override
  String get map_wardriveHideRepeaterCoverage =>
      'Ocultar os blocos de cobertura';

  @override
  String get mapCache_title => 'Cache de Mapa Offline';

  @override
  String get mapCache_selectAreaFirst =>
      'Selecione uma área para armazenar em cache primeiro';

  @override
  String get mapCache_noTilesToDownload =>
      'Não há tiles para baixar para esta área.';

  @override
  String get mapCache_downloadTilesTitle => 'Baixar tiles';

  @override
  String mapCache_downloadTilesPrompt(int count) {
    return 'Baixar $count tiles para uso offline?';
  }

  @override
  String get mapCache_downloadAction => 'Baixar';

  @override
  String mapCache_cachedTiles(int count) {
    return '$count tiles armazenados em cache';
  }

  @override
  String mapCache_cachedTilesWithFailed(int downloaded, int failed) {
    return '$downloaded tiles armazenados em cache ($failed falharam)';
  }

  @override
  String get mapCache_clearOfflineCacheTitle => 'Limpar cache offline';

  @override
  String get mapCache_clearOfflineCachePrompt =>
      'Remover todos os tiles de mapa em cache?';

  @override
  String get mapCache_offlineCacheCleared => 'Cache offline limpo';

  @override
  String get mapCache_noAreaSelected => 'Nenhuma área selecionada';

  @override
  String get mapCache_cacheArea => 'Área de Cache';

  @override
  String get mapCache_useCurrentView => 'Usar a Visualização Atual';

  @override
  String get mapCache_zoomRange => 'Intervalo de Zoom';

  @override
  String mapCache_estimatedTiles(int count) {
    return 'Tiles estimados: $count';
  }

  @override
  String mapCache_downloadedTiles(int completed, int total) {
    return 'Baixado $completed / $total';
  }

  @override
  String get mapCache_downloadTilesButton => 'Baixar Tiles';

  @override
  String get mapCache_clearCacheButton => 'Limpar Cache';

  @override
  String mapCache_failedDownloads(int count) {
    return 'Downloads com falha: $count';
  }

  @override
  String get mapCache_cachedTilesLabel => 'Tiles em cache';

  @override
  String get mapCache_cachedTileSummaryLabel => 'Resumo dos tiles em cache';

  @override
  String mapCache_bulkDownloadDisabledForSource(String source) {
    return 'Os downloads offline em massa estão desativados para $source.';
  }

  @override
  String mapCache_bulkDownloadDisabledInConfig(String source) {
    return 'Os downloads offline em massa para $source estão desativados nesta configuração do aplicativo.';
  }

  @override
  String mapCache_summarySource(String source) {
    return 'Fonte: $source';
  }

  @override
  String mapCache_summaryCachedTilesForSource(int count) {
    return 'Tiles em cache para a fonte: $count';
  }

  @override
  String mapCache_summaryCachedInSelection(int count) {
    return 'Em cache na área/zoom selecionado: $count';
  }

  @override
  String mapCache_summaryApproxCacheSize(String size) {
    return 'Tamanho aproximado do cache: $size';
  }

  @override
  String mapCache_boundsLabel(
    String north,
    String south,
    String east,
    String west,
  ) {
    return 'N $north, S $south, L $east, O $west';
  }

  @override
  String get time_justNow => 'Agora';

  @override
  String time_minutesAgo(int minutes) {
    return '$minutes minutos atrás';
  }

  @override
  String time_hoursAgo(int hours) {
    return '${hours}h atrás';
  }

  @override
  String time_daysAgo(int days) {
    return '$days dias atrás';
  }

  @override
  String get time_hour => 'hora';

  @override
  String get time_hours => 'horas';

  @override
  String get time_day => 'dia';

  @override
  String get time_days => 'dias';

  @override
  String get time_week => 'semana';

  @override
  String get time_weeks => 'semanas';

  @override
  String get time_month => 'mês';

  @override
  String get time_months => 'meses';

  @override
  String get time_minutes => 'minutos';

  @override
  String get time_allTime => 'Todo o período';

  @override
  String get dialog_disconnect => 'Desconectar';

  @override
  String get dialog_disconnectConfirm =>
      'Tem certeza de que deseja desconectar deste dispositivo?';

  @override
  String get login_repeaterLogin => 'Login no Repetidor';

  @override
  String get login_roomLogin => 'Login no Servidor de Sala';

  @override
  String get login_password => 'Senha';

  @override
  String get login_enterPassword => 'Insira a senha';

  @override
  String get login_showPassword => 'Mostrar senha';

  @override
  String get login_hidePassword => 'Esconder a senha';

  @override
  String get login_savePassword => 'Salvar senha';

  @override
  String get login_savePasswordSubtitle =>
      'A senha será armazenada com segurança neste dispositivo.';

  @override
  String get login_repeaterDescription =>
      'Insira a senha do repetidor para acesso de convidado ou de administrador.';

  @override
  String get login_roomDescription =>
      'Insira a senha da sala para acesso de convidado ou de administrador.';

  @override
  String get login_advanced => 'Avançado';

  @override
  String get login_routing => 'Rotas';

  @override
  String get login_routingMode => 'Modo de roteamento';

  @override
  String get login_autoUseSavedPath => 'Auto (usar caminho salvo)';

  @override
  String get login_forceFloodMode => 'Modo de Inundação Forçado';

  @override
  String get login_managePaths => 'Gerenciar Caminhos';

  @override
  String get login_login => 'Entrar';

  @override
  String login_attempt(int current, int max) {
    return 'Tentativa $current/$max';
  }

  @override
  String login_failed(String error) {
    return 'Login falhou: $error';
  }

  @override
  String get login_failedMessage =>
      'Falha no login. A senha está incorreta ou o repetidor está inacessível.';

  @override
  String get common_reload => 'Recarregar';

  @override
  String get common_clearSearch => 'Limpar pesquisa';

  @override
  String get path_currentPathLabel => 'Caminho atual';

  @override
  String get path_noRepeatersFound =>
      'Não foram encontrados repetidores ou servidores de sala.';

  @override
  String get repeater_management => 'Gerenciamento de Repetidor';

  @override
  String get room_management => 'Gerenciamento de Servidor de Sala';

  @override
  String get repeater_guest => 'Informações do Repetidor';

  @override
  String get room_guest => 'Informações do Servidor';

  @override
  String get repeater_managementTools => 'Ferramentas de Gerenciamento';

  @override
  String get repeater_guestTools => 'Ferramentas para Convidados';

  @override
  String get repeater_roleAdmin => 'ADMIN';

  @override
  String get repeater_roleGuest => 'CONVIDADO';

  @override
  String get repeater_status => 'Estado';

  @override
  String get repeater_statusSubtitle =>
      'Visualizar status do repetidor, estatísticas e vizinhos.';

  @override
  String get repeater_telemetry => 'Telemetria';

  @override
  String get repeater_telemetrySubtitle =>
      'Visualizar telemetria de sensores e estatísticas do sistema';

  @override
  String get repeater_cli => 'Interface de Linha de Comando';

  @override
  String get repeater_cliSubtitle => 'Enviar comandos ao repetidor';

  @override
  String get repeater_neighbors => 'Vizinhos';

  @override
  String get repeater_neighborsSubtitle => 'Visualizar vizinhos de salto zero.';

  @override
  String get repeater_settings => 'Configurações';

  @override
  String get repeater_settingsSubtitle => 'Configurar parâmetros do repetidor';

  @override
  String get repeater_clockSyncAfterLogin =>
      'Sincronização do relógio após o login';

  @override
  String get repeater_clockSyncAfterLoginSubtitle =>
      'Enviar automaticamente \"clock sync\" após um login bem-sucedido.';

  @override
  String get repeater_statusTitle => 'Status do Repetidor';

  @override
  String get repeater_routingMode => 'Modo de roteamento';

  @override
  String get repeater_refresh => 'Atualizar';

  @override
  String get repeater_statusRequestTimeout => 'Solicitação de status expirou.';

  @override
  String repeater_errorLoadingStatus(String error) {
    return 'Erro ao carregar o status: $error';
  }

  @override
  String get repeater_systemInformation => 'Informações do Sistema';

  @override
  String get repeater_battery => 'Bateria';

  @override
  String get repeater_clockAtLogin => 'Relógio (no login)';

  @override
  String get repeater_uptime => 'Tempo de atividade';

  @override
  String get repeater_queueLength => 'Comprimento da Fila';

  @override
  String get repeater_debugFlags => 'Sinalizadores de Depuração';

  @override
  String get repeater_radioStatistics => 'Estatísticas de Rádio';

  @override
  String get repeater_lastRssi => 'Último RSSI';

  @override
  String get repeater_lastSnr => 'Último SNR';

  @override
  String get repeater_noiseFloor => 'Nível de Ruído';

  @override
  String get repeater_txAirtime => 'Tempo no ar TX';

  @override
  String get repeater_rxAirtime => 'Tempo no ar RX';

  @override
  String get repeater_chanUtil => 'Utilização do canal';

  @override
  String get repeater_packetStatistics => 'Estatísticas de Pacote';

  @override
  String get repeater_sent => 'Enviado';

  @override
  String get repeater_received => 'Recebido';

  @override
  String get repeater_duplicates => 'Duplicatas';

  @override
  String get repeater_packetErrors => 'Erros de pacotes';

  @override
  String repeater_daysHoursMinsSecs(
    int days,
    int hours,
    int minutes,
    int seconds,
  ) {
    return '$days dias ${hours}h ${minutes}m ${seconds}s';
  }

  @override
  String repeater_packetTxTotal(int total, String flood, String direct) {
    return 'Total: $total, Inundação: $flood, Direto: $direct';
  }

  @override
  String repeater_packetRxTotal(int total, String flood, String direct) {
    return 'Total: $total, Inundação: $flood, Direto: $direct';
  }

  @override
  String repeater_duplicatesFloodDirect(String flood, String direct) {
    return 'Inundação: $flood, Direto: $direct';
  }

  @override
  String repeater_duplicatesTotal(int total) {
    return 'Total: $total';
  }

  @override
  String get repeater_settingsTitle => 'Configurações do Repetidor';

  @override
  String get repeater_basicSettings => 'Configurações Básicas';

  @override
  String get repeater_repeaterName => 'Nome do Repetidor';

  @override
  String get repeater_repeaterNameHelper => 'Nome de exibição deste repetidor';

  @override
  String get repeater_adminPassword => 'Senha de Administrador';

  @override
  String get repeater_adminPasswordHelper => 'Senha de acesso total';

  @override
  String get repeater_guestPassword => 'Senha de convidado';

  @override
  String get repeater_guestPasswordHelper => 'Senha de acesso somente leitura';

  @override
  String get repeater_radioSettings => 'Configurações de Rádio';

  @override
  String get repeater_frequencyMhz => 'Frequência (MHz)';

  @override
  String get repeater_frequencyHelper => '300-2500 MHz';

  @override
  String get repeater_txPower => 'Potência de TX';

  @override
  String get repeater_txPowerHelper => '1-30 dBm';

  @override
  String get repeater_bandwidth => 'Largura de banda';

  @override
  String get repeater_spreadingFactor => 'Fator de Dispersão';

  @override
  String get repeater_codingRate => 'Taxa de Codificação';

  @override
  String get repeater_locationSettings => 'Configurações de Localização';

  @override
  String get repeater_latitude => 'Latitude';

  @override
  String get repeater_latitudeHelper => 'Graus decimais (por exemplo, 37,7749)';

  @override
  String get repeater_longitude => 'Longitude';

  @override
  String get repeater_longitudeHelper =>
      'Graus decimais (por exemplo, -122,4194)';

  @override
  String get repeater_features => 'Recursos';

  @override
  String get repeater_packetForwarding => 'Encaminhamento de Pacotes';

  @override
  String get repeater_packetForwardingSubtitle =>
      'Habilitar o repetidor para encaminhar pacotes';

  @override
  String get repeater_guestAccess => 'Acesso de Convidado';

  @override
  String get repeater_guestAccessSubtitle =>
      'Permitir acesso de convidado somente leitura';

  @override
  String get repeater_privacyMode => 'Modo de Privacidade';

  @override
  String get repeater_privacyModeSubtitle =>
      'Esconder nome/localização em anúncios';

  @override
  String get repeater_advertisementSettings => 'Configurações de Anúncios';

  @override
  String get repeater_localAdvertInterval => 'Intervalo de Anúncio Local';

  @override
  String repeater_localAdvertIntervalMinutes(int minutes) {
    return '$minutes minutos';
  }

  @override
  String get repeater_floodAdvertInterval =>
      'Intervalo de Anúncio de Inundação';

  @override
  String repeater_floodAdvertIntervalHours(int hours) {
    return '$hours horas';
  }

  @override
  String get repeater_encryptedAdvertInterval =>
      'Intervalo de Anúncio Criptografado';

  @override
  String get repeater_dangerZone => 'Zona de Perigo';

  @override
  String get repeater_rebootRepeater => 'Reiniciar Repetidor';

  @override
  String get repeater_rebootRepeaterSubtitle =>
      'Reiniciar o dispositivo repetidor';

  @override
  String get repeater_rebootRepeaterConfirm =>
      'Tem certeza de que deseja reiniciar este repetidor?';

  @override
  String get repeater_regenerateIdentityKey => 'Regenerar Chave de Identidade';

  @override
  String get repeater_regenerateIdentityKeySubtitle =>
      'Gerar novo par de chaves pública/privada';

  @override
  String get repeater_regenerateIdentityKeyConfirm =>
      'Isso gerará uma nova identidade para o repetidor. Continuar?';

  @override
  String get repeater_eraseFileSystem => 'Excluir Sistema de Arquivos';

  @override
  String get repeater_eraseFileSystemSubtitle =>
      'Formatar o sistema de arquivos do repetidor';

  @override
  String get repeater_eraseFileSystemConfirm =>
      'AVISO: Isso apagará todos os dados no repetidor. Isso não pode ser desfeito!';

  @override
  String get repeater_eraseSerialOnly =>
      'Apagar está disponível apenas via console serial.';

  @override
  String repeater_commandSent(String command) {
    return 'Comando enviado: $command';
  }

  @override
  String repeater_errorSendingCommand(String error) {
    return 'Erro ao enviar comando: $error';
  }

  @override
  String get repeater_confirm => 'Confirmar';

  @override
  String get repeater_settingsSaved => 'Configurações salvas com sucesso';

  @override
  String get repeater_rxGain => 'Aumento do ganho do RX';

  @override
  String get repeater_rxGainHelper =>
      'Maior sensibilidade, maior consumo de corrente (apenas para SX1262/SX1268)';

  @override
  String get repeater_refreshRxGain => 'Atualizar ganho de RX aumentado';

  @override
  String get repeater_multiAcks => 'Múltiplas respostas de confirmação';

  @override
  String get repeater_multiAcksSubtitle =>
      'Confirme mensagens por múltiplos caminhos para uma melhor entrega.';

  @override
  String get repeater_refreshMultiAcks => 'Atualizar multi-ACKs';

  @override
  String get repeater_networkHealth => 'Saúde da rede';

  @override
  String get repeater_loopDetect => 'Detecção de loops';

  @override
  String get repeater_loopDetectHelper =>
      'Descartar pacotes de inundação que pareçam loops de roteamento.';

  @override
  String get repeater_loopDetectOff => 'Desligado';

  @override
  String get repeater_loopDetectMinimal => 'Mínimo';

  @override
  String get repeater_loopDetectModerate => 'Moderado';

  @override
  String get repeater_loopDetectStrict => 'Rígido';

  @override
  String get repeater_dutyCycle => 'Ciclo de operação';

  @override
  String get repeater_dutyCycleHelper =>
      'Porcentagem máxima de tempo de transmissão';

  @override
  String repeater_dutyCyclePercent(int percent) {
    return '$percent%';
  }

  @override
  String get repeater_ownerInfo => 'Informações sobre o operador';

  @override
  String get repeater_ownerInfoHelper =>
      'Metadados públicos para este repetidor';

  @override
  String get repeater_refreshOwnerInfo => 'Atualizar informações do operador';

  @override
  String get repeater_floodMax => 'Máximo de saltos de inundação';

  @override
  String get repeater_floodMaxHelper =>
      'Número máximo de saltos que um pacote de inundação pode percorrer (0-64)';

  @override
  String get repeater_advancedSettings => 'Avançado';

  @override
  String get repeater_advancedSettingsSubtitle =>
      'Controles de ajuste para operadores experientes';

  @override
  String get repeater_pathHashMode => 'Modo de hash de caminho';

  @override
  String get repeater_pathHashModeHelper =>
      'Bytes usados para codificar o ID deste repetidor nas tags de caminho de inundação/detecção de loop. 0=1 byte (256 IDs, até 64 saltos), 1=2 bytes (65.000 IDs, até 32 saltos), 2=3 bytes (16 milhões de IDs, até 21 saltos). O firmware anterior à v1.14 sempre usava caminhos de 1 byte; v1.14 e versões mais recentes podem ser configuradas para caminhos de 2 ou 3 bytes.';

  @override
  String get repeater_keySettings => 'Alterar as chaves de identidade';

  @override
  String get repeater_keySettingsSubtitle =>
      'Alterar o par de chaves pública/privada';

  @override
  String get repeater_prvKey => 'Chave privada';

  @override
  String get repeater_prvKeyHelper =>
      'Uma nova chave privada para o repetidor, uma string hexadecimal de 128 caracteres.';

  @override
  String get repeater_generatePrvKey => 'Gerar um par de chaves aleatório';

  @override
  String get repeater_stopGeneratingPrvKey =>
      'Interromper a busca do par de chaves';

  @override
  String get repeater_pubKey => 'Chave pública';

  @override
  String get repeater_pubKeyHelper =>
      'Esta é a chave pública correspondente à chave privada gerada. Ela não pode ser definida diretamente.';

  @override
  String get repeater_pubKeyPrefix => 'Prefixo desejado';

  @override
  String repeater_pubKeyPrefixHelper(int tries) {
    return 'Procurar uma chave pública que comece com estes dígitos hexadecimais. Tentativas previstas: $tries.';
  }

  @override
  String get repeater_txDelay => 'Atraso de TX de inundação';

  @override
  String get repeater_txDelayHelper =>
      'Intervalo de retransmissão para tráfego de inundação, como multiplicador do tempo de transmissão do pacote (0-2, padrão 0,5). Quanto maior, menos colisões, mas entrega mais lenta.';

  @override
  String get repeater_directTxDelay => 'Atraso de TX direto';

  @override
  String get repeater_directTxDelayHelper =>
      'Intervalo de retransmissão para tráfego direto (não por inundação), como um multiplicador do tempo de transmissão do pacote (0-2, padrão 0,3).';

  @override
  String get repeater_intThresh => 'Limite de interferência';

  @override
  String get repeater_intThreshHelper =>
      'O limite é definido para o nível de ruído do rádio, de modo que ele rejeite interferências acima desse nível. 0 desativa – aumente apenas se você observar erros de RX em uma faixa de frequência com ruído.';

  @override
  String get repeater_agcResetInterval => 'Intervalo de reinicialização do AGC';

  @override
  String get repeater_agcResetIntervalHelper =>
      'Com que frequência redefinir o controle automático de ganho do rádio para recuperar de um estado em que o ganho está travado. Segundos, reduzidos a um múltiplo de 4. 0 desativa as redefinições periódicas.';

  @override
  String get repeater_actionsTitle => 'Ações';

  @override
  String get repeater_sendAdvert => 'Enviar anúncio de inundação';

  @override
  String get repeater_sendAdvertSubtitle =>
      'Transmita um anúncio de inundação pela rede.';

  @override
  String get repeater_sendAdvertZeroHop => 'Enviar anúncio sem intermediários';

  @override
  String get repeater_sendAdvertZeroHopSubtitle =>
      'Transmita um anúncio de um único salto (sem repetidores).';

  @override
  String get repeater_clockSync => 'Sincronize o relógio agora';

  @override
  String get repeater_clockSyncSubtitle =>
      'Envie a hora do seu telefone para o repetidor.';

  @override
  String repeater_actionSucceeded(String action) {
    return '$action concluído com sucesso';
  }

  @override
  String repeater_actionFailed(String action, String error) {
    return '$action falhou: $error';
  }

  @override
  String get repeater_settingsSavedRebootNeeded =>
      'Configurações salvas — reinicie o repetidor para aplicar as alterações.';

  @override
  String repeater_settingsPartialFailure(String failures) {
    return 'Algumas configurações falharam: $failures';
  }

  @override
  String repeater_errorSavingSettings(String error) {
    return 'Erro ao salvar as configurações: $error';
  }

  @override
  String get repeater_refreshBasicSettings => 'Atualizar Configurações Básicas';

  @override
  String get repeater_refreshRadioSettings =>
      'Atualizar Configurações de Rádio';

  @override
  String get repeater_refreshTxPower => 'Atualizar potência de TX';

  @override
  String get repeater_refreshPacketForwarding =>
      'Atualizar Encaminhamento de Pacotes';

  @override
  String get repeater_refreshGuestAccess => 'Atualizar Acesso de Convidados';

  @override
  String get repeater_refreshPrivacyMode => 'Atualizar Modo Privacidade';

  @override
  String get repeater_refreshAll => 'Atualizar tudo';

  @override
  String get repeater_settingsNotLoaded =>
      'As configurações ainda não foram carregadas deste repetidor.';

  @override
  String get repeater_settingsLoadIncomplete =>
      'Algumas configurações não puderam ser carregadas. Use os botões de atualização para tentar novamente.';

  @override
  String repeater_refreshed(String label) {
    return '$label atualizado';
  }

  @override
  String repeater_errorRefreshing(String label) {
    return 'Erro ao atualizar $label';
  }

  @override
  String get repeater_cliTitle => 'CLI do Repetidor';

  @override
  String get repeater_debugNextCommand => 'Depurar Próximo Comando';

  @override
  String get repeater_commandHelp => 'Ajuda';

  @override
  String get repeater_clearHistory => 'Limpar Histórico';

  @override
  String get repeater_noCommandsSent => 'Ainda não foram enviados comandos.';

  @override
  String get repeater_typeCommandOrUseQuick =>
      'Digite um comando abaixo ou use comandos rápidos';

  @override
  String get repeater_enterCommandHint => 'Insira o comando...';

  @override
  String get repeater_previousCommand => 'Comando anterior';

  @override
  String get repeater_nextCommand => 'Próximo comando';

  @override
  String get repeater_enterCommandFirst => 'Insira um comando primeiro';

  @override
  String get repeater_cliCommandFrameTitle => 'Frame de Comando CLI';

  @override
  String repeater_cliCommandError(String error) {
    return 'Erro: $error';
  }

  @override
  String get repeater_cliQuickGetName => 'Obter Nome';

  @override
  String get repeater_cliQuickGetRadio => 'Obter Rádio';

  @override
  String get repeater_cliQuickGetTx => 'Obter TX';

  @override
  String get repeater_cliQuickNeighbors => 'Vizinhos';

  @override
  String get repeater_cliQuickVersion => 'Versão';

  @override
  String get repeater_cliQuickAdvertise => 'Anunciar';

  @override
  String get repeater_cliQuickClock => 'Relógio';

  @override
  String get repeater_cliQuickClockSync => 'Sincronização do Relógio';

  @override
  String get repeater_cliQuickDiscovery => 'Descobrir Vizinhos';

  @override
  String get repeater_cliHelpAdvert => 'Envia um pacote de anúncios';

  @override
  String get repeater_cliHelpReboot =>
      'Reinicia o dispositivo. (note, você pode obter \'Timeout\' que é normal)';

  @override
  String get repeater_cliHelpClock =>
      'Exibe a hora atual de acordo com o relógio do dispositivo.';

  @override
  String get repeater_cliHelpPassword =>
      'Define uma nova senha de administrador para o dispositivo.';

  @override
  String get repeater_cliHelpVersion =>
      'Mostra a versão do dispositivo e a data de compilação do firmware.';

  @override
  String get repeater_cliHelpClearStats =>
      'Reseta vários contadores de estatísticas para zero.';

  @override
  String get repeater_cliHelpSetAf => 'Define o fator de tempo no ar.';

  @override
  String get repeater_cliHelpSetTx =>
      'Define a potência de transmissão LoRa em dBm (reinicie para aplicar).';

  @override
  String get repeater_cliHelpSetRepeat =>
      'Habilita ou desabilita a função de repetidor deste nó.';

  @override
  String get repeater_cliHelpSetAllowReadOnly =>
      '(Servidor de sala) Se \'on\', então o login com senha em branco será permitido, mas não poderá postar na sala. (somente leitura)';

  @override
  String get repeater_cliHelpSetFloodMax =>
      'Define o número máximo de saltos de pacotes de inundação de entrada (se for >= máximo, o pacote não é encaminhado)';

  @override
  String get repeater_cliHelpSetIntThresh =>
      'Define o Limite de Interferência (em dB). O valor padrão é 14. Defina como 0 para desativar a detecção de interferência de canal.';

  @override
  String get repeater_cliHelpSetAgcResetInterval =>
      'Define o intervalo para resetar o Controlador de Ganho Automático. Defina como 0 para desativar.';

  @override
  String get repeater_cliHelpSetMultiAcks =>
      'Habilita ou desabilita a funcionalidade de \"double ACKs\".';

  @override
  String get repeater_cliHelpSetAdvertInterval =>
      'Define o intervalo do timer em minutos para enviar um pacote de anúncio local (sem salto). Defina como 0 para desativar.';

  @override
  String get repeater_cliHelpSetFloodAdvertInterval =>
      'Define o intervalo do timer em horas para enviar um pacote de anúncio de inundação. Defina como 0 para desativar.';

  @override
  String get repeater_cliHelpSetGuestPassword =>
      'Define/atualiza a senha do convidado. (para repetidores, os logins de convidados podem enviar a solicitação \"Get Stats\")';

  @override
  String get repeater_cliHelpSetName => 'Define o nome do anúncio.';

  @override
  String get repeater_cliHelpSetLat =>
      'Define a latitude do mapa de anúncios. (graus decimais)';

  @override
  String get repeater_cliHelpSetLon =>
      'Define a longitude do mapa de anúncios. (graus decimais)';

  @override
  String get repeater_cliHelpSetRadio =>
      'Define completamente novos parâmetros de rádio e salva nas preferências. Requer um comando \"reboot\" para aplicar.';

  @override
  String get repeater_cliHelpSetRxDelay =>
      'Define (experimental) a base (deve ser > 1 para ter efeito) para aplicar um pequeno atraso aos pacotes recebidos, com base na força/pontuação do sinal. Defina como 0 para desativar.';

  @override
  String get repeater_cliHelpSetTxDelay =>
      'Define um fator multiplicado pelo tempo no ar de um pacote em modo de inundação e por um sistema de slots aleatórios, para atrasar seu encaminhamento. (para diminuir a probabilidade de colisões)';

  @override
  String get repeater_cliHelpSetDirectTxDelay =>
      'Igual a txdelay, mas para aplicar um atraso aleatório ao encaminhamento de pacotes em modo direto.';

  @override
  String get repeater_cliHelpSetBridgeEnabled => 'Ativar/Desativar ponte.';

  @override
  String get repeater_cliHelpSetBridgeDelay =>
      'Definir atraso antes de retransmitir pacotes.';

  @override
  String get repeater_cliHelpSetBridgeSource =>
      'Escolha se a ponte retransmitirá pacotes recebidos ou pacotes transmitidos.';

  @override
  String get repeater_cliHelpSetBridgeBaud =>
      'Definir a taxa de baud para as pontes rs232.';

  @override
  String get repeater_cliHelpSetBridgeSecret =>
      'Definir segredo de ponte para pontes espnow.';

  @override
  String get repeater_cliHelpSetAdcMultiplier =>
      'Define um fator personalizado para ajustar a voltagem de bateria relatada (apenas suportado em placas selecionadas).';

  @override
  String get repeater_cliHelpTempRadio =>
      'Define parâmetros de rádio temporários para o número especificado de minutos, revertendo para os parâmetros de rádio originais posteriormente. (não salva nas preferências).';

  @override
  String get repeater_cliHelpSetPerm =>
      'Modifica o ACL. Remove a entrada correspondente (pelo prefixo de pubkey) se \"permissions\" for zero. Adiciona uma nova entrada se o pubkey-hex for de comprimento total e não estiver atualmente no ACL. Atualiza a entrada por correspondência de prefixo de pubkey. Os bits de permissão variam conforme o papel do firmware, mas os 2 bits inferiores são: 0 (Convidado), 1 (Somente leitura), 2 (Leitura e escrita), 3 (Admin)';

  @override
  String get repeater_cliHelpGetBridgeType =>
      'Obtém o tipo de ponte: none, rs232, espnow';

  @override
  String get repeater_cliHelpLogStart =>
      'Inicia o registro de pacotes no sistema de arquivos.';

  @override
  String get repeater_cliHelpLogStop =>
      'Interrompe o registro de pacotes no sistema de arquivos.';

  @override
  String get repeater_cliHelpLogErase =>
      'Apaga os logs de pacotes do sistema de arquivos.';

  @override
  String get repeater_cliHelpNeighbors =>
      'Mostra uma lista de outros nós de repetição ouvidos através de anúncios zero-hop. Cada linha é id-prefixo-hexadecimal:timestamp:snr-vezes-4';

  @override
  String get repeater_cliHelpNeighborRemove =>
      'Remove a primeira entrada correspondente (por prefixo de chave pública (hexadecimal)) da lista de vizinhos.';

  @override
  String get repeater_cliHelpRegion =>
      '(apenas serial) Lista todas as regiões definidas e as permissões de inundação atuais.';

  @override
  String get repeater_cliHelpRegionLoad =>
      'NOTA: isto é uma invocação multi-comando especial. Cada comando subsequente é um nome de região (indentado com espaços para indicar a hierarquia pai, com no mínimo um espaço). Terminado enviando uma linha em branco/comando.';

  @override
  String get repeater_cliHelpRegionGet =>
      'Procura região com o prefixo de nome dado (ou \"*\" para o escopo global). Responde com \"-> nome-região (nome-pai) \'F\'\"';

  @override
  String get repeater_cliHelpRegionPut =>
      'Adiciona ou atualiza uma definição de região com o nome fornecido.';

  @override
  String get repeater_cliHelpRegionRemove =>
      'Remove uma definição de região com o nome fornecido. (deve corresponder exatamente e não ter regiões filhas)';

  @override
  String get repeater_cliHelpRegionAllowf =>
      'Define a permissão de inundação (\'F\'lood) para a região especificada. (\'*\' para o escopo global/legado)';

  @override
  String get repeater_cliHelpRegionDenyf =>
      'Remove a permissão de inundação (\'F\'lood) para a região especificada. (NOTA: neste momento NÃO é aconselhável usar isso no escopo global/legado!!)';

  @override
  String get repeater_cliHelpRegionHome =>
      'Responde com a região \'home\' atual. (Ainda não é aplicada em nenhum lugar, reservada para o futuro)';

  @override
  String get repeater_cliHelpRegionHomeSet => 'Define a região \'home\'.';

  @override
  String get repeater_cliHelpRegionSave =>
      'Persiste a lista/mapa de regiões para o armazenamento.';

  @override
  String get repeater_cliHelpGps =>
      'Mostra o status do GPS. Quando o GPS estiver desligado, responde apenas com \"off\", se estiver ligado, responde com \"on\", status, fix, contagem de satélites.';

  @override
  String get repeater_cliHelpGpsOnOff => 'Alterna o estado de energia do GPS.';

  @override
  String get repeater_cliHelpGpsSync =>
      'Sincroniza o tempo do nó com o relógio GPS.';

  @override
  String get repeater_cliHelpGpsSetLoc =>
      'Define a posição do nó para as coordenadas GPS e salva as preferências.';

  @override
  String get repeater_cliHelpGpsAdvert =>
      'Mostra a configuração de anúncio da localização do nó:\n- none: não incluir a localização nos anúncios\n- share: compartilhar a localização GPS (do SensorManager)\n- prefs: anunciar a localização armazenada nas preferências';

  @override
  String get repeater_cliHelpGpsAdvertSet =>
      'Define a configuração do anúncio de localização.';

  @override
  String get repeater_commandsListTitle => 'Lista de Comandos';

  @override
  String get repeater_commandsListNote =>
      'NOTA: para os diversos comandos \"set...\", também existe um comando \"get...\".';

  @override
  String get repeater_general => 'Geral';

  @override
  String get repeater_settingsCategory => 'Configurações';

  @override
  String get repeater_bridge => 'Ponte';

  @override
  String get repeater_logging => 'Registro';

  @override
  String get repeater_neighborsRepeaterOnly => 'Vizinhos (apenas repetidor)';

  @override
  String get repeater_regionManagementRepeaterOnly =>
      'Gerenciamento de Região (Apenas Repetidor)';

  @override
  String get repeater_regionNote =>
      'Os comandos de região foram introduzidos para gerenciar definições e permissões de região.';

  @override
  String get repeater_gpsManagement => 'Gerenciamento GPS';

  @override
  String get repeater_gpsNote =>
      'O comando GPS foi introduzido para gerenciar tópicos relacionados à localização.';

  @override
  String get repeater_getCategory => 'Obter valores';

  @override
  String get repeater_powerMgmt => 'Gerenciamento de energia';

  @override
  String get repeater_sensors => 'Sensores';

  @override
  String get repeater_cliHelpPowerOff =>
      'Desliga o dispositivo. (não se espera resposta)';

  @override
  String get repeater_cliHelpClkReboot =>
      'Redefine o relógio para uma data conhecida e reinicia o dispositivo.';

  @override
  String get repeater_cliHelpAdvertZeroHop =>
      'Envia um anúncio sem \"salto\" (apenas para vizinhos próximos).';

  @override
  String get repeater_cliHelpStartOta =>
      'Inicia uma atualização de firmware via rádio em placas compatíveis.';

  @override
  String get repeater_cliHelpTime =>
      'Define o relógio do dispositivo para os segundos da época Unix especificados. O relógio não pode retroceder.';

  @override
  String get repeater_cliHelpBoard =>
      'Indica o fabricante da placa / identificador de hardware.';

  @override
  String get repeater_cliHelpDiscoverNeighbors =>
      'Envia uma solicitação de descoberta de nós para os vizinhos próximos. (Apenas para repetidores)';

  @override
  String get repeater_cliHelpPowersaving =>
      'Indica se o modo de economia de energia está ativado ou desativado.';

  @override
  String get repeater_cliHelpPowersavingOnOff =>
      'Habilita ou desabilita o modo de economia de energia (quando disponível).';

  @override
  String get repeater_cliHelpErase =>
      '(Apenas serial) Formata o sistema de arquivos do dispositivo. Apaga todas as configurações e contatos.';

  @override
  String get repeater_cliHelpSetDutyCycle =>
      'Define o ciclo de transmissão máximo permitido como uma porcentagem (1-100). Ajusta internamente o fator de tempo de transmissão.';

  @override
  String get repeater_cliHelpSetPrvKey =>
      'Substitui a chave privada de identificação do dispositivo. É necessário reiniciar o dispositivo para aplicar a alteração. Gera uma nova chave pública.';

  @override
  String get repeater_cliHelpSetRadioRxGain =>
      '(Apenas para SX126x) Alterna o ganho amplificado do receptor (RX) para melhorar a sensibilidade, com maior consumo de corrente.';

  @override
  String get repeater_cliHelpSetOwnerInfo =>
      'Define a string com as informações de contato do proprietário, que será incluída nos anúncios. Utilize \'|\' para indicar novas linhas.';

  @override
  String get repeater_cliHelpSetPathHashMode =>
      'Define o modo de hash de caminho: quantos bytes do hash de cada salto entram no caminho dos pacotes de inundação enviados por este nó. 0 = 1 byte, 1 = 2 bytes, 2 = 3 bytes.';

  @override
  String get repeater_cliHelpSetLoopDetect =>
      'Define o nível de sensibilidade para a detecção de loops de roteamento: off, minimal, moderate ou strict.';

  @override
  String get repeater_cliHelpSetFreq =>
      '(Apenas serial) Define rapidamente apenas a frequência. É necessário reiniciar o dispositivo. Recomenda-se usar \"set radio\" para definir todos os parâmetros do rádio.';

  @override
  String get repeater_cliHelpSetBridgeChannel =>
      '(Apenas para a ponte ESPNow) Define o canal Wi-Fi (1-14) utilizado pela ponte.';

  @override
  String get repeater_cliHelpGetName => 'Mostra o nome configurado do nó.';

  @override
  String get repeater_cliHelpGetRole =>
      'Mostra o papel do firmware (Repetidor, Servidor de Sala, etc.).';

  @override
  String get repeater_cliHelpGetPublicKey =>
      'Exibe a chave pública do dispositivo.';

  @override
  String get repeater_cliHelpGetPrvKey =>
      '(Apenas serial) Exibe a chave privada do dispositivo. Trate-a como uma informação confidencial.';

  @override
  String get repeater_cliHelpGetRepeat =>
      'Indica se a função de encaminhamento de pacotes (função de repetidor) está ativada ou desativada.';

  @override
  String get repeater_cliHelpGetTx => 'Mostra a potência atual em dBm.';

  @override
  String get repeater_cliHelpGetFreq =>
      'Mostra a frequência de rádio configurada em MHz.';

  @override
  String get repeater_cliHelpGetRadio =>
      'Exibe todos os parâmetros de rádio: frequência, largura de banda, fator de espalhamento, taxa de codificação.';

  @override
  String get repeater_cliHelpGetRadioRxGain =>
      '(Apenas para SX126x) Mostra o estado do ganho amplificado do RX.';

  @override
  String get repeater_cliHelpGetAf =>
      'Mostra o fator de tempo de transmissão atual.';

  @override
  String get repeater_cliHelpGetDutyCycle =>
      'Mostra o ciclo de trabalho atual permitido em porcentagem.';

  @override
  String get repeater_cliHelpGetIntThresh =>
      'Mostra o limite de interferência do canal em dB.';

  @override
  String get repeater_cliHelpGetAgcResetInterval =>
      'Mostra o intervalo de reinicialização do AGC em segundos.';

  @override
  String get repeater_cliHelpGetMultiAcks =>
      'Indica se o modo de confirmação dupla está ativado (1) ou desativado (0).';

  @override
  String get repeater_cliHelpGetAllowReadOnly =>
      'Indica se o acesso somente de leitura para os convidados está habilitado.';

  @override
  String get repeater_cliHelpGetAdvertInterval =>
      'Mostra o intervalo de anúncio local em minutos.';

  @override
  String get repeater_cliHelpGetFloodAdvertInterval =>
      'Mostra o intervalo de anúncio de inundação em horas.';

  @override
  String get repeater_cliHelpGetGuestPassword =>
      'Mostra a senha de convidado configurada.';

  @override
  String get repeater_cliHelpGetLat => 'Mostra a latitude configurada.';

  @override
  String get repeater_cliHelpGetLon => 'Mostra a longitude configurada.';

  @override
  String get repeater_cliHelpGetRxDelay => 'Mostra o valor base do rxdelay.';

  @override
  String get repeater_cliHelpGetTxDelay =>
      'Mostra o fator de atraso em modo de inundação.';

  @override
  String get repeater_cliHelpGetDirectTxDelay =>
      'Mostra o fator de atraso direto.';

  @override
  String get repeater_cliHelpGetFloodMax =>
      'Mostra o número máximo de saltos de inundação.';

  @override
  String get repeater_cliHelpGetOwnerInfo =>
      'Exibe a string de informações de contato do proprietário.';

  @override
  String get repeater_cliHelpGetPathHashMode =>
      'Mostra o modo de hash de caminho (0/1/2).';

  @override
  String get repeater_cliHelpGetLoopDetect =>
      'Mostra a sensibilidade da detecção de loops.';

  @override
  String get repeater_cliHelpGetAcl =>
      '(Apenas serial) Lista as entradas de controle de acesso em um repetidor.';

  @override
  String get repeater_cliHelpGetBridgeEnabled =>
      'Indica se a ponte está habilitada.';

  @override
  String get repeater_cliHelpGetBridgeDelay =>
      'Mostra o atraso da ponte em milissegundos.';

  @override
  String get repeater_cliHelpGetBridgeSource =>
      'Indica se a ponte registra pacotes RX ou TX.';

  @override
  String get repeater_cliHelpGetBridgeBaud =>
      '(Apenas para ponte RS232) Exibe a taxa de baud da ponte.';

  @override
  String get repeater_cliHelpGetBridgeChannel =>
      '(Apenas para a ponte ESPNow) Exibe o canal WiFi da ponte.';

  @override
  String get repeater_cliHelpGetBridgeSecret =>
      '(Apenas para a ponte ESPNow) Exibe o segredo compartilhado pela ponte.';

  @override
  String get repeater_cliHelpGetBootloaderVer =>
      '(Apenas para NRF52) Exibe a versão do bootloader.';

  @override
  String get repeater_cliHelpGetAdcMultiplier =>
      'Mostra o multiplicador do ADC (escalonamento da tensão da bateria).';

  @override
  String get repeater_cliHelpGetPwrMgtSupport =>
      'Indica se a placa possui suporte para gerenciamento de energia.';

  @override
  String get repeater_cliHelpGetPwrMgtSource =>
      'Indica a fonte de energia atual: externa ou bateria.';

  @override
  String get repeater_cliHelpGetPwrMgtBootReason =>
      'Mostra as razões mais recentes para a reinicialização e desligamento.';

  @override
  String get repeater_cliHelpGetPwrMgtBootMv =>
      'Mostra a tensão da bateria no momento da inicialização, em milivolts (mV).';

  @override
  String get repeater_cliHelpSensorGet =>
      'Lê uma configuração de sensor personalizada através de uma chave.';

  @override
  String get repeater_cliHelpSensorSet =>
      'Cria uma configuração personalizada para um sensor.';

  @override
  String get repeater_cliHelpSensorList =>
      'Lista todas as configurações de sensores personalizadas, organizadas em páginas a partir de um índice de início opcional.';

  @override
  String get repeater_cliHelpRegionDefault =>
      'Mostra o escopo de região padrão atual.';

  @override
  String get repeater_cliHelpRegionDefaultSet =>
      'Define o escopo regional padrão. Use \"<null>\" para limpar.';

  @override
  String get repeater_cliHelpRegionListAllowed =>
      'Lista as regiões que permitem tráfego de inundação.';

  @override
  String get repeater_cliHelpRegionListDenied =>
      'Lista as regiões que negam tráfego de inundação.';

  @override
  String get repeater_cliHelpStatsPackets =>
      '(Apenas serial) Apresenta estatísticas em nível de pacotes.';

  @override
  String get repeater_cliHelpStatsRadio =>
      '(Apenas serial) Exibe estatísticas de rádio.';

  @override
  String get repeater_cliHelpStatsCore =>
      '(Apenas serial) Exibe estatísticas do núcleo do firmware.';

  @override
  String get telemetry_receivedData => 'Dados de Telemetria Recebidos';

  @override
  String get telemetry_requestTimeout =>
      'Solicitação de telemetria expirou o tempo.';

  @override
  String telemetry_errorLoading(String error) {
    return 'Erro ao carregar a telemetria: $error';
  }

  @override
  String get telemetry_noData => 'Não estão disponíveis dados de telemetria.';

  @override
  String telemetry_channelTitle(int channel) {
    return 'Canal $channel';
  }

  @override
  String get telemetry_batteryLabel => 'Bateria';

  @override
  String get telemetry_voltageLabel => 'Tensão';

  @override
  String get telemetry_mcuTemperatureLabel => 'Temperatura do MCU';

  @override
  String get telemetry_temperatureLabel => 'Temperatura';

  @override
  String get telemetry_currentLabel => 'Corrente';

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
  String get telemetry_digitalInputLabel => 'Entrada digital';

  @override
  String get telemetry_digitalOutputLabel => 'Saída digital';

  @override
  String get telemetry_analogInputLabel => 'Entrada analógica';

  @override
  String get telemetry_analogOutputLabel => 'Saída analógica';

  @override
  String get telemetry_genericLabel => 'Sensor genérico';

  @override
  String get telemetry_luminosityLabel => 'Luminosidade';

  @override
  String get telemetry_presenceLabel => 'Presença';

  @override
  String get telemetry_humidityLabel => 'Umidade';

  @override
  String get telemetry_accelerometerLabel => 'Acelerômetro';

  @override
  String get telemetry_pressureLabel => 'Pressão';

  @override
  String get telemetry_altitudeLabel => 'Altitude';

  @override
  String get telemetry_frequencyLabel => 'Frequência';

  @override
  String get telemetry_percentageLabel => 'Porcentagem';

  @override
  String get telemetry_concentrationLabel => 'Concentração';

  @override
  String get telemetry_powerLabel => 'Potência';

  @override
  String get telemetry_calculatedPowerLabel => 'Potência calculada (V × I)';

  @override
  String get telemetry_distanceLabel => 'Distância';

  @override
  String get telemetry_energyLabel => 'Energia';

  @override
  String get telemetry_directionLabel => 'Direção';

  @override
  String get telemetry_timeLabel => 'Hora';

  @override
  String get telemetry_gyrometerLabel => 'Girômetro';

  @override
  String get telemetry_colourLabel => 'Cor';

  @override
  String get telemetry_gpsLabel => 'GPS';

  @override
  String get telemetry_switchLabel => 'Interruptor';

  @override
  String get telemetry_polylineLabel => 'Polilinha';

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
  String get telemetry_autoFetchQuantity => 'Número de solicitações';

  @override
  String get telemetry_error => 'Não foi possível obter os dados';

  @override
  String get neighbors_receivedData => 'Dados dos Vizinhos Recebidos';

  @override
  String get neighbors_requestTimedOut => 'A solicitação de vizinhos expirou.';

  @override
  String neighbors_errorLoading(String error) {
    return 'Erro ao carregar vizinhos: $error';
  }

  @override
  String get neighbors_repeatersNeighbors => 'Vizinhos do repetidor';

  @override
  String get neighbors_noData => 'Não estão disponíveis dados de vizinhos.';

  @override
  String neighbors_unknownContact(String pubkey) {
    return '$pubkey Desconhecido';
  }

  @override
  String neighbors_heardAgo(String time) {
    return 'Ouvido: $time atrás';
  }

  @override
  String get channelPath_title => 'Caminho do Pacote';

  @override
  String get channelPath_viewMap => 'Ver mapa';

  @override
  String get channelPath_otherObservedPaths => 'Outros Caminhos Observados';

  @override
  String get channelPath_repeaterHops => 'Saltos do Repetidor';

  @override
  String get channelPath_repeaterHopsHighTimeout =>
      'Tempo limite ampliado para o rastreio da rota (10 s × saltos)';

  @override
  String get channelPath_noHopDetails =>
      'Os detalhes dos saltos não são fornecidos para este pacote.';

  @override
  String get channelPath_messageDetails => 'Detalhes da Mensagem';

  @override
  String get channelPath_senderLabel => 'Remetente';

  @override
  String get channelPath_timeLabel => 'Hora de recepção/criação';

  @override
  String get channelPath_repeatsLabel => 'Repetições';

  @override
  String channelPath_pathLabel(int index) {
    return 'Caminho $index';
  }

  @override
  String get channelPath_observedLabel => 'Observado';

  @override
  String channelPath_observedPathTitle(int index, String hops) {
    return 'Caminho observado $index • $hops';
  }

  @override
  String get channelPath_noLocationData => 'Não há dados de localização.';

  @override
  String channelPath_timeWithDate(int day, int month, String time) {
    return '$day/$month $time';
  }

  @override
  String channelPath_timeOnly(String time) {
    return '$time';
  }

  @override
  String get channelPath_unknownPath => 'Desconhecido';

  @override
  String get channelPath_floodPath => 'Inundação';

  @override
  String get channelPath_directPath => 'Direto';

  @override
  String channelPath_observedZeroOf(int total) {
    return '0 de $total saltos';
  }

  @override
  String channelPath_observedSomeOf(int observed, int total) {
    return '$observed de $total saltos';
  }

  @override
  String get channelPath_mapTitle => 'Mapa de Caminhos';

  @override
  String get channelPath_noRepeaterLocations =>
      'Não estão disponíveis localizações de repetidores para este caminho.';

  @override
  String channelPath_primaryPath(int index) {
    return 'Caminho $index (Primário)';
  }

  @override
  String get channelPath_pathLabelTitle => 'Caminho';

  @override
  String get channelPath_observedPathHeader => 'Caminho Observado';

  @override
  String channelPath_selectedPathLabel(String label, String prefixes) {
    return '$label • $prefixes';
  }

  @override
  String get channelPath_noHopDetailsAvailable =>
      'Não há detalhes de saltos disponíveis para este pacote.';

  @override
  String get channelPath_unknownRepeater => 'Repetidor Desconhecido';

  @override
  String get channelPath_outgoingSentByRadioAt =>
      'Aguardando o envio via rádio, s';

  @override
  String get community_title => 'Comunidade';

  @override
  String get community_create => 'Criar Comunidade';

  @override
  String get community_createDesc =>
      'Crie uma nova comunidade e compartilhe via código QR.';

  @override
  String get community_join => 'Junte-se';

  @override
  String get community_joinTitle => 'Junte-se à Comunidade';

  @override
  String community_joinConfirmation(String name) {
    return 'Você gostaria de se juntar à comunidade \"$name\"?';
  }

  @override
  String get community_scanQr => 'Escanear o Código QR da Comunidade';

  @override
  String get community_scanInstructions =>
      'Aponte a câmera para um código QR da comunidade';

  @override
  String get community_showQr => 'Mostrar Código QR';

  @override
  String get community_publicChannel => 'Canal Público da Comunidade';

  @override
  String get community_hashtagChannel => 'Hashtag da Comunidade';

  @override
  String get community_name => 'Nome da Comunidade';

  @override
  String get community_enterName => 'Insira o nome da comunidade';

  @override
  String community_created(String name) {
    return 'Comunidade \"$name\" criada';
  }

  @override
  String community_joined(String name) {
    return 'Juntou-se à comunidade \"$name\"';
  }

  @override
  String get community_qrTitle => 'Compartilhar Comunidade';

  @override
  String community_qrInstructions(String name) {
    return 'Escanear este código QR para juntar-se a $name';
  }

  @override
  String get community_hashtagPrivacyHint =>
      'Os canais de hashtag da comunidade só podem ser acessados por membros da comunidade';

  @override
  String get community_invalidQrCode => 'Código QR da comunidade inválido';

  @override
  String get community_alreadyMember => 'Já é Membro';

  @override
  String community_alreadyMemberMessage(String name) {
    return 'Você já é membro de \"$name\".';
  }

  @override
  String get community_addPublicChannel =>
      'Adicionar Canal Público da Comunidade';

  @override
  String get community_addPublicChannelHint =>
      'Adicionar automaticamente o canal público para esta comunidade';

  @override
  String get community_noCommunities =>
      'Ainda não foram adicionadas comunidades.';

  @override
  String get community_scanOrCreate =>
      'Escaneie um código QR ou crie uma comunidade para começar.';

  @override
  String get community_manageCommunities => 'Gerenciar Comunidades';

  @override
  String get community_delete => 'Deixar Comunidade';

  @override
  String community_deleteConfirm(String name) {
    return 'Sair de \"$name\"?';
  }

  @override
  String community_deleteChannelsWarning(int count) {
    return 'Isso também excluirá $count canal/canais e suas mensagens.';
  }

  @override
  String community_deleted(String name) {
    return 'Saiu da comunidade \"$name\"';
  }

  @override
  String get community_regenerateSecret => 'Regenerar Segredo';

  @override
  String community_regenerateSecretConfirm(String name) {
    return 'Regenerar a chave secreta para \"$name\"? Todos os membros precisarão escanear o novo código QR para continuar a comunicação.';
  }

  @override
  String get community_regenerate => 'Regenerar';

  @override
  String community_secretRegenerated(String name) {
    return 'Segredo regenerado para \"$name\"';
  }

  @override
  String get community_updateSecret => 'Atualizar Segredo';

  @override
  String community_secretUpdated(String name) {
    return 'Segredo atualizado para \"$name\"';
  }

  @override
  String community_scanToUpdateSecret(String name) {
    return 'Escanear o novo código QR para atualizar o segredo para \"$name\"';
  }

  @override
  String get community_addHashtagChannel => 'Adicionar Hashtag da Comunidade';

  @override
  String get community_addHashtagChannelDesc =>
      'Adicionar um canal de hashtag para esta comunidade';

  @override
  String get community_selectCommunity => 'Selecione Comunidade';

  @override
  String get community_regularHashtag => 'Hashtag Regular';

  @override
  String get community_regularHashtagDesc =>
      'Hashtag público (qualquer pessoa pode participar)';

  @override
  String get community_communityHashtag => 'Hashtag da Comunidade';

  @override
  String get community_communityHashtagDesc =>
      'Apenas para membros da comunidade';

  @override
  String community_forCommunity(String name) {
    return 'Para $name';
  }

  @override
  String get listFilter_tooltip => 'Filtrar e ordenar';

  @override
  String get listFilter_sortBy => 'Ordenar por';

  @override
  String get listFilter_latestMessages => 'Últimas mensagens';

  @override
  String get listFilter_heardRecently => 'Ouvido recentemente';

  @override
  String get listFilter_az => 'De A a Z';

  @override
  String get listFilter_filters => 'Filtros';

  @override
  String get listFilter_all => 'Tudo';

  @override
  String get listFilter_favorites => 'Favoritos';

  @override
  String get listFilter_addToFavorites => 'Adicionar aos favoritos';

  @override
  String get listFilter_removeFromFavorites => 'Remover da lista de favoritos';

  @override
  String get listFilter_removeFromWardrive => 'Ignorar no Wardrive';

  @override
  String get listFilter_returnToWardrive => 'Considerar no Wardrive';

  @override
  String get listFilter_users => 'Usuários';

  @override
  String get listFilter_repeaters => 'Repetidores';

  @override
  String get listFilter_roomServers => 'Servidores de sala';

  @override
  String get listFilter_unreadOnly => 'Apenas não lidos';

  @override
  String get listFilter_newGroup => 'Novo grupo';

  @override
  String get pathTrace_you => 'Você';

  @override
  String get pathTrace_failed => 'Falha no rastreamento de caminho.';

  @override
  String get pathTrace_notAvailable => 'Traçado de caminho não disponível.';

  @override
  String get pathTrace_refreshTooltip => 'Atualizar rastreamento de caminho.';

  @override
  String get pathTrace_hopConfirmedNoDirectEchoTooltip =>
      'Salto confirmado, eco não ouvido diretamente';

  @override
  String get pathTrace_someHopsNoLocation =>
      'Um ou mais saltos estão sem localização!';

  @override
  String get pathTrace_clearTooltip => 'Limpar caminho';

  @override
  String get losSelectStartEnd => 'Selecione nós iniciais e finais para LOS.';

  @override
  String losRunFailed(String error) {
    return 'Falha na verificação da linha de visão: $error';
  }

  @override
  String get losClearAllPoints => 'Limpe todos os pontos';

  @override
  String get losRunToViewElevationProfile =>
      'Execute o LOS para visualizar o perfil de elevação';

  @override
  String get losMenuTitle => 'Menu LOS';

  @override
  String get losMenuSubtitle =>
      'Toque nos nós ou mantenha pressionado o mapa para obter pontos personalizados';

  @override
  String get losShowDisplayNodes => 'Mostrar nós de exibição';

  @override
  String get losCustomPoints => 'Pontos personalizados';

  @override
  String losCustomPointLabel(int index) {
    return '$index personalizado';
  }

  @override
  String get losPointA => 'Ponto A';

  @override
  String get losPointB => 'Ponto B';

  @override
  String losAntennaA(String value, String unit) {
    return 'Antena A: $value $unit';
  }

  @override
  String losAntennaB(String value, String unit) {
    return 'Antena B: $value $unit';
  }

  @override
  String get losRun => 'Executar LOS';

  @override
  String get losNoElevationData => 'Sem dados de elevação';

  @override
  String losProfileClear(
    String distance,
    String distanceUnit,
    String clearance,
    String heightUnit,
  ) {
    return '$distance $distanceUnit, LOS livre, folga mínima $clearance $heightUnit';
  }

  @override
  String losProfileBlocked(
    String distance,
    String distanceUnit,
    String obstruction,
    String heightUnit,
  ) {
    return '$distance $distanceUnit, bloqueado por $obstruction $heightUnit';
  }

  @override
  String get losStatusChecking => 'LOS: verificando...';

  @override
  String get losStatusNoData => 'LOS: sem dados';

  @override
  String losStatusSummary(int clear, int total, int blocked, int unknown) {
    return 'LOS: $clear/$total livres, $blocked bloqueados, $unknown desconhecidos';
  }

  @override
  String get losErrorElevationUnavailable =>
      'Dados de elevação indisponíveis para uma ou mais amostras.';

  @override
  String get losErrorInvalidInput =>
      'Dados de pontos/elevação inválidos para cálculo de LOS.';

  @override
  String get losRenameCustomPoint => 'Renomear ponto personalizado';

  @override
  String get losPointName => 'Nome do ponto';

  @override
  String get losShowPanelTooltip => 'Mostrar painel LOS';

  @override
  String get losHidePanelTooltip => 'Ocultar painel LOS';

  @override
  String get losElevationAttribution =>
      'Dados de elevação: Open-Meteo (CC BY 4.0)';

  @override
  String get losLegendRadioHorizon => 'Horizonte de rádio';

  @override
  String get losLegendLosBeam => 'Linha de visada';

  @override
  String get losLegendTerrain => 'Terreno';

  @override
  String get losBlockedSpotsTitle => 'Pontos bloqueados';

  @override
  String get losBlockedSpotsHint =>
      'Toque em um ponto bloqueado para destacá-lo no mapa.';

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
  String get losSelectedObstructionTitle => 'Obstrução selecionada';

  @override
  String losSelectedObstructionDetails(
    String obstruction,
    String heightUnit,
    String distanceFromA,
    String distanceUnit,
    String distanceFromB,
  ) {
    return 'Bloqueado por $obstruction $heightUnit, $distanceFromA de A e $distanceFromB de B ($distanceUnit).';
  }

  @override
  String get losFrequencyLabel => 'Frequência';

  @override
  String get losFrequencyInfoTooltip => 'Ver detalhes do cálculo';

  @override
  String get losFrequencyDialogTitle => 'Cálculo do horizonte de rádio';

  @override
  String losFrequencyDialogDescription(
    double baselineK,
    double baselineFreq,
    double frequencyMHz,
    double kFactor,
  ) {
    return 'Começando em k=$baselineK em $baselineFreq MHz, o cálculo ajusta o fator k para $kFactor na banda atual de $frequencyMHz MHz, que define o limite do horizonte de rádio curvo.';
  }

  @override
  String get contacts_pathTrace => 'Traçado de Caminho';

  @override
  String get contacts_ping => 'Pingar';

  @override
  String get contacts_repeaterPathTrace => 'Traçar caminho para repetidor';

  @override
  String get contacts_repeaterPing => 'Pingar repetidor';

  @override
  String get contacts_roomPathTrace => 'Traçar caminho para o servidor da sala';

  @override
  String get contacts_roomPing => 'Pingar servidor da sala';

  @override
  String get contacts_chatTraceRoute => 'Rastrear rota do caminho';

  @override
  String contacts_pathTraceTo(String name) {
    return 'Rastrear rota para $name';
  }

  @override
  String get contacts_clipboardEmpty => 'A Área de Transferência está vazia.';

  @override
  String get contacts_invalidAdvertFormat => 'Dados de Contato Inválidos';

  @override
  String get contacts_contactImported => 'Contato foi importado.';

  @override
  String get contacts_contactImportFailed => 'Contato falhou ao ser importado.';

  @override
  String get discoveredContacts_export => 'Exportar contatos descobertos';

  @override
  String get discoveredContacts_import => 'Importar contatos descobertos';

  @override
  String discoveredContacts_exported(String path) {
    return 'Contatos descobertos exportados para $path.';
  }

  @override
  String discoveredContacts_exportFailed(String error) {
    return 'Falha ao exportar contatos descobertos: $error';
  }

  @override
  String discoveredContacts_imported(int count) {
    return '$count contatos descobertos importados.';
  }

  @override
  String get discoveredContacts_importNoContacts =>
      'Nenhum contato encontrado no arquivo de importação.';

  @override
  String discoveredContacts_importSummary(
    int imported,
    int skipped,
    int invalid,
  ) {
    return '$imported contatos descobertos importados. $skipped já conhecidos e $invalid entradas ilegíveis foram ignorados.';
  }

  @override
  String get discoveredContacts_importInvalidFile =>
      'O arquivo não é uma exportação de contatos descobertos.';

  @override
  String discoveredContacts_importTooLarge(int maxMb) {
    return 'O arquivo de importação é grande demais (máximo $maxMb MB).';
  }

  @override
  String discoveredContacts_importFailed(String error) {
    return 'Falha ao importar contatos descobertos: $error';
  }

  @override
  String get contacts_zeroHopAdvert => 'Anúncio Zero Hop';

  @override
  String get contacts_floodAdvert => 'Anúncio de Inundação';

  @override
  String get contacts_copyAdvertToClipboard =>
      'Copiar o próprio link «meshcore://»';

  @override
  String get contacts_addContactFromClipboard =>
      'Adicionar Contato pelo link «meshcore://» da Área de Transferência';

  @override
  String get contacts_scanQrCode => 'Digitalizar um Código QR';

  @override
  String get contacts_scanQrInstructions =>
      'Aponte a câmera para um código QR de contato do MeshCore';

  @override
  String get contacts_qrFromGallery => 'Digitalizar QR da galeria';

  @override
  String get contacts_noQrCodeFound =>
      'Nenhum código QR encontrado na imagem selecionada.';

  @override
  String get contacts_qrGalleryFailed => 'Não foi possível abrir a galeria.';

  @override
  String get contacts_ShareContact =>
      'Copiar contato para Área de Transferência';

  @override
  String get contacts_ShareContactZeroHop => 'Compartilhar contato por anúncio';

  @override
  String get contacts_zeroHopContactAdvertSent =>
      'Contato enviado por anúncio.';

  @override
  String get contacts_zeroHopContactAdvertFailed => 'Falha ao enviar contato.';

  @override
  String get contacts_contactAdvertCopied =>
      'Anúncio copiado para a Área de Transferência.';

  @override
  String get contacts_contactAdvertCopyFailed =>
      'Cópia do anúncio para a Área de Transferência falhou.';

  @override
  String get notification_activityTitle => 'Atividade MeshCore';

  @override
  String notification_messagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mensagens',
      one: 'mensagem',
    );
    return '$count $_temp0';
  }

  @override
  String notification_channelMessagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mensagens de canal',
      one: 'mensagem de canal',
    );
    return '$count $_temp0';
  }

  @override
  String notification_newNodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'novos nós',
      one: 'novo nó',
    );
    return '$count $_temp0';
  }

  @override
  String notification_newTypeDiscovered(String contactType) {
    return 'Novo $contactType descoberto';
  }

  @override
  String get notification_receivedNewMessage => 'Nova mensagem recebida';

  @override
  String get notification_actionReply => 'Responder';

  @override
  String get notification_actionMarkRead => 'Marcar como lido';

  @override
  String get notification_actionMuteChannel => 'Silenciar canal';

  @override
  String get notification_replyHint => 'Mensagem';

  @override
  String get notification_you => 'Você';

  @override
  String get notification_replyFailedTitle => 'Resposta não enviada';

  @override
  String get notification_replyNotConnected =>
      'Não conectado a um rádio. Reconecte no MeshCore Open e envie a sua resposta novamente.';

  @override
  String get notification_replyTooLong =>
      'A sua resposta é demasiado longa para ser enviada a partir de uma notificação. Envie-a pelo MeshCore Open.';

  @override
  String get notification_replyUnavailable =>
      'Esta conversa já não está no rádio conectado.';

  @override
  String get notification_replySendFailed =>
      'A sua resposta pode não ter sido enviada. Verifique no MeshCore Open e tente novamente.';

  @override
  String get notification_replyAppNotRunning =>
      'O MeshCore Open não está em execução. Abra-o e envie a sua resposta novamente.';

  @override
  String get settings_gpxExportRepeaters =>
      'Exportar repetidores / servidor de sala para GPX';

  @override
  String get settings_gpxExportRepeatersSubtitle =>
      'Exporta repetidores / roomserver com localização para arquivo GPX.';

  @override
  String get settings_gpxExportContacts => 'Exportar companheiros para GPX';

  @override
  String get settings_gpxExportContactsSubtitle =>
      'Exporta companheiros com uma localização para um arquivo GPX.';

  @override
  String get settings_gpxExportAll => 'Exportar todos os contatos para GPX';

  @override
  String get settings_gpxExportAllSubtitle =>
      'Exporta todos os contatos com uma localização para um arquivo GPX.';

  @override
  String get settings_gpxExportSuccess => 'Arquivo GPX exportado com sucesso.';

  @override
  String get settings_gpxExportNoContacts => 'Nenhum contato para exportar.';

  @override
  String get settings_gpxExportNotAvailable =>
      'Não suportado no seu dispositivo/SO';

  @override
  String get settings_gpxExportError => 'Ocorreu um erro ao exportar.';

  @override
  String get settings_gpxExportRepeatersRoom =>
      'Localizações de repetidores e servidores de sala';

  @override
  String get settings_gpxExportChat => 'Localizações de companheiros';

  @override
  String get settings_gpxExportAllContacts => 'Todos os locais de contatos';

  @override
  String get settings_gpxExportShareText =>
      'Dados do mapa exportados do meshcore-open';

  @override
  String get settings_gpxExportShareSubject =>
      'meshcore-open exportação de dados de mapa GPX';

  @override
  String get snrIndicator_nearByRepeaters => 'Repetidores Próximos';

  @override
  String get snrIndicator_lastSeen => 'Visto pela última vez';

  @override
  String get snrIndicator_nearByRepeatersDescription =>
      'Repetidores que o seu rádio ouviu diretamente, do mais recente para o mais antigo.';

  @override
  String get contactsSettings_title => 'Configurações de contatos';

  @override
  String get contactsSettings_autoAddTitle => 'Descoberta Automática';

  @override
  String get contactsSettings_otherTitle =>
      'Outras configurações relacionadas a contatos';

  @override
  String get contactsSettings_autoAddUsersTitle =>
      'Adicionar usuários automaticamente';

  @override
  String get contactsSettings_autoAddUsersSubtitle =>
      'Permitir que o companheiro adicione automaticamente os usuários descobertos.';

  @override
  String get contactsSettings_autoAddRepeatersTitle =>
      'Adicionar repetidores automaticamente';

  @override
  String get contactsSettings_autoAddRepeatersSubtitle =>
      'Permitir que o companheiro adicione automaticamente os repetidores descobertos.';

  @override
  String get contactsSettings_autoAddRoomServersTitle =>
      'Adicionar automaticamente servidores de sala';

  @override
  String get contactsSettings_autoAddRoomServersSubtitle =>
      'Permitir que o companheiro adicione automaticamente os servidores de salas descobertos.';

  @override
  String get contactsSettings_autoAddSensorsTitle =>
      'Adicionar sensores automaticamente';

  @override
  String get contactsSettings_autoAddSensorsSubtitle =>
      'Permitir que o companheiro adicione automaticamente sensores descobertos.';

  @override
  String get contactsSettings_overwriteOldestTitle =>
      'Sobrescrever o Mais Antigo';

  @override
  String get contactsSettings_overwriteOldestSubtitle =>
      'Quando a lista de contatos estiver cheia, o contato mais antigo não favoritado será substituído.';

  @override
  String get discoveredContacts_Title => 'Adicionar contatos descobertos';

  @override
  String get contactsSettings_evictDiscoveredContactsTitle =>
      'Remover contatos descobertos';

  @override
  String contactsSettings_evictDiscoveredContactsSubtitle(int limit) {
    return 'Quando ativado, o aplicativo remove os contatos descobertos mais antigos assim que a lista de descobertos atingir o limite de $limit entradas.';
  }

  @override
  String get discoveredContacts_noMatching => 'Nenhum contato correspondente';

  @override
  String get discoveredContacts_searchHint => 'Pesquisar contatos descobertos';

  @override
  String get discoveredContacts_contactAdded => 'Contato adicionado';

  @override
  String get discoveredContacts_addContact => 'Adicionar Contato';

  @override
  String get discoveredContacts_copyContact =>
      'Copiar Contato para a área de transferência';

  @override
  String get discoveredContacts_deleteContact => 'Excluir Contato';

  @override
  String get discoveredContacts_deleteContactAll =>
      'Excluir Todos os Contatos Descobertos';

  @override
  String get discoveredContacts_discoverDevices => 'Descobrir dispositivos';

  @override
  String get discoveredContacts_requestName => 'Solicitar nome';

  @override
  String get discoveredContacts_nameRequestFailed =>
      'Não foi possível solicitar o nome do repetidor';

  @override
  String discoveredContacts_discoveryFailed(String error) {
    return 'Não foi possível descobrir dispositivos: $error';
  }

  @override
  String get discoveredContacts_deleteContactAllContent =>
      'Tem certeza de que deseja excluir todos os contatos descobertos?';

  @override
  String get discoveredContacts_scan => 'Buscar nós próximos';

  @override
  String get discoveredContacts_scanTitle => 'Nós próximos';

  @override
  String get discoveredContacts_scanExplanation =>
      'Pede aos nós ao alcance direto do rádio que se identifiquem. Repetidores e sensores respondem. Servidores de sala e companheiros geralmente não.';

  @override
  String get discoveredContacts_scanning => 'Buscando…';

  @override
  String discoveredContacts_scanFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nós encontrados',
      one: '1 nó encontrado',
    );
    return '$_temp0';
  }

  @override
  String get discoveredContacts_scanNoResults =>
      'Nenhum nó respondeu. Os repetidores limitam a frequência das respostas, então tente novamente em um minuto.';

  @override
  String get discoveredContacts_scanAgain => 'Buscar novamente';

  @override
  String get discoveredContacts_scanFailed =>
      'Não foi possível enviar a solicitação de busca.';

  @override
  String discoveredContacts_scanSignal(String snr, String remoteSnr) {
    return 'Sinal $snr dB · eles nos ouviram a $remoteSnr dB';
  }

  @override
  String get discoveredContacts_scanInContacts => 'Já está nos contatos';

  @override
  String get discoveredContacts_scanNameLater =>
      'O nome aparece após o próximo anúncio';

  @override
  String get chat_sendCooldown =>
      'Por favor, aguarde um momento antes de reenviar.';

  @override
  String get appSettings_jumpToOldestUnread =>
      'Vá para a mensagem mais antiga não lida';

  @override
  String get appSettings_jumpToOldestUnreadSubtitle =>
      'Ao abrir uma conversa com mensagens não lidas, role para a primeira mensagem não lida, em vez da mais recente.';

  @override
  String get appSettings_languageHu => 'Húngaro';

  @override
  String get appSettings_languageJa => 'Japonês';

  @override
  String get appSettings_languageKo => 'Coreano';

  @override
  String get radioStats_tooltip => 'Estatísticas de rádio e malha';

  @override
  String get radioStats_screenTitle => 'Estatísticas de rádio';

  @override
  String get radioStats_sectionSignal => 'Sinal';

  @override
  String get radioStats_sectionAirtime => 'Tempo de transmissão';

  @override
  String get radioStats_notConnected =>
      'Conecte-se a um dispositivo para visualizar estatísticas de rádio.';

  @override
  String get radioStats_firmwareTooOld =>
      'As estatísticas de rádio exigem o firmware v8 ou uma versão mais recente.';

  @override
  String get radioStats_waiting => 'Aguardando dados…';

  @override
  String radioStats_noiseFloor(int noiseDbm) {
    return 'Nível de ruído: $noiseDbm dBm';
  }

  @override
  String radioStats_lastRssi(int rssiDbm) {
    return 'Último RSSI: $rssiDbm dBm';
  }

  @override
  String radioStats_lastSnr(String snr) {
    return 'Último SNR: $snr dB';
  }

  @override
  String radioStats_txAir(int seconds) {
    return 'Tempo de transmissão da TX (total): $seconds s';
  }

  @override
  String radioStats_rxAir(int seconds) {
    return 'Tempo de uso do RX (total): $seconds s';
  }

  @override
  String get radioStats_chartCaption =>
      'Nível de ruído (dBm) em amostras recentes.';

  @override
  String radioStats_stripNoise(int noiseDbm) {
    return 'Nível de ruído: $noiseDbm dBm';
  }

  @override
  String get radioStats_stripWaiting => 'Obtendo estatísticas de rádio…';

  @override
  String get radioStats_settingsTile => 'Estatísticas de rádio';

  @override
  String get radioStats_settingsSubtitle =>
      'Nível de ruído, RSSI, SNR e tempo de transmissão';

  @override
  String get translation_title => 'Tradução';

  @override
  String get translation_enableTitle => 'Ativar a tradução';

  @override
  String get translation_enableSubtitle =>
      'Traduzir mensagens recebidas e permitir a tradução antes do envio.';

  @override
  String get translation_composerTitle => 'Traduza antes de enviar';

  @override
  String get translation_composerSubtitle =>
      'Controla o estado padrão do ícone de tradução do editor de mensagens.';

  @override
  String get translation_autoIncomingTitle =>
      'Traduzir mensagens automaticamente';

  @override
  String get translation_autoIncomingSubtitle =>
      'Traduz automaticamente mensagens para notificações e para chats ou canais.';

  @override
  String get translation_translateMessage => 'Traduzir mensagem';

  @override
  String get translation_targetLanguage => 'Língua-alvo';

  @override
  String get translation_useAppLanguage => 'Usar o idioma do aplicativo';

  @override
  String get translation_downloadedModelLabel => 'Modelo baixado';

  @override
  String get translation_presetModelLabel =>
      'Modelo pré-definido da Hugging Face';

  @override
  String get translation_manualUrlLabel => 'URL manual do modelo';

  @override
  String get translation_downloadModel => 'Baixar modelo';

  @override
  String get translation_downloading => 'Baixando...';

  @override
  String get translation_working => 'Trabalhando...';

  @override
  String get translation_stop => 'Pare';

  @override
  String get translation_mergingChunks =>
      'Combinando os fragmentos baixados em um único arquivo...';

  @override
  String get translation_downloadedModels => 'Modelos baixados';

  @override
  String get translation_deleteModel => 'Excluir modelo';

  @override
  String get translation_modelDownloaded => 'Modelo de tradução baixado.';

  @override
  String get translation_downloadStopped => 'Download interrompido.';

  @override
  String translation_downloadFailed(String error) {
    return 'Falha no download: $error';
  }

  @override
  String get translation_enterUrlFirst => 'Insira primeiro a URL do modelo.';

  @override
  String get scanner_linuxPairingShowPin => 'Mostrar PIN';

  @override
  String get scanner_linuxPairingHidePin => 'Ocultar PIN';

  @override
  String get scanner_linuxPairingPinTitle => 'PIN de emparelhamento Bluetooth';

  @override
  String scanner_linuxPairingPinPrompt(String deviceName) {
    return 'Insira o PIN para $deviceName (deixe em branco se não houver).';
  }

  @override
  String get translation_messageTranslation => 'Tradução da mensagem';

  @override
  String get translation_translateBeforeSending => 'Traduzir antes de enviar';

  @override
  String get translation_composerEnabledHint =>
      'As mensagens serão traduzidas antes de serem enviadas.';

  @override
  String get translation_composerDisabledHint =>
      'Envie mensagens no idioma original, conforme digitado.';

  @override
  String translation_translateTo(String language) {
    return 'Traduzir para $language';
  }

  @override
  String get translation_translationOptions => 'Opções de tradução';

  @override
  String get translation_systemLanguage => 'Idioma do sistema';

  @override
  String get background_serviceTitle => 'MeshCore em execução';

  @override
  String get background_serviceText => 'Mantendo o nó conectado';

  @override
  String appSettings_translationModelDeleted(String name) {
    return '$name excluído';
  }

  @override
  String appSettings_translationModelDeleteFailed(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String channels_channelUpdateFailed(String error) {
    return 'Falha ao atualizar o canal: $error';
  }

  @override
  String get channels_mcmpCompression => 'Compressão MCMP';

  @override
  String get channels_mcmpCompressionDescription =>
      'Usando o modelo mesh-compressor';

  @override
  String get channels_copyPath => 'Copiar a rota da mensagem';

  @override
  String get channels_copyPathExtended =>
      'Copiar a rota da mensagem (estendida)';

  @override
  String get channels_copiedPath => 'Rota da mensagem copiada';

  @override
  String get channels_copyPathFailed =>
      'Não foi possível copiar a rota da mensagem';

  @override
  String get settings_copyMsgPathTitle =>
      'Configurar a cópia da rota da mensagem';

  @override
  String get settings_copyMsgPathDscr =>
      'Editar o modelo de montagem das informações da rota de uma mensagem de canal';

  @override
  String get settings_copyMsgPathEditTemplateTitle => 'Edição do modelo';

  @override
  String get settings_copyMsgPathEditTemplateDscr =>
      'Use os modelos de substituição:\n%hopInd% - ordem do salto\n%hopKey% - chave do salto\n%hopName% - nome do salto\n%collisionMarker% - marca de colisão de repetidores\n%div% - separador (omitido no último salto)\n%hops% - quantidade de saltos\n\\n - quebra de linha';

  @override
  String get settings_copyMsgPathEditFinalTitle => 'Mensagem final';

  @override
  String get settings_copyMsgPathEditFinalDscr =>
      'Modelos disponíveis:\n%senderName% - nome do remetente\n%path% - rota montada\n%hops% - quantidade de saltos\n\\n - quebra de linha';

  @override
  String get settings_channelsSendAsBinary =>
      'Enviar os formatos estendidos em binário (canais)';

  @override
  String get settings_dmSendAsBinary =>
      'Enviar os formatos estendidos em binário (mensagens diretas)';

  @override
  String get contact_typeChat => 'Chat';

  @override
  String get contact_typeRepeater => 'Repetidor';

  @override
  String get contact_typeRoom => 'Sala';

  @override
  String get contact_typeSensor => 'Sensor';

  @override
  String get contact_typeUnknown => 'Desconhecido';

  @override
  String get map_zoomIn => 'Ampliar';

  @override
  String get map_zoomOut => 'Reduzir';

  @override
  String get map_centerMap => 'Centralizar mapa';

  @override
  String get chrome_bluetoothRequiresChromium =>
      'O Web Bluetooth requer um navegador Chromium.';

  @override
  String channels_communityShortId(String id) {
    return 'ID: $id...';
  }

  @override
  String get pathTrace_legendGpsConfirmed => 'GPS confirmado';

  @override
  String get pathTrace_legendInferred => 'Posição inferida';

  @override
  String get pathMap_viewSingle => 'Único';

  @override
  String get pathMap_viewCombined => 'Combinado';

  @override
  String get pathMap_play => 'Reproduzir';

  @override
  String get pathMap_pause => 'Pausa';

  @override
  String get pathMap_replay => 'Repetir';

  @override
  String get pathMap_stepBack => 'Salto anterior';

  @override
  String get pathMap_stepForward => 'Próximo salto';

  @override
  String get pathMap_animationOn => 'Exibir animação do pacote';

  @override
  String get pathMap_animationOff => 'Ocultar a animação do pacote';

  @override
  String pathMap_hopOf(int current, int total) {
    return 'Salto $current de $total';
  }

  @override
  String pathMap_observedPaths(int count) {
    return 'Caminhos observados: $count';
  }

  @override
  String get pathMap_primary => 'Primário';

  @override
  String pathMap_alternate(int index) {
    return 'Alt $index';
  }

  @override
  String pathMap_hopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saltos',
      one: '$count salto',
      zero: '$count saltos',
    );
    return '$_temp0';
  }

  @override
  String pathMap_gpsCount(int confirmed, int total) {
    return '$confirmed/$total GPS';
  }

  @override
  String get pathMap_legendShared => 'Segmento compartilhado';

  @override
  String get pathMap_legendEstimated => 'Segmento estimado';

  @override
  String pathMap_sharedNodeCount(int count) {
    return 'Utilizado em $count caminhos';
  }

  @override
  String pathMap_partialAnimation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saltos não têm localização — o caminho mostrado é parcial',
      one: '$count salto não tem localização — o caminho mostrado é parcial',
    );
    return '$_temp0';
  }

  @override
  String get pathMap_showAllPaths => 'Mostrar tudo';

  @override
  String get pathMap_hidePath => 'Esconder caminho';

  @override
  String get pathMap_showPath => 'Mostrar o caminho';

  @override
  String get pathMap_collapsePanel => 'Recolher painel';

  @override
  String get pathMap_expandPanel => 'Expandir painel';

  @override
  String get pathMap_noLocation => 'Sem localização';

  @override
  String get pathMap_followPacket => 'Fixar vista no pacote';

  @override
  String get pathMap_unfollowPacket => 'Liberar vista do pacote';

  @override
  String get chat_canvas => 'Tela MCOimg';

  @override
  String get chat_canvasV4Title => 'Tela vetorial MCOimg v4';

  @override
  String get chat_canvasV4SetupTitle => 'Nova tela vetorial';

  @override
  String get chat_canvasV4Grid => 'Grade de coordenadas';

  @override
  String get chat_canvasV4GridDescription =>
      'Uma grade menor reduz o payload; uma maior aumenta a precisão ao posicionar as figuras.';

  @override
  String get chat_canvasV4Background => 'Fundo';

  @override
  String get chat_canvasV4Transparent => 'Transparente';

  @override
  String get chat_canvasV4Fill => 'Preenchimento';

  @override
  String get chat_canvasV4Stroke => 'Contorno';

  @override
  String get chat_canvasV4StrokeWidth => 'Espessura do contorno';

  @override
  String get chat_canvasV4Closed => 'Fechar a figura';

  @override
  String get chat_canvasV4HideFigure => 'Ocultar figura';

  @override
  String get chat_canvasV4ShowFigure => 'Mostrar figura';

  @override
  String get chat_canvasV4MoveUp => 'Mover para cima';

  @override
  String get chat_canvasV4MoveDown => 'Mover para baixo';

  @override
  String get chat_canvasV4Objects => 'Figuras';

  @override
  String get chat_canvasV4NoObjects => 'Ainda não há figuras na tela';

  @override
  String get chat_canvasV4Calculate => 'Calcular a imagem final';

  @override
  String get chat_canvasV4Redo => 'Refazer';

  @override
  String get chat_canvasV4CanvasSettings => 'Configurações da tela';

  @override
  String get chat_canvasV4InvalidSize => 'De 1 a 256';

  @override
  String get chat_canvasV4LoadReference => 'Carregar imagem de referência';

  @override
  String get chat_canvasV4HideReference => 'Ocultar imagem de referência';

  @override
  String get chat_canvasV4ShowReference => 'Mostrar imagem de referência';

  @override
  String get chat_canvasV4RemoveReference => 'Remover imagem de referência';

  @override
  String get chat_canvasV4ReferenceNotEncoded =>
      'A imagem de referência não entra no payload';

  @override
  String get chat_canvasV4PaletteFull => 'O documento já usa 64 cores';

  @override
  String chat_canvasV4Payload(int bytes) {
    return 'Payload: $bytes bytes';
  }

  @override
  String chat_canvasV4PayloadTooLarge(int bytes) {
    return 'O payload excede o tamanho disponível em $bytes bytes';
  }

  @override
  String get chat_canvasV4ApplyStyle => 'Aplicar estilo';

  @override
  String get chat_canvasV4WaveHint =>
      'Indique o início, o fim e a profundidade da onda';

  @override
  String get chat_canvasV4ToolSelect => 'Selecionar e mover';

  @override
  String get chat_canvasV4ToolDot => 'Ponto';

  @override
  String get chat_canvasV4ToolPencil => 'Lápis';

  @override
  String get chat_canvasV4ToolLine => 'Linha';

  @override
  String get chat_canvasV4ToolPolyline => 'Polilinha';

  @override
  String get chat_canvasV4PolylineHint =>
      'Marque os vértices do contorno. Toque no primeiro vértice ou escolha como concluir.';

  @override
  String get chat_canvasV4FinishOpen => 'Concluir aberta';

  @override
  String get chat_canvasV4FinishClosed => 'Fechar';

  @override
  String get chat_canvasV4ToolRect => 'Retângulo';

  @override
  String get chat_canvasV4ToolEllipse => 'Elipse';

  @override
  String get chat_canvasV4ToolCircle => 'Círculo';

  @override
  String get chat_canvasV4ToolWave => 'Onda';

  @override
  String get chat_canvasCrop => 'Recortar/expandir';

  @override
  String get chat_canvasResize => 'Comprimir/esticar';

  @override
  String get chat_canvasUnlockSize => 'Desbloquear o tamanho da tela';

  @override
  String get chat_canvasFormatVer => 'Versão do codec';

  @override
  String get chat_canvasPalette => 'Paleta';

  @override
  String get chat_canvasPaletteShow => 'Mostrar a paleta';

  @override
  String get chat_canvasPaletteMode => 'Perfil da paleta';

  @override
  String get chat_canvasPaletteDynamic => 'Dinâmica';

  @override
  String get chat_canvasPaletteDynamicProfile =>
      'Conjunto base da paleta dinâmica';

  @override
  String get chat_canvasPaletteDynamicUsed => 'Cores realmente usadas';

  @override
  String get chat_canvasPaletteDynamicDscr =>
      'Atenção! Use a paleta dinâmica com critério! Ela foi pensada principalmente para imagens com gradientes, para montar uma paleta menor e usar cores que não pertencem a uma mesma paleta base. Para referência: uma paleta base menor reduz o custo de codificar as informações sobre os tons usados, e um número total de cores menor reduz o custo de cada pixel da tela.';

  @override
  String get chat_canvasPaletteAlpha => 'Cor de transparência';

  @override
  String get chat_canvasChangeSize => 'Alterar o tamanho da tela';

  @override
  String get chat_canvasTrim => 'Recortar o espaço vazio';

  @override
  String get chat_canvasWidth => 'Largura';

  @override
  String get chat_canvasHeight => 'Altura';

  @override
  String get chat_canvasGridShow => 'Mostrar a grade';

  @override
  String get chat_canvasRulerShow => 'Mostrar a régua';

  @override
  String get chat_canvasGridColor => 'Cor da grade';

  @override
  String get chat_canvasSave => 'Salvar em arquivo';

  @override
  String get chat_canvasLoad => 'Carregar de arquivo';

  @override
  String get chat_formatBold => 'Negrito';

  @override
  String get chat_formatItalic => 'Itálico';

  @override
  String get chat_formatUnderline => 'Sublinhado';

  @override
  String get chat_formatStrikethrough => 'Riscado';

  @override
  String get chat_formatMono => 'Monoespaçado';

  @override
  String get chat_formatColor => 'Cor do texto';

  @override
  String chat_canvasSendPayloadExceed(int count) {
    return 'Não foi possível enviar: o payload foi excedido em $count bytes. Reduza a quantidade de detalhes ou o tamanho da tela.';
  }

  @override
  String chat_canvasCurrentPayload(int payload) {
    return 'Payload atual: $payload';
  }

  @override
  String get chat_canvasActive => 'Mostrar a tela';

  @override
  String get chat_canvasShowLockBtn => 'Mostrar o botão de bloqueio da tela';

  @override
  String get chat_canvasSendToEdit => 'Enviar para a tela';

  @override
  String get chat_canvasSendToGallery => 'Salvar na galeria';

  @override
  String get chat_canvasGalleryShowPNG => 'Mostrar o original (PNG)';

  @override
  String get chat_canvasGalleryShowBIN => 'Mostrar como Bin';

  @override
  String get chat_canvasGalleryRemove => 'Remover';

  @override
  String get chat_canvasGalleryRemoveConfirm => 'Remover a imagem da galeria?';

  @override
  String chat_canvasFormatNotSupported(int received, int current) {
    return 'Versão do MCOimg: $received, o codec atual suporta até $current';
  }

  @override
  String get chat_canvasSaveBinary => 'Salvar em arquivo binário';

  @override
  String chat_canvasCannotSend(int count) {
    return 'Não foi possível enviar: o payload foi excedido em $count bytes. Edite a imagem e tente novamente.';
  }

  @override
  String get chat_canvasCompressionLevel => 'Nível de compressão';

  @override
  String get chat_canvasCompressionLevelNormal => 'Normal';

  @override
  String get chat_canvasCompressionLevelHigh => 'Alto';

  @override
  String get chat_canvasCompressionLevelExtreme => 'Extremo';

  @override
  String get chat_showHops => 'Mostrar os saltos';

  @override
  String get settings_modSettings => 'Configurações da modificação';

  @override
  String get settings_modSettingsSubtitle =>
      'Esta seção reúne as opções ausentes no meshcore_open original';

  @override
  String get settings_modSettingsVisual => 'Aparência';

  @override
  String get settings_modSettingsMessaging => 'Mensagens';

  @override
  String get settings_modSettingsMCMP => 'MCMP';

  @override
  String get settings_mcmp_version => 'Versão';

  @override
  String get settings_mcmp_useSign => 'Assinatura de mensagens';

  @override
  String get settings_mcmp_signed => 'Com verificação da assinatura';

  @override
  String get settings_mcmp_noSign => 'Sem assinatura';

  @override
  String get settings_mcmp_senderNameCollision =>
      'O nome do remetente não é único!';

  @override
  String get chat_mcmpSignatureValid => 'A assinatura é válida';

  @override
  String get chat_mcmpSignatureInvalid => 'Assinatura inválida!';

  @override
  String get chat_mcmpSignatureUnverifiable =>
      'A assinatura não pode ser verificada — o remetente não está nos contatos';

  @override
  String get chat_mcmpSignatureTransport =>
      'Autenticado pela criptografia do transporte';

  @override
  String get chat_mcmpManualRecheckSign => 'Verificar a assinatura novamente';

  @override
  String get chat_mcmpSignatureCheckStatus => 'Verificação da assinatura';

  @override
  String get chat_mcmpSigningFailed => 'Não foi possível assinar a mensagem';

  @override
  String get chat_mcmpAnswerTo => 'Resposta MCMPv3 para';

  @override
  String get chat_mcmpSignedTimestamp => 'Timestamp MCMP';

  @override
  String chat_mcmpTimestampQueerly(int time) {
    return 'O timestamp MCMP difere do timestamp do pacote em $time segundos';
  }

  @override
  String chat_mcmpTimestampQueerlyReceived(int time) {
    return 'O timestamp MCMP assinado difere significativamente da hora de recebimento, em $time segundos';
  }

  @override
  String get chat_timestampPacket => 'Timestamp do pacote';

  @override
  String get settings_modSettingsMCOimg => 'MCOimg';

  @override
  String get settings_modSettingsVisualShowMCOimgFormat =>
      'MCOimg: mostrar o selo da versão do formato';

  @override
  String get settings_modSettingsVisualShowMCOimgAlgo =>
      'MCOimg: mostrar o selo do algoritmo de codificação';

  @override
  String get settings_modSettingsVisualShowMCOimgBytes =>
      'MCOimg: mostrar o peso da imagem (bytes)';

  @override
  String get settings_modSettingsVisualShowMCOimgResolution =>
      'MCOimg: mostrar a resolução';

  @override
  String get settings_modSettingsMCOimg_showReplacements =>
      'Mostrar os originais das imagens em vez das versões LoRa';

  @override
  String get settings_modSettingsMCOimg_replacementsScale =>
      'Redimensionar os originais nos chats';

  @override
  String get settings_modSettingsMCOimg_replacementsLottieScale =>
      'Limite de tamanho das substituições lottie';

  @override
  String get settings_modSettingsMCOimg_scaleNearestNeighbor =>
      'Redimensionar como Nearest Neighbor';

  @override
  String get settings_modSettingsMCOimg_replacementsSharp =>
      'Aumentar a nitidez dos originais nos chats';

  @override
  String get settings_modSettingsMCOimg_replacementsSharpDscr =>
      'Atenção! Desativa a animação dos GIFs!';

  @override
  String get settings_modSettingsHideChInd => 'Ocultar o índice do canal';

  @override
  String get settings_modSettingsHideRadioStats =>
      'Ocultar as estatísticas de rádio no cabeçalho';

  @override
  String get settings_modSettingsSNRindicatorAllRepActivity =>
      'Indicador SNR: acionar em todas as respostas dos repetidores, não apenas nos anúncios';

  @override
  String get settings_modSettingsIncomingQuoteAsMentions =>
      'Mostrar as citações das mensagens recebidas como menções';

  @override
  String get settings_modSettingsSimplifiedMentions =>
      'Estilo simplificado das menções nas mensagens';

  @override
  String get settings_modSettingsSharedMsgHistory =>
      'Histórico de mensagens compartilhado';

  @override
  String get settings_modSettingsSharedMsgHistoryDscr =>
      'Combinação do histórico de mensagens recebido de dispositivos diferentes; o histórico final é armazenado apenas no aplicativo';

  @override
  String get settings_modSettingsSharedMsgHistoryDisabled => 'Desativado';

  @override
  String get settings_modSettingsSharedMsgHistoryChannels => 'Somente canais';

  @override
  String get settings_modSettingsSharedMsgHistoryContacts => 'Somente contatos';

  @override
  String get settings_modSettingsSharedMsgHistoryAll => 'Todos os chats';

  @override
  String get settings_modSettingsMessagingShowCompressionRatio =>
      'Mostrar o grau de compressão';

  @override
  String get settings_modSettingsMessagingCompressionRatioWithSendername =>
      'Considerar também o nome do nó';

  @override
  String get settings_modSettingsVisualHideMapZoomControls =>
      'Ocultar o painel de zoom no mapa';

  @override
  String get settings_modSettingsVisualShowMsgRegion =>
      'Mostrar a região da mensagem';

  @override
  String channels_messageRegion(String region) {
    return 'Região: $region';
  }

  @override
  String get channels_messageRegionUnknown => 'desconhecida';

  @override
  String get channels_messageRegionNotMatchesWithKnown => 'sem correspondência';

  @override
  String get channels_messageRegionEmpty => 'não definida';

  @override
  String get settings_defaultRegionScope => 'Região padrão do nó';

  @override
  String get settings_defaultRegionScopeChanged => 'Região padrão alterada';

  @override
  String get settings_defaultRegionScopeChangeFailed =>
      'Não foi possível alterar a região';

  @override
  String get settings_defaultRegionScopeEmpty => 'Não definida';

  @override
  String get settings_defaultRegionScopeWaitForSync =>
      'Aguarde o fim da sincronização';

  @override
  String get common_reset => 'Redefinir';

  @override
  String get connection_autoconnect => 'Conexão automática';

  @override
  String settings_modSettingsNoRetraInfo(int time) {
    return 'Nenhuma retransmissão ouvida por $time s.';
  }

  @override
  String get settings_modSettingsNoRetraHeading =>
      'Marcar as mensagens como não enviadas se nenhuma retransmissão for ouvida nestes segundos:';

  @override
  String get settings_modSettingsNoRetraDscr =>
      'Atenção! Devido a um mecanismo do firmware do nó, as mensagens de canal com mais de ~133 bytes não podem receber confirmações fisicamente e sempre serão marcadas como falhas! Use esta opção junto com o limite de payload nas configurações do aplicativo!';

  @override
  String get settings_selfTelemetryShow => 'Ver os sensores';

  @override
  String get settings_modSettingsVisualChannelsUnreadSorting =>
      'Ordenar os canais por mensagens não lidas';

  @override
  String get settings_modSettingsMessagingBackgroundTCP =>
      'Manter a conexão TCP em segundo plano';

  @override
  String get settings_modSettingsDPIchange => 'Ajuste do DPI';

  @override
  String get settings_modSettingsDPIchangeToIcons => 'Aplicar aos ícones';

  @override
  String get settings_modSettingsMonochromeSenderNames =>
      'Nomes de remetente monocromáticos';

  @override
  String get chat_MCOimgOpenGallery => 'Abrir a galeria MCOimg';

  @override
  String get chat_additionalActions => 'Menu de ações';

  @override
  String get mcogallery_common => 'Geral';

  @override
  String get mcogallery_addPack => 'Adicionar pacote';

  @override
  String get mcogallery_removePack => 'Remover pacote';

  @override
  String mcogallery_removePackConfirm(String name) {
    return 'Confirme a remoção do pacote «$name»';
  }

  @override
  String get mcogallery_addGroup => 'Adicionar grupo';

  @override
  String get mcogallery_removeGroup => 'Remover grupo';

  @override
  String get mcogallery_showLora => 'Mostrar a variante LoRa';

  @override
  String get mcogallery_showPacked => 'Mostrar a variante melhorada';

  @override
  String get chat_sendSelfContact => 'Enviar meu contato';

  @override
  String get chat_sendContact => 'Compartilhar contato';

  @override
  String get chat_addContact => 'Adicionar contato';

  @override
  String get chat_sureToReplaceContact => 'O contato já existe, substituir?';

  @override
  String get contacts_addContactByPubkey => 'Adicionar contato por chave';

  @override
  String get contacts_addContactByPubkey_contactType => 'Tipo de contato';

  @override
  String get chat_contactIsYou => 'É o seu próprio contato';

  @override
  String chat_contactType(String contacttype) {
    return 'Tipo de contato: $contacttype';
  }

  @override
  String get chat_contactTypeNode => 'Nó';

  @override
  String get chat_contactTypeRepeater => 'Repetidor';

  @override
  String get chat_contactTypeRoom => 'Servidor de sala';

  @override
  String get chat_contactTypeSensor => 'Sensor';

  @override
  String get chat_myLocation => 'Enviar minha localização';

  @override
  String get chat_locationFromMap => 'Enviar coordenadas do mapa';

  @override
  String get settings_modSettingsRoomServer => 'Servidores de sala e contatos';

  @override
  String get settings_modSettingsRoomServerShowNotemptyOnChatscreen =>
      'Mostrar os servidores com histórico na mesma tela dos canais';

  @override
  String get settings_modSettingsRoomServerShowNotemptyContactsOnChatscreen =>
      'Mostrar os contatos com histórico na mesma tela dos canais';

  @override
  String get settings_modSettingsRoomServerDisableRoomAndContactsSorting =>
      'Manter o comportamento anterior de arrastar e soltar: alterar a ordem dos canais altera a ordem deles no nó, e não é possível ordenar contatos ou servidores';

  @override
  String get settings_modSettingsMapAndLocation => 'Mapa e localização';

  @override
  String get settings_modSettingsAlwaysRequestMapLocation =>
      'Sempre solicitar a localização ao abrir o mapa';

  @override
  String get settings_modSettingsExactQuote =>
      'Usar citações precisas em mensagens normais';

  @override
  String get settings_modSettingsExactQuoteLimit =>
      'Limite de bytes para construir a citação';

  @override
  String get settings_modSettingsExactQuoteLimitDscr =>
      'O limite padrão é 30. Além do limite, são adicionados 5 bytes que formatam a citação para clientes que não suportam esta função';

  @override
  String get settings_appSettingsCustomChemistry => 'Personalizada';

  @override
  String get map_clearDiscoveredContactsCache => 'Limpar o cache local dos nós';

  @override
  String get map_clearDiscoveredContactsCacheDisclaimer =>
      'Tem certeza de que deseja limpar o cache dos contatos descobertos? Isso não afetará os contatos do próprio nó.';

  @override
  String get snrIndicator_v2_nearByRepeaters => 'Atividade dos repetidores';

  @override
  String get app_connectionLostReconnect =>
      'Conexão com o nó perdida, reconectando...';

  @override
  String get app_connectionLostReconnected => 'Conexão com o nó restabelecida';

  @override
  String get app_connectionLostBreaked => 'Conexão com o nó interrompida';

  @override
  String get contacts_batchOperations => 'Operações em lote';

  @override
  String get contacts_batchOperations_notSelected =>
      'Você não selecionou nenhum contato para processar!';

  @override
  String get contacts_batchOperations_removeConfirm =>
      'Remover os contatos selecionados da memória do nó?';

  @override
  String get contacts_batchOperations_removeSuccess =>
      'Os contatos selecionados foram removidos';

  @override
  String get contacts_batchOperations_removeFail =>
      'Não foi possível remover os contatos: verifique a lista novamente';

  @override
  String get contacts_batchOperations_commonSuccess =>
      'A operação foi concluída com sucesso';

  @override
  String get contacts_batchOperations_commonFail =>
      'Não foi possível concluir a operação';

  @override
  String get contacts_batchOperations_selectFiltered =>
      'Selecionar os filtrados';

  @override
  String get chat_searchMessages => 'Buscar mensagens';

  @override
  String get chat_searchMessages_placeholder =>
      'A partir de 3 caracteres, sem diferenciar maiúsculas';

  @override
  String get chat_searchMessages_results => 'Resultados da busca';

  @override
  String chat_searchMessages_results_found(int count) {
    return '$count mensagens encontradas';
  }

  @override
  String chat_searchMessages_results_channel(String name) {
    return 'Canal $name';
  }

  @override
  String chat_searchMessages_results_room(String name) {
    return 'Sala $name';
  }

  @override
  String chat_searchMessages_results_contact(String name) {
    return 'Conversa com $name';
  }

  @override
  String get app_offline => 'Offline';

  @override
  String get app_offline_unableToMessage =>
      'Você não pode enviar mensagens nem realizar outras ações no modo offline';

  @override
  String get app_offline_sharedMode => 'Histórico combinado';

  @override
  String get settings_infoHardware => 'Hardware';

  @override
  String get appSettings_batteryLipoHv => 'LiPo HV (3,0-4,35V)';

  @override
  String get chat_sendImage => 'Enviar imagem';

  @override
  String get chat_imagePickFailed => 'Não consegui abrir essa imagem';

  @override
  String get imageMessages_enableTitle => 'Ativar mensagens de imagem';

  @override
  String get imageMessages_enableSubtitle =>
      'Envie as imagens pela malha. Requer um único download do modelo de imagem.';

  @override
  String get imageMessages_modelSectionTitle => 'Modelo de imagem';

  @override
  String get imageMessages_downloadModel => 'Baixar';

  @override
  String get imageMessages_cancelDownload => 'Cancelar';

  @override
  String get imageMessages_removeModel => 'Remover modelo';

  @override
  String get imageMessages_modelReady => 'Pronto';

  @override
  String get imageMessages_modelNotPublished =>
      'Ainda não publicado — esta versão não pode baixá-lo.';

  @override
  String get imageMessages_downloadFailed =>
      'O modelo de imagem não pôde ser baixado.';

  @override
  String get imageMessages_autoProcessTitle =>
      'Processar imagens automaticamente';

  @override
  String get imageMessages_autoProcessSubtitle =>
      'Reconstrói cada imagem assim que ela chega. Usa cerca de 2 GB de memória por um segundo a cada vez; deixe desativado para reconstruir com um toque.';

  @override
  String get imageSend_title => 'Enviar imagem';

  @override
  String get imageSend_cropNote =>
      'Redimensionado para 512 × 512 · a proporção de aspecto não foi preservada';

  @override
  String imageSend_lossyNote(int bytes) {
    return 'Comprimido para cerca de $bytes bytes. O modelo do receptor reconstrói-o, por isso os detalhes serão diferentes.';
  }

  @override
  String get imageSend_viewOriginal => 'Original';

  @override
  String get imageSend_viewReconstruction => 'O que os destinatários veem';

  @override
  String get imageSend_reconstructionUnavailable =>
      'Este dispositivo não pode pré-visualizar a reconstrução.';

  @override
  String get imageSend_modelNotDownloaded =>
      'O modelo de imagem ainda não foi transferido. Transfira-o nas Configurações para enviar imagens.';

  @override
  String get imageSend_originalSize => 'Original';

  @override
  String get imageSend_onAirSize => 'No ar';

  @override
  String get imageSend_quality => 'Qualidade';

  @override
  String get imageSend_qualityStandard => 'Padrão';

  @override
  String get imageSend_qualityHigh => 'Alta';

  @override
  String get imageSend_packetsLabel => 'Pacotes';

  @override
  String get imageSend_airtimeLabel => 'Tempo em transmissão';

  @override
  String get imageSend_sizeLabel => 'Carga útil';

  @override
  String imageSend_packetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pacotes',
      one: 'pacote',
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
  String get imageSend_radioUnknownTitle =>
      'Configurações de rádio desconhecidas';

  @override
  String get imageSend_radioUnknownBody =>
      'Conecte-se a um dispositivo para que o tempo de transmissão possa ser calculado.';

  @override
  String get imageSend_longSendTitle => 'Transmissão longa';

  @override
  String imageSend_longSendBody(String duration) {
    return 'Isso manterá o canal por cerca de $duration.';
  }

  @override
  String get imageSend_floodNote =>
      'Roteamento por inundação: cada repetidor ao alcance retransmite cada pacote, fazendo com que o canal permaneça ocupado por mais tempo do que isso.';

  @override
  String get imageSend_parityTitle => 'Pacote de recuperação';

  @override
  String get imageSend_paritySubtitle =>
      'Um pacote extra. As mensagens em grupo não são confirmadas, então isso permite que o destinatário reconstrua a imagem caso um único pacote seja perdido.';

  @override
  String get imageSend_send => 'Enviar';

  @override
  String get imageSend_cancel => 'Cancelar';

  @override
  String get imageSend_encodeFailed => 'Esta imagem não pode ser codificada.';

  @override
  String get imageSend_codecDownloading =>
      'O modelo de imagem ainda está baixando.';

  @override
  String get imageSend_codecUnavailable =>
      'O envio de imagem não está disponível neste dispositivo.';

  @override
  String get imageSend_codecDisabled =>
      'As mensagens de imagem estão desativadas nas configurações.';

  @override
  String get imageSend_deviceUnsupported =>
      'Este rádio não pode enviar pacotes de imagem. Conecte um dispositivo com firmware companheiro versão 1.15.0 ou superior.';

  @override
  String get imageSend_directMessagesUnsupported =>
      'As imagens viajam como dados em grupo, portanto, só podem ser enviadas para um canal — não em mensagem direta.';

  @override
  String get imageSend_tooLarge =>
      'Essa imagem foi codificada em mais pacotes do que o formato de malha permite.';

  @override
  String imageSend_sentConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'pacotes',
      one: 'pacote',
    );
    return 'Imagem enviada como $count $_temp0.';
  }

  @override
  String imageSend_sendFailed(String error) {
    return 'A imagem não pôde ser enviada: $error';
  }

  @override
  String imageSend_sendingProgress(int sent, int total) {
    return 'Envio da imagem — pacote $sent de $total';
  }

  @override
  String receivedImage_senderPrefix(String prefix) {
    return 'Nó $prefix';
  }

  @override
  String receivedImage_incoming(int received, int total) {
    return '$received de $total pacotes';
  }

  @override
  String get receivedImage_queued => 'Aguardando para decodificar';

  @override
  String get receivedImage_tapToDecode => 'Toque para decodificar';

  @override
  String get receivedImage_decoding => 'Reconstruindo… cerca de 1 segundo';

  @override
  String receivedImage_incomplete(int received, int total) {
    return 'Imagem incompleta — $received de $total pacotes chegaram';
  }

  @override
  String get receivedImage_corrupt => 'A imagem não pôde ser reconstruída';

  @override
  String get receivedImage_decoderMissing =>
      'Imagem recebida — a decodificação de imagens está desativada';

  @override
  String get receivedImage_evicted => 'A imagem não está mais armazenada';

  @override
  String get receivedImage_retry => 'Tente novamente';

  @override
  String get receivedImage_decodeAgain => 'Decodifique novamente';

  @override
  String get receivedImage_openSettings => 'Configurar';

  @override
  String get receivedImage_tapToProcess => 'Toque para processar';

  @override
  String get receivedImage_save => 'Guardar imagem';

  @override
  String receivedImage_shareCaption(int bytes) {
    return 'Reconstruído por IA a partir de $bytes bytes; os detalhes finos são gerados, não transmitidos.';
  }

  @override
  String get receivedImage_packetInfo => 'Informações do pacote';

  @override
  String get receivedImage_parityRecovered =>
      'Um pacote foi reconstruído a partir do pacote de recuperação.';

  @override
  String receivedImage_decodeTime(int ms) {
    return 'Reconstruído em $ms ms';
  }

  @override
  String get receivedImage_saveFailed => 'Não foi possível guardar a imagem';

  @override
  String receivedImage_awaiting(int bytes, int packets) {
    String _temp0 = intl.Intl.pluralLogic(
      packets,
      locale: localeName,
      other: 'pacotes',
      one: 'pacote',
    );
    return '$bytes bytes · $packets $_temp0';
  }

  @override
  String imageSend_secondsValue(String seconds) {
    return '$seconds segundos';
  }

  @override
  String imageSend_minutesSecondsValue(String minutes, String seconds) {
    return '$minutes min $seconds s';
  }

  @override
  String get map_copyCoordsFromMap => 'Copiar coordenadas';

  @override
  String get map_coordsCopied => 'Coordenadas copiadas';

  @override
  String get appSettings_yandexApiKey => 'Chave da API Yandex Tiles';

  @override
  String get appSettings_yandexApiKeyMissing =>
      'Não definida — o OpenStreetMap é exibido';

  @override
  String get appSettings_yandexApiKeyDialogDescription =>
      'Insira sua própria chave do painel de desenvolvedor da Yandex. O plano gratuito da Tiles API permite até 30 solicitações por segundo. Dados do mapa © Yandex.';

  @override
  String get appSettings_yandexSigningSecret =>
      'Segredo de assinatura da Yandex';

  @override
  String get appSettings_yandexSigningSecretMissing =>
      'Não definido — as solicitações são enviadas sem assinatura';

  @override
  String get appSettings_yandexSigningSecretDialogDescription =>
      'Opcional. Cole o segredo de assinatura vinculado à sua chave no console da Yandex. No modo de assinatura opcional, solicitações sem assinatura também funcionam.';

  @override
  String get appSettings_yandexTileScale => 'Resolução dos blocos da Yandex';

  @override
  String appSettings_yandexTileScaleSubtitle(String scale) {
    return 'Atual: $scale';
  }

  @override
  String get appSettings_yandexTileScaleDescription =>
      'Valores maiores solicitam o mesmo bloco com mais pixels — mais nítido em telas densas, porém com mais tráfego e espaço em cache.';

  @override
  String get settings_aboutYandexMapsTerms =>
      'Blocos do mapa por Yandex Maps. Termos de uso: \nhttps://yandex.ru/legal/maps_termsofuse/';

  @override
  String get map_showMarksFromChannels => 'Mostrar marcadores de...';

  @override
  String get map_markerStyleTitle => 'Estilo do marcador';

  @override
  String get map_markerStyleColor => 'Cor de preenchimento';

  @override
  String get map_markerStyleIcon => 'Ícone';

  @override
  String get map_removeMarkerForEveryone => 'Remover para todos';

  @override
  String get chat_poiRemoved => 'POI removido';

  @override
  String get chat_blockSender => 'Bloquear remetente';

  @override
  String get chat_unblockSender => 'Desbloquear remetente';

  @override
  String get chat_senderBlocked => 'remetente bloqueado';

  @override
  String get chat_blockedSenders => 'Remetentes bloqueados';

  @override
  String get chat_blockedSendersEmpty => 'Nenhum remetente bloqueado';

  @override
  String get chat_blockedSendersAllChannels => 'Todos os canais';

  @override
  String get chat_blockSenderName => 'Nome do remetente';

  @override
  String get chat_hideBlockedSenderMessages => 'Ocultar as linhas de mensagens';

  @override
  String get chat_showBlockedSenderMessages => 'Mostrar as linhas de mensagens';

  @override
  String get imageSend_previewShowAsReceived => 'Ver como será recebido';

  @override
  String get imageSend_previewShowOriginal => 'Ver original';

  @override
  String get imageSend_previewAsReceived =>
      'É assim que os destinatários verão a imagem';

  @override
  String get imageSend_previewDecodeFailed =>
      'Não foi possível decodificar a pré-visualização';

  @override
  String get settings_modSettingsLastHopSignal =>
      'Mostrar SNR/RSSI do último salto nos canais';

  @override
  String get repeater_cliClearNeighbors => 'Limpar lista de vizinhos';

  @override
  String get settings_backgroundPermissions =>
      'Solicitar novamente as permissões em segundo plano';

  @override
  String get settings_backgroundPermissionsSubtitle =>
      'Verificar a isenção de otimização de bateria e solicitá-la novamente';

  @override
  String get settings_backgroundPermissionsGranted =>
      'A permissão já foi concedida';

  @override
  String get chat_selectSendAction => 'Selecionar ação de envio';

  @override
  String get chat_sendImageLora => 'Enviar imagem via MeshCore';

  @override
  String get reaction_report => 'Reações de emoji';

  @override
  String get messageHistoryMigrationWarningTitle =>
      'O histórico de mensagens foi migrado parcialmente';

  @override
  String messageHistoryMigrationWarningDescription(
    int histories,
    int messages,
  ) {
    return 'Durante a migração não foi possível recuperar $histories conversas e $messages mensagens avulsas. O restante do histórico foi preservado.';
  }

  @override
  String get messageHistoryMigrationManage => 'Gerenciar o armazenamento';

  @override
  String get settings_modSettingsMessageStorage => 'Armazenamento de mensagens';

  @override
  String get messageHistoryDatabaseTitle => 'Gerenciamento do banco de dados';

  @override
  String get messageHistoryDatabaseSubtitle =>
      'Estatísticas, recuperação e manutenção do histórico de mensagens';

  @override
  String get messageHistoryDatabaseOverview => 'Estado do banco de dados';

  @override
  String get messageHistoryDatabasePath => 'Caminho do banco de dados';

  @override
  String get messageHistoryDatabaseFileSize => 'Tamanho do arquivo';

  @override
  String get messageHistoryDatabaseDirectCount => 'Mensagens diretas';

  @override
  String get messageHistoryDatabaseChannelCount => 'Mensagens de canais';

  @override
  String get messageHistoryDatabaseReclaimable => 'Espaço recuperável';

  @override
  String get messageHistoryDatabaseQuarantine => 'Quarentena da migração';

  @override
  String messageHistoryDatabaseQuarantineCount(int count, String size) {
    return 'Registros rejeitados: $count · $size';
  }

  @override
  String get messageHistoryDatabaseQuarantineEmpty =>
      'Nenhum registro rejeitado';

  @override
  String get messageHistoryDatabaseRetry => 'Repetir a recuperação';

  @override
  String get messageHistoryDatabaseRetryDescription =>
      'Verificar a quarentena novamente com o analisador atual e devolver ao histórico as mensagens recuperadas.';

  @override
  String messageHistoryDatabaseRetryResult(int restored, int remaining) {
    return 'Recuperados: $restored, restantes: $remaining';
  }

  @override
  String get messageHistoryDatabaseDiagnostic => 'Exportar diagnóstico';

  @override
  String get messageHistoryDatabaseDiagnosticDescription =>
      'Criar um relatório sem o texto das mensagens nem as chaves dos contatos.';

  @override
  String get messageHistoryDatabaseRecovery => 'Exportar dados de recuperação';

  @override
  String get messageHistoryDatabaseRecoveryDescription =>
      'Criar um arquivo apenas com os registros rejeitados. Ele pode conter conversas privadas.';

  @override
  String get messageHistoryDatabaseRecoveryWarningTitle =>
      'Exportação de dados confidenciais';

  @override
  String get messageHistoryDatabaseRecoveryWarningDescription =>
      'O arquivo de recuperação contém o texto original das mensagens rejeitadas e os identificadores das conversas. Revise-o antes de compartilhá-lo com alguém.';

  @override
  String get messageHistoryDatabaseDeleteAfterExportTitle =>
      'Excluir a quarentena após a exportação?';

  @override
  String get messageHistoryDatabaseDeleteAfterExportDescription =>
      'O arquivo de recuperação já foi salvo. Excluir do banco de dados os dados rejeitados que foram exportados?';

  @override
  String get messageHistoryDatabaseClearQuarantine => 'Excluir a quarentena';

  @override
  String get messageHistoryDatabaseClearQuarantineDescription =>
      'Excluir os dados rejeitados sem possibilidade de recuperação.';

  @override
  String get messageHistoryDatabaseClearWarningTitle =>
      'Excluir os dados rejeitados?';

  @override
  String get messageHistoryDatabaseClearWarningDescription =>
      'Após a exclusão, as mensagens em quarentena não poderão mais ser recuperadas nem exportadas.';

  @override
  String get messageHistoryDatabaseMaintenance => 'Manutenção';

  @override
  String get messageHistoryDatabaseIncrementalVacuum =>
      'Liberar espaço não utilizado';

  @override
  String get messageHistoryDatabaseIncrementalVacuumDescription =>
      'Devolver gradualmente ao sistema operacional as páginas do SQLite que não estão em uso.';

  @override
  String get messageHistoryDatabaseIncrementalVacuumUnavailableDescription =>
      'Este banco de dados requer primeiro um VACUUM completo.';

  @override
  String get messageHistoryDatabaseFullVacuum =>
      'VACUUM (reconstruir o banco por completo)';

  @override
  String get messageHistoryDatabaseFullVacuumDescription =>
      'Reconstruir por completo o arquivo do banco de dados. A operação pode demorar e exigir espaço livre adicional.';

  @override
  String get messageHistoryDatabaseFullVacuumWarningTitle =>
      'Reconstruir o banco de dados por completo?';

  @override
  String get messageHistoryDatabaseFullVacuumWarningDescription =>
      'Não feche o aplicativo até a operação terminar. O SQLite pode precisar de espaço adicional equivalente ao tamanho atual do banco de dados.';

  @override
  String get messageHistoryDatabaseCopyPath => 'Copiar o caminho';

  @override
  String get messageHistoryDatabasePathCopied => 'Caminho copiado';

  @override
  String messageHistoryDatabaseExportSaved(String path) {
    return 'Arquivo salvo: $path';
  }

  @override
  String get messageHistoryDatabaseExportShared =>
      'Arquivo enviado ao menu de compartilhamento do sistema';

  @override
  String messageHistoryDatabaseDeleted(int count) {
    return 'Registros excluídos: $count';
  }

  @override
  String get messageHistoryDatabaseOperationComplete => 'Operação concluída';

  @override
  String messageHistoryDatabaseOperationFailed(String error) {
    return 'A operação falhou: $error';
  }

  @override
  String get settings_supportDevelopment => 'Apoiar o desenvolvimento';

  @override
  String get donate_intro =>
      'Obrigado pela visita!\nSe você gostou desta modificação, pode apoiar o seu desenvolvimento com uma doação.';

  @override
  String get donate_tipLinkLabel => 'Link para gorjetas:';

  @override
  String get donate_upstreamAuthor =>
      'O autor do meshcore_open original — zjs81 — aceita doações aqui:';

  @override
  String get chat_canvasV4ToolText => 'Texto';

  @override
  String get chat_canvasV4TextAlignLeft => 'Esquerda';

  @override
  String get chat_canvasV4TextAlignCenter => 'Centro';

  @override
  String get chat_canvasV4TextAlignRight => 'Direita';

  @override
  String chat_canvasV4TextWidth(int cells) {
    return 'Largura da área: $cells';
  }

  @override
  String chat_canvasV4TextFontSize(int size) {
    return 'Tamanho da fonte: $size';
  }

  @override
  String get channels_mcotxtPlainWhenSmaller =>
      'Enviar uma mensagem normal se for mais compacta';

  @override
  String get settings_modSettingsRecoverLongEchoes =>
      'Recuperar repetições de pacotes longos';

  @override
  String get settings_modSettingsRecoverLongEchoesDscr =>
      'Reconhecer uma cópia do registro RX da nossa própria mensagem de canal cortada pelo limite de quadro BLE';

  @override
  String get chat_canvasV4TextSize => 'Tamanho do texto';

  @override
  String chat_unknownAppDataPlaceholder(
    String namespace,
    int subtype,
    int version,
  ) {
    return 'Recebido um pacote de subtipo desconhecido ($namespace, subtipo $subtype versão $version); pode ser necessário atualizar o aplicativo';
  }

  @override
  String chat_unknownAppDataPlaceholderNamespace(String namespace) {
    return 'Recebido um pacote em um formato que este aplicativo não consegue ler ($namespace); pode ser necessário atualizar o aplicativo';
  }

  @override
  String get chat_showWithoutMarkdown => 'Mostrar sem Markdown';

  @override
  String get chat_showWithMarkdown => 'Mostrar com Markdown';

  @override
  String get channels_scanQrInstructions =>
      'Aponte a câmera para o código QR de um canal';

  @override
  String get channels_invalidQrCode => 'Este não é um código QR de canal';

  @override
  String channels_qrAlreadyAdded(String name) {
    return 'O canal \"$name\" já foi adicionado';
  }

  @override
  String get channels_shareQrHint =>
      'Escaneie o código QR para adicionar o canal.';

  @override
  String get channels_shareSecretKey => 'Chave secreta';

  @override
  String get channels_shareRegionScope => 'Região do canal';

  @override
  String get channels_shareKeyCopied => 'Chave secreta copiada';

  @override
  String get channels_shareLinkCopied => 'Link copiado';

  @override
  String get channels_shareQrTapToCopy =>
      'Toque no código QR para copiá-lo como imagem.';

  @override
  String get channels_shareQrTapToShare =>
      'Toque no código QR para salvá-lo ou compartilhá-lo como imagem.';

  @override
  String get channels_shareQrImageCopied => 'Código QR copiado como imagem';

  @override
  String get channels_shareQrImageFailed =>
      'Não foi possível preparar a imagem do código QR';

  @override
  String channels_qrUpdateExisting(String name) {
    return 'O canal $name já existe. Atualizar suas propriedades?';
  }

  @override
  String get settings_modSettingsDirectEchoRecovery =>
      'Receber mensagens diretas sem esperar a rota ser concluída';

  @override
  String get settings_modSettingsDirectEchoRecoveryDscr =>
      'Atenção! A chave privada do nó será exportada para a memória do aplicativo, para que o próprio aplicativo, e não o nó, descriptografe o pacote.';

  @override
  String get settings_modSettingsDirectEchoRecoveryPrompt =>
      'Ativar o recebimento acelerado de mensagens diretas?\nPara isso, a chave privada do nó será extraída para a memória RAM do aplicativo.';

  @override
  String get channelPath_incompletePaths => 'Caminhos incompletos';

  @override
  String channelPath_incompletePathTitle(int index, String hops) {
    return 'Caminho incompleto $index • $hops';
  }

  @override
  String get channelPath_copyInvertedPath => 'Copiar a rota inversa';

  @override
  String get channelPath_invertedPathCopied => 'Rota inversa copiada';

  @override
  String get discoveredContacts_alreadyAdded => 'O nó já está nos contatos';

  @override
  String get chat_floodRegionNode => 'Região do nó';

  @override
  String chat_floodRegionNodeWith(String region) {
    return 'Região do nó: $region';
  }

  @override
  String get chat_floodRegionNone => 'Sem região';

  @override
  String get chat_stopSending => 'parar envio';

  @override
  String get urlImage_enable => 'Ativar imagens de URL';

  @override
  String get urlImage_possible =>
      'Possível imagem de URL; ative-a em Configurações.';

  @override
  String get settings_radioSettingsNotApplied =>
      'O rádio não aplicou estas configurações';

  @override
  String get settings_publicKeyCopied => 'Chave pública copiada';

  @override
  String get channels_noFreeSlots => 'Todos os slots de canal estão em uso';

  @override
  String get repeater_frequencyRangeHelper => '150-2500 MHz';

  @override
  String get repeater_frequencyInvalid => 'Frequência inválida (150-2500 MHz)';

  @override
  String get repeater_txPowerRangeHelper => '-9 a 30 dBm';

  @override
  String get repeater_recvErrors => 'Erros de Recepção';

  @override
  String get room_postsStored => 'Publicações';

  @override
  String get room_postsPushed => 'Publicações Enviadas';

  @override
  String get repeater_cliRegionLoadActive =>
      'Modo de carregamento de regiões: envie um nome de região por linha, indentado com espaços sob sua região pai (adicione F após o nome para permitir inundação). As linhas não recebem resposta. Envie uma linha vazia para terminar e depois \"region save\" para salvar o resultado.';

  @override
  String get repeater_cliRegionLoadHint =>
      'Linha de região, ou vazia para terminar';

  @override
  String get repeater_cliRegionLoadEnd => '(fim do carregamento de regiões)';

  @override
  String get repeater_cliHelpRegionDef =>
      'Define uma cadeia de regiões em um único comando: cada nome é adicionado sob o anterior; \"name,parent\" adiciona o nome e continua sob o pai indicado. Responde com a lista de regiões.';

  @override
  String get repeater_cliHelpSetFloodMaxUnscoped =>
      'Define o número máximo de saltos para encaminhar pacotes de inundação sem escopo regional (0-64).';

  @override
  String get repeater_cliHelpSetFloodMaxAdvert =>
      'Define o número máximo de saltos para encaminhar anúncios de inundação (0-64).';

  @override
  String get repeater_cliHelpGetFloodMaxUnscoped =>
      'Mostra o número máximo de saltos para pacotes de inundação sem escopo regional.';

  @override
  String get repeater_cliHelpGetFloodMaxAdvert =>
      'Mostra o número máximo de saltos para os anúncios de inundação.';

  @override
  String get repeater_cliHelpSetRadioFemRxGain =>
      'Ativa ou desativa o ganho RX (LNA) do módulo frontal de LoRa. Placas sem esse módulo respondem \"Error: unsupported\".';

  @override
  String get repeater_cliHelpSetRadioFemTxGain =>
      'Ativa ou desativa o ganho TX (PA) do módulo frontal de LoRa. Placas sem esse módulo respondem \"Error: unsupported\".';

  @override
  String get repeater_cliHelpGetRadioFemRxGain =>
      'Mostra se o ganho RX do módulo frontal de LoRa está ativado.';

  @override
  String get repeater_cliHelpGetRadioFemTxGain =>
      'Mostra se o ganho TX do módulo frontal de LoRa está ativado.';

  @override
  String get repeater_bridgeNote =>
      'Disponível apenas em firmware compilado com uma ponte (RS232 ou ESP-NOW).';

  @override
  String chat_longMessageRetryNote(int count) {
    return 'Mais de 158 bytes: enviado no máximo $count vezes';
  }

  @override
  String get contacts_notInNodeMemory => 'Não adicionado à memória do nó';

  @override
  String get contacts_addToNodeTitle => 'Adicionar à memória do nó?';

  @override
  String contacts_addToNodeMessage(String contactName) {
    return 'Apenas o aplicativo conhece $contactName. Login, solicitações, compartilhamento e mensagens exigem que o contato esteja na memória do nó.';
  }

  @override
  String get contacts_addToNodeFailed =>
      'Não foi possível adicionar à memória do nó';

  @override
  String get contacts_addToNodeFull => 'A memória do nó está cheia';

  @override
  String get channels_shareCopyLink => 'Copiar link';

  @override
  String get dataFolder_inUseTitle => 'A pasta de dados já está em uso';

  @override
  String dataFolder_inUseBody(String path) {
    return 'Outra cópia do aplicativo em execução está usando esta pasta de dados:\n$path\n\nFeche essa cópia e inicie o aplicativo novamente.';
  }

  @override
  String get dataFolder_unavailableTitle =>
      'Não é possível usar a pasta de dados';

  @override
  String dataFolder_unavailableBody(String path) {
    return 'O aplicativo guarda seus dados nesta pasta, mas não consegue criá-la nem gravar nela:\n$path\n\nMova o aplicativo para uma pasta com permissão de gravação.';
  }

  @override
  String get dataFolder_missingPath =>
      'O parâmetro --data-dir não indica nenhuma pasta. Ele é escrito assim: --data-dir=<caminho>.';

  @override
  String get dataFolder_otherFolderHint =>
      'Ao iniciar, uma cópia do aplicativo pode receber uma pasta de dados própria: --data-dir=<caminho>. Um caminho relativo é contado a partir da pasta do aplicativo.';

  @override
  String dataFolder_details(String error) {
    return 'Detalhes: $error';
  }

  @override
  String get dataTransfer_offerTitle =>
      'Dados de uma instalação anterior encontrados';

  @override
  String dataTransfer_offerBody(String target) {
    return 'Antes, o aplicativo guardava seus dados nas pastas do sistema. Eles podem ser copiados para esta pasta de dados:\n$target';
  }

  @override
  String get dataTransfer_offerSources => 'Copiar de:';

  @override
  String dataTransfer_offerSize(String size) {
    return 'Tamanho: $size';
  }

  @override
  String get dataTransfer_offerSizeCounting => 'Tamanho: calculando…';

  @override
  String get dataTransfer_offerCopiedBefore => 'Estes dados já foram copiados:';

  @override
  String get dataTransfer_offerNote =>
      'As pastas originais permanecem como estão. Antes de copiar, feche as outras cópias do aplicativo em execução.';

  @override
  String get dataTransfer_copy => 'Copiar';

  @override
  String get dataTransfer_startEmpty => 'Começar com dados vazios';

  @override
  String get dataTransfer_progressTitle => 'Copiando dados';

  @override
  String dataTransfer_progress(String copied, String total) {
    return 'Copiado $copied de $total';
  }

  @override
  String get dataTransfer_progressNote =>
      'Fechar a janela interrompe a cópia; ela será oferecida novamente na próxima inicialização.';

  @override
  String get dataTransfer_failedTitle => 'Não foi possível copiar os dados';

  @override
  String get dataTransfer_failedBody =>
      'As pastas originais não foram alteradas. A cópia será oferecida novamente na próxima inicialização; antes disso, feche as outras cópias do aplicativo.';

  @override
  String get dataCleanup_title => 'Excluir os dados antigos?';

  @override
  String get dataCleanup_body =>
      'Em uma inicialização anterior, os dados foram copiados para esta pasta de dados. Os originais continuam nas pastas do sistema e podem ser excluídos se tudo estiver aqui:';

  @override
  String get dataCleanup_note =>
      'Estes dados não serão mais oferecidos a outras cópias novas do aplicativo. Das pastas compartilhadas de arquivos temporários e de documentos, são excluídos apenas os arquivos copiados para cá.';

  @override
  String get dataCleanup_keep => 'Manter';

  @override
  String get dataCleanup_progress => 'Excluindo os dados antigos…';

  @override
  String dataCleanup_partial(int count) {
    return 'Não foi possível esvaziar algumas pastas antigas ($count): outra cópia do aplicativo em execução pode estar usando seus arquivos. A pergunta será repetida na próxima inicialização.';
  }

  @override
  String get settings_modSettingsExactQuoteLatest =>
      'Usar também para a última mensagem do autor';

  @override
  String get settings_modSettingsExactQuoteLatestDscr =>
      'Desativado: a resposta à última mensagem do autor inclui apenas uma menção. Ativado: é tratado corretamente o caso em que a sua última mensagem e a dos outros não coincidem e são mensagens diferentes.';

  @override
  String get channelPath_deliveryConfirmedPath =>
      'Entrega confirmada pelo caminho';

  @override
  String get channelPath_deliveryPathUnknown =>
      'Ainda não foi recebida confirmação de entrega para esta mensagem, ou não foi possível determinar a rota.';

  @override
  String get channelPath_deliveredDirectly =>
      'Entregue diretamente, sem repetidores';

  @override
  String get channelPath_incompletePathsNote =>
      'Os pacotes de mensagens diretas carregam apenas os saltos restantes, não a rota completa: cada repetidor, por sua vez, retira a si mesmo do caminho restante.';

  @override
  String get discoveredContacts_previouslyHeard => 'nós ouvidos anteriormente';

  @override
  String map_wardriveBackgroundNeeds(String requirement) {
    return 'O modo em segundo plano precisa de: $requirement. Toque na opção novamente para passar à próxima permissão.';
  }

  @override
  String map_wardriveBackgroundOff(String requirement) {
    return 'O modo em segundo plano está desativado, ainda falta: $requirement.';
  }

  @override
  String get map_wardriveRequirementNotifications =>
      'a permissão de notificações';

  @override
  String get map_wardriveRequirementLocationServices =>
      'a localização do telefone ativada';

  @override
  String get map_wardriveRequirementLocationAlways =>
      'o acesso à localização \"Permitir o tempo todo\"';

  @override
  String get map_wardriveRequirementBattery =>
      'a otimização de bateria desativada para o aplicativo';

  @override
  String get map_wardriveRequirementBackgroundActivity =>
      'a atividade em segundo plano permitida (sem restrição nas configurações de bateria)';

  @override
  String get settings_modSettingsSenderNameScale =>
      'Tamanho dos nomes dos remetentes';

  @override
  String get reviewMode_dialogTitle => 'Entrar no modo de revisão?';

  @override
  String get reviewMode_dialogBody =>
      'O modo de revisão conecta-se a um rádio simulado com contatos, canais e mensagens de exemplo. Não é necessário um rádio real.';

  @override
  String get reviewMode_confirm => 'Entrar';

  @override
  String get reviewMode_cancel => 'Cancelar';

  @override
  String get reviewMode_banner => 'Modo de revisão — dados simulados';

  @override
  String get reviewMode_sendTest => 'Enviar mensagem de teste';

  @override
  String get reviewMode_testSent => 'Uma mensagem de teste chegará em breve.';

  @override
  String get reviewMode_exit => 'Sair';

  @override
  String reviewMode_connectFailed(Object error) {
    return 'Não foi possível iniciar o modo de revisão: $error';
  }

  @override
  String get channels_waitForSync =>
      'Os canais ainda estão sendo carregados do rádio. Tente novamente quando a sincronização terminar.';

  @override
  String channels_nameTooLong(Object maxBytes) {
    return 'O nome é muito longo (máx. $maxBytes bytes).';
  }

  @override
  String repeater_valueRequired(Object field) {
    return '$field: insira um valor';
  }

  @override
  String get losMapDetailTooltip => 'Detalhe do mapa';

  @override
  String get losUnitsTooltip => 'Unidades';

  @override
  String get losDistance => 'Distância';

  @override
  String get losClearance => 'Folga';

  @override
  String get losBlockedBy => 'Bloqueado por';

  @override
  String get losObstruction => 'Obstrução';

  @override
  String losDistanceFromA(Object distance) {
    return '$distance de A';
  }

  @override
  String get losWorstBadge => 'PIOR';

  @override
  String losBlockedAmount(Object amount) {
    return 'Bloqueado $amount';
  }

  @override
  String get losFromA => 'De A';

  @override
  String get losFromB => 'De B';

  @override
  String get losElevation => 'Elevação';

  @override
  String get losCenterOnMap => 'Centralizar no mapa';

  @override
  String get losStatusClear => 'Livre';

  @override
  String get losStatusMarginal => 'Marginal';

  @override
  String get losStatusBlocked => 'Bloqueado';

  @override
  String get losStatusCheckingShort => 'Verificando';

  @override
  String get losStatusNoResult => 'Sem resultado';

  @override
  String get losSelectedPill => 'Selecionado';

  @override
  String get gif_tapToLoad => 'Toque para carregar o GIF';

  @override
  String get gif_loadFailedRetry =>
      'Não foi possível carregar o GIF\nToque para tentar novamente';

  @override
  String get qr_cameraPermissionDenied =>
      'Permissão da câmera negada.\nAtive o acesso à câmera nas configurações.';

  @override
  String get qr_cameraUnsupported =>
      'Câmera não compatível com este dispositivo.';

  @override
  String qr_cameraStartFailed(Object details) {
    return 'Falha ao iniciar a câmera.\n$details';
  }

  @override
  String imageMessages_downloadFailedWithError(Object error) {
    return 'Não foi possível baixar o modelo de imagem: $error';
  }

  @override
  String get map_nodeId => 'ID';

  @override
  String get map_markerHideHint =>
      'Ocultar: fica oculto até você sair do mapa.';

  @override
  String get map_markerRemoveHint =>
      'Remover: continua oculto até você restaurá-lo no menu de filtros.';

  @override
  String get map_markerRemoved => 'Marcador removido';

  @override
  String get map_restoreRemovedMarkers => 'Restaurar marcadores removidos';

  @override
  String map_restoreRemovedMarkersSubtitle(Object count) {
    return '$count removidos';
  }

  @override
  String map_markersRestored(Object count) {
    return '$count marcadores restaurados';
  }

  @override
  String get map_setLocationConfirmTitle => 'Definir como sua localização?';

  @override
  String map_setLocationConfirmBody(Object lat, Object lon) {
    return 'Seu nó vai anunciar esta posição:\n$lat, $lon';
  }

  @override
  String get map_setLocationAction => 'Definir localização';

  @override
  String get map_locationSetSuccess => 'Localização do nó atualizada';

  @override
  String get map_locationSetFailed =>
      'O dispositivo não confirmou a nova localização. Tente novamente.';

  @override
  String map_poiClusterTitle(Object count) {
    return '$count marcadores aqui';
  }

  @override
  String map_poiClusterSemantics(Object count) {
    return '$count marcadores compartilhados. Toque para listá-los.';
  }

  @override
  String map_youWithMarkers(Object count) {
    return 'Você e $count marcadores';
  }

  @override
  String map_sharedMarkerSemantics(Object label) {
    return 'Marcador compartilhado: $label';
  }

  @override
  String map_nodeMarkerSemantics(Object name, Object status, Object type) {
    return '$name, $type, $status';
  }

  @override
  String mapCache_zoomLevel(Object zoom) {
    return 'Zoom $zoom';
  }

  @override
  String mapCache_sizeBytes(Object size) {
    return '$size B';
  }

  @override
  String mapCache_sizeKilobytes(Object size) {
    return '$size KB';
  }

  @override
  String mapCache_sizeMegabytes(Object size) {
    return '$size MB';
  }

  @override
  String mapCache_sizeGigabytes(Object size) {
    return '$size GB';
  }

  @override
  String mapCache_downloadCancelled(Object count) {
    return 'Download cancelado. $count blocos em cache.';
  }

  @override
  String get mapCache_tooManyTilesTitle => 'Área muito grande';

  @override
  String mapCache_tooManyTiles(Object count, Object max) {
    return 'Esta área precisa de $count blocos, mais do que o limite de $max. Escolha uma área menor ou reduza o zoom máximo.';
  }

  @override
  String get chat_clearChatConfirm =>
      'Isto apaga todas as mensagens desta conversa deste dispositivo. Não é possível desfazer.';

  @override
  String get channels_clearChatConfirm =>
      'Isto apaga todas as mensagens deste canal deste dispositivo, incluindo as imagens recebidas. Não é possível desfazer.';

  @override
  String get channels_timeNow => 'agora';

  @override
  String channels_timeMinutes(Object minutes) {
    return '${minutes}min';
  }

  @override
  String channels_timeHours(Object hours) {
    return '${hours}h';
  }

  @override
  String channels_timeDays(Object days) {
    return '${days}d';
  }

  @override
  String channels_indexChip(Object index) {
    return 'CH $index';
  }

  @override
  String get reaction_unknownSender => 'Desconhecido';

  @override
  String get pathMap_noSelfGpsFix => 'O nó local não tem sinal de GPS';

  @override
  String pathTrace_sendFailed(Object error) {
    return 'Não foi possível enviar o rastreamento de caminho: $error';
  }

  @override
  String get losErrorNoInternet =>
      'Os dados de elevação precisam de conexão com a internet';

  @override
  String get losResultStale => 'Desatualizado: a altura da antena mudou';

  @override
  String losSnrValue(Object snr) {
    return '$snr dB';
  }

  @override
  String losFrequencyValue(Object frequency) {
    return '$frequency MHz';
  }

  @override
  String losKFactorValue(Object kFactor) {
    return 'k=$kFactor';
  }

  @override
  String get losEndpointA => 'A';

  @override
  String get losEndpointB => 'B';

  @override
  String get units_km => 'km';

  @override
  String get units_mi => 'mi';

  @override
  String get units_m => 'm';

  @override
  String get units_ft => 'ft';

  @override
  String get telemetry_loading => 'Carregando telemetria…';

  @override
  String telemetry_axisValue(Object x, Object y, Object z) {
    return 'X: $x, Y: $y, Z: $z';
  }

  @override
  String telemetry_colourValue(Object blue, Object green, Object red) {
    return 'R: $red, G: $green, B: $blue';
  }

  @override
  String telemetry_altitudeValueFeet(Object feet) {
    return '$feet ft';
  }

  @override
  String telemetry_distanceValueFeet(Object feet) {
    return '$feet ft';
  }

  @override
  String get settings_notConnectedError =>
      'Sem conexão com um rádio. Conecte e tente novamente.';

  @override
  String get settings_requiresConnection =>
      'Conecte-se a um rádio para usar isto';

  @override
  String settings_txPowerInvalidRange(Object max, Object min) {
    return 'Potência de TX inválida ($min a $max dBm)';
  }

  @override
  String get settings_contactSettingsSaved => 'Configurações do contato salvas';

  @override
  String get settings_batteryToggleHint =>
      'Toque para alternar entre porcentagem e tensão';

  @override
  String get settings_publicKeyCopyHint => 'Copiar chave pública';

  @override
  String get settings_locationClearHelper =>
      'Deixe ambos os campos vazios para remover sua localização.';

  @override
  String get settings_locationCleared => 'Localização removida';

  @override
  String get settings_regionFetchDiscovering =>
      'Procurando repetidores próximos…';

  @override
  String settings_regionFetchProgress(Object current, Object total) {
    return 'Consultando o repetidor $current de $total…';
  }

  @override
  String get settings_regionFetchNoRepeaters =>
      'Ainda não há repetidores conhecidos. Adicione um repetidor como contato ou aguarde um anunciar, e tente novamente.';

  @override
  String get settings_regionFetchNoneResponded =>
      'Nenhum repetidor próximo respondeu. Aproxime-se de um repetidor e tente novamente.';

  @override
  String appSettings_sourceSummary(Object description, Object label) {
    return '$label - $description';
  }

  @override
  String get appSettings_routingSection => 'Roteamento';

  @override
  String get appSettings_imageMessagesSection => 'Mensagens de imagem';

  @override
  String get appSettings_showApiKey => 'Mostrar chave de API';

  @override
  String get appSettings_hideApiKey => 'Ocultar chave de API';

  @override
  String get translation_defaultModelName => 'Modelo';

  @override
  String translation_downloadProgressBytes(Object current, Object fileName) {
    return '$fileName: $current MB';
  }

  @override
  String translation_downloadProgressTotal(
    Object current,
    Object fileName,
    Object percent,
    Object total,
  ) {
    return '$fileName: $current / $total MB ($percent%)';
  }

  @override
  String translation_downloadedModelDetails(Object size, Object source) {
    return '$size MB • $source';
  }

  @override
  String get repeater_radioDisconnected => 'Rádio desconectado';

  @override
  String get repeater_radioDisconnectedHint =>
      'Reconecte-se ao seu rádio para enviar comandos, atualizar ou salvar alterações.';

  @override
  String get repeater_cliSend => 'Enviar comando';

  @override
  String get repeater_cliCopyTranscript => 'Copiar transcrição';

  @override
  String get repeater_cliShareTranscript => 'Compartilhar transcrição';

  @override
  String get repeater_cliTranscriptCopied => 'Transcrição copiada';

  @override
  String get repeater_cliClearHistoryConfirm =>
      'Limpar o histórico de comandos? Não é possível desfazer.';

  @override
  String get repeater_cliSearchCommands => 'Pesquisar comandos';

  @override
  String get repeater_cliNoMatchingCommands => 'Nenhum comando correspondente';

  @override
  String get debugLog_clearConfirm =>
      'Limpar todas as entradas do registro? Não é possível desfazer.';

  @override
  String get repeater_unsavedChangesTitle => 'Alterações não salvas';

  @override
  String get repeater_unsavedChangesMessage =>
      'Você tem alterações que não foram salvas no repetidor.';

  @override
  String get repeater_discardChanges => 'Descartar';

  @override
  String repeater_actionSentNoReply(Object action) {
    return '$action: comando enviado. O repetidor não responde a este comando.';
  }

  @override
  String repeater_invalidSettingValue(Object setting, Object value) {
    return '$setting: $value não é válido';
  }

  @override
  String repeater_txPowerOutOfRange(Object max, Object min, Object value) {
    return 'Potência de TX $value fora do intervalo ($min a $max dBm)';
  }

  @override
  String repeater_prvKeyLengthError(Object length) {
    return 'A chave privada deve ter exatamente $length caracteres hexadecimais';
  }

  @override
  String get contacts_advertFailed => 'Não foi possível enviar o anúncio';

  @override
  String get contacts_manageGroups => 'Gerenciar grupos';

  @override
  String community_shortId(Object id) {
    return 'ID: $id…';
  }

  @override
  String get tcpSectionTitle => 'TCP / IP';

  @override
  String get tcpConnectedToHeader => 'Conectado a';

  @override
  String get usbChooseSerialPort => 'Escolher porta serial';

  @override
  String neighbors_durationSeconds(Object seconds) {
    return '${seconds}s';
  }

  @override
  String neighbors_durationMinutes(Object minutes, Object seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String neighbors_durationHours(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get channels_dataScopeQuestion =>
      'Excluir os dados do canal apenas para este nó ou no histórico combinado de todos os nós do aplicativo?';

  @override
  String get channels_dataScopeThisNode => 'Este nó';

  @override
  String get channels_dataScopeAllNodes => 'Todos os nós';

  @override
  String get chat_historyLinkBanner =>
      'Existe um histórico de mensagens de um contato com este nome, mas com outra chave.';

  @override
  String get chat_historyLinkAttach => 'Vincular';

  @override
  String get chat_historyLinkTitle => 'Vincular o histórico?';

  @override
  String chat_historyLinkBody(String name, String key) {
    return 'Foi encontrado um histórico de um contato chamado \"$name\" com outra chave ($key). Vincule-o a esta conversa apenas se tiver certeza de que é a mesma pessoa, e não um homônimo. As duas chaves passarão então a ser um único contato no aplicativo.';
  }

  @override
  String get chat_historyLinked => 'O histórico foi vinculado.';

  @override
  String get scanner_getNodeTitle => 'Precisa de um novo nó?';

  @override
  String get scanner_getNodeBody =>
      'Do tamanho de uma carteira, roda MeshCore, GPS dual-band, à prova d\'água, bateria para 5 dias.';

  @override
  String get scanner_getNodeAction => 'Compre aqui';

  @override
  String get scanner_getNodeDisclosure =>
      'Link de afiliado: cada compra apoia o MeshCore Open.';

  @override
  String get networkMap_settingsSection => 'Mapa da rede';

  @override
  String get networkMap_uploadTitle => 'Compartilhar o que meu rádio ouve';

  @override
  String get networkMap_uploadExplanation =>
      'Quando isto está ativado e o seu rádio está conectado, o app envia um breve resumo dos pacotes que o seu rádio ouve para o mapa da rede do MeshCore Open, para que todos possam ver quais repetidores existem e como se conectam. Ele envia o tipo, a rota, os saltos, a intensidade do sinal e o tamanho de cada pacote, além dos nomes e localizações aproximadas dos repetidores, obtidos dos próprios anúncios. Nunca envia o texto das mensagens, quem fala com quem, nomes de canais, seus contactos nem a sua posição exata: as localizações são arredondadas para cerca de 2 km, e o seu app recebe um novo ID aleatório todos os dias.';

  @override
  String get networkMap_whatWeCollect => 'O que coletamos';

  @override
  String get networkMap_promptTitle => 'Ajudar a construir o mapa da rede?';

  @override
  String get networkMap_promptBody =>
      'O MeshCore Open pode compartilhar o que o seu rádio ouve com o mapa público da rede em map.meshcoreopen.org, para que todos possam ver quais repetidores existem e como se conectam.\n\nNunca envia o texto das mensagens, quem fala com quem, nomes de canais, seus contactos nem a sua posição exata. As localizações são arredondadas para cerca de 2 km.';

  @override
  String get networkMap_promptSettingsHint =>
      'Você pode mudar isso a qualquer momento em Configurações → Configurações do App → Mapa da rede.';

  @override
  String get networkMap_promptAccept => 'Compartilhar';

  @override
  String get networkMap_promptDecline => 'Não, obrigado';

  @override
  String get networkMap_statusOff => 'Desativado. Nada é enviado.';

  @override
  String get networkMap_statusWaiting =>
      'Ativado. Aguardando conexão com o rádio.';

  @override
  String get networkMap_statusNothingSent => 'Ativado. Nada enviado ainda.';

  @override
  String networkMap_statusLastSent(String time, int count) {
    return 'Último envio $time. $count pacotes hoje.';
  }

  @override
  String get networkMap_sourceLocal => 'Local';

  @override
  String get networkMap_sourceOnline => 'Online';

  @override
  String get networkMap_sourceBoth => 'Ambos';

  @override
  String get networkMap_zoomInHint =>
      'Aproxime o zoom para ver o mapa da rede online';

  @override
  String get networkMap_loadFailed =>
      'Não foi possível carregar o mapa da rede online';

  @override
  String get networkMap_inYourContacts => 'Nos seus contactos';

  @override
  String get networkMap_status => 'Estado';

  @override
  String get networkMap_statusActive => 'Ativo na última hora';

  @override
  String get networkMap_statusRecent => 'Ouvido no último dia';

  @override
  String get networkMap_statusStale => 'Não ouvido recentemente';

  @override
  String get networkMap_confirmed => 'Confirmado';

  @override
  String get networkMap_singleSource => 'Fonte única, ainda não confirmado';

  @override
  String get networkMap_reports => 'Relatórios';

  @override
  String get networkMap_locationEstimated =>
      'Localização aproximada, estimada a partir de quem o ouviu';

  @override
  String get networkMap_locationAdvertised =>
      'Localização aproximada, do próprio anúncio';

  @override
  String get networkMap_heardByRadio => 'Ouvido pelo seu rádio';

  @override
  String get networkMap_inYourArea => 'Na sua área';

  @override
  String get networkMap_farAway => 'Muito longe. A gestão não chegará até ele.';

  @override
  String get networkMap_addToContacts => 'Adicionar aos contactos';

  @override
  String get networkMap_manage => 'Gerenciar';

  @override
  String get networkMap_addedToContacts => 'Adicionado aos contactos';

  @override
  String get networkMap_addFailed => 'Não foi possível adicionar aos contactos';

  @override
  String get networkMap_unnamed => 'Repetidor sem nome';

  @override
  String get channelPath_sendAttemptsLabel => 'Tentativas de envio';

  @override
  String get settings_modSettingsHideChannelMute =>
      'Ocultar o botão de silenciar o canal';

  @override
  String appSettings_channelMinHopsDelay(int seconds) {
    return 'Pausa antes de reenviar: $seconds s';
  }

  @override
  String settings_modSettingsNoRetraInfoResends(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tentativas',
      one: '$count tentativa',
      zero: '$count tentativas',
    );
    return 'Não se propagou pela rede em $_temp0.';
  }

  @override
  String get channels_senderNameLabel => 'Remetente';

  @override
  String get channels_senderNameDefault => 'padrão';

  @override
  String get channels_senderNameTitle => 'Nome do remetente';

  @override
  String get channels_senderNameBody =>
      'Você pode alterar o nome para este canal.';

  @override
  String channels_senderNameBytes(int count, int max) {
    return '$count / $max bytes';
  }

  @override
  String get channels_senderNameLockedBySign =>
      'Um canal com assinatura MCMP envia com o nome do nó.';

  @override
  String get channels_senderNameNeedsFirmware =>
      'Requer firmware com código de versão 13 ou mais recente.';

  @override
  String get channels_senderNamePrivateRegion =>
      'A chave da região fica no repetidor, por isso o nome não pode ser alterado.';

  @override
  String get channels_senderNameResetBySign =>
      'O nome do remetente definido para este canal será redefinido.';

  @override
  String get powerSaving_title => 'Economia de energia';

  @override
  String get powerSaving_skipIdleDirectProgressParsing =>
      'Analisar o progresso só durante o envio';

  @override
  String get powerSaving_skipIdleDirectProgressParsingDescription =>
      'Não analisa os quadros de rádio para o progresso da entrega direta enquanto não houver envios acompanhados. A recepção de mensagens e as confirmações de entrega são mantidas.';

  @override
  String get powerSaving_cacheChannelKeyHashes =>
      'Armazenar em cache os parâmetros dos canais';

  @override
  String get powerSaving_cacheChannelKeyHashesDescription =>
      'Reutiliza o hash calculado de uma chave de canal inalterada ao processar pacotes recebidos. A verificação e a descriptografia das mensagens são mantidas.';

  @override
  String get powerSaving_pauseHiddenStatusAnimations =>
      'Pausar animações de status ocultas';

  @override
  String get powerSaving_pauseHiddenStatusAnimationsDescription =>
      'Para os pontos de envio e os indicadores pulsantes fora da área visível, sob outra tela e com o aplicativo inativo. Os indicadores visíveis continuam animados.';

  @override
  String get powerSaving_disableContinuousStatusAnimations =>
      'Indicadores de status estáticos';

  @override
  String get powerSaving_disableContinuousStatusAnimationsDescription =>
      'Substitui a animação dos pontos de envio e a pulsação suave dos indicadores de status por indicadores estáticos, inclusive na tela. Os status, os contadores de repetições e o processamento do envio são mantidos.';

  @override
  String get powerSaving_reduceBlePluginLogs =>
      'Menos logs de diagnóstico do Bluetooth';

  @override
  String get powerSaving_reduceBlePluginLogsDescription =>
      'Reduz a saída de diagnóstico do Bluetooth no Android, iOS e macOS. Avisos, erros e o registro de quadros do aplicativo são mantidos. Não tem efeito no Windows, no Linux nem no navegador.';

  @override
  String get powerSaving_deferBleLogDescriptions =>
      'Adiar as descrições do registro de quadros';

  @override
  String get powerSaving_deferBleLogDescriptionsDescription =>
      'Gera a descrição em texto quando ela é necessária para exibição ou cópia. Os dados do quadro e o horário são salvos imediatamente; o conteúdo do registro e a proteção de dados privados não mudam.';

  @override
  String get powerSaving_uiNotificationInterval =>
      'Intervalo de atualização da interface';

  @override
  String get powerSaving_uiNotificationDescription =>
      'Agrupa as atualizações comuns durante um fluxo de eventos. Um intervalo maior torna a exibição menos imediata. O processamento de pacotes e confirmações não é atrasado; as mudanças de estado da conexão mantêm a janela original de 50 ms.';

  @override
  String powerSaving_milliseconds(int milliseconds) {
    return '$milliseconds ms';
  }

  @override
  String get powerSaving_profile => 'Perfil';

  @override
  String get powerSaving_disabled => 'Desativado';

  @override
  String get powerSaving_balanced => 'Equilibrado';

  @override
  String get powerSaving_economical => 'Econômico';

  @override
  String get powerSaving_maximum => 'Economia máxima';

  @override
  String get powerSaving_custom => 'Configurações próprias';

  @override
  String get powerSaving_hiddenRadioStatsInterval =>
      'Intervalo das estatísticas de rádio com a tela oculta';

  @override
  String powerSaving_seconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get powerSaving_radioStatsDescription =>
      'Aplica-se quando a tela de estatísticas de rádio está coberta ou o aplicativo está inativo. A tela visível continua sendo atualizada a cada segundo. Outras funções podem solicitar atualizações mais frequentes.';

  @override
  String get powerSaving_customDescription =>
      'Os valores mínimos mantêm o comportamento original. Suas configurações próprias são salvas separadamente dos perfis predefinidos.';

  @override
  String get powerSaving_presetDescription =>
      'Os valores do perfil predefinido são fixos. Para alterá-los individualmente, escolha \"Configurações próprias\".';

  @override
  String get powerSaving_pauseHiddenRadioIndicator =>
      'Pausar a consulta do indicador de rádio oculto';

  @override
  String get powerSaving_pauseHiddenRadioIndicatorDescription =>
      'Interrompe a consulta para o indicador quando ele está oculto, coberto por outra tela ou o aplicativo está inativo. O envio de mensagens e outros usos da consulta mantêm as atualizações de que precisam.';

  @override
  String get powerSaving_batteryInterval =>
      'Intervalo de consulta da bateria do nó';

  @override
  String powerSaving_batteryDescription(int minutes) {
    return 'Aplica-se com o aplicativo aberto e em segundo plano. O limite de silêncio para o controle da conexão é de $minutes min; um intervalo maior atrasa a detecção de uma conexão que não responde. A atualização manual continua disponível.';
  }

  @override
  String get powerSaving_gpsInterval => 'Intervalo de atualização do GPS do nó';

  @override
  String get powerSaving_gpsDescription =>
      'Aplica-se com o aplicativo aberto e em segundo plano, somente se o GPS estiver ativado no nó. Um intervalo maior torna a posição exibida do nó menos atual. O GPS do telefone e o wardrive são configurados separadamente.';

  @override
  String get powerSaving_pauseIdleImageCleanup =>
      'Pausar a limpeza de imagens em repouso';

  @override
  String get powerSaving_pauseIdleImageCleanupDescription =>
      'A limpeza só é executada enquanto houver imagens incompletas ou imagens recém-concluídas guardadas para reconhecer duplicatas. O tempo de espera pelos pacotes que faltam não muda.';

  @override
  String get powerSaving_pauseHiddenGifs => 'Pausar GIFs ocultos';

  @override
  String get powerSaving_pauseHiddenGifsDescription =>
      'Para os quadros de GIF fora da área visível, sob outra tela e com o aplicativo inativo. Ao voltar, a reprodução é retomada, a menos que você tenha pausado o GIF manualmente.';

  @override
  String get powerSaving_backgroundReconnectInterval =>
      'Pausa entre reconexões em segundo plano';

  @override
  String get powerSaving_backgroundReconnectDescription =>
      'Somente BLE e TCP, depois das seis primeiras pausas de 1/2/4/8/16/30 segundos. Aplica-se com o aplicativo inativo; voltar ao aplicativo restaura o ritmo normal. Uma pausa maior pode atrasar a recuperação da conexão. O tempo de conexão é somado à pausa.';

  @override
  String get powerSaving_cpuSleepAlways =>
      'Permitir a suspensão da CPU sempre que possível';

  @override
  String get powerSaving_cpuSleepBle => 'Com conexão BLE';

  @override
  String get powerSaving_cpuSleepDescription =>
      'Permitir que o dispositivo entre em suspensão entre operações. As opções individuais se aplicam em segundo plano; todos os cenários ativos devem permitir a suspensão. A opção \"Sempre\" se aplica independentemente do cenário.';

  @override
  String get powerSaving_cpuSleepProxy => 'Com o proxy companion em execução';

  @override
  String get powerSaving_cpuSleepTcp => 'Com conexão TCP';

  @override
  String get powerSaving_cpuSleepTitle => 'Suspensão da CPU (Android)';

  @override
  String get powerSaving_cpuSleepWardrive => 'Com o wardrive em execução';

  @override
  String get powerSaving_cpuSleepUnconditional => 'Sempre, sem exceções';

  @override
  String get powerSaving_cpuSleepUnconditionalDescription =>
      'Libera completamente nossos bloqueios de ativação da CPU, inclusive durante as operações. A suspensão do dispositivo pode atrasá-las ou interrompê-las. Os bloqueios do Android e de outros componentes não mudam.';

  @override
  String get powerSaving_blePriorityTitle => 'Modo de conexão BLE com o nó';

  @override
  String get powerSaving_blePriorityDescription =>
      'Aplica-se após reconectar ao nó. \"Original\" não solicita mudanças; High prioriza a velocidade, Low power a economia de energia. Os parâmetros reais são escolhidos pelo Android e pelo nó; o modo econômico pode deixar a troca de dados mais lenta.';

  @override
  String get powerSaving_bleOriginal => 'Original';

  @override
  String get powerSaving_bleBalanced => 'Equilibrado (Balanced)';

  @override
  String get powerSaving_bleHigh => 'Alta velocidade (High)';

  @override
  String get powerSaving_bleLowPower => 'Economia de energia (Low power)';

  @override
  String get powerSaving_releaseTcpWifiLock =>
      'Não manter o Wi-Fi ativo para TCP';

  @override
  String get powerSaving_releaseTcpWifiLockDescription =>
      'Permitir a economia de energia normal do Wi-Fi com uma conexão TCP ao nó, inclusive via Tailscale. Aplica-se imediatamente, na tela e em segundo plano; o serviço em segundo plano e a configuração de suspensão da CPU não mudam. Em alguns dispositivos podem ocorrer atrasos ou quedas de conexão.';

  @override
  String get powerSaving_reduceDeliveryObservationWrites =>
      'Reduzir a regravação das estatísticas de entrega';

  @override
  String get powerSaving_reduceDeliveryObservationWritesDescription =>
      'Atualizar apenas a parte alterada das estatísticas de entrega armazenadas. O conteúdo e a ordem não mudam, e a gravação não é atrasada além do normal.';

  @override
  String get powerSaving_iosImmortalizerTitle =>
      'iOS: execução em segundo plano';

  @override
  String get powerSaving_iosImmortalizerDescription =>
      'Opções experimentais para a manutenção integrada do TCP em segundo plano. Disponíveis em \"Configurações próprias\"; os valores originais mantêm o comportamento atual. A proteção de quadros e da GPU continua ativada.';

  @override
  String get powerSaving_iosImmortalizerFrames =>
      'Pausar o agendamento de quadros da interface em segundo plano';

  @override
  String get powerSaving_iosImmortalizerHooks =>
      'Processamento reduzido dos hooks nativos';

  @override
  String get powerSaving_iosImmortalizerMode =>
      'Modo de manutenção em segundo plano';

  @override
  String get powerSaving_iosImmortalizerOriginal =>
      'Original (hooks e áudio silencioso)';

  @override
  String get powerSaving_iosImmortalizerWithoutAudio =>
      'Sem áudio (experimental)';

  @override
  String get powerSaving_iosImmortalizerWithoutAudioDescription =>
      'Sem áudio silencioso, o iOS pode suspender o aplicativo e a entrega de mensagens. As configurações de áudio são mantidas, mas não se aplicam neste modo.';

  @override
  String get powerSaving_iosImmortalizerSampleRate =>
      'Taxa de amostragem do arquivo de silêncio';

  @override
  String get powerSaving_iosImmortalizerEightKhz => 'Original: 8 kHz';

  @override
  String get powerSaving_iosImmortalizerOutputRate =>
      'De acordo com a saída de áudio real';

  @override
  String get powerSaving_iosImmortalizerBuffer =>
      'Buffer de E/S de áudio preferido';

  @override
  String get powerSaving_iosImmortalizerBufferDescription =>
      'Uma solicitação ao iOS, não uma duração de hardware garantida. \"Sistema\" mantém a preferência original. Consulte o valor aceito no diagnóstico.';

  @override
  String get powerSaving_iosImmortalizerSystem =>
      'Sistema (preferência original)';

  @override
  String get powerSaving_iosImmortalizerLoop => 'Duração do ciclo de silêncio';

  @override
  String get powerSaving_iosImmortalizerLoopDescription =>
      'Originalmente 1 segundo. Um ciclo PCM mais longo ocupa mais memória; nenhuma economia de bateria foi comprovada.';

  @override
  String get companionCli_title => 'CompanionCLI';

  @override
  String companionCli_nodeTitle(String nodeName) {
    return 'CLI do nó: $nodeName';
  }

  @override
  String get companionCli_description => 'Console de serviço do nó conectado';

  @override
  String get companionCli_noNode => 'Nenhum nó selecionado';

  @override
  String get companionCli_localOnly =>
      'Os comandos são executados apenas no nó conectado no momento';

  @override
  String get companionCli_sharedHistory =>
      'Histórico comum com indicação do nó';

  @override
  String get companionCli_empty =>
      'O histórico do console está vazio. Experimente o comando ver.';

  @override
  String get companionCli_command => 'Comando';

  @override
  String get companionCli_send => 'Executar comando';

  @override
  String get companionCli_emptyReply => 'Foi recebida uma resposta vazia';

  @override
  String get companionCli_unavailable =>
      'Para enviar, é necessário um companion conectado com versão de protocolo 14 ou mais recente (MeshCore 1.18+). O histórico continua disponível.';

  @override
  String get companionCli_busy => 'Aguarde o término do comando atual.';

  @override
  String get companionCli_invalidCommand =>
      'Digite um único comando sem quebras de linha nem bytes nulos, com pelo menos dois bytes UTF-8.';

  @override
  String get companionCli_tooLong =>
      'O comando excede o limite: no máximo 172 bytes UTF-8; os parâmetros de set radio, no máximo 131 bytes.';

  @override
  String get companionCli_tagExhausted =>
      'Os identificadores das solicitações CLI se esgotaram. Reinicie o aplicativo para começar uma nova sessão segura.';

  @override
  String get companionCli_timeout =>
      'A resposta não chegou a tempo. O comando pode ter sido executado; ele não será repetido automaticamente. A conexão está sendo renovada.';

  @override
  String get companionCli_protocolError =>
      'O nó ou o proxy recusou a solicitação.';

  @override
  String get companionCli_disconnected =>
      'A conexão ou o nó mudou. O comando não será retomado automaticamente.';

  @override
  String get companionCli_historyError =>
      'Não foi possível ler ou salvar o histórico do console.';

  @override
  String get companionCli_sendFailed =>
      'Não foi possível confirmar o envio. O comando não será repetido automaticamente.';

  @override
  String get cliHistory_temporary =>
      'Neste navegador, o histórico da CLI é mantido apenas até a página ser recarregada. Ele não é salvo nas configurações.';

  @override
  String get cliHistory_clearCurrentNodeConfirm =>
      'Limpar o histórico deste console para o nó atual? O histórico dos outros nós será mantido. Um comando em execução não será cancelado.';
}
