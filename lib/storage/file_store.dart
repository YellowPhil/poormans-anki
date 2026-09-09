/// Keys are relative POSIX-style paths (`decks/abc.json`). Contents are UTF-8
/// text. Cloud backends (Drive, iCloud) implement exactly these operations.
abstract interface class FileStore {
  /// Direct children of [dir] as `dir/name`; empty when [dir] is absent.
  Future<List<String>> list(String dir);

  Future<String?> read(String path);

  /// Atomic replace; creates missing parent directories.
  Future<void> write(String path, String contents);

  /// Appends [line] plus a trailing newline.
  Future<void> append(String path, String line);

  Future<void> delete(String path);
}
