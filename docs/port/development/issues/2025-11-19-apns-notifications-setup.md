# APNs Notifications Setup & Verification (Native iOS + Supabase Edge Functions)

This document describes how to fully configure and verify the push notification pipeline for the native iOS app using APNs and the `ask-ai-v7` Supabase Edge Function.

The React Native / Expo stack is deprecated; only native iOS + APNs is supported.

---

## 1. iOS App Target Configuration

**Files involved**

- `native/WhatsThatIOS/WhatsThatIOSApp.swift`
- `native/WhatsThatIOS/AppDelegate.swift`
- `native/Config/WhatsThatIOS.entitlements`
- `native/WhatsThatIOSPackage/Sources/WhatsThatInfrastructure/Services/Notifications/NativePushService.swift`
- `native/WhatsThatIOSPackage/Sources/WhatsThatInfrastructure/Services/Notifications/NativePushTokenStore.swift`

**Steps**

1. Open `native/WhatsThatIOS.xcworkspace` in Xcode.
2. Select the **WhatsThatIOS** app target.
3. On the **Signing & Capabilities** tab:
   - Ensure the **Bundle Identifier** is the intended production identifier (e.g. `com.yourcompany.whats-that-ios`).
   - Add the **Push Notifications** capability if it is not already present.
   - Ensure the **Associated Domains** capability matches the values in `WhatsThatIOS.entitlements` if used (for deep links).
4. Confirm entitlements:
   - `native/Config/WhatsThatIOS.entitlements` must include:
     - `aps-environment = development` for debug/sandbox builds.
     - For App Store builds, Xcode will typically switch to `production` using the archive configuration; verify before release.
5. Confirm the app entry point:
   - `WhatsThatIOSApp` uses `@UIApplicationDelegateAdaptor(AppDelegate.self)` so that:
     - `AppDelegate` receives `didRegisterForRemoteNotificationsWithDeviceToken`.
     - The delegate forwards the APNs device token into `NativePushTokenStore.shared`.
6. Confirm the push service:
   - `NativePushService.requestPushAuthorizationIfNeeded()`:
     - Requests authorization via `UNUserNotificationCenter`.
     - Calls `UIApplication.shared.registerForRemoteNotifications()` on iOS.
     - Awaits a token from `NativePushTokenStore.shared`.

---

## 2. Apple Developer Portal Configuration

You need access to the Apple Developer account for the team that owns this app.

**2.1 Team ID (`APNS_TEAM_ID`)**

1. Go to <https://developer.apple.com/account/>.
2. Click **Membership**.
3. Copy **Team ID** (e.g. `ABCD123456`).
4. Use this value as `APNS_TEAM_ID`.

**2.2 App Identifier / Bundle ID (`APNS_BUNDLE_ID`)**

1. In the Apple Developer portal, go to **Certificates, Identifiers & Profiles → Identifiers**.
2. Ensure there is an **App ID** that matches the Xcode bundle identifier used by `WhatsThatIOS`.
3. Edit that App ID:
   - Turn on **Push Notifications**.
4. Use the bundle identifier string (e.g. `com.yourcompany.whats-that-ios`) as `APNS_BUNDLE_ID`.

**2.3 APNs Auth Key (`APNS_KEY_ID`, `APNS_PRIVATE_KEY`)**

1. In the Apple Developer portal, go to **Certificates, Identifiers & Profiles → Keys**.
2. Click the **+** button to create a new key.
3. Give it a descriptive name (e.g. `WhatsThat APNs Key`).
4. Enable **Apple Push Notifications service (APNs)**.
5. Click **Continue → Register → Download**.
6. Note the **Key ID** shown on the details page; this is `APNS_KEY_ID`.
7. Securely store the downloaded `.p8` file. You can only download it once.
8. Open the `.p8` file in a text editor and copy the full contents, including:
   ```text
   -----BEGIN PRIVATE KEY-----
   ...
   -----END PRIVATE KEY-----
   ```
9. Use the full PEM text as `APNS_PRIVATE_KEY` (do **not** commit this file or value to git).

**2.4 Environment (`APNS_ENVIRONMENT`)**

- For development / staging, use:
  - `APNS_ENVIRONMENT = sandbox`
- For production, use:
  - `APNS_ENVIRONMENT = production`

The same auth key can be used for both environments; the flag only changes the APNs host (`api.sandbox.push.apple.com` vs `api.push.apple.com`).

---

## 3. Supabase Edge Function Configuration

**File involved**

- `supabase/functions/ask-ai-v7/index.ts`

The `ask-ai-v7` Edge Function:

- Accepts an optional `pushToken` in the request body.
- After creating the discovery, calls:
  ```ts
  await sendPushNotification(
    pushToken,
    "Discovery Complete! 🎉",
    `Your discovery "${titleForStorage}" is ready to view.`,
    String(discoveryId),
    pushLogger
  );
  ```
- `sendPushNotification` is APNs-only and uses:
  - `APNS_TEAM_ID`
  - `APNS_KEY_ID`
  - `APNS_PRIVATE_KEY`
  - `APNS_BUNDLE_ID`
  - `APNS_ENVIRONMENT`

### 3.1 Local Development (Supabase CLI)

For `supabase start` / `supabase functions serve ask-ai-v7`:

1. Export environment variables in your shell (do **not** commit these):
   ```bash
   export APNS_TEAM_ID=YOUR_TEAM_ID
   export APNS_KEY_ID=YOUR_KEY_ID
   export APNS_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----
   ...
   -----END PRIVATE KEY-----'
   export APNS_BUNDLE_ID=com.yourcompany.whats-that-ios
   export APNS_ENVIRONMENT=sandbox
   ```
