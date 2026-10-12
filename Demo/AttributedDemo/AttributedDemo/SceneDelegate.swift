// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        NSLog("PROBE willConnect %@", String(describing: type(of: scene)))
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let navigationController = UINavigationController(rootViewController: HomeViewController())
        navigationController.navigationBar.prefersLargeTitles = true
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window

        // `-stressSeconds N` runs the stress page for N seconds and returns
        // home, so memory can be measured after a reproducible run.
        let arguments = ProcessInfo.processInfo.arguments

        if let index = arguments.firstIndex(of: "-stressSeconds"), index + 1 < arguments.count,
           let seconds = TimeInterval(arguments[index + 1]) {
            let stress = StressViewController()
            stress.autoRunSeconds = seconds
            navigationController.pushViewController(stress, animated: false)
        }
    }
}
