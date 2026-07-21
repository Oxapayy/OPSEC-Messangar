import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { ChatListView() }
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }

            NavigationStack { ContactsView() }
                .tabItem { Label("Contacts", systemImage: "person.2.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
