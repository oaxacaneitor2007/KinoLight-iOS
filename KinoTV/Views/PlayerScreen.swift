import SwiftUI
import AVKit

struct PlayerScreen: View {
    @StateObject private var model: PlayerModel
    let request: PlayRequest
    let onClose: (Bool) -> Void

    init(request: PlayRequest, onClose: @escaping (Bool) -> Void) {
        self.request = request
        self.onClose = onClose
        _model = StateObject(wrappedValue: PlayerModel(request: request))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Controles nativos: reproducir/pausar, +-10 s, barra de tiempo, AirPlay, PiP y pistas de audio incrustadas.
            VideoPlayer(player: model.player).ignoresSafeArea()

            if request.audio {
                VStack(spacing: 16) {
                    AsyncImage(url: URL(string: request.poster)) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                        .frame(width: 220, height: 220)
                    Text(request.title).font(.title2.bold()).multilineTextAlignment(.center)
                }
                .allowsHitTesting(false)
            }

            if !model.subtitle.isEmpty {
                VStack {
                    Spacer()
                    Text(model.subtitle)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(6)
                        .padding(.bottom, 90)
                }
                .allowsHitTesting(false)
            }

            VStack {
                HStack {
                    Button { model.stop(); onClose(false) } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(Color.white.opacity(0.85))
                    }
                    Spacer()
                    Menu {
                        if !model.availableSubs.isEmpty {
                            Button { model.selectSub(-1) } label: {
                                Label("Subtítulos: apagados", systemImage: model.subIndex == -1 ? "checkmark" : "captions.bubble")
                            }
                            ForEach(Array(model.availableSubs.enumerated()), id: \.offset) { i, t in
                                Button { model.selectSub(i) } label: {
                                    Label(t.label, systemImage: model.subIndex == i ? "checkmark" : "captions.bubble")
                                }
                            }
                        }
                        Button { model.tryNext() } label: { Label("Probar otra fuente", systemImage: "arrow.triangle.2.circlepath") }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill").font(.title).foregroundColor(Color.white.opacity(0.85))
                    }
                }
                .padding()

                if let msg = model.message {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                Spacer()
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.didFinish) { finished in
            if finished { onClose(true) }
        }
    }
}
