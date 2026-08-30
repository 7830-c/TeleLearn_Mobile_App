class UserSession {
  final String phone;
  final String? displayName;
  final String? avatarUrl;
  final bool isLoggedIn;

  UserSession({
    required this.phone,
    this.displayName,
    this.avatarUrl,
    required this.isLoggedIn,
  });

  factory UserSession.guest() {
    return UserSession(
      phone: '+1 (555) 019-2834',
      displayName: 'Alex Carter',
      isLoggedIn: true,
    );
  }
}
