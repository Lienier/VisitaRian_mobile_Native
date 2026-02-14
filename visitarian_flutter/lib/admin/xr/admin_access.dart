const String kAdminEmail = 'reineilarayat70@gmail.com';

bool isAdminEmail(String? email) {
  if (email == null) return false;
  return email.trim().toLowerCase() == kAdminEmail;
}
