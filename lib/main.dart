import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Store.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Video Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6750A4),
      ),
      home: const HomeScreen(),
    );
  }
}

/// Simple persistence layer: recents list + resume positions.
class Store {
  static late final SharedPreferences _prefs;
  static const _recentsKey = 'recents';

  static Future<void> init() async => _prefs = await SharedPreferences.getInstance();

  static List<Map<String, String>> recents() {
    final raw = _prefs.getString(_recentsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addRecent(String source, String title) async {
    final list = recents()..removeWhere((m) => m['s'] == source);
    list.insert(0, {'s': source, 't': title});
    await _prefs.setString(
        _recentsKey, jsonEncode(list.take(30).toList()));
  }

  static int? resumeMs(String source) => _prefs.getInt('pos:$source');

  static Future<void> saveResumeMs(String source, int ms) =>
      _prefs.setInt('pos:$source', ms);

  static Future<void> clearResume(String source) =>
      _prefs.remove('pos:$source');
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, String>> _recents = [];

  @override
  void initState() {
    super.initState();
    _recents = Store.recents();
  }

  Future<void> _openFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null) return;
    await _play(path, path.split('/').last);
  }

  Future<void> _openUrl() async {
    final url = await _promptUrl();
    if (url == null) return;
    final clean = url.trim();
    if (clean.isEmpty) return;
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      _toast('Only http(s) URLs are supported.');
      return;
    }
    var name = clean.split('/').last;
    if (name.isEmpty) name = 'Stream';
    await _play(clean, name);
  }

  Future<String?> _promptUrl() {
    final c = TextEditingController(text: 'https://');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open network stream'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/video.m3u8',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Future<void> _play(String source, String title) async {
    await Store.addRecent(source, title);
    if (!mounted) return;
    setState(() => _recents = Store.recents());
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(source: source, title: title),
    ));
    setState(() => _recents = Store.recents());
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Universal Video Player')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _openFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open video file'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openUrl,
            icon: const Icon(Icons.link),
            label: const Text('Open network stream (HLS / DASH / MP4)'),
          ),
          const SizedBox(height: 24),
          if (_recents.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No recent videos yet.\nOpen a file or paste a stream URL to get started.',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            )
          else ...[
            Text('Recent', style: theme.textTheme.titleMedium),
            for (final r in _recents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline),
                title: Text(
                  r['t'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  r['s'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _play(r['s']!, r['t'] ?? 'Video'),
              ),
          ],
        ],
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.source,
    required this.title,
  });

  final String source;
  final String title;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  Timer? _saveTimer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    // Resume where the user left off (if more than 10s in).
    final resumeMs = Store.resumeMs(widget.source) ?? 0;
    player.open(
      Media(
        widget.source,
        start: resumeMs > 10000 ? Duration(milliseconds: resumeMs) : Duration.zero,
      ),
    );

    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveProgress(),
    );

    player.stream.completed.listen((completed) {
      if (!mounted) return;
      setState(() => _finished = completed);
      if (completed) Store.clearResume(widget.source);
    });
  }

  void _saveProgress() {
    final pos = player.state.position.inMilliseconds;
    final dur = player.state.duration.inMilliseconds;
    if (pos > 0 && (dur == 0 || pos < dur - 15000)) {
      Store.saveResumeMs(widget.source, pos);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveProgress();
    WakelockPlus.disable();
    player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ControlsOverlay(
        player: player,
        controller: controller,
        title: widget.title,
        finished: _finished,
      ),
    );
  }
}

class ControlsOverlay extends StatefulWidget {
  const ControlsOverlay({
    super.key,
    required this.player,
    required this.controller,
    required this.title,
    this.finished = false,
  });

  final Player player;
  final VideoController controller;
  final String title;
  final bool finished;

  @override
  State<ControlsOverlay> createState() => _ControlsOverlayState();
}

class _ControlsOverlayState extends State<ControlsOverlay> {
  bool _visible = true;
  Timer? _hideTimer;
  double? _dragMs;
  double? _doubleTapX;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _showControls() {
    setState(() => _visible = true);
    _scheduleHide();
  }

