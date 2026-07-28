import SwiftUI

@main
struct GitMateApp: App {
    var body: some Scene {
        WindowGroup {
            Text("GitMate")
                .frame(width: 960, height: 640)
        }
        .windowResizability(.contentSize)
    }
}
