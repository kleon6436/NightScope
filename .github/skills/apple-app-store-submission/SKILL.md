---
name: apple-app-store-submission
description: 'Guidelines for the submission, review, and publication process for apps on the Apple App Store (iOS / macOS). Use when submitting apps to the Apple App Store, preparing App Store metadata and screenshots, responding to App Review rejections, configuring App Store Connect, managing TestFlight beta testing, handling privacy compliance and export regulations.'
argument-hint: 'The submission process item to review or apply (optional)'
---

# Apple App Store Submission Guidelines (iOS / macOS)

## Overview

This skill defines the conventions for the submission, review, and publication process for iOS / macOS apps on the Apple App Store.
It provides practical guidelines covering everything from App Store Connect configuration and metadata preparation to responding to App Review Guidelines and managing releases.

> **Scope vs. CI/CD**: For build automation, Fastlane, and Xcode Cloud pipeline setup, refer to the `cicd-deployment` skill. This skill focuses on submission preparation, review response, and publication management.

---

## 1. Pre-Submission Preparation

### 1.1 App Store Connect Account

| Item | Requirement |
|------|------|
| Apple Developer Program | $99/year (Individual / Organization) |
| Role | App Manager role or higher required |
| Team setup | D-U-N-S number required for organization accounts |
| Agreements | Paid Apps agreement, tax information, and banking details required (if offering paid apps / IAP) |

### 1.2 Bundle ID & App ID

- Use reverse-domain format for Bundle ID: `com.example.appname`
- Register an App ID in the Apple Developer Portal
- Use an Explicit App ID (Wildcard cannot be used for App Store submission)
- Once submitted to the App Store, a Bundle ID cannot be changed

### 1.3 Certificates & Provisioning Profiles

| Type | Purpose |
|------|------|
| Apple Distribution Certificate | Code signing for App Store / TestFlight |
| Provisioning Profile (App Store) | Profile for App Store distribution |

- Regularly check certificate expiration dates
- Recommended to use automatic signing (Xcode Automatically manage signing)
- Manual signing + Keychain management required in CI/CD environments (see `cicd-deployment` skill for details)

### 1.4 Capabilities & Entitlements

- Enable required Capabilities in both the Apple Developer Portal and Xcode
- Do not include unused Capabilities (can cause rejection during review)
- Key Capabilities:

| Capability | Notes |
|-----------|---------|
| Push Notifications | APNs certificate or Key configuration required |
| Sign in with Apple | Required when third-party login is present |
| App Groups | For data sharing between apps or widget integration |
| Associated Domains | For Universal Links and Handoff |
| HealthKit | Additional review criteria apply for health data access |
| BackgroundModes | Must be able to justify the use of each mode |

---

## 2. App Store Connect Configuration

### 2.1 App Basic Information

| Item | Guideline |
|------|------------|
| App name | Maximum 30 characters. Avoid trademark infringement and overly generic names |
| Subtitle | Maximum 30 characters. A concise description of the app |
| Primary category | Choose the category that best matches the app's main functionality |
| Secondary category | Optional. A supplementary category |
| Content rating | Answer the App Rating questions accurately |

### 2.2 Pricing & Availability

- Set a price tier. Required even for free apps
- Select countries/regions for distribution (defaults to all regions)
- Pre-Order can be set up to 180 days in advance
- Enabling Universal Purchase allows a single purchase to unlock the app on both iOS and macOS

### 2.3 In-App Purchases (IAP) & Subscriptions

| Type | Description |
|------|------|
| Consumable | Consumed on use (e.g., in-game currency) |
| Non-Consumable | Permanent unlock (e.g., unlocking additional features) |
| Auto-Renewable Subscription | Auto-renewing subscription |
| Non-Renewing Subscription | Non-auto-renewing subscription |

- Pre-register products in App Store Connect when using IAP
- For subscriptions, configure subscription groups appropriately
- Implementing Restore Purchases is required (Guideline 3.1.1)
- Recommended to use StoreKit 2

### 2.4 Additional Targets

| Target | Configuration Points |
|-----------|--------------|
| App Clip | Configure App Clip card metadata in App Store Connect |
| Widget | Submit as part of the main app. No separate submission required |
| iMessage Extension | Submit as part of the main app |
| watchOS App | Submit as a companion to the main app or as a standalone app |

---

## 3. Metadata & Asset Preparation

### 3.1 Description & Keywords

| Item | Requirement | Guideline |
|------|------|------------|
| Description | Max 4,000 characters | The first 1–3 lines are most important (shown before truncation). Place key features at the top |
| Keywords | Max 100 characters (comma-separated) | Do not include competitor names or irrelevant terms. Use singular forms only to save space |
| What's New | Max 4,000 characters | Briefly describe the major changes in each version |
| Promotional Text | Max 170 characters | Can be updated at any time without review. Useful for campaign announcements |
| Support URL | Required | URL of a valid support page |
| Marketing URL | Optional | Official website for the app |

