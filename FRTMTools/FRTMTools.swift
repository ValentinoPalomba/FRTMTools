//
//  ipaAnalyzerApp.swift
//  ipaAnalyzer
//
//  Created by PALOMBA VALENTINO on 02/09/25.
//

import SwiftUI

@main
struct FRTMTools: App {
    
    init() {
        DependencyRegister.register()
    }
    @State private var showOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    var body: some Scene {
        WindowGroup {
            MainView()
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                }
        }
    }
}

