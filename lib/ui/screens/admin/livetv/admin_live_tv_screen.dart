import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../widgets/admin_form_styles.dart';

class AdminLiveTvScreen extends StatefulWidget {
  const AdminLiveTvScreen({super.key});

  @override
  State<AdminLiveTvScreen> createState() => _AdminLiveTvScreenState();
}

class _AdminLiveTvScreenState extends State<AdminLiveTvScreen> {
  bool _loading = true;
  bool _discovering = false;
  bool _savingConfig = false;
  bool _refreshingGuide = false;
  String? _error;

  List<Map<String, dynamic>> _tuners = const [];
  List<Map<String, dynamic>> _providers = const [];
  List<Map<String, dynamic>> _discoveredTuners = const [];
  Map<String, dynamic> _config = const {};

  AdminLiveTvApi get _api => GetIt.instance<MediaServerClient>().adminLiveTvApi;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 404 || status == 405 || status == 501) {
        return AppLocalizations.of(context).adminLiveTvNotAvailable;
      }
      final data = error.response?.data;
      if (data is Map) {
        final message =
            data['message'] ?? data['Message'] ?? data['error'] ?? data['title'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      } else if (data is String && data.trim().isNotEmpty) {
        return data;
      }
      if (status != null) {
        return AppLocalizations.of(context).adminServerReturnedHttp(status);
      }
    }
    return error.toString();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final config = await _api.getLiveTvConfiguration();
      final tuners = (config['TunerHosts'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      final providers = (config['ListingProviders'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _tuners = tuners;
        _providers = providers;
        _config = config;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  String _display(Map<String, dynamic> item, List<String> keys, {String? fallback}) {
    for (final key in keys) {
      final value = item[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return fallback ?? AppLocalizations.of(context).unknown;
  }

  String _idOf(Map<String, dynamic> item) {
    return _display(item, const ['Id', 'ID', 'Guid', 'Name'], fallback: '');
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _guideDaysText() {
    final l10n = AppLocalizations.of(context);
    final days = (_config['GuideDays'] as num?)?.toInt();
    return days == null
        ? l10n.adminGuideDaysAuto
        : l10n.adminGuideDaysValue(days);
  }

  Widget _dialogSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColorScheme.accent.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Future<void> _discoverTuners() async {
    if (_discovering) return;
    setState(() => _discovering = true);
    try {
      final found = await _api.discoverTuners();
      if (!mounted) return;
      setState(() {
        _discoveredTuners = found;
        _discovering = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _discovering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminTunerDiscoveryFailed(e.toString()))),
      );
    }
  }

  Future<void> _showAddTunerDialog({Map<String, dynamic>? seed}) async {
    final typeController = TextEditingController(
      text: _display(seed ?? const {}, const ['Type', 'TunerType'], fallback: 'M3U'),
    );
    final urlController = TextEditingController(
      text: _display(seed ?? const {}, const ['Url', 'Path', 'ImportUrl'], fallback: ''),
    );
    final nameController = TextEditingController(
      text: _display(seed ?? const {}, const ['Name', 'FriendlyName'], fallback: ''),
    );

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(AppLocalizations.of(context).adminAddTuner),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).adminTunerType,
                  hintText: AppLocalizations.of(context).adminTunerTypeHint,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).adminUrlPath,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).adminNameOptional,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () {
              final type = typeController.text.trim();
              final url = urlController.text.trim();
              final name = nameController.text.trim();
              Navigator.pop(ctx, {
                'Type': type,
                'Url': url,
                if (name.isNotEmpty) 'Name': name,
              });
            },
            child: Text(AppLocalizations.of(context).add),
          ),
        ],
      ),
    );

    typeController.dispose();
    urlController.dispose();
    nameController.dispose();

    if (payload == null || !mounted) return;
    try {
      await _api.addTunerHost(payload);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminTunerAdded)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminTunerAddFailed(e.toString()))),
      );
    }
  }

  Future<void> _showAddProviderDialog() async {
    final typeController = TextEditingController(text: 'XMLTV');
    final urlController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final refreshHoursController = TextEditingController(text: '24');

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(AppLocalizations.of(context).adminAddProvider),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).adminProviderType,
                  hintText: AppLocalizations.of(context).adminProviderTypeHint,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).adminUrlPath,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).adminUsernameOptional,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).adminPasswordOptional,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refreshHoursController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).adminRefreshInterval,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () {
              final refresh = int.tryParse(refreshHoursController.text.trim());
              final payload = <String, dynamic>{
                'Type': typeController.text.trim(),
                if (urlController.text.trim().isNotEmpty) 'Url': urlController.text.trim(),
                if (usernameController.text.trim().isNotEmpty) 'Username': usernameController.text.trim(),
                if (passwordController.text.trim().isNotEmpty) 'Password': passwordController.text.trim(),
                'RefreshIntervalHours': ?refresh,
              };
              Navigator.pop(ctx, payload);
            },
            child: Text(AppLocalizations.of(context).add),
          ),
        ],
      ),
    );

    typeController.dispose();
    urlController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    refreshHoursController.dispose();

    if (payload == null || !mounted) return;

    try {
      await _api.addListingProvider(payload);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminProviderAdded)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminProviderAddFailed(e.toString()))),
      );
    }
  }

  Future<void> _removeTuner(Map<String, dynamic> tuner) async {
    final id = _idOf(tuner);
    if (id.isEmpty) return;
    try {
      await _api.removeTunerHost(id);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminTunerRemoveFailed(e.toString()))),
      );
    }
  }

  Future<void> _resetTuner(Map<String, dynamic> tuner) async {
    final id = _idOf(tuner);
    if (id.isEmpty) return;
    try {
      await _api.resetTuner(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminTunerResetRequested)),
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final message = e is DioException && e.response?.statusCode == 400
          ? l10n.adminTunerResetNotSupported
          : l10n.adminTunerResetFailed(_friendlyError(e));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _refreshGuideData() async {
    if (_refreshingGuide) return;
    setState(() => _refreshingGuide = true);
    final l10n = AppLocalizations.of(context);
    try {
      final tasksApi = GetIt.instance<MediaServerClient>().adminTasksApi;
      final tasks = await tasksApi.getTasks();
      final task = tasks.firstWhere(
        (t) => t['Key'] == 'RefreshGuide',
        orElse: () => const <String, dynamic>{},
      );
      final id = (task['Id'] ?? '').toString();
      if (id.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.adminGuideRefreshUnavailable)),
        );
        return;
      }
      await tasksApi.startTask(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminGuideRefreshStarted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _refreshingGuide = false);
    }
  }

  Future<void> _removeProvider(Map<String, dynamic> provider) async {
    final id = _idOf(provider);
    if (id.isEmpty) return;
    try {
      await _api.removeListingProvider(id);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminProviderRemoveFailed(e.toString()))),
      );
    }
  }

  Future<void> _saveRecordingSettings() async {
    final prePadding = _intValue(
      _config['PrePaddingSeconds'] ?? _config['PrePaddingMinutes'],
    );
    final postPadding = _intValue(
      _config['PostPaddingSeconds'] ?? _config['PostPaddingMinutes'],
    );
    final recordingPath = (_config['RecordingPath'] ?? '').toString();
    final seriesPath = (_config['SeriesRecordingPath'] ?? '').toString();

    final preController = TextEditingController(
      text: (prePadding ~/ 60).toString(),
    );
    final postController = TextEditingController(
      text: (postPadding ~/ 60).toString(),
    );
    final recPathController = TextEditingController(text: recordingPath);
    final seriesPathController = TextEditingController(text: seriesPath);
    final moviePathController = TextEditingController(
      text: (_config['MovieRecordingPath'] ?? '').toString(),
    );
    final postProcessorController = TextEditingController(
      text: (_config['RecordingPostProcessor'] ?? '').toString(),
    );
    final postProcessorArgsController = TextEditingController(
      text: (_config['RecordingPostProcessorArguments'] ?? '').toString(),
    );

    const guideDayOptions = <int?>[null, 1, 2, 3, 5, 7, 14];
    final rawGuideDays = (_config['GuideDays'] as num?)?.toInt();
    var guideDays = guideDayOptions.contains(rawGuideDays) ? rawGuideDays : null;
    var saveNfo = _config['SaveRecordingNFO'] as bool? ?? true;
    var saveImages = _config['SaveRecordingImages'] as bool? ?? true;

    final l10n = AppLocalizations.of(context);
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.adminRecordingSettings),
        content: SizedBox(
          width: 400,
          child: StatefulBuilder(
            builder: (ctx, setLocal) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _dialogSectionLabel(l10n.adminLiveTvSectionTiming),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: preController,
                          keyboardType: TextInputType.number,
                          decoration:
                              adminInputDecoration(label: l10n.adminPrePadding),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: postController,
                          keyboardType: TextInputType.number,
                          decoration:
                              adminInputDecoration(label: l10n.adminPostPadding),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: guideDays,
                    decoration: adminInputDecoration(label: l10n.adminGuideDays),
                    items: [
                      for (final d in guideDayOptions)
                        DropdownMenuItem(
                          value: d,
                          child: Text(d == null
                              ? l10n.adminGuideDaysAuto
                              : l10n.adminGuideDaysValue(d)),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => guideDays = v),
                  ),
                  _dialogSectionLabel(l10n.adminLiveTvSectionPaths),
                  TextField(
                    controller: recPathController,
                    decoration:
                        adminInputDecoration(label: l10n.adminRecordingPath),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: seriesPathController,
                    decoration: adminInputDecoration(
                        label: l10n.adminSeriesRecordingPath),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: moviePathController,
                    decoration: adminInputDecoration(
                        label: l10n.adminMovieRecordingPath),
                  ),
                  _dialogSectionLabel(l10n.adminLiveTvSectionPostProcessing),
                  TextField(
                    controller: postProcessorController,
                    decoration: adminInputDecoration(
                        label: l10n.adminRecordingPostProcessor),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: postProcessorArgsController,
                    decoration: adminInputDecoration(
                        label: l10n.adminRecordingPostProcessorArgs),
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColorScheme.onSurface.withValues(alpha: 0.05),
                      borderRadius: AppRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        adminSwitchRow(
                          title: l10n.adminSaveRecordingNfo,
                          value: saveNfo,
                          onChanged: (v) => setLocal(() => saveNfo = v),
                        ),
                        Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: 16,
                          color:
                              AppColorScheme.onSurface.withValues(alpha: 0.10),
                        ),
                        adminSwitchRow(
                          title: l10n.adminSaveRecordingImages,
                          value: saveImages,
                          onChanged: (v) => setLocal(() => saveImages = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final preMinutes = int.tryParse(preController.text.trim()) ?? 0;
              final postMinutes = int.tryParse(postController.text.trim()) ?? 0;
              Navigator.pop(ctx, {
                ..._config,
                'PrePaddingSeconds': preMinutes * 60,
                'PostPaddingSeconds': postMinutes * 60,
                'GuideDays': guideDays,
                'RecordingPath': recPathController.text.trim(),
                'SeriesRecordingPath': seriesPathController.text.trim(),
                'MovieRecordingPath': moviePathController.text.trim(),
                'RecordingPostProcessor': postProcessorController.text.trim(),
                'RecordingPostProcessorArguments':
                    postProcessorArgsController.text.trim(),
                'SaveRecordingNFO': saveNfo,
                'SaveRecordingImages': saveImages,
              });
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    preController.dispose();
    postController.dispose();
    recPathController.dispose();
    seriesPathController.dispose();
    moviePathController.dispose();
    postProcessorController.dispose();
    postProcessorArgsController.dispose();

    if (updated == null || !mounted) return;

    setState(() => _savingConfig = true);
    try {
      await _api.updateLiveTvConfiguration(updated);
      if (!mounted) return;
      setState(() {
        _config = updated;
        _savingConfig = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminRecordingSettingsSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingConfig = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminSettingsSaveFailed(e.toString()))),
      );
    }
  }

  Future<void> _setChannelMappings() async {
    final controller = TextEditingController();
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(AppLocalizations.of(context).adminSetChannelMappings),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).adminMappingJson,
            hintText: AppLocalizations.of(context).adminMappingJsonHint,
            border: OutlineInputBorder(),
          ),
          minLines: 4,
          maxLines: 8,
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                Navigator.pop(ctx, const <String, dynamic>{});
                return;
              }
              try {
                final decoded = jsonDecode(text);
                if (decoded is Map<String, dynamic>) {
                  Navigator.pop(ctx, decoded);
                } else {
                  Navigator.pop(ctx, {'Mappings': decoded});
                }
              } catch (_) {
                Navigator.pop(ctx, null);
              }
            },
            child: Text(AppLocalizations.of(context).adminApply),
          ),
        ],
      ),
    );
    controller.dispose();

    if (payload == null || !mounted) return;

    try {
      await _api.setChannelMappings(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminChannelMappingsUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).adminChannelMappingsUpdateFailed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context).adminLiveTvLoadFailed),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loadAll,
              child: Text(AppLocalizations.of(context).retry),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.of(context).adminLiveTvTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).refresh,
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _sectionCard(
          context,
          title: AppLocalizations.of(context).adminTunerDevices,
          action: FilledButton.tonalIcon(
            onPressed: () => _showAddTunerDialog(),
            icon: const Icon(Icons.add),
            label: Text(AppLocalizations.of(context).adminAddTuner),
          ),
          child: _tuners.isEmpty
              ? Text(AppLocalizations.of(context).adminNoTunerHosts)
              : Column(
                  children: _tuners.map((tuner) {
                    final name = _display(tuner, const ['FriendlyName', 'Name']);
                    final type = _display(tuner, const ['Type', 'TunerType']);
                    final id = _idOf(tuner);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(name),
                      subtitle: Text(type),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: AppLocalizations.of(context).adminReset,
                            onPressed: id.isEmpty ? null : () => _resetTuner(tuner),
                            icon: const Icon(Icons.restart_alt),
                          ),
                          IconButton(
                            tooltip: AppLocalizations.of(context).delete,
                            onPressed: id.isEmpty ? null : () => _removeTuner(tuner),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: AppLocalizations.of(context).adminGuideProviders,
          action: FilledButton.tonalIcon(
            onPressed: _showAddProviderDialog,
            icon: const Icon(Icons.add),
            label: Text(AppLocalizations.of(context).adminAddGuideProvider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _refreshingGuide ? null : _refreshGuideData,
                  icon: _refreshingGuide
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(AppLocalizations.of(context).adminRefreshGuideData),
                ),
              ),
              const SizedBox(height: 8),
              if (_providers.isEmpty)
                Text(AppLocalizations.of(context).adminNoListingProviders)
              else
                ..._providers.map((provider) {
                  final name = _display(provider, const ['Name', 'Type']);
                  final url =
                      _display(provider, const ['Url', 'Path'], fallback: '');
                  final id = _idOf(provider);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(name),
                    subtitle: url.isEmpty ? null : Text(url),
                    trailing: IconButton(
                      tooltip: AppLocalizations.of(context).delete,
                      onPressed:
                          id.isEmpty ? null : () => _removeProvider(provider),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: AppLocalizations.of(context).adminRecordingSettings,
          action: FilledButton.tonalIcon(
            onPressed: _savingConfig ? null : _saveRecordingSettings,
            icon: const Icon(Icons.save),
            label: Text(AppLocalizations.of(context).edit),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).adminRecordingPathDisplay(_display(_config, const ['RecordingPath'], fallback: AppLocalizations.of(context).adminNotSet))),
              const SizedBox(height: 4),
              Text(AppLocalizations.of(context).adminSeriesPathDisplay(_display(_config, const ['SeriesRecordingPath'], fallback: AppLocalizations.of(context).adminNotSet))),
              const SizedBox(height: 4),
              Text(AppLocalizations.of(context).adminPrePaddingDisplay(_intValue(_config['PrePaddingSeconds']) ~/ 60)),
              const SizedBox(height: 4),
              Text(AppLocalizations.of(context).adminPostPaddingDisplay(_intValue(_config['PostPaddingSeconds']) ~/ 60)),
              const SizedBox(height: 4),
              Text(AppLocalizations.of(context)
                  .adminGuideDaysDisplay(_guideDaysText())),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: AppLocalizations.of(context).adminTunerDiscovery,
          actionBelowTitle: true,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonalIcon(
                onPressed: _discovering ? null : _discoverTuners,
                icon: const Icon(Icons.radar),
                label: Text(AppLocalizations.of(context).adminDiscover),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _setChannelMappings,
                child: Text(AppLocalizations.of(context).adminChannelMappings),
              ),
            ],
          ),
          child: _discovering
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              : _discoveredTuners.isEmpty
                  ? Text(AppLocalizations.of(context).adminNoDiscoveredTuners)
                  : Column(
                      children: _discoveredTuners.map((item) {
                        final name = _display(item, const ['FriendlyName', 'Name']);
                        final type = _display(item, const ['Type', 'TunerType']);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(name),
                          subtitle: Text(type),
                          trailing: FilledButton.tonal(
                            onPressed: () => _showAddTunerDialog(seed: item),
                            child: Text(AppLocalizations.of(context).add),
                          ),
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
    Widget? action,
    bool actionBelowTitle = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!actionBelowTitle)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ?action,
                ],
              )
            else ...[
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (action != null) ...[
                const SizedBox(height: 8),
                action,
              ],
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