### 3.2 Screenshot Requirements

#### [iOS]

| Device | Size (px) | Required |
|---------|------------|------|
| iPhone 6.9" (Pro Max) | 1320 × 2868 | ✅ |
| iPhone 6.7" | 1290 × 2796 | ✅ |
| iPhone 6.5" | 1284 × 2778 or 1242 × 2688 | ✅ |
| iPhone 5.5" | 1242 × 2208 | ✅ |
| iPad Pro 13" (M4) | 2064 × 2752 | ✅ if iPad-supported |
| iPad Pro 12.9" (6th gen) | 2048 × 2732 | ✅ if iPad-supported |

#### [macOS]

| Size (px) | Notes |
|------------|------|
| 1280 × 800 or larger (max 2560 × 1600) | Minimum 1, maximum 10 |

#### Common Rules

- Minimum 1, maximum 10 per device size
- PNG or JPEG format (no transparency)
- Do not include personal information in the status bar
- Recommended to provide screenshots for each localized language

### 3.3 App Preview Videos

| Item | Requirement |
|------|------|
| Length | 15–30 seconds |
| Format | H.264 / HEVC, MOV |
| Resolution | Match the screenshot size for each device |
| Audio | Optional (plays muted by default) |
| Count | Maximum 3 per device size |

### 3.4 App Icon

| Item | Requirement |
|------|------|
| Size | 1024 × 1024 px |
| Format | PNG (no transparency, no rounded corners) |
| Note | Submit as a square; iOS applies the rounded corner mask automatically |

---

## 4. Privacy & Compliance

### 4.1 App Privacy Details (Privacy Labels)

Declare the following in App Store Connect:

1. **Types of data collected**: Contact info, location, identifiers, usage data, etc.
2. **Purpose of data use**: App functionality, analytics, third-party advertising, etc.
3. **Data linking**: Whether data is linked to the user's identity
4. **Tracking**: Whether App Tracking Transparency (ATT) is required

- Data collection by third-party SDKs must also be declared
- If declared information does not match actual app behavior, the app will be rejected

### 4.2 Privacy Policy

- **Required for all apps**
- Register a valid URL in App Store Connect
- Clearly state what data the app collects and how it is used
- Comply with applicable laws (GDPR, CCPA, etc.)

### 4.3 Privacy Manifest (PrivacyInfo.xcprivacy)

Add a `PrivacyInfo.xcprivacy` file to the Xcode project:

```xml
<!-- Example PrivacyInfo.xcprivacy configuration -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <!-- Add an entry for each type of data collected -->
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <!-- Add an entry for each Required Reason API -->
    </array>
</dict>
</plist>
```

### 4.4 Required Reason APIs

When using the following APIs, a valid reason must be declared:

| API Category | Examples |
|-------------|-----|
| File timestamp APIs | `NSFileCreationDate`, `NSFileModificationDate` |
| System boot time APIs | `systemUptime`, `ProcessInfo` |
| Disk space APIs | `volumeAvailableCapacity` |
| User defaults APIs | `UserDefaults` (including via third-party SDKs) |
| Active keyboard APIs | `UITextInputMode` |

- Be aware of Required Reason APIs used by third-party SDKs
- Use Xcode's Privacy Report to review usage

### 4.5 Export Compliance (Encryption Usage Declaration)

Set the following in `Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

| Situation | Value |
|------|-------|
| HTTPS only (ATS standard) | `false` |
| Custom encryption algorithm implemented | `true` (encryption documentation submission required) |
| Standard encryption libraries only | In most cases `false` (exempt) |

- If `true`, French encryption regulation documentation may be required
- Consult legal / compliance team if uncertain

### 4.6 Age Restrictions & COPPA Compliance

- Apps for children (Kids category) are subject to additional review criteria
- Restrictions on use of third-party analytics and advertising SDKs
- COPPA (Children's Online Privacy Protection Act) compliance required
- Set the Content Rating in App Store Connect accurately

---

## 5. App Review Guidelines Compliance

### 5.1 Common Rejection Reasons & How to Avoid Them

| Guideline | Reason | How to Avoid |
|-----------|------|--------|
| **2.1** Performance | Too many crashes or bugs | Conduct thorough testing. Pre-validate with TestFlight |
| **2.1** Incomplete app | Placeholder content or unimplemented features | Submit only when all features are functional |
| **2.3.7** Metadata accuracy | Screenshots do not match the actual app | Take screenshots from the latest build |
| **2.3.10** In-app advertising | Test ads are shown | Switch to production ad IDs |
| **3.1.1** IAP requirements | External payment used for digital content purchases | Use IAP for digital content. External payment is allowed for physical goods |
| **3.1.2** Subscriptions | Restore Purchases is missing | Always implement the Restore feature |
| **4.0** Design | Does not comply with HIG | Refer to the `apple-ui-guidelines` skill |
| **4.2** Minimum functionality | App is merely a website wrapper | Leverage native features to provide added value |
| **5.1.1** Data collection | Collecting unnecessary data | Collect only the minimum required data. State the reason clearly |
| **5.1.2** Data use and sharing | Privacy labels do not match implementation | Fill in Privacy Manifest and App Privacy Details accurately |
| **5.2.1** Legal requirements | Privacy policy is insufficient | Set a valid privacy policy URL |

### 5.2 App Review Notes & Demo Accounts

- **App Review Notes**: Include supplementary notes for the reviewer
  - Provide demo account credentials for apps that require login
  - Explain features that require special hardware
  - Provide setup instructions if server-side configuration is needed

```
✅ Good: Example App Review Notes
---
Demo Account:
  Email: demo@example.com
  Password: Review2026!

