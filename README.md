# PGME - Post Graduate Medical Education

A complete, production-ready Flutter application for medical education with clean architecture, modern UI/UX, and comprehensive features.

## 🎯 Features

- **Splash Screen** - Animated splash screen with PGME branding
- **Onboarding Flow** - 4 beautiful onboarding screens
- **Authentication** - Phone-based OTP authentication
- **User Profile** - Complete data collection and profile management
- **Dashboard** - Interactive home screen with live classes and courses
- **Courses** - Browse and enroll in medical courses
- **Revision Series** - Access theory packages and study materials
- **Notes** - Manage and access PDF/EPUB study notes
- **Video Player** - Watch recorded lectures
- **Settings** - Comprehensive settings and preferences
- **Purchase Flow** - In-app course purchase with congratulations screen

## 🎨 Design System

### Color Palette
- Primary Blue: `#0000C8` (Strong Blue)
- Secondary Blue: `#00BEFA` (Bright Sky Blue)
- Background: `#FFFFFF`
- Card Background: `#F8F9FE`
- Text Primary: `#000000`
- Text Secondary: `#6B7280`

### Typography
- Font Family: Inter
- Display: 32px, Bold
- Headings: 18-24px, SemiBold
- Body: 14-16px, Regular
- Caption: 12-13px, Regular

## 📁 Project Structure

```
lib/
├── main.dart                          # App entry point
├── core/
│   ├── theme/
│   │   └── app_theme.dart            # Theme configuration
│   ├── routes/
│   │   └── app_router.dart           # Navigation setup
│   └── widgets/
│       ├── primary_button.dart       # Reusable button
│       ├── custom_text_field.dart    # Input field
│       ├── otp_input.dart            # OTP input widget
│       ├── page_indicator.dart       # Page dots
│       └── course_card.dart          # Course card widget
├── features/
│   ├── splash/
│   │   └── screens/
│   │       └── splash_screen.dart
│   ├── onboarding/
│   │   ├── screens/
│   │   │   └── onboarding_screen.dart
│   │   └── providers/
│   │       └── onboarding_provider.dart
│   ├── auth/
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── otp_verification_screen.dart
│   │   │   └── data_collection_screen.dart
│   │   └── providers/
│   │       └── auth_provider.dart
│   ├── home/
│   │   └── screens/
│   │       ├── main_screen.dart
│   │       └── dashboard_screen.dart
│   ├── courses/
│   │   └── screens/
│   │       ├── revision_series_screen.dart
│   │       ├── course_detail_screen.dart
│   │       └── video_player_screen.dart
│   ├── notes/
│   │   └── screens/
│   │       └── notes_list_screen.dart
│   ├── settings/
│   │   └── screens/
│   │       ├── profile_screen.dart
│   │       └── settings_screen.dart
│   └── purchase/
│       └── screens/
│           ├── purchase_screen.dart
│           └── congratulations_screen.dart
```

## 🖼️ Assets Structure & Upload Guide

### Where to Upload Your Images

Create the following folder structure and place your images:

```
assets/
├── images/
│   ├── splash_pattern.png           # Checkered pattern for splash
│   ├── flag_india.png                # Indian flag for phone input
│   └── app_icon.png                  # App launcher icon
├── icons/
│   └── app_icon.png                  # App icon (1024x1024)
└── illustrations/
    ├── onboarding_1.png              # Welcome illustration
    ├── onboarding_2.png              # Learn Subject illustration
    ├── onboarding_3.png              # Watch Lectures illustration
    └── onboarding_4.png              # Live Webinars illustration
```

### Asset Upload Instructions

#### 1. Splash Screen Pattern
**Path:** `assets/images/splash_pattern.png`
- **Size:** 1080x1920px (or 2x/3x)
- **Description:** Blue and white checkered pattern background
- **Design:** Geometric blocks pattern similar to PGME logo

#### 2. Onboarding Illustrations
**Path:** `assets/illustrations/`
Upload these 4 images from your design:

**onboarding_1.png** - Welcome to PGME
- Person with medical education interface
- Blue color scheme
- Size: 600x600px minimum

**onboarding_2.png** - Learn Subject by Subject
- Books/courses illustration
- Educational theme
- Size: 600x600px minimum

**onboarding_3.png** - Watch Recorded Lectures
- Video/laptop illustration with play button
- Size: 600x600px minimum

**onboarding_4.png** - Live Webinars
- Broadcast tower/streaming illustration
- Size: 600x600px minimum

#### 3. App Icon
**Path:** `assets/icons/app_icon.png`
- **Size:** 1024x1024px
- **Description:** PGME logo with blue blocks
- **Format:** PNG with transparent background

#### 4. India Flag (Optional)
**Path:** `assets/images/flag_india.png`
- **Size:** 48x48px
- **Description:** Indian flag icon for phone number input
- **Note:** App uses emoji fallback if not provided

### Fonts (Optional - Already Configured)

If you want to use custom Inter font:
```
assets/
└── fonts/
    ├── Inter-Regular.ttf
    ├── Inter-Medium.ttf
    ├── Inter-SemiBold.ttf
    └── Inter-Bold.ttf
```

