// The moments of play that make a sound (#49) or a tick (#55).

/// A moment the player hears or feels.
enum FeedbackEvent {
  /// A number landed.
  place('place'),

  /// A counted mistake, announced at once.
  mistake('mistake'),

  /// The puzzle solved.
  solve('solve'),

  /// The last strike used.
  lastStrike('lose');

  const FeedbackEvent(this.clip);

  /// The clip's canonical name: `assets/audio/<clip>.wav`, and the name the
  /// channel carries.
  final String clip;
}
