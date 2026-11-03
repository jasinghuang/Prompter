import SwiftUI
import UIKit

/// Keeps UIKit's interactive pop available with the custom player toolbar.
/// UIKit owns transition progress, direction, cancellation and Reduce Motion behavior.
struct NativePlayerNavigation: UIViewControllerRepresentable {
    var enabled: Bool

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.enabled = enabled
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enabled = enabled
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restoreGesture()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        var enabled = true
        private weak var gesture: UIGestureRecognizer?
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private var previouslyEnabled = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let navigationController, navigationController.viewControllers.count > 1,
                  let pop = navigationController.interactivePopGestureRecognizer else { return }
            guard pop.delegate !== self else { return }
            gesture = pop
            previousDelegate = pop.delegate
            previouslyEnabled = pop.isEnabled
            pop.delegate = self
            pop.isEnabled = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            // An interactive cancellation does not finish disappearance. Keep ownership until
            // the player actually leaves; restoring in viewWillDisappear would break cancellation.
            restoreGesture()
        }

        func restoreGesture() {
            if let gesture, gesture.delegate === self {
                gesture.delegate = previousDelegate
                gesture.isEnabled = previouslyEnabled
            }
            gesture = nil
            previousDelegate = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard enabled, viewIfLoaded?.window != nil, let navigationController,
                  navigationController.viewControllers.count > 1,
                  navigationController.transitionCoordinator == nil,
                  navigationController.presentedViewController == nil else { return false }
            // Do not let a stale/background player start a pop on another navigation page.
            var page: UIViewController = self
            while let parent = page.parent, parent !== navigationController { page = parent }
            return navigationController.topViewController === page && page.presentedViewController == nil
        }
    }
}
