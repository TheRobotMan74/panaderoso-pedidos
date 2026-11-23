// Dónde se guarda qué tarjetas están plegadas: un archivito en el celular.
// En la versión web no se guarda (solo dura mientras está abierta).
export 'fold_store_stub.dart' if (dart.library.io) 'fold_store_io.dart';
