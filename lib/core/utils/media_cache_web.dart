class File {
  File(this.path);
  final String path;
  bool existsSync() => false;
  Future<File> writeAsBytes(List<int> bytes) async => this;
  void deleteSync() {}
}
