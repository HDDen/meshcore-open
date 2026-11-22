import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/utils/contact_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('reload publishes persisted sorting and keeps transient search drafts', () async {
    final view = UiViewStateService();
    addTearDown(view.dispose);
    await view.initialize();
    view.setContactsSearchText('Alice');
    view.setChannelsSearchText('Public');
    var notifications = 0;
    view.addListener(() {
      notifications++;
      expect(view.contactsSortOption, ContactSortOption.name);
      expect(view.channelsSortOption, ChannelSortOption.name);
    });
    await PrefsManager.instance.setString('ui_contacts_sort_option', 'name');
    await PrefsManager.instance.setString('ui_channels_sort_option', 'name');

    await view.reload();

    expect(notifications, 1);
    expect(view.contactsSearchText, 'Alice');
    expect(view.channelsSearchText, 'Public');
  });

  test('reload accepts the legacy channel sort preference', () async {
    final view = UiViewStateService();
    addTearDown(view.dispose);
    await view.initialize();
    await PrefsManager.instance.setInt('ui_channels_sort_index', 3);
    await view.reload();
    expect(view.channelsSortOption, ChannelSortOption.unread);
  });
}
