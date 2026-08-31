class AppConstants {
  static const String appName = 'TeleLearn';
  static const String appTagline = 'Master Any Skill on Your Own Terms';
  static const String appDescription =
      'Transform any Telegram Channel or Forum into a high-performance offline & streaming video learning workspace.';

  // Storage Keys
  static const String keyThemeMode = 'telelearn_theme_mode';
  static const String keyUserPhone = 'telelearn_user_phone';
  static const String keyIsLoggedIn = 'telelearn_is_logged_in';
  static const String keyActiveChannelId = 'telelearn_active_channel_id';

  // Learner titles for greeting
  static const List<String> learnerTitles = [
    'Learner',
    'Scholar',
    'Future Achiever',
    'Knowledge Seeker',
    'Champion',
    'Engineer',
    'Builder',
  ];

  // Default streaming host port
  static const int localProxyPort = 8765;

  // Telegram MTProto Credentials
  static const int telegramApiId = 33952264;
  static const String telegramApiHash = '6a51d05428a6b7906e17f61d20a533df';
  static const String telegramServerBaseUrl = 'https://api.telegram.org';
  static const String telegramGatewayToken = ''; // Optional Telegram Gateway Bearer Token (gateway.telegram.org)
}
