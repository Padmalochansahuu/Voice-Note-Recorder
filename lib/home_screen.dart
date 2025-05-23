import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'note_service.dart';
import 'main.dart'; // For ThemeProvider

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Initial load, if not already handled by NoteService constructor
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<NoteService>(context, listen: false).loadNotes();
    });
  }

  void _showStorageStats() async {
    final noteService = Provider.of<NoteService>(context, listen: false);
    String usage = await noteService.getStorageUsage();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage Usage'),
        content: Text('Total space used by notes: $usage'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSortOptions() {
    final noteService = Provider.of<NoteService>(context, listen: false);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Sort By", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 10),
              _buildSortOptionTile(context, 'Date (Newest First)', SortOption.dateDescending, noteService),
              _buildSortOptionTile(context, 'Date (Oldest First)', SortOption.dateAscending, noteService),
              _buildSortOptionTile(context, 'Title (A-Z)', SortOption.titleAscending, noteService),
              _buildSortOptionTile(context, 'Title (Z-A)', SortOption.titleDescending, noteService),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildSortOptionTile(BuildContext context, String title, SortOption option, NoteService noteService) {
    bool isSelected = noteService.currentSortOption == option;
    return ListTile(
      title: Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
      onTap: () {
        noteService.setSortOption(option);
        Navigator.pop(context);
      },
    );
  }

  void _startRecordingFlow() {
    final noteService = Provider.of<NoteService>(context, listen: false);
    noteService.startRecording().then((_) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: false, // Prevent dismissing while recording
        enableDrag: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
        ),
        builder: (context) => RecordingInProgressSheet(),
      );
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting recording: $e')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final noteService = Provider.of<NoteService>(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('VoiceNoteMini'),
        actions: [
          IconButton(
            icon: Icon(themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            tooltip: 'Toggle Theme',
            onPressed: () {
              themeProvider.toggleTheme(!themeProvider.isDarkMode);
            },
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort Notes',
            onPressed: _showSortOptions,
          ),
          IconButton(
            icon: const Icon(Icons.data_usage),
            tooltip: 'Storage Stats',
            onPressed: _showStorageStats,
          ),
        ],
      ),
      body: noteService.notes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic_off_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 20),
                  Text(
                    'No voice notes yet.',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap the microphone button to start recording.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 80), // Space for FAB
              itemCount: noteService.notes.length,
              itemBuilder: (context, index) {
                final note = noteService.notes[index];
                return NoteCard(note: note);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: noteService.isRecording ? null : _startRecordingFlow,
        label: Text(noteService.isRecording ? 'Recording...' : 'Record'),
        icon: Icon(noteService.isRecording ? Icons.stop_circle_outlined : Icons.mic),
        backgroundColor: noteService.isRecording ? Colors.redAccent : Theme.of(context).floatingActionButtonTheme.backgroundColor,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class RecordingInProgressSheet extends StatelessWidget {
  const RecordingInProgressSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final noteService = Provider.of<NoteService>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom, // For keyboard
        left: 20, right: 20, top: 20
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Recording...',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Text(
            noteService.formatDuration(noteService.currentRecordingDuration),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          // Simple Live Waveform Visual
          Container(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: noteService.waveformValues.map((val) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 50),
                  height: (val * 50).clamp(2.0, 50.0), // Min height 2, max 50
                  width: 2,
                  color: themeProvider.isDarkMode ? Colors.tealAccent[200] : Colors.teal,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Discard'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                onPressed: () async {
                  await noteService.stopRecording(); // Stop and discard
                  Navigator.pop(context); // Close sheet
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt_outlined),
                label: const Text('Stop & Save'),
                onPressed: () async {
                  final filePath = await noteService.stopRecording();
                  final duration = noteService.currentRecordingDuration; // Capture before reset
                  Navigator.pop(context); // Close sheet
                  if (filePath != null) {
                    _showSaveNoteDialog(context, filePath, duration);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showSaveNoteDialog(BuildContext context, String filePath, Duration duration) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final tagsController = TextEditingController(); // For comma-separated tags

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Save Voice Note'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title (Optional)'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (Optional, comma-separated)',
                  hintText: 'e.g., work, idea, important'
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              File(filePath).delete(); // Delete the recorded file if cancelled
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final noteService = Provider.of<NoteService>(context, listen: false);
              List<String> tags = tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
              noteService.saveNote(titleController.text, descriptionController.text, tags, filePath, duration);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}


class NoteCard extends StatelessWidget {
  final VoiceNote note;
  const NoteCard({super.key, required this.note});

  void _showEditNoteDialog(BuildContext context, NoteService noteService) {
    final titleController = TextEditingController(text: note.title);
    final descriptionController = TextEditingController(text: note.description);
    final tagsController = TextEditingController(text: note.tags.join(', '));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Voice Note'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma-separated)',
                  hintText: 'e.g., work, idea'
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              List<String> newTags = tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
              noteService.updateNote(note.id, titleController.text, descriptionController.text, newTags);
              Navigator.pop(context);
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noteService = Provider.of<NoteService>(context, listen: false); // No need to listen for general card
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    note.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Consumer<NoteService>( // Consumer specifically for play button state
                  builder: (context, service, child) {
                    bool isCurrentlyPlaying = service.isPlaying && service.currentlyPlayingId == note.id;
                    return IconButton(
                      icon: Icon(
                        isCurrentlyPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Theme.of(context).primaryColor,
                        size: 32,
                      ),
                      onPressed: () => service.togglePlayback(note.id),
                    );
                  }
                )
              ],
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM dd, yyyy - hh:mm a').format(note.createdAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            if (note.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  note.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Duration: ${noteService.formatDuration(note.duration)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // Simple Waveform Placeholder (could be improved with actual data)
                // For now, let's just use an icon or a few static bars
                // Icon(Icons.bar_chart_rounded, color: Colors.grey[400]),
                _buildSimpleStaticWaveform(context, themeProvider.isDarkMode),
              ],
            ),
            if (note.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6.0,
                runSpacing: 4.0,
                children: note.tags.map((tag) => Chip(
                  label: Text(tag),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  labelStyle: TextStyle(fontSize: 12, color: themeProvider.isDarkMode ? Colors.black : Colors.teal[900]),
                  backgroundColor: themeProvider.isDarkMode ? Colors.tealAccent[100] : Colors.teal[100],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
              ),
            ],
            const SizedBox(height: 8),
            Divider(height: 1, color: Colors.grey[300]),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: Colors.blueGrey[400]),
                  tooltip: 'Edit Note',
                  onPressed: () => _showEditNoteDialog(context, noteService),
                ),
                IconButton(
                  icon: Icon(Icons.share_outlined, color: Colors.blueGrey[400]),
                  tooltip: 'Share Audio',
                  onPressed: () async {
                    final file = XFile(note.filePath);
                    await Share.shareXFiles([file], text: 'Check out this voice note: ${note.title}');
                  },
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                  tooltip: 'Delete Note',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Note'),
                        content: Text('Are you sure you want to delete "${note.title}"? This cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () {
                              noteService.deleteNote(note.id);
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('"${note.title}" deleted.'), duration: Duration(seconds: 2)),
                              );
                            },
                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
  Widget _buildSimpleStaticWaveform(BuildContext context, bool isDark) {
    // Generates a very simple, somewhat random static "waveform"
    // You could derive this from note.duration or other properties for more variety
    // For a real waveform, you'd need to process the audio file.
    final random = math.Random(note.id.hashCode); // Seed with note ID for consistency
    final color = isDark ? Colors.tealAccent[100]!.withOpacity(0.6) : Colors.teal.withOpacity(0.6);
    return Row(
      children: List.generate(15, (index) {
        double height = (random.nextDouble() * 15).clamp(2.0, 15.0);
        return Container(
          height: height,
          width: 2,
          margin: const EdgeInsets.symmetric(horizontal: 0.5),
          color: color,
        );
      }),
    );
  }
}