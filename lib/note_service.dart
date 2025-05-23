import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class VoiceNote {
  final String id;
  String title;
  String description;
  final String filePath;
  final DateTime createdAt;
  Duration duration;
  List<String> tags;

  VoiceNote({
    required this.id,
    required this.title,
    this.description = '',
    required this.filePath,
    required this.createdAt,
    required this.duration,
    this.tags = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'duration': duration.inMilliseconds,
        'tags': tags,
      };

  factory VoiceNote.fromJson(Map<String, dynamic> json) => VoiceNote(
        id: json['id'],
        title: json['title'],
        description: json['description'] ?? '',
        filePath: json['filePath'],
        createdAt: DateTime.parse(json['createdAt']),
        duration: Duration(milliseconds: json['duration']),
        tags: List<String>.from(json['tags'] ?? []),
      );
}

class NoteService extends ChangeNotifier {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentlyPlayingId;
  Duration _currentRecordingDuration = Duration.zero;
  StreamSubscription? _recordingSub;
  StreamSubscription? _playerSub;
  List<double> _waveformValues = List.filled(100, 0.0); // For live waveform

  List<double> get waveformValues => _waveformValues;

  List<VoiceNote> _notes = [];
  List<VoiceNote> get notes => _notes;
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get currentlyPlayingId => _currentlyPlayingId;
  Duration get currentRecordingDuration => _currentRecordingDuration;

  SortOption _currentSortOption = SortOption.dateDescending;
  SortOption get currentSortOption => _currentSortOption;

  Timer? _recordingTimer;

  NoteService() {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _init();
  }

  Future<void> _init() async {
    await _recorder!.openRecorder();
    await _player!.openPlayer();

    // Set the subscription duration for recording progress updates
    await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 100));

    // Subscribe to the recorder's onProgress stream for live waveform
    _recordingSub = _recorder!.onProgress!.listen((e) {
      if (e.decibels != null) {
        // Normalize decibel to 0-1 range (approx) and add to waveform values
        double normalized = (e.decibels! + 60) / 60; // Assuming -60dB is silence, 0dB is max
        normalized = normalized.clamp(0.0, 1.0);
        _waveformValues.removeAt(0);
        _waveformValues.add(normalized);
        notifyListeners(); // Update UI for waveform
      }
    });

    // Set subscription duration and listen to player progress
    await _player!.setSubscriptionDuration(const Duration(milliseconds: 100));
    _playerSub = _player!.onProgress!.listen((e) {
      if (e.position != e.duration) {
        // Could update a playback progress bar here if needed
      } else {
        stopPlayback(); // Auto-stop when finished
      }
    });

    await loadNotes();
  }

  Future<void> requestPermissions() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission not granted');
    }
    // Storage permission might be needed for older Android versions if not saving in app-specific dir
    // but path_provider usually handles app-specific directories well.
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _metadataFile async {
    final path = await _localPath;
    return File('$path/notes_metadata.json');
  }

  Future<void> loadNotes() async {
    try {
      final file = await _metadataFile;
      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> jsonData = jsonDecode(contents);
        _notes = jsonData.map((item) => VoiceNote.fromJson(item)).toList();
        // Ensure files exist, remove metadata if file is missing
        _notes.removeWhere((note) => !File(note.filePath).existsSync());
      } else {
        _notes = [];
      }
    } catch (e) {
      print("Error loading notes: $e");
      _notes = [];
    }
    sortNotes(); // Sorts by current sort option
    notifyListeners();
  }

  Future<void> _saveMetadata() async {
    final file = await _metadataFile;
    final List<Map<String, dynamic>> jsonData =
        _notes.map((note) => note.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonData));
  }

  Future<void> startRecording() async {
    await requestPermissions();
    if (_isRecording) return;

    final path = await _localPath;
    final fileName = '${const Uuid().v4()}.aac'; // Using AAC for good compression/quality
    final filePath = '$path/$fileName';

    _currentRecordingDuration = Duration.zero;
    _waveformValues = List.filled(100, 0.0); // Reset waveform
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _currentRecordingDuration = Duration(seconds: _currentRecordingDuration.inSeconds + 1);
      notifyListeners();
    });

    await _recorder!.startRecorder(
      toFile: filePath,
      codec: Codec.aacADTS,
    );
    _isRecording = true;
    notifyListeners();
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    _recordingTimer?.cancel();
    final path = await _recorder!.stopRecorder();
    _isRecording = false;
    notifyListeners();
    return path;
  }

  Future<void> saveNote(String title, String description, List<String> tags, String filePath, Duration duration) async {
    final newNote = VoiceNote(
      id: const Uuid().v4(),
      title: title.isEmpty ? 'Voice Note ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}' : title,
      description: description,
      filePath: filePath,
      createdAt: DateTime.now(),
      duration: duration,
      tags: tags,
    );
    _notes.add(newNote);
    await _saveMetadata();
    sortNotes(); // Re-sort after adding
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    final note = _notes.firstWhere((n) => n.id == id);
    final file = File(note.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    _notes.removeWhere((n) => n.id == id);
    await _saveMetadata();
    notifyListeners();
  }

  Future<void> updateNote(String id, String newTitle, String newDescription, List<String> newTags) async {
    final noteIndex = _notes.indexWhere((n) => n.id == id);
    if (noteIndex != -1) {
      _notes[noteIndex].title = newTitle;
      _notes[noteIndex].description = newDescription;
      _notes[noteIndex].tags = newTags;
      await _saveMetadata();
      notifyListeners();
    }
  }

  Future<void> togglePlayback(String noteId) async {
    final note = _notes.firstWhere((n) => n.id == noteId);
    if (_isPlaying && _currentlyPlayingId == noteId) {
      await stopPlayback();
    } else {
      if (_isPlaying && _currentlyPlayingId != null) {
        await stopPlayback(); // Stop current playback if any
      }
      _currentlyPlayingId = noteId;
      _isPlaying = true;
      notifyListeners(); // Update UI to show playing state
      await _player!.startPlayer(
        fromURI: note.filePath,
        codec: Codec.aacADTS, // Match recording codec
        whenFinished: () {
          stopPlayback();
        },
      );
    }
  }

  Future<void> stopPlayback() async {
    if (!_isPlaying) return;
    await _player!.stopPlayer();
    _isPlaying = false;
    _currentlyPlayingId = null;
    notifyListeners();
  }

  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<String> getStorageUsage() async {
    final path = await _localPath;
    final dir = Directory(path);
    int totalSize = 0;
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && (entity.path.endsWith('.aac') || entity.path.endsWith('.mp4') || entity.path.endsWith('.m4a'))) { // Common audio extensions
          totalSize += await entity.length();
        }
      }
    }
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(2)} KB';
    return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  void setSortOption(SortOption option) {
    _currentSortOption = option;
    sortNotes();
  }

  void sortNotes() {
    switch (_currentSortOption) {
      case SortOption.dateAscending:
        _notes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortOption.dateDescending:
        _notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.titleAscending:
        _notes.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SortOption.titleDescending:
        _notes.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    _player?.closePlayer();
    _recordingSub?.cancel();
    _playerSub?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }
}

enum SortOption {
  dateAscending,
  dateDescending,
  titleAscending,
  titleDescending,
}