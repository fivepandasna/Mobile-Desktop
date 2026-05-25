import 'audio_capability_profile.dart';
import '../preference/preference_constants.dart';
import '../util/platform_detection.dart';
import 'known_defects.dart';

class DeviceProfileBuilder {
  const DeviceProfileBuilder._();

  static const List<String> _downmixSupportedAudioCodecs = <String>[
    'aac',
    'mp2',
    'mp3',
  ];

  static const List<String> _supportedAudioCodecs = <String>[
    'aac',
    'aac_latm',
    'ac3',
    'alac',
    'dca',
    'dts',
    'eac3',
    'flac',
    'mlp',
    'mp2',
    'mp3',
    'opus',
    'pcm_alaw',
    'pcm_mulaw',
    'pcm_s16le',
    'pcm_s20le',
    'pcm_s24le',
    'truehd',
    'vorbis',
  ];

  static const List<String> _hlsMpegTsAudioCodecs = <String>[
    'aac',
    'ac3',
    'eac3',
    'mp3',
  ];

  static const List<String> _hlsFmp4AudioCodecs = <String>[
    'aac',
    'ac3',
    'eac3',
    'mp3',
    'alac',
    'flac',
    'opus',
    'dts',
    'truehd',
  ];

  static const List<String> _audioDirectPlayContainers = <String>[
    'aac',
    'ac3',
    'alac',
    'ape',
    'dts',
    'eac3',
    'flac',
    'm4a',
    'm4b',
    'mka',
    'mp3',
    'oga',
    'ogg',
    'opus',
    'wav',
    'wma',
  ];

