import SwiftUI
import UIKit

/// The system page indicator (`UIPageControl`) — SwiftUI has no standalone one outside `TabView`.
struct PageIndicator: UIViewRepresentable {
    let numberOfPages: Int
    let currentPage: Int
    let onSelect: (Int) -> Void

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.hidesForSinglePage = true
        control.pageIndicatorTintColor = .tertiaryLabel
        control.currentPageIndicatorTintColor = .label
        control.addTarget(context.coordinator, action: #selector(Coordinator.pageChanged(_:)), for: .valueChanged)
        control.setContentHuggingPriority(.required, for: .vertical)
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        context.coordinator.onSelect = onSelect
        control.numberOfPages = numberOfPages
        if control.currentPage != currentPage {
            control.currentPage = currentPage
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject {
        var onSelect: (Int) -> Void

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        @objc func pageChanged(_ control: UIPageControl) {
            onSelect(control.currentPage)
        }
    }
}
