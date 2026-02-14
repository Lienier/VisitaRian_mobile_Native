import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = AuthService();

  final _email = TextEditingController();
  final _confirmEmail = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();

  bool _isSignup = false;
  bool _loading = false;
  bool _hidePass = true;
  String? _error;
  Timer? _errorTimer;

  @override
  void dispose() {
    _errorTimer?.cancel();
    _email.dispose();
    _confirmEmail.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  void _showTimedError(String message) {
    _errorTimer?.cancel();
    setState(() {
      _error = message;
      _password.clear();
    });
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _error = null);
    });
  }

  Future<void> _doEmailAuth() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isSignup) {
        if (_email.text.trim().toLowerCase() !=
            _confirmEmail.text.trim().toLowerCase()) {
          _showTimedError('Email and confirm email do not match.');
          return;
        }

        await _auth.signUpWithEmail(
          username: _username.text,
          email: _email.text,
          password: _password.text,
        );
      } else {
        await _auth.signInWithEmail(
          email: _email.text,
          password: _password.text,
        );
      }
    } catch (e) {
      _showTimedError(_mapAuthError(e, isSignup: _isSignup));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      _showTimedError(_mapAuthError(e, isSignup: false));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapAuthError(Object error, {required bool isSignup}) {
    if (error is FirebaseAuthException) {
      if (!isSignup &&
          (error.code == 'wrong-password' ||
              error.code == 'user-not-found' ||
              error.code == 'invalid-credential' ||
              error.code == 'invalid-email')) {
        return 'Wrong email or password';
      }
      if (error.code == 'email-already-in-use') {
        return error.message ?? 'Email already has an account.';
      }
      if (error.code == 'provider-mismatch') {
        return error.message ??
            'This email must use its original sign-in method.';
      }
      return error.message ?? 'Authentication failed.';
    }
    return 'Authentication failed.';
  }

  @override
  Widget build(BuildContext context) {
    const lightBg = Color.fromARGB(255, 248, 255, 251);
    const pillGreen = Color(0xFF1B5A45);
    const darkText = Color(0xFF1A1A1A);

    return Scaffold(
      backgroundColor: lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 30),

              // Logo and tagline
              Column(
                children: [
                  const Text(
                    'VisitaRian',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: darkText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Explore through your eyes',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Sign in heading
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _isSignup ? "Sign up" : "Sign in",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: darkText,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (_isSignup) ...[
                _buildTextField(
                  controller: _username,
                  label: "Username",
                  hint: "Enter your username",
                ),
                const SizedBox(height: 20),
              ],

              _buildTextField(
                controller: _email,
                label: "Email",
                hint: "Enter your email",
              ),

              if (_isSignup) ...[
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _confirmEmail,
                  label: "Confirm Email",
                  hint: "Re-enter your email",
                ),
              ],

              const SizedBox(height: 20),

              _buildTextField(
                controller: _password,
                label: "Password",
                hint: "Enter your password",
                obscure: _hidePass,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _hidePass = !_hidePass),
                  icon: Icon(
                    _hidePass ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Sign in button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pillGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 6,
                    shadowColor: Colors.black.withOpacity(1.0),
                  ),
                  onPressed: _loading ? null : _doEmailAuth,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          _isSignup ? "SIGN UP" : "SIGN IN",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Google sign in button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: darkText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                    elevation: 4,
                    shadowColor: Colors.black.withOpacity(1.0),
                  ),
                  onPressed: _loading ? null : _doGoogle,
                  icon: Image.asset(
                    'assets/images/google_logo.png',
                    height: 20,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.g_mobiledata, size: 20);
                    },
                  ),
                  label: const Text(
                    "Sign in with Google",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Forgot password and sign up links
              if (!_isSignup) ...[
                Center(
                  child: TextButton(
                    onPressed: _loading
                        ? null
                        : () async {
                            if (_email.text.trim().isEmpty) {
                              _showTimedError(
                                "Enter your email first to reset password.",
                              );
                              return;
                            }
                            try {
                              await _auth.sendPasswordReset(_email.text);
                              if (mounted) {
                                setState(
                                  () => _error = "Password reset email sent.",
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                _showTimedError(
                                  _mapAuthError(e, isSignup: false),
                                );
                              }
                            }
                          },
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(
                        color: pillGreen,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Switch between sign in/up
              Center(
                child: TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                          _isSignup = !_isSignup;
                          _error = null;
                          _confirmEmail.clear();
                        }),
                  child: Text.rich(
                    TextSpan(
                      text: _isSignup
                          ? "Already have an account? "
                          : "No Account? ",
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                      children: [
                        TextSpan(
                          text: _isSignup ? "Sign in" : "Sign Up",
                          style: const TextStyle(
                            color: pillGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.5),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ],
    );
  }
}
