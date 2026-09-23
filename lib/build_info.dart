// The app's version, as the build passes it: `--dart-define=HS_VERSION=
// <name>+<build>` (tools/gate.sh and the release workflow set it). A plugin
// could read it from the package, but none is needed for one string.

/// A version name and build number.
final class BuildInfo {
  /// Creates the info.
  const BuildInfo(this.name, this.build);

  /// Parses `<x.y.z[-pre]>+<n>`; anything else is `0.0.0`, build `0`.
  factory BuildInfo.parse(String raw) {
    final m = RegExp(r'^(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+(\d+)$')
        .firstMatch(raw.trim());
    if (m == null) return const BuildInfo('0.0.0', 0);
    return BuildInfo(m.group(1)!, int.parse(m.group(2)!));
  }

  /// This build's info, from `HS_VERSION`.
  static final BuildInfo current = BuildInfo.parse(
    const String.fromEnvironment('HS_VERSION'),
  );

  /// `1.0.0`.
  final String name;

  /// `12`.
  final int build;

  /// The settings screen's line: `v1.0.0 · BUILD 12`.
  String get versionLine => 'v$name · BUILD $build';

  /// About the App's line: `v1.0.0 · OFFLINE`.
  String get aboutLine => 'v$name · OFFLINE';

  @override
  bool operator ==(Object other) =>
      other is BuildInfo && other.name == name && other.build == build;

  @override
  int get hashCode => Object.hash(name, build);
}