Regarding Bluetooth functionality:
  The Bluetooth feature of this app can be verified using Demo Mode.
  Go to Settings > Demo Mode and turn it ON.
```

### 5.3 Appeal

1. Communicate with the review team through the "Resolution Center" in App Store Connect
2. Provide specific counterarguments and details of fixes for each rejection reason
3. If unresolved, a formal appeal to the App Review Board is possible
4. Respond politely and stick to the facts

---

## 6. Versioning & Release Strategy

### 6.1 Versioning Conventions

| Key | Description | Example |
|------|------|-----|
| `CFBundleShortVersionString` | Version number displayed to users | `2.1.0` |
| `CFBundleVersion` | Build number (unique within the same version) | `2024041801` |

- Recommended to use Semantic Versioning (`MAJOR.MINOR.PATCH`) for version numbers
- Build numbers must be monotonically increasing (App Store Connect will reject otherwise)
- Example build number format: `YYYYMMDDNN` or sequential integers

### 6.2 Release Options

| Option | Description | Recommended Use Case |
|-----------|------|-----------|
| Automatic release | Publish immediately after review approval | Regular updates |
| Manual release | Publish manually after review approval | Releases coordinated with marketing |
| Phased Release | Roll out gradually over 7 days | Major updates where you want to reduce risk |
| Scheduled release | Publish at a specified date and time | Event or campaign-tied releases |

### 6.3 Phased Release

| Day | Distribution % |
|----|---------|
| Day 1 | 1% |
| Day 2 | 2% |
| Day 3 | 5% |
| Day 4 | 10% |
| Day 5 | 20% |
| Day 6 | 50% |
| Day 7 | 100% |

- Even during phased release, users can get the update immediately by manually updating
- Phased release can be paused if issues are found
- For critical issues, the release can be pulled and a hotfix submitted

### 6.4 Multi-Platform Simultaneous Release

- **Universal Purchase**: Share the same purchase entitlement across iOS and macOS
  - Assign the same Bundle ID group
  - Configure the link in App Store Connect
- Recommended to align version numbers between iOS and macOS
- If releasing on one platform first, announce in the release notes

---

## 7. TestFlight Beta Testing

### 7.1 Internal vs External Testing

| Item | Internal Testing | External Testing |
|------|-----------|-----------|
| Number of testers | Up to 100 | Up to 10,000 |
| Who | Team members (App Store Connect users) | Invited via email address or public link |
| Beta App Review | Not required | Required for first build and significant changes |
| Build availability | Available immediately | Available after Beta App Review |

### 7.2 Test Group Management

- Create groups for specific purposes (e.g., internal QA, external beta, VIP users)
- Different builds can be distributed to each group
- Include release notes (What to Test) for testers

### 7.3 Beta App Review Notes

- The first external test build requires review (typically 24–48 hours)
- Subsequent builds with no significant changes are often auto-approved
- The same guidelines as production App Review apply
- Include demo account information for the review in the review notes

### 7.4 Testing Period

- TestFlight builds expire after **90 days**
- Upload a new build before expiration
- Encourage testers to submit feedback (screenshot feedback feature in the TestFlight app)

---

## 8. macOS-Specific Considerations [macOS]

### 8.1 Mac Catalyst vs Native macOS

| Item | Mac Catalyst | Native macOS |
|------|-------------|----------------|
| Submission method | iOS app's "Mac (Designed for iPad)" or Catalyst-enabled | Submit as a standalone macOS app |
| Bundle ID | May be the same as the iOS app (`maccatalyst.*`) | Unique Bundle ID |
| Review | Reviewed separately for macOS | macOS-specific review criteria |

### 8.2 Sandbox Requirements

- **App Sandbox is required for apps distributed through the Mac App Store**
- Declare required permissions in the Entitlements file:

| Entitlement | Purpose |
|------------|------|
| `com.apple.security.network.client` | Network connections (outbound) |
| `com.apple.security.network.server` | Network connections (inbound) |
| `com.apple.security.files.user-selected.read-write` | Access to user-selected files |
| `com.apple.security.files.bookmarks.app-scope` | Security-scoped bookmarks |

- Some features may be restricted by Sandbox limitations
- Temporary Exception Entitlements are scrutinized heavily during review

### 8.3 Hardened Runtime & Notarization

| Item | Requirement |
|------|------|
| Hardened Runtime | Required for Mac App Store submission. Enable when code signing |
| Notarization | Required for distribution outside the Mac App Store. Apple handles it automatically for App Store submissions |

- Minimize Hardened Runtime exceptions:
  - `com.apple.security.cs.disable-library-validation` — Only when loading external libraries
  - `com.apple.security.cs.allow-jit` — Only when JIT compilation is required

### 8.4 Helper Tools & Extension Signing

- Helper tools (LaunchAgent / LaunchDaemon) also require signing
- System Extensions have separate review requirements (Endpoint Security, etc.)
- Finder Sync Extension, Share Extension, etc. are submitted as part of the main app

---

## 9. Post-Submission Operations

### 9.1 App Analytics

| Metric | How to Use |
|------|---------|
| Impressions | Number of App Store page views. Measure the impact of metadata optimization |
| Conversion rate | View → Download rate. Indicator for improving screenshots and descriptions |
| Retention rate | Continued usage rate. App quality indicator |
| Crash rate | Stability indicator. Helps identify high-priority fixes |

### 9.2 Customer Review Management

- App Store Connect allows replying to reviews
- Respond politely to negative reviews and communicate planned improvements
- Use `SKStoreReviewController.requestReview()` to prompt reviews at the right moment
  - Most effective immediately after a positive user experience
  - Excessive prompts degrade user experience (the system controls display frequency)

### 9.3 Crash Report Monitoring

| Tool | Features |
|--------|------|
| Xcode Organizer | Built into Xcode. Crash logs, energy reports, and disk write reports |
| App Store Connect | Web-based. Monitor crash rate trends in the Metrics tab |
| MetricKit | In-app API for collecting performance data |

- Submit a hotfix promptly if the crash rate is high
- Expedited Review can be requested (for critical bug fixes)

### 9.4 App Removal & Unpublishing

| Action | Description |
|------|------|
| Remove from sale | Hide the app from the App Store (existing users can still re-download) |
| Delete app | Permanently remove the app from App Store Connect (restorable within 180 days) |
| Unpublish in specific regions | Exclude from the distribution region list |

- The app continues to work for existing users after removal from sale
- The app name and Bundle ID cannot be reused for a certain period after deletion

---

## 10. Submission Checklist

### Initial Submission

- [ ] Enrolled in the Apple Developer Program
- [ ] App created in App Store Connect
- [ ] Bundle ID is correctly configured
- [ ] Distribution certificate and Provisioning Profile are valid
- [ ] Required Capabilities / Entitlements are configured

### Metadata

- [ ] App name and subtitle are set
- [ ] Description and keywords are properly filled in
- [ ] Screenshots for all required device sizes are uploaded
- [ ] App icon (1024 × 1024 px) is uploaded
- [ ] Support URL is valid
- [ ] Category and content rating are set

### Privacy & Compliance

- [ ] Privacy policy URL is registered
- [ ] App Privacy Details (privacy labels) are accurately filled in
- [ ] Privacy Manifest (PrivacyInfo.xcprivacy) is included in the project
- [ ] Required Reason API usage reasons are declared
- [ ] Export Compliance (`ITSAppUsesNonExemptEncryption`) is set
- [ ] COPPA compliance verified for children's apps

### Build & Signing

- [ ] Archive created with a Release build
- [ ] Test ads and debug flags are disabled
- [ ] Confirmed no crashes or critical bugs via TestFlight
- [ ] dSYM files are uploaded (for crash reports)

### App Review Preparation

- [ ] Demo account credentials included in App Review Notes (if login is required)
- [ ] Instructions for special features included in App Review Notes
- [ ] Screenshots match the actual app
- [ ] All links and buttons work correctly

### macOS-Specific [macOS]

- [ ] App Sandbox is enabled
- [ ] Hardened Runtime is enabled
- [ ] Helper tools and extensions are signed
- [ ] Temporary Exception Entitlements are kept to the minimum necessary

### Release Settings

- [ ] Release option selected (automatic / manual / phased)
- [ ] Version number and build number are correct (monotonically increasing)
- [ ] What's New (release notes) are filled in