  static Map<String, dynamic> build({
    int? maxBitrateMbps,
    AudioCapabilityProfile? audioCapabilityProfile,
    AudioOutputMode audioOutputMode = AudioOutputMode.auto,
    AudioFallbackCodec audioFallbackCodec = AudioFallbackCodec.auto,
    bool ac3PassthroughEnabled = false,
    bool eac3PassthroughEnabled = false,
    bool eac3JocPassthroughEnabled = false,
    bool dtsCorePassthroughEnabled = false,
    bool dtsHdPassthroughEnabled = false,
    bool trueHdPassthroughEnabled = false,
    bool trueHdAtmosPassthroughEnabled = false,
    bool downMixAudio = false,
    bool audioFallbackToStereoAac = true,
    MaxVideoResolution maxResolution = MaxVideoResolution.auto,
    bool pgsDirectPlay = true,
    bool assDirectPlay = true,
    bool supportsAvc = false,
    bool supportsAvcHigh10 = false,
    int avcMainLevel = 0,
    int avcHigh10Level = 0,
    bool supportsHevc = false,
    bool supportsHevcMain10 = false,
    int hevcMainLevel = 0,
    bool supportsHevcDolbyVision = false,
    bool supportsHevcDolbyVisionEl = false,
    bool supportsHevcHdr10 = false,
    bool supportsHevcHdr10Plus = false,
    bool supportsAv1 = false,
    bool supportsAv1Main10 = false,
    bool supportsAv1DolbyVision = false,
    bool supportsAv1Hdr10 = false,
    bool supportsAv1Hdr10Plus = false,
    bool supportsVc1 = false,
    int maxResolutionAvcWidth = 0,
    int maxResolutionAvcHeight = 0,
    int maxResolutionHevcWidth = 0,
    int maxResolutionHevcHeight = 0,
    int maxResolutionAv1Width = 0,
    int maxResolutionAv1Height = 0,
    int maxResolutionVc1Width = 0,
    int maxResolutionVc1Height = 0,
    bool supportsDvProfile5 = false,
    bool supportsDvProfile7 = false,
    bool supportsDvProfile8 = false,
    bool knownHevcDoviHdr10PlusBug = false,
    bool allowDolbyVisionProfile7ElDirectPlay = false,
  }) {
    final bitrateBps = maxBitrateMbps == null ? null : maxBitrateMbps * 1000000;
    final capabilityProfile =
        audioCapabilityProfile ?? const AudioCapabilityProfile.optimistic();
    final forceStereo = _isForceStereo(
      audioOutputMode: audioOutputMode,
      legacyDownMixAudio: downMixAudio,
    );
    final effectiveAudioFallbackCodec = _resolveAudioFallbackCodec(
      requested: audioFallbackCodec,
      legacyStereoAacFallback: audioFallbackToStereoAac,
      capabilityProfile: capabilityProfile,
      forceStereo: forceStereo,
    );

    final allowedAudioCodecs = forceStereo
        ? _downmixSupportedAudioCodecs
        : _supportedAudioCodecs
              .where(
                (codec) => _isAudioCodecAllowed(
                  codec: codec,
                  capabilityProfile: capabilityProfile,
                  ac3PassthroughEnabled: ac3PassthroughEnabled,
                  eac3PassthroughEnabled: eac3PassthroughEnabled,
                  eac3JocPassthroughEnabled: eac3JocPassthroughEnabled,
                  dtsCorePassthroughEnabled: dtsCorePassthroughEnabled,
                  dtsHdPassthroughEnabled: dtsHdPassthroughEnabled,
                  trueHdPassthroughEnabled: trueHdPassthroughEnabled,
                  trueHdAtmosPassthroughEnabled: trueHdAtmosPassthroughEnabled,
                ),
              )
              .toList(growable: false);

    final mpegTsAudioCodecs = _mpegTsAudioCodecsForFallback(
      effectiveAudioFallbackCodec: effectiveAudioFallbackCodec,
      allowedAudioCodecs: allowedAudioCodecs,
    );

    final hlsVideoCodecs = <String>[
      if (supportsHevc) 'hevc',
      'h264',
    ].join(',');

    final hasKnownHevcDoviHdr10PlusBug =
        knownHevcDoviHdr10PlusBug || KnownDefects.hevcDoviHdr10PlusBug;

    final codecProfiles = _codecProfiles(
      downMixAudio: forceStereo,
      audioFallbackToStereoAac:
          effectiveAudioFallbackCodec == AudioFallbackCodec.aacStereo,
      maxResolution: maxResolution,
      supportsAvc: supportsAvc,
      supportsAvcHigh10: supportsAvcHigh10,
      avcMainLevel: avcMainLevel,
      avcHigh10Level: avcHigh10Level,
      supportsHevc: supportsHevc,
      supportsHevcMain10: supportsHevcMain10,
      hevcMainLevel: hevcMainLevel,
      supportsHevcDolbyVision: supportsHevcDolbyVision,
      supportsHevcDolbyVisionEl: supportsHevcDolbyVisionEl,
      supportsHevcHdr10: supportsHevcHdr10,
      supportsHevcHdr10Plus: supportsHevcHdr10Plus,
      supportsAv1: supportsAv1,
      supportsAv1Main10: supportsAv1Main10,
      supportsAv1DolbyVision: supportsAv1DolbyVision,
      supportsAv1Hdr10: supportsAv1Hdr10,
      supportsAv1Hdr10Plus: supportsAv1Hdr10Plus,
      supportsVc1: supportsVc1,
      maxResolutionAvcWidth: maxResolutionAvcWidth,
      maxResolutionAvcHeight: maxResolutionAvcHeight,
      maxResolutionHevcWidth: maxResolutionHevcWidth,
      maxResolutionHevcHeight: maxResolutionHevcHeight,
      maxResolutionAv1Width: maxResolutionAv1Width,
      maxResolutionAv1Height: maxResolutionAv1Height,
      maxResolutionVc1Width: maxResolutionVc1Width,
      maxResolutionVc1Height: maxResolutionVc1Height,
      supportsDvProfile5: supportsDvProfile5,
      supportsDvProfile7: supportsDvProfile7,
      supportsDvProfile8: supportsDvProfile8,
      knownHevcDoviHdr10PlusBug: hasKnownHevcDoviHdr10PlusBug,
      allowDolbyVisionProfile7ElDirectPlay:
          allowDolbyVisionProfile7ElDirectPlay,
    );

    return <String, dynamic>{
      'Name': _profileName(),
      'MaxStaticBitrate': bitrateBps,
      'MaxStreamingBitrate': bitrateBps,
      'MusicStreamingTranscodingBitrate': 384000,
      'DirectPlayProfiles': <Map<String, dynamic>>[
        <String, dynamic>{
          'Type': 'Video',
          'Container':
              'asf,dash,hls,m4v,mkv,mov,mp4,ogm,ogv,ts,vob,webm,wmv,xvid',
          'VideoCodec': 'av1,h264,hevc,mpeg,mpeg2video,vc1,vp8,vp9',
          'AudioCodec': allowedAudioCodecs.join(','),
        },
        <String, dynamic>{
          'Type': 'Audio',
          'Container': _audioDirectPlayContainers.join(','),
          'AudioCodec': allowedAudioCodecs.join(','),
        },
      ],
      'TranscodingProfiles': <Map<String, dynamic>>[
        <String, dynamic>{
          'Type': 'Video',
          'Context': 'Streaming',
          'Container': 'ts',
          'Protocol': 'hls',
          'VideoCodec': hlsVideoCodecs,
          'AudioCodec': mpegTsAudioCodecs.join(','),
          'CopyTimestamps': false,
          'EnableSubtitlesInManifest': true,
        },
        <String, dynamic>{
          'Type': 'Video',
          'Context': 'Streaming',
          'Container': 'mp4',
          'Protocol': 'hls',
          'VideoCodec': hlsVideoCodecs,
          'AudioCodec': _hlsFmp4AudioCodecs
              .where(allowedAudioCodecs.contains)
              .join(','),
          'CopyTimestamps': false,
          'EnableSubtitlesInManifest': true,
        },
        <String, dynamic>{
          'Type': 'Audio',
          'Context': 'Streaming',
          'Container': 'ts',
          'Protocol': 'hls',
          'AudioCodec': 'aac',
        },
      ],
      'ContainerProfiles': <Map<String, dynamic>>[],
      'CodecProfiles': codecProfiles,
      'SubtitleProfiles': _subtitleProfiles(
        pgsDirectPlay: pgsDirectPlay,
        assDirectPlay: assDirectPlay,
      ),
    };
  }

