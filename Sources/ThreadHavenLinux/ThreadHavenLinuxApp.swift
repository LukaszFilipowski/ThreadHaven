import Adwaita

@main
struct ThreadHavenLinuxApp: App {
    var app = AdwaitaApp(id: "app.threadhaven.ThreadHaven")

    var scene: Scene {
        Window(id: "main") { _ in
            SessionsView()
        }
        .title("ThreadHaven")
        .defaultSize(width: 1000, height: 700)
    }
}
