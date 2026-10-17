# Getting Leaf onto TestFlight (Xcode only)

Leaf is a plain Xcode project: no Expo, no CocoaPods, no packages, no paid
services. You build and upload it from Xcode on your Mac with your Apple
Developer account. The first time takes about 30 minutes, mostly spent waiting
on Apple's processing. After that, each new build is Archive → Upload.

## What's already set up in the project

- **Targets:** `Leaf` (iPhone, iOS 26+) with `LeafWatch` (Apple Watch, watchOS 26+)
  embedded, so installing the iPhone app offers the watch app automatically.
- **Bundle IDs:** `com.norvodesigns.leaf` and `com.norvodesigns.leaf.watchkitapp`.
  Confirm these before the first upload. Once Apple registers them, they can't change.
- **Version 1.0, build 1,** set once at the project level so the phone and watch
  apps always match. Xcode bumps the build number for you on upload (step 5).
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` (Leaf uses only HTTPS),
  so App Store Connect won't ask about encryption on every build.
- **Privacy manifest:** no tracking and no collected data.
- **App icons:** light, dark and tinted variants, plus the watch icon.
- **Capabilities:** none that need special provisioning. Notifications are local
  and WatchConnectivity needs no entitlement.

## 1. Open the project

1. Install **Xcode 26 or later** from the Mac App Store.
2. Clone the repo. In Xcode choose **Integrate → Clone…** and paste
   `https://github.com/norvodesigns/leaf`, or in Terminal run
   `git clone https://github.com/norvodesigns/leaf`.
3. Double-click **`Leaf.xcodeproj`**.

## 2. Pick your team (one time)

1. In the navigator on the left, click the blue **Leaf** project icon.
2. Under **Targets**, select **Leaf**, open **Signing & Capabilities**, and
   choose your team under **Team**. Leave **Automatically manage signing** on.
3. Do the same for the **LeafWatch** target and, optionally, **LeafTests**.

Xcode registers both bundle IDs and creates the signing certificates and
profiles for you.

## 3. Try it on your own iPhone and Watch (optional, recommended)

1. Plug in your iPhone. If prompted, turn on **Settings → Privacy & Security →
   Developer Mode** on the phone.
2. Pick the phone as the run destination at the top of the window, then press **⌘R**.
3. The watch app installs on the paired Apple Watch automatically. If it
   doesn't, open the **Watch** app on the iPhone, find **Leaf**, and tap **Install**.

## 4. Create the app in App Store Connect (one time)

1. Go to https://appstoreconnect.apple.com → **Apps** → **+** → **New App**.
2. Fill in:
   - **Platform:** iOS
   - **Name:** must be unique on the whole App Store, and "Leaf" is almost
     certainly taken. Try **Leaf: Reading Planner**. The name under the icon on
     the home screen stays "Leaf" either way.
   - **Primary language:** English (U.S.)
   - **Bundle ID:** `com.norvodesigns.leaf`. It appears in the list after step 2.
     If it isn't there yet, build to a device once or do step 5 first.
   - **SKU:** `leaf-ios` (any unique string)
   - **User access:** Full Access

## 5. Archive and upload

1. At the top of the Xcode window, set the run destination to **Any iOS Device (arm64)**.
2. Choose **Product → Archive**. This takes a few minutes.
3. When the Organizer opens, select the new archive and click **Distribute App**.
4. Choose **App Store Connect** → **Distribute**. Keep the defaults, including
   **Manage Version and Build Number** (it bumps the build number for both the
   phone and watch apps) and **Automatically manage signing**.
5. Click **Upload**.

Apple takes about 5–15 minutes to process the build. Then it shows up under
**App Store Connect → your app → TestFlight**.

### Or from Terminal

`scripts/testflight.sh` does the same archive and upload with Xcode's
command-line tools. Do steps 2 and 4 once first, then:

```bash
sudo xcode-select -s /Applications/Xcode.app    # use the full Xcode, not just the Command Line Tools
cd leaf
TEAM_ID=ABCDE12345 scripts/testflight.sh       # your Team ID: developer.apple.com/account → Membership details
```

It signs with the Apple ID you're signed in with in **Xcode → Settings → Accounts**.
Each run uses a timestamp as the build number, so every upload is accepted.
To use an App Store Connect API key instead (**Users and Access → Integrations →
App Store Connect API**, role *App Manager*), save the `.p8` file to
`~/.appstoreconnect/private_keys/` and put `ASC_KEY_ID=… ASC_ISSUER_ID=…` before the command.

## 6. Invite testers

- **Internal testing** (you and up to 100 people on your App Store Connect team):
  **TestFlight → Internal Testing → +** to add a group, then add testers. No
  review is needed and the build is available right away.
- **External testing** (up to 10,000 people by email or public link): needs a
  one-time **Beta App Review**, which usually takes about a day. It asks for a
  short description of what to test, a feedback email, and a **privacy policy
  URL**. The text for the policy is in [`PRIVACY.md`](PRIVACY.md), so you can
  publish it on any public page (for example a `/leaf/privacy` page on your website).

Testers install the **TestFlight** app from the App Store and accept the
invite. The watch app comes along with the iPhone app.

## Testing the Apple Watch app

The watch app ships inside the iPhone app, so there's nothing separate to upload.

1. Install Leaf from TestFlight on an iPhone that's paired with an Apple Watch.
2. On the iPhone, open the **Watch** app → scroll to **Leaf** → tap **Install**
   (or turn on **Show App on Apple Watch**).
3. Open Leaf on the iPhone and finish onboarding once. The watch shows today's
   reading as soon as the two devices have synced, usually within a few seconds.
4. Start a session on either device and it appears on both. End it on the watch by
   turning the Digital Crown to the page you reached, or on the phone as usual.

If the watch says "Open Leaf on your iPhone", launch the phone app once with both
devices nearby.

## 7. App Privacy answers

On App Store Connect → **App Privacy**, answer **"Data Not Collected"**.
Everything Leaf stores stays on the device. Book searches send only the search
text to Open Library, which isn't linked to the user.

## Later builds

Pull the latest code (**Integrate → Pull** in Xcode), then repeat step 5.

## About the GitHub Actions check

`.github/workflows/ios.yml` builds the project, runs the unit tests, and takes
simulator screenshots on a GitHub-hosted Mac on every push to `main`. It never
signs or uploads anything. On a private repo it uses your account's free
GitHub Actions minutes (macOS minutes count 10× against the monthly allowance).
If you'd rather not use it, open **Actions → iOS → ⋯ → Disable workflow**.
Nothing else depends on it.
