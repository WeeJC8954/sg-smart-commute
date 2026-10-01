// Driver for running integration tests on Web:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_boot_test.dart -d chrome
// Requires a chromedriver matching the installed Chrome, listening on 4444.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