  static bool _isForceStereo({
    required AudioOutputMode audioOutputMode,
    required bool legacyDownMixAudio,
  }) {
    switch (audioOutputMode) {
      case AudioOutputMode.forceStereo:
        return true;
      case AudioOutputMode.avrPassthrough:
        return false;
      case AudioOutputMode.auto:
        return legacyDownMixAudio;
    }
  }

  static AudioFallbackCodec _resolveAudioFallbackCodec({
    required AudioFallbackCodec requested,
    required bool legacyStereoAacFallback,
    required AudioCapabilityProfile capabilityProfile,
    required bool forceStereo,
  }) {
    if (forceStereo) {
      return AudioFallbackCodec.aacStereo;
    }
    if (requested != AudioFallbackCodec.auto) {
      return requested;
    }
    if (legacyStereoAacFallback || !capabilityProfile.hasMultichannelCapability) {
      return AudioFallbackCodec.aacStereo;
    }
    return AudioFallbackCodec.auto;
  }

  static List<String> _mpegTsAudioCodecsForFallback({
    required AudioFallbackCodec effectiveAudioFallbackCodec,
    required List<String> allowedAudioCodecs,
  }) {
    final preferredTargets = switch (effectiveAudioFallbackCodec) {
      AudioFallbackCodec.auto => _hlsMpegTsAudioCodecs,
      AudioFallbackCodec.aacStereo => const <String>['aac', 'mp3'],
      AudioFallbackCodec.ac3_5_1 => const <String>['ac3', 'aac', 'mp3'],
      AudioFallbackCodec.eac3_5_1 => const <String>[
        'eac3',
        'ac3',
        'aac',
        'mp3',
      ],
    };

    return preferredTargets
        .where(allowedAudioCodecs.contains)
        .toList(growable: false);
  }

