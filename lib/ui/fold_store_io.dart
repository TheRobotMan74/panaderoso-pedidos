import 'dart:io';

/// Android: un archivito en la carpeta privada de la app (la de temporales,
/// que Flutter pone dentro de la app). Si Android la limpia, solo se pierde
/// qué estaba plegado.
class FoldStore {
  FoldStore._();

  static File _file(String name) => File('${Directory.systemTemp.path}/$name.json');

  /// [name]: qué archivito (por defecto el de las tarjetas plegadas).
  static Future<String?> read({String name = 'panaderoso_plegados'}) async {
    final f = _file(name);
    return await f.exists() ? f.readAsString() : null;
  }

  static Future<void> write(String data, {String name = 'panaderoso_plegados'}) async {
    final f = _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }
}
