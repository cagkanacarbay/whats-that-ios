# Step-by-Step Implementation Guide: Version Control & Compliance System

This document provides a complete, file-by-file implementation guide with specific line numbers and changes. Follow these steps in order.

---

## Table of Contents

1. [Database Migration](#1-database-migration)
2. [New Files to Create](#2-new-files-to-create)
3. [Existing Files to Modify](#3-existing-files-to-modify)
4. [Potential Issues &amp; Considerations](#4-potential-issues--considerations)
5. [Testing Checklist](#5-testing-checklist)

---

## 1. Database Migration

Create the migration file as specified in [implementation-plan.md](./implementation-plan.md).

### File: `supabase/migrations/20260120143000_version_control.sql`

Execute the following SQL in order:

```sql
-- 1. Create ENUMs
CREATE TYPE version_type AS ENUM ('tos', 'privacy', 'app');
CREATE TYPE update_type AS ENUM ('soft', 'force');

-- 2. Create version_log table (lines 35-67 of implementation-plan.md)
CREATE TABLE public.version_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type version_type NOT NULL,
  version TEXT NOT NULL,
  message TEXT,
  app_update_type update_type DEFAULT 'soft',
  released_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_version_log_type_released
  ON public.version_log(type, released_at DESC);

ALTER TABLE public.version_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read version log" ON public.version_log
  FOR SELECT USING (true);

-- 3. Create user_agreements table (lines 83-112 of implementation-plan.md)
CREATE TABLE public.user_agreements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tos_version TEXT,
  privacy_version TEXT,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_agreements_user_accepted
  ON public.user_agreements(user_id, accepted_at DESC);

CREATE UNIQUE INDEX idx_user_agreements_unique_acceptance
  ON public.user_agreements(user_id, COALESCE(tos_version, ''), COALESCE(privacy_version, ''));

ALTER TABLE public.user_agreements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own agreements" ON public.user_agreements
  FOR SELECT USING (auth.uid() = user_id);

-- 4. Create app_config table (lines 127-155 of implementation-plan.md)
CREATE TABLE public.app_config (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  min_supported_version TEXT NOT NULL DEFAULT '0.0.0',
  maintenance_mode BOOLEAN DEFAULT FALSE,
  maintenance_message TEXT,
  app_store_url TEXT NOT NULL DEFAULT 'https://apps.apple.com/app/id...',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read app_config" ON public.app_config FOR SELECT USING (true);

-- 5. Initial data seed
INSERT INTO public.app_config (min_supported_version) VALUES ('1.0.0');

INSERT INTO public.version_log (type, version, message) VALUES
  ('tos', '1.0', 'Initial Terms of Service'),
  ('privacy', '1.0', 'Initial Privacy Policy'),
  ('app', '1.0.0', 'Initial release');

-- 6. Create get_app_config() function (lines 197-306 of implementation-plan.md)
CREATE OR REPLACE FUNCTION public.get_app_config()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
  current_user_id UUID := auth.uid();
  latest_tos_version TEXT;
  latest_privacy_version TEXT;
  user_tos_version TEXT;
  user_privacy_version TEXT;
  config_record RECORD;
BEGIN
  SELECT * INTO config_record FROM public.app_config LIMIT 1;
  IF config_record IS NULL THEN
    RAISE EXCEPTION 'App config missing';
  END IF;

  SELECT version INTO latest_tos_version
  FROM public.version_log
  WHERE type = 'tos'
  ORDER BY released_at DESC LIMIT 1;

  SELECT version INTO latest_privacy_version
  FROM public.version_log
  WHERE type = 'privacy'
  ORDER BY released_at DESC LIMIT 1;

  IF current_user_id IS NOT NULL THEN
    SELECT tos_version INTO user_tos_version
    FROM public.user_agreements
    WHERE user_id = current_user_id AND tos_version IS NOT NULL
    ORDER BY accepted_at DESC LIMIT 1;

    SELECT privacy_version INTO user_privacy_version
    FROM public.user_agreements
    WHERE user_id = current_user_id AND privacy_version IS NOT NULL
    ORDER BY accepted_at DESC LIMIT 1;
  END IF;

  SELECT json_build_object(
    'maintenance', json_build_object(
      'enabled', config_record.maintenance_mode,
      'message', config_record.maintenance_message
    ),
    'tos', (
      SELECT json_build_object(
        'version', version,
        'message', message,
        'released_at', released_at
      ) FROM public.version_log WHERE type = 'tos' ORDER BY released_at DESC LIMIT 1
    ),
    'privacy', (
      SELECT json_build_object(
        'version', version,
        'message', message,
        'released_at', released_at
      ) FROM public.version_log WHERE type = 'privacy' ORDER BY released_at DESC LIMIT 1
    ),
    'app', (
      SELECT json_build_object(
        'version', v.version,
        'message', v.message,
        'released_at', v.released_at,
        'app_update_type', v.app_update_type,
        'min_supported_version', config_record.min_supported_version,
        'app_store_url', config_record.app_store_url,
        'last_force_version', (
          SELECT version FROM public.version_log
          WHERE type = 'app' AND app_update_type = 'force'
          ORDER BY released_at DESC LIMIT 1
        )
      )
      FROM public.version_log v
      WHERE v.type = 'app'
      ORDER BY v.released_at DESC LIMIT 1
    ),
    'user_status', CASE
      WHEN current_user_id IS NOT NULL THEN json_build_object(
        'needs_tos_acceptance', (user_tos_version IS NULL OR user_tos_version <> latest_tos_version),
        'needs_privacy_acceptance', (user_privacy_version IS NULL OR user_privacy_version <> latest_privacy_version),
        'accepted_tos_version', user_tos_version,
        'accepted_privacy_version', user_privacy_version
      )
      ELSE NULL
    END
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_app_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_config() TO anon;

-- 7. Create accept_terms() function (lines 315-391 of implementation-plan.md)
CREATE OR REPLACE FUNCTION public.accept_terms(
  tos_version TEXT DEFAULT NULL,
  privacy_version TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_user_id UUID := auth.uid();
  latest_tos_version TEXT;
  latest_privacy_version TEXT;
  tos_to_insert TEXT := NULL;
  privacy_to_insert TEXT := NULL;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF tos_version IS NULL AND privacy_version IS NULL THEN
    RAISE EXCEPTION 'Must accept at least one version';
  END IF;

  IF tos_version IS NOT NULL THEN
    SELECT version INTO latest_tos_version
    FROM public.version_log
    WHERE type = 'tos'
    ORDER BY released_at DESC LIMIT 1;

    IF latest_tos_version IS NULL THEN
      RAISE EXCEPTION 'No ToS version found in version_log';
    END IF;

    IF tos_version != latest_tos_version THEN
      RAISE EXCEPTION 'Version mismatch: You are trying to accept ToS % but latest is %', tos_version, latest_tos_version;
    END IF;

    tos_to_insert := latest_tos_version;
  END IF;

  IF privacy_version IS NOT NULL THEN
    SELECT version INTO latest_privacy_version
    FROM public.version_log
    WHERE type = 'privacy'
    ORDER BY released_at DESC LIMIT 1;

    IF latest_privacy_version IS NULL THEN
      RAISE EXCEPTION 'No Privacy Policy version found in version_log';
    END IF;

    IF privacy_version != latest_privacy_version THEN
      RAISE EXCEPTION 'Version mismatch: You are trying to accept Privacy % but latest is %', privacy_version, latest_privacy_version;
    END IF;

    privacy_to_insert := latest_privacy_version;
  END IF;

  INSERT INTO public.user_agreements (user_id, tos_version, privacy_version)
  VALUES (current_user_id, tos_to_insert, privacy_to_insert)
  ON CONFLICT (user_id, COALESCE(tos_version, ''), COALESCE(privacy_version, '')) DO NOTHING;

  RETURN json_build_object(
    'success', true,
    'accepted_tos_version', tos_to_insert,
    'accepted_privacy_version', privacy_to_insert
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_terms(TEXT, TEXT) TO authenticated;

-- 8. Backfill existing users (run AFTER tables created, BEFORE app update)
INSERT INTO public.user_agreements (user_id, tos_version, privacy_version, accepted_at)
SELECT id, '1.0', '1.0', NOW()
FROM auth.users
WHERE id NOT IN (SELECT DISTINCT user_id FROM public.user_agreements);
```

---

## 2. New Files to Create

### 2.1 Domain Layer - Models

#### File: `Sources/WhatsThatDomain/VersionControl/AppConfigModels.swift`

```swift
import Foundation

// MARK: - App Config Response (from get_app_config RPC)

public struct AppConfigResponse: Codable, Sendable, Equatable {
    public let maintenance: MaintenanceConfig
    public let tos: VersionInfo
    public let privacy: VersionInfo
    public let app: AppVersionInfo
    public let userStatus: UserComplianceStatus?

    enum CodingKeys: String, CodingKey {
        case maintenance, tos, privacy, app
        case userStatus = "user_status"
    }
}

public struct MaintenanceConfig: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let message: String?
}

public struct VersionInfo: Codable, Sendable, Equatable {
    public let version: String
    public let message: String?
    public let releasedAt: Date

    enum CodingKeys: String, CodingKey {
        case version, message
        case releasedAt = "released_at"
    }
}

public struct AppVersionInfo: Codable, Sendable, Equatable {
    public let version: String
    public let message: String?
    public let releasedAt: Date
    public let appUpdateType: UpdateType
    public let minSupportedVersion: String
    public let appStoreUrl: String
    public let lastForceVersion: String?

    enum CodingKeys: String, CodingKey {
        case version, message
        case releasedAt = "released_at"
        case appUpdateType = "app_update_type"
        case minSupportedVersion = "min_supported_version"
        case appStoreUrl = "app_store_url"
        case lastForceVersion = "last_force_version"
    }
}

public enum UpdateType: String, Codable, Sendable {
    case soft
    case force
}

public struct UserComplianceStatus: Codable, Sendable, Equatable {
    public let needsTosAcceptance: Bool
    public let needsPrivacyAcceptance: Bool
    public let acceptedTosVersion: String?
    public let acceptedPrivacyVersion: String?

    enum CodingKeys: String, CodingKey {
        case needsTosAcceptance = "needs_tos_acceptance"
        case needsPrivacyAcceptance = "needs_privacy_acceptance"
        case acceptedTosVersion = "accepted_tos_version"
        case acceptedPrivacyVersion = "accepted_privacy_version"
    }
}

// MARK: - Accept Terms Response

public struct AcceptTermsResponse: Codable, Sendable {
    public let success: Bool
    public let acceptedTosVersion: String?
    public let acceptedPrivacyVersion: String?

    enum CodingKeys: String, CodingKey {
        case success
        case acceptedTosVersion = "accepted_tos_version"
        case acceptedPrivacyVersion = "accepted_privacy_version"
    }
}

// MARK: - Local Cache Structures

public struct AppUpdateReminderState: Codable, Sendable, Equatable {
    public var softUpdateVersion: String?
    public var lastReminderDate: Date?
    public var reminderCount: Int
    public var forceGracePeriodStartDate: Date?

    public init(
        softUpdateVersion: String? = nil,
        lastReminderDate: Date? = nil,
        reminderCount: Int = 0,
        forceGracePeriodStartDate: Date? = nil
    ) {
        self.softUpdateVersion = softUpdateVersion
        self.lastReminderDate = lastReminderDate
        self.reminderCount = reminderCount
        self.forceGracePeriodStartDate = forceGracePeriodStartDate
    }
}

public struct CachedMaintenanceState: Codable, Sendable {
    public let isEnabled: Bool
    public let message: String?
    public let cachedAt: Date

    public init(isEnabled: Bool, message: String?, cachedAt: Date = Date()) {
        self.isEnabled = isEnabled
        self.message = message
        self.cachedAt = cachedAt
    }

    public var isValid: Bool {
        Date().timeIntervalSince(cachedAt) < 10800 // 3 hours
    }
}

// MARK: - Blocking State

public enum ComplianceBlockingState: Equatable, Sendable {
    case maintenance(message: String?)
    case forceUpdateImmediate(targetVersion: String, appStoreUrl: String)
    case forceUpdateExpired(targetVersion: String, appStoreUrl: String, message: String?)
    case legalAcceptance(needsTos: Bool, needsPrivacy: Bool, tosVersion: String?, privacyVersion: String?, tosMessage: String?, privacyMessage: String?)
}

public enum ComplianceNonBlockingState: Equatable, Sendable {
    case forceUpdateGrace(targetVersion: String, daysRemaining: Int, appStoreUrl: String, message: String?)
    case softUpdateReminder(targetVersion: String, appStoreUrl: String, message: String?)
}
```

---

#### File: `Sources/WhatsThatDomain/VersionControl/VersionComparisonExtension.swift`

```swift
import Foundation

public extension String {
    /// Compares semantic versions. Returns true if self < other.
    /// Examples: "1.2.0".isVersionLessThan("1.10.0") → true
    ///           "2.0.0".isVersionLessThan("1.9.0") → false
    func isVersionLessThan(_ other: String) -> Bool {
        let v1Components = self.split(separator: ".").compactMap { Int($0) }
        let v2Components = other.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(v1Components.count, v2Components.count)
        let v1Padded = v1Components + Array(repeating: 0, count: maxLength - v1Components.count)
        let v2Padded = v2Components + Array(repeating: 0, count: maxLength - v2Components.count)

        for i in 0..<maxLength {
            if v1Padded[i] < v2Padded[i] { return true }
            if v1Padded[i] > v2Padded[i] { return false }
        }
        return false // Equal versions
    }
}
```

---

#### File: `Sources/WhatsThatDomain/VersionControl/AppConfigRepository.swift`

```swift
import Foundation

public protocol AppConfigRepository: Sendable {
    func fetchConfig() async throws -> AppConfigResponse
    func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws -> AcceptTermsResponse
}
```

---

#### File: `Sources/WhatsThatDomain/VersionControl/ComplianceUseCase.swift`

```swift
import Foundation

public actor ComplianceUseCase {
    private let repository: AppConfigRepository
    private let localStore: ComplianceLocalStore

    private var cachedConfig: AppConfigResponse?
    private var lastFetchTime: Date?
    private let stalenessThreshold: TimeInterval = 3600 // 1 hour

    public init(repository: AppConfigRepository, localStore: ComplianceLocalStore) {
        self.repository = repository
        self.localStore = localStore
    }

    // MARK: - Config Fetching

    public func fetchConfig(forceFresh: Bool = false) async throws -> AppConfigResponse {
        if !forceFresh, let cached = cachedConfig, let lastFetch = lastFetchTime {
            if Date().timeIntervalSince(lastFetch) < stalenessThreshold {
                return cached
            }
        }

        let config = try await repository.fetchConfig()
        cachedConfig = config
        lastFetchTime = Date()

        // Cache maintenance state for offline resilience
        await localStore.cacheMaintenanceState(
            CachedMaintenanceState(
                isEnabled: config.maintenance.enabled,
                message: config.maintenance.message
            )
        )

        return config
    }

    public func isConfigStale() -> Bool {
        guard let lastFetch = lastFetchTime else { return true }
        return Date().timeIntervalSince(lastFetch) >= stalenessThreshold
    }

    public func getCachedConfig() -> AppConfigResponse? {
        cachedConfig
    }

    public func clearCache() {
        cachedConfig = nil
        lastFetchTime = nil
    }

    // MARK: - Terms Acceptance

    public func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws -> AcceptTermsResponse {
        let response = try await repository.acceptTerms(tosVersion: tosVersion, privacyVersion: privacyVersion)

        // Refresh config to update user_status
        _ = try? await fetchConfig(forceFresh: true)

        return response
    }

    // MARK: - Blocking State Determination

    public func determineBlockingState(
        config: AppConfigResponse,
        userAppVersion: String
    ) async -> ComplianceBlockingState? {
        // Priority 1: Maintenance mode
        if config.maintenance.enabled {
            return .maintenance(message: config.maintenance.message)
        }

        // Priority 2: Below minimum supported version (immediate block)
        if userAppVersion.isVersionLessThan(config.app.minSupportedVersion) {
            return .forceUpdateImmediate(
                targetVersion: config.app.version,
                appStoreUrl: config.app.appStoreUrl
            )
        }

        // Priority 3: Check last_force_version with grace period
        if let lastForceVersion = config.app.lastForceVersion,
           userAppVersion.isVersionLessThan(lastForceVersion) {
            var state = await localStore.loadAppUpdateReminderState()

            // Mark force update seen (only sets if nil)
            if state.forceGracePeriodStartDate == nil {
                state.forceGracePeriodStartDate = Date()
                await localStore.saveAppUpdateReminderState(state)
            }

            if isForceGracePeriodExpired(state: state) {
                return .forceUpdateExpired(
                    targetVersion: config.app.version,
                    appStoreUrl: config.app.appStoreUrl,
                    message: config.app.message
                )
            }
        }

        // Priority 4: Legal acceptance required
        if let userStatus = config.userStatus,
           (userStatus.needsTosAcceptance || userStatus.needsPrivacyAcceptance) {
            return .legalAcceptance(
                needsTos: userStatus.needsTosAcceptance,
                needsPrivacy: userStatus.needsPrivacyAcceptance,
                tosVersion: config.tos.version,
                privacyVersion: config.privacy.version,
                tosMessage: config.tos.message,
                privacyMessage: config.privacy.message
            )
        }

        return nil
    }

    // MARK: - Non-Blocking State Determination

    public func determineNonBlockingState(
        config: AppConfigResponse,
        userAppVersion: String
    ) async -> ComplianceNonBlockingState? {
        // Force update within grace period
        if let lastForceVersion = config.app.lastForceVersion,
           userAppVersion.isVersionLessThan(lastForceVersion) {
            let state = await localStore.loadAppUpdateReminderState()
            if !isForceGracePeriodExpired(state: state),
               let startDate = state.forceGracePeriodStartDate {
                let daysRemaining = max(0, 7 - Int(Date().timeIntervalSince(startDate) / 86400))
                return .forceUpdateGrace(
                    targetVersion: config.app.version,
                    daysRemaining: daysRemaining,
                    appStoreUrl: config.app.appStoreUrl,
                    message: config.app.message
                )
            }
        }

        // Soft update reminder
        if config.app.appUpdateType == .soft,
           userAppVersion.isVersionLessThan(config.app.version) {
            var state = await localStore.loadAppUpdateReminderState()

            // Reset tracking for new version
            if state.softUpdateVersion != config.app.version {
                state.softUpdateVersion = config.app.version
                state.lastReminderDate = nil
                state.reminderCount = 0
                await localStore.saveAppUpdateReminderState(state)
            }

            if shouldShowSoftReminder(state: state) {
                return .softUpdateReminder(
                    targetVersion: config.app.version,
                    appStoreUrl: config.app.appStoreUrl,
                    message: config.app.message
                )
            }
        }

        return nil
    }

    public func markSoftReminderShown() async {
        var state = await localStore.loadAppUpdateReminderState()
        state.lastReminderDate = Date()
        state.reminderCount += 1
        await localStore.saveAppUpdateReminderState(state)
    }

    // MARK: - Offline Handling

    public func getMaintenanceStateForOffline() async -> CachedMaintenanceState? {
        let cached = await localStore.loadCachedMaintenanceState()
        guard let cached, cached.isValid, cached.isEnabled else {
            return nil
        }
        return cached
    }

    // MARK: - Private Helpers

    private func isForceGracePeriodExpired(state: AppUpdateReminderState) -> Bool {
        guard let startDate = state.forceGracePeriodStartDate else {
            return false
        }
        let gracePeriodSeconds: TimeInterval = 7 * 24 * 60 * 60
        return Date().timeIntervalSince(startDate) > gracePeriodSeconds
    }

    private func shouldShowSoftReminder(state: AppUpdateReminderState) -> Bool {
        guard state.reminderCount < 3 else { return false }
        guard let lastReminder = state.lastReminderDate else { return true }

        let daysSinceLastReminder = Int(Date().timeIntervalSince(lastReminder) / 86400)

        switch state.reminderCount {
        case 0: return true // Day 1
        case 1: return daysSinceLastReminder >= 2 // Day 3
        case 2: return daysSinceLastReminder >= 4 // Day 7
        default: return false
        }
    }
}
```

---

#### File: `Sources/WhatsThatDomain/VersionControl/ComplianceLocalStore.swift`

```swift
import Foundation

public protocol ComplianceLocalStore: Sendable {
    func loadAppUpdateReminderState() async -> AppUpdateReminderState
    func saveAppUpdateReminderState(_ state: AppUpdateReminderState) async
    func loadCachedMaintenanceState() async -> CachedMaintenanceState?
    func cacheMaintenanceState(_ state: CachedMaintenanceState) async
    func clearAll() async
}
```

---

### 2.2 Data Layer - Repository Implementation

#### File: `Sources/WhatsThatData/Repositories/Compliance/SupabaseAppConfigRepository.swift`

```swift
import Foundation
import WhatsThatDomain

#if USE_REMOTE_DEPS && canImport(Supabase)
import Supabase

public final class SupabaseAppConfigRepository: AppConfigRepository, @unchecked Sendable {
    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    public func fetchConfig() async throws -> AppConfigResponse {
        let response: AppConfigResponse = try await client.rpc("get_app_config").execute().value
        return response
    }

    public func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws -> AcceptTermsResponse {
        struct Params: Encodable {
            let tos_version: String?
            let privacy_version: String?
        }

        let response: AcceptTermsResponse = try await client
            .rpc("accept_terms", params: Params(tos_version: tosVersion, privacy_version: privacyVersion))
            .execute()
            .value

        return response
    }
}
#endif
```

---

#### File: `Sources/WhatsThatData/Repositories/Compliance/UserDefaultsComplianceLocalStore.swift`

```swift
import Foundation
import WhatsThatDomain

public actor UserDefaultsComplianceLocalStore: ComplianceLocalStore {
    private let userDefaults: UserDefaults
    private let appUpdateReminderKey = "com.whatsthat.app_update_reminder_state"
    private let maintenanceCacheKey = "com.whatsthat.cached_maintenance_state"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadAppUpdateReminderState() async -> AppUpdateReminderState {
        guard let data = userDefaults.data(forKey: appUpdateReminderKey),
              let state = try? decoder.decode(AppUpdateReminderState.self, from: data) else {
            return AppUpdateReminderState()
        }
        return state
    }

    public func saveAppUpdateReminderState(_ state: AppUpdateReminderState) async {
        guard let data = try? encoder.encode(state) else { return }
        userDefaults.set(data, forKey: appUpdateReminderKey)
    }

    public func loadCachedMaintenanceState() async -> CachedMaintenanceState? {
        guard let data = userDefaults.data(forKey: maintenanceCacheKey),
              let state = try? decoder.decode(CachedMaintenanceState.self, from: data) else {
            return nil
        }
        return state
    }

    public func cacheMaintenanceState(_ state: CachedMaintenanceState) async {
        guard let data = try? encoder.encode(state) else { return }
        userDefaults.set(data, forKey: maintenanceCacheKey)
    }

    public func clearAll() async {
        userDefaults.removeObject(forKey: appUpdateReminderKey)
        // Note: Don't clear maintenance cache on sign-out (system-wide, not user-specific)
    }
}
```

---

### 2.3 Shared Layer - Bundle Extension

#### File: `Sources/WhatsThatShared/Extensions/Bundle+AppVersion.swift`

```swift
import Foundation

public extension Bundle {
    /// The app's marketing version (CFBundleShortVersionString), e.g., "1.2.0"
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// The app's build number (CFBundleVersion), e.g., "42"
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
```

---

### 2.4 Presentation Layer - UI Components

#### File: `Sources/WhatsThatPresentation/Features/Compliance/ComplianceOverlayView.swift`

```swift
import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct ComplianceOverlayView: View {
    let blockingState: ComplianceBlockingState
    let onAcceptTerms: (String?, String?) async -> Result<Void, Error>
    let onSignOut: () async -> Void
    let onOpenAppStore: (String) -> Void
    let onCheckAgain: () async -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            switch blockingState {
            case .maintenance(let message):
                MaintenanceBlockingView(
                    message: message,
                    onCheckAgain: onCheckAgain
                )
            case .forceUpdateImmediate(let targetVersion, let appStoreUrl):
                ForceUpdateBlockingView(
                    targetVersion: targetVersion,
                    message: nil,
                    isGraceExpired: false,
                    onOpenAppStore: { onOpenAppStore(appStoreUrl) },
                    onCheckAgain: onCheckAgain
                )
            case .forceUpdateExpired(let targetVersion, let appStoreUrl, let message):
                ForceUpdateBlockingView(
                    targetVersion: targetVersion,
                    message: message,
                    isGraceExpired: true,
                    onOpenAppStore: { onOpenAppStore(appStoreUrl) },
                    onCheckAgain: onCheckAgain
                )
            case .legalAcceptance(let needsTos, let needsPrivacy, let tosVersion, let privacyVersion, let tosMessage, let privacyMessage):
                LegalAcceptanceModalView(
                    needsTos: needsTos,
                    needsPrivacy: needsPrivacy,
                    tosVersion: tosVersion,
                    privacyVersion: privacyVersion,
                    tosMessage: tosMessage,
                    privacyMessage: privacyMessage,
                    onAccept: onAcceptTerms,
                    onSignOut: onSignOut
                )
            }
        }
        .transition(.opacity)
        .zIndex(1000)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }
}
```

---

#### File: `Sources/WhatsThatPresentation/Features/Compliance/LegalAcceptanceModalView.swift`

```swift
import SwiftUI
import WhatsThatDomain
import WhatsThatShared

struct LegalAcceptanceModalView: View {
    let needsTos: Bool
    let needsPrivacy: Bool
    let tosVersion: String?
    let privacyVersion: String?
    let tosMessage: String?
    let privacyMessage: String?
    let onAccept: (String?, String?) async -> Result<Void, Error>
    let onSignOut: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isChecked = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSignOutConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.large) {
                // Header
                VStack(spacing: BrandSpacing.small) {
                    Text("📜")
                        .font(.system(size: 48))
                    Text("Terms Update Required")
                        .font(.adaptiveSystem(size: 24, weight: .bold))
                        .foregroundStyle(titleColor)
                }
                .padding(.top, BrandSpacing.large)

                // Document Cards
                VStack(spacing: BrandSpacing.medium) {
                    if needsTos, let version = tosVersion {
                        DocumentCard(
                            title: "Terms of Service",
                            version: version,
                            message: tosMessage,
                            url: AppConfiguration.termsAndConditionsURL
                        )
                    }

                    if needsPrivacy, let version = privacyVersion {
                        DocumentCard(
                            title: "Privacy Policy",
                            version: version,
                            message: privacyMessage,
                            url: AppConfiguration.privacyPolicyURL
                        )
                    }
                }

                // Checkbox
                Toggle(isOn: $isChecked) {
                    Text(checkboxText)
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundStyle(bodyColor)
                }
                .toggleStyle(SwitchToggleStyle(tint: primaryColor))
                .disabled(isSubmitting)

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                // Accept button
                BrandPrimaryButton(
                    title: isSubmitting ? "Accepting..." : "Accept and Continue",
                    isLoading: isSubmitting
                ) {
                    Task { await handleAccept() }
                }
                .disabled(!isChecked || isSubmitting)

                // Sign Out button
                Button("Sign Out") {
                    showSignOutConfirmation = true
                }
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))
                .disabled(isSubmitting)

                Spacer(minLength: BrandSpacing.large)
            }
            .padding(.horizontal, BrandSpacing.large)
        }
        .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task { await onSignOut() }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private var checkboxText: String {
        if needsTos && needsPrivacy {
            return "I have read and agree to the updated Terms of Service and Privacy Policy"
        } else if needsTos {
            return "I have read and agree to the updated Terms of Service"
        } else {
            return "I have read and agree to the updated Privacy Policy"
        }
    }

    private func handleAccept() async {
        isSubmitting = true
        errorMessage = nil

        let tosToAccept = needsTos ? tosVersion : nil
        let privacyToAccept = needsPrivacy ? privacyVersion : nil

        // Retry up to 3 times
        for attempt in 1...3 {
            let result = await onAccept(tosToAccept, privacyToAccept)
            switch result {
            case .success:
                return // Success - view will be dismissed by parent
            case .failure:
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        // All attempts failed
        await MainActor.run {
            isSubmitting = false
            errorMessage = "Network error. Please check your connection and try again."
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var primaryColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }
}

// MARK: - Document Card

private struct DocumentCard: View {
    let title: String
    let version: String
    let message: String?
    let url: URL

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.small) {
            HStack {
                Text("\(title) v\(version)")
                    .font(.adaptiveSystem(size: 16, weight: .semibold))
                    .foregroundStyle(titleColor)
                Spacer()
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(.adaptiveSystem(size: 14))
                    .foregroundStyle(bodyColor)
            }

            Button {
                openURL(url)
            } label: {
                HStack(spacing: 4) {
                    Text("View Full Document")
                        .font(.adaptiveSystem(size: 14, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(primaryColor)
            }
        }
        .padding(BrandSpacing.medium)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var primaryColor: Color {
        colorScheme == .dark ? BrandColors.Dark.primaryAction : BrandColors.Light.primaryAction
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
}
```

---

#### File: `Sources/WhatsThatPresentation/Features/Compliance/MaintenanceBlockingView.swift`

```swift
import SwiftUI
import WhatsThatShared

struct MaintenanceBlockingView: View {
    let message: String?
    let onCheckAgain: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isChecking = false
    @State private var lastCheckTime: Date?
    private let checkCooldown: TimeInterval = 60

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Spacer()

            Text("🔧")
                .font(.system(size: 64))

            Text("Under Maintenance")
                .font(.adaptiveSystem(size: 28, weight: .bold))
                .foregroundStyle(titleColor)

            Text("We are currently undergoing maintenance. Please check back later.")
                .font(.adaptiveSystem(size: 16))
                .foregroundStyle(bodyColor)
                .multilineTextAlignment(.center)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.adaptiveSystem(size: 14))
                    .foregroundStyle(bodyColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(BrandSpacing.medium)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()

            BrandSecondaryButton(
                title: isChecking ? "Checking..." : "Check Again",
                isLoading: isChecking
            ) {
                Task { await handleCheckAgain() }
            }
            .disabled(isChecking)

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.large)
        .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
    }

    private func handleCheckAgain() async {
        await MainActor.run { isChecking = true }

        let now = Date()
        let canCheck = lastCheckTime == nil || now.timeIntervalSince(lastCheckTime!) >= checkCooldown

        if canCheck {
            await MainActor.run { lastCheckTime = now }
            await onCheckAgain()
        } else {
            try? await Task.sleep(for: .seconds(1))
        }

        await MainActor.run { isChecking = false }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
}
```

---

#### File: `Sources/WhatsThatPresentation/Features/Compliance/ForceUpdateBlockingView.swift`

```swift
import SwiftUI
import WhatsThatShared

struct ForceUpdateBlockingView: View {
    let targetVersion: String
    let message: String?
    let isGraceExpired: Bool
    let onOpenAppStore: () -> Void
    let onCheckAgain: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isChecking = false
    @State private var lastCheckTime: Date?
    private let checkCooldown: TimeInterval = 60

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Spacer()

            Text("🔒")
                .font(.system(size: 64))

            Text("Update Required")
                .font(.adaptiveSystem(size: 28, weight: .bold))
                .foregroundStyle(titleColor)

            Text("A required update must be installed to continue using What's That?")
                .font(.adaptiveSystem(size: 16))
                .foregroundStyle(bodyColor)
                .multilineTextAlignment(.center)

            Text("Version \(targetVersion)")
                .font(.adaptiveSystem(size: 14, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))

            if let message, !message.isEmpty {
                Text(message)
                    .font(.adaptiveSystem(size: 14))
                    .foregroundStyle(bodyColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(BrandSpacing.medium)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()

            VStack(spacing: BrandSpacing.medium) {
                BrandPrimaryButton(title: "Update Now") {
                    onOpenAppStore()
                }

                BrandSecondaryButton(
                    title: isChecking ? "Checking..." : "Check Again",
                    isLoading: isChecking
                ) {
                    Task { await handleCheckAgain() }
                }
                .disabled(isChecking)
            }

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.large)
        .frame(maxWidth: UIDevice.isIPad ? 500 : .infinity)
    }

    private func handleCheckAgain() async {
        await MainActor.run { isChecking = true }

        let now = Date()
        let canCheck = lastCheckTime == nil || now.timeIntervalSince(lastCheckTime!) >= checkCooldown

        if canCheck {
            await MainActor.run { lastCheckTime = now }
            await onCheckAgain()
        } else {
            try? await Task.sleep(for: .seconds(1))
        }

        await MainActor.run { isChecking = false }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
}
```

---

#### File: `Sources/WhatsThatPresentation/Features/Compliance/SoftUpdatePromptView.swift`

```swift
import SwiftUI
import WhatsThatShared

struct SoftUpdatePromptView: View {
    let targetVersion: String
    let message: String?
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Text("🎉")
                .font(.system(size: 48))

            Text("New Version Available!")
                .font(.adaptiveSystem(size: 24, weight: .bold))
                .foregroundStyle(titleColor)

            Text("Version \(targetVersion)")
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))

            if let message, !message.isEmpty {
                Text(message)
                    .font(.adaptiveSystem(size: 14))
                    .foregroundStyle(bodyColor)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: BrandSpacing.small) {
                BrandPrimaryButton(title: "Update Now") {
                    onUpdate()
                }

                Button("Maybe Later") {
                    onDismiss()
                }
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))
            }
        }
        .padding(BrandSpacing.large)
        .frame(maxWidth: UIDevice.isIPad ? 400 : .infinity)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }
}
```

---

#### File: `Sources/WhatsThatPresentation/Features/Compliance/ForceUpdateGracePromptView.swift`

```swift
import SwiftUI
import WhatsThatShared

struct ForceUpdateGracePromptView: View {
    let targetVersion: String
    let daysRemaining: Int
    let message: String?
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: BrandSpacing.large) {
            Text("⚠️")
                .font(.system(size: 48))

            Text("Required Update")
                .font(.adaptiveSystem(size: 24, weight: .bold))
                .foregroundStyle(warningColor)

            Text("Version \(targetVersion) is required")
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor)

            Text("You have \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") to update before this becomes mandatory.")
                .font(.adaptiveSystem(size: 14))
                .foregroundStyle(bodyColor.opacity(0.8))
                .multilineTextAlignment(.center)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.adaptiveSystem(size: 14))
                    .foregroundStyle(bodyColor)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: BrandSpacing.small) {
                BrandPrimaryButton(title: "Update Now") {
                    onUpdate()
                }

                Button("Remind Me Later") {
                    onDismiss()
                }
                .font(.adaptiveSystem(size: 16, weight: .medium))
                .foregroundStyle(bodyColor.opacity(0.7))
            }
        }
        .padding(BrandSpacing.large)
        .frame(maxWidth: UIDevice.isIPad ? 400 : .infinity)
    }

    private var warningColor: Color {
        Color.orange
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }
}
```

---

## 3. Existing Files to Modify

### 3.1 AppDependencyContainer.swift

**File:** `Sources/WhatsThatApp/DependencyInjection/AppDependencyContainer.swift`

**Changes:**

1. **Add new properties (after line 31):**

```swift
// Add after: private let creditBalanceStore: CreditBalanceStore
private let appConfigRepository: AppConfigRepository
public let complianceLocalStore: ComplianceLocalStore
public let complianceUseCase: ComplianceUseCase
```

2. **Update init parameters (add after line 48):**

```swift
// Add to init parameters after: locationService: DiscoveryLocationService
appConfigRepository: AppConfigRepository,
complianceLocalStore: ComplianceLocalStore
```

3. **Update init body (add after line 65):**

```swift
self.appConfigRepository = appConfigRepository
self.complianceLocalStore = complianceLocalStore
self.complianceUseCase = ComplianceUseCase(
    repository: appConfigRepository,
    localStore: complianceLocalStore
)
```

4. **Update `live()` function (after line 192, before return statement):**

```swift
let appConfigRepository = SupabaseAppConfigRepository(client: client)
let complianceLocalStore = UserDefaultsComplianceLocalStore()
```

5. **Update return statement in `live()` (around line 216):**

```swift
// Add to AppDependencyContainer init call:
appConfigRepository: appConfigRepository,
complianceLocalStore: complianceLocalStore
```

6. **Add compliance data clearing to `clearAllUserData()` (after line 422):**

```swift
// Add before the closing brace of clearAllUserData():
await complianceUseCase.clearCache()
await complianceLocalStore.clearAll()
```

---

### 3.2 AppRootViewModel.swift

**File:** `Sources/WhatsThatPresentation/App/AppRootViewModel.swift`

**Changes:**

1. **Add new published properties (after line 9):**

```swift
@Published public private(set) var complianceBlockingState: ComplianceBlockingState?
@Published public private(set) var complianceNonBlockingState: ComplianceNonBlockingState?
@Published public private(set) var pendingLegalAcceptance: Bool = false
```

2. **Add new dependencies (after line 15):**

```swift
private let complianceUseCase: ComplianceUseCase
private let userAppVersion: String
```

3. **Update init parameters (after line 26):**

```swift
// Add to init:
complianceUseCase: ComplianceUseCase,
userAppVersion: String = Bundle.main.appVersion
```

4. **Assign in init body (after line 32):**

```swift
self.complianceUseCase = complianceUseCase
self.userAppVersion = userAppVersion
```

5. **Add compliance check method (after line 228):**

```swift
// MARK: - Compliance

public func checkCompliance() async {
    do {
        let config = try await complianceUseCase.fetchConfig(forceFresh: true)
        await updateComplianceState(config: config)
    } catch {
        // Check for cached maintenance state on failure
        if let maintenanceState = await complianceUseCase.getMaintenanceStateForOffline() {
            await MainActor.run {
                self.complianceBlockingState = .maintenance(message: maintenanceState.message)
            }
        }
    }
}

public func refreshComplianceIfStale() async {
    guard await complianceUseCase.isConfigStale() else { return }
    await checkCompliance()
}

private func updateComplianceState(config: AppConfigResponse) async {
    let blockingState = await complianceUseCase.determineBlockingState(
        config: config,
        userAppVersion: userAppVersion
    )

    let nonBlockingState: ComplianceNonBlockingState?
    if blockingState == nil {
        nonBlockingState = await complianceUseCase.determineNonBlockingState(
            config: config,
            userAppVersion: userAppVersion
        )
    } else {
        nonBlockingState = nil
    }

    await MainActor.run {
        self.complianceBlockingState = blockingState
        self.complianceNonBlockingState = nonBlockingState

        // Set pending flag for legal acceptance (used for safe-screen deferral)
        if case .legalAcceptance = blockingState {
            self.pendingLegalAcceptance = true
        }
    }
}

public func acceptTerms(tosVersion: String?, privacyVersion: String?) async throws {
    _ = try await complianceUseCase.acceptTerms(tosVersion: tosVersion, privacyVersion: privacyVersion)

    // Refresh compliance state
    if let config = await complianceUseCase.getCachedConfig() {
        await updateComplianceState(config: config)
    }

    await MainActor.run {
        self.pendingLegalAcceptance = false
    }
}

public func dismissSoftUpdateReminder() async {
    await complianceUseCase.markSoftReminderShown()
    await MainActor.run {
        self.complianceNonBlockingState = nil
    }
}
```

6. **Update `bootstrap()` method to include compliance check (after line 243):**

```swift
// Add after: updateFlow(session: session)
// Check compliance after session is established
if case .authenticated = session {
    Task {
        await checkCompliance()
    }
}
```

7. **Update `signOut()` to clear compliance state (in signOut method, after line 157):**

```swift
// Add before: updateFlow(session: .signedOut)
await MainActor.run {
    self.complianceBlockingState = nil
    self.complianceNonBlockingState = nil
    self.pendingLegalAcceptance = false
}
```

---

### 3.3 RootContentView.swift

**File:** `Sources/WhatsThatPresentation/App/RootContentView.swift`

**Changes:**

1. **Add state for tracking current screen safety (after line 17):**

```swift
@State private var currentScreenIsSafe: Bool = true
@State private var showSoftUpdateSheet: Bool = false
@State private var showForceGraceSheet: Bool = false
```

2. **Update `body` to wrap mainContent with compliance overlay (modify lines 119-126):**

Replace:

```swift
public var body: some View {
    ZStack {
        backgroundColor
            .ignoresSafeArea()

        mainContent
        passwordResetOverlay
    }
```

With:

```swift
public var body: some View {
    ZStack {
        backgroundColor
            .ignoresSafeArea()

        mainContent
        passwordResetOverlay
        complianceOverlay
    }
```

3. **Add compliance overlay computed property (after `passwordResetOverlay`, around line 477):**

```swift
@ViewBuilder
private var complianceOverlay: some View {
    // Only show blocking overlays when in main state and on safe screen
    if case .main = viewModel.flowState,
       let blockingState = viewModel.complianceBlockingState {
        // Legal acceptance is deferred to safe screens
        if case .legalAcceptance = blockingState {
            if currentScreenIsSafe {
                ComplianceOverlayView(
                    blockingState: blockingState,
                    onAcceptTerms: { tosVersion, privacyVersion in
                        do {
                            try await viewModel.acceptTerms(tosVersion: tosVersion, privacyVersion: privacyVersion)
                            return .success(())
                        } catch {
                            return .failure(error)
                        }
                    },
                    onSignOut: {
                        try? await viewModel.signOut()
                    },
                    onOpenAppStore: { url in
                        if let url = URL(string: url) {
                            UIApplication.shared.open(url)
                        }
                    },
                    onCheckAgain: {
                        await viewModel.checkCompliance()
                    }
                )
            }
        } else {
            // Maintenance and force update block immediately
            ComplianceOverlayView(
                blockingState: blockingState,
                onAcceptTerms: { _, _ in .failure(NSError()) },
                onSignOut: { try? await viewModel.signOut() },
                onOpenAppStore: { url in
                    if let url = URL(string: url) {
                        UIApplication.shared.open(url)
                    }
                },
                onCheckAgain: {
                    await viewModel.checkCompliance()
                }
            )
        }
    }
}
```

4. **Add soft/force grace sheet modifiers (after line 203, inside the settings sheet block):**

```swift
.sheet(isPresented: $showSoftUpdateSheet) {
    if case .softUpdateReminder(let version, let url, let message) = viewModel.complianceNonBlockingState {
        SoftUpdatePromptView(
            targetVersion: version,
            message: message,
            onUpdate: {
                if let appStoreUrl = URL(string: url) {
                    UIApplication.shared.open(appStoreUrl)
                }
                showSoftUpdateSheet = false
            },
            onDismiss: {
                Task { await viewModel.dismissSoftUpdateReminder() }
                showSoftUpdateSheet = false
            }
        )
        .presentationDetents([.medium])
    }
}
.sheet(isPresented: $showForceGraceSheet) {
    if case .forceUpdateGrace(let version, let days, let url, let message) = viewModel.complianceNonBlockingState {
        ForceUpdateGracePromptView(
            targetVersion: version,
            daysRemaining: days,
            message: message,
            onUpdate: {
                if let appStoreUrl = URL(string: url) {
                    UIApplication.shared.open(appStoreUrl)
                }
                showForceGraceSheet = false
            },
            onDismiss: {
                showForceGraceSheet = false
            }
        )
        .presentationDetents([.medium])
    }
}
```

5. **Add onChange handler for non-blocking state (after line 282):**

```swift
.onChange(of: viewModel.complianceNonBlockingState) { _, newValue in
    guard currentScreenIsSafe else { return }
    switch newValue {
    case .softUpdateReminder:
        showSoftUpdateSheet = true
    case .forceUpdateGrace:
        showForceGraceSheet = true
    case .none:
        break
    }
}
```

6. **Add scene phase handler for staleness check (modify existing .onChange(of: scenePhase) around line 262):**

Add inside the `.active` case:

```swift
// Refresh compliance if stale
Task { await viewModel.refreshComplianceIfStale() }
```

---

### 3.4 MainTabView.swift

**File:** `Sources/WhatsThatPresentation/App/MainTabView.swift`

**Changes:**

1. **Add callback for screen safety tracking (after line 47):**

```swift
private let onScreenSafetyChanged: ((Bool) -> Void)?
```

2. **Update init to accept callback (add parameter after line 59):**

```swift
onScreenSafetyChanged: ((Bool) -> Void)? = nil
```

3. **Assign in init body (after line 70):**

```swift
self.onScreenSafetyChanged = onScreenSafetyChanged
```

4. **Add screen safety tracking (in handleTabChange method, around line 263):**

Add at the start of `handleTabChange`:

```swift
// Track screen safety for compliance overlay deferral
let isSafeScreen = (tab == .discoveries || tab == .audioGuides)
onScreenSafetyChanged?(isSafeScreen)
```

5. **Track overlay state for safety (in updateOverlayVisibility, around line 433):**

Modify to also report safety:

```swift
private func updateOverlayVisibility(for tab: Tab, phase: DiscoveryCreationPhase) {
    guard activeOverlayTab == tab else { return }
    if !shouldShowOverlay(for: phase) {
        activeOverlayTab = nil
        // Screen becomes safe when overlay dismissed on discoveries/audioGuides
        if selectedTab == .discoveries || selectedTab == .audioGuides {
            onScreenSafetyChanged?(true)
        }
    } else {
        // Screen is unsafe when overlay is active
        onScreenSafetyChanged?(false)
    }
}
```

---

### 3.5 Update RootContentView MainTabView call

**File:** `Sources/WhatsThatPresentation/App/RootContentView.swift`

**Changes:** Update the MainTabView initialization (around line 421) to pass the safety callback:

```swift
MainTabView(
    storeObserver: storeObserver,
    deletionUseCase: deletionUseCase,
    cameraViewModel: makeCreationViewModel(.camera),
    uploadViewModel: makeCreationViewModel(.upload),
    audioServices: audioServicesContainer,
    initialTab: mainTabDestination,
    onSignOut: {
        Task { try? await viewModel.signOut() }
    },
    onSettings: {
        isSettingsPresented = true
    },
    isSettingsPresented: $isSettingsPresented,
    makeCreditsViewModel: makeCreditsViewModel,
    onScreenSafetyChanged: { isSafe in
        currentScreenIsSafe = isSafe
    }
)
```

---

### 3.6 SignUpForm.swift - Add Terms Acceptance on Signup

**File:** `Sources/WhatsThatPresentation/Features/Authentication/SignUpForm.swift`

The existing SignUpForm already has terms agreement checkbox. The backend `accept_terms` call needs to happen after successful signup. This is handled in **AppRootViewModel**.

**Changes to AppRootViewModel.signUp() method (around line 95):**

After successful signup, the compliance check will automatically trigger and record acceptance since the user just agreed to terms. However, for explicit recording during signup:

Add a new parameter to track versions being agreed to, and call `accept_terms` after successful signup:

```swift
// In AppRootViewModel, modify or add after signUp succeeds:
// After the user is authenticated, immediately accept terms
Task {
    // The compliance fetch will get current versions
    // Then we call acceptTerms with those versions
    do {
        let config = try await complianceUseCase.fetchConfig()
        _ = try await complianceUseCase.acceptTerms(
            tosVersion: config.tos.version,
            privacyVersion: config.privacy.version
        )
    } catch {
        // Failure is acceptable - user will see modal on first safe screen
    }
}
```

---

## 4. Potential Issues & Considerations

### 4.1 Critical Issues to Address

1. **Screen Safety Tracking Complexity**

   - **Issue:** The current `MainTabView` doesn't expose which screen is active to parent views
   - **Solution:** Added `onScreenSafetyChanged` callback, but need to ensure ALL unsafe screens (Camera fullscreen cover, detail view, paywall) properly report unsafe state
   - **Risk:** If missed, legal modal could appear during recording
2. **ZStack vs Sheet for Legal Modal**

   - **Issue:** Plan specifies ZStack overlay to avoid `.sheet` conflicts with `.fullScreenCover`
   - **Solution:** Implemented as ZStack overlay in `RootContentView`
   - **Verify:** Test that legal modal appears above camera fullScreenCover
3. **Supabase RPC Date Decoding**

   - **Issue:** `released_at` comes as ISO8601 string from PostgreSQL
   - **Solution:** Ensure `SupabaseClientFactory` uses ISO8601 date decoding strategy (already configured at line 33-37)
   - **Verify:** Test date parsing in `VersionInfo` and `AppVersionInfo`
4. **Race Condition on Signup**

   - **Issue:** If `accept_terms` fails after signup, user is authenticated but hasn't accepted
   - **Solution:** This is handled gracefully - user will see legal modal on first safe screen
   - **Document:** This edge case in deployment guide

### 4.2 Testing Considerations

1. **Version Comparison Edge Cases**

   - Test: "1.10.0" vs "1.9.0" (semantic comparison)
   - Test: "1.0" vs "1.0.0" (padding)
   - Test: Empty/malformed versions
2. **Grace Period Persistence**

   - Test: Force grace period does NOT reset on new force version
   - Test: Grace period survives app restart
   - Test: Grace period clears when user updates app
3. **Offline Behavior**

   - Test: Maintenance cache survives offline period
   - Test: Legal modal doesn't appear when offline (fail-open)
   - Test: Config refresh works when coming back online
4. **Signup Flow**

   - Test: New user signup records acceptance automatically
   - Test: Social auth (Google/Apple) records acceptance
   - Test: Signup failure doesn't leave orphan acceptance records

### 4.3 Migration Checklist

Before deploying:

1. [ ] Run database migration on **development** Supabase first
2. [ ] Test all RPC functions in SQL editor
3. [ ] Deploy iOS app to TestFlight
4. [ ] Verify compliance flow works end-to-end
5. [ ] Run existing user backfill script
6. [ ] Deploy to **production** Supabase
7. [ ] Release iOS app update

### 4.4 Files Not Modified (Intentionally)

- **AppDelegate.swift** - No changes needed; push notifications unaffected
- **WhatsThatIOSApp.swift** - Entry point unchanged; DI flows through AppDependencyContainer
- **SettingsView.swift** - No direct compliance UI in settings (handled at root level)
- **AuthenticationFlowView.swift** - Terms agreement already exists in SignUpForm

---

## 5. Testing Checklist

### Unit Tests

- [ ] `String.isVersionLessThan()` - semantic version comparison
- [ ] `AppUpdateReminderState` - reminder schedule logic (1/3/7 days)
- [ ] `isForceGracePeriodExpired()` - grace period calculation
- [ ] `CachedMaintenanceState.isValid` - 3-hour validity check

### Integration Tests

- [ ] `SupabaseAppConfigRepository.fetchConfig()` - RPC response parsing
- [ ] `SupabaseAppConfigRepository.acceptTerms()` - RPC call and response
- [ ] `ComplianceUseCase.determineBlockingState()` - all priority levels
- [ ] `UserDefaultsComplianceLocalStore` - persistence round-trip

### Manual Tests

- [ ] Fresh install → no legal modal (new user accepts at signup)
- [ ] Existing user → sees legal modal after ToS update
- [ ] Legal modal → checkbox required → accept button enabled
- [ ] Legal modal → accept → retries 3x on failure → shows error
- [ ] Legal modal → sign out → returns to login
- [ ] Onboarding → legal modal deferred until main app
- [ ] Camera active → legal modal deferred
- [ ] Navigate to Discoveries → legal modal appears
- [ ] Maintenance mode → blocks all screens immediately
- [ ] Force update (< min_supported) → immediate block
- [ ] Force update (grace period) → dismissible warning
- [ ] Force update (grace expired) → blocking
- [ ] Soft update → reminder at day 1/3/7
- [ ] Offline + no cache → proceeds normally (fail-open)
- [ ] Offline + maintenance cache valid → shows maintenance
- [ ] App version update → clears force grace period
- [ ] Check Again button → rate limited to 1 min

---

## Summary

This implementation requires:

- **1 SQL migration file** with 8 sections
- **14 new Swift files** across Domain, Data, Shared, and Presentation layers
- **5 existing files modified** (AppDependencyContainer, AppRootViewModel, RootContentView, MainTabView, SignUpForm integration)

Total estimated new code: ~1,200 lines of Swift

The architecture follows existing patterns in the codebase:

- Actor-based repositories matching `UserDefaultsOnboardingRepository`
- Use cases matching `AuthUseCase` pattern
- ZStack overlays matching `passwordResetOverlay` pattern
- Sheet presentations matching existing Settings modals
