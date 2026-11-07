# MacFace AI

MacFace AI is a macOS app prototype for local face enrollment and recognition. It uses Apple's Vision framework to analyze camera frames and compare face feature prints. Touch ID and an app-specific password are also available as authentication options inside the app.

> **Prototype notice:** MacFace AI does not unlock or replace the macOS login window. Face matching scores are not calibrated for secure account authentication, and camera-based liveness checks cannot guarantee protection against sophisticated spoofing.

## Features

- Enroll a face from multiple camera samples and recognize it locally.
- Use a liveness prompt during enrollment and recognition.
- Optionally verify with Touch ID or configure an app-specific password.
- Adjust the face-match similarity threshold and app appearance.
- Keep encrypted face templates on the Mac, with the encryption key stored in Keychain.

Face analysis uses Apple's Vision image feature prints; this project does not include an ArcFace Core ML model. Camera analysis, feature extraction, and template matching run on-device.

## Requirements

- macOS 14 or later
- Xcode with a Swift toolchain that supports the project
- A Mac camera for face enrollment and recognition
- Touch ID hardware for Touch ID verification (optional)

## Build and run

1. Open `MacFaceAI.xcodeproj` in Xcode.
2. Select the **MacFaceAI** scheme and a Mac destination.
3. Build and run the app.
4. Allow camera access when prompted to use face enrollment and recognition.

You can also build from Terminal:

```sh
xcodebuild -project MacFaceAI.xcodeproj -scheme MacFaceAI -configuration Debug build
```

## Privacy and storage

Face processing and matching are performed locally. Encrypted face templates are stored in the app's Application Support directory, and the encryption key is stored in Keychain. The app requests camera access for live face analysis. Touch ID uses macOS LocalAuthentication and authorizes actions inside this app only.
