# TestFlight and App Store Release Guide

This guide describes the project’s release preparation. Apple’s UI, submission requirements, and tooling change; use the official links below for current requirements.

## Prerequisites

- Access to the app’s Apple Developer team and App Store Connect record.
- macOS with Xcode and Flutter configured; confirm the environment with `flutter doctor`.
- CocoaPods installed and available on PATH. Avoid copying a machine-specific Ruby/gems path.
- Signing certificates/profiles or automatic signing configured for the correct team.
- Bundle ID `com.monitormx.meshcoreopen`, matching `ios/Runner.xcodeproj/project.pbxproj`.
- A device running iOS **16.4 or newer**, the project’s current deployment target.

If an app record already exists, use it rather than registering a duplicate identifier or listing.

## Prepare a release

1. Start from the intended release commit and verify `pubspec.yaml` version/build number. Increment the build number for a new upload; use the intended release version rather than a sample value copied from this guide.
2. Run dependency installation and project checks:

   ```bash
   flutter pub get
   dart format --output=none --set-exit-if-changed .
   flutter analyze --fatal-infos --fatal-warnings
   flutter test
   ```

3. Review the changelog, store description, screenshots, support URL, and hosted privacy policy. Describe available features and their platform/firmware limits.
4. Test on physical hardware: BLE connect/reconnect, direct/channel messages, notifications/background behavior, and affected features such as contact QR import, regions, translation, and image reconstruction.
5. Confirm camera, Bluetooth, and photo-library usage descriptions match the app’s behavior. Test permissions and denial paths.

## Build and upload

From the repository root:

```bash
flutter build ipa --release
```

Locate the generated IPA under `build/ios/ipa/`; do not assume an exact filename. Upload it with Transporter or Xcode’s supported distribution flow. If signing fails, open `ios/Runner.xcworkspace` and check Runner → Signing & Capabilities, team access, bundle identifier, and provisioning.

Wait for App Store Connect processing and inspect any validation messages before assigning the build to testers. Processing/review times vary.

## TestFlight

Use the existing app’s TestFlight page to assign a processed build to an internal testing group. External distribution may require beta review. Provide concrete What to Test notes, feedback contact information, and instructions for the companion radio/firmware needed to exercise the app.

Follow [Apple’s TestFlight documentation](https://developer.apple.com/testflight/) for current tester limits, permissions, and review requirements.

## App Store submission

Update the app information, screenshots for required supported device classes, release notes, support URL, privacy-policy URL, and privacy disclosures. Use the current App Store Connect prompts for screenshot requirements rather than a fixed list of screen sizes in this guide.

Reviewers need a clear explanation of the external MeshCore hardware requirement and accessible instructions for evaluating relevant features. Do not promise firmware updates or unsupported platform features in the listing.

Assess export compliance using the app’s actual encryption, including app-provided cryptographic functions as well as HTTPS. Do not assume an exemption solely because standard algorithms are used. Follow [Apple’s encryption questionnaire and documentation workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation).

Select the processed build, complete the current review prompts, and submit through App Store Connect. If rejected, address the stated issue and update the build or metadata as appropriate.

## macOS distribution

```bash
flutter build macos --release
```

The app bundle is under `build/macos/Build/Products/Release/`. For public distribution, prepare signing and notarization using the applicable Apple distribution workflow; a zip alone does not establish that an app is signed or notarized.

## Troubleshooting

| Problem | Check |
|---|---|
| CocoaPods missing | Installation and PATH; `flutter doctor` |
| Signing/profile error | Team, certificates, profiles, and matching bundle ID |
| Build not visible | Processing status and validation messages in App Store Connect |
| Permissions or hardware failure | Physical-device logs, usage descriptions, radio firmware, and reproduction steps |
| Native model crash | Available memory, supported runtime, and complete model bundle |

## References and support

- [App Store Connect](https://appstoreconnect.apple.com)
- [Apple Developer support](https://developer.apple.com/contact/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Flutter iOS deployment](https://docs.flutter.dev/deployment/ios)
- [Project privacy policy](docs/PRIVACY_POLICY.md)
- [Project issues](https://github.com/zjs81/meshcore-open/issues)