  static bool _isAudioCodecAllowed({
    required String codec,
    required AudioCapabilityProfile capabilityProfile,
    required bool ac3PassthroughEnabled,
    required bool eac3PassthroughEnabled,
    required bool eac3JocPassthroughEnabled,
    required bool dtsCorePassthroughEnabled,
    required bool dtsHdPassthroughEnabled,
    required bool trueHdPassthroughEnabled,
    required bool trueHdAtmosPassthroughEnabled,
  }) {
    if (_isAudioCodecDecodeSupported(codec, capabilityProfile)) {
      return true;
    }

    final passthroughSupported = _isAudioCodecPassthroughSupported(
      codec,
      capabilityProfile,
    );
    if (!passthroughSupported) {
      return false;
    }

    return _isAudioCodecPassthroughEnabled(
      codec: codec,
      ac3PassthroughEnabled: ac3PassthroughEnabled,
      eac3PassthroughEnabled: eac3PassthroughEnabled,
      eac3JocPassthroughEnabled: eac3JocPassthroughEnabled,
      dtsCorePassthroughEnabled: dtsCorePassthroughEnabled,
      dtsHdPassthroughEnabled: dtsHdPassthroughEnabled,
      trueHdPassthroughEnabled: trueHdPassthroughEnabled,
      trueHdAtmosPassthroughEnabled: trueHdAtmosPassthroughEnabled,
    );
  }

  static bool _isAudioCodecDecodeSupported(
    String codec,
    AudioCapabilityProfile capabilityProfile,
  ) {
    switch (codec) {
      case 'ac3':
        return capabilityProfile.canDecodeAc3;
      case 'eac3':
        return capabilityProfile.canDecodeEac3;
      case 'dts':
      case 'dca':
        return capabilityProfile.canDecodeDts || capabilityProfile.canDecodeDtsHd;
      case 'truehd':
      case 'mlp':
        return capabilityProfile.canDecodeTrueHd;
      case 'flac':
        return capabilityProfile.canDecodeFlac;
      default:
        return true;
    }
  }

  static bool _isAudioCodecPassthroughSupported(
    String codec,
    AudioCapabilityProfile capabilityProfile,
  ) {
    switch (codec) {
      case 'ac3':
        return capabilityProfile.canPassthroughAc3;
      case 'eac3':
        return capabilityProfile.canPassthroughEac3 ||
            capabilityProfile.canPassthroughEac3Joc;
      case 'dts':
      case 'dca':
        return capabilityProfile.canPassthroughDts ||
            capabilityProfile.canPassthroughDtsHd;
      case 'truehd':
      case 'mlp':
        return capabilityProfile.canPassthroughTrueHd;
      default:
        return false;
    }
  }

  static bool _isAudioCodecPassthroughEnabled({
    required String codec,
    required bool ac3PassthroughEnabled,
    required bool eac3PassthroughEnabled,
    required bool eac3JocPassthroughEnabled,
    required bool dtsCorePassthroughEnabled,
    required bool dtsHdPassthroughEnabled,
    required bool trueHdPassthroughEnabled,
    required bool trueHdAtmosPassthroughEnabled,
  }) {
    switch (codec) {
      case 'ac3':
        return ac3PassthroughEnabled;
      case 'eac3':
        return eac3PassthroughEnabled || eac3JocPassthroughEnabled;
      case 'dts':
      case 'dca':
        return dtsCorePassthroughEnabled || dtsHdPassthroughEnabled;
      case 'truehd':
      case 'mlp':
        return trueHdPassthroughEnabled || trueHdAtmosPassthroughEnabled;
      default:
        return false;
    }
  }