Download Inter font from: https://fonts.google.com/specimen/Inter

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)
- Android Studio / VS Code
- iOS: Xcode (for iOS development)

### Installation

1. **Clone or extract the project**
   ```bash
   cd "flutter apk"
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Add your images to assets folders** (see Assets Structure above)

4. **Run the app**
   ```bash
   flutter run
   ```

### Building for Production

**Android APK**
```bash
flutter build apk --release
```

Android ships `lib/main.dart` (`core/` + `features/`). `lib/main_android.dart`
is a thin alias for it, so `-t lib/main_android.dart` builds the identical app —
the two used to boot different trees, and picking the wrong one silently
shipped a build missing Workshops and the All Packages card. `lib/main_ios.dart`
is genuinely separate: iOS runs reader-mode with no purchase or payment flow.

**Android App Bundle**
```bash
flutter build appbundle --release
```

**iOS**
```bash
flutter build ios --release
```

## 🔧 Configuration

### Update App Name
Edit `pubspec.yaml`:
```yaml
name: pgme
description: Post Graduate Medical Education
```

### Update Package Name (Android)
Edit `android/app/build.gradle`:
```gradle
applicationId "com.pgme.app"
```

### Update Bundle Identifier (iOS)
Edit in Xcode: `ios/Runner.xcodeproj`

## 📱 Screen Flow

```
Splash Screen
    ↓
Onboarding (4 screens)
    ↓
Login (Phone Number)
    ↓
OTP Verification
    ↓
Data Collection
    ↓
Main App (Dashboard)
    ├── Home/Dashboard
    ├── Revision Series
    ├── Notes
    └── Profile
        └── Settings
```

## 🎯 Key Features Explained

### 1. Clean Architecture
- Separation of concerns
- Feature-based folder structure
- Provider pattern for state management

### 2. Reusable Components
- `PrimaryButton` - Consistent button styling
- `CustomTextField` - Standardized input fields
- `OTPInput` - Auto-focus OTP entry
- `CourseCard` - Flexible course display
- `PageIndicator` - Onboarding progress dots

### 3. Smooth Navigation
- GoRouter for type-safe routing
- Custom page transitions
- Deep linking support

### 4. Responsive Design
- Works on all mobile screen sizes
- Proper spacing and typography
- Material 3 design system

## 🔐 Mock Authentication

The app uses mock authentication for demonstration:
- **Any 10-digit phone number** will work
- **OTP:** Any 4-digit code (mock accepts all)
- **Data:** All fields required but no validation to external services

To connect real API:
1. Update `lib/features/auth/providers/auth_provider.dart`
2. Replace mock delays with actual HTTP calls
3. Handle error responses

## 🎨 Customization

### Change Primary Color
Edit `lib/core/theme/app_theme.dart`:
```dart
static const Color primaryBlue = Color(0xFF0000C8);
```

### Modify Text Styles
All text styles are centralized in `app_theme.dart`

### Update Illustrations
Simply replace the placeholder images in `assets/illustrations/`

## 📦 Dependencies

- `go_router` - Navigation and routing
- `provider` - State management
- `shared_preferences` - Local storage
- `intl` - Internationalization
- `flutter_svg` - SVG rendering

## 🐛 Troubleshooting

### Assets Not Loading
1. Run `flutter clean`
2. Run `flutter pub get`
3. Restart the app

### Build Errors
1. Check Flutter version: `flutter --version`
2. Upgrade Flutter: `flutter upgrade`
3. Clear cache: `flutter clean`

### Navigation Issues
1. Check route names in `app_router.dart`
2. Ensure GoRouter is properly initialized

## 📝 TODO / Future Enhancements

- [ ] Integrate real API endpoints
- [ ] Add video player implementation
- [ ] Implement PDF viewer for notes
- [ ] Add payment gateway integration
- [ ] Implement push notifications
- [ ] Add offline mode support
- [ ] Implement search functionality
- [ ] Add analytics tracking

## 🤝 Contributing

This is a production-ready template. To customize:
1. Update branding and colors
2. Replace placeholder images
3. Connect to your backend API
4. Add your business logic

## 📄 License

This project is created for PGME - Post Graduate Medical Education.

## 📧 Support

For questions or issues, please refer to the code comments or Flutter documentation.

---

**Made with ❤️ using Flutter**

### Quick Start Checklist

- [ ] Run `flutter pub get`
- [ ] Add images to `assets/images/`
- [ ] Add illustrations to `assets/illustrations/`
- [ ] Run `flutter run`
- [ ] Test all screens and navigation
- [ ] Build release APK
- [ ] Deploy to Play Store / App Store

### Important Notes

1. **Image Placeholders**: The app has fallback UI for missing images
2. **Mock Data**: All data is currently mock - connect to real API
3. **Authentication**: OTP verification is simulated
4. **Payments**: Purchase flow is UI only - integrate payment gateway
5. **Videos**: Video player shows placeholder - add video_player package

Enjoy building with PGME! 🚀
