/// Versión web: no hay archivos; lo plegado dura mientras la página siga abierta.
class FoldStore {
  FoldStore._();
  static Future<String?> read({String name = ''}) async => null;
  static Future<void> write(String data, {String name = ''}) async {}
}
