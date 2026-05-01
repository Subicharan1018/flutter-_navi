class AppConstants {
  AppConstants._();

  /// Maximum number of previously-played songs retained
  /// in the in-memory history list. Raise if users need
  /// deeper "go back" navigation; lower to reduce memory.
  static const int playerHistoryMaxLength = 50;
}
