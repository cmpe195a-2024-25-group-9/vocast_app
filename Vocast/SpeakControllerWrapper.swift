//
//  SpeakControllerWrapper.swift
//  Vocast
//
//  Created by Fardin Haque on 4/13/25.
//

import SwiftUI

struct SpeakControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SpeakController {
        return SpeakController()
    }

    func updateUIViewController(_ uiViewController: SpeakController, context: Context) {
        // No updates needed in this case
    }
}
