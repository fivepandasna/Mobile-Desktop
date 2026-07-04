import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';
import 'package:rxdart/rxdart.dart';
import 'package:server_core/server_core.dart';

import '../data/models/aggregated_item.dart';
import '../data/services/audiobook_resume_service.dart';
import '../data/services/media_server_client_factory.dart';
import '../util/platform_detection.dart';
import '../preference/user_preferences.dart';
import 'headless_session_bootstrap.dart';
import 'last_playback_session_store.dart';
import 'media_browse_service.dart';

class MoonfinAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final PlaybackManager _manager;
  final MediaServerClientFactory _clientFactory;
  final MediaBrowseService _browse;
  final LastPlaybackSessionStore _lastSessionStore;

  final List<StreamSubscription> _subs = [];
  final Map<String, BehaviorSubject<Map<String, dynamic>>> _childrenSubjects =
      {};

  DateTime? _lastPositionPush;
  DateTime? _lastSessionPersist;

  // iOS claim/release state for the in-app player's `.playback` session.
  // Android claims at startup; desktop/tvOS never run this handler.
  bool _iosSessionConfigured = false;
  bool _iosSessionActive = false;

  MoonfinAudioHandler(
    this._manager,
    this._clientFactory,
    this._browse,
    this._lastSessionStore,
  ) {
    _bindStreams();
  }

  // stop() cancels _subs; car/lock-screen commands can arrive afterwards, so
  // re-bind before acting on them.
  void _ensureBound() {
    if (_subs.isEmpty) _bindStreams();
  }

  void _bindStreams() {
    final s = _manager.state;
    final q = _manager.queueService;

    _subs.addAll([
      s.playingStream.listen((_) {
        _pushPlaybackState();
        _updateIosAudioSession();
      }),
      s.bufferingStream.listen((_) => _pushPlaybackState()),
      // Keep the lock-screen / notification scrubber advancing during steady
      // playback. positionStream fires several times a second, so throttle the
      // pushes to ~1 Hz to avoid flooding the platform channel.
      s.positionStream.listen((_) {
        final now = DateTime.now();
        final last = _lastPositionPush;
        if (last != null &&
            now.difference(last) < const Duration(seconds: 1)) {
          return;
        }
        _lastPositionPush = now;
        _pushPlaybackState();
        _maybePersistSession();
      }),
      s.durationStream.listen((_) => _pushMediaItemForCurrentTrack()),
      q.queueChangedStream.listen((_) {
        _pushQueue();
        _pushMediaItemForCurrentTrack();
        _pushPlaybackState();
        _updateIosAudioSession();
        _persistSession();
      }),
    ]);
  }

  void _maybePersistSession() {
    final now = DateTime.now();
    final last = _lastSessionPersist;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _persistSession();
  }

  // Snapshot the audio queue for the media resumption card and empty queue
  // play restore. Audiobooks also refresh the client-authoritative local
  // resume point, which the in-app player only maintains while its own view
  // is open.
  void _persistSession() {
    final current = _manager.queueService.currentItem;
    if (current is! AggregatedItem || !current.isAudioLike) return;
    _lastSessionPersist = DateTime.now();

    final items = _manager.queueService.items
        .whereType<AggregatedItem>()
        .toList(growable: false);
    if (items.isEmpty) return;
    var index = items.indexWhere((i) => i.id == current.id);
    if (index < 0) index = 0;
    final positionMs = _manager.state.position.inMilliseconds;
    final mediaItem = _mediaItemFor(current);

    unawaited(_lastSessionStore.save(LastPlaybackSession(
      serverId: current.serverId,
      itemIds: items.map((i) => i.id).toList(growable: false),
      index: index,
      positionMs: positionMs,
      title: mediaItem.title,
      artist: mediaItem.artist,
      artUri: mediaItem.artUri?.toString(),
      isAudiobook: current.isAudiobook,
    )));

    if (current.isAudiobook && positionMs > 0) {
      unawaited(GetIt.instance<AudiobookResumeService>()
          .save(current.serverId, current.id, positionMs));
    }
  }

  bool _drivesSession(dynamic raw) {
    if (raw is! AggregatedItem) return false;
    if (PlatformDetection.isTV) return raw.isAudioLike;
    return true;
  }

  // Claimed only once playback is running, so the category is asserted after
  // libmpv opens its audio output. Kept through pause, released on stop/idle.
  void _updateIosAudioSession() {
    if (!PlatformDetection.isIOS) return;
    final s = _manager.state;
    final q = _manager.queueService;
    if (s.isPlaying && _drivesSession(q.currentItem)) {
      _activateIosSession();
    } else if (q.currentItem == null) {
      _deactivateIosSession();
    }
  }

  Future<void> _activateIosSession() async {
    if (_iosSessionActive) return;
    _iosSessionActive = true;
    try {
      final session = await AudioSession.instance;
      if (!_iosSessionConfigured) {
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.moviePlayback,
        ));
        _iosSessionConfigured = true;
      }
      await session.setActive(true);
    } catch (_) {
      _iosSessionActive = false;
    }
  }

  Future<void> _deactivateIosSession() async {
    if (!_iosSessionActive) return;
    _iosSessionActive = false;
    try {
      final session = await AudioSession.instance;
      await session.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } catch (_) {}
  }

  void _pushPlaybackState() {
    final s = _manager.state;
    final q = _manager.queueService;

    if (PlatformDetection.isTV && !_drivesSession(q.currentItem)) {
      // No music session (TV video / nothing playing): emit idle so audio_service
      // tears down the foreground notification and system controls.
      playbackState.add(PlaybackState(
        controls: const [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
      ));
      return;
    }

    final currentItem = q.currentItem;
    final isAudiobook = currentItem is AggregatedItem && currentItem.isAudiobook;

    final controls = isAudiobook
        ? [
            MediaControl.rewind,
            s.isPlaying ? MediaControl.pause : MediaControl.play,
            MediaControl.fastForward,
            MediaControl.skipToNext,
          ]
        : [
            MediaControl.skipToPrevious,
            s.isPlaying ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            // Android Auto only renders buttons from the controls list, not from
            // the repeat/shuffle mode fields, so shuffle and repeat are custom
            // actions. The icon and label carry the current state since the car
            // tints custom icons uniformly and can't show an active highlight.
            MediaControl.custom(
              androidIcon: 'drawable/ic_shuffle',
              label: s.isShuffled ? 'Shuffle on' : 'Shuffle',
              name: 'toggle_shuffle',
            ),
            MediaControl.custom(
              androidIcon: q.repeatMode == RepeatMode.repeatOne
                  ? 'drawable/ic_repeat_one'
                  : 'drawable/ic_repeat',
              label: switch (q.repeatMode) {
                RepeatMode.none => 'Repeat off',
                RepeatMode.repeatAll => 'Repeat all',
                RepeatMode.repeatOne => 'Repeat one',
              },
              name: 'toggle_repeat',
            ),
          ];

    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: {
        MediaAction.seek,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.setSpeed,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
        if (isAudiobook) MediaAction.fastForward,
        if (isAudiobook) MediaAction.rewind,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: s.isBuffering
          ? AudioProcessingState.buffering
          : q.currentItem != null
              ? AudioProcessingState.ready
              : AudioProcessingState.idle,
      playing: s.isPlaying,
      updatePosition: s.position,
      bufferedPosition: s.buffer,
      speed: s.playbackSpeed,
      queueIndex: q.currentIndex,
      // Keep the session's shuffle and repeat state correct for the lock screen,
      // Assistant, and other clients. Android Auto's buttons come from the
      // controls above, not these fields.
      repeatMode: switch (q.repeatMode) {
        RepeatMode.none => AudioServiceRepeatMode.none,
        RepeatMode.repeatOne => AudioServiceRepeatMode.one,
        RepeatMode.repeatAll => AudioServiceRepeatMode.all,
      },
      shuffleMode: s.isShuffled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  void _pushMediaItemForCurrentTrack() {
    final raw = _manager.queueService.currentItem;
    if (raw is! AggregatedItem || (PlatformDetection.isTV && !raw.isAudioLike)) {
      mediaItem.add(null);
      return;
    }
    mediaItem.add(_mediaItemFor(raw));
  }

  void _pushQueue() {
    final items = _manager.queueService.items;
    queue.add(items
        .whereType<AggregatedItem>()
        .map(_mediaItemFor)
        .toList());
  }

  MediaItem _mediaItemFor(AggregatedItem item) {
    final client = _clientFor(item);
    String? artUri;
    try {
      final albumTag = item.albumPrimaryImageTag;
      final albumId = item.albumId;
      if (item.type == 'Audio' && albumTag != null && albumId != null) {
        artUri = client.imageApi
            .getPrimaryImageUrl(albumId, maxHeight: 300, tag: albumTag);
      } else if (item.primaryImageTag != null) {
        artUri = client.imageApi
            .getPrimaryImageUrl(item.id, maxHeight: 300, tag: item.primaryImageTag);
      }
    } catch (_) {}

    final String? artistName;
    if (item.type == 'Episode') {
      artistName = (item.seriesName != null && item.seriesName!.isNotEmpty)
          ? item.seriesName
          : 'TV Show';
    } else if (item.type == 'Movie') {
      final directors = item.people
          .where((p) => p['Type'] == 'Director')
          .map((p) => p['Name'] as String?)
          .whereType<String>()
          .toList();
      if (directors.isNotEmpty) {
        artistName = directors.join(', ');
      } else {
        final studios = item.studios
            .map((s) => s['Name'] as String?)
            .whereType<String>()
            .toList();
        artistName = studios.isNotEmpty ? studios.first : 'Movie';
      }
    } else {
      artistName = item.artists.isNotEmpty
          ? item.artists.join(', ')
          : item.albumArtist;
    }

    return MediaItem(
      id: item.id,
      title: item.name,
      artist: artistName,
      album: item.album,
      duration: item.runtime,
      artUri: artUri != null ? Uri.parse(artUri) : null,
      extras: {'serverId': item.serverId},
    );
  }

  MediaServerClient _clientFor(AggregatedItem item) {
    return _clientFactory.getClientIfExists(item.serverId) ??
        GetIt.instance<MediaServerClient>();
  }

  @override
  Future<void> play() async {
    _ensureBound();
    if (_manager.queueService.currentItem != null) {
      return _manager.resume();
    }
    // Empty queue: a car head unit, steering wheel, or Bluetooth device sent
    // play with nothing loaded, so restore the last audio session.
    final prefs = GetIt.instance<UserPreferences>();
    if (!prefs.get(UserPreferences.resumeLastQueueOnPlay)) return;
    final last = await _lastSessionStore.load();
    if (last == null) return;
    final request = await _browse.resolveLastSession(last);
    if (request == null) return;
    await _manager.playItems(
      request.items,
      startIndex: request.startIndex,
      startPosition: request.startPosition,
    );
  }

  @override
  Future<void> pause() async => _manager.pause();

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) =>
      _browse.getChildren(parentMediaId, options);

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(
    String parentMediaId,
  ) =>
      _childrenSubjects.putIfAbsent(
        parentMediaId,
        () => BehaviorSubject.seeded(<String, dynamic>{}),
      );

  /// Makes subscribed car clients re-query [parentMediaId], or all subscribed
  /// parents when null. Called after the headless session restore completes
  /// and on sign-in changes.
  void notifyChildrenChanged([String? parentMediaId]) {
    if (parentMediaId != null) {
      _childrenSubjects[parentMediaId]?.add(<String, dynamic>{});
      return;
    }
    for (final subject in _childrenSubjects.values) {
      subject.add(<String, dynamic>{});
    }
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    _ensureBound();
    if (mediaId.startsWith('msg|')) {
      _pushErrorState('Open Moonfin on your phone to sign in');
      return;
    }
    final request = await _browse.resolvePlayRequest(mediaId);
    if (request == null) {
      _pushErrorState('This item is unavailable right now');
      return;
    }
    await _manager.playItems(
      request.items,
      startIndex: request.startIndex,
      startPosition: request.startPosition,
    );
  }

  // Android's media-resumption flow sends prepareFromMediaId followed by play.
  @override
  Future<void> prepareFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) =>
      playFromMediaId(mediaId, extras);

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    _ensureBound();
    final request = await _browse.resolveSearchPlay(query);
    if (request == null) {
      _pushErrorState('Nothing found for "$query"');
      return;
    }
    await _manager.playItems(
      request.items,
      startIndex: request.startIndex,
      startPosition: request.startPosition,
    );
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) =>
      _browse.search(query);

  void _pushErrorState(String message) {
    playbackState.add(PlaybackState(
      controls: const [],
      systemActions: const {},
      processingState: AudioProcessingState.error,
      errorMessage: message,
      playing: false,
    ));
  }

  @override
  Future<void> stop() async {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    await _manager.stop(userInitiated: false);
    await _deactivateIosSession();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async => _manager.seekTo(position);

  @override
  Future<void> skipToNext() async => _manager.next();

  @override
  Future<void> skipToPrevious() async => _manager.previous();

  @override
  Future<void> skipToQueueItem(int index) async =>
      _manager.playFromQueue(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final target = switch (repeatMode) {
      AudioServiceRepeatMode.none => RepeatMode.none,
      AudioServiceRepeatMode.one => RepeatMode.repeatOne,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group =>
        RepeatMode.repeatAll,
    };
    while (_manager.queueService.repeatMode != target) {
      _manager.toggleRepeat();
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final wantShuffle = shuffleMode != AudioServiceShuffleMode.none;
    if (_manager.state.isShuffled != wantShuffle) _manager.toggleShuffle();
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      // toggleShuffle/toggleRepeat fire queueChangedStream, which re-pushes the
      // playback state (and its updated control icons), same as setShuffleMode.
      case 'toggle_shuffle':
        _manager.toggleShuffle();
      case 'toggle_repeat':
        _manager.toggleRepeat();
      default:
        return super.customAction(name, extras);
    }
  }

  @override
  Future<void> fastForward() async {
    final prefs = GetIt.instance<UserPreferences>();
    final ms = prefs.get(UserPreferences.skipForwardLength);
    await _manager.seekTo(_manager.state.position + Duration(milliseconds: ms));
  }

  @override
  Future<void> rewind() async {
    final prefs = GetIt.instance<UserPreferences>();
    final ms = prefs.get(UserPreferences.skipBackLength);
    final target = _manager.state.position - Duration(milliseconds: ms);
    await _manager.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _manager.setPlaybackSpeed(speed);
  }
}

