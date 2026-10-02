// Driver for running integration tests on Web:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_boot_test.dart \
//     -d web-server --browser-name=chrome --profile
// Requires a chromedriver matching the installed Chrome, listening on 4444.
// Debug mode does not start on Web; see docs/testing.md.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
