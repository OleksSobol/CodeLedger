/// Defines the input mode for manual time entry:
/// [duration] for logging total duration without specific time-of-day,
/// or [exactTime] for clock-in / clock-out timestamp ranges.
enum ManualEntryMode {
  duration,
  exactTime;

  String get label => switch (this) {
    duration => 'Duration',
    exactTime => 'Exact Time',
  };
}
