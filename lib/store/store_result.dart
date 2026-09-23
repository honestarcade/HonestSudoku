// What reading a document found.

/// The outcome of reading one document.
sealed class StoreResult<T> {
  const StoreResult();

  /// The document was read.
  const factory StoreResult.present(T value) = Present<T>;

  /// There is no such document yet.
  const factory StoreResult.absent() = Absent<T>;

  /// The document could not be read; it was set aside.
  const factory StoreResult.corrupt(String reason) = Corrupt<T>;

  /// A later version of the app wrote it; it is left alone.
  const factory StoreResult.newer(int version) = Newer<T>;

  /// The value, or null for every case but [Present]. Callers restoring
  /// state treat corrupt and newer like absent.
  T? get valueOrNull => switch (this) {
    Present<T>(:final value) => value,
    _ => null,
  };
}

/// The document was read.
final class Present<T> extends StoreResult<T> {
  /// Creates the result.
  const Present(this.value);

  /// The value.
  final T value;
}

/// There is no such document.
final class Absent<T> extends StoreResult<T> {
  /// Creates the result.
  const Absent();
}

/// The document could not be read.
final class Corrupt<T> extends StoreResult<T> {
  /// Creates the result.
  const Corrupt(this.reason);

  /// Why.
  final String reason;
}

/// A later version wrote the document.
final class Newer<T> extends StoreResult<T> {
  /// Creates the result.
  const Newer(this.version);

  /// The version found.
  final int version;
}
