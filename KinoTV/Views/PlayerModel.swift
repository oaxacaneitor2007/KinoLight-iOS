import Foundation
import AVFoundation

/// Logica de reproduccion: cambio automatico de fuente, progreso y subtitulos externos.
/// Todas las llamadas llegan en el hilo principal (observer en .main, KVO y notificaciones se reenvian).
final class PlayerModel: ObservableObject {
    let req: PlayRequest
    let player = AVPlayer()

    @Published var message: String?
    @Published var subtitle = ""
    @Published var subIndex = -1            // -1 = apagados
    @Published var availableSubs: [SubTrack] = []
    @Published var didFinish = false

    private var idx: Int
    private var attempts = 0
    private var cues: [Cue] = []
    private var statusObs: NSKeyValueObservation?
    private var timeObs: Any?
    private var notifObs: [NSObjectProtocol] = []
    private var watchdog: Task<Void, Never>?
    private var subTask: Task<Void, Never>?
    private var lastSave = 0
    private var stopped = false
    private var pendingResume = 0

    init(request: PlayRequest) {
        req = request
        idx = request.startIndex
    }

    func start() {
        timeObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            self?.tick(t.seconds)
        }
        play(index: idx, resume: req.resume)
    }

    // MARK: Reproduccion

    private func play(index: Int, resume: Int) {
        guard index < req.streams.count, let url = URL(string: req.streams[index].url) else { tryNext(); return }
        let s = req.streams[index]
        clearItemObservers()

        var opts: [String: Any]?
        if !s.headers.isEmpty { opts = ["AVURLAssetHTTPHeaderFieldsKey": s.headers] }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: opts))
        pendingResume = resume

        statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async { self?.itemStatus(it.status) }
        }
        let nc = NotificationCenter.default
        notifObs.append(nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.ended()
        })
        notifObs.append(nc.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.tryNext()
        })

        // subtitulos: los de los addons + los propios de la fuente; apagados al cambiar de fuente
        var tracks: [SubTrack] = []
        for t in req.subs + s.subs where !tracks.contains(where: { $0.url == t.url }) { tracks.append(t) }
        availableSubs = tracks
        selectSub(-1)

        player.replaceCurrentItem(with: item)
        player.play()
        startWatchdog()
    }

    private func itemStatus(_ st: AVPlayerItem.Status) {
        if stopped { return }
        if st == .readyToPlay {
            watchdog?.cancel()
            message = nil
            if pendingResume > 10 {
                player.seek(to: CMTime(seconds: Double(pendingResume), preferredTimescale: 600))
                pendingResume = 0
            }
        } else if st == .failed {
            tryNext()
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self?.tryNext() }
        }
    }

    /// Si la fuente falla o no responde en 30 s, pasa a la siguiente (maximo 6 intentos).
    func tryNext() {
        if stopped { return }
        watchdog?.cancel()
        let cur = player.currentTime().seconds
        attempts += 1
        idx += 1
        if attempts >= 6 || idx >= req.streams.count {
            player.pause()
            message = "No se pudo reproducir. Cierra y elige otra fuente."
            return
        }
        message = "La fuente no respondió. Probando la siguiente (\(idx + 1) de \(req.streams.count))…"
        play(index: idx, resume: (cur.isFinite && cur > 5) ? Int(cur) : req.resume)
    }

    private func ended() {
        if stopped { return }
        if req.live { tryNext(); return }
        stopped = true
        ContinueStore.remove(req.key)
        cleanup()
        didFinish = true
    }

    // MARK: Subtitulos externos

    func selectSub(_ i: Int) {
        subTask?.cancel()
        subIndex = i
        cues = []
        subtitle = ""
        guard i >= 0, i < availableSubs.count else { return }
        let url = availableSubs[i].url
        subTask = Task { [weak self] in
            let c = await Subtitles.load(url)
            if Task.isCancelled { return }
            await MainActor.run { self?.cues = c }
        }
    }

    // MARK: Progreso (continuar viendo)

    private func tick(_ t: Double) {
        if stopped || !t.isFinite { return }
        if !cues.isEmpty {
            let txt = cues.first(where: { t >= $0.start && t <= $0.end })?.text ?? ""
            if txt != subtitle { subtitle = txt }
        }
        if !req.live {
            let pos = Int(t)
            if pos - lastSave >= 20 || pos < lastSave { saveProgress() }
        }
    }

    private func saveProgress() {
        if req.live { return }
        let pos = Int(player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0)
        let d = player.currentItem?.duration.seconds ?? 0
        let dur = d.isFinite ? Int(d) : 0
        if dur > 0 && Double(pos) > Double(dur) * 0.92 {
            ContinueStore.remove(req.key)
            return
        }
        if pos < 10 { return }
        ContinueStore.save(ContinueEntry(k: req.key, t: req.type, i: req.metaId, a: req.abase,
                                         n: String(req.title.prefix(70)), p: req.poster, v: req.vid,
                                         s: req.season, e: req.episode, pos: pos, dur: dur))
        lastSave = pos
    }

    // MARK: Cierre

    private func clearItemObservers() {
        statusObs = nil
        for o in notifObs { NotificationCenter.default.removeObserver(o) }
        notifObs.removeAll()
    }

    private func cleanup() {
        watchdog?.cancel()
        subTask?.cancel()
        clearItemObservers()
        if let o = timeObs { player.removeTimeObserver(o); timeObs = nil }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    /// Se llama al cerrar la pantalla: guarda el punto donde quedaste.
    func stop() {
        if !stopped { saveProgress() }
        stopped = true
        cleanup()
    }
}
