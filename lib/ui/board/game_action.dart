// What the controller last did, set before every notification so a listener
// can tell a placement from a tick without diffing everything (#49).

/// The verb behind a [GameController] notification.
enum GameAction {
  /// A value placed, cleared by placing it again, or a pencil mark toggled.
  place,

  /// A cell erased.
  erase,

  /// Undo.
  undo,

  /// Redo.
  redo,

  /// Note mode switched.
  noteToggle,

  /// A cell selected or deselected.
  select,

  /// Check.
  check,

  /// A hint.
  hint,

  /// Paused.
  pause,

  /// Resumed.
  resume,

  /// A second of play.
  tick,

  /// The puzzle restarted.
  restart,

  /// A new puzzle of the same kind requested.
  newDeal,

  /// A new puzzle requested from setup.
  startNew,

  /// Settings changed.
  settings,

  /// Settings, statistics and a saved game read at launch.
  load,

  /// Generation progressed, finished, failed or was cancelled.
  generation,
}
