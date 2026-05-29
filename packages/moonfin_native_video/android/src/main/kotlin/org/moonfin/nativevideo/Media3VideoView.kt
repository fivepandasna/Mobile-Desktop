package org.moonfin.nativevideo

import android.app.ActivityManager
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.core.content.getSystemService
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.VideoSize
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.ExperimentalApi
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.video.MediaCodecVideoRenderer
import androidx.media3.exoplayer.video.VideoRendererEventListener
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.github.peerless2012.ass.media.AssHandler
import io.github.peerless2012.ass.media.kt.withAssMkvSupport
import io.github.peerless2012.ass.media.kt.withAssSupport
import io.github.peerless2012.ass.media.parser.AssSubtitleParserFactory
import io.github.peerless2012.ass.media.type.AssRenderType
import kotlin.math.roundToInt

@OptIn(ExperimentalApi::class)
private class MoonfinRenderersFactory(
    context: Context,
) : DefaultRenderersFactory(context) {
    override fun buildVideoRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        eventHandler: Handler,
        eventListener: VideoRendererEventListener,
        allowedVideoJoiningTimeMs: Long,
        out: ArrayList<Renderer>,
    ) {
        var videoRendererBuilder =
            MediaCodecVideoRenderer
                .Builder(context)
                .setCodecAdapterFactory(codecAdapterFactory)
                .setMediaCodecSelector(mediaCodecSelector)
                .setAllowedJoiningTimeMs(allowedVideoJoiningTimeMs)
                .setEnableDecoderFallback(enableDecoderFallback)
                .setEventHandler(eventHandler)
                .setEventListener(eventListener)
                .setMaxDroppedFramesToNotify(MAX_DROPPED_VIDEO_FRAME_COUNT_TO_NOTIFY)

        if (Build.VERSION.SDK_INT >= 34) {
            videoRendererBuilder =
                videoRendererBuilder.experimentalSetEnableMediaCodecBufferDecodeOnlyFlag(
                    false,
                )
        }

        out.add(videoRendererBuilder.build())
    }

    override fun buildAudioRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        audioSink: AudioSink,
        eventHandler: Handler,
        eventListener: AudioRendererEventListener,
        out: ArrayList<Renderer>,
    ) {
        super.buildAudioRenderers(
            context,
            extensionRendererMode,
            FlacWorkaroundMediaCodecSelector(mediaCodecSelector),
            enableDecoderFallback,
            audioSink,
            eventHandler,
            eventListener,
            out,
        )
    }
}

/**
 * Wraps a [MediaCodecSelector] to exclude the Google software FLAC decoders
 * (`c2.android.flac.decoder` and the older `OMX.google.flac.decoder`).
 *
 * Those decoders crash with
 * `DecoderInputBuffer$InsufficientCapacityException: Buffer too small (32768 < N)`
 * on many 16-bit FLAC streams because the Media3 FLAC extractor underestimates
 * the maximum frame size. By filtering them out we allow Media3 to fall through
 * to the bundled `FfmpegAudioRenderer`, which decodes FLAC correctly. All other
 * audio mime types (AAC, AC3, E-AC3, TrueHD, DTS, ...) are passed through
 * untouched so hardware decode and passthrough to AVRs are preserved.
 */
private class FlacWorkaroundMediaCodecSelector(
    private val delegate: MediaCodecSelector,
) : MediaCodecSelector {
    override fun getDecoderInfos(
        mimeType: String,
        requiresSecureDecoder: Boolean,
        requiresTunnelingDecoder: Boolean,
    ): List<MediaCodecInfo> {
        val infos = delegate.getDecoderInfos(
            mimeType,
            requiresSecureDecoder,
            requiresTunnelingDecoder,
        )
        if (mimeType.equals(MimeTypes.AUDIO_FLAC, ignoreCase = true)) {
            return infos.filterNot { info -> isBuggyFlacDecoder(info.name) }
        }
        return infos
    }

    private fun isBuggyFlacDecoder(name: String): Boolean =
        name.equals("c2.android.flac.decoder", ignoreCase = true) ||
            name.equals("OMX.google.flac.decoder", ignoreCase = true)
}

