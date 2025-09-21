import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/tournaments/match_details_page.dart';
import 'package:game_app/widgets/timezone_utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io';
import 'package:toastification/toastification.dart';

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

class TournamentDetailsPage extends StatefulWidget {
  final Tournament tournament;
  final String creatorName;

  const TournamentDetailsPage({
    super.key,
    required this.tournament,
    required this.creatorName,
  });

  @override
  State<TournamentDetailsPage> createState() => _TournamentDetailsPageState();
}

class _TournamentDetailsPageState extends State<TournamentDetailsPage>
    with SingleTickerProviderStateMixin {
  String? _tournamentProfileImage;
  String? _sponsorImage;
  bool _isLoading = false;
  bool _hasJoined = false;
  bool _isUmpire = false;
  String _tournamentTimezone = 'UTC';
  late TabController _tabController;
  late List<Map<String, dynamic>> _participants;
  late List<Map<String, dynamic>> _matches;
  final Map<String, Map<String, dynamic>> _leaderboardData = {};
  int _selectedEventIndex = 0;
  int _numberOfCourts = 1;
  List<String> _timeSlots = [];

  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _secondaryColor = const Color(0xFFC1DADB);
  final Color _accentColor = const Color(0xFFF4A261);
  final Color _textColor = const Color(0xFF333333);
  final Color _secondaryText = const Color(0xFF757575);
  final Color _cardBackground = const Color(0xFFFFFFFF);
  final Color _successColor = const Color(0xFF4CAF50);
  final Color _errorColor = const Color(0xFFE76F51);
  final Color _goldColor = const Color(0xFFFFD700);
  final Color _silverColor = const Color(0xFFC0C0C0);
  final Color _bronzeColor = const Color(0xFFCD7F32);

  @override
  void initState() {
    super.initState();
     _listenToMatchCompletions();
    _tabController = TabController(length: 5, vsync: this);
    _participants =
        widget.tournament.events[_selectedEventIndex].participants
            .map((id) => {'id': id, 'name': null})
            .toList();
    _matches = [];
    _tournamentProfileImage = widget.tournament.profileImage;
    _sponsorImage = widget.tournament.sponsorImage;
    _numberOfCourts =
        widget.tournament.events[_selectedEventIndex].numberOfCourts;
    _timeSlots = widget.tournament.events[_selectedEventIndex].timeSlots;

    // Initialize timezone properly
    tz.initializeTimeZones();

    // Set tournament timezone and location
    _tournamentTimezone = widget.tournament.timezone;

    // CRITICAL FIX: Initialize the location properly
    try {} catch (e) {
      // Fallback to UTC if the timezone is invalid
      debugPrint('Error setting timezone $_tournamentTimezone: $e');
      _tournamentTimezone = 'UTC';
    }

    _checkIfJoined();
    _checkIfUmpire();
    _loadParticipants();
    _loadMatches();
    _listenToTournamentUpdates();
  }

void _listenToMatchCompletions() {
  FirebaseFirestore.instance
      .collection('tournaments')
      .doc(widget.tournament.id)
      .collection('matches')
      .where('eventId', isEqualTo: widget.tournament.events[_selectedEventIndex].name)
      .snapshots()
      .listen((snapshot) {
    if (!mounted) return;
    
    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.modified) {
        final matchData = change.doc.data() as Map<String, dynamic>;
        if (matchData['completed'] == true) {
          _updateNextRoundMatches(change.doc.id, matchData);
        }
      }
    }
  });
}


Future<void> _updateNextRoundMatches(String completedMatchId, Map<String, dynamic> matchData) async {
  try {
    final winner = matchData['winner'];
    final isDoubles = matchData['matchType'].toString().toLowerCase().contains('doubles');
    
    // Find matches that reference this completed match as a previous match
    final nextMatchesQuery = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .collection('matches')
        .where('eventId', isEqualTo: widget.tournament.events[_selectedEventIndex].name)
        .where('completed', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    bool hasUpdates = false;

    for (var nextMatchDoc in nextMatchesQuery.docs) {
      final nextMatchData = nextMatchDoc.data();
      final nextMatchRef = nextMatchDoc.reference;
      var shouldUpdate = false;
      var updatedData = <String, dynamic>{};

      if (nextMatchData['previousMatch1'] == completedMatchId) {
        if (isDoubles) {
          if (nextMatchData['wasTBDTeam1'] == true) {
            updatedData['team1'] = winner == 'team1' ? matchData['team1'] : matchData['team2'];
            updatedData['team1Ids'] = winner == 'team1' ? matchData['team1Ids'] : matchData['team2Ids'];
            updatedData['team1Genders'] = winner == 'team1' ? matchData['team1Genders'] : matchData['team2Genders'];
            updatedData['wasTBDTeam1'] = false;
            shouldUpdate = true;
          }
        } else {
          if (nextMatchData['wasTBD1'] == true) {
            final winnerId = winner == 'player1' ? matchData['player1Id'] : matchData['player2Id'];
            final winnerName = winner == 'player1' ? matchData['player1'] : matchData['player2'];
            
            updatedData['player1Id'] = winnerId;
            updatedData['player1'] = winnerName;
            updatedData['wasTBD1'] = false;
            shouldUpdate = true;
          }
        }
      }

      if (nextMatchData['previousMatch2'] == completedMatchId) {
        if (isDoubles) {
          if (nextMatchData['wasTBDTeam2'] == true) {
            updatedData['team2'] = winner == 'team1' ? matchData['team1'] : matchData['team2'];
            updatedData['team2Ids'] = winner == 'team1' ? matchData['team1Ids'] : matchData['team2Ids'];
            updatedData['team2Genders'] = winner == 'team1' ? matchData['team1Genders'] : matchData['team2Genders'];
            updatedData['wasTBDTeam2'] = false;
            shouldUpdate = true;
          }
        } else {
          if (nextMatchData['wasTBD2'] == true) {
            final winnerId = winner == 'player1' ? matchData['player1Id'] : matchData['player2Id'];
            final winnerName = winner == 'player1' ? matchData['player1'] : matchData['player2'];
            
            updatedData['player2Id'] = winnerId;
            updatedData['player2'] = winnerName;
            updatedData['wasTBD2'] = false;
            shouldUpdate = true;
          }
        }
      }

      if (shouldUpdate) {
        batch.update(nextMatchRef, {
          ...updatedData,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        hasUpdates = true;
      }
    }

    if (hasUpdates) {
      await batch.commit();
      // Reload matches to reflect changes
      await _loadMatches();
    }
  } catch (e) {
    debugPrint('Error updating next round matches: $e');
  }
}


  void _listenToTournamentUpdates() {
    // Listen to the tournament document
    FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;
            if (!snapshot.exists || snapshot.data() == null) {
              debugPrint('Tournament document does not exist or is empty');
              return;
            }

            final data = snapshot.data()!;
            try {
              final updatedTournament = Tournament.fromFirestore(
                data,
                widget.tournament.id,
              );

              if (mounted) {
                setState(() {
                  _tournamentProfileImage = data['profileImage']?.toString();
                  _sponsorImage = data['sponsorImage']?.toString();
                  _numberOfCourts =
                      updatedTournament
                          .events[_selectedEventIndex]
                          .numberOfCourts;
                  _timeSlots = List<String>.from(
                    updatedTournament.events[_selectedEventIndex].timeSlots,
                  );
                  // widget.tournament is final and cannot be reassigned; update dependent state only
                });

                await _loadMatches(); // Ensure matches are reloaded
                await _generateLeaderboardData();
              }
            } catch (e) {
              debugPrint('Error processing tournament updates: $e');
              if (mounted) {
                toastification.show(
                  context: context,
                  type: ToastificationType.error,
                  title: const Text('Update Error'),
                  description: Text('Failed to process tournament data: $e'),
                  autoCloseDuration: const Duration(seconds: 2),
                );
              }
            }
          },
          onError: (e) {
            debugPrint('Error in tournament updates: $e');
            if (mounted) {
              toastification.show(
                context: context,
                type: ToastificationType.error,
                title: const Text('Update Error'),
                description: Text('Failed to update tournament data: $e'),
                autoCloseDuration: const Duration(seconds: 2),
              );
            }
          },
        );

    // Add listener for matches subcollection
    FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .collection('matches')
        .where(
          'eventId',
          isEqualTo: widget.tournament.events[_selectedEventIndex].name,
        )
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;
            try {
              final newMatches =
                  snapshot.docs.map((doc) {
                    return {'matchId': doc.id, ...doc.data()};
                  }).toList();

              if (mounted) {
                setState(() {
                  _matches = newMatches;
                });
                await _generateLeaderboardData();
              }
            } catch (e) {
              debugPrint('Error processing matches updates: $e');
              if (mounted) {
                toastification.show(
                  context: context,
                  type: ToastificationType.error,
                  title: const Text('Update Error'),
                  description: Text('Failed to process matches data: $e'),
                  autoCloseDuration: const Duration(seconds: 2),
                );
              }
            }
          },
          onError: (e) {
            debugPrint('Error in matches updates listener: $e');
            if (mounted) {
              toastification.show(
                context: context,
                type: ToastificationType.error,
                title: const Text('Update Error'),
                description: Text('Failed to update matches data: $e'),
                autoCloseDuration: const Duration(seconds: 2),
              );
            }
          },
        );
  }

  Future<List<Map<String, dynamic>>> _loadParticipantNames(
    List<String> participantIds,
  ) async {
    final updatedParticipants = <Map<String, dynamic>>[];
    for (var id in participantIds) {
      try {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(id).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          updatedParticipants.add({
            'id': id,
            'name':
                '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                    .trim(),
            'firstName': userData['firstName'],
            'lastName': userData['lastName'],
          });
        } else {
          updatedParticipants.add({
            'id': id,
            'name': 'Unknown Player',
            'firstName': 'Unknown',
            'lastName': '',
          });
        }
      } catch (e) {
        debugPrint('Error loading user $id: $e');
        updatedParticipants.add({
          'id': id,
          'name': 'Error Loading',
          'firstName': 'Error',
          'lastName': '',
        });
      }
    }
    return updatedParticipants;
  }


void _showEditMatchDialog(Map<String, dynamic> match, int matchIndex) {
  final isDoubles = match['matchType'].toString().toLowerCase().contains('doubles');
  final selectedEvent = widget.tournament.events[_selectedEventIndex];
  
  showDialog(
    context: context,
    builder: (context) => _EditMatchDialog(
      match: match,
      isDoubles: isDoubles,
      tournamentId: widget.tournament.id,
      eventName: selectedEvent.name,
      participants: _participants,
      availablePlayers: _getAvailablePlayersForEdit(match, isDoubles),
      onSave: (updatedMatch) => _updateMatch(matchIndex, updatedMatch),
      primaryColor: _primaryColor,
      accentColor: _accentColor,
      textColor: _textColor,
      secondaryText: _secondaryText,
      cardBackground: _cardBackground,
      successColor: _successColor,
    ),
  );
}


List<Map<String, dynamic>> _getAvailablePlayersForEdit(Map<String, dynamic> match, bool isDoubles) {
  final allParticipants = List<Map<String, dynamic>>.from(_participants);
  final unavailablePlayers = <String>{};

  // Get players already in other matches in the same round
  final sameRoundMatches = _matches.where((m) => 
      m['round'] == match['round'] && 
      m['matchId'] != match['matchId'] &&
      m['completed'] != true
  ).toList();

  for (var otherMatch in sameRoundMatches) {
    if (isDoubles) {
      final team1Ids = List<String>.from(otherMatch['team1Ids'] ?? []);
      final team2Ids = List<String>.from(otherMatch['team2Ids'] ?? []);
      unavailablePlayers.addAll(team1Ids);
      unavailablePlayers.addAll(team2Ids);
    } else {
      unavailablePlayers.add(otherMatch['player1Id']);
      unavailablePlayers.add(otherMatch['player2Id']);
    }
  }

  // Also exclude players from the opposite side of the same match
  if (isDoubles) {
    if (match['wasTBDTeam1'] == true) {
      final team2Ids = List<String>.from(match['team2Ids'] ?? []);
      unavailablePlayers.addAll(team2Ids);
    }
    if (match['wasTBDTeam2'] == true) {
      final team1Ids = List<String>.from(match['team1Ids'] ?? []);
      unavailablePlayers.addAll(team1Ids);
    }
  } else {
    if (match['wasTBD1'] == true) {
      unavailablePlayers.add(match['player2Id']);
    }
    if (match['wasTBD2'] == true) {
      unavailablePlayers.add(match['player1Id']);
    }
  }

  return allParticipants.where((participant) => 
      !unavailablePlayers.contains(participant['id'])
  ).toList();
}

