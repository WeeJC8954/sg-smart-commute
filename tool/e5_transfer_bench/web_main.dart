// Chrome (dart2js) runner of the E5 benchmark. Compiled and run by
// run_chrome.sh (README.md): index.html loads data.js (the snapshot as two JS
// strings) before this script, which writes the report into the page.
import 'dart:js_interop';

import 'bench.dart';

@JS('e5StopsJson')
external String get _stopsJson;

@JS('e5ServicesJson')
external String get _servicesJson;

@JS('e5UserAgent')
external String get _userAgent;

@JS('e5SetResult')
external void _setResult(String text);

void main() {
  _setResult(
    runBenchmark(_stopsJson, _servicesJson, platform: 'dart2js, $_userAgent'),
  );
}