2. Optionally, wire them through `supabase/config.toml` so they are visible to all functions:
   ```toml
   [functions.environment]
   APNS_TEAM_ID = "env(APNS_TEAM_ID)"
   APNS_KEY_ID = "env(APNS_KEY_ID)"
   APNS_PRIVATE_KEY = "env(APNS_PRIVATE_KEY)"
   APNS_BUNDLE_ID = "env(APNS_BUNDLE_ID)"
   APNS_ENVIRONMENT = "env(APNS_ENVIRONMENT)"
   ```
3. Restart the local stack:
   ```bash
   supabase stop
   supabase start
   ```

### 3.2 Supabase Cloud (Production / Staging)

In the Supabase Dashboard:

1. Open your project in Supabase Studio.
2. Navigate to **Settings → Configuration** (Environment Variables / Secrets).
3. Add the following keys for the project:
   - `APNS_TEAM_ID`
   - `APNS_KEY_ID`
   - `APNS_PRIVATE_KEY`
   - `APNS_BUNDLE_ID`
   - `APNS_ENVIRONMENT` (`sandbox` or `production`)
4. Save and redeploy the `ask-ai-v7` function if necessary.

Alternatively, using the Supabase CLI:

```bash
supabase secrets set \
  APNS_TEAM_ID=YOUR_TEAM_ID \
  APNS_KEY_ID=YOUR_KEY_ID \
  APNS_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----
  ...
  -----END PRIVATE KEY-----' \
  APNS_BUNDLE_ID=com.yourcompany.whats-that-ios \
  APNS_ENVIRONMENT=production
```

---

## 4. End-to-End Verification Checklist

Use this checklist to verify notifications are fully working.

### 4.1 App-Side Verification (Simulator vs Device)

**On real device (recommended for APNs)**

1. Install and run the `WhatsThatIOS` app on an iPhone signed into the correct Apple ID.
2. Confirm that:
   - The notifications permission prompt appears when:
     - Using the onboarding permissions card, or
     - Running a discovery flow that triggers `NativePushService.requestPushAuthorizationIfNeeded()`.
   - The app does **not** crash when requesting permission or registering.
3. Accept notifications.
4. In Xcode console logs, look for:
   - A `[Push]` log from `AppDelegate` if registration fails.
   - Optional debug logging you may add around `NativePushTokenStore.updateToken` to confirm a token is received.

**On simulator**

- The current code path will still run, but APNs does not deliver real remote notifications to the simulator.
- Use simulator primarily to verify that:
  - Permission prompts appear.
  - No runtime crashes.
  - The `pushToken` field is populated in the payload sent to `ask-ai-v7` (inspect logs).

### 4.2 Edge Function Verification

1. Ensure the `ask-ai-v7` function is deployed with the latest code from this repository.
2. On local Supabase or Cloud:
   - Trigger a discovery from the app (on a device with notifications enabled).
3. In Supabase logs (Functions / `ask-ai-v7`):
   - Confirm that:
     - The request includes a non-empty `pushToken`.
     - After the discovery insert, the logs show:
       - `sendPushNotification` called.
       - Either:
         - `APNs push notification sent successfully`, or
         - A detailed `APNs push API error` with `reason` and status.

If you see `APNs credentials not configured` or missing env vars in logs, revisit section **3**.

### 4.3 Device Notification Delivery

On the physical device:

1. Put the app in the background (home button / swipe up).
2. Trigger a new discovery from another device or from the same device (if flow allows).
3. After the `ask-ai-v7` analysis completes:
   - You should receive a push notification:
     - Title: `"Discovery Complete! 🎉"`
     - Body: `Your discovery "<title>" is ready to view.`
4. Tap the notification:
   - Currently, the app delegate’s `userNotificationCenter(_:didReceive:withCompletionHandler:)` is a no-op placeholder.
   - Future work (optional): parse `discoveryId` from `userInfo` and deep-link into the discovery detail screen.

---

## 5. Common Failure Modes & Debug Tips

- **No notification prompt in app**
  - Check that `UNUserNotificationCenter` is being queried in `OnboardingPermissionsCoordinator` and `NativePushService`.
  - Confirm the app target has the **Push Notifications** capability in Xcode.

- **Prompt appears but no device token**
  - Confirm `AppDelegate` is wired via `@UIApplicationDelegateAdaptor`.
  - Add temporary logs in:
    - `didRegisterForRemoteNotificationsWithDeviceToken`
    - `didFailToRegisterForRemoteNotificationsWithError`
  - Ensure `NativePushTokenStore.updateToken` is called.

- **Function logs show APNs errors**
  - Verify `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `APNS_ENVIRONMENT` are all set and match the Apple Developer configuration.
  - Check that the bundle ID used in `APNS_BUNDLE_ID` matches the one used to sign the app sending the device token.

- **Notifications work in sandbox but not production**
  - Confirm:
    - `APNS_ENVIRONMENT=production` in the production Supabase project.
    - The app is built with a distribution profile and uses the same bundle ID.
    - The APNs auth key is still valid and associated with the correct team.

---

## 6. Future Enhancements

- Deep Link Handling:
  - Update `AppDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)` to:
    - Parse `discoveryId` from the notification payload.
    - Route into the discovery detail flow in SwiftUI.
- Token Management:
  - Optionally upsert device tokens to the `push_tokens` table for audits and cleanup.
- Test Coverage:
  - Add integration tests (or manual test scripts) that exercise:
    - Permission changes (denied → allowed).
    - Multiple devices per user.
    - Error handling when APNs returns specific failure reasons.

