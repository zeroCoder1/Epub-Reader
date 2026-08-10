//
//  AppDelegate.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        // The app chrome (library, settings, theme panels) is designed light-only; lock it to
        // light so it doesn't flip with the system. The reader themes its page independently
        // (WebView colors), so dark/sepia reading still works.
        window?.overrideUserInterfaceStyle = .light
        let navController = UINavigationController(rootViewController: LibraryViewController())
        window?.rootViewController = navController
        window?.makeKeyAndVisible()
        return true
    }
}