  static String _profileName() {
    if (PlatformDetection.isAndroid) return 'Moonfin for Android';
    if (PlatformDetection.isIOS) return 'Moonfin iOS';
    if (PlatformDetection.isMacOS) return 'Moonfin macOS';
    if (PlatformDetection.isWindows) return 'Moonfin Windows';
    if (PlatformDetection.isLinux) return 'Moonfin Linux';
    return 'Moonfin';
  }

  static List<Map<String, dynamic>> _codecProfiles({
    required bool downMixAudio,
    required bool audioFallbackToStereoAac,
    required MaxVideoResolution maxResolution,
    required bool supportsAvc,
    required bool supportsAvcHigh10,
    required int avcMainLevel,
    required int avcHigh10Level,
    required bool supportsHevc,
    required bool supportsHevcMain10,
    required int hevcMainLevel,
    required bool supportsHevcDolbyVision,
    required bool supportsHevcDolbyVisionEl,
    required bool supportsHevcHdr10,
    required bool supportsHevcHdr10Plus,
    required bool supportsAv1,
    required bool supportsAv1Main10,
    required bool supportsAv1DolbyVision,
    required bool supportsAv1Hdr10,
    required bool supportsAv1Hdr10Plus,
    required bool supportsVc1,
    required int maxResolutionAvcWidth,
    required int maxResolutionAvcHeight,
    required int maxResolutionHevcWidth,
    required int maxResolutionHevcHeight,
    required int maxResolutionAv1Width,
    required int maxResolutionAv1Height,
    required int maxResolutionVc1Width,
    required int maxResolutionVc1Height,
    required bool supportsDvProfile5,
    required bool supportsDvProfile7,
    required bool supportsDvProfile8,
    required bool knownHevcDoviHdr10PlusBug,
    required bool allowDolbyVisionProfile7ElDirectPlay,
  }) {
    final profiles = <Map<String, dynamic>>[];

    profiles.add(
      _codecProfile(
        type: 'Video',
        codec: 'h264',
        conditions: <Map<String, dynamic>>[
          _condition(
            condition: supportsAvc ? 'NotEquals' : 'Equals',
            property: 'VideoProfile',
            value: supportsAvc ? 'none' : 'none',
          ),
        ],
      ),
    );

    if (!supportsAvcHigh10) {
      profiles.add(
        _codecProfile(
          type: 'Video',
          codec: 'h264',
          conditions: <Map<String, dynamic>>[
            _condition(
              condition: 'NotEquals',
              property: 'VideoProfile',
              value: 'high 10',
            ),
          ],
        ),
      );
    }

    if (supportsAvc && avcMainLevel > 0) {
      for (final profile in const <String>[
        'high',
        'main',
        'baseline',
        'constrained baseline',
      ]) {
        profiles.add(
          _codecProfile(
            type: 'Video',
            codec: 'h264',
            conditions: <Map<String, dynamic>>[
              _condition(
                condition: 'LessThanEqual',
                property: 'VideoLevel',
                value: '$avcMainLevel',
              ),
            ],
            applyConditions: <Map<String, dynamic>>[
              _condition(
                condition: 'Equals',
                property: 'VideoProfile',
                value: profile,
              ),
            ],
          ),
        );
      }
    }

    if (supportsAvcHigh10 && avcHigh10Level > 0) {
      profiles.add(
        _codecProfile(
          type: 'Video',
          codec: 'h264',
          conditions: <Map<String, dynamic>>[
            _condition(
              condition: 'LessThanEqual',
              property: 'VideoLevel',
              value: '$avcHigh10Level',
            ),
          ],
          applyConditions: <Map<String, dynamic>>[
            _condition(
              condition: 'Equals',
              property: 'VideoProfile',
              value: 'high 10',
            ),
          ],
        ),
      );
    }

    profiles.add(
      _codecProfile(
        type: 'Video',
        codec: 'h264',
        conditions: <Map<String, dynamic>>[
          _condition(
            condition: 'LessThanEqual',
            property: 'RefFrames',
            value: '12',
          ),
        ],
        applyConditions: <Map<String, dynamic>>[
          _condition(
            condition: 'GreaterThanEqual',
            property: 'Width',
            value: '1200',
          ),
        ],
      ),
    );

    profiles.add(
      _codecProfile(
        type: 'Video',
        codec: 'h264',
        conditions: <Map<String, dynamic>>[
          _condition(
            condition: 'LessThanEqual',
            property: 'RefFrames',
            value: '4',
          ),
        ],
        applyConditions: <Map<String, dynamic>>[
          _condition(
            condition: 'GreaterThanEqual',
            property: 'Width',
            value: '1900',
          ),
        ],
      ),
    );

    profiles.add(
      _codecProfile(
        type: 'Video',
        codec: 'hevc',
        conditions: <Map<String, dynamic>>[
          _condition(
            condition: supportsHevc ? 'NotEquals' : 'Equals',
            property: 'VideoProfile',
            value: supportsHevc ? 'none' : 'none',
          ),
        ],
      ),
    );

    if (!supportsHevcMain10) {
      profiles.add(
        _codecProfile(
          type: 'Video',
          codec: 'hevc',
          conditions: <Map<String, dynamic>>[
            _condition(
              condition: 'NotEquals',
              property: 'VideoProfile',
              value: 'main 10',
            ),
          ],
        ),
      );
    }

    profiles.add(
      _codecProfile(
        type: 'Video',
        codec: 'av1',
        conditions: <Map<String, dynamic>>[
          if (!supportsAv1)
            _condition(
              condition: 'Equals',
              property: 'VideoProfile',
              value: 'none',
            )
          else if (!supportsAv1Main10)
            _condition(
              condition: 'NotEquals',
              property: 'VideoProfile',
              value: 'main 10',
            )
          else
            _condition(
              condition: 'NotEquals',
              property: 'VideoProfile',
              value: 'none',
            ),
        ],
      ),
    );

    profiles.add(
      _codecProfile(
        type: 'Video',
        codec: 'vc1',
        conditions: <Map<String, dynamic>>[
          _condition(
            condition: supportsVc1 ? 'NotEquals' : 'Equals',
            property: 'VideoProfile',
            value: 'none',
          ),
        ],
      ),
    );

    _addResolutionProfile(
      profiles: profiles,
      codec: 'h264',
      maxResolution: maxResolution,
      detectedWidth: maxResolutionAvcWidth,
      detectedHeight: maxResolutionAvcHeight,
    );
    _addResolutionProfile(
      profiles: profiles,
      codec: 'hevc',
      maxResolution: maxResolution,
      detectedWidth: maxResolutionHevcWidth,
      detectedHeight: maxResolutionHevcHeight,
    );
    _addResolutionProfile(
      profiles: profiles,
      codec: 'av1',
      maxResolution: maxResolution,
      detectedWidth: maxResolutionAv1Width,
      detectedHeight: maxResolutionAv1Height,
    );
    _addResolutionProfile(
      profiles: profiles,
      codec: 'vc1',
      maxResolution: maxResolution,
      detectedWidth: maxResolutionVc1Width,
      detectedHeight: maxResolutionVc1Height,
    );

    final unsupportedRangeTypesAv1 = <String>{
      'DOVI_INVALID',
    };
    if (!supportsAv1DolbyVision) {
      unsupportedRangeTypesAv1.add('DOVI');
      if (!supportsAv1Hdr10) {
        unsupportedRangeTypesAv1.add('DOVI_WITH_HDR10');
      }
      if (!supportsAv1Hdr10Plus) {
        unsupportedRangeTypesAv1.add('DOVI_WITH_HDR10_PLUS');
      }
    }
    if (!supportsAv1Hdr10) {
      unsupportedRangeTypesAv1.add('HDR10');
      if (!supportsAv1Hdr10Plus) {
        unsupportedRangeTypesAv1.add('HDR10_PLUS');
      }
    }

    final unsupportedRangeTypesHevc = <String>{
      'DOVI_INVALID',
    };
    if (!supportsHevcDolbyVisionEl) {
      if (!allowDolbyVisionProfile7ElDirectPlay) {
        unsupportedRangeTypesHevc.add('DOVI_WITH_EL');
        unsupportedRangeTypesHevc.add('DOVI_WITH_ELHDR10_PLUS');
      }

      if (!supportsHevcDolbyVision) {
        unsupportedRangeTypesHevc.add('DOVI');
        if (!supportsHevcHdr10) {
          unsupportedRangeTypesHevc.add('DOVI_WITH_HDR10');
        }
      }
    }

    if (!supportsHevcHdr10) {
      unsupportedRangeTypesHevc.add('HDR10');
      if (!supportsHevcHdr10Plus) {
        unsupportedRangeTypesHevc.add('HDR10_PLUS');
      }
    }

    if (knownHevcDoviHdr10PlusBug) {
      unsupportedRangeTypesHevc.add('DOVI_WITH_HDR10_PLUS');
      unsupportedRangeTypesHevc.add('DOVI_WITH_ELHDR10_PLUS');
    }

    if (!supportsDvProfile5) {
      unsupportedRangeTypesHevc.add('DOVI');
    }
    if (!supportsDvProfile7) {
      if (!allowDolbyVisionProfile7ElDirectPlay) {
        unsupportedRangeTypesHevc.add('DOVI_WITH_EL');
        unsupportedRangeTypesHevc.add('DOVI_WITH_ELHDR10_PLUS');
      }
    }
    if (!supportsDvProfile8) {
      unsupportedRangeTypesHevc.add('DOVI_WITH_HDR10');
    }

    _addUnsupportedRangeProfiles(
      profiles: profiles,
      codec: 'av1',
      rangeTypes: unsupportedRangeTypesAv1,
    );
    _addUnsupportedRangeProfiles(
      profiles: profiles,
      codec: 'hevc',
      rangeTypes: unsupportedRangeTypesHevc,
    );

    profiles.add(
      _codecProfile(
        type: 'VideoAudio',
        conditions: <Map<String, dynamic>>[
          _condition(
            condition: 'LessThanEqual',
            property: 'AudioChannels',
            value: downMixAudio ? '2' : '8',
          ),
        ],
      ),
    );

    if (audioFallbackToStereoAac && !downMixAudio) {
      profiles.add(
        _codecProfile(
          type: 'VideoAudio',
          codec: 'aac',
          conditions: <Map<String, dynamic>>[
            _condition(
              condition: 'LessThanEqual',
              property: 'AudioChannels',
              value: '2',
            ),
          ],
        ),
      );
    }

    return profiles;
  }

