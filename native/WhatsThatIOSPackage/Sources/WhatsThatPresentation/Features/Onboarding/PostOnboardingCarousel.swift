import SwiftUI
import UIKit
import OSLog
import CoreLocation
import WhatsThatShared
import WhatsThatDomain

struct PostOnboardingCarousel: View {
    enum SlideKind {
        case overview
        case ipopPreferences
        case voicePicker
        case locationPermission
        case actions
    }

    struct Slide: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let imageName: String?
        let kind: SlideKind
    }

    let onComplete: () -> Void
    let onLaunchCamera: () -> Void
    let onLaunchUpload: () -> Void
    @StateObject private var voicePickerViewModel: VoicePickerViewModel
    @StateObject private var ipopPreferencesViewModel: IPoPPreferencesViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var index: Int = 0
    @StateObject private var permissionsCoordinator = OnboardingPermissionsCoordinator()
    @State private var isRequestingLocation = false
    @State private var showLocationSettingsAlert = false
    private let logger = Logger(subsystem: "com.whatsthat.onboarding", category: "PostOnboardingCarousel")

    init(
        onComplete: @escaping () -> Void,
        onLaunchCamera: @escaping () -> Void,
        onLaunchUpload: @escaping () -> Void,
        loadVoiceoverPreferences: @escaping () async -> VoiceoverPreferences,
        saveVoiceoverPreferences: @escaping (VoiceoverPreferences) async -> Void,
        fetchVoiceOptions: @escaping () async -> [VoiceModelOption],
        fetchVoiceSampleURL: @escaping (String) async -> URL?,
        loadIPoPPreferences: @escaping () async -> IPoPPreferences?,
        saveIPoPPreferences: @escaping (IPoPPreferences) async -> Void
    ) {
        self.onComplete = onComplete
        self.onLaunchCamera = onLaunchCamera
        self.onLaunchUpload = onLaunchUpload
        _voicePickerViewModel = StateObject(
            wrappedValue: VoicePickerViewModel(
                loadVoiceoverPreferences: loadVoiceoverPreferences,
                saveVoiceoverPreferences: saveVoiceoverPreferences,
                fetchVoiceOptions: fetchVoiceOptions,
                fetchVoiceSampleURL: fetchVoiceSampleURL
            )
        )
        _ipopPreferencesViewModel = StateObject(
            wrappedValue: IPoPPreferencesViewModel(
                loadPreferences: loadIPoPPreferences,
                savePreferences: saveIPoPPreferences
            )
        )
    }

    private let slides: [Slide] = [
        Slide(
            title: "Welcome aboard!",
            message: "You’ve got 3 free credits. Each credit explains one photo with quick, personalized insights.",
            imageName: "post1",
            kind: .overview
        ),
        Slide(
            title: "Snap and get answers.",
            message: "Point your camera and get instant explanations tailored to what you care about.",
            imageName: "post2",
            kind: .overview
        ),
        Slide(
            title: "Choose your narrator.",
            message: "Select the voice you like best. You can change anytime.",
            imageName: nil,
            kind: .voicePicker
        ),
        Slide(
            title: "Content Preferences",
            message: "Put these in the order that matters to you. We’ll shape our answers based on your preferences.",
            imageName: nil,
            kind: .ipopPreferences
        ),
        Slide(
            title: "Unlock local insights.",
            message: "With location permissions, discoveries will be attuned to where you are. Used only to improve your experience—never sold.",
            imageName: "post3",
            kind: .locationPermission
        ),
        Slide(
            title: "Make your first discovery.",
            message: "Use your free credits now—take a picture or use a photo from your gallery.",
            imageName: "post4",
            kind: .actions
        )
    ]

    var body: some View {
        bodyContent
            .task {
                await ipopPreferencesViewModel.ensureLoaded()
                await voicePickerViewModel.prepareForOnboardingPrefetch()
            }
    }

    @ViewBuilder
    private var bodyContent: some View {
        coreView
            .onChange(of: index) { oldValue, newValue in
                handleSlideTransition(from: oldValue, to: newValue)
            }
            .onChange(of: permissionsCoordinator.locationStatus) { _, newStatus in
                guard isRequestingLocation else { return }
                evaluateLocationStatus(for: newStatus)
            }
    }

    private var coreView: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let topInset: CGFloat = 0
            let bottomInset = proxy.safeAreaInsets.bottom
            content(width: width, topInset: topInset, bottomInset: bottomInset)
                .frame(width: width, height: proxy.size.height)
        }
        .alert("Location Access", isPresented: $showLocationSettingsAlert) {
            Button("Not Now", role: .cancel) {
                isRequestingLocation = false
            }
            Button("Open Settings") {
                isRequestingLocation = false
                openAppSettings()
            }
        } message: {
            Text("For the best experience with location-based features, please enable location access in your device settings.")
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        TabView(selection: selectionBinding) {
            ForEach(slides.indices, id: \.self) { idx in
                switch slides[idx].kind {
                case .ipopPreferences:
                    OnboardingIPoPSlide(
                        title: slides[idx].title,
                        message: slides[idx].message,
                        titleColor: titleColor,
                        bodyColor: bodyColor,
                        containerWidth: width,
                        topInset: topInset,
                        viewModel: ipopPreferencesViewModel
                    )
                    .tag(idx)
                case .voicePicker:
                    OnboardingVoicePickerSlide(
                        title: slides[idx].title,
                        message: slides[idx].message,
                        titleColor: titleColor,
                        bodyColor: bodyColor,
                        containerWidth: width,
                        topInset: topInset,
                        viewModel: voicePickerViewModel
                    )
                    .tag(idx)
                default:
                    if let imageName = slides[idx].imageName {
                        OnboardingSlidePage(
                            imageName: imageName,
                            title: slides[idx].title,
                            message: slides[idx].message,
                            titleColor: titleColor,
                            bodyColor: bodyColor,
                            containerWidth: width,
                            topInset: topInset
                        )
                        .tag(idx)
                    }
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: width)
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            callToAction(bottomInset: bottomInset)
        }
    }

    private var selectionBinding: Binding<Int> {
        Binding(
            get: { index },
            set: { newValue in
                guard slides.indices.contains(index), slides.indices.contains(newValue) else { return }
                let currentKind = slides[index].kind
                if currentKind == .ipopPreferences,
                   newValue > index,
                   ipopPreferencesViewModel.persistedOrder == nil {
                    ipopPreferencesViewModel.errorMessage = "Please set your preferences in order to continue."
                    logger.debug("Blocked forward swipe via binding; persisted=nil, currentIdx=\(self.index), attempted=\(newValue)")
                    return
                }
                index = newValue
            }
        )
    }

    @ViewBuilder
    private func callToAction(bottomInset: CGFloat) -> some View {
        VStack(spacing: BrandSpacing.small) {
            OnboardingPageIndicators(count: slides.count, currentIndex: index)
            switch slides[index].kind {
            case .actions:
                HStack(spacing: BrandSpacing.medium) {
                    BrandPrimaryButton(title: "Camera") {
                        onLaunchCamera()
                    }
                    BrandSecondaryButton(title: "Gallery") {
                        onLaunchUpload()
                    }
                }
            case .ipopPreferences:
                VStack(spacing: BrandSpacing.small) {
                    let errorText = ipopPreferencesViewModel.errorMessage ?? " "
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(ipopPreferencesViewModel.errorMessage == nil ? Color.clear : Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.none, value: ipopPreferencesViewModel.errorMessage)
                    HStack(spacing: BrandSpacing.medium) {
                        BrandSecondaryButton(title: "Previous") {
                            goToPreviousSlide()
                        }
                        BrandPrimaryButton(title: ipopPreferencesViewModel.isSaving ? "Saving…" : "Save order") {
                            Task { await saveIPoPAndAdvance() }
                        }
                        .disabled(ipopPreferencesViewModel.isSaving)
                    }
                }
            case .overview, .locationPermission, .voicePicker:
                if index == 0 {
                    BrandPrimaryButton(title: "Next") {
                        goToNextSlide()
                    }
                } else {
                    HStack(spacing: BrandSpacing.medium) {
                        BrandSecondaryButton(title: "Previous") {
                            goToPreviousSlide()
                        }
                        BrandPrimaryButton(title: isLastSlide ? "Get Started" : "Next") {
                            goToNextSlide()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, BrandSpacing.large)
        .padding(.bottom, min(bottomInset, BrandSpacing.small))
        .background(backgroundColor)
    }

    private var isLastSlide: Bool {
        index == slides.count - 1
    }

    private func goToNextSlide() {
        guard index < slides.count - 1 else {
            onComplete()
            return
        }
        withAnimation {
            selectionBinding.wrappedValue = index + 1
        }
    }

    private func goToPreviousSlide() {
        guard index > 0 else { return }
        withAnimation { index -= 1 }
    }

    private func saveIPoPAndAdvance() async {
        let didSave = await ipopPreferencesViewModel.persistChanges()
        if didSave {
            goToNextSlide()
        }
    }

    private func handleSlideTransition(from oldIndex: Int, to newIndex: Int) {
        guard oldIndex != newIndex else { return }
        guard slides.indices.contains(oldIndex), slides.indices.contains(newIndex) else { return }
        if slides[newIndex].kind == .ipopPreferences {
            logger.debug("Navigating to IPoP slide idx=\(newIndex), persisted=\(ipopPreferencesViewModel.persistedOrder != nil)")
        }
        let leavingSlide = slides[oldIndex]
        if leavingSlide.kind == .locationPermission, newIndex > oldIndex {
            requestLocationPermissionIfNeeded()
        }
        if leavingSlide.kind == .voicePicker {
            voicePickerViewModel.stop()
        }
        
        let enteringSlide = slides[newIndex]
        if enteringSlide.kind == .voicePicker {
            Task {
                await voicePickerViewModel.autoplaySelectedVoice()
            }
        }
    }

    private func requestLocationPermissionIfNeeded() {
        switch permissionsCoordinator.locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted:
            showLocationSettingsAlert = true
        case .notDetermined:
            isRequestingLocation = true
            permissionsCoordinator.requestLocationPermission()
        @unknown default:
            break
        }
    }

    private func evaluateLocationStatus(for status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            isRequestingLocation = false
        case .denied, .restricted:
            isRequestingLocation = false
            showLocationSettingsAlert = true
        case .notDetermined:
            break
        @unknown default:
            isRequestingLocation = false
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : BrandColors.Light.accentText
    }

    private var bodyColor: Color {
        colorScheme == .dark ? BrandColors.Dark.bodyText : BrandColors.Light.bodyText
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? BrandColors.Dark.background : BrandColors.Light.background
    }
}
