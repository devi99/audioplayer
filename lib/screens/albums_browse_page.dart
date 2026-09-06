import 'dart:async';

import 'package:flutter/material.dart';

import '../models/library_entities.dart';
import '../services/music_library_api.dart';
import 'album_songs_page.dart';
import 'shared_library_widgets.dart';

class AlbumsBrowsePage extends StatefulWidget {
  const AlbumsBrowsePage({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  State<AlbumsBrowsePage> createState() => _AlbumsBrowsePageState();
}

class _AlbumsBrowsePageState extends State<AlbumsBrowsePage> {
  static final List<int> _decadeOptions = _buildDecadeOptions();

  late Future<List<AlbumSummary>> _albumsFuture;
  late Future<List<ArtistSummary>> _artistsFuture;
  late final TextEditingController _artistFieldController;
  late final FocusNode _artistFieldFocusNode;
  int? _selectedArtistId;
  int? _selectedDecade;

  @override
  void initState() {
    super.initState();
    _artistFieldController = TextEditingController(text: 'All artists');
    _artistFieldFocusNode = FocusNode();
    _artistsFuture = widget.api.fetchArtists();
    _reloadAlbums();
  }

  @override
  void dispose() {
    _artistFieldController.dispose();
    _artistFieldFocusNode.dispose();
    super.dispose();
  }

  static List<int> _buildDecadeOptions() {
    final currentDecade = (DateTime.now().year ~/ 10) * 10;
    const firstDecade = 1950;
    final options = <int>[];
    for (var year = currentDecade; year >= firstDecade; year -= 10) {
      options.add(year);
    }
    return options;
  }

  void _reloadAlbums() {
    _albumsFuture = widget.api.fetchAlbums(
      artistId: _selectedArtistId,
      decade: _selectedDecade,
    );
  }

  void _applyArtistFilter(int? artistId, List<ArtistSummary> artists) {
    if (_selectedArtistId == artistId) {
      return;
    }
    final selectedArtist = artists
        .where((artist) => artist.id == artistId)
        .cast<ArtistSummary?>()
        .firstWhere((artist) => artist != null, orElse: () => null);

    setState(() {
      _selectedArtistId = artistId;
      _artistFieldController.text = selectedArtist?.name ?? 'All artists';
      _reloadAlbums();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<ArtistSummary>>(
      future: _artistsFuture,
      builder: (context, artistSnapshot) {
        final artists = (artistSnapshot.data ?? const <ArtistSummary>[])
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));

        final hasSelectedArtist =
            artists.any((artist) => artist.id == _selectedArtistId);
        final selectedArtistId = hasSelectedArtist ? _selectedArtistId : null;
        final selectedArtistName = selectedArtistId == null
          ? 'All artists'
          : artists
            .firstWhere((artist) => artist.id == selectedArtistId)
            .name;

        if (_artistFieldController.text != selectedArtistName &&
          !_artistFieldFocusNode.hasFocus) {
          _artistFieldController.text = selectedArtistName;
        }

        return FutureBuilder<List<AlbumSummary>>(
          future: _albumsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return LibraryErrorState(
                message: 'Unable to load albums',
                details: snapshot.error.toString(),
              );
            }

            final albums = snapshot.data ?? const <AlbumSummary>[];
            final summaryParts = <String>[
              '${albums.length} albums',
              if (_selectedDecade != null) 'from ${_selectedDecade!}s',
              if (selectedArtistId != null)
                'for ${artists.firstWhere((artist) => artist.id == selectedArtistId).name}',
            ];
            final summary = '${summaryParts.join(' ')} in your library';

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Albums',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    summary,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final controlsOnSingleRow = constraints.maxWidth >= 700;
                      final decadeWidth =
                          controlsOnSingleRow ? 220.0 : constraints.maxWidth;
                      final artistWidth =
                          controlsOnSingleRow ? 300.0 : constraints.maxWidth;

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          SizedBox(
                            width: decadeWidth,
                            child: DropdownButtonFormField<int?>(
                              initialValue: _selectedDecade,
                              isDense: true,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Decade',
                                border: OutlineInputBorder(),
                              ),
                              items: <DropdownMenuItem<int?>>[
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('All decades'),
                                ),
                                for (final decade in _decadeOptions)
                                  DropdownMenuItem<int?>(
                                    value: decade,
                                    child: Text('${decade}s'),
                                  ),
                              ],
                              onChanged: (value) {
                                if (_selectedDecade == value) {
                                  return;
                                }
                                setState(() {
                                  _selectedDecade = value;
                                  _reloadAlbums();
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: artistWidth,
                            child: RawAutocomplete<_ArtistFilterOption>(
                              textEditingController: _artistFieldController,
                              focusNode: _artistFieldFocusNode,
                              displayStringForOption: (option) => option.label,
                              optionsBuilder: (textEditingValue) {
                                if (artistSnapshot.hasError) {
                                  return const Iterable<_ArtistFilterOption>.empty();
                                }
                                final query =
                                    textEditingValue.text.trim().toLowerCase();
                                final options = <_ArtistFilterOption>[
                                  const _ArtistFilterOption(
                                    artistId: null,
                                    label: 'All artists',
                                  ),
                                  ...artists.map(
                                    (artist) => _ArtistFilterOption(
                                      artistId: artist.id,
                                      label: artist.name,
                                    ),
                                  ),
                                ];
                                if (query.isEmpty) {
                                  return options;
                                }
                                return options.where(
                                  (option) =>
                                      option.label.toLowerCase().contains(query),
                                );
                              },
                              onSelected: (option) {
                                _applyArtistFilter(option.artistId, artists);
                              },
                              fieldViewBuilder: (context, controller, focusNode,
                                  onFieldSubmitted) {
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  enabled: !artistSnapshot.hasError,
                                  onTapOutside: (_) {
                                    focusNode.unfocus();
                                  },
                                  onTap: () {
                                    if (controller.text == 'All artists') {
                                      controller.clear();
                                    }
                                  },
                                  onFieldSubmitted: (_) {
                                    onFieldSubmitted();
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Artist',
                                    hintText: 'Type to filter artists',
                                    border: const OutlineInputBorder(),
                                    prefixIcon:
                                        const Icon(Icons.search_rounded),
                                    suffixIcon: selectedArtistId == null
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear artist filter',
                                            icon: const Icon(
                                              Icons.clear_rounded,
                                            ),
                                            onPressed: () {
                                              _applyArtistFilter(
                                                null,
                                                artists,
                                              );
                                              focusNode.unfocus();
                                            },
                                          ),
                                  ),
                                );
                              },
                              optionsViewBuilder:
                                  (context, onSelected, options) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(12),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 280,
                                        minWidth: 260,
                                      ),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        itemBuilder: (context, index) {
                                          final option = options.elementAt(index);
                                          return ListTile(
                                            dense: true,
                                            title: Text(
                                              option.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onTap: () => onSelected(option),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_selectedDecade != null ||
                              _selectedArtistId != null)
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedDecade = null;
                                  _selectedArtistId = null;
                                  _artistFieldController.text = 'All artists';
                                  _reloadAlbums();
                                });
                              },
                              icon: const Icon(Icons.filter_alt_off_rounded),
                              label: const Text('Clear filters'),
                            ),
                        ],
                      );
                    },
                  ),
                  if (artistSnapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Unable to load artist filter options: ${artistSnapshot.error}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 240,
                        mainAxisExtent: 300,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                      ),
                      itemCount: albums.length,
                      itemBuilder: (context, index) {
                        return _AlbumCard(
                            album: albums[index], api: widget.api);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ArtistFilterOption {
  const _ArtistFilterOption({required this.artistId, required this.label});

  final int? artistId;
  final String label;
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.api});

  final AlbumSummary album;
  final MusicLibraryApi api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: theme.colorScheme.surface.withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => AlbumSongsPage(album: album, api: api),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: FutureBuilder<String?>(
                  future: api.lookupAlbumImage(album),
                  builder: (context, snapshot) {
                    return LibraryArtworkFrame(
                      imageUrl: snapshot.data,
                      fallbackIcon: Icons.album_rounded,
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF6E4F2B), Color(0xFF1D1720)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Text(
                album.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                album.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

