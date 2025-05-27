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
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let navController = UINavigationController(rootViewController: LibraryViewController())
        window?.rootViewController = navController
        window?.makeKeyAndVisible()
        return true
    }
}

