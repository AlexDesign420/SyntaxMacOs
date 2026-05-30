//
//  SyntaxApp.swift
//  Syntax
//
//  Created by Alexander Dejan on 5/12/26.
//

import SwiftUI

@main
struct SyntaxApp: App {
    @StateObject private var appModel = SyntaxAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
    }
}
