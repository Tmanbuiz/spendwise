# Building SpendWise for iPhone

iPhone apps can only be built on macOS. SpendWise is built on Codemagic's Macs
from this GitHub repository, then installed through TestFlight, so no Mac is
needed.

## What works on iPhone

Everything except automatic capture from bank notifications. Apple does not let
any app read another app's notifications, so on iPhone:

- statements are imported from Files, Mail or the bank's download, including
  with **Open in SpendWise** on a PDF, CSV or text file
- expenses can be added by hand
- budgets, insights, the Vault, the EI hours tracker and the Leave Planner all
  work as on Android

Budget notifications are Android-only for now and are hidden on iPhone.

## One-time setup

1. **Apple Developer Program** (US$99 a year) at developer.apple.com.
   Enrolling as an individual is quickest. Enrolling as **WianTribe Inc** needs
   the company's D-U-N-S number and takes longer, but the App Store then shows
   WianTribe as the developer.

2. **Register the app ID.** In Certificates, Identifiers & Profiles, add an App
   ID with the bundle ID `com.wiantribe.spendwise`. It cannot be changed after
   the first upload.

3. **Create the app in App Store Connect.** Choose iOS, the bundle ID above,
   and a name. App Store names are unique, so "SpendWise" may already be taken;
   something like "SpendWise by WianTribe" works. Note the **Apple ID** number
   under App Information.

4. **Create an App Store Connect API key.** In App Store Connect, Users and
   Access, Integrations, generate a key with the App Manager role. Download the
   `.p8` file once (Apple does not offer it again) and note the Issuer ID and
   Key ID.

5. **Connect Codemagic.** Sign in to codemagic.io with GitHub and add the
   `Tmanbuiz/spendwise` repository. Under team integrations, add the API key
   and name it exactly `SpendWise App Store Connect`. Under code signing
   identities, let Codemagic create or fetch an iOS distribution certificate
   and an App Store profile for `com.wiantribe.spendwise`.

6. **Fill in `codemagic.yaml`.** Replace `APP_STORE_APPLE_ID: 0000000000` with
   the Apple ID number from step 3, and commit it.

## Each build

1. In Codemagic, start the **iOS to TestFlight** workflow on `master`.
2. When it finishes, the build appears in App Store Connect under TestFlight,
   usually after Apple's processing, which can take a while.
3. Install Apple's **TestFlight** app on the iPhone, accept the invitation, and
   install SpendWise from there.

The build number is taken from the latest TestFlight build plus one, so builds
never collide. The version name comes from `app/pubspec.yaml`.
