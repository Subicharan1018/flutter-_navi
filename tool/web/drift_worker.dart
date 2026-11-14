// Source of web/drift_worker.js (the drift database worker for the browser).
// Rebuild after a drift upgrade:
//   dart compile js -O4 tool/web/drift_worker.dart -o web/drift_worker.js
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