  void _tapToggle() {
    if (_visible) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    } else {
      _showControls();
    }
  }

  void _doubleTapSeek() {
    final w = context.size?.width ?? 0;
    final x = _doubleTapX ?? w / 2;
    final pos = widget.player.state.position;
    if (x < w / 3) {
      widget.player.seek(pos - const Duration(seconds: 10));
    } else if (x > 2 * w / 3) {
      widget.player.seek(pos + const Duration(seconds: 10));
    }
  }

  Future<void> _toggleFullscreen() async {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    if (isPortrait) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(
          DeviceOrientation.values);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _speedSheet() {
    const rates = [
      0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0
    ];
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Playback speed'),
            ),
            for (final r in rates)
              ListTile(
                title: Text('${r}x'),
                trailing: widget.player.state.rate == r
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  widget.player.setRate(r);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _subtitleSheet() {
    final tracks = widget.player.state.tracks;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Subtitles'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_mode),
              title: const Text('Auto'),
              onTap: () {
                widget.player.setSubtitleTrack(SubtitleTrack.automatic());
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Off'),
              onTap: () {
                widget.player.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(context);
              },
            ),
            for (final t in tracks.subtitle)
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: Text(t.title ?? t.id),
                subtitle: t.language == null ? null : Text(t.language!),
                onTap: () {
                  widget.player.setSubtitleTrack(SubtitleTrack.id(t.id));
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.file_open),
              title: const Text('Load subtitle file (.srt / .vtt / .ass)'),
              onTap: () async {
                final res = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['srt', 'vtt', 'ass', 'ssa', 'sub'],
                );
                final path = res?.files.single.path;
                if (path != null) {
                  widget.player.setSubtitleTrack(SubtitleTrack.uri(path));
                }
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _audioSheet() {
    final tracks = widget.player.state.tracks;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Audio track'),
            ),
            for (final t in tracks.audio)
              ListTile(
                leading: const Icon(Icons.audiotrack_outlined),
                title: Text(t.title ?? t.id),
                subtitle: t.language == null ? null : Text(t.language!),
                onTap: () {
                  widget.player.setAudioTrack(AudioTrack.id(t.id));
                  Navigator.pop(context);
                },
              ),
            if (tracks.audio.isEmpty)
              const ListTile(title: Text('No embedded audio tracks')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: _tapToggle,
      onDoubleTapDown: (d) => _doubleTapX = d.globalPosition.dx,
      onDoubleTap: _doubleTapSeek,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: widget.controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
          StreamBuilder<bool>(
            stream: player.stream.buffering,
            initialData: player.state.buffering,
            builder: (context, snap) => (snap.data ?? false)
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox.shrink(),
          ),
          if (widget.finished)
            Center(
              child: IconButton(
                iconSize: 56,
                icon: const Icon(Icons.replay),
                onPressed: () {
                  player.seek(Duration.zero);
                  player.play();
                },
              ),
            ),
          AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_visible,
              child: Column(
                children: [
                  // Top bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Bottom panel
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StreamBuilder<Duration>(
                          stream: player.stream.position,
                          initialData: player.state.position,
                          builder: (context, snap) {
                            final posMs =
                                (snap.data ?? Duration.zero).inMilliseconds;
                            final durMs =
                                player.state.duration.inMilliseconds;
                            final max =
                                durMs > 0 ? durMs.toDouble() : 1.0;
                            final value =
                                (_dragMs ?? posMs.toDouble()).clamp(0.0, max);
                            return Row(
                              children: [
                                Text(_fmt(Duration(milliseconds: value.round())),
                                    style: const TextStyle(fontSize: 12)),
                                Expanded(
                                  child: Slider(
                                    value: value,
                                    max: max,
                                    onChangeStart: (_) =>
                                        _hideTimer?.cancel(),
                                    onChanged: (v) => setState(() {
                                      _dragMs = v;
                                      _hideTimer?.cancel();
                                    }),
                                    onChangeEnd: (v) async {
                                      await player.seek(Duration(
                                          milliseconds: v.round()));
                                      if (mounted) {
                                        setState(() => _dragMs = null);
                                        _showControls();
                                      }
                                    },
                                  ),
                                ),
                                Text(
                                    _fmt(Duration(
                                        milliseconds: durMs)),
                                    style: const TextStyle(fontSize: 12)),
                              ],
                            );
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10),
                              onPressed: () => player.seek(player
                                      .state.position -
                                  const Duration(seconds: 10)),
                            ),
                            StreamBuilder<bool>(
                              stream: player.stream.playing,
                              initialData: player.state.playing,
                              builder: (context, snap) {
                                final playing = snap.data ?? false;
                                return IconButton(
                                  iconSize: 36,
                                  icon: Icon(playing
                                      ? Icons.pause
                                      : Icons.play_arrow),
                                  onPressed: () => playing
                                      ? player.pause()
                                      : player.play(),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.forward_10),
                              onPressed: () => player.seek(player
                                      .state.position +
                                  const Duration(seconds: 10)),
                            ),
                            IconButton(
                              icon: Icon(player.state.volume == 0
                                  ? Icons.volume_off
                                  : Icons.volume_up),
                              onPressed: () => player.setVolume(
                                  player.state.volume == 0 ? 100 : 0),
                            ),
                            IconButton(
                              icon: const Icon(Icons.speed),
                              onPressed: _speedSheet,
                            ),
                            IconButton(
                              icon: const Icon(Icons.subtitles),
                              onPressed: _subtitleSheet,
                            ),
                            IconButton(
                              icon: const Icon(Icons.graphic_eq),
                              onPressed: _audioSheet,
                            ),
                            IconButton(
                              icon: Icon(
                                MediaQuery.of(context).orientation ==
                                        Orientation.portrait
                                    ? Icons.fullscreen
                                    : Icons.fullscreen_exit,
                              ),
                              onPressed: _toggleFullscreen,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}
