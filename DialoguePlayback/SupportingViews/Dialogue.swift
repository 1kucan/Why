//
//  Dialogue.swift
//  DialoguePlayback
//
//  Created by Alexander Kutsan on 25.09.2020.
//

import SwiftUI
import Combine
import AVKit

struct Dialogue: View {
    @EnvironmentObject var appData: AppData<Fetcher>
    
    @State private var utterance: AVSpeechUtterance?
    @State private var feed: [Message] = []
    
    @State private var storage = Set<AnyCancellable>()
    ///
    private let deliveredPub = PassthroughSubject<Void, Never>()
    ///
    private let player = Player()
    ///
    var body: some View {
        NavigationView {
            LazyVStack
            {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: R.messageStackSpacing) {
                        ForEach(feed) { item in
                            MessageRow(message:
                                        item)
                                .opacity(item.opacity)
                                .onCompleteAnimation(for: item.opacity) {
                                    deliveredPub.send()
                                }
                                .onAppear {
                                    withAnimation(.linear(duration: R.animationDuration)) {
                                        feed.firstIndex { $0.id == item.id }
                                            .map { feed[$0].opacity = 1.0 }
                                    }
                                }
                        }
                    }.padding(R.balloon.radius)
                }.animation(.linear(duration: R.animationDuration))
            }
            .navigationBarTitle(R.dialogueViewTitle, displayMode: .inline)
            .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity,
                   minHeight: 0, idealHeight: .infinity, maxHeight: .infinity,
                   alignment: .bottom)
            .onAppear() {
                ///
                appData.messagePub()?
                    .zip(deliveredPub)
                    .map(\.0)
                    .zip(player.$isPlaying)
                    .delay(for: .seconds(R.preUtteranceDelay), scheduler: RunLoop.main)
                    .flatMap { val in
                        Just(val)
                            .tryMap { _ in
                                guard val.1 == false else {
                                    throw PlaybackErr()
                                }
                                return val.0
                            }
                            .catch { _ in
                                Just(val.0)
                            }
                    }
                    .sink {
                        feed.append($0)
                        utterance = AVSpeechUtterance(string: String($0.text.prefix(R.maxCharacters))) }
                    .store(in: &storage)
                ///
                deliveredPub
                    .delay(for: .seconds(R.preUtteranceDelay), scheduler: RunLoop.main)
                    .sink {
                        defer { utterance = nil }
                        utterance.map { player.speaker.speak($0) }
                    }
                    .store(in: &storage)
                // To kick-off
                deliveredPub.send()
                ///
            }.padding(R.dialogueViewPadding)
        }
    }
    struct PlaybackErr: Error {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Dialogue().environmentObject(AppData<Fetcher>())
    }
}
// MARK: - Animation
struct AM<Value>: AnimatableModifier where Value: VectorArithmetic {
    ///
    var animatableData: Value {
        didSet {
            handleCompletion()
        }
    }
    ///
    private var target: Value
    private var handler: () -> Void
    ///
    init(observedValue: Value, completion: @escaping () -> Void) {
        self.handler = completion
        self.animatableData = observedValue
        target = observedValue
    }
    ///
    private func handleCompletion() {
        guard animatableData == target else { return }
        
        DispatchQueue.main.async {
            self.handler()
        }
    }
    ///
    func body(content: Content) -> some View {
        return content
    }
}

extension View {
    func onCompleteAnimation<Value: VectorArithmetic>(for value: Value, completion: @escaping () -> Void) -> ModifiedContent<Self, AM<Value>> {
        return modifier(AM(observedValue: value, completion: completion))
    }
}
