import 'package:flutter/widgets.dart';
import 'package:mediahro/app/root.dart';
import 'package:mediahro/features/settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loaded before the first frame so it already has the user's theme,
  // language and last mode (CORE-001, CORE-007).
  final settings = await SettingsStore.open();
  runApp(mediahroRoot(settings));
}
