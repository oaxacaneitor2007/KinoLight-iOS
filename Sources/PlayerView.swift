import SwiftUI
import AVFoundation
import Combine
import UIKit

/// Estado del reproductor. Equivale a lo que PlayerScreen.kt hacía con ExoPlayer.
final class PlayerModel: ObservableObject {
    let player = AVPlayer()

    @Published var playing = true
    @Published var buffering = true
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var buffered: Double = 0
    @Published var failed = false
    @Published var ended = false

    private let url: URL?
    private var timeObserver: Any?
    private var bag = Set<AnyCancellable>()

    init(urlString: String) {
        url = URL(string: urlString)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let s = time.seconds
            if s.isFinite { self?.position = max(0, s) }
        }
        load()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    /// Carga (o recarga, en "Reintentar") el video.
    func load() {
        bag.removeAll()
        failed = false
        ended = false
        buffering = true
        position = 0
        duration = 0
        buffered = 0
        guard let url else {
            failed = true
            buffering = false
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .failed {
                    self?.failed = true
                    self?.buffering = false
                }
            }
            .store(in: &bag)

        item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] d in
                if d.isNumeric, d.seconds > 0 { self?.duration = d.seconds }
            }
            .store(in: &bag)

        item.publisher(for: \.loadedTimeRanges)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ranges in
                guard let self else { return }
                let spans = ranges.map { $0.timeRangeValue }
                let current = self.position
                let match = spans.first { $0.start.seconds <= current && current <= $0.end.seconds } ?? spans.first
                if let match { self.buffered = match.end.seconds }
            }
            .store(in: &bag)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.playing = status != .paused
                self?.buffering = status == .waitingToPlayAtSpecifiedRate
            }
            .store(in: &bag)

        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.ended = true }
            .store(in: &bag)

        player.play()
    }

    func togglePlayPause() {
        if ended {
            seek(to: 0)
            ended = false
            player.play()
            return
        }
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
    }

    func seekBy(_ delta: Double) {
        let upper = duration > 0 ? duration : Double.greatestFiniteMagnitude
        seek(to: min(max(player.currentTime().seconds + delta, 0), upper))
        ended = false
    }

    func pause() { player.pause() }
}

/// La capa de video sin controles nativos (los controles son los de Kino).
private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: LayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

/// Barra de progreso con el búfer; se arrastra o se toca.
private struct SeekBar: View {
    let position: Double
    let duration: Double
    let buffered: Double
    let onDrag: (Double) -> Void
    let onEnd: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let played = duration > 0 ? min(max(position / duration, 0), 1) : 0
            let buf = duration > 0 ? min(max(buffered / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                Capsule().fill(Color.white.opacity(0.4)).frame(width: w * buf, height: 4)
                Capsule().fill(Kino.red).frame(width: w * played, height: 4)
                Circle().fill(Kino.red).frame(width: 14, height: 14)
                    .offset(x: w * played - 7)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onDrag(min(max($0.location.x / w, 0), 1)) }
                    .onEnded { onEnd(min(max($0.location.x / w, 0), 1)) }
            )
        }
        .frame(height: 44)
    }
}

private struct AutoHideKey: Hashable {
    let tick: Int
    let visible: Bool
    let playing: Bool
}

/// El reproductor: video a pantalla completa con el overlay de Kino (título, progreso con búfer,
/// -10 / pausa / +10 y botón de rotar).
struct PlayerView: View {
    let film: Film

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: PlayerModel
    @State private var controlsVisible = false // empieza oculto: primero el video
    @State private var tick = 0
    @State private var dragFraction: Double?
    @State private var didRotate = false

    private let seekStep: Double = 10
    private let hideAfterNanos: UInt64 = 4_500_000_000

    init(film: Film) {
        self.film = film
        _model = StateObject(wrappedValue: PlayerModel(urlString: film.videoUrl))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerSurface(player: model.player).ignoresSafeArea()

            // Un toque en el video muestra u oculta los controles.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }

            if model.buffering && !model.failed {
                ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.4)
            }

            if model.failed { errorView }

            if controlsVisible && !model.failed {
                controls.transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear(perform: startSession)
        .onDisappear(perform: endSession)
        // Salir de la app pausa; al volver queda en pausa con los controles visibles.
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                model.pause()
                bump()
            }
        }
        .task(id: AutoHideKey(tick: tick, visible: controlsVisible, playing: model.playing)) {
            guard controlsVisible, model.playing else { return }
            try? await Task.sleep(nanoseconds: hideAfterNanos)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    // MARK: - Controles

    private var controls: some View {
        let shownPosition = dragFraction.map { $0 * model.duration } ?? model.position
        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.70), location: 0.0),
                    .init(color: Color.black.opacity(0.08), location: 0.30),
                    .init(color: Color.black.opacity(0.08), location: 0.70),
                    .init(color: Color.black.opacity(0.85), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Arriba: atrás y título.
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Atrás")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(film.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(film.metaLine())
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

                Spacer()

                // Centro: -10 / play-pausa / +10.
                HStack(spacing: 44) {
                    roundButton("gobackward.10", size: 34, label: "Retroceder 10 segundos") {
                        model.seekBy(-seekStep); bump()
                    }
                    roundButton(model.playing && !model.ended ? "pause.fill" : "play.fill", size: 48,
                                label: model.playing ? "Pausa" : "Reproducir") {
                        model.togglePlayPause(); bump()
                    }
                    roundButton("goforward.10", size: 34, label: "Adelantar 10 segundos") {
                        model.seekBy(seekStep); bump()
                    }
                }

                Spacer()

                // Abajo: tiempo, barra y rotar.
                HStack(spacing: 10) {
                    Text(formatDuration(shownPosition))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                    SeekBar(
                        position: shownPosition,
                        duration: model.duration,
                        buffered: model.buffered,
                        onDrag: { dragFraction = $0; bump() },
                        onEnd: { fraction in
                            model.seek(to: fraction * model.duration)
                            dragFraction = nil
                            bump()
                        }
                    )
                    Text(formatDuration(model.duration))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                    Button { rotate() } label: {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Rotar pantalla")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func roundButton(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: size + 20, height: size + 20)
        }
        .accessibilityLabel(label)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Text("No se pudo reproducir este video.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Button { model.load() } label: {
                Text("Reintentar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Kino.red, in: Capsule())
            }
            Button("Volver") { dismiss() }
                .font(.system(size: 14))
                .foregroundStyle(Kino.textSecondary)
        }
    }

    // MARK: - Acciones

    private func bump() {
        controlsVisible = true
        tick += 1
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if controlsVisible { controlsVisible = false } else { bump() }
        }
    }

    private func startSession() {
        // Audio aunque el interruptor de silencio esté activado.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true // pantalla encendida mientras se ve
    }

    private func endSession() {
        model.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        if didRotate { setOrientations(UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Alterna vertical / horizontal.
    private func rotate() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }
        didRotate = true
        setOrientations(scene.interfaceOrientation.isPortrait ? .landscape : .portrait)
        bump()
    }

    private func setOrientations(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}
