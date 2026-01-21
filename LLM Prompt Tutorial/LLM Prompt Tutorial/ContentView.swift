//
//  ContentView.swift
//  LLM Prompt Tutorial
//
//  Created by Ismael Medina on 1/18/26.
//

import SwiftUI

struct LlmPromptRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
}

struct LlmChunk: Codable {
    let response: String?
    let done: Bool?
}

final class ViewModel: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var prompt = ""
    @Published var output = ""
    @Published var status = ""

    // Toggle this depending on what you're testing
    // - true  -> your own chatterd server over HTTP
    // - false -> mada.eecs.umich.edu
    private let useLocalServer = true

    // IMPORTANT: update this if your IP changes
    private let localIP = "192.168.218.196"

    private var buffer = Data()

    private var endpointURL: URL {
        if useLocalServer {
            return URL(string: "http://\(localIP):8443/llmprompt")!
        } else {
            return URL(string: "https://mada.eecs.umich.edu/llmprompt")!
        }
    }

    func sendPrompt() {
        buffer.removeAll()

        Task { @MainActor in
            self.output = ""
            self.status = "Connecting…"
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = LlmPromptRequest(
            model: "gemma3:270m",
            prompt: prompt,
            stream: true
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            Task { @MainActor in
                self.status = "Encoding error: \(error.localizedDescription)"
            }
            return
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session.dataTask(with: request).resume()
    }


    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)

        while let range = buffer.firstRange(of: Data([0x0A])) { // '\n'
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)

            guard !lineData.isEmpty else { continue }

            if let chunk = try? JSONDecoder().decode(LlmChunk.self, from: lineData),
               let text = chunk.response {
                Task { @MainActor in
                    self.output += text
                    self.status = "Streaming…"
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.status = "Failed: \(error.localizedDescription)"
                return
            }

            if let http = task.response as? HTTPURLResponse, http.statusCode != 200 {
                self.status = "HTTP \(http.statusCode)"
            } else {
                self.status = "Done"
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = ViewModel()

    var body: some View {
        VStack(spacing: 12) {
            TextField("Enter prompt", text: $vm.prompt)
                .textFieldStyle(.roundedBorder)

            Button("Send") {
                vm.sendPrompt()
            }
            .buttonStyle(.borderedProminent)

            Text(vm.status)
                .font(.caption)

            ScrollView {
                Text(vm.output)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}

