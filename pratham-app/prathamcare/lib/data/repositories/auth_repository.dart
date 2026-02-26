abstract class AuthRepository {
  Future<void> loginWithOtp(String phoneNumber, String otp);
  Future<void> logout();
}