Future<void> _updateMatch(int matchIndex, Map<String, dynamic> updatedMatch) async {
  setState(() {
    _isLoading = true;
  });

  try {
    final matchId = _matches[matchIndex]['matchId'];
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .collection('matches')
        .doc(matchId)
        .update({
          ...updatedMatch,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

    setState(() {
      _matches[matchIndex] = {..._matches[matchIndex], ...updatedMatch};
    });

    toastification.show(
      context: context,
      type: ToastificationType.success,
      title: const Text('Match Updated'),
      description: const Text('Match details have been updated successfully.'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  } catch (e) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: const Text('Update Failed'),
      description: Text('Failed to update match: $e'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}



  Future<void> _loadParticipants() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final participants =
          widget.tournament.events[_selectedEventIndex].participants;
      final updatedParticipants = await _loadParticipantNames(participants);
      if (mounted) {
        setState(() {
          _participants = updatedParticipants;
        });
        await _generateLeaderboardData();
      }
    } catch (e) {
      debugPrint('Error loading participants: $e');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Load Participants Failed'),
          description: Text('Failed to load participants: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMatches() async {
    try {
      final matchesSnapshot =
          await FirebaseFirestore.instance
              .collection('tournaments')
              .doc(widget.tournament.id)
              .collection('matches')
              .where(
                'eventId',
                isEqualTo: widget.tournament.events[_selectedEventIndex].name,
              )
              .get();

      if (mounted) {
        setState(() {
          _matches =
              matchesSnapshot.docs.map((doc) {
                return {'matchId': doc.id, ...doc.data()};
              }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading matches: $e');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to load matches: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _checkIfJoined() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userId = authState.user.uid;
      setState(() {
        _hasJoined = widget.tournament.events[_selectedEventIndex].participants
            .contains(userId);
      });
    }
  }

  void _checkIfUmpire() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userEmail = authState.user.email;
      if (userEmail != null) {
        final umpireDoc =
            await FirebaseFirestore.instance
                .collection('umpire_credentials')
                .doc(userEmail)
                .get();
        if (mounted) {
          setState(() {
            _isUmpire = umpireDoc.exists;
          });
        }
      }
    }
  }

  bool get _canGenerateMatches {
    final now = DateTime.now().toUtc();
    return now.isAfter(widget.tournament.registrationEnd);
  }


bool get _hasStartedOrCompletedMatches {
  return _matches.any((match) => 
      match['completed'] == true || 
      (match['liveScores'] != null && 
       match['liveScores']['isLive'] == true) ||
      (match['umpire'] != null && 
       match['umpire']['name'] != null && 
       match['umpire']['name'].toString().isNotEmpty));
}



Future<void> _resetMatches() async {
  if (_isLoading || !_canGenerateMatches || _hasStartedOrCompletedMatches) return;
  
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        'Reset All Matches?',
        style: GoogleFonts.poppins(
          color: _textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        'This will delete all current matches and umpire assignments for the selected event. This action cannot be undone.',
        style: GoogleFonts.poppins(color: _secondaryText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: GoogleFonts.poppins(color: _secondaryText),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Reset',
            style: GoogleFonts.poppins(
              color: _errorColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  setState(() {
    _isLoading = true;
  });

  try {
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final matchDocs = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .collection('matches')
        .where('eventId', isEqualTo: selectedEvent.name)
        .get();

    // Delete all matches from Firestore (this will also remove umpire assignments)
    for (var doc in matchDocs.docs) {
      await doc.reference.delete();
    }

    // CRITICAL: Also clear any umpire assignments in the tournament document
    // if they're stored there (adjust this based on your data structure)
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .get();

    final tournamentData = tournamentDoc.data();
    if (tournamentData != null && tournamentData.containsKey('umpireAssignments')) {
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({
            'umpireAssignments': FieldValue.delete(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
    }

    // Update local state
    if (mounted) {
      setState(() {
        _matches = [];
      });
      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Matches Reset'),
        description: const Text('All matches and umpire assignments have been successfully reset.'),
        autoCloseDuration: const Duration(seconds: 2),
      );
    }
  } catch (e) {
    if (mounted) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Reset Failed'),
        description: Text('Failed to reset matches: $e'),
        autoCloseDuration: const Duration(seconds: 2),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}


  Future<void> _uploadTournamentImage() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final file = File(pickedFile.path);
      final storageRef = FirebaseStorage.instance.ref().child(
        'tournament_images/${widget.tournament.id}.jpg',
      );
      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'profileImage': downloadUrl});

      if (mounted) {
        setState(() {
          _tournamentProfileImage = downloadUrl;
        });
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Image Uploaded'),
          description: const Text('Tournament image updated successfully!'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Upload Failed'),
          description: Text('Failed to upload image: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _uploadSponsorImage() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final file = File(pickedFile.path);
      final storageRef = FirebaseStorage.instance.ref().child(
        'sponsor_images/${widget.tournament.id}.jpg',
      );
      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'sponsorImage': downloadUrl});

      if (mounted) {
        setState(() {
          _sponsorImage = downloadUrl;
        });
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Sponsor Image Uploaded'),
          description: const Text('Sponsor image updated successfully!'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Upload Failed'),
          description: Text('Failed to upload sponsor image: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showImageOptionsDialog(bool isCreator) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: _cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Image Options',
              style: GoogleFonts.poppins(
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.visibility, color: _accentColor),
                  title: Text(
                    'View Tournament Image',
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showFullImageDialog(
                      _tournamentProfileImage,
                      'Tournament Image',
                    );
                  },
                ),
                if (isCreator)
                  ListTile(
                    leading: Icon(Icons.edit, color: _accentColor),
                    title: Text(
                      'Edit Tournament Image',
                      style: GoogleFonts.poppins(
                        color: _textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _uploadTournamentImage();
                    },
                  ),
                if (_sponsorImage != null && _sponsorImage!.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.visibility, color: _accentColor),
                    title: Text(
                      'View Sponsor Image',
                      style: GoogleFonts.poppins(
                        color: _textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showFullImageDialog(_sponsorImage, 'Sponsor Image');
                    },
                  ),
                if (isCreator)
                  ListTile(
                    leading: Icon(Icons.edit, color: _accentColor),
                    title: Text(
                      'Edit Sponsor Image',
                      style: GoogleFonts.poppins(
                        color: _textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _uploadSponsorImage();
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(color: _secondaryText),
                ),
              ),
            ],
          ),
    );
  }

  void _showFullImageDialog(String? imageUrl, String title) {
    final isLocalFile = imageUrl?.startsWith('file://') ?? false;
    final isAsset = imageUrl?.startsWith('assets/') ?? false;

    showDialog(
      context: context,
      builder:
          (_) => Dialog(
            backgroundColor: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7,
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                  ),
                  child:
                      imageUrl != null && imageUrl.isNotEmpty
                          ? isLocalFile
                              ? Image.file(
                                File(imageUrl.replaceFirst('file://', '')),
                                fit: BoxFit.contain,
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                        _buildPlaceholderImage(),
                              )
                              : isAsset
                              ? Image.asset(
                                imageUrl,
                                fit: BoxFit.contain,
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                        _buildPlaceholderImage(),
                              )
                              : Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                        _buildPlaceholderImage(),
                              )
                          : _buildPlaceholderImage(),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Image.asset('assets/tournament_placholder.jpg', fit: BoxFit.contain);
  }

  Future<void> _generateLeaderboardData() async {
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final isDoubles = selectedEvent.matchType.toLowerCase().contains('doubles');
    final competitors = _participants;

    _leaderboardData.clear();

    for (var competitor in competitors) {
      final competitorId = competitor['id'] as String;
      final name = competitor['name'] as String? ?? 'Unknown';
      int score = 0;

      for (var match in _matches) {
        if (match['completed'] == true && match['winner'] != null) {
          final winner = match['winner'] as String;
          if (isDoubles) {
            final team1Ids = List<String>.from(match['team1Ids'] ?? []);
            final team2Ids = List<String>.from(match['team2Ids'] ?? []);
            if ((winner == 'team1' && team1Ids.contains(competitorId)) ||
                (winner == 'team2' && team2Ids.contains(competitorId))) {
              score += 1;
            }
          } else {
            final winnerId =
                winner == 'player1' ? match['player1Id'] : match['player2Id'];
            if (winnerId == competitorId) {
              score += 1;
            }
          }
        }
      }

      _leaderboardData[competitorId] = {'name': name, 'score': score};
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<Map<String, dynamic>> _getUserData(String userId) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data() ?? {'firstName': 'Unknown', 'lastName': ''};
  }

  Future<String> _getDisplayName(String userId) async {
    if (userId == 'TBD' || userId == 'bye') return 'TBD';
    final userData = await _getUserData(userId);
    return '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
        .trim();
  }

  Future<String> _getUserEmail(String userId) async {
    if (userId == 'bye') return 'N/A';
    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
      if (userDoc.exists) {
        return userDoc.data()?['email'] ?? 'No email';
      }
      return 'User not found';
    } catch (e) {
      return 'Error loading email';
    }
  }

  Future<void> _cleanUpOldTimeSlotsFromMatches(
    List<String> newTimeSlots,
  ) async {
    try {
      final selectedEvent = widget.tournament.events[_selectedEventIndex];
      final matchDocs =
          await FirebaseFirestore.instance
              .collection('tournaments')
              .doc(widget.tournament.id)
              .collection('matches')
              .where('eventId', isEqualTo: selectedEvent.name)
              .get();

      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (var doc in matchDocs.docs) {
        final matchData = doc.data();
        final currentTimeSlot = matchData['timeSlot'] as String?;

        // If the match has a time slot that's not in the new list, update it
        if (currentTimeSlot != null &&
            !newTimeSlots.contains(currentTimeSlot)) {
          // Assign the first available time slot or a default
          final defaultTimeSlot =
              newTimeSlots.isNotEmpty ? newTimeSlots[0] : 'TBD';

          batch.update(doc.reference, {
            'timeSlot': defaultTimeSlot,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        await batch.commit();
        debugPrint('Updated time slots for ${matchDocs.docs.length} matches');
      }
    } catch (e) {
      debugPrint('Error cleaning up old time slots: $e');
      // Consider showing a more specific error message for debugging
    }
  }

  Future<void> _configureTournamentSettings() async {
    if (_isLoading) return;

    int tempCourts = _numberOfCourts;
    List<String> tempTimeSlots = List.from(_timeSlots);

    // Time selection variables
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    final TextEditingController courtsController = TextEditingController(
      text: tempCourts.toString(),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (context, setStateDialog) => Dialog(
                  backgroundColor: _cardBackground,
                  surfaceTintColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.85,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Icon(
                                  Icons.settings,
                                  color: _accentColor,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Configure Tournament Settings',
                                    style: GoogleFonts.poppins(
                                      color: _textColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Courts Selection
                            Text(
                              'Number of Courts',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: _textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Numeric input for courts with validation
                            TextFormField(
                              controller: courtsController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Enter number of courts (1-20)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _accentColor.withOpacity(0.3),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: _accentColor),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontSize: 16,
                              ),
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  final courtCount = int.tryParse(value) ?? 0;
                                  if (courtCount >= 1 && courtCount <= 20) {
                                    setStateDialog(() {
                                      tempCourts = courtCount;
                                    });
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '* Must be a number between 1 and 20',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: _secondaryText,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Time Slots Section
                            Text(
                              'Time Slots',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: _textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Current Time Slots
                            if (tempTimeSlots.isNotEmpty) ...[
                              Text(
                                'Current Time Slots:',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: _secondaryText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.of(context).size.height * 0.2,
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: tempTimeSlots.length,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.05,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                        leading: Icon(
                                          Icons.access_time,
                                          color: _accentColor,
                                          size: 20,
                                        ),
                                        title: Text(
                                          tempTimeSlots[index],
                                          style: GoogleFonts.poppins(
                                            color: _textColor,
                                            fontSize: 14,
                                          ),
                                        ),
                                        trailing: IconButton(
                                          icon: Icon(
                                            Icons.delete_outline,
                                            color: _errorColor,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            setStateDialog(() {
                                              tempTimeSlots.removeAt(index);
                                            });
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Add Time Slot Section
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add New Time Slot',
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      color: _textColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // Time selection in a column for better mobile responsiveness
                                  Column(
                                    children: [
                                      // Start Time
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Start Time',
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: _secondaryText,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          InkWell(
                                            onTap: () async {
                                              final selectedTime = await showTimePicker(
                                                context: context,
                                                initialTime:
                                                    startTime ??
                                                    TimeOfDay.now(),
                                                builder: (context, child) {
                                                  return Theme(
                                                    data: ThemeData.light()
                                                        .copyWith(
                                                          colorScheme:
                                                              ColorScheme.light(
                                                                primary:
                                                                    _accentColor,
                                                                onPrimary:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                        ),
                                                    child: child!,
                                                  );
                                                },
                                              );
                                              if (selectedTime != null) {
                                                setStateDialog(() {
                                                  startTime = selectedTime;
                                                });
                                              }
                                            },
                                            child: Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: _accentColor
                                                      .withOpacity(0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    startTime != null
                                                        ? "${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}"
                                                        : 'Select start time',
                                                    style: GoogleFonts.poppins(
                                                      color:
                                                          startTime != null
                                                              ? _textColor
                                                              : _secondaryText,
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.access_time,
                                                    color: _accentColor,
                                                    size: 20,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 12),

                                      // End Time
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'End Time',
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: _secondaryText,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          InkWell(
                                            onTap: () async {
                                              final selectedTime = await showTimePicker(
                                                context: context,
                                                initialTime:
                                                    endTime ??
                                                    (startTime ??
                                                            TimeOfDay.now())
                                                        .replacing(
                                                          hour:
                                                              (startTime ??
                                                                      TimeOfDay.now())
                                                                  .hour +
                                                              1,
                                                        ),
                                                builder: (context, child) {
                                                  return Theme(
                                                    data: ThemeData.light()
                                                        .copyWith(
                                                          colorScheme:
                                                              ColorScheme.light(
                                                                primary:
                                                                    _accentColor,
                                                                onPrimary:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                        ),
                                                    child: child!,
                                                  );
                                                },
                                              );
                                              if (selectedTime != null) {
                                                setStateDialog(() {
                                                  endTime = selectedTime;
                                                });
                                              }
                                            },
                                            child: Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: _accentColor
                                                      .withOpacity(0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    endTime != null
                                                        ? "${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}"
                                                        : 'Select end time',
                                                    style: GoogleFonts.poppins(
                                                      color:
                                                          endTime != null
                                                              ? _textColor
                                                              : _secondaryText,
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.access_time,
                                                    color: _accentColor,
                                                    size: 20,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed:
                                          startTime != null && endTime != null
                                              ? () {
                                                // Validate time order
                                                if (_isTimeAfter(
                                                  startTime!,
                                                  endTime!,
                                                )) {
                                                  toastification.show(
                                                    context: context,
                                                    type:
                                                        ToastificationType
                                                            .error,
                                                    title: const Text(
                                                      'Invalid Time Range',
                                                    ),
                                                    description: const Text(
                                                      'End time must be after start time',
                                                    ),
                                                    autoCloseDuration:
                                                        const Duration(
                                                          seconds: 2,
                                                        ),
                                                  );
                                                  return;
                                                }

                                                final timeSlot =
                                                    "${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}-"
                                                    "${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}";

                                                if (!tempTimeSlots.contains(
                                                  timeSlot,
                                                )) {
                                                  setStateDialog(() {
                                                    tempTimeSlots.add(timeSlot);
                                                    tempTimeSlots
                                                        .sort(); // Sort time slots
                                                    startTime = null;
                                                    endTime = null;
                                                  });
                                                } else {
                                                  toastification.show(
                                                    context: context,
                                                    type:
                                                        ToastificationType.info,
                                                    title: const Text(
                                                      'Duplicate Time Slot',
                                                    ),
                                                    description: const Text(
                                                      'This time slot already exists',
                                                    ),
                                                    autoCloseDuration:
                                                        const Duration(
                                                          seconds: 2,
                                                        ),
                                                  );
                                                }
                                              }
                                              : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _accentColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                      child: Text(
                                        'Add Time Slot',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Action buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _secondaryText,
                                  ),
                                  child: Text(
                                    'Cancel',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () async {
                                    // Validate courts input
                                    final courtCount =
                                        int.tryParse(courtsController.text) ??
                                        0;
                                    if (courtCount < 1 || courtCount > 20) {
                                      toastification.show(
                                        context: context,
                                        type: ToastificationType.error,
                                        title: const Text(
                                          'Invalid Court Count',
                                        ),
                                        description: const Text(
                                          'Please enter a number between 1 and 20',
                                        ),
                                        autoCloseDuration: const Duration(
                                          seconds: 2,
                                        ),
                                      );
                                      return;
                                    }

                                    if (tempTimeSlots.isEmpty) {
                                      toastification.show(
                                        context: context,
                                        type: ToastificationType.warning,
                                        title: const Text(
                                          'Time Slots Required',
                                        ),
                                        description: const Text(
                                          'Please add at least one time slot',
                                        ),
                                        autoCloseDuration: const Duration(
                                          seconds: 2,
                                        ),
                                      );
                                      return;
                                    }

                                    // Return the configuration data instead of updating directly
                                    Navigator.pop(context, {
                                      'courts': courtCount,
                                      'timeSlots': List<String>.from(
                                        tempTimeSlots,
                                      ),
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _successColor,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(
                                    'Save Changes',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ),
    );

    // Handle the result outside the dialog
    if (result != null) {
      setState(() {
        _isLoading = true;
      });

      try {
        final newCourts = result['courts'] as int;
        final newTimeSlots = result['timeSlots'] as List<String>;

        // Update the tournament document
        final updatedEvents =
            widget.tournament.events.asMap().entries.map((entry) {
              if (entry.key == _selectedEventIndex) {
                return Event(
                  name: entry.value.name,
                  format: entry.value.format,
                  level: entry.value.level,
                  maxParticipants: entry.value.maxParticipants,
                  bornAfter: entry.value.bornAfter,
                  matchType: entry.value.matchType,
                  matches: entry.value.matches,
                  participants: entry.value.participants,
                  numberOfCourts: newCourts,
                  timeSlots: newTimeSlots,
                );
              }
              return entry.value;
            }).toList();

        // Update Firestore
        await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournament.id)
            .update({
              'events': updatedEvents.map((e) => e.toFirestore()).toList(),
              'lastUpdated': FieldValue.serverTimestamp(),
            });

        // Clean up old time slots from matches
        await _cleanUpOldTimeSlotsFromMatches(newTimeSlots);

        // Update local state after successful Firestore update
        if (mounted) {
          setState(() {
            _numberOfCourts = newCourts;
            _timeSlots = newTimeSlots;
          });
          toastification.show(
            context: context,
            type: ToastificationType.success,
            title: const Text('Settings Updated'),
            description: const Text(
              'Tournament settings updated successfully!',
            ),
            autoCloseDuration: const Duration(seconds: 2),
          );
        }
      } catch (e) {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.error,
            title: const Text('Update Failed'),
            description: Text('Failed to update settings: ${e.toString()}'),
            autoCloseDuration: const Duration(seconds: 2),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  bool _isTimeAfter(TimeOfDay time1, TimeOfDay time2) {
    if (time1.hour > time2.hour) return true;
    if (time1.hour == time2.hour && time1.minute >= time2.minute) return true;
    return false;
  }

// Add these methods to the _TournamentDetailsPageState class

// Update the _generateMatches method's switch statement to include new formats
Future<void> _generateMatches() async {
  if (_isLoading || !_canGenerateMatches) return;

  setState(() {
    _isLoading = true;
  });

  try {
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final isDoubles = selectedEvent.matchType.toLowerCase().contains('doubles');
    final competitors = List<Map<String, dynamic>>.from(_participants);

    if (competitors.length < 2) {
      throw 'Need at least 2 ${isDoubles ? 'players for team formation' : 'participants'} to schedule matches.';
    }

    // Enhanced validation for mixed doubles
    if (isDoubles && selectedEvent.matchType.toLowerCase().contains('mixed')) {
      final maleCount = await _countParticipantsByGender(competitors, 'male');
      final femaleCount = await _countParticipantsByGender(competitors, 'female');

      if (maleCount == 0 || femaleCount == 0) {
        throw 'Mixed doubles requires both male and female participants. Current: $maleCount males, $femaleCount females.';
      }

      if (math.min(maleCount, femaleCount) < 1) {
        throw 'Need at least 1 male and 1 female participant for mixed doubles teams.';
      }
    }

    if (_numberOfCourts < 1) {
      throw 'No courts configured. Please set up courts in tournament settings.';
    }

    if (_timeSlots.isEmpty) {
      throw 'No time slots configured. Please set up time slots in tournament settings.';
    }

    List<Map<String, dynamic>> competitorsList;

    if (isDoubles) {
      competitorsList = await _createDoublesTeams(competitors, selectedEvent.matchType);
      
      if (competitorsList.isEmpty) {
        throw 'Unable to create teams. Please ensure proper gender distribution for mixed doubles.';
      }

      if (competitorsList.length < 2) {
        throw 'Need at least 2 teams to schedule matches. Only ${competitorsList.length} team(s) could be formed.';
      }
    } else {
      competitorsList = competitors;
    }

    final newMatches = <Map<String, dynamic>>[];
    int currentTimeSlotIndex = 0;
    int currentCourt = 1;

    // Updated switch statement with new formats
    switch (selectedEvent.format.toLowerCase()) {
      case 'knockout':
        await _generateKnockoutMatches(
          competitorsList, isDoubles, selectedEvent, newMatches,
          currentTimeSlotIndex, currentCourt,
        );
        break;

      case 'round-robin':
        await _generateRoundRobinMatches(
          competitorsList, isDoubles, selectedEvent, newMatches,
          currentTimeSlotIndex, currentCourt,
        );
        break;

      case 'swiss format':
        await _generateSwissFormatMatches(
          competitorsList, isDoubles, selectedEvent, newMatches,
          currentTimeSlotIndex, currentCourt,
        );
        break;

      case 'ladder':
        await _generateLadderMatches(
          competitorsList, isDoubles, selectedEvent, newMatches,
          currentTimeSlotIndex, currentCourt,
        );
        break;

      case 'double elimination':
        await _generateDoubleEliminationMatches(
          competitorsList, isDoubles, selectedEvent, newMatches,
          currentTimeSlotIndex, currentCourt,
        );
        break;

      case 'group + knockout':
        await _generateGroupKnockoutMatches(
          competitorsList, isDoubles, selectedEvent, newMatches,
          currentTimeSlotIndex, currentCourt,
        );
        break;

      case 'team format':
        // Team format is same as mixed doubles, already handled above
        await _generateRoundRobinMatches(
          competitorsList, isDoubles, selectedEvent, newMatches,
          currentTimeSlotIndex, currentCourt,
        );
        break;

      default:
        throw 'Unsupported tournament format: ${selectedEvent.format}';
    }

    // Save matches to Firestore
    await _saveMatchesToFirestore(newMatches, selectedEvent);

    if (mounted) {
      setState(() {
        _matches = newMatches;
      });
      await _generateLeaderboardData();

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Matches Scheduled'),
        description: Text(
          'Successfully generated ${newMatches.length} matches with ${isDoubles ? competitorsList.length : competitors.length} ${isDoubles ? 'teams' : 'participants'}!',
        ),
        autoCloseDuration: const Duration(seconds: 3),
      );
    }
  } catch (e) {
    if (mounted) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Match Generation Failed'),
        description: Text('$e'),
        autoCloseDuration: const Duration(seconds: 4),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

// Swiss Format Implementation
Future<void> _generateSwissFormatMatches(
  List<Map<String, dynamic>> competitors,
  bool isDoubles,
  Event selectedEvent,
  List<Map<String, dynamic>> newMatches,
  int currentTimeSlotIndex,
  int currentCourt,
) async {
  final participantCount = competitors.length;
  
  // Calculate number of rounds (typically log2 of participants, minimum 3)
  final numberOfRounds = math.max(3, (math.log(participantCount) / math.log(2)).ceil());
  
  // Track player scores and opponents faced
  final playerScores = <String, int>{};
  final playerOpponents = <String, Set<String>>{};
  
  // Initialize tracking
  for (var competitor in competitors) {
    final id = isDoubles ? competitor['teamId'] : competitor['id'];
    playerScores[id] = 0;
    playerOpponents[id] = <String>{};
  }

  for (int round = 1; round <= numberOfRounds; round++) {
    List<Map<String, dynamic>> availableCompetitors = List.from(competitors);
    List<Map<String, dynamic>> roundMatches = [];

    if (round == 1) {
      // First round: random or seeded pairing
      availableCompetitors.shuffle();
    } else {
      // Subsequent rounds: pair by similar scores
      availableCompetitors.sort((a, b) {
        final aId = isDoubles ? a['teamId'] : a['id'];
        final bId = isDoubles ? b['teamId'] : b['id'];
        final aScore = playerScores[aId] ?? 0;
        final bScore = playerScores[bId] ?? 0;
        return bScore.compareTo(aScore); // Higher scores first
      });
    }

    // Pair players for this round
    while (availableCompetitors.length >= 2) {
      Map<String, dynamic>? player1;
      Map<String, dynamic>? player2;

      // Find a valid pairing
      for (int i = 0; i < availableCompetitors.length; i++) {
        player1 = availableCompetitors[i];
        final player1Id = isDoubles ? player1['teamId'] : player1['id'];

        for (int j = i + 1; j < availableCompetitors.length; j++) {
          player2 = availableCompetitors[j];
          final player2Id = isDoubles ? player2['teamId'] : player2['id'];

          // Check if they haven't played before
          if (!playerOpponents[player1Id]!.contains(player2Id)) {
            // Valid pairing found
            availableCompetitors.removeAt(j); // Remove j first (higher index)
            availableCompetitors.removeAt(i); // Then remove i
            
            // Record that they've played each other
            playerOpponents[player1Id]!.add(player2Id);
            playerOpponents[player2Id]!.add(player1Id);
            
            break;
          }
          player2 = null; // Reset if not valid
        }
        
        if (player2 != null) break; // Found a pairing
        player1 = null; // Reset if no pairing found
      }

      if (player1 != null && player2 != null) {
        final matchData = await _createMatchData(
          player1, player2, selectedEvent, round, roundMatches.length + 1,
          currentTimeSlotIndex, currentCourt, isDoubles,
        );

        roundMatches.add(matchData);
        
        // Update scheduling positions
        final scheduleUpdate = _updateSchedulePosition(currentCourt, currentTimeSlotIndex);
        currentCourt = scheduleUpdate['court']!;
        currentTimeSlotIndex = scheduleUpdate['timeSlotIndex']!;
      } else {
        // No valid pairing found for remaining players
        break;
      }
    }

    // Handle bye if odd number of players
    if (availableCompetitors.length == 1) {
      final byePlayer = availableCompetitors.first;
      final byeMatchData = await _createByeMatch(
        byePlayer, selectedEvent, round, currentTimeSlotIndex, currentCourt, isDoubles,
      );
      
      roundMatches.add(byeMatchData);
      
      // Award point for bye
      final byeId = isDoubles ? byePlayer['teamId'] : byePlayer['id'];
      playerScores[byeId] = (playerScores[byeId] ?? 0) + 1;
    }

    newMatches.addAll(roundMatches);

    // Update scores based on match results (simulate for now, will be updated when matches are completed)
    // In a real implementation, this would be done when match results are entered
    for (var match in roundMatches) {
      if (match['isBye'] == true) continue; // Skip bye matches
      
      // For now, we'll leave scores at 0 until matches are actually played
      // The scoring will be handled in the match completion logic
    }
  }
}

// Ladder Tournament Implementation  
Future<void> _generateLadderMatches(
  List<Map<String, dynamic>> competitors,
  bool isDoubles,
  Event selectedEvent,
  List<Map<String, dynamic>> newMatches,
  int currentTimeSlotIndex,
  int currentCourt,
) async {
  // Initialize ladder rankings (can be random or based on some criteria)
  final ladderRankings = List<Map<String, dynamic>>.from(competitors);
  
  // Shuffle to create initial random ladder positions
  // In a real implementation, you might want to seed based on player ratings
  ladderRankings.shuffle();

  // For initial setup, create some challenge matches
  // In a real ladder system, these would be ongoing based on player challenges
  
  final maxChallengeDistance = math.min(3, ladderRankings.length - 1); // Can challenge up to 3 positions above
  
  for (int challengerIndex = 1; challengerIndex < ladderRankings.length; challengerIndex++) {
    // Each player can challenge someone above them
    final challenger = ladderRankings[challengerIndex];
    
    // Randomly select someone above them to challenge (within challenge distance)
    final maxTargetIndex = math.max(0, challengerIndex - maxChallengeDistance);
    final targetIndex = math.Random().nextInt(challengerIndex - maxTargetIndex) + maxTargetIndex;
    final target = ladderRankings[targetIndex];

    final matchData = await _createMatchData(
      challenger, target, selectedEvent, 1, newMatches.length + 1,
      currentTimeSlotIndex, currentCourt, isDoubles,
    );

    // Add ladder-specific metadata
    matchData['ladderChallenge'] = true;
    matchData['challengerPosition'] = challengerIndex + 1;
    matchData['targetPosition'] = targetIndex + 1;
    matchData['description'] = 'Ladder Challenge: Position ${challengerIndex + 1} challenges Position ${targetIndex + 1}';

    newMatches.add(matchData);

    // Update scheduling positions
    final scheduleUpdate = _updateSchedulePosition(currentCourt, currentTimeSlotIndex);
    currentCourt = scheduleUpdate['court']!;
    currentTimeSlotIndex = scheduleUpdate['timeSlotIndex']!;
    
    // Limit initial challenges to avoid too many matches
    if (newMatches.length >= competitors.length) break;
  }
}

// Double Elimination Implementation (placeholder - needs your specification)
Future<void> _generateDoubleEliminationMatches(
  List<Map<String, dynamic>> competitors,
  bool isDoubles,
  Event selectedEvent,
  List<Map<String, dynamic>> newMatches,
  int currentTimeSlotIndex,
  int currentCourt,
) async {
  // TODO: Implement double elimination with winners and losers brackets
  // Need clarification on the exact structure you want
  throw 'Double Elimination format needs specification - please provide details on winners/losers bracket structure';
}

// Group + Knockout Implementation (placeholder - needs your specification)
Future<void> _generateGroupKnockoutMatches(
  List<Map<String, dynamic>> competitors,
  bool isDoubles,
  Event selectedEvent,
  List<Map<String, dynamic>> newMatches,
  int currentTimeSlotIndex,
  int currentCourt,
) async {
  // TODO: Implement group stage followed by knockout
  // Need clarification on group size, advancement rules, etc.
  throw 'Group + Knockout format needs specification - please provide details on group size and advancement rules';
}

// Helper method to update Swiss format scores when matches are completed
Future<void> _updateSwissFormatScores(String matchId, String winner) async {
  // This would be called when a Swiss format match is completed
  // Update the player scores in the database
  try {
    final matchDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .collection('matches')
        .doc(matchId)
        .get();

    if (matchDoc.exists) {
      final matchData = matchDoc.data()!;
      
      // Update Swiss format scores
      // This is a simplified version - you might want more sophisticated scoring
      if (matchData['eventId'] == widget.tournament.events[_selectedEventIndex].name) {
        // Add Swiss scoring logic here
        // For example, update a separate collection to track Swiss standings
      }
    }
  } catch (e) {
    debugPrint('Error updating Swiss format scores: $e');
  }
}

// Helper method to handle ladder position swapping
Future<void> _handleLadderMatchResult(String matchId, String winner) async {
  // This would be called when a ladder match is completed
  try {
    final matchDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .collection('matches')
        .doc(matchId)
        .get();

    if (matchDoc.exists) {
      final matchData = matchDoc.data()!;
      
      if (matchData['ladderChallenge'] == true) {
        // Handle ladder position swapping logic
        final challengerPosition = matchData['challengerPosition'] as int;
        final targetPosition = matchData['targetPosition'] as int;
        
        // If challenger wins, they swap positions
        // Implementation would depend on how you store ladder rankings
        // You might want a separate collection for ladder standings
        
        debugPrint('Ladder match result: Challenger at position $challengerPosition vs Target at position $targetPosition');
      }
    }
  } catch (e) {
    debugPrint('Error handling ladder match result: $e');
  }
}

  // Helper function to count participants by gender
  Future<int> _countParticipantsByGender(
    List<Map<String, dynamic>> participants,
    String targetGender,
  ) async {
    int count = 0;
    for (var participant in participants) {
      final userDetails = await _getUserDetails(participant['id']);
      if (userDetails['gender'] == targetGender) {
        count++;
      }
    }
    return count;
  }

  Future<void> _createManualMatch(
    dynamic competitor1,
    dynamic competitor2,
    int court,
    String timeSlot,
  ) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final selectedEvent = widget.tournament.events[_selectedEventIndex];
      final isDoubles = selectedEvent.matchType.toLowerCase().contains(
        'doubles',
      );

      // Validate teams for mixed doubles
      if (isDoubles &&
          selectedEvent.matchType.toLowerCase().contains('mixed')) {
        await _validateMixedDoublesTeams(competitor1, competitor2);
      }

      // Parse the time slot to create a proper DateTime
      DateTime? startTime;
      try {
        // Get tournament start date
        final tournamentDoc =
            await FirebaseFirestore.instance
                .collection('tournaments')
                .doc(widget.tournament.id)
                .get();

        final data = tournamentDoc.data();
        final tournamentStartDate =
            (data?['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();

        // Parse time slot (format: "HH:mm-HH:mm")
        final timeParts = timeSlot.split('-');
        if (timeParts.length == 2) {
          final startTimeParts = timeParts[0].trim().split(':');
          if (startTimeParts.length == 2) {
            final hour = int.tryParse(startTimeParts[0]);
            final minute = int.tryParse(startTimeParts[1]);

            if (hour != null && minute != null) {
              // Create start time using tournament start date with the time slot time
              startTime = DateTime(
                tournamentStartDate.year,
                tournamentStartDate.month,
                tournamentStartDate.day,
                hour,
                minute,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Error parsing time slot for manual match: $e');
      }

      String matchId;
      Map<String, dynamic> newMatch;

      if (isDoubles) {
        final team1Ids = competitor1['playerIds'] as List<String>;
        final team2Ids = competitor2['playerIds'] as List<String>;
        matchId =
            '${selectedEvent.name}_manual_${team1Ids.join('_')}_vs_${team2Ids.join('_')}_${DateTime.now().millisecondsSinceEpoch}';

        newMatch = {
          'matchId': matchId,
          'eventId': selectedEvent.name,
          'matchType': selectedEvent.matchType,
          'round': _matches.isNotEmpty ? (_matches.last['round'] ?? 1) : 1,
          'team1': competitor1['playerNames'],
          'team2': competitor2['playerNames'],
          'team1Ids': team1Ids,
          'team2Ids': team2Ids,
          'team1Genders':
              competitor1['playerGenders'] ?? ['unknown', 'unknown'],
          'team2Genders':
              competitor2['playerGenders'] ?? ['unknown', 'unknown'],
          'teamType1': competitor1['teamType'] ?? 'manual',
          'teamType2': competitor2['teamType'] ?? 'manual',
          'completed': false,
          'winner': null,
          'umpire': {'name': '', 'email': '', 'phone': ''},
          'liveScores': {
            'team1': [0, 0, 0],
            'team2': [0, 0, 0],
            'currentGame': 1,
            'isLive': false,
            'currentServer': 'team1',
          },
          'court': court,
          'timeSlot': timeSlot,
          'startTime':
              startTime != null ? Timestamp.fromDate(startTime.toUtc()) : null,
          'lastUpdated': FieldValue.serverTimestamp(),
        };
      } else {
        matchId =
            '${selectedEvent.name}_manual_${competitor1['id']}_vs_${competitor2['id']}_${DateTime.now().millisecondsSinceEpoch}';

        newMatch = {
          'matchId': matchId,
          'eventId': selectedEvent.name,
          'matchType': selectedEvent.matchType,
          'round': _matches.isNotEmpty ? (_matches.last['round'] ?? 1) : 1,
          'player1':
              competitor1['name'] ?? await _getDisplayName(competitor1['id']),
          'player2':
              competitor2['name'] ?? await _getDisplayName(competitor2['id']),
          'player1Id': competitor1['id'],
          'player2Id': competitor2['id'],
          'completed': false,
          'winner': null,
          'umpire': {'name': '', 'email': '', 'phone': ''},
          'liveScores': {
            'player1': [0, 0, 0],
            'player2': [0, 0, 0],
            'currentGame': 1,
            'isLive': false,
            'currentServer': 'player1',
          },
          'court': court,
          'timeSlot': timeSlot,
          'startTime':
              startTime != null ? Timestamp.fromDate(startTime.toUtc()) : null,
          'lastUpdated': FieldValue.serverTimestamp(),
        };
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .collection('matches')
          .doc(matchId)
          .set(newMatch);

      final updatedEvents =
          widget.tournament.events.asMap().entries.map((entry) {
            if (entry.key == _selectedEventIndex) {
              return Event(
                name: entry.value.name,
                format: entry.value.format,
                level: entry.value.level,
                maxParticipants: entry.value.maxParticipants,
                bornAfter: entry.value.bornAfter,
                matchType: entry.value.matchType,
                matches: [...entry.value.matches, matchId],
                participants: entry.value.participants,
                numberOfCourts: entry.value.numberOfCourts,
                timeSlots: entry.value.timeSlots,
              );
            }
            return entry.value;
          }).toList();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({
            'events': updatedEvents.map((e) => e.toFirestore()).toList(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        setState(() {
          _matches.add(newMatch);
        });
        await _generateLeaderboardData();

        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Match Created'),
          description: Text(
            'Manual ${isDoubles ? 'doubles' : 'singles'} match has been successfully created and scheduled for ${startTime != null ? DateFormat('MMM dd, yyyy • HH:mm').format(startTime) : timeSlot}!',
          ),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to create match: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _validateMixedDoublesTeams(
    Map<String, dynamic> team1,
    Map<String, dynamic> team2,
  ) async {
    final team1Genders = team1['playerGenders'] as List<String>?;
    final team2Genders = team2['playerGenders'] as List<String>?;

    // Check if both teams have proper gender distribution for mixed doubles
    if (team1Genders != null && team1Genders.length == 2) {
      final team1HasMale = team1Genders.contains('male');
      final team1HasFemale = team1Genders.contains('female');

      if (!team1HasMale || !team1HasFemale) {
        throw 'Team 1 must have one male and one female player for mixed doubles';
      }
    }

    if (team2Genders != null && team2Genders.length == 2) {
      final team2HasMale = team2Genders.contains('male');
      final team2HasFemale = team2Genders.contains('female');

      if (!team2HasMale || !team2HasFemale) {
        throw 'Team 2 must have one male and one female player for mixed doubles';
      }
    }
  }

  // MODIFIED: Remove date/time selection from manual match dialog
  void _showManualMatchDialog(bool isCreator) {
    if (!isCreator || !_canGenerateMatches) return;

    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final isDoubles = selectedEvent.matchType.toLowerCase().contains('doubles');
    final isMixed = selectedEvent.matchType.toLowerCase().contains('mixed');
    final competitors = List<Map<String, dynamic>>.from(_participants);

    if (competitors.length < 2) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Insufficient Participants'),
        description: Text(
          'At least ${isDoubles ? 'four players (for two teams)' : 'two players'} are required to create a match.',
        ),
        autoCloseDuration: const Duration(seconds: 3),
      );
      return;
    }

    showDialog(
      context: context,
      builder:
          (_) => _ManualMatchDialog(
            competitors: competitors,
            selectedEvent: selectedEvent,
            isDoubles: isDoubles,
            isMixed: isMixed,
            onCreateMatch: (competitor1, competitor2, court, timeSlot) {
              _createManualMatch(competitor1, competitor2, court, timeSlot);
            },
            primaryColor: _primaryColor,
            accentColor: _accentColor,
            textColor: _textColor,
            secondaryText: _secondaryText,
            cardBackground: _cardBackground,
            successColor: _successColor,
          ),
    );
  }

  Future<void> _deleteMatch(int matchIndex) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final match = _matches[matchIndex];
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .collection('matches')
          .doc(match['matchId'])
          .delete();

      final updatedEvents =
          widget.tournament.events.asMap().entries.map((entry) {
            if (entry.key == _selectedEventIndex) {
              final updatedMatches = List<String>.from(entry.value.matches)
                ..remove(match['matchId']);
              return Event(
                name: entry.value.name,
                format: entry.value.format,
                level: entry.value.level,
                maxParticipants: entry.value.maxParticipants,
                bornAfter: entry.value.bornAfter,
                matchType: entry.value.matchType,
                matches: updatedMatches,
                participants: entry.value.participants,
                numberOfCourts: entry.value.numberOfCourts,
                timeSlots: entry.value.timeSlots,
              );
            }
            return entry.value;
          }).toList();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({
            'events': updatedEvents.map((e) => e.toFirestore()).toList(),
          });

      if (mounted) {
        setState(() {
          _matches.removeAt(matchIndex);
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Match Deleted'),
          description: const Text('The match has been successfully deleted.'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Delete Failed'),
          description: Text('Failed to delete match: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showDeleteConfirmation(BuildContext context, int matchIndex) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: _cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Confirm Delete',
              style: GoogleFonts.poppins(
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Are you sure you want to delete this match?',
              style: GoogleFonts.poppins(color: _secondaryText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(color: _secondaryText),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteMatch(matchIndex);
                },
                child: Text(
                  'Delete',
                  style: GoogleFonts.poppins(
                    color: _errorColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showDeleteParticipantDialog(String participantId) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Remove Participant',
              style: GoogleFonts.poppins(
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Are you sure you want to remove this participant from the event?',
              style: GoogleFonts.poppins(color: _secondaryText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(color: _secondaryText),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _removeParticipant(participantId);
                },
                child: Text(
                  'Remove',
                  style: GoogleFonts.poppins(
                    color: _errorColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _removeParticipant(String participantId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final updatedEvents =
          widget.tournament.events.asMap().entries.map((entry) {
            if (entry.key == _selectedEventIndex) {
              return Event(
                name: entry.value.name,
                format: entry.value.format,
                level: entry.value.level,
                maxParticipants: entry.value.maxParticipants,
                bornAfter: entry.value.bornAfter,
                matchType: entry.value.matchType,
                matches: entry.value.matches,
                participants:
                    entry.value.participants
                        .where((id) => id != participantId)
                        .toList(),
                numberOfCourts: entry.value.numberOfCourts,
                timeSlots: entry.value.timeSlots,
              );
            }
            return entry.value;
          }).toList();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({
            'events': updatedEvents.map((e) => e.toFirestore()).toList(),
          });

      if (mounted) {
        setState(() {
          _participants.removeWhere((p) => p['id'] == participantId);
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Participant Removed'),
          description: const Text(
            'Participant has been successfully removed from the event.',
          ),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Remove Failed'),
          description: Text('Failed to remove participant: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _extractGenderFromMatchType(String matchType) {
    final lowerType = matchType.toLowerCase();
    if (lowerType.contains("men's") && !lowerType.contains("women's")) {
      return 'male';
    } else if (lowerType.contains("women's") || lowerType.contains("ladies")) {
      return 'female';
    } else if (lowerType.contains('mixed')) {
      return 'mixed';
    }
    return 'open';
  }

  Future<Map<String, dynamic>> _getUserDetails(String userId) async {
    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        return {
          'gender':
              userData['gender']?.toString().toLowerCase() ?? 'not_specified',
          'firstName': userData['firstName'] ?? '',
          'lastName': userData['lastName'] ?? '',
          'email': userData['email'] ?? '',
        };
      }
      return {
        'gender': 'not_specified',
        'firstName': 'Unknown',
        'lastName': '',
        'email': '',
      };
    } catch (e) {
      debugPrint('Error getting user details: $e');
      return {
        'gender': 'not_specified',
        'firstName': 'Unknown',
        'lastName': '',
        'email': '',
      };
    }
  }

  Future<bool> _hasUserJoinedAnyEvent() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return false;

    final userId = authState.user.uid;

    // Check if user has already joined any event in this tournament
    for (int i = 0; i < widget.tournament.events.length; i++) {
      if (widget.tournament.events[i].participants.contains(userId)) {
        return true;
      }
    }

    return false;
  }

  Future<bool> _canUserJoinEvent() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return false;

    final userId = authState.user.uid;
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final eventGender = _extractGenderFromMatchType(selectedEvent.matchType);
    final userDetails = await _getUserDetails(userId);
    final userGender = userDetails['gender'] as String;

    // Check if user has already joined any event in this tournament
    final hasJoinedAnyEvent = await _hasUserJoinedAnyEvent();
    if (hasJoinedAnyEvent) {
      return false; // User can only join one event per tournament
    }

    // If it's an open tournament, anyone can join
    if (eventGender == 'open') return true;

    // For mixed doubles, we need both male and female participants
    if (eventGender == 'mixed') {
      // Mixed events are open to all, but team formation logic will handle gender pairing
      return userGender == 'male' || userGender == 'female';
    }

    // If user gender is not specified, they can't join gender-specific events
    if (userGender == 'not_specified' && eventGender != 'open') {
      return false;
    }

    // Check if user's gender matches event requirement
    return eventGender == userGender;
  }

  Future<void> _joinTournament(BuildContext context) async {
    if (_isLoading) return;

    final now = DateTime.now().toUtc();
    if (now.isAfter(widget.tournament.registrationEnd)) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Registration Closed'),
        description: const Text('Registration for this tournament has ended.'),
        autoCloseDuration: const Duration(seconds: 3),
      );
      return;
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Authentication Required'),
        description: const Text('Please sign in to join the tournament.'),
        autoCloseDuration: const Duration(seconds: 2),
      );
      return;
    }

    final userId = authState.user.uid;
    if (widget.tournament.createdBy == userId) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Creator Cannot Join'),
        description: const Text(
          'As the tournament creator, you cannot join as a participant.',
        ),
        autoCloseDuration: const Duration(seconds: 2),
      );
      return;
    }

    if (_hasJoined) {
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        title: const Text('Already Joined'),
        description: const Text('You have already joined this event!'),
        autoCloseDuration: const Duration(seconds: 2),
      );
      return;
    }

    // Check if user has already joined any event in this tournament
    final hasJoinedAnyEvent = await _hasUserJoinedAnyEvent();
    if (hasJoinedAnyEvent) {
      // Find which event they joined
      String joinedEventName = '';
      for (int i = 0; i < widget.tournament.events.length; i++) {
        if (widget.tournament.events[i].participants.contains(userId)) {
          joinedEventName = widget.tournament.events[i].name;
          break;
        }
      }

      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Already Registered'),
        description: Text(
          'You have already joined "$joinedEventName" in this tournament. Players can only participate in one event per tournament.',
        ),
        autoCloseDuration: const Duration(seconds: 4),
      );
      return;
    }

    // Enhanced gender validation
    final canJoin = await _canUserJoinEvent();
    if (!canJoin) {
      final selectedEvent = widget.tournament.events[_selectedEventIndex];
      final eventGender = _extractGenderFromMatchType(selectedEvent.matchType);
      final userDetails = await _getUserDetails(userId);

      String genderMessage = '';
      if (eventGender == 'male') {
        genderMessage = 'This event is for male participants only.';
      } else if (eventGender == 'female') {
        genderMessage = 'This event is for female participants only.';
      } else if (eventGender == 'mixed') {
        if (userDetails['gender'] == 'not_specified') {
          genderMessage =
              'Please update your gender in profile settings to join mixed doubles events.';
        } else {
          genderMessage =
              'Mixed doubles events require valid gender information.';
        }
      } else {
        genderMessage =
            'You cannot join this event due to eligibility requirements.';
      }

      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Cannot Join Event'),
        description: Text(genderMessage),
        autoCloseDuration: const Duration(seconds: 3),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final selectedEvent = widget.tournament.events[_selectedEventIndex];
      if (selectedEvent.participants.length >= selectedEvent.maxParticipants) {
        throw 'This event has reached its maximum participants.';
      }

      final updatedEvents =
          widget.tournament.events.asMap().entries.map((entry) {
            if (entry.key == _selectedEventIndex) {
              return Event(
                name: entry.value.name,
                format: entry.value.format,
                level: entry.value.level,
                maxParticipants: entry.value.maxParticipants,
                bornAfter: entry.value.bornAfter,
                matchType: entry.value.matchType,
                matches: entry.value.matches,
                participants: [...entry.value.participants, userId],
                numberOfCourts: entry.value.numberOfCourts,
                timeSlots: entry.value.timeSlots,
              );
            }
            return entry.value;
          }).toList();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({
            'events': updatedEvents.map((e) => e.toFirestore()).toList(),
          });

      if (mounted) {
        setState(() {
          _participants.add({'id': userId, 'name': null});
          _hasJoined = true;
        });
        await _loadParticipants();

        // Enhanced success message for different event types
        final selectedEvent = widget.tournament.events[_selectedEventIndex];
        final eventType =
            selectedEvent.matchType.toLowerCase().contains('doubles')
                ? 'doubles event'
                : 'singles event';

        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Successfully Joined!'),
          description: Text(
            'You have joined ${selectedEvent.name} ($eventType). ${selectedEvent.matchType.toLowerCase().contains('mixed') ? 'Teams will be formed with proper gender pairing.' : ''}',
          ),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Join Failed'),
          description: Text('Failed to join event: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

Future<void> _generateKnockoutMatches(
  List<Map<String, dynamic>> competitors,
  bool isDoubles,
  Event selectedEvent,
  List<Map<String, dynamic>> newMatches,
  int currentTimeSlotIndex,
  int currentCourt,
) async {
  List<Map<String, dynamic>> currentRoundParticipants = List.from(competitors);
  int round = 1;

  while (currentRoundParticipants.length > 1) {
    final nextRoundParticipants = <Map<String, dynamic>>[];
    final roundMatches = <Map<String, dynamic>>[];

    for (int i = 0; i < currentRoundParticipants.length - 1; i += 2) {
      final competitor1 = currentRoundParticipants[i];
      final competitor2 = currentRoundParticipants[i + 1];

      final matchData = await _createMatchData(
        competitor1,
        competitor2,
        selectedEvent,
        round,
        i ~/ 2 + 1,
        currentTimeSlotIndex,
        currentCourt,
        isDoubles,
      );

      roundMatches.add(matchData);
      
      // Create a TBD placeholder for the next round
      nextRoundParticipants.add({
        'id': 'TBD', // This will be updated when the match is completed
        'winnerMatchId': matchData['matchId'],
        'position': i ~/ 2, // Track position in the bracket
      });

      // Update scheduling positions
      final scheduleUpdate = _updateSchedulePosition(currentCourt, currentTimeSlotIndex);
      currentCourt = scheduleUpdate['court']!;
      currentTimeSlotIndex = scheduleUpdate['timeSlotIndex']!;
    }

    // Handle bye if odd number of participants
    if (currentRoundParticipants.length % 2 != 0) {
      final byeCompetitor = currentRoundParticipants.last;
      final byeMatchData = await _createByeMatch(
        byeCompetitor,
        selectedEvent,
        round,
        currentTimeSlotIndex,
        currentCourt,
        isDoubles,
      );

      roundMatches.add(byeMatchData);
      nextRoundParticipants.add({
        'id': isDoubles ? byeCompetitor['teamId'] : byeCompetitor['id'],
        'winnerMatchId': byeMatchData['matchId'],
        'position': currentRoundParticipants.length ~/ 2,
      });
    }

    // Add all matches for this round
    newMatches.addAll(roundMatches);
    
    // Setup next round with TBD placeholders
    if (nextRoundParticipants.length > 1) {
      currentRoundParticipants = nextRoundParticipants;
      round++;
    } else if (nextRoundParticipants.length == 1) {
      // This is the final - no need to create another round
      break;
    }
  }
}




  
  Future<void> _generateRoundRobinMatches(
    List<Map<String, dynamic>> competitors,
    bool isDoubles,
    Event selectedEvent,
    List<Map<String, dynamic>> newMatches,
    int currentTimeSlotIndex,
    int currentCourt,
  ) async {
    final n = competitors.length;
    final rounds = n.isEven ? n - 1 : n;

    List<Map<String, dynamic>> fixed = List.from(competitors);
    if (n.isOdd) {
      fixed.add({'id': 'bye', 'name': 'Bye'});
    }

    for (int round = 1; round <= rounds; round++) {
      for (int i = 0; i < fixed.length ~/ 2; i++) {
        final competitor1 = fixed[i];
        final competitor2 = fixed[fixed.length - 1 - i];

        // Skip if one of them is a bye
        if (competitor1['id'] == 'bye' || competitor2['id'] == 'bye') {
          continue;
        }

        final matchData = await _createMatchData(
          competitor1,
          competitor2,
          selectedEvent,
          round,
          i + 1,
          currentTimeSlotIndex,
          currentCourt,
          isDoubles,
        );

        newMatches.add(matchData);

        // Update scheduling positions - MODIFIED: Remove day tracking
        final scheduleUpdate = _updateSchedulePosition(
          currentCourt,
          currentTimeSlotIndex,
        );
        currentCourt = scheduleUpdate['court']!;
        currentTimeSlotIndex = scheduleUpdate['timeSlotIndex']!;
      }

      // Rotate for next round (keep first element fixed)
      final last = fixed.removeLast();
      fixed.insert(1, last);
    }
  }

  Map<String, int> _updateSchedulePosition(
    int currentCourt,
    int currentTimeSlotIndex,
  ) {
    currentCourt++;
    if (currentCourt > _numberOfCourts) {
      currentCourt = 1;
      currentTimeSlotIndex++;
      if (currentTimeSlotIndex >= _timeSlots.length) {
        // Reset to first time slot if we run out
        currentTimeSlotIndex = 0;
      }
    }

    return {'court': currentCourt, 'timeSlotIndex': currentTimeSlotIndex};
  }


  Future<Map<String, dynamic>> _createMatchData(
  Map<String, dynamic> competitor1,
  Map<String, dynamic> competitor2,
  Event selectedEvent,
  int round,
  int matchNumber,
  int currentTimeSlotIndex,
  int currentCourt,
  bool isDoubles,
) async {
  final timeSlot = _timeSlots[currentTimeSlotIndex];
  final matchId = '${selectedEvent.name}_round${round}_match$matchNumber';

  // Check if we're dealing with TBD placeholders from previous rounds
  final isCompetitor1TBD = competitor1['id'] == 'TBD';
  final isCompetitor2TBD = competitor2['id'] == 'TBD';

  // Parse the time slot to create a proper DateTime
  DateTime? startTime;
  try {
    // Get tournament start date and timezone
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .get();

    final data = tournamentDoc.data();
    final tournamentStartDate = (data?['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();

    // Parse time slot (format: "HH:mm-HH:mm")
    final timeParts = timeSlot.split('-');
    if (timeParts.length == 2) {
      final startTimeParts = timeParts[0].trim().split(':');
      if (startTimeParts.length == 2) {
        final hour = int.tryParse(startTimeParts[0]);
        final minute = int.tryParse(startTimeParts[1]);

        if (hour != null && minute != null) {
          // Create start time using tournament start date with the time slot time
          startTime = DateTime(
            tournamentStartDate.year,
            tournamentStartDate.month,
            tournamentStartDate.day,
            hour,
            minute,
          );
        }
      }
    }
  } catch (e) {
    debugPrint('Error parsing time slot: $e');
  }

  // In the _createMatchData method, add flags to track TBD origins
if (isDoubles) {
  return {
    'matchId': matchId,
    'eventId': selectedEvent.name,
    'matchType': selectedEvent.matchType,
    'round': round,
    'team1': isCompetitor1TBD ? ['TBD', 'TBD'] : competitor1['playerNames'] ?? ['Unknown', 'Unknown'],
    'team2': isCompetitor2TBD ? ['TBD', 'TBD'] : competitor2['playerNames'] ?? ['Unknown', 'Unknown'],
    'team1Ids': isCompetitor1TBD ? ['TBD', 'TBD'] : competitor1['playerIds'] ?? ['unknown1', 'unknown2'],
    'team2Ids': isCompetitor2TBD ? ['TBD', 'TBD'] : competitor2['playerIds'] ?? ['unknown1', 'unknown2'],
    'team1Genders': isCompetitor1TBD ? ['unknown', 'unknown'] : competitor1['playerGenders'] ?? ['unknown', 'unknown'],
    'team2Genders': isCompetitor2TBD ? ['unknown', 'unknown'] : competitor2['playerGenders'] ?? ['unknown', 'unknown'],
    'teamType1': isCompetitor1TBD ? 'TBD' : competitor1['teamType'] ?? 'unknown',
    'teamType2': isCompetitor2TBD ? 'TBD' : competitor2['teamType'] ?? 'unknown',
    'completed': false,
    'winner': null,
    'umpire': {'name': '', 'email': '', 'phone': ''},
    'liveScores': {
      'team1': [0, 0, 0],
      'team2': [0, 0, 0],
      'currentGame': 1,
      'isLive': false,
      'currentServer': 'team1',
    },
    'court': currentCourt,
    'timeSlot': timeSlot,
    'startTime': startTime != null ? Timestamp.fromDate(startTime.toUtc()) : null,
    'lastUpdated': FieldValue.serverTimestamp(),
    // Store references to previous matches for winner propagation
    'previousMatch1': competitor1['winnerMatchId'],
    'previousMatch2': competitor2['winnerMatchId'],
    // Track which slots were originally TBD
    'wasTBDTeam1': isCompetitor1TBD,
    'wasTBDTeam2': isCompetitor2TBD,
  };
} else {
  return {
    'matchId': matchId,
    'eventId': selectedEvent.name,
    'matchType': selectedEvent.matchType,
    'round': round,
    'player1': isCompetitor1TBD ? 'TBD' : competitor1['name'] ?? await _getDisplayName(competitor1['id']),
    'player2': isCompetitor2TBD ? 'TBD' : competitor2['name'] ?? await _getDisplayName(competitor2['id']),
    'player1Id': isCompetitor1TBD ? 'TBD' : competitor1['id'],
    'player2Id': isCompetitor2TBD ? 'TBD' : competitor2['id'],
    'completed': false,
    'winner': null,
    'umpire': {'name': '', 'email': '', 'phone': ''},
    'liveScores': {
      'player1': [0, 0, 0],
      'player2': [0, 0, 0],
      'currentGame': 1,
      'isLive': false,
      'currentServer': 'player1',
    },
    'court': currentCourt,
    'timeSlot': timeSlot,
    'startTime': startTime != null ? Timestamp.fromDate(startTime.toUtc()) : null,
    'lastUpdated': FieldValue.serverTimestamp(),
    // Store references to previous matches for winner propagation
    'previousMatch1': competitor1['winnerMatchId'],
    'previousMatch2': competitor2['winnerMatchId'],
    // Track which slots were originally TBD
    'wasTBD1': isCompetitor1TBD,
    'wasTBD2': isCompetitor2TBD,
  };
}
}

Future<Map<String, dynamic>> _createByeMatch(
  Map<String, dynamic> byeCompetitor,
  Event selectedEvent,
  int round,
  int currentTimeSlotIndex,
  int currentCourt,
  bool isDoubles,
) async {
  final byeMatchId = '${selectedEvent.name}_round${round}_bye';

  if (isDoubles) {
    return {
      'matchId': byeMatchId,
      'eventId': selectedEvent.name,
      'matchType': selectedEvent.matchType,
      'round': round,
      'team1': byeCompetitor['playerNames'],
      'team2': ['Bye'],
      'team1Ids': byeCompetitor['playerIds'],
      'team2Ids': ['bye'],
      'completed': true,
      'winner': 'team1',
      'umpire': {'name': '', 'email': '', 'phone': ''},
      'liveScores': {
        'team1': [0, 0, 0],
        'team2': [0, 0, 0],
        'currentGame': 1,
        'isLive': false,
        'currentServer': 'team1',
      },
      'isBye': true, // Add flag to identify bye matches
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  } else {
    return {
      'matchId': byeMatchId,
      'eventId': selectedEvent.name,
      'matchType': selectedEvent.matchType,
      'round': round,
      'player1':
          byeCompetitor['name'] ?? await _getDisplayName(byeCompetitor['id']),
      'player2': 'Bye',
      'player1Id': byeCompetitor['id'],
      'player2Id': 'bye',
      'completed': true,
      'winner': 'player1',
      'umpire': {'name': '', 'email': '', 'phone': ''},
      'liveScores': {
        'player1': [0, 0, 0],
        'player2': [0, 0, 0],
        'currentGame': 1,
        'isLive': false,
        'currentServer': 'player1',
      },
      'isBye': true, // Add flag to identify bye matches
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  }
}

  Future<void> _saveMatchesToFirestore(
    List<Map<String, dynamic>> matches,
    Event selectedEvent,
  ) async {
    final batch = FirebaseFirestore.instance.batch();
    final matchesRef = FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .collection('matches');

    for (var match in matches) {
      batch.set(matchesRef.doc(match['matchId']), match);
    }

    await batch.commit();

    // Update tournament with match references
    final updatedEvents =
        widget.tournament.events.asMap().entries.map((entry) {
          if (entry.key == _selectedEventIndex) {
            return Event(
              name: entry.value.name,
              format: entry.value.format,
              level: entry.value.level,
              maxParticipants: entry.value.maxParticipants,
              bornAfter: entry.value.bornAfter,
              matchType: entry.value.matchType,
              matches: matches.map((m) => m['matchId'] as String).toList(),
              participants: entry.value.participants,
              numberOfCourts: _numberOfCourts,
              timeSlots: List<String>.from(_timeSlots),
            );
          }
          return entry.value;
        }).toList();

    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournament.id)
        .update({
          'events': updatedEvents.map((e) => e.toFirestore()).toList(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
  }

  Future<List<Map<String, dynamic>>> _createDoublesTeams(
    List<Map<String, dynamic>> participants,
    String matchType,
  ) async {
    final teams = <Map<String, dynamic>>[];
    final isMixed = matchType.toLowerCase().contains('mixed');

    if (isMixed) {
      // For mixed doubles: pair 1 male + 1 female
      final males = <Map<String, dynamic>>[];
      final females = <Map<String, dynamic>>[];

      // Separate participants by gender
      for (var participant in participants) {
        final userDetails = await _getUserDetails(participant['id']);
        final gender = userDetails['gender'] as String;

        if (gender == 'male') {
          males.add({
            ...participant,
            'gender': gender,
            'firstName': userDetails['firstName'],
            'lastName': userDetails['lastName'],
          });
        } else if (gender == 'female') {
          females.add({
            ...participant,
            'gender': gender,
            'firstName': userDetails['firstName'],
            'lastName': userDetails['lastName'],
          });
        }
      }

      // Shuffle for random pairing
      males.shuffle();
      females.shuffle();

      // Create mixed teams (1 male + 1 female)
      final maxTeams = math.min(males.length, females.length);

      for (int i = 0; i < maxTeams; i++) {
        final male = males[i];
        final female = females[i];

        teams.add({
          'teamId': 'mixed_team_${teams.length + 1}',
          'playerIds': [male['id'], female['id']],
          'playerNames': [
            '${male['firstName']} ${male['lastName']}'.trim(),
            '${female['firstName']} ${female['lastName']}'.trim(),
          ],
          'playerGenders': ['male', 'female'],
          'teamType': 'mixed',
        });
      }

      // Handle remaining participants (if uneven gender distribution)
      final remainingParticipants = <Map<String, dynamic>>[];
      if (males.length > maxTeams) {
        remainingParticipants.addAll(males.sublist(maxTeams));
      }
      if (females.length > maxTeams) {
        remainingParticipants.addAll(females.sublist(maxTeams));
      }

      // For remaining participants, create same-gender teams if allowed
      if (remainingParticipants.length >= 2) {
        for (int i = 0; i < remainingParticipants.length - 1; i += 2) {
          final player1 = remainingParticipants[i];
          final player2 = remainingParticipants[i + 1];

          teams.add({
            'teamId': 'backup_team_${teams.length + 1}',
            'playerIds': [player1['id'], player2['id']],
            'playerNames': [
              '${player1['firstName']} ${player1['lastName']}'.trim(),
              '${player2['firstName']} ${player2['lastName']}'.trim(),
            ],
            'playerGenders': [player1['gender'], player2['gender']],
            'teamType': 'backup',
          });
        }
      }
    } else {
      // For same-gender doubles: pair any two participants
      final shuffledParticipants = List<Map<String, dynamic>>.from(
        participants,
      );
      shuffledParticipants.shuffle();

      for (int i = 0; i < shuffledParticipants.length - 1; i += 2) {
        final player1 = shuffledParticipants[i];
        final player2 = shuffledParticipants[i + 1];

        // Get user details for proper names
        final player1Details = await _getUserDetails(player1['id']);
        final player2Details = await _getUserDetails(player2['id']);

        teams.add({
          'teamId': 'team_${teams.length + 1}',
          'playerIds': [player1['id'], player2['id']],
          'playerNames': [
            '${player1Details['firstName']} ${player1Details['lastName']}'
                .trim(),
            '${player2Details['firstName']} ${player2Details['lastName']}'
                .trim(),
          ],
          'playerGenders': [player1Details['gender'], player2Details['gender']],
          'teamType': 'same_gender',
        });
      }
    }

    return teams;
  }

  Future<void> _withdrawFromTournament(BuildContext context) async {
    if (_isLoading) return;

    final now = DateTime.now().toUtc();
    if (now.isAfter(widget.tournament.registrationEnd)) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Withdrawal Not Allowed'),
        description: const Text(
          'Cannot withdraw after registration has ended.',
        ),
        autoCloseDuration: const Duration(seconds: 2),
      );
      return;
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final userId = authState.user.uid;

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedEvents =
          widget.tournament.events.asMap().entries.map((entry) {
            if (entry.key == _selectedEventIndex) {
              return Event(
                name: entry.value.name,
                format: entry.value.format,
                level: entry.value.level,
                maxParticipants: entry.value.maxParticipants,
                bornAfter: entry.value.bornAfter,
                matchType: entry.value.matchType,
                matches: entry.value.matches,
                participants:
                    entry.value.participants
                        .where((id) => id != userId)
                        .toList(),
                numberOfCourts: entry.value.numberOfCourts,
                timeSlots: entry.value.timeSlots,
              );
            }
            return entry.value;
          }).toList();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({
            'events': updatedEvents.map((e) => e.toFirestore()).toList(),
          });

      if (mounted) {
        setState(() {
          _participants =
              _participants.where((p) => p['id'] != userId).toList();
          _hasJoined = false;
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Withdrawn'),
          description: Text(
            'You have successfully withdrawn from ${widget.tournament.events[_selectedEventIndex].name}.',
          ),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Withdrawal Failed'),
          description: Text('Failed to withdraw: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
    bool enabled = true,
    String? disabledReason,
  }) {
    final buttonColor = color ?? _accentColor;
    final isDisabled = !enabled;

    return Tooltip(
      message: isDisabled ? disabledReason ?? '' : '',
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: InkWell(
          onTap:
              isDisabled
                  ? () {
                    if (disabledReason != null) {
                      toastification.show(
                        context: context,
                        type: ToastificationType.info,
                        title: const Text('Action Disabled'),
                        description: Text(disabledReason),
                        autoCloseDuration: const Duration(seconds: 2),
                      );
                    }
                  }
                  : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color:
                  isDisabled
                      ? Colors.grey.shade100
                      : buttonColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    isDisabled
                        ? Colors.grey.shade300
                        : buttonColor.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isDisabled ? Colors.grey.shade500 : buttonColor,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDisabled ? Colors.grey.shade500 : buttonColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Enhanced icon-only button
  Widget _buildIconOnlyButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      borderRadius: BorderRadius.circular(20),
      color: Colors.transparent,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: color ?? _textColor,
        onPressed: onPressed,
        splashRadius: 20,
        tooltip: 'Delete',
      ),
    );
  }

  Widget _buildParticipantsTab() {
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final isCreator =
        context.read<AuthBloc>().state is AuthAuthenticated &&
        (context.read<AuthBloc>().state as AuthAuthenticated).user.uid ==
            widget.tournament.createdBy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with improved styling
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.people_alt_outlined, color: _accentColor, size: 24),
              const SizedBox(width: 12),
              Text(
                selectedEvent.name,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              const Spacer(),
              Text(
                '${_participants.length} / ${selectedEvent.maxParticipants}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _secondaryText,
                ),
              ),
            ],
          ),
        ),

        // Participants content
        Expanded(
          child:
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _participants.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: _secondaryText.withOpacity(0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No participants yet',
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Players will appear here once they register',
                          style: GoogleFonts.poppins(
                            color: _secondaryText.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                  : AnimationLimiter(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _participants.length,
                      itemBuilder: (context, index) {
                        final participant = _participants[index];
                        return AnimationConfiguration.staggeredList(
                          position: index,
                          duration: const Duration(milliseconds: 375),
                          child: SlideAnimation(
                            verticalOffset: 50.0,
                            child: FadeInAnimation(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _accentColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      color: _accentColor,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    participant['name'] ?? participant['id'],
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      color: _textColor,
                                    ),
                                  ),
                                  subtitle: FutureBuilder<String>(
                                    future: _getUserEmail(participant['id']),
                                    builder: (context, snapshot) {
                                      return Text(
                                        snapshot.hasData
                                            ? snapshot.data!
                                            : 'Loading email...',
                                        style: GoogleFonts.poppins(
                                          color: _secondaryText,
                                          fontSize: 13,
                                        ),
                                      );
                                    },
                                  ),
                                  trailing:
                                      isCreator
                                          ? _buildIconOnlyButton(
                                            icon: Icons.delete_outline,
                                            onPressed:
                                                () =>
                                                    _showDeleteParticipantDialog(
                                                      participant['id'],
                                                    ),
                                            color: _errorColor,
                                          )
                                          : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }

  int _currentRoundPage = 0;

  String _formatDateTime(DateTime date) {
    String baseInfo = DateFormat('MMM dd, yyyy').format(date);

    return '$baseInfo ';
  }

  bool get canGenerateMatches {
    // Get the current time in the tournament's timezone
    final location = tz.getLocation(_tournamentTimezone);
    final now = tz.TZDateTime.now(location);
    return now.isAfter(widget.tournament.registrationEnd);
  }

  String get _timeUntilCanGenerate {
    final location = tz.getLocation(_tournamentTimezone);
    final now = tz.TZDateTime.now(location);
    final registrationEnd = widget.tournament.registrationEnd;

    if (now.isAfter(registrationEnd)) {
      return "Available now";
    }

    final difference = registrationEnd.difference(now);
    final formattedDate = DateFormat(
      'MMM dd, yyyy, hh:mm a',
    ).format(registrationEnd);

    if (difference.inDays > 0) {
      return "Can generate after $formattedDate (${difference.inDays} day${difference.inDays > 1 ? 's' : ''})";
    } else if (difference.inHours > 0) {
      return "Can generate after $formattedDate (${difference.inHours} hour${difference.inHours > 1 ? 's' : ''})";
    } else if (difference.inMinutes > 0) {
      return "Can generate after $formattedDate (${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''})";
    } else {
      return "Can generate after $formattedDate (soon)";
    }
  }

  Widget _buildDetailsTab() {
    final timezoneAbbreviation = TimezoneUtils.getTimezoneAbbreviation(
      widget.tournament.timezone,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tournament Details Section
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300, width: 1.5),
              ),
            ),
            child: Text(
              'Tournament Details',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _textColor,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Tournament details card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Game Type
                _buildDetailRow(
                  icon: Icons.sports_outlined,
                  label: 'Game Type',
                  value: widget.tournament.gameType,
                ),
                const SizedBox(height: 16),

                _buildDetailRow(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Deadline to Register',
                  value:
                      '${DateFormat('MMM dd, yyyy, hh:mm a').format(widget.tournament.registrationEnd)} ($timezoneAbbreviation)',
                ),
                const SizedBox(height: 16),

                _buildDetailRow(
                  icon: Icons.access_time_outlined,
                  label: 'Duration',
                  value:
                      widget.tournament.startDate != widget.tournament.endDate
                          ? '${DateFormat('MMM dd, yyyy').format(widget.tournament.startDate)} - ${DateFormat('MMM dd, yyyy').format(widget.tournament.endDate)} ($timezoneAbbreviation)'
                          : DateFormat(
                            'MMM dd, yyyy',
                          ).format(widget.tournament.startDate),
                ),
                const SizedBox(height: 16),

                // Status
                _buildDetailRow(
                  icon: Icons.info_outline,
                  label: 'Status',
                  value: widget.tournament.status.toUpperCase(),
                ),
                const SizedBox(height: 16),

                // Venue
                _buildDetailRow(
                  icon: Icons.place_outlined,
                  label: 'Venue',
                  value: widget.tournament.venue + "," + widget.tournament.city,
                ),
                const SizedBox(height: 16),

                // Contact Name
                _buildDetailRow(
                  icon: Icons.person_outline,
                  label: 'Contact Person',
                  value: widget.tournament.contactName ?? 'No name provided',
                ),
                const SizedBox(height: 16),

                // Contact Number
                _buildDetailRow(
                  icon: Icons.phone_outlined,
                  label: 'Contact Number',
                  value:
                      widget.tournament.contactNumber ?? 'No number provided',
                ),
                const SizedBox(height: 16),

                // Entry Fee
                _buildDetailRow(
                  icon: Icons.monetization_on_outlined,
                  label: 'Entry Fee',
                  value:
                      widget.tournament.entryFee > 0
                          ? '₹${widget.tournament.entryFee}'
                          : 'Free',
                ),
                const SizedBox(height: 16),

                // Payment Policy
                _buildDetailRow(
                  icon: Icons.payment_outlined,
                  label: 'Payment',
                  value:
                      widget.tournament.canPayAtVenue
                          ? 'Pay at venue allowed'
                          : 'Pre-payment required',
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Event Details Section
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300, width: 1.5),
              ),
            ),
            child: Text(
              'Event Details',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _textColor,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Event details card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Format
                _buildDetailRow(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'Format',
                  value: widget.tournament.events[_selectedEventIndex].format,
                ),
                const SizedBox(height: 16),

                // Level
                _buildDetailRow(
                  icon: Icons.emoji_events_outlined,
                  label: 'Level',
                  value: widget.tournament.events[_selectedEventIndex].level,
                ),
                const SizedBox(height: 16),

                // Match Type (with gender indication)
                _buildDetailRow(
                  icon: Icons.sports_tennis,
                  label: 'Match Type',
                  value:
                      widget.tournament.events[_selectedEventIndex].matchType,
                ),
                const SizedBox(height: 16),

                // Gender Requirement
                _buildDetailRow(
                  icon: Icons.wc_outlined,
                  label: 'Gender Requirement',
                  value: _getGenderRequirementText(
                    _extractGenderFromMatchType(
                      widget.tournament.events[_selectedEventIndex].matchType,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Max Participants
                _buildDetailRow(
                  icon: Icons.group_outlined,
                  label: 'Max Participants',
                  value:
                      widget
                          .tournament
                          .events[_selectedEventIndex]
                          .maxParticipants
                          .toString(),
                ),
                const SizedBox(height: 16),

                // Born After
                _buildDetailRow(
                  icon: Icons.cake_outlined,
                  label: 'Born After',
                  value:
                      widget.tournament.events[_selectedEventIndex].bornAfter !=
                              null
                          ? DateFormat('MMM dd, yyyy').format(
                            widget
                                .tournament
                                .events[_selectedEventIndex]
                                .bornAfter!,
                          )
                          : 'No age restriction',
                ),
                const SizedBox(height: 16),

                // Courts
                _buildDetailRow(
                  icon: Icons.location_on_outlined,
                  label: 'Courts',
                  value: _numberOfCourts.toString(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Time slots section
          Text(
            'Time Slots',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 12),

          // Time slots list
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                _timeSlots.isEmpty
                    ? Center(
                      child: Text(
                        'No time slots configured',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: _textColor,
                          height: 1.4,
                        ),
                      ),
                    )
                    : Column(
                      children:
                          _timeSlots
                              .map(
                                (slot) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                          right: 12,
                                        ),
                                        child: Icon(
                                          Icons.access_time_rounded,
                                          size: 18,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          slot,
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            color: _textColor,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                    ),
          ),
        ],
      ),
    );
  }

  // Helper method to get gender requirement text
  String _getGenderRequirementText(String genderRequirement) {
    switch (genderRequirement) {
      case 'male':
        return 'Men Only';
      case 'female':
        return 'Women Only';
      case 'mixed':
        return 'Mixed (Men & Women)';
      case 'open':
        return 'Open to All';
      default:
        return 'Open to All';
    }
  }

  Widget _buildMatchesTab() {
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final isCreator =
        context.read<AuthBloc>().state is AuthAuthenticated &&
        (context.read<AuthBloc>().state as AuthAuthenticated).user.uid ==
            widget.tournament.createdBy;
    final canGenerateMatches = _canGenerateMatches;
    final hasEnoughParticipants = _participants.length >= 2;
    final hasMatches = _matches.isNotEmpty;

    // Group matches by round
    final matchesByRound = <int, List<Map<String, dynamic>>>{};
    for (var match in _matches) {
      final round = match['round'] as int;
      if (!matchesByRound.containsKey(round)) {
        matchesByRound[round] = [];
      }
      matchesByRound[round]!.add(match);
    }

    // Sort rounds
    final sortedRounds = matchesByRound.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.sports_tennis_outlined, color: _accentColor, size: 24),
              const SizedBox(width: 12),
              Text(
                selectedEvent.name,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              const Spacer(),
              if (_matches.isNotEmpty)
                Text(
                  '${_matches.length} Matches',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _secondaryText,
                  ),
                ),
            ],
          ),
        ),

        // Action buttons
        Container(
          width: MediaQuery.of(context).size.width,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.grey.shade50,
          child: Column(
            children: [
              // Buttons row - ALWAYS SHOW THEM, but disabled when registration not ended
              Wrap(
                spacing: 12.0,
                runSpacing: 8.0,
                children: [
                  if (isCreator && hasEnoughParticipants)
                    _buildIconButton(
                      icon: Icons.add_circle_outline,
                      label: 'Create Match',
                      onPressed:
                          canGenerateMatches
                              ? () => _showManualMatchDialog(isCreator)
                              : () {},
                      color: canGenerateMatches ? _successColor : Colors.grey,
                      enabled: canGenerateMatches,
                      disabledReason:
                          canGenerateMatches
                              ? null
                              : 'Registration period has not ended yet',
                    ),
                  if (isCreator && hasEnoughParticipants && !hasMatches)
                    _buildIconButton(
                      icon: Icons.auto_awesome_mosaic,
                      label: 'Generate All',
                      onPressed:
                          canGenerateMatches ? () => _generateMatches() : () {},
                      color: canGenerateMatches ? _accentColor : Colors.grey,
                      enabled: canGenerateMatches,
                      disabledReason:
                          canGenerateMatches ? null : _timeUntilCanGenerate,
                    ),
                 if (isCreator && hasMatches)
  _buildIconButton(
    icon: Icons.restart_alt,
    label: 'Reset All',
    onPressed: _hasStartedOrCompletedMatches ? () {} : () { _resetMatches(); },
    color: _hasStartedOrCompletedMatches ? Colors.grey : _errorColor,
    enabled: !_hasStartedOrCompletedMatches && canGenerateMatches,
    disabledReason: _hasStartedOrCompletedMatches 
        ? 'Cannot reset - matches are in progress or completed'
        : _timeUntilCanGenerate,
  ),
                ],
              ),

              // Registration status message - ALWAYS show when registration hasn't ended
              if (!canGenerateMatches)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _timeUntilCanGenerate,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: _secondaryText,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),

        // Rest of the code remains the same...
        // Round navigation (only show if there are multiple rounds)
        if (sortedRounds.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous button
                IconButton(
                  onPressed:
                      _currentRoundPage > 0
                          ? () {
                            setState(() {
                              _currentRoundPage--;
                            });
                          }
                          : null,
                  icon: Icon(
                    Icons.arrow_back_ios,
                    color:
                        _currentRoundPage > 0
                            ? _accentColor
                            : Colors.grey.shade400,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        _currentRoundPage > 0
                            ? _accentColor.withOpacity(0.1)
                            : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),

                // Round indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accentColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Round ${sortedRounds[_currentRoundPage]} of ${sortedRounds.length}',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _accentColor,
                    ),
                  ),
                ),

                // Next button
                IconButton(
                  onPressed:
                      _currentRoundPage < sortedRounds.length - 1
                          ? () {
                            setState(() {
                              _currentRoundPage++;
                            });
                          }
                          : null,
                  icon: Icon(
                    Icons.arrow_forward_ios,
                    color:
                        _currentRoundPage < sortedRounds.length - 1
                            ? _accentColor
                            : Colors.grey.shade400,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        _currentRoundPage < sortedRounds.length - 1
                            ? _accentColor.withOpacity(0.1)
                            : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Matches content
        Expanded(
          child:
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _matches.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.sports_tennis,
                          size: 64,
                          color: _secondaryText.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No matches scheduled yet',
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (isCreator &&
                            canGenerateMatches &&
                            hasEnoughParticipants)
                          Text(
                            'Create matches manually or generate a complete schedule',
                            style: GoogleFonts.poppins(
                              color: _secondaryText.withOpacity(0.7),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        if (!hasEnoughParticipants)
                          Text(
                            'Need at least 2 participants to create matches',
                            style: GoogleFonts.poppins(
                              color: _secondaryText.withOpacity(0.7),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
                  )
                  : sortedRounds.isEmpty
                  ? const Center(child: Text('No rounds available'))
                  : _buildCurrentRoundMatches(
                    sortedRounds[_currentRoundPage],
                    matchesByRound[sortedRounds[_currentRoundPage]]!,
                    selectedEvent,
                    isCreator,
                  ),
        ),
      ],
    );
  }


bool _hasTBDPlayers(Map<String, dynamic> match) {
  final isDoubles = match['matchType'].toString().toLowerCase().contains('doubles');
  if (isDoubles) {
    final team1Ids = List<String>.from(match['team1Ids'] ?? []);
    final team2Ids = List<String>.from(match['team2Ids'] ?? []);
    return team1Ids.contains('TBD') || team2Ids.contains('TBD');
  } else {
    return match['player1Id'] == 'TBD' || match['player2Id'] == 'TBD';
  }
}

bool _wasTBDButAssigned(Map<String, dynamic> match) {
  return match['wasTBD1'] == true || 
         match['wasTBD2'] == true || 
         match['wasTBDTeam1'] == true || 
         match['wasTBDTeam2'] == true;
}



Widget _buildCurrentRoundMatches(
  int round,
  List<Map<String, dynamic>> roundMatches,
  Event selectedEvent,
  bool isCreator,
) {
  final isDoubles = selectedEvent.matchType.toLowerCase().contains('doubles');

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Round header
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _accentColor.withOpacity(0.1),
              _accentColor.withOpacity(0.05),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, color: _accentColor, size: 24),
            const SizedBox(width: 12),
            Text(
              'Round $round',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _accentColor,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${roundMatches.length} ${roundMatches.length == 1 ? 'Match' : 'Matches'}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: roundMatches.length,
          itemBuilder: (context, matchIndex) {
            final match = roundMatches[matchIndex];
            final isBye = match['isBye'] == true;
            final isCompleted = match['completed'] == true;
            final winner = match['winner'] as String?;
            
            // Special styling for bye matches
            if (isBye) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.emoji_events_outlined,
                      color: Colors.grey.shade600,
                      size: 24,
                    ),
                  ),
                  title: Text(
                    isDoubles
                        ? '${(match['team1'] as List).join(' & ')} receives a bye'
                        : '${match['player1']} receives a bye',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        'Automatic advance to next round',
                        style: GoogleFonts.poppins(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  
                ),
              );
            }
            
            // Regular match display
            final startTime = (match['startTime'] as Timestamp?)?.toDate() ?? DateTime.now();
            final scores = match['liveScores'] ?? {
              isDoubles ? 'team1' : 'player1': [0, 0, 0],
              isDoubles ? 'team2' : 'player2': [0, 0, 0],
            };

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: isCompleted
                    ? Border.all(
                      color: _successColor.withOpacity(0.3),
                      width: 1.5,
                    )
                    : null,
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient:
                        isCompleted
                            ? LinearGradient(
                              colors: [
                                _successColor,
                                _successColor.withOpacity(0.7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                            : LinearGradient(
                              colors: [
                                _accentColor,
                                _accentColor.withOpacity(0.7),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isCompleted ? _successColor : _accentColor)
                            .withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isCompleted ? Icons.check_circle : Icons.schedule,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                title: Text(
                  isDoubles
                      ? '${(match['team1'] as List).join(' & ')} vs ${(match['team2'] as List).join(' & ')}'
                      : '${match['player1']} vs ${match['player2']}',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    fontSize: 16,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: _secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Court ${match['court']}',
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: _secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            match['timeSlot'],
                            style: GoogleFonts.poppins(
                              color: _secondaryText,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: _secondaryText,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDateTime(startTime),
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (isCompleted) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _successColor.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (winner != null)
                              Text.rich(
                                TextSpan(
                                  text: 'Winner: ',
                                  style: GoogleFonts.poppins(
                                    color: _secondaryText,
                                    fontSize: 12,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          winner == 'team1' ||
                                                  winner == 'player1'
                                              ? (isDoubles
                                                  ? (match['team1'] as List)
                                                      .join(' & ')
                                                  : match['player1'])
                                              : (isDoubles
                                                  ? (match['team2'] as List)
                                                      .join(' & ')
                                                  : match['player2']),
                                      style: GoogleFonts.poppins(
                                        color: _successColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              'Score: ${(scores[isDoubles ? 'team1' : 'player1'] as List).join('-')} vs ${(scores[isDoubles ? 'team2' : 'player2'] as List).join('-')}',
                              style: GoogleFonts.poppins(
                                color: _secondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                trailing:
                
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    if ((isCreator || _isUmpire) && 
        (_hasTBDPlayers(match) || _wasTBDButAssigned(match)))
      _buildIconOnlyButton(
        icon: Icons.edit,
        onPressed: () => _showEditMatchDialog(match, matchIndex),
        color: _accentColor,
      ),
    if (isCreator)
      _buildIconOnlyButton(
        icon: Icons.delete_outline,
        onPressed: () {
          _showDeleteConfirmation(context, matchIndex);
        },
        color: _errorColor,
      ),
                      ],
                    ),
                onTap: () {
                  final matchIndex = _matches.indexWhere(
                    (m) => m['matchId'] == match['matchId'],
                  );
                  if (matchIndex != -1) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => MatchDetailsPage(
                              match: match,
                              tournamentId: widget.tournament.id,
                              isCreator: isCreator,
                              isUmpire: _isUmpire,
                              isDoubles: isDoubles,
                              matchIndex: matchIndex,
                              onDeleteMatch: () {
                                final idx = _matches.indexWhere(
                                  (m) => m['matchId'] == match['matchId'],
                                );
                                if (idx != -1) {
                                  _deleteMatch(idx);
                                }
                              },
                            ),
                      ),
                    );
                  }
                },
              ),
            );
          },
        ),
      ),
    ],
  );
}


  Widget _buildLeaderboardTab() {
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final isDoubles = selectedEvent.matchType.toLowerCase().contains('doubles');
    final sortedLeaderboard =
        _leaderboardData.entries.toList()..sort(
          (a, b) =>
              (b.value['score'] as int).compareTo(a.value['score'] as int),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with improved styling
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.leaderboard_outlined, color: _accentColor, size: 24),
              const SizedBox(width: 12),
              Text(
                selectedEvent.name,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              const Spacer(),
              if (sortedLeaderboard.isNotEmpty)
                Text(
                  '${sortedLeaderboard.length} ${isDoubles ? 'Teams' : 'Players'}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _secondaryText,
                  ),
                ),
            ],
          ),
        ),

        // Leaderboard content
        Expanded(
          child:
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : sortedLeaderboard.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.leaderboard_outlined,
                          size: 64,
                          color: _secondaryText.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No leaderboard data available',
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Complete matches to see rankings',
                          style: GoogleFonts.poppins(
                            color: _secondaryText.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                  : Column(
                    children: [
                      // Table header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        color: Colors.grey.shade50,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                '#',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _secondaryText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Text(
                                isDoubles ? 'Team' : 'Player',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _secondaryText,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Wins',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _secondaryText,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Leaderboard list
                      Expanded(
                        child: AnimationLimiter(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: sortedLeaderboard.length,
                            itemBuilder: (context, index) {
                              final entry = sortedLeaderboard[index];
                              final rank = index + 1;
                              final isTopThree = index < 3;

                              return AnimationConfiguration.staggeredList(
                                position: index,
                                duration: const Duration(milliseconds: 375),
                                child: SlideAnimation(
                                  verticalOffset: 50.0,
                                  child: FadeInAnimation(
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.03,
                                            ),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                        leading: Container(
                                          width: 36,
                                          height: 36,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color:
                                                isTopThree
                                                    ? (index == 0
                                                        ? _goldColor
                                                            .withOpacity(0.1)
                                                        : index == 1
                                                        ? _silverColor
                                                            .withOpacity(0.1)
                                                        : _bronzeColor
                                                            .withOpacity(0.1))
                                                    : _accentColor.withOpacity(
                                                      0.1,
                                                    ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color:
                                                  isTopThree
                                                      ? (index == 0
                                                          ? _goldColor
                                                          : index == 1
                                                          ? _silverColor
                                                          : _bronzeColor)
                                                      : _accentColor
                                                          .withOpacity(0.3),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Text(
                                            '$rank',
                                            style: GoogleFonts.poppins(
                                              color:
                                                  isTopThree
                                                      ? (index == 0
                                                          ? _goldColor
                                                          : index == 1
                                                          ? _silverColor
                                                          : _bronzeColor)
                                                      : _accentColor,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          entry.value['name'],
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w500,
                                            color: _textColor,
                                          ),
                                        ),
                                        trailing: Container(
                                          width: 40,
                                          height: 40,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: _accentColor.withOpacity(
                                              0.1,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '${entry.value['score']}',
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              color: _accentColor,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
        ),
      ],
    );
  }

  String _calculateDuration(DateTime startDate, DateTime endDate) {
    final duration = endDate.difference(startDate);
    final days = duration.inDays;

    if (days == 0) {
      return 'Single day event';
    } else if (days == 1) {
      return '2 days';
    } else {
      return '${days + 1} days';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreator =
        context.read<AuthBloc>().state is AuthAuthenticated &&
        (context.read<AuthBloc>().state as AuthAuthenticated).user.uid ==
            widget.tournament.createdBy;

    return Scaffold(
      backgroundColor: _secondaryColor,
      body: DefaultTabController(
        length: 5,
        child: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 200.0,
                floating: false,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    widget.tournament.name,
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      _tournamentProfileImage != null &&
                              _tournamentProfileImage!.isNotEmpty
                          ? Image.network(
                            _tournamentProfileImage!,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (context, error, stackTrace) => Image.asset(
                                  'assets/tournament_placholder.jpg',
                                  fit: BoxFit.cover,
                                ),
                          )
                          : Image.asset(
                            'assets/tournament_placholder.jpg',
                            fit: BoxFit.cover,
                          ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _secondaryColor.withOpacity(0.7),
                              _primaryColor.withOpacity(0.7),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                backgroundColor: _secondaryColor,
                elevation: 10,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.image, color: Colors.white),
                    onPressed: () => _showImageOptionsDialog(isCreator),
                  ),
                  if (isCreator)
                    _buildIconOnlyButton(
                      icon: Icons.settings,
                      onPressed: _configureTournamentSettings,
                      color: Colors.white,
                    ),
                ],
              ),

              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  color: _cardBackground,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event details and sponsor image side by side
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final screenWidth = MediaQuery.of(context).size.width;
                          final isSmallScreen = screenWidth < 400;
                          final imageWidth = isSmallScreen ? 80.0 : 100.0;
                          final imageHeight = isSmallScreen ? 48.0 : 60.0;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Event details
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Event Name
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.event_outlined,
                                            color: _accentColor,
                                            size: isSmallScreen ? 20 : 22,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              widget
                                                  .tournament
                                                  .events[_selectedEventIndex]
                                                  .name,
                                              style: GoogleFonts.poppins(
                                                fontSize:
                                                    isSmallScreen ? 16 : 20,
                                                fontWeight: FontWeight.w600,
                                                color: _textColor,
                                                height: 1.3,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 12),

                                      // Creator Info
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.person_outlined,
                                            color: _secondaryText.withOpacity(
                                              0.7,
                                            ),
                                            size: isSmallScreen ? 16 : 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Created by ${widget.creatorName}',
                                            style: GoogleFonts.poppins(
                                              fontSize: isSmallScreen ? 14 : 15,
                                              color: _secondaryText,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 8),

                                      // Date Range
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today_outlined,
                                            color: _secondaryText.withOpacity(
                                              0.7,
                                            ),
                                            size: isSmallScreen ? 16 : 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${DateFormat('MMM dd, yyyy').format(widget.tournament.startDate)} - ${DateFormat('MMM dd, yyyy').format(widget.tournament.endDate)}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize:
                                                        isSmallScreen ? 14 : 15,
                                                    color: _secondaryText,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  _calculateDuration(
                                                    widget.tournament.startDate,
                                                    widget.tournament.endDate,
                                                  ),
                                                  style: GoogleFonts.poppins(
                                                    fontSize:
                                                        isSmallScreen ? 12 : 13,
                                                    color: _secondaryText
                                                        .withOpacity(0.7),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),
                              // Sponsor image
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: imageWidth,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Sponsored by:',
                                      style: GoogleFonts.poppins(
                                        fontSize: isSmallScreen ? 8 : 12,
                                        fontWeight: FontWeight.w600,
                                        color: _textColor,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap:
                                          () => _showFullImageDialog(
                                            _sponsorImage,
                                            'Sponsor Image',
                                          ),
                                      child: Container(
                                        height: imageHeight,
                                        width: imageWidth,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          color: _secondaryColor.withOpacity(
                                            0.2,
                                          ),
                                        ),
                                        child:
                                            _sponsorImage != null &&
                                                    _sponsorImage!.isNotEmpty
                                                ? Image.network(
                                                  _sponsorImage!,
                                                  fit: BoxFit.contain,
                                                  loadingBuilder: (
                                                    context,
                                                    child,
                                                    loadingProgress,
                                                  ) {
                                                    if (loadingProgress ==
                                                        null) {
                                                      return child;
                                                    }
                                                    return Center(
                                                      child: CircularProgressIndicator(
                                                        value:
                                                            loadingProgress
                                                                        .expectedTotalBytes !=
                                                                    null
                                                                ? loadingProgress
                                                                        .cumulativeBytesLoaded /
                                                                    loadingProgress
                                                                        .expectedTotalBytes!
                                                                : null,
                                                      ),
                                                    );
                                                  },
                                                  errorBuilder: (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) {
                                                    debugPrint(
                                                      'Error loading sponsor image: $error',
                                                    );
                                                    return Center(
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Icon(
                                                            Icons.error,
                                                            color: _errorColor,
                                                            size:
                                                                isSmallScreen
                                                                    ? 20
                                                                    : 24,
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Text(
                                                            'Failed to load',
                                                            style: GoogleFonts.poppins(
                                                              color:
                                                                  _secondaryText,
                                                              fontSize:
                                                                  isSmallScreen
                                                                      ? 10
                                                                      : 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                )
                                                : Image.asset(
                                                  'assets/tournament_placholder.jpg',
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) {
                                                    debugPrint(
                                                      'Error loading placeholder image: $error',
                                                    );
                                                    return Center(
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Icon(
                                                            Icons.error,
                                                            color: _errorColor,
                                                            size:
                                                                isSmallScreen
                                                                    ? 20
                                                                    : 24,
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Text(
                                                            'Failed to load',
                                                            style: GoogleFonts.poppins(
                                                              color:
                                                                  _secondaryText,
                                                              fontSize:
                                                                  isSmallScreen
                                                                      ? 10
                                                                      : 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      // Event selection chips
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8.0,
                        children:
                            widget.tournament.events.asMap().entries.map((
                              entry,
                            ) {
                              return ChoiceChip(
                                label: Text(
                                  entry.value.name,
                                  style: GoogleFonts.poppins(
                                    color:
                                        _selectedEventIndex == entry.key
                                            ? Colors.white
                                            : _textColor,
                                  ),
                                ),
                                selected: _selectedEventIndex == entry.key,
                                selectedColor: _accentColor,
                                backgroundColor: _cardBackground,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: _accentColor.withOpacity(0.5),
                                  ),
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedEventIndex = entry.key;
                                      _participants =
                                          widget
                                              .tournament
                                              .events[_selectedEventIndex]
                                              .participants
                                              .map(
                                                (id) => {
                                                  'id': id,
                                                  'name': null,
                                                },
                                              )
                                              .toList();
                                      _numberOfCourts =
                                          widget
                                              .tournament
                                              .events[_selectedEventIndex]
                                              .numberOfCourts;
                                      _timeSlots =
                                          widget
                                              .tournament
                                              .events[_selectedEventIndex]
                                              .timeSlots;
                                      _hasJoined = false;
                                      _checkIfJoined();
                                      _loadParticipants();
                                      _loadMatches();
                                      _generateLeaderboardData();
                                    });
                                  }
                                },
                              );
                            }).toList(),
                      ),
                      // Join/Withdraw button and registration info
                      const SizedBox(height: 16),
                      if (!isCreator)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildIconButton(
                                  icon:
                                      _hasJoined
                                          ? Icons.remove_circle
                                          : Icons.add_circle,
                                  label: _hasJoined ? 'Withdraw' : 'Join Event',
                                  onPressed:
                                      () =>
                                          _hasJoined
                                              ? _withdrawFromTournament(context)
                                              : _joinTournament(context),
                                  color:
                                      _hasJoined ? _errorColor : _successColor,
                                  enabled:
                                      !_isLoading &&
                                      (_hasJoined
                                          ? !DateTime.now().toUtc().isAfter(
                                            widget.tournament.registrationEnd,
                                          )
                                          : !DateTime.now().toUtc().isAfter(
                                            widget.tournament.registrationEnd,
                                          )),
                                  disabledReason:
                                      _hasJoined
                                          ? 'Cannot withdraw after registration has ended'
                                          : 'Registration has ended',
                                ),
                                Text(
                                  '${_participants.length}/${widget.tournament.events[_selectedEventIndex].maxParticipants} Participants',
                                  style: GoogleFonts.poppins(
                                    color: _textColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              DateTime.now().toUtc().isAfter(
                                    widget.tournament.registrationEnd,
                                  )
                                  ? 'Registration closed on: ${DateFormat('MMM dd, yyyy, hh:mm a').format(widget.tournament.registrationEnd)}'
                                  : 'Registration ends: ${DateFormat('MMM dd, yyyy, hh:mm a').format(widget.tournament.registrationEnd)}',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color:
                                    DateTime.now().toUtc().isAfter(
                                          widget.tournament.registrationEnd,
                                        )
                                        ? _errorColor
                                        : _secondaryText,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              SliverPersistentHeader(
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelColor: _accentColor,
                    unselectedLabelColor: _secondaryText,
                    indicatorColor: _accentColor,
                    labelStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(text: 'Details'),
                      Tab(text: 'Matches'),
                      Tab(text: 'Participants'),
                      Tab(text: 'Leaderboard'),
                      Tab(text: 'Rules'),
                    ],
                  ),
                ),
                pinned: true,
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildDetailsTab(),
              _buildMatchesTab(),
              _buildParticipantsTab(),
              _buildLeaderboardTab(),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tournament Rules',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (widget.tournament.rules != null &&
                              widget.tournament.rules!.isNotEmpty)
                          ? widget.tournament.rules!
                          : 'No specific rules provided for this tournament.',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: _textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: const Color(0xFFC1DADB), child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

Widget _buildDetailRow({
  required IconData icon,
  required String label,
  required String value,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: Colors.grey.shade700),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ManualMatchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> competitors;
  final Event selectedEvent;
  final bool isDoubles;
  final bool isMixed;
  final Function(dynamic, dynamic, int, String)
  onCreateMatch; // MODIFIED: Remove DateTime parameter
  final Color primaryColor;
  final Color accentColor;
  final Color textColor;
  final Color secondaryText;
  final Color cardBackground;
  final Color successColor;

  const _ManualMatchDialog({
    required this.competitors,
    required this.selectedEvent,
    required this.isDoubles,
    required this.isMixed,
    required this.onCreateMatch,
    required this.primaryColor,
    required this.accentColor,
    required this.textColor,
    required this.secondaryText,
    required this.cardBackground,
    required this.successColor,
  });

  @override
  State<_ManualMatchDialog> createState() => _ManualMatchDialogState();
}

class _ManualMatchDialogState extends State<_ManualMatchDialog> {
  dynamic selectedCompetitor1;
  dynamic selectedCompetitor2;
  int selectedCourt = 1;
  String selectedTimeSlot = '';
  List<Map<String, dynamic>> availableTeams = [];
  bool isLoadingTeams = false;

  @override
  void initState() {
    super.initState();
    selectedTimeSlot =
        widget.selectedEvent.timeSlots.isNotEmpty
            ? widget.selectedEvent.timeSlots[0]
            : 'TBD';

    if (widget.isDoubles) {
      _generateTeamsForManualMatch();
    }
  }

  Future<void> _generateTeamsForManualMatch() async {
    setState(() {
      isLoadingTeams = true;
    });

    try {
      final teams = <Map<String, dynamic>>[];
      final competitors = widget.competitors;

      if (widget.isMixed) {
        // For mixed doubles: create teams with gender validation
        final males = <Map<String, dynamic>>[];
        final females = <Map<String, dynamic>>[];

        for (var participant in competitors) {
          final userDetails =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(participant['id'])
                  .get();

          if (userDetails.exists) {
            final gender =
                userDetails.data()?['gender']?.toString().toLowerCase() ??
                'not_specified';
            final firstName = userDetails.data()?['firstName'] ?? '';
            final lastName = userDetails.data()?['lastName'] ?? '';

            final playerData = {
              ...participant,
              'gender': gender,
              'firstName': firstName,
              'lastName': lastName,
              'fullName': '$firstName $lastName'.trim(),
            };

            if (gender == 'male') {
              males.add(playerData);
            } else if (gender == 'female') {
              females.add(playerData);
            }
          }
        }

        // Create all possible mixed teams (1 male + 1 female)
        for (var male in males) {
          for (var female in females) {
            teams.add({
              'teamId': 'mixed_${male['id']}_${female['id']}',
              'playerIds': [male['id'], female['id']],
              'playerNames': [male['fullName'], female['fullName']],
              'playerGenders': ['male', 'female'],
              'teamType': 'mixed',
              'displayName': '${male['fullName']} & ${female['fullName']}',
            });
          }
        }
      } else {
        // For same-gender doubles: create all possible combinations
        for (int i = 0; i < competitors.length; i++) {
          for (int j = i + 1; j < competitors.length; j++) {
            final player1 = competitors[i];
            final player2 = competitors[j];

            // Get user details
            final player1Details =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(player1['id'])
                    .get();
            final player2Details =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(player2['id'])
                    .get();

            final player1Name =
                player1Details.exists
                    ? '${player1Details.data()?['firstName'] ?? ''} ${player1Details.data()?['lastName'] ?? ''}'
                        .trim()
                    : player1['name'] ?? 'Unknown';
            final player2Name =
                player2Details.exists
                    ? '${player2Details.data()?['firstName'] ?? ''} ${player2Details.data()?['lastName'] ?? ''}'
                        .trim()
                    : player2['name'] ?? 'Unknown';

            teams.add({
              'teamId': 'team_${player1['id']}_${player2['id']}',
              'playerIds': [player1['id'], player2['id']],
              'playerNames': [player1Name, player2Name],
              'playerGenders': [
                player1Details.data()?['gender']?.toString().toLowerCase() ??
                    'unknown',
                player2Details.data()?['gender']?.toString().toLowerCase() ??
                    'unknown',
              ],
              'teamType': 'same_gender',
              'displayName': '$player1Name & $player2Name',
            });
          }
        }
      }

      setState(() {
        availableTeams = teams;
      });
    } catch (e) {
      debugPrint('Error generating teams: $e');
    } finally {
      setState(() {
        isLoadingTeams = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final competitorsList =
        widget.isDoubles ? availableTeams : widget.competitors;

    return AlertDialog(
      backgroundColor: widget.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Create Manual Match',
        style: GoogleFonts.poppins(
          color: widget.textColor,
          fontWeight: FontWeight.bold,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9, // Dynamic width
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Event: ${widget.selectedEvent.name}',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: widget.accentColor,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    Text(
                      'Type: ${widget.selectedEvent.matchType}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: widget.secondaryText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.isMixed)
                      Text(
                        'Teams must have 1 male + 1 female',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: widget.accentColor,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Loading indicator for teams
              if (widget.isDoubles && isLoadingTeams)
                const Center(child: CircularProgressIndicator()),

              // Competitor/Team Selection
              if (!isLoadingTeams) ...[
                DropdownButtonFormField<dynamic>(
                  decoration: InputDecoration(
                    labelText:
                        widget.isDoubles ? 'Select Team 1' : 'Select Player 1',
                    labelStyle: GoogleFonts.poppins(
                      color: widget.textColor.withOpacity(0.7),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.accentColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  isExpanded: true,
                  items:
                      competitorsList.map((competitor) {
                        return DropdownMenuItem(
                          value: competitor,
                          child: Text(
                            widget.isDoubles
                                ? competitor['displayName'] ?? 'Unknown Team'
                                : competitor['name'] ?? competitor['id'],
                            style: GoogleFonts.poppins(color: widget.textColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCompetitor1 = value;
                    });
                  },
                ),

                const SizedBox(height: 16),

                DropdownButtonFormField<dynamic>(
                  decoration: InputDecoration(
                    labelText:
                        widget.isDoubles ? 'Select Team 2' : 'Select Player 2',
                    labelStyle: GoogleFonts.poppins(
                      color: widget.textColor.withOpacity(0.7),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: widget.accentColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  isExpanded: true,
                  items:
                      competitorsList
                          .where((competitor) {
                            // Exclude the already selected competitor
                            return competitor != selectedCompetitor1;
                          })
                          .map((competitor) {
                            return DropdownMenuItem(
                              value: competitor,
                              child: Text(
                                widget.isDoubles
                                    ? competitor['displayName'] ??
                                        'Unknown Team'
                                    : competitor['name'] ?? competitor['id'],
                                style: GoogleFonts.poppins(
                                  color: widget.textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          })
                          .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCompetitor2 = value;
                    });
                  },
                ),
              ],

              const SizedBox(height: 16),

              // Court and Time Slot Selection
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width:
                        MediaQuery.of(context).size.width >= 600
                            ? (MediaQuery.of(context).size.width * 0.9 - 16) / 2
                            : MediaQuery.of(context).size.width * 0.9,
                    child: DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: 'Court',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      value: selectedCourt,
                      items:
                          List.generate(
                                widget.selectedEvent.numberOfCourts,
                                (index) => index + 1,
                              )
                              .map(
                                (court) => DropdownMenuItem(
                                  value: court,
                                  child: Text(
                                    'Court $court',
                                    style: GoogleFonts.poppins(
                                      color: widget.textColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedCourt = value!;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width:
                        MediaQuery.of(context).size.width >= 600
                            ? (MediaQuery.of(context).size.width * 0.9 - 16) / 2
                            : MediaQuery.of(context).size.width * 0.9,
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Time Slot',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      value: selectedTimeSlot,
                      items:
                          widget.selectedEvent.timeSlots
                              .map(
                                (slot) => DropdownMenuItem(
                                  value: slot,
                                  child: Text(
                                    slot,
                                    style: GoogleFonts.poppins(
                                      color: widget.textColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedTimeSlot = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: GoogleFonts.poppins(color: widget.secondaryText),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: () {
            if (selectedCompetitor1 == null || selectedCompetitor2 == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Please select both ${widget.isDoubles ? 'teams' : 'players'}',
                    style: GoogleFonts.poppins(),
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            Navigator.pop(context);

            widget.onCreateMatch(
              selectedCompetitor1,
              selectedCompetitor2,
              selectedCourt,
              selectedTimeSlot,
            );
          },
          child: Text(
            'Create',
            style: GoogleFonts.poppins(
              color: widget.successColor,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}



class _EditMatchDialog extends StatefulWidget {
  final Map<String, dynamic> match;
  final bool isDoubles;
  final String tournamentId;
  final String eventName;
  final List<Map<String, dynamic>> participants;
  final List<Map<String, dynamic>> availablePlayers;
  final Function(Map<String, dynamic>) onSave;
  final Color primaryColor;
  final Color accentColor;
  final Color textColor;
  final Color secondaryText;
  final Color cardBackground;
  final Color successColor;

  const _EditMatchDialog({
    required this.match,
    required this.isDoubles,
    required this.tournamentId,
    required this.eventName,
    required this.participants,
    required this.availablePlayers,
    required this.onSave,
    required this.primaryColor,
    required this.accentColor,
    required this.textColor,
    required this.secondaryText,
    required this.cardBackground,
    required this.successColor,
  });

  @override
  State<_EditMatchDialog> createState() => _EditMatchDialogState();
}

class _EditMatchDialogState extends State<_EditMatchDialog> {
  dynamic editedPlayer1;
  dynamic editedPlayer2;
  dynamic editedTeam1;
  dynamic editedTeam2;
  int editedCourt = 1;
  String editedTimeSlot = '';

  @override
  void initState() {
    super.initState();
    _initializeValues();
  }

  void _initializeValues() {
    editedCourt = widget.match['court'] ?? 1;
    editedTimeSlot = widget.match['timeSlot'] ?? '';
    
    if (widget.isDoubles) {
      editedTeam1 = widget.match['team1'];
      editedTeam2 = widget.match['team2'];
    } else {
      final isTBD1 = widget.match['wasTBD1'] == true;
      final isTBD2 = widget.match['wasTBD2'] == true;
      
      editedPlayer1 = isTBD1 ? null : widget.match['player1Id'];
      editedPlayer2 = isTBD2 ? null : widget.match['player2Id'];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: widget.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              decoration: BoxDecoration(
                color: widget.primaryColor.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.sports_tennis, color: widget.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Edit Match',
                      style: GoogleFonts.poppins(
                        color: widget.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isDoubles) ...[
                      _buildTeamSelector('Team 1', editedTeam1, (value) {
                        setState(() => editedTeam1 = value);
                      }, true),
                      const SizedBox(height: 16),
                      _buildTeamSelector('Team 2', editedTeam2, (value) {
                        setState(() => editedTeam2 = value);
                      }, false),
                    ] else ...[
                      _buildPlayerDisplay('Player 1', editedPlayer1, true),
                      const SizedBox(height: 16),
                      _buildPlayerDisplay('Player 2', editedPlayer2, false),
                    ],
                    const SizedBox(height: 16),
                    _buildCourtSelector(),
                    const SizedBox(height: 16),
                    _buildTimeSlotSelector(),
                  ],
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: widget.secondaryText.withOpacity(0.1)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: widget.secondaryText,
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.successColor,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      'Save',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerDisplay(String label, dynamic currentPlayerId, bool isPlayer1) {
    final isTBD = isPlayer1 ? widget.match['wasTBD1'] == true : widget.match['wasTBD2'] == true;
    final playerName = isPlayer1 ? widget.match['player1'] : widget.match['player2'];

    if (!isTBD) {
      return _buildReadOnlyPlayerCard(label, playerName ?? 'Unknown Player', true);
    } else {
      return _buildPlayerSelector(label, currentPlayerId, (value) {
        setState(() {
          if (isPlayer1) {
            editedPlayer1 = value;
          } else {
            editedPlayer2 = value;
          }
        });
      }, isPlayer1);
    }
  }

  Widget _buildReadOnlyPlayerCard(String label, String playerName, bool isAssigned) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: widget.textColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            if (isAssigned)
              Icon(Icons.check_circle, color: widget.successColor, size: 16),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: widget.secondaryText.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
            color: widget.cardBackground.withOpacity(0.5),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: widget.primaryColor,
                radius: 20,
                child: Text(
                  playerName.substring(0, 1).toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playerName,
                      style: GoogleFonts.poppins(
                        color: widget.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Already assigned',
                      style: GoogleFonts.poppins(
                        color: widget.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerSelector(String label, dynamic currentValue, Function(dynamic) onChanged, bool isPlayer1) {
    List<DropdownMenuItem<dynamic>> playerItems = [];
    
    try {
      playerItems = widget.availablePlayers.map((player) {
        return DropdownMenuItem<dynamic>(
          value: player,
          child: _buildDropdownItem(player),
        );
      }).toList();
    } catch (e) {
      // Fallback if there's an error creating items
      playerItems = [
        DropdownMenuItem<dynamic>(
          value: null,
          child: _buildDropdownItem({'name': 'Error loading players', 'id': null}),
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: widget.textColor,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: DropdownButtonFormField<dynamic>(
            value: _getValidDropdownValue(currentValue),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.secondaryText.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.secondaryText.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.primaryColor, width: 2),
              ),
              filled: true,
              fillColor: widget.cardBackground.withOpacity(0.5),
              hintText: 'Assign Player to TBD',
              hintStyle: GoogleFonts.poppins(
                color: widget.secondaryText,
                fontSize: 14,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Icon(Icons.person_add, color: widget.secondaryText),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            isExpanded: true,
            items: playerItems,
            onChanged: onChanged,
            validator: (value) {
              if (value == null) {
                return 'Please assign a player';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownItem(Map<String, dynamic> player) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200), // Fixed width constraint
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: widget.primaryColor,
            radius: 16,
            child: Text(
              player['name']?.toString().substring(0, 1).toUpperCase() ?? '?',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              player['name'] ?? player['id']?.toString() ?? 'Unknown Player',
              style: GoogleFonts.poppins(
                color: widget.textColor,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  dynamic _getValidDropdownValue(dynamic currentValue) {
    if (currentValue == null) return null;
    
    try {
      return widget.availablePlayers.any((player) => 
        player['id']?.toString() == currentValue?.toString()
      ) ? currentValue : null;
    } catch (e) {
      return null;
    }
  }

  Widget _buildTeamSelector(String label, dynamic currentValue, Function(dynamic) onChanged, bool isTeam1) {
    final isTBD = isTeam1 ? widget.match['wasTBDTeam1'] == true : widget.match['wasTBDTeam2'] == true;
    
    if (!isTBD) {
      return _buildReadOnlyTeamCard(label, true);
    } else {
      return _buildTBDTeamCard(label);
    }
  }

  Widget _buildReadOnlyTeamCard(String label, bool isAssigned) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: widget.textColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            if (isAssigned)
              Icon(Icons.check_circle, color: widget.successColor, size: 16),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: widget.secondaryText.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
            color: widget.cardBackground.withOpacity(0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.group, color: widget.primaryColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Team Already Assigned',
                      style: GoogleFonts.poppins(
                        color: widget.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'No changes needed',
                      style: GoogleFonts.poppins(
                        color: widget.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTBDTeamCard(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: widget.textColor,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.orange.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
            color: Colors.orange.withOpacity(0.05),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TBD - Team assignment needed',
                  style: GoogleFonts.poppins(
                    color: widget.textColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCourtSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Court',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: widget.textColor,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: DropdownButtonFormField<int>(
            value: editedCourt,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.secondaryText.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.secondaryText.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.primaryColor, width: 2),
              ),
              filled: true,
              fillColor: widget.cardBackground.withOpacity(0.5),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Icon(Icons.sports_tennis, color: widget.secondaryText),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            isExpanded: true,
            items: List.generate(10, (index) => index + 1).map((court) {
              return DropdownMenuItem<int>(
                value: court,
                child: Text(
                  'Court $court',
                  style: GoogleFonts.poppins(
                    color: widget.textColor,
                    fontSize: 14,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => editedCourt = value);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSlotSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Time Slot',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: widget.textColor,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextFormField(
            initialValue: editedTimeSlot,
            onChanged: (value) => setState(() => editedTimeSlot = value),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.secondaryText.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.secondaryText.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.primaryColor, width: 2),
              ),
              filled: true,
              fillColor: widget.cardBackground.withOpacity(0.5),
              hintText: 'e.g., 10:00 AM - 12:00 PM',
              hintStyle: GoogleFonts.poppins(
                color: widget.secondaryText,
                fontSize: 14,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Icon(Icons.schedule, color: widget.secondaryText),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            style: GoogleFonts.poppins(
              color: widget.textColor,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  void _saveChanges() {
    try {
      final updatedMatch = Map<String, dynamic>.from(widget.match);
      
      if (widget.isDoubles) {
        updatedMatch['wasTBDTeam1'] = editedTeam1 == null;
        updatedMatch['wasTBDTeam2'] = editedTeam2 == null;
      } else {
        final isTBD1 = widget.match['wasTBD1'] == true;
        final isTBD2 = widget.match['wasTBD2'] == true;
        
        if (isTBD1 && editedPlayer1 != null) {
          updatedMatch['player1Id'] = editedPlayer1['id'];
          updatedMatch['player1'] = editedPlayer1['name'];
          updatedMatch['wasTBD1'] = false;
        }
        
        if (isTBD2 && editedPlayer2 != null) {
          updatedMatch['player2Id'] = editedPlayer2['id'];
          updatedMatch['player2'] = editedPlayer2['name'];
          updatedMatch['wasTBD2'] = false;
        }
        
        if (!isTBD1) {
          updatedMatch['player1Id'] = widget.match['player1Id'];
          updatedMatch['player1'] = widget.match['player1'];
          updatedMatch['wasTBD1'] = false;
        }
        
        if (!isTBD2) {
          updatedMatch['player2Id'] = widget.match['player2Id'];
          updatedMatch['player2'] = widget.match['player2'];
          updatedMatch['wasTBD2'] = false;
        }
      }
      
      updatedMatch['court'] = editedCourt;
      updatedMatch['timeSlot'] = editedTimeSlot;
      
      widget.onSave(updatedMatch);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Handle any errors silently
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}