import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:visitarian_flutter/core/services/services.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _username = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _auth = AuthService();

  bool _saving = false;
  File? _profileImage;
  String? _photoUrl;
  bool _showPasswordFields = false;
  bool _canChangePassword = true;
  String? _passwordHint;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();

      if (mounted) {
        final providerId = user.providerData.isNotEmpty
            ? user.providerData.first.providerId
            : 'password';
        setState(() {
          _username.text = (data?['username'] ?? '') as String;
          _photoUrl = (data?['photoUrl'] ?? '') as String?;
          if (_photoUrl?.isEmpty ?? true) _photoUrl = null;
          _canChangePassword = providerId == 'password';
          _passwordHint = _canChangePassword
              ? null
              : 'Password change is only available for email/password accounts.';
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      _showMessage('Failed to pick image: $e');
    }
  }

  Future<String?> _uploadProfileImage() async {
    if (_profileImage == null) return _photoUrl;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final fileName =
          'profiles/${user.uid}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child(fileName);

      await ref.putFile(_profileImage!);
      final downloadUrl = await ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      _showMessage('Failed to upload image: $e');
      return null;
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = _username.text.trim();
    if (name.isEmpty) {
      _showMessage('Please enter a username.');
      return;
    }

    final shouldSave = await _confirmAction(
      title: 'Confirm Changes',
      message: 'Save profile changes?',
      confirmText: 'Save',
    );
    if (!shouldSave) return;

    setState(() => _saving = true);

    try {
      // Upload profile image if selected
      String? photoUrl = _photoUrl;
      if (_profileImage != null) {
        photoUrl = await _uploadProfileImage();
      }

      // Save to Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'username': name,
        'email': user.email ?? '',
        'photoUrl': photoUrl ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showMessage('Failed to save profile: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_canChangePassword) {
      _showMessage(
        _passwordHint ??
            'Password change is only available for email/password accounts.',
      );
      return;
    }

    final currentPass = _currentPassword.text.trim();
    final newPass = _newPassword.text.trim();

    if (currentPass.isEmpty || newPass.isEmpty) {
      _showMessage('Please fill in all password fields.');
      return;
    }

    if (newPass.length < 6) {
      _showMessage('New password must be at least 6 characters.');
      return;
    }

    final shouldChangePassword = await _confirmAction(
      title: 'Confirm Password Change',
      message: 'Are you sure you want to update your password?',
      confirmText: 'Update',
    );
    if (!shouldChangePassword) return;

    setState(() => _saving = true);

    try {
      await _auth.changePassword(
        currentPassword: currentPass,
        newPassword: newPass,
      );

      if (!mounted) return;
      _showMessage('Password changed successfully!');
      setState(() {
        _currentPassword.clear();
        _newPassword.clear();
        _showPasswordFields = false;
      });
    } on FirebaseAuthException catch (e) {
      _showMessage('Error: ${e.message}');
    } catch (e) {
      _showMessage('Failed to change password: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  void dispose() {
    _username.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pillGreen = Color(0xFF1B5A45);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = scheme.surface;
    final fieldFill = isDark ? scheme.surfaceContainerHigh : Colors.white;
    final fieldBorder = isDark
        ? scheme.outline.withValues(alpha: 0.55)
        : scheme.outline.withValues(alpha: 0.35);
    final mutedText = scheme.onSurfaceVariant;
    final softContainer = isDark
        ? scheme.surfaceContainerHighest
        : Colors.white.withValues(alpha: 0.85);
    final cancelBg = isDark
        ? scheme.surfaceContainerHigh
        : Colors.grey.shade400;
    final cancelText = isDark ? scheme.onSurface : Colors.black;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: const Text('Edit Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const SizedBox(height: 18),

            // Profile Picture
            Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.white,
                  backgroundImage: _profileImage != null
                      ? FileImage(_profileImage!) as ImageProvider
                      : (_photoUrl != null && _photoUrl!.isNotEmpty
                            ? NetworkImage(_photoUrl!) as ImageProvider
                            : null),
                  child: _profileImage == null && (_photoUrl?.isEmpty ?? true)
                      ? const Icon(
                          Icons.person,
                          size: 52,
                          color: Colors.black54,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      decoration: BoxDecoration(
                        color: pillGreen,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Text(
              _profileImage != null
                  ? 'Picture selected'
                  : 'Tap camera to change picture',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText),
            ),

            const SizedBox(height: 24),

            // Username
            TextField(
              controller: _username,
              decoration: InputDecoration(
                labelText: 'Username',
                filled: true,
                fillColor: fieldFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: pillGreen, width: 1.4),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Save Profile Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: pillGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Save Profile',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),

            const SizedBox(height: 32),
            Divider(color: scheme.outline.withValues(alpha: 0.4)),
            const SizedBox(height: 16),

            // Change Password Section
            Text(
              'Change Password',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),

            const SizedBox(height: 12),

            if (!_canChangePassword)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: softContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _passwordHint ??
                      'Password change is only available for email/password accounts.',
                  style: TextStyle(color: mutedText),
                ),
              )
            else if (!_showPasswordFields)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => setState(() => _showPasswordFields = true),
                  child: const Text(
                    'Change Password',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else ...[
              TextField(
                controller: _currentPassword,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  filled: true,
                  fillColor: fieldFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: fieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: fieldBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: pillGreen, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPassword,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  filled: true,
                  fillColor: fieldFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: fieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: fieldBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: pillGreen, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pillGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _saving ? null : _changePassword,
                      child: _saving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Update Password',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cancelBg,
                        foregroundColor: cancelText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => setState(() {
                        _showPasswordFields = false;
                        _currentPassword.clear();
                        _newPassword.clear();
                      }),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
