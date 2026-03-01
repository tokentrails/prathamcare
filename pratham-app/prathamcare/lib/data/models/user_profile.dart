class UserProfile {
  const UserProfile({
    required this.userId,
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
  });

  final String userId;
  final String email;
  final String name;
  final String phone;
  final String role;
}
