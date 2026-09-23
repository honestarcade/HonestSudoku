// How an older document becomes the current one. Keyed by document, then by
// the version a migration upgrades FROM; each transforms `data` one version
// up. Version 1 is the first, so there is nothing to migrate yet — the table
// exists so the first change of format is a migration, not a data loss.

/// Upgrades one version's `data` to the next.
typedef Migration = Map<String, Object?> Function(Map<String, Object?> data);

/// Every migration, per document file name and starting version.
const Map<String, Map<int, Migration>> kMigrations = {};
