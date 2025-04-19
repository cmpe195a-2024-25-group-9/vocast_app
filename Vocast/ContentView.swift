//
//  ContentView.swift
//  Vocast
//
//  Created by Fardin Haque on 4/19/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject var streamer = AudioStreamer()

    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Streamer")
                .font(.title)
            Button(streamer.isStreaming ? "Mute" : "Unmute") {
                if streamer.isStreaming {
                    streamer.stopStreaming()
                } else {
                    streamer.startStreaming()
                }
            }
            .padding()
        }
    }
}