  static void _addUnsupportedRangeProfiles({
    required List<Map<String, dynamic>> profiles,
    required String codec,
    required Set<String> rangeTypes,
  }) {
    if (rangeTypes.isEmpty) {
      return;
    }

    final expandedRangeTypes = _expandVideoRangeTypeAliases(rangeTypes);
    final sortedRangeTypes = expandedRangeTypes.toList(growable: false)..sort();
    final joinedRangeTypes = sortedRangeTypes.join('|');
    profiles.add(
      _codecProfile(
        type: 'Video',
        codec: codec,
        conditions: <Map<String, dynamic>>[
          _condition(
            condition: 'NotEquals',
            property: 'VideoRangeType',
            value: joinedRangeTypes,
            isRequired: false,
          ),
        ],
        applyConditions: <Map<String, dynamic>>[
          _condition(
            condition: 'EqualsAny',
            property: 'VideoRangeType',
            value: joinedRangeTypes,
            isRequired: false,
          ),
        ],
      ),
    );
  }

  static Set<String> _expandVideoRangeTypeAliases(Set<String> rangeTypes) {
    final expanded = <String>{};
    for (final token in rangeTypes) {
      final aliases = _videoRangeTypeAliases[token];
      if (aliases == null || aliases.isEmpty) {
        expanded.add(token);
      } else {
        expanded.addAll(aliases);
      }
    }
    return expanded;
  }

