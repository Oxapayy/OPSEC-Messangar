import SwiftUI

struct MainTabView: View {
    init() {
        // Make the tab bar match the theme.
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.navyDeep)
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Theme.textSecondary)
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Theme.cyan)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes =
            [.foregroundColor: UIColor(Theme.cyan)]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.navyDeep)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }

    var body: some View {
        TabView {
            NavigationStack { ChatListView() }
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }

            NavigationStack { ContactsView() }
                .tabItem { Label("Contacts", systemImage: "person.2.fill") }

            NavigationStack { GroupsView() }
                .tabItem { Label("Groups", systemImage: "person.3.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
