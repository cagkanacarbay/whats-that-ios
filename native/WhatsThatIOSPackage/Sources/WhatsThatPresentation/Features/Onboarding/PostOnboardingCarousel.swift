import SwiftUI
import UIKit
import CoreLocation
import WhatsThatShared

struct PostOnboardingCarousel: View {
    enum SlideKind {
        case overview
        case locationPermission
        case actions
    }

    struct Slide: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let imageName: String
        let kind: SlideKind
    }

    let onComplete: () -> Void
    let onLaunchCamera: () -> Void
    let onLaunchUpload: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var index: Int = 0
    @State private var previousIndex: Int = 0
    @StateObject private var permissionsCoordinator = OnboardingPermissionsCoordinator()
    @State private var isRequestingLocation = false
    @State private var showLocationSettingsAlert = false

    private let slides: [Slide] = [
        Slide(
            title: "Welcome aboard!",
            message: "You’ve got 3 free credits. Each credit explains one photo with quick, personalized insights—no typing.",
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
            title: "Unlock local insights.",
            message: "With location permissions, discoveries include nearby places and meaningful context. Used only to improve results—never sold.",
            imageName: "post3",
            kind: .locationPermission
        ),
        Slide(
            title: "Make your first discovery.",
            message: "Use your 3 free credits now—try Camera take a picture or Upload a photo from your gallery.",
            imageName: "post4",
            kind: .actions
        )
    ]

    var body: some View {
        bodyContent
    }

    @ViewBuilder
    private var bodyContent: some View {
        if #available(iOS 17.0, *) {
            coreView
                .onChange(of: index) { oldValue, newValue in
                    handleSlideTransition(from: oldValue, to: newValue)
                    previousIndex = newValue
                }
                .onChange(of: permissionsCoordinator.locationStatus) { _, newStatus in
                    guard isRequestingLocation else { return }
                    evaluateLocationStatus(for: newStatus)
                }
        } else {
            coreView
                .onChange(of: index) { newValue in
                    handleSlideTransition(from: previousIndex, to: newValue)
                    previousIndex = newValue
                }
                .onChange(of: permissionsCoordinator.locationStatus) { newStatus in
                    guard isRequestingLocation else { return }
                    evaluateLocationStatus(for: newStatus)
                }
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
        TabView(selection: $index) {
            ForEach(slides.indices, id: \.self) { idx in
                OnboardingSlidePage(
                    imageName: slides[idx].imageName,
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
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: width)
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            callToAction(bottomInset: bottomInset)
        }
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
                    BrandSecondaryButton(title: "Upload") {
                        onLaunchUpload()
                    }
                }
            case .overview, .locationPermission:
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
        if index < slides.count - 1 {
            withAnimation { index += 1 }
        } else {
            onComplete()
        }
    }

    private func goToPreviousSlide() {
        guard index > 0 else { return }
        withAnimation { index -= 1 }
    }

    private func handleSlideTransition(from oldIndex: Int, to newIndex: Int) {
        guard oldIndex != newIndex else { return }
        let leavingSlide = slides[oldIndex]
        if leavingSlide.kind == .locationPermission, newIndex > oldIndex {
            requestLocationPermissionIfNeeded()
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