@UnstableApi
class Media3VideoView(
    private val context: Context,
) : PlatformView, MethodChannel.MethodCallHandler {
    companion object {
        private const val TS_SEARCH_BYTES_LOW_RAM = TsExtractor.TS_PACKET_SIZE * 1800
        private const val TS_SEARCH_BYTES_DEFAULT = TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES
    }

    private fun DefaultExtractorsFactory.setTsPayloadReaderFactoryFlagsCompat(
        flags: Int,
    ): DefaultExtractorsFactory {
        try {
            DefaultExtractorsFactory::class.java
                .getMethod(
                    "setTsExtractorPayloadReaderFactoryFlags",
                    Int::class.javaPrimitiveType,
                )
                .invoke(this, flags)
            return this
        } catch (_: Throwable) {
        }

        try {
            DefaultExtractorsFactory::class.java
                .getMethod("setTsExtractorFlags", Int::class.javaPrimitiveType)
                .invoke(this, flags)
        } catch (_: Throwable) {
        }

        return this
    }


    private enum class SubtitleRendererMode(
        val wireValue: String,
    ) {
        NATIVE("native"),
        ASS_OVERLAY("assOverlay"),
        ;

        companion object {
            fun fromWire(value: String?): SubtitleRendererMode {
                return entries.firstOrNull { it.wireValue == value } ?: NATIVE
            }
        }
    }

    private data class TrackEntry(
        val group: TrackGroup,
        val trackIndex: Int,
    )

    private enum class ZoomMode(
        val wireValue: String,
    ) {
        FIT("fit"),
        CROP("crop"),
        STRETCH("stretch"),
        ;

        companion object {
            fun fromWire(value: String?): ZoomMode {
                return entries.firstOrNull { it.wireValue == value } ?: FIT
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val useSurfaceView = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
    private val videoView: View = if (useSurfaceView) {
        SurfaceView(context)
    } else {
        TextureView(context)
    }
    private val firstFrameCover = View(context).apply {
        setBackgroundColor(Color.BLACK)
    }
    private val subtitleView = SubtitleView(context)
    private val subtitleTypeface: Typeface? by lazy {
        loadSubtitleTypeface(
            "flutter_assets/assets/fonts/NotoSansCJK-Regular.ttc",
            "flutter_assets/assets/fonts/NotoSans-Regular.ttf",
        )
    }
    private val containerView: FrameLayout = FrameLayout(context).also { container ->
        container.setBackgroundColor(Color.BLACK)
        val videoLayoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
            Gravity.CENTER,
        )
        val subtitleLayoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
        container.addView(videoView, videoLayoutParams)
        container.addView(firstFrameCover, subtitleLayoutParams)
        container.addView(subtitleView, subtitleLayoutParams)
    }
    private val trackSelector = DefaultTrackSelector(context)
    private val audioPipeline = ExoPlayerAudioPipeline()
    private val audioAttributeState = AudioAttributeState()
    private var preferFfmpegDecoder = Media3Bridge.preferFfmpegDecoderEnabled()
    private var decoderPreferenceDirty = false

    private var player: ExoPlayer

    private var ticker: Runnable? = null
    private var currentUrl: String? = null
    private var currentHeaders: Map<String, String> = emptyMap()
    private lateinit var httpDataSourceFactory: DefaultHttpDataSource.Factory
    private var requestedSubtitleRendererMode: SubtitleRendererMode = SubtitleRendererMode.NATIVE
    private var activeSubtitleRendererMode: SubtitleRendererMode = SubtitleRendererMode.NATIVE
    private var selectedSubtitleCodec: String? = null
    private var selectedSubtitleIsExternal = false
    private var selectedSubtitleIsBitmap = false
    private var selectedExternalSubtitleUrl: String? = null
    private var subtitleTrackEnabled = false
    private var zoomMode = ZoomMode.FIT
    private var videoWidthPx = 0
    private var videoHeightPx = 0
    private var videoPixelRatio = 1f
    private var currentNormalizationGainDb: Float? = null
    private var currentContainer: String? = null
    private var currentVideoRangeType: String? = null
    private var currentMediaType: String = "video"
    private var audioOffloadDisabled = false
    private var audioOffloadRetryAttemptedForCurrentSource = false
    private var sessionTunnelingDisabled = Media3Bridge.sessionTunnelingDisabledEnabled()
    private var isDisposed = false
    private var firstFrameRendered = false
    private var lastStateLogAtMs = 0L
    private var lastStateLogSignature = ""
    private val externalSubtitleConfigurations = mutableListOf<MediaItem.SubtitleConfiguration>()

    private fun shouldLogStateSnapshot(): Boolean {
        val signature = "${player.isPlaying}|${player.playbackState}|${player.currentPosition}|${player.duration}|${player.bufferedPosition}|${player.playWhenReady}"
        val nowMs = System.currentTimeMillis()
        if (signature != lastStateLogSignature || nowMs - lastStateLogAtMs >= 1000L) {
            lastStateLogSignature = signature
            lastStateLogAtMs = nowMs
            return true
        }
        return false
    }

    private val listener = object : Player.Listener {
        @Suppress("DEPRECATION")
        override fun onCues(cues: List<Cue>) {
            mainHandler.post {
                subtitleView.setCues(cues)
            }
        }

        override fun onCues(cueGroup: CueGroup) {
            mainHandler.post {
                subtitleView.setCues(cueGroup.cues)
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (
                playbackState == Player.STATE_READY &&
                !firstFrameRendered &&
                firstFrameCover.visibility == View.VISIBLE &&
                videoWidthPx > 0 &&
                videoHeightPx > 0
            ) {
                revealVideo()
            }
            emitState()
            if (playbackState == Player.STATE_ENDED) {
                Media3Bridge.emitEvent(
                    mapOf(
                        "event" to "completed",
                        "completed" to true,
                    ),
                )
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            emitState()
        }

        override fun onPlayerError(error: PlaybackException) {
            val offloadRetryTriggered = retryAudioWithoutOffloadIfNeeded(error)
            emitRecoverablePlayerError(error, offloadRetryTriggered)
            Media3Bridge.emitEvent(
                mapOf(
                    "event" to "error",
                    "message" to (error.localizedMessage ?: "Unknown Media3 playback error"),
                ),
            )
            emitState()
        }

        override fun onTracksChanged(tracks: androidx.media3.common.Tracks) {
            emitTracksChanged()
            emitState()
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            videoWidthPx = videoSize.width
            videoHeightPx = videoSize.height
            videoPixelRatio = videoSize.pixelWidthHeightRatio
            applyVideoLayout()
            Media3Bridge.emitEvent(
                mapOf(
                    "event" to "videoSizeChanged",
                    "width" to videoSize.width,
                    "height" to videoSize.height,
                    "pixelWidthHeightRatio" to videoSize.pixelWidthHeightRatio,
                ),
            )
        }

        override fun onAudioSessionIdChanged(audioSessionId: Int) {
            audioPipeline.setAudioSessionId(audioSessionId)
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            audioPipeline.normalizationGainDb = currentNormalizationGainDb
        }

        override fun onRenderedFirstFrame() {
            revealVideo()
        }
    }

    private val analyticsListener = object : AnalyticsListener {
        override fun onAudioSinkError(
            eventTime: AnalyticsListener.EventTime,
            audioSinkError: Exception,
        ) {
            val message = audioSinkError.message?.lowercase() ?: ""
            val isDiscontinuityError =
                audioSinkError is AudioSink.UnexpectedDiscontinuityException ||
                    message.contains("discontinuity") ||
                    message.contains("discontinu")
            if (isDiscontinuityError) {
                Media3Bridge.emitEvent(
                    mapOf(
                        "event" to "tunnelingDiscontinuity",
                    ),
                )
            }
        }
    }

    init {
        applyTrackSelectorForCurrentSource()

        player = createPlayer()

        containerView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            applyVideoLayout()
        }

        refreshSubtitleRendererMode()

        startTicker()
        Media3Bridge.attachView(this)
    }

    override fun getView(): View = containerView

    override fun dispose() {
        isDisposed = true
        stopTicker()
        player.removeListener(listener)
        player.removeAnalyticsListener(analyticsListener)
        audioPipeline.release()
        player.clearVideoSurface()
        player.release()
        Media3Bridge.detachView(this)
    }

    private fun createPlayer(): ExoPlayer {
        val renderersFactory = MoonfinRenderersFactory(context).apply {
            setEnableDecoderFallback(true)
            setExtensionRendererMode(extensionRendererModeForCurrentPreference())
        }

        val isLowRamDevice = context.getSystemService<ActivityManager>()?.isLowRamDevice == true
        val extractorsFactory = DefaultExtractorsFactory()
            .setTsExtractorMode(TsExtractor.MODE_SINGLE_PMT)
            .setTsPayloadReaderFactoryFlagsCompat(DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES)
            .setTsExtractorTimestampSearchBytes(
                if (isLowRamDevice) TS_SEARCH_BYTES_LOW_RAM else TS_SEARCH_BYTES_DEFAULT,
            )
            .setConstantBitrateSeekingEnabled(true)
            .setConstantBitrateSeekingAlwaysEnabled(true)

        httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
        val bootDataSourceFactory = DefaultDataSource.Factory(context, httpDataSourceFactory)
        val assHandler = AssHandler(AssRenderType.CUES)
        val assParserFactory = AssSubtitleParserFactory(assHandler)
        val bootMediaSourceFactory = DefaultMediaSourceFactory(
            bootDataSourceFactory,
            extractorsFactory.withAssMkvSupport(assParserFactory, assHandler),
        ).apply {
            setSubtitleParserFactory(assParserFactory)
        }

        return ExoPlayer.Builder(context, renderersFactory.withAssSupport(assHandler))
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(bootMediaSourceFactory)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setPauseAtEndOfMediaItems(true)
            .build()
            .also {
                assHandler.init(it)
                if (useSurfaceView) {
                    it.setVideoSurfaceView(videoView as SurfaceView)
                } else {
                    it.setVideoTextureView(videoView as TextureView)
                }
                it.addListener(listener)
                it.addAnalyticsListener(analyticsListener)
            }
    }

    private fun rebuildPlayerForDecoderPreference() {
        player.removeListener(listener)
        player.removeAnalyticsListener(analyticsListener)
        player.clearVideoSurface()
        player.release()
        player = createPlayer()
        httpDataSourceFactory.setDefaultRequestProperties(currentHeaders)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        handleControlCall(call, result)
    }

    fun handleControlCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "setSource" -> {
                    setSource(call.arguments)
                    result.success(null)
                }

                "play" -> {
                    player.playWhenReady = true
                    player.play()
                    emitState()
                    result.success(null)
                }

                "pause" -> {
                    player.pause()
                    emitState()
                    result.success(null)
                }

                "stop" -> {
                    player.pause()
                    player.seekTo(0)
                    firstFrameCover.visibility = View.VISIBLE
                    emitState()
                    result.success(null)
                }

                "seek" -> {
                    val positionMs = when (val args = call.arguments) {
                        is Number -> args.toLong()
                        is Map<*, *> -> (args["positionMs"] as? Number)?.toLong() ?: 0L
                        else -> 0L
                    }
                    player.seekTo(positionMs)
                    emitState()
                    result.success(null)
                }

                "setVolume" -> {
                    val volumePercent = when (val args = call.arguments) {
                        is Number -> args.toFloat()
                        is Map<*, *> -> (args["volume"] as? Number)?.toFloat() ?: 100f
                        else -> 100f
                    }
                    player.volume = (volumePercent / 100f).coerceIn(0f, 1f)
                    result.success(null)
                }

                "setSpeed" -> {
                    val speed = when (val args = call.arguments) {
                        is Number -> args.toFloat()
                        is Map<*, *> -> (args["speed"] as? Number)?.toFloat() ?: 1f
                        else -> 1f
                    }
                    player.playbackParameters = PlaybackParameters(speed)
                    emitState()
                    result.success(null)
                }

                "setZoomMode" -> {
                    updateZoomMode(call.arguments)
                    result.success(null)
                }

                "setAudioTrack" -> {
                    val index = ((call.arguments as? Map<*, *>)?.get("index") as? Number)?.toInt() ?: 0
                    selectTrack(C.TRACK_TYPE_AUDIO, index)
                    result.success(null)
                }

                "setSubtitleTrack" -> {
                    val args = call.arguments as? Map<*, *>
                    val index = (args?.get("index") as? Number)?.toInt() ?: 0
                    val codec = args?.get("codec")?.toString()
                    val isExternal = args?.get("isExternalSubtitle") as? Boolean ?: false
                    val isBitmap = args?.get("isBitmapSubtitle") as? Boolean ?: false
                    val externalUrl = args?.get("externalSubtitleUrl")?.toString()
                    val selected = selectTrack(C.TRACK_TYPE_TEXT, index)
                    if (selected) {
                        selectedSubtitleCodec = codec?.trim()?.lowercase()
                        selectedSubtitleIsExternal = isExternal
                        selectedSubtitleIsBitmap = isBitmap
                        selectedExternalSubtitleUrl = externalUrl?.takeIf { it.isNotBlank() }
                        subtitleTrackEnabled = true
                        applyTrackSelectorForCurrentSource()
                        refreshSubtitleRendererMode()
                    }
                    result.success(null)
                }

                "disableSubtitleTrack" -> {
                    trackSelector.parameters = trackSelector.parameters
                        .buildUpon()
                        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                        .build()
                    selectedSubtitleCodec = null
                    selectedSubtitleIsExternal = false
                    selectedSubtitleIsBitmap = false
                    selectedExternalSubtitleUrl = null
                    subtitleTrackEnabled = false
                    applyTrackSelectorForCurrentSource()
                    clearAssSubtitleScript()
                    refreshSubtitleRendererMode()
                    emitTracksChanged()
                    emitState()
                    result.success(null)
                }

                "setSubtitleRendererMode" -> {
                    updateSubtitleRendererMode(call.arguments)
                    result.success(null)
                }

                "setDecoderPreferences" -> {
                    updateDecoderPreferences(call.arguments)
                    result.success(null)
                }

                "disableTunnelingForSession" -> {
                    disableTunnelingForSession()
                    result.success(null)
                }

                "addExternalSubtitle" -> {
                    addExternalSubtitle(call.arguments as? Map<*, *>)
                    result.success(null)
                }

                "configureSubtitleStyle" -> {
                    configureSubtitleStyle(call.arguments as? Map<*, *>)
                    result.success(null)
                }

                "getState" -> {
                    result.success(stateMap())
                }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("MEDIA3_VIEW_ERROR", t.localizedMessage ?: "Unknown error", null)
        }
    }

    fun handleQueuedCall(method: String, args: Any?) {
        try {
            when (method) {
                "setSource" -> setSource(args)
                "play" -> {
                    player.playWhenReady = true
                    player.play()
                    emitState()
                }

                "pause" -> {
                    player.pause()
                    emitState()
                }

                "stop" -> {
                    player.pause()
                    player.seekTo(0)
                    firstFrameCover.visibility = View.VISIBLE
                    emitState()
                }

                "seek" -> {
                    val positionMs = when (args) {
                        is Number -> args.toLong()
                        is Map<*, *> -> (args["positionMs"] as? Number)?.toLong() ?: 0L
                        else -> 0L
                    }
                    player.seekTo(positionMs)
                    emitState()
                }

                "setVolume" -> {
                    val volumePercent = when (args) {
                        is Number -> args.toFloat()
                        is Map<*, *> -> (args["volume"] as? Number)?.toFloat() ?: 100f
                        else -> 100f
                    }
                    player.volume = (volumePercent / 100f).coerceIn(0f, 1f)
                }

                "setSpeed" -> {
                    val speed = when (args) {
                        is Number -> args.toFloat()
                        is Map<*, *> -> (args["speed"] as? Number)?.toFloat() ?: 1f
                        else -> 1f
                    }
                    player.playbackParameters = PlaybackParameters(speed)
                    emitState()
                }

                "setZoomMode" -> {
                    updateZoomMode(args)
                }

                "setAudioTrack" -> {
                    val index = (args as? Map<*, *>)?.get("index") as? Number ?: return
                    selectTrack(C.TRACK_TYPE_AUDIO, index.toInt())
                }

                "setSubtitleTrack" -> {
                    val subtitleArgs = args as? Map<*, *> ?: return
                    val index = subtitleArgs["index"] as? Number ?: return
                    val codec = subtitleArgs["codec"]?.toString()
                    val isExternal = subtitleArgs["isExternalSubtitle"] as? Boolean ?: false
                    val isBitmap = subtitleArgs["isBitmapSubtitle"] as? Boolean ?: false
                    val externalUrl = subtitleArgs["externalSubtitleUrl"]?.toString()
                    val selected = selectTrack(C.TRACK_TYPE_TEXT, index.toInt())
                    if (selected) {
                        selectedSubtitleCodec = codec?.trim()?.lowercase()
                        selectedSubtitleIsExternal = isExternal
                        selectedSubtitleIsBitmap = isBitmap
                        selectedExternalSubtitleUrl = externalUrl?.takeIf { it.isNotBlank() }
                        subtitleTrackEnabled = true
                        applyTrackSelectorForCurrentSource()
                        refreshSubtitleRendererMode()
                    }
                }

                "disableSubtitleTrack" -> {
                    trackSelector.parameters = trackSelector.parameters
                        .buildUpon()
                        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                        .build()
                    selectedSubtitleCodec = null
                    selectedSubtitleIsExternal = false
                    selectedSubtitleIsBitmap = false
                    selectedExternalSubtitleUrl = null
                    subtitleTrackEnabled = false
                    applyTrackSelectorForCurrentSource()
                    clearAssSubtitleScript()
                    refreshSubtitleRendererMode()
                    emitTracksChanged()
                    emitState()
                }

                "setSubtitleRendererMode" -> {
                    updateSubtitleRendererMode(args)
                }

                "disableTunnelingForSession" -> {
                    disableTunnelingForSession()
                }

                "addExternalSubtitle" -> addExternalSubtitle(args as? Map<*, *>)
                "configureSubtitleStyle" -> configureSubtitleStyle(args as? Map<*, *>)
            }
        } catch (_: Throwable) {
        }
    }

    fun stateSnapshot(): Map<String, Any> = stateMap()

    fun trackSnapshot(): Map<String, Any?> = trackStateMap()

    private fun setSource(arguments: Any?) {
        val args = arguments as? Map<*, *> ?: return
        val url = args["url"]?.toString() ?: return
        val startPositionMs = (args["startPositionMs"] as? Number)?.toLong() ?: 0L
        val autoPlay = args["autoPlay"] as? Boolean ?: false

        if (decoderPreferenceDirty) {
            rebuildPlayerForDecoderPreference()
            decoderPreferenceDirty = false
        }

        currentContainer = args["container"]
            ?.toString()
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
        currentVideoRangeType = args["videoRangeType"]
            ?.toString()
            ?.trim()
            ?.uppercase()
            ?.takeIf { it.isNotEmpty() }
        currentMediaType = args["mediaType"]?.toString()?.lowercase() ?: "video"
        audioOffloadRetryAttemptedForCurrentSource = false
        currentNormalizationGainDb = (args["normalizationGainDb"] as? Number)?.toFloat()

        currentUrl = url
        currentHeaders = (args["headers"] as? Map<*, *>)
            ?.mapNotNull { (k, v) ->
                if (k == null || v == null) {
                    null
                } else {
                    k.toString() to v.toString()
                }
            }
            ?.toMap()
            ?: emptyMap()
        httpDataSourceFactory.setDefaultRequestProperties(currentHeaders)

        resetTrackSelectionsForNewSource()
        externalSubtitleConfigurations.clear()
        selectedSubtitleCodec = null
        selectedSubtitleIsExternal = false
        selectedSubtitleIsBitmap = false
        selectedExternalSubtitleUrl = null
        subtitleTrackEnabled = false
        firstFrameRendered = false
        firstFrameCover.visibility = View.VISIBLE
        clearAssSubtitleScript()
        applyTrackSelectorForCurrentSource()
        refreshSubtitleRendererMode()
        applyAudioAttributesForCurrentMediaType()
        audioPipeline.normalizationGainDb = currentNormalizationGainDb
        setMediaItem(startPositionMs, playWhenReady = autoPlay)
    }

    private fun revealVideo() {
        if (firstFrameRendered) {
            return
        }
        firstFrameRendered = true
        firstFrameCover.visibility = View.GONE
    }

    private fun resetTrackSelectionsForNewSource() {
        trackSelector.parameters = trackSelector.parameters
            .buildUpon()
            .clearOverrides()
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .build()
    }

    private fun applyAudioAttributesForCurrentMediaType() {
        val contentType = if (currentMediaType == "audio") {
            C.AUDIO_CONTENT_TYPE_MUSIC
        } else {
            C.AUDIO_CONTENT_TYPE_MOVIE
        }

        audioAttributeState.updateAudioAttributes(
            builder = {
                setContentType(contentType)
                setUsage(C.USAGE_MEDIA)
            },
            onChange = { audioAttributes ->
                player.setAudioAttributes(audioAttributes, true)
            },
        )
    }

    private fun applyTrackSelectorForCurrentSource() {
        val isAudioContent = currentMediaType == "audio"
        val hasExternalSubtitle = selectedSubtitleIsExternal ||
            !selectedExternalSubtitleUrl.isNullOrBlank() ||
            externalSubtitleConfigurations.isNotEmpty()
        val shouldEnableTunneling =
            !isAudioContent &&
                !hasExternalSubtitle &&
                !sessionTunnelingDisabled &&
                isHdrLikeRangeType(currentVideoRangeType)

        val offloadMode = if (isAudioContent && !audioOffloadDisabled) {
            TrackSelectionParameters.AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED
        } else {
            TrackSelectionParameters.AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_DISABLED
        }

        trackSelector.setParameters(
            trackSelector.buildUponParameters()
                .setAudioOffloadPreferences(
                    TrackSelectionParameters.AudioOffloadPreferences.DEFAULT
                        .buildUpon()
                        .setAudioOffloadMode(offloadMode)
                        .build(),
                )
                .setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
                .setTunnelingEnabled(shouldEnableTunneling),
        )
    }

    private fun updateSubtitleRendererMode(arguments: Any?) {
        val args = arguments as? Map<*, *>
        val modeValue = args?.get("mode")?.toString()
        val nextMode = SubtitleRendererMode.fromWire(modeValue)
        if (requestedSubtitleRendererMode == nextMode) {
            return
        }

        requestedSubtitleRendererMode = nextMode
        refreshSubtitleRendererMode()
    }

    private fun updateDecoderPreferences(arguments: Any?) {
        val args = arguments as? Map<*, *> ?: return

        val nextPreference = args["preferFfmpeg"] as? Boolean
        if (nextPreference != null && preferFfmpegDecoder != nextPreference) {
            preferFfmpegDecoder = nextPreference
            decoderPreferenceDirty = true
        }

        val nextTunnelingDisabled = args["tunnelingDisabled"] as? Boolean
        if (nextTunnelingDisabled != null && sessionTunnelingDisabled != nextTunnelingDisabled) {
            sessionTunnelingDisabled = nextTunnelingDisabled
            Media3Bridge.setSessionTunnelingDisabledEnabled(nextTunnelingDisabled)
            applyTrackSelectorForCurrentSource()
        }
    }

    private fun disableTunnelingForSession() {
        if (sessionTunnelingDisabled) {
            return
        }
        sessionTunnelingDisabled = true
        Media3Bridge.setSessionTunnelingDisabledEnabled(true)
        applyTrackSelectorForCurrentSource()
    }

    private fun extensionRendererModeForCurrentPreference(): Int =
        if (preferFfmpegDecoder) DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
        else DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON

    private fun updateZoomMode(arguments: Any?) {
        val args = arguments as? Map<*, *>
        val modeValue = args?.get("mode")?.toString()
        val nextMode = ZoomMode.fromWire(modeValue)
        if (zoomMode == nextMode) {
            return
        }

        zoomMode = nextMode
        applyVideoLayout()
    }

    private fun applyVideoLayout() {
        val currentParams = videoView.layoutParams as? FrameLayout.LayoutParams
        val layoutParams = currentParams ?: FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
            Gravity.CENTER,
        )

        if (zoomMode == ZoomMode.STRETCH) {
            updateVideoLayoutParams(
                layoutParams = layoutParams,
                width = FrameLayout.LayoutParams.MATCH_PARENT,
                height = FrameLayout.LayoutParams.MATCH_PARENT,
            )
            return
        }

        val containerWidth = containerView.width
        val containerHeight = containerView.height
        val sourceWidth = videoWidthPx.toFloat() * videoPixelRatio
        val sourceHeight = videoHeightPx.toFloat()
        if (containerWidth <= 0 || containerHeight <= 0 || sourceWidth <= 0f || sourceHeight <= 0f) {
            updateVideoLayoutParams(
                layoutParams = layoutParams,
                width = FrameLayout.LayoutParams.MATCH_PARENT,
                height = FrameLayout.LayoutParams.MATCH_PARENT,
            )
            return
        }

        val containerAspect = containerWidth.toFloat() / containerHeight.toFloat()
        val sourceAspect = sourceWidth / sourceHeight
        val targetSize = when (zoomMode) {
            ZoomMode.FIT -> {
                if (containerAspect > sourceAspect) {
                    val targetHeight = containerHeight
                    val targetWidth = (targetHeight * sourceAspect).roundToInt()
                    targetWidth to targetHeight
                } else {
                    val targetWidth = containerWidth
                    val targetHeight = (targetWidth / sourceAspect).roundToInt()
                    targetWidth to targetHeight
                }
            }

            ZoomMode.CROP -> {
                if (containerAspect > sourceAspect) {
                    val targetWidth = containerWidth
                    val targetHeight = (targetWidth / sourceAspect).roundToInt()
                    targetWidth to targetHeight
                } else {
                    val targetHeight = containerHeight
                    val targetWidth = (targetHeight * sourceAspect).roundToInt()
                    targetWidth to targetHeight
                }
            }

            ZoomMode.STRETCH -> FrameLayout.LayoutParams.MATCH_PARENT to FrameLayout.LayoutParams.MATCH_PARENT
        }

        updateVideoLayoutParams(
            layoutParams = layoutParams,
            width = targetSize.first.coerceAtLeast(1),
            height = targetSize.second.coerceAtLeast(1),
        )
    }

    private fun updateVideoLayoutParams(
        layoutParams: FrameLayout.LayoutParams,
        width: Int,
        height: Int,
    ) {
        if (
            layoutParams.width == width &&
            layoutParams.height == height &&
            layoutParams.gravity == Gravity.CENTER
        ) {
            return
        }

        layoutParams.width = width
        layoutParams.height = height
        layoutParams.gravity = Gravity.CENTER
        videoView.layoutParams = layoutParams
    }

    private fun applySubtitleRendererMode(mode: SubtitleRendererMode) {
        when (mode) {
            SubtitleRendererMode.NATIVE,
            SubtitleRendererMode.ASS_OVERLAY,
            -> {
                subtitleView.visibility = View.VISIBLE
                subtitleView.setApplyEmbeddedStyles(true)
                subtitleView.setApplyEmbeddedFontSizes(true)
            }
        }
    }

    private fun refreshSubtitleRendererMode() {
        val desiredMode = SubtitleRendererMode.NATIVE
        val resolvedMode = SubtitleRendererMode.NATIVE
        val fallbackReason = if (requestedSubtitleRendererMode == SubtitleRendererMode.ASS_OVERLAY) {
            "handledByAssMedia"
        } else {
            null
        }

        val previousActive = activeSubtitleRendererMode
        activeSubtitleRendererMode = resolvedMode

        applySubtitleRendererMode(activeSubtitleRendererMode)

        if (previousActive != activeSubtitleRendererMode || desiredMode != previousActive) {
            emitSubtitleRendererModeChanged(desiredMode)
        }

        if (desiredMode != resolvedMode && !fallbackReason.isNullOrBlank()) {
            emitSubtitleRendererFallback(desiredMode, resolvedMode, fallbackReason)
        }
    }

    private fun emitSubtitleRendererFallback(
        desiredMode: SubtitleRendererMode,
        activeMode: SubtitleRendererMode,
        reason: String,
    ) {
        Media3Bridge.emitEvent(
            mapOf(
                "event" to "subtitleRendererFallback",
                "requestedMode" to requestedSubtitleRendererMode.wireValue,
                "desiredMode" to desiredMode.wireValue,
                "activeMode" to activeMode.wireValue,
                "reason" to reason,
                "codec" to selectedSubtitleCodec,
                "isExternalSubtitle" to selectedSubtitleIsExternal,
                "isBitmapSubtitle" to selectedSubtitleIsBitmap,
            ),
        )
    }

    private fun emitSubtitleRendererModeChanged(desiredMode: SubtitleRendererMode) {
        Media3Bridge.emitEvent(
            mapOf(
                "event" to "subtitleRendererModeChanged",
                "requestedMode" to requestedSubtitleRendererMode.wireValue,
                "desiredMode" to desiredMode.wireValue,
                "activeMode" to activeSubtitleRendererMode.wireValue,
                "usesFallback" to (desiredMode != activeSubtitleRendererMode),
                "codec" to selectedSubtitleCodec,
                "isExternalSubtitle" to selectedSubtitleIsExternal,
                "isBitmapSubtitle" to selectedSubtitleIsBitmap,
            ),
        )
    }

    private fun clearAssSubtitleScript() {
    }

    private fun addExternalSubtitle(args: Map<*, *>?) {
        val url = args?.get("url")?.toString() ?: return
        val codec = args["codec"]?.toString()
        val language = args["language"]?.toString()
        val title = args["title"]?.toString()

        val subtitleBuilder = MediaItem.SubtitleConfiguration.Builder(Uri.parse(url))
            .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)

        val mimeType = codecToMimeType(codec)
        if (!mimeType.isNullOrEmpty()) {
            subtitleBuilder.setMimeType(mimeType)
        }
        if (!language.isNullOrEmpty()) {
            subtitleBuilder.setLanguage(language)
        }
        if (!title.isNullOrEmpty()) {
            subtitleBuilder.setLabel(title)
        }

        externalSubtitleConfigurations.add(subtitleBuilder.build())
        applyTrackSelectorForCurrentSource()

        val playWhenReady = player.playWhenReady
        val currentPosition = player.currentPosition
        setMediaItem(currentPosition, playWhenReady = playWhenReady)
    }

    private fun loadSubtitleTypeface(vararg assetPaths: String): Typeface? {
        for (assetPath in assetPaths) {
            val typeface = runCatching {
                Typeface.createFromAsset(context.assets, assetPath)
            }.getOrNull()
            if (typeface != null) {
                return typeface
            }
        }
        return null
    }

    private fun configureSubtitleStyle(args: Map<*, *>?) {
        val textColor = (args?.get("textColor") as? Number)?.toInt() ?: Color.WHITE
        val bgColor = (args?.get("backgroundColor") as? Number)?.toInt() ?: Color.TRANSPARENT
        val strokeColor = (args?.get("strokeColor") as? Number)?.toInt() ?: Color.TRANSPARENT
        val fontSize = (args?.get("fontSize") as? Number)?.toFloat()
        val verticalOffset = (args?.get("verticalOffset") as? Number)?.toFloat()

        val edgeType = if (strokeColor != Color.TRANSPARENT) {
            CaptionStyleCompat.EDGE_TYPE_OUTLINE
        } else {
            CaptionStyleCompat.EDGE_TYPE_NONE
        }

        subtitleView.setStyle(
            CaptionStyleCompat(
                textColor,
                bgColor,
                Color.TRANSPARENT,
                edgeType,
                strokeColor,
                subtitleTypeface,
            ),
        )

        if (fontSize != null) {
            val fractionalTextSize = (fontSize / 24f) * 0.06f
            subtitleView.setFractionalTextSize(fractionalTextSize.coerceAtLeast(0.01f))
        }

        if (verticalOffset != null) {
            subtitleView.setBottomPaddingFraction(verticalOffset.coerceIn(0f, 0.95f))
        }
    }

    private fun setMediaItem(startPositionMs: Long, playWhenReady: Boolean) {
        val url = currentUrl ?: return

        val subtitleConfigurations = externalSubtitleConfigurations.toList()
        val mediaItemBuilder = MediaItem.Builder()
            .setUri(url)
            .setSubtitleConfigurations(subtitleConfigurations)
        val inferredMimeType = inferStreamMimeType(url, currentContainer, currentMediaType)
        inferredMimeType?.let { mimeType ->
            mediaItemBuilder.setMimeType(mimeType)
        }
        val mediaItem = mediaItemBuilder.build()
        player.setMediaItem(mediaItem, startPositionMs)
        player.prepare()
        if (playWhenReady) {
            player.playWhenReady = true
            player.play()
        } else {
            player.playWhenReady = false
        }
        emitState()
    }

    private fun inferStreamMimeType(url: String, container: String?, mediaType: String?): String? {
        val normalizedMediaType = mediaType?.trim()?.lowercase()
        val containerTokens = container
            ?.split(',', ';', '|', ' ')
            ?.mapNotNull { token -> token.trim().lowercase().takeIf { it.isNotEmpty() } }
            ?: emptyList()
        var resolvedMimeType: String? = null

        for (token in containerTokens) {
            if (token == "hls" || token == "m3u8") {
                resolvedMimeType = MimeTypes.APPLICATION_M3U8
                break
            }
            if (token == "dash" || token == "mpd") {
                resolvedMimeType = MimeTypes.APPLICATION_MPD
                break
            }

            val inferredMimeType = inferAudioMimeType(token, normalizedMediaType)
            if (inferredMimeType != null) {
                resolvedMimeType = inferredMimeType
                break
            }
        }

        if (resolvedMimeType == null) {
            val normalizedUrl = url.lowercase()
            resolvedMimeType = when {
                normalizedUrl.contains(".m3u8") -> MimeTypes.APPLICATION_M3U8
                normalizedUrl.contains(".mpd") -> MimeTypes.APPLICATION_MPD
                normalizedUrl.contains(".flac") -> MimeTypes.AUDIO_FLAC
                normalizedUrl.contains(".mp3") -> MimeTypes.AUDIO_MPEG
                normalizedUrl.contains(".m4a") || normalizedUrl.contains(".aac") -> MimeTypes.AUDIO_AAC
                normalizedUrl.contains(".opus") -> MimeTypes.AUDIO_OPUS
                normalizedUrl.contains(".ogg") || normalizedUrl.contains(".oga") -> MimeTypes.AUDIO_OGG
                normalizedUrl.contains(".wav") || normalizedUrl.contains(".wave") -> MimeTypes.AUDIO_WAV
                normalizedUrl.contains(".ac3") -> MimeTypes.AUDIO_AC3
                normalizedUrl.contains(".eac3") -> MimeTypes.AUDIO_E_AC3
                normalizedUrl.contains(".dts") -> MimeTypes.AUDIO_DTS
                normalizedUrl.contains(".mka") -> MimeTypes.AUDIO_MATROSKA
                else -> null
            }
        }

        return resolvedMimeType
    }

    private fun inferAudioMimeType(containerToken: String, mediaType: String?): String? {
        return when (containerToken) {
            "mp3" -> MimeTypes.AUDIO_MPEG
            "flac" -> MimeTypes.AUDIO_FLAC
            "aac" -> MimeTypes.AUDIO_AAC
            "m4a",
            "m4b",
            -> MimeTypes.AUDIO_AAC

            "mp4" -> if (mediaType == "audio") MimeTypes.AUDIO_AAC else null
            "opus" -> MimeTypes.AUDIO_OPUS
            "ogg",
            "oga",
            -> MimeTypes.AUDIO_OGG

            "wav",
            "wave",
            -> MimeTypes.AUDIO_WAV

            "wma" -> "audio/x-ms-wma"
            "alac" -> "audio/alac"
            "ac3" -> MimeTypes.AUDIO_AC3
            "eac3" -> MimeTypes.AUDIO_E_AC3
            "dts" -> MimeTypes.AUDIO_DTS
            "mka",
            "matroska",
            -> MimeTypes.AUDIO_MATROSKA

            else -> null
        }
    }

    private fun retryAudioWithoutOffloadIfNeeded(error: PlaybackException): Boolean {
        val isAudioContent = currentMediaType == "audio"
        val isRetryableError =
            error.errorCode == PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED ||
                error.errorCode == PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED

        if (!isAudioContent || !isRetryableError || audioOffloadDisabled || audioOffloadRetryAttemptedForCurrentSource) {
            return false
        }

        audioOffloadRetryAttemptedForCurrentSource = true
        val mediaItem = player.currentMediaItem ?: return false
        val retryPositionMs = player.currentPosition.coerceAtLeast(0L)
        val playWhenReady = player.playWhenReady

        audioOffloadDisabled = true
        applyTrackSelectorForCurrentSource()
        player.setMediaItem(mediaItem, retryPositionMs)
        player.prepare()
        player.playWhenReady = playWhenReady
        return true
    }

    private fun isHdrLikeRangeType(videoRangeType: String?): Boolean {
        if (videoRangeType.isNullOrBlank()) {
            return false
        }
        return videoRangeType.contains("HDR") || videoRangeType.contains("DOVI")
    }

    private fun emitRecoverablePlayerError(
        error: PlaybackException,
        audioOffloadRetryTriggered: Boolean,
    ) {
        val recoverableKind = when (error.errorCode) {
            PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED,
            PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
            -> "unsupported_audio"

            else -> null
        }

        if (recoverableKind == null) {
            return
        }

        Media3Bridge.emitEvent(
            mapOf(
                "event" to "playerError",
                "recoverable" to true,
                "kind" to recoverableKind,
                "code" to error.errorCode,
                "message" to (error.localizedMessage ?: ""),
                "audioOffloadRetryTriggered" to audioOffloadRetryTriggered,
            ),
        )
    }

    private fun selectTrack(trackType: Int, oneBasedIndex: Int): Boolean {
        val entries = collectTracks(trackType)
        if (oneBasedIndex <= 0 || oneBasedIndex > entries.size) {
            return false
        }
        val entry = entries[oneBasedIndex - 1]

        return try {
            val override = TrackSelectionOverride(entry.group, listOf(entry.trackIndex))

            trackSelector.parameters = trackSelector.parameters
                .buildUpon()
                .setTrackTypeDisabled(trackType, false)
                .clearOverridesOfType(trackType)
                .addOverride(override)
                .build()

            emitTracksChanged()
            emitState()
            true
        } catch (_: Throwable) {
            emitTracksChanged()
            emitState()
            false
        }
    }

    private fun collectTracks(trackType: Int): List<TrackEntry> {
        val entries = mutableListOf<TrackEntry>()

        for (group in player.currentTracks.groups) {
            if (group.type != trackType) continue
            val mediaTrackGroup = group.mediaTrackGroup
            for (index in 0 until group.length) {
                if (group.isTrackSupported(index)) {
                    entries.add(TrackEntry(mediaTrackGroup, index))
                }
            }
        }

        return entries
    }

    private fun trackCount(trackType: Int): Int = collectTracks(trackType).size

    private fun trackStateMap(): Map<String, Any?> {
        return mapOf(
            "audioTracks" to collectTrackOptions(C.TRACK_TYPE_AUDIO),
            "subtitleTracks" to collectTrackOptions(C.TRACK_TYPE_TEXT),
        )
    }

    private fun collectTrackOptions(trackType: Int): List<Map<String, Any?>> {
        val options = mutableListOf<Map<String, Any?>>()
        var oneBasedIndex = 1

        for (group in player.currentTracks.groups) {
            if (group.type != trackType) continue

            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue

                val format = group.getTrackFormat(trackIndex)
                options.add(
                    mapOf(
                        "index" to oneBasedIndex,
                        "label" to formatTrackLabel(format, trackType, oneBasedIndex),
                        "selected" to group.isTrackSelected(trackIndex),
                        "language" to (format.language ?: ""),
                        "codec" to (format.codecs ?: format.sampleMimeType ?: ""),
                    ),
                )
                oneBasedIndex += 1
            }
        }

        return options
    }

    private fun formatTrackLabel(format: Format, trackType: Int, fallbackIndex: Int): String {
        val explicitLabel = format.label?.trim().orEmpty()
        if (explicitLabel.isNotEmpty()) {
            return explicitLabel
        }

        val language = format.language
            ?.takeIf { it.isNotBlank() && it != "und" }
            ?.replaceFirstChar { it.uppercase() }
        val codec = format.codecs
            ?.takeIf { it.isNotBlank() }
            ?: format.sampleMimeType
                ?.substringAfterLast('.')
                ?.takeIf { it.isNotBlank() }
                ?.uppercase()

        val pieces = listOfNotNull(language, codec)
        if (pieces.isNotEmpty()) {
            return pieces.joinToString(" • ")
        }

        return "${trackTypeLabel(trackType)} $fallbackIndex"
    }

    private fun trackTypeLabel(trackType: Int): String {
        return when (trackType) {
            C.TRACK_TYPE_AUDIO -> "Audio"
            C.TRACK_TYPE_TEXT -> "Subtitle"
            else -> "Track"
        }
    }

    private fun emitTracksChanged() {
        Media3Bridge.emitEvent(
            mapOf(
                "event" to "tracksChanged",
                "audioTrackCount" to trackCount(C.TRACK_TYPE_AUDIO),
                "textTrackCount" to trackCount(C.TRACK_TYPE_TEXT),
                "subtitleRendererMode" to activeSubtitleRendererMode.wireValue,
                "subtitleRendererModeRequested" to requestedSubtitleRendererMode.wireValue,
            ),
        )
    }

    private fun stateMap(): Map<String, Any> {
        val duration = player.duration
        val bufferedPosition = player.bufferedPosition
        val videoSize = player.videoSize
        return mapOf(
            "positionMs" to player.currentPosition,
            "durationMs" to if (duration > 0) duration else 0L,
            "bufferedMs" to if (bufferedPosition > 0) bufferedPosition else 0L,
            "isPlaying" to player.isPlaying,
            "isBuffering" to (player.playbackState == Player.STATE_BUFFERING),
            "playbackSpeed" to player.playbackParameters.speed.toDouble(),
            "videoWidth" to videoSize.width,
            "videoHeight" to videoSize.height,
            "subtitleRendererMode" to activeSubtitleRendererMode.wireValue,
            "subtitleRendererModeRequested" to requestedSubtitleRendererMode.wireValue,
        )
    }

    private fun emitState() {
        if (shouldLogStateSnapshot()) {
        }
        Media3Bridge.emitEvent(
            mapOf(
                "event" to "state",
                "positionMs" to player.currentPosition,
                "durationMs" to if (player.duration > 0) player.duration else 0L,
                "bufferedMs" to if (player.bufferedPosition > 0) player.bufferedPosition else 0L,
                "isPlaying" to player.isPlaying,
                "isBuffering" to (player.playbackState == Player.STATE_BUFFERING),
                "playbackSpeed" to player.playbackParameters.speed.toDouble(),
                "videoWidth" to player.videoSize.width,
                "videoHeight" to player.videoSize.height,
            ),
        )
    }

    private fun startTicker() {
        val runnable = object : Runnable {
            override fun run() {
                emitState()
                mainHandler.postDelayed(this, 250L)
            }
        }
        ticker = runnable
        mainHandler.post(runnable)
    }

    private fun stopTicker() {
        ticker?.let { mainHandler.removeCallbacks(it) }
        ticker = null
    }

    private fun codecToMimeType(codec: String?): String? {
        val normalized = codec?.trim()?.lowercase() ?: return null
        return when (normalized) {
            "ass", "ssa" -> MimeTypes.TEXT_SSA
            "srt", "subrip" -> MimeTypes.APPLICATION_SUBRIP
            "vtt", "webvtt" -> MimeTypes.TEXT_VTT
            "ttml" -> MimeTypes.APPLICATION_TTML
            "pgs", "pgssub", "hdmv_pgs_subtitle" -> MimeTypes.APPLICATION_PGS
            "dvbsub", "dvb_subtitle" -> MimeTypes.APPLICATION_DVBSUBS
            "dvdsub", "dvd_subtitle", "vobsub", "xsub" -> MimeTypes.APPLICATION_VOBSUB
            else -> null
        }
    }
}
