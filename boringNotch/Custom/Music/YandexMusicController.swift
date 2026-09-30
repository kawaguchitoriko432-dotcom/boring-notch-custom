//
//  YandexMusicController.swift
//  boringNotch
//
//  Режим «Яндекс Музыка». Приложение «Яндекс Музыка» для macOS публикует
//  «Now Playing» в систему, поэтому берём данные из системного источника
//  (NowPlayingController), но пропускаем только треки этого приложения.
//  Если играет что-то другое (браузер, Spotify), шторка не показывает чужой трек.
//

import AppKit
import Combine
import Foundation

final class YandexMusicController: ObservableObject, MediaControllerProtocol {
    static let bundleID = "ru.yandex.desktop.music"

    private let inner: NowPlayingController
    private var cancellable: AnyCancellable?

    @Published private(set) var playbackState: PlaybackState = YandexMusicController.idleState()

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }

    init?() {
        guard let inner = NowPlayingController() else { return nil }
        self.inner = inner
        cancellable = inner.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handle(state)
            }
    }

    private static func idleState() -> PlaybackState {
        var state = PlaybackState(bundleIdentifier: bundleID)
        state.title = ""
        state.artist = ""
        state.album = ""
        state.isPlaying = false
        return state
    }

    private func handle(_ state: PlaybackState) {
        // Хелперы Electron могут приходить как «ru.yandex.desktop.music.helper…».
        if state.bundleIdentifier.hasPrefix(Self.bundleID) {
            playbackState = state
        } else {
            let idle = Self.idleState()
            if playbackState != idle {
                playbackState = idle
            }
        }
    }

    // MARK: - Управление (через системный Now Playing)

    func play() async { await inner.play() }
    func pause() async { await inner.pause() }
    func togglePlay() async { await inner.togglePlay() }
    func nextTrack() async { await inner.nextTrack() }
    func previousTrack() async { await inner.previousTrack() }
    func seek(to time: Double) async { await inner.seek(to: time) }
    func toggleShuffle() async { await inner.toggleShuffle() }
    func toggleRepeat() async { await inner.toggleRepeat() }
    func setVolume(_ level: Double) async {}
    func setFavorite(_ favorite: Bool) async {}
    func isActive() -> Bool { true }
    func updatePlaybackInfo() async {}
}
