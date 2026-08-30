import 'package:flutter/material.dart';

import '../models/music_track.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.tracks});

  final List<MusicTrack> tracks;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String selectedTag = 'all';
  int minimumRating = 3;

  List<MusicTrack> get filteredTracks {
    return widget.tracks.where((track) {
      final matchesTag = selectedTag == 'all' || track.tags.contains(selectedTag);
      final matchesRating = track.rating >= minimumRating;
      return matchesTag && matchesRating;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tags = <String>{'all', ...widget.tracks.expand((track) => track.tags)}.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Library'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ),
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            children: tags.map((tag) {
              return ChoiceChip(
                label: Text(tag),
                selected: selectedTag == tag,
                onSelected: (_) => setState(() => selectedTag = tag),
              );
            }).toList(),
          ),
          Slider(
            value: minimumRating.toDouble(),
            min: 0,
            max: 5,
            divisions: 5,
            label: 'Minimum rating: $minimumRating',
            onChanged: (value) => setState(() => minimumRating = value.round()),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredTracks.length,
              itemBuilder: (context, index) {
                final track = filteredTracks[index];
                return ListTile(
                  title: Text(track.title),
                  subtitle: Text('${track.artist} • ${track.album}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 18),
                      Text('${track.rating}'),
                    ],
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Queued ${track.title}')),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
