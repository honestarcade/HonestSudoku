# Store fixtures, format version 1

These three files are what version 1 of the app writes: a 9×9 Medium game
on the hand-built `basePattern` board from `test/game/fixtures.dart` (its
`seed` field says 1, but no generator made it; five strikes, announced at the
end) with four undo steps and one redo step, the design's sample Easy
statistics, and a populated settings file. `test/store/store_fixture_test.dart`
reads them through the store and asserts what they hold; which values it
checks is in that file.

**Never regenerate them.** They stand for files already on players' phones.
When the format changes incompatibly — a key removed or renamed, or a value
whose meaning changes — bump the document's version in
`lib/store/app_store.dart`, add a migration in `lib/store/migrations.dart`,
and leave these files alone: the test then proves the migration reads them.
A new optional key whose absence decodes to the old behaviour needs no bump,
because older builds ignore it; the test must then assert what these files,
which lack it, decode to (`quiet`, #292, owner decision 2026-09-29).