  static const Map<String, List<String>> _videoRangeTypeAliases =
      <String, List<String>>{
        'DOVI_INVALID': <String>['DOVI_INVALID', 'DOVIInvalid'],
        'DOVI_WITH_EL': <String>['DOVI_WITH_EL', 'DOVIWithEL'],
        'DOVI_WITH_ELHDR10_PLUS': <String>[
          'DOVI_WITH_ELHDR10_PLUS',
          'DOVIWithELHDR10Plus',
        ],
        'DOVI_WITH_HDR10': <String>['DOVI_WITH_HDR10', 'DOVIWithHDR10'],
        'DOVI_WITH_HDR10_PLUS': <String>[
          'DOVI_WITH_HDR10_PLUS',
          'DOVIWithHDR10Plus',
        ],
        'HDR10_PLUS': <String>['HDR10_PLUS', 'HDR10Plus'],
      };

  static void _addResolutionProfile({
    required List<Map<String, dynamic>> profiles,
    required String codec,
    required MaxVideoResolution maxResolution,
    required int detectedWidth,
    required int detectedHeight,
  }) {
    final userWidth =
        maxResolution == MaxVideoResolution.auto ? 0 : maxResolution.width;
    final userHeight =
        maxResolution == MaxVideoResolution.auto ? 0 : maxResolution.height;

    var width = detectedWidth > 0 ? detectedWidth : userWidth;
    var height = detectedHeight > 0 ? detectedHeight : userHeight;

    if (userWidth > 0) {
      width = width <= 0 ? userWidth : width.clamp(0, userWidth).toInt();
    }
    if (userHeight > 0) {
      height =
          height <= 0 ? userHeight : height.clamp(0, userHeight).toInt();
    }

    if (width <= 0 || height <= 0) {
      return;
    }

    profiles.add(
      _codecProfile(
        type: 'Video',
        codec: codec,
        conditions: <Map<String, dynamic>>[
          _condition(
            condition: 'LessThanEqual',
            property: 'Width',
            value: '$width',
          ),
          _condition(
            condition: 'LessThanEqual',
            property: 'Height',
            value: '$height',
          ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _codecProfile({
    required String type,
    String? codec,
    List<Map<String, dynamic>> conditions = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> applyConditions = const <Map<String, dynamic>>[],
  }) {
    final profile = <String, dynamic>{
      'Type': type,
      'Conditions': conditions,
      if (applyConditions.isNotEmpty) 'ApplyConditions': applyConditions,
    };

    if (codec != null) {
      profile['Codec'] = codec;
    }

    return profile;
  }

  static Map<String, dynamic> _condition({
    required String condition,
    required String property,
    required String value,
    bool isRequired = true,
  }) {
    return <String, dynamic>{
      'Condition': condition,
      'Property': property,
      'Value': value,
      'IsRequired': isRequired,
    };
  }

  static List<Map<String, dynamic>> _subtitleProfiles({
    required bool pgsDirectPlay,
    required bool assDirectPlay,
  }) {
    final profiles = <Map<String, dynamic>>[];

    void add(String format, String method) {
      profiles.add(<String, dynamic>{'Format': format, 'Method': method});
    }

    for (final format in const <String>['vtt', 'webvtt']) {
      add(format, 'Embed');
      add(format, 'External');
      add(format, 'Hls');
    }

    for (final format in const <String>['srt', 'subrip', 'ttml']) {
      add(format, 'Embed');
      add(format, 'External');
    }

    for (final format in const <String>['dvbsub', 'dvdsub', 'idx']) {
      add(format, 'Embed');
      add(format, 'Encode');
    }

    for (final format in const <String>['pgs', 'pgssub']) {
      if (pgsDirectPlay) {
        add(format, 'Embed');
      }
      add(format, 'Encode');
    }

    for (final format in const <String>['ass', 'ssa']) {
      if (assDirectPlay) {
        add(format, 'Embed');
        add(format, 'External');
      }
      add(format, 'Encode');
    }

    return profiles;
  }
}