Future<void> initAudioService({
  required PlaybackManager manager,
  required MediaServerClientFactory clientFactory,
}) async {
  final bootstrap = GetIt.instance<HeadlessSessionBootstrap>();
  final browse = GetIt.instance<MediaBrowseService>();
  final lastSessionStore = GetIt.instance<LastPlaybackSessionStore>();

  final handler = await AudioService.init<MoonfinAudioHandler>(
    builder: () =>
        MoonfinAudioHandler(manager, clientFactory, browse, lastSessionStore),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.moonfin.app.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      notificationColor: const Color(0xFF1A1A2E),
      androidNotificationIcon: 'drawable/ic_notification',
      androidBrowsableRootExtras: {
        AndroidContentStyle.supportedKey: true,
        AndroidContentStyle.browsableHintKey:
            AndroidContentStyle.categoryListItemHintValue,
        AndroidContentStyle.playableHintKey:
            AndroidContentStyle.listItemHintValue,
      },
    ),
  );

  if (!GetIt.instance.isRegistered<MoonfinAudioHandler>()) {
    GetIt.instance.registerSingleton<MoonfinAudioHandler>(handler);
  }

  // Kick the widget-free session restore so a car client that bound the
  // service headlessly gets a populated tree; the notify makes Android Auto
  // re-query the root it may have seen empty during engine startup.
  if (PlatformDetection.isAndroid) {
    unawaited(bootstrap.ensureSession().then((client) {
      if (client != null) handler.notifyChildrenChanged();
    }));
  }
}
