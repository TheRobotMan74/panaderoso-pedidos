import 'dart:io';

/// Android: un archivito en la carpeta privada de la app (la de temporales,
/// que Flutter pone dentro de la app). Si Android la limpia, solo se pierde
/// qué estaba plegado.
class FoldStore {
  FoldStore._();

  static File get _file => File('${Directory.systemTemp.path}/panaderoso_plegados.json');

  static Future<String?> read() async {
    final f = _file;
    return await f.exists() ? f.readAsString() : null;
  }

  static Future<void> write(String data) async {
    final f = _file;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }
}
