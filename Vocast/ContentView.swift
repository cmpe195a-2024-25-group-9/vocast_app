//
//  ContentView.swift
//  Vocast
//
//  Created by Fardin Haque on 4/19/25.
//
import SwiftUI

struct ContentView: View {
    @State private var ipAddress: String = ""
    @State private var confirmedIP: String? = nil
    @State private var ipConfirmed = false

    @StateObject private var streamer = AudioStreamer(espIP: "0.0.0.0")

    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Streamer")
                .font(.title)

            HStack {
                TextField("Enter ESP IP", text: $ipAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 200)

                Button(action: {
                    confirmedIP = ipAddress
                    ipConfirmed = true
                    streamer.updateIP(to: ipAddress)
                }) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                }
            }

            if let ip = confirmedIP {
                Text("Streaming to IP: \(ip)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Button(streamer.isStreaming ? "Mute" : "Unmute") {
                if streamer.isStreaming {
                    streamer.stopStreaming()
                } else {
                    streamer.startStreaming()
                }
            }
            .padding()
            .disabled(!ipConfirmed) // disable until IP is confirmed
        }
        .padding()
    }
}
