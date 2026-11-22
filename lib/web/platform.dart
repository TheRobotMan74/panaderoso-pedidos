// Cosas que solo existen en el navegador (Safari del iPhone, Chrome…).
// En Android se usa la versión "stub", que no hace nada.
export 'platform_stub.dart' if (dart.library.js_interop) 'platform_web.dart';
