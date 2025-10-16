# Sign in with Apple – Production Checklist

These steps wire the iOS app, Apple Developer portal, and Supabase project together so that Sign in with Apple succeeds in production. Follow them in order; each stage depends on the previous one.

## 1. Prepare configuration secrets

1. Copy `native/Config/Environments/Example.xcconfig` to a non-tracked file, e.g. `native/Config/Environments/Production.xcconfig`.
2. Populate at minimum:
   ```xcconfig
   SUPABASE_URL_SCHEME = https://
   SUPABASE_URL_HOST_PATH = your-project.supabase.co
   SUPABASE_URL = $(SUPABASE_URL_SCHEME)$(SUPABASE_URL_HOST_PATH)
   SUPABASE_ANON_KEY = <supabase anon key>
   GOOGLE_CLIENT_ID = <google client id or leave blank if unused>
   ```
3. Reference this xcconfig in the `Production` build configuration (Xcode ▸ File ▸ Project Settings ▸ Info tab ▸ `Production` configuration row ▸ set “Based on Configuration File” to your new file).

## 2. Register bundle identifiers

In the Apple Developer portal (**Certificates, Identifiers & Profiles ▸ Identifiers**):

1. Create (or locate) the App ID that will ship to the App Store. Its Bundle ID **must** match the value in Xcode (e.g. `com.company.whats-that`).
2. Enable the **Sign in with Apple** capability for that App ID.
3. If you intend to support universal links/Web SSO, also register a **Services ID**; otherwise, native apps do not need it.

## 3. Generate the Sign in with Apple key

In the portal (**Certificates, Identifiers & Profiles ▸ Keys**):

1. Create a new key, check **Sign in with Apple**, and associate it with the App ID from step 2.
2. Download the `.p8` key file (Apple only lets you download it once).
3. Record:
   - **Key ID** (displayed after creation),
   - **Team ID** (shown in the top-right corner of the developer portal).

## 4. Configure Supabase Apple provider

In the Supabase dashboard (**Authentication ▸ Providers ▸ Apple**):

1. **Services ID / Client ID**: set to the App ID / bundle identifier used in step 2 (e.g. `com.company.whats-that`).
2. **Key ID**: paste the Apple Key ID from step 3.
3. **Team ID**: paste the Apple Team ID.
4. **Private Key**: paste the entire contents of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines.
5. Save the provider configuration.

## 5. Update the Xcode project

1. Open the workspace and set the target’s **Bundle Identifier** to the production value registered in step 2.
2. In the target’s **Signing & Capabilities** tab:
   - Ensure **Automatically manage signing** is enabled (or provide the appropriate provisioning profile).
   - Add the **Sign in with Apple** capability if Xcode did not import it automatically. This writes the `com.apple.developer.applesignin = ["Default"]` entitlement (already committed).
3. Clean build (`Shift+Cmd+K`) to recompile entitlements.

## 6. Supply runtime environment

1. Ensure the Supabase project referenced in your xcconfig has the Apple provider enabled (step 4). Without this, Supabase returns `AuthError.unknown` after Apple’s flow.
2. Provide the correct Supabase environment variables at runtime:
   - For production builds, Xcode will read them from the `Production.xcconfig`.
   - For local testing, either switch the scheme to the configuration that uses your new `.xcconfig` or provide overrides via `Edit Scheme ▸ Arguments`.

## 7. Verify the flow

1. Run on a device or simulator that is signed into an Apple ID.
2. Attach a log stream to catch the instrumentation we added:
   ```bash
   log stream --info --predicate 'subsystem == "WhatsThatIOS" && (category == "SignInWithApple" || category == "SupabaseAuthService")'
   ```
3. Tap **Continue with Apple** in the app. A successful path looks like:
   - Apple sheet appears and returns without logging an error.
   - Supabase exchanges the token (`Sign in with Apple flow succeeded` log) and emits an authenticated session.
4. If the sheet shows “Something went wrong”, inspect the console:
   - `Sign in with Apple unavailable: missing service instance` → entitlement/capability not enabled.
   - `Sign in with Apple flow failed: ... -7026` → Apple rejected the bundle ID; double-check portal setup.
   - `Supabase Apple sign-in exchange failed: ...` → Supabase configuration (client ID, key) is incorrect.

## 8. CI / build machine considerations

- Make sure the CI machine (or Xcode Cloud) has access to the Apple Sign In signing certificate and provisioning profile that now include the capability.
- Keep the `.p8` private key, Supabase anon key, and any environment overrides out of source control; inject them via your secrets manager.

Once all of the above is in place, the production app will have a valid entitlement, Apple will issue tokens for your bundle ID, and Supabase will accept them—removing the “Something went wrong” fallback.***
