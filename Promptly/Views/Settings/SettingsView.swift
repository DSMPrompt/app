//
//  SettingsView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI

struct SettingsView: View {
    @State var keepScreenOn: Bool = false
    
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Display")) {
                    Toggle("Keep Screen On", isOn: self.$keepScreenOn)
                }
            }
            .navigationTitle(Text("Settings"))
            .onChange(of: self.keepScreenOn) {_, _ in
                #if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = self.keepScreenOn
                #endif
            }
        }
    }
}

#Preview {
    SettingsView()
}
