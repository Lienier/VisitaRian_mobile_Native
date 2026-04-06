import 'package:flutter/material.dart';
import 'package:visitarian_flutter/core/services/services.dart';
import 'package:visitarian_flutter/core/theme/theme.dart';
import 'package:visitarian_flutter/screens/widgets/tour_selection_styles.dart';

class TourProfileContent extends StatelessWidget {
  final String username;
  final String email;
  final String photoUrl;
  final VoidCallback onEditProfile;
  final VoidCallback onLogout;

  const TourProfileContent({
    super.key,
    required this.username,
    required this.email,
    required this.photoUrl,
    required this.onEditProfile,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        final textColor = Theme.of(context).colorScheme.onSurface;
        final secondaryTextColor = Theme.of(
          context,
        ).colorScheme.onSurfaceVariant;
        final screenSize = MediaQuery.sizeOf(context);
        final isLandscapePhone =
            screenSize.width >= 640 && screenSize.height < 560;
        final avatarRadius = isLandscapePhone ? 38.0 : 50.0;
        final titleSize = isLandscapePhone ? 20.0 : 24.0;
        final emailSize = isLandscapePhone ? 14.0 : 16.0;
        final verticalSpacing = isLandscapePhone ? 10.0 : 16.0;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isLandscapePhone ? 12 : 20,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: avatarRadius,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: photoUrl.isNotEmpty
                    ? NetworkImage(photoUrl) as ImageProvider
                    : null,
                child: photoUrl.isEmpty
                    ? Icon(
                        Icons.person,
                        size: isLandscapePhone ? 40 : 50,
                        color: Colors.grey,
                      )
                    : null,
              ),
              SizedBox(height: verticalSpacing),
              Text(
                username,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                email,
                style: TextStyle(
                  fontSize: emailSize,
                  color: secondaryTextColor,
                ),
              ),
              SizedBox(height: verticalSpacing),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: isLandscapePhone ? 4 : 6,
                ),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.dark_mode_outlined),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Dark Mode',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Switch(
                      value: AppThemeController.instance.isDarkMode,
                      onChanged: (value) =>
                          AppThemeController.instance.setDarkMode(value),
                    ),
                  ],
                ),
              ),
              SizedBox(height: verticalSpacing),
              ElevatedButton(
                onPressed: onEditProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tsPrimaryGreen,
                  padding: EdgeInsets.symmetric(
                    horizontal: isLandscapePhone ? 24 : 32,
                    vertical: isLandscapePhone ? 10 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Edit Profile',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              SizedBox(height: verticalSpacing),
              FutureBuilder<AppDistributionConfig>(
                future: AppDistributionService.instance.fetchConfig(),
                builder: (context, snapshot) {
                  final config = snapshot.data;
                  if (config == null || config.androidApkUrl.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Android app download',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Install the latest APK if you want the mobile app or full VR mode.',
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  AppDistributionService.instance.openAndroidApk(
                                    config,
                                  );
                                },
                                icon: const Icon(Icons.download),
                                label: const Text('Download Android APK'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: verticalSpacing),
                    ],
                  );
                },
              ),
              OutlinedButton(
                onPressed: onLogout,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: EdgeInsets.symmetric(
                    horizontal: isLandscapePhone ? 24 : 32,
                    vertical: isLandscapePhone ? 10 : 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
