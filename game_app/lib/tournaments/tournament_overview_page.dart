import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/tournaments/match_details_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
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
    _tabController = TabController(length: 5, vsync: this);
    _participants = widget.tournament.events[_selectedEventIndex].participants
        .map((id) => {'id': id, 'name': null})
        .toList();
    _matches = [];
    _tournamentProfileImage = widget.tournament.profileImage;
    _sponsorImage = widget.tournament.sponsorImage;
    _numberOfCourts = widget.tournament.events[_selectedEventIndex].numberOfCourts;
    _timeSlots = widget.tournament.events[_selectedEventIndex].timeSlots;
    _checkIfJoined();
    _checkIfUmpire();
    _loadParticipants();
    _loadMatches();
    _listenToTournamentUpdates();
  }

  void _listenToTournamentUpdates() {
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
              final updatedTournament = Tournament.fromFirestore(data, widget.tournament.id);
              final participants = updatedTournament.events[_selectedEventIndex].participants;
              final updatedParticipants = await _loadParticipantNames(participants);
              if (mounted) {
                setState(() {
                  _participants = updatedParticipants;
                  _tournamentProfileImage = data['profileImage']?.toString();
                  _sponsorImage = data['sponsorImage']?.toString();
                  _numberOfCourts = updatedTournament.events[_selectedEventIndex].numberOfCourts;
                  _timeSlots = updatedTournament.events[_selectedEventIndex].timeSlots;
                });
                await _loadMatches();
                await _generateLeaderboardData();
              }
            } catch (e) {
              debugPrint('Error processing tournament updates: $e');
              toastification.show(
                context: context,
                type: ToastificationType.error,
                title: const Text('Update Error'),
                description: Text('Failed to process tournament data: $e'),
                autoCloseDuration: const Duration(seconds: 2),
              );
            }
          },
          onError: (e) {
            debugPrint('Error in tournament updates: $e');
            toastification.show(
              context: context,
              type: ToastificationType.error,
              title: const Text('Update Error'),
              description: Text('Failed to update tournament data: $e'),
              autoCloseDuration: const Duration(seconds: 2),
            );
          },
        );
  }

  Future<List<Map<String, dynamic>>> _loadParticipantNames(List<String> participantIds) async {
    final updatedParticipants = <Map<String, dynamic>>[];
    for (var id in participantIds) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(id).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          updatedParticipants.add({
            'id': id,
            'name': '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim(),
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

  Future<void> _loadParticipants() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final participants = widget.tournament.events[_selectedEventIndex].participants;
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
      final selectedEvent = widget.tournament.events[_selectedEventIndex];
      final matchDocs = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .collection('matches')
          .where('eventId', isEqualTo: selectedEvent.name)
          .get();
      final matches = matchDocs.docs.map((doc) => {'matchId': doc.id, ...doc.data()}).toList();
      if (mounted) {
        setState(() {
          _matches = matches;
        });
      }
    } catch (e) {
      debugPrint('Error loading matches: $e');
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Load Matches Failed'),
        description: Text('Failed to load matches: $e'),
        autoCloseDuration: const Duration(seconds: 2),
      );
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
        _hasJoined = widget.tournament.events[_selectedEventIndex].participants.contains(userId);
      });
    }
  }

  void _checkIfUmpire() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userEmail = authState.user.email;
      if (userEmail != null) {
        final umpireDoc = await FirebaseFirestore.instance
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

  Future<void> _resetMatches() async {
    if (_isLoading || !_canGenerateMatches) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset All Matches?', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.bold)),
        content: Text('This will delete all current matches for the selected event. This action cannot be undone.', style: GoogleFonts.poppins(color: _secondaryText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: _secondaryText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Reset', style: GoogleFonts.poppins(color: _errorColor, fontWeight: FontWeight.w600)),
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
      for (var doc in matchDocs.docs) {
        await doc.reference.delete();
      }
      final updatedEvents = widget.tournament.events.asMap().entries.map((entry) {
        if (entry.key == _selectedEventIndex) {
          return Event(
            name: entry.value.name,
            format: entry.value.format,
            level: entry.value.level,
            maxParticipants: entry.value.maxParticipants,
            bornAfter: entry.value.bornAfter,
            matchType: entry.value.matchType,
            matches: [],
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
          .update({'events': updatedEvents.map((e) => e.toFirestore()).toList()});

      if (mounted) {
        setState(() {
          _matches = [];
        });
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Matches Reset'),
          description: const Text('All matches have been successfully reset.'),
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
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('tournament_images/${widget.tournament.id}.jpg');
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
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('sponsor_images/${widget.tournament.id}.jpg');
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
      builder: (_) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Image Options', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.visibility, color: _accentColor),
              title: Text('View Tournament Image', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _showFullImageDialog(_tournamentProfileImage, 'Tournament Image');
              },
            ),
            if (isCreator)
              ListTile(
                leading: Icon(Icons.edit, color: _accentColor),
                title: Text('Edit Tournament Image', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  _uploadTournamentImage();
                },
              ),
            if (_sponsorImage != null && _sponsorImage!.isNotEmpty)
              ListTile(
                leading: Icon(Icons.visibility, color: _accentColor),
                title: Text('View Sponsor Image', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  _showFullImageDialog(_sponsorImage, 'Sponsor Image');
                },
              ),
            if (isCreator)
              ListTile(
                leading: Icon(Icons.edit, color: _accentColor),
                title: Text('Edit Sponsor Image', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w500)),
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
            child: Text('Cancel', style: GoogleFonts.poppins(color: _secondaryText)),
          ),
        ],
      ),
    );
  }

  void _showFullImageDialog(String? imageUrl, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(color: _textColor, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        'assets/tournament_placholder.jpg',
                        fit: BoxFit.contain,
                      ),
                    )
                  : Image.asset(
                      'assets/tournament_placholder.jpg',
                      fit: BoxFit.contain,
                    ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
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
            final winnerId = winner == 'player1' ? match['player1Id'] : match['player2Id'];
            if (winnerId == competitorId) {
              score += 1;
            }
          }
        }
      }

      _leaderboardData[competitorId] = {
        'name': name,
        'score': score,
      };
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<Map<String, dynamic>> _getUserData(String userId) async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return userDoc.data() ?? {'firstName': 'Unknown', 'lastName': ''};
  }

  Future<String> _getDisplayName(String userId) async {
    if (userId == 'TBD' || userId == 'bye') return 'TBD';
    final userData = await _getUserData(userId);
    return '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
  }

  Future<void> _configureTournamentSettings() async {
  if (_isLoading) return;
  int tempCourts = _numberOfCourts;
  List<String> tempTimeSlots = List.from(_timeSlots);
  TextEditingController timeSlotController = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Configure Tournament',
          style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.bold),
        ),
        content: Container(
          // Constrain the dialog content width and height
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6, // Limit dialog height
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Number of Courts',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                DropdownButton<int>(
                  value: tempCourts,
                  isExpanded: true,
                  items: List.generate(10, (index) => index + 1).map((cnt) {
                    return DropdownMenuItem(
                      value: cnt,
                      child: Text('$cnt', style: GoogleFonts.poppins(color: _textColor)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setStateDialog(() {
                      tempCourts = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Time Slots',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Constrain ListView.builder height
                SizedBox(
                  height: 150, // Fixed height for the ListView
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tempTimeSlots.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(
                          tempTimeSlots[index],
                          style: GoogleFonts.poppins(color: _textColor),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: _errorColor),
                          onPressed: () {
                            setStateDialog(() {
                              tempTimeSlots.removeAt(index);
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: timeSlotController,
                  decoration: InputDecoration(
                    labelText: 'Add Time Slot (e.g., 09:00-10:00)',
                   
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (timeSlotController.text.isNotEmpty) {
                      setStateDialog(() {
                        tempTimeSlots.add(timeSlotController.text);
                        timeSlotController.clear();
                      });
                    }
                  },
                  child: Text(
                    'Add Time Slot',
                    style: GoogleFonts.poppins(color: _successColor),
                  ),
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
              style: GoogleFonts.poppins(color: _secondaryText),
            ),
          ),
          TextButton(
            onPressed: () async {
              setState(() {
                _isLoading = true;
              });
              try {
                final updatedEvents = widget.tournament.events.asMap().entries.map((entry) {
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
                      numberOfCourts: tempCourts,
                      timeSlots: tempTimeSlots,
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
                    _numberOfCourts = tempCourts;
                    _timeSlots = tempTimeSlots;
                  });
                  toastification.show(
                    context: context,
                    type: ToastificationType.success,
                    title: const Text('Settings Updated'),
                    description: const Text('Tournament settings updated successfully!'),
                    autoCloseDuration: const Duration(seconds: 2),
                  );
                }
                Navigator.pop(context);
              } catch (e) {
                if (mounted) {
                  toastification.show(
                    context: context,
                    type: ToastificationType.error,
                    title: const Text('Update Failed'),
                    description: Text('Failed to update settings: $e'),
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
            },
            child: Text(
              'Save',
              style: GoogleFonts.poppins(
                color: _successColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

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
        throw 'Need at least 2 ${isDoubles ? 'teams' : 'participants'} to schedule matches.';
      }

      List<Map<String, dynamic>> teams = [];
      if (isDoubles) {
        final shuffledParticipants = List<Map<String, dynamic>>.from(competitors)..shuffle();
        for (int i = 0; i < shuffledParticipants.length - 1; i += 2) {
          final player1 = shuffledParticipants[i];
          final player2 = shuffledParticipants[i + 1];
          teams.add({
            'teamId': 'team_${teams.length + 1}',
            'playerIds': [player1['id'], player2['id']],
            'playerNames': [
              player1['name'] ?? await _getDisplayName(player1['id']),
              player2['name'] ?? await _getDisplayName(player2['id']),
            ],
          });
        }
      }

      final competitorsList = isDoubles ? teams : competitors;
      final newMatches = <Map<String, dynamic>>[];
      DateTime matchStartDate = widget.tournament.startDate;
      final startHour = widget.tournament.startDate.hour;
      final startMinute = widget.tournament.startDate.minute;

      // Assign courts and time slots
      final availableCourts = List.generate(selectedEvent.numberOfCourts, (index) => index + 1);
      final availableTimeSlots = List<String>.from(selectedEvent.timeSlots);

      switch (selectedEvent.format.toLowerCase()) {
        case 'knockout':
          final shuffledCompetitors = List<Map<String, dynamic>>.from(competitorsList)..shuffle();
          List<Map<String, dynamic>> currentRoundParticipants = shuffledCompetitors;
          int round = 1;
          int matchIndex = 0;

          while (currentRoundParticipants.length > 1) {
            final nextRoundParticipants = <Map<String, dynamic>>[];
            for (int i = 0; i < currentRoundParticipants.length - 1; i += 2) {
              final competitor1 = currentRoundParticipants[i];
              final competitor2 = currentRoundParticipants[i + 1];
              final matchId = '${selectedEvent.name}_match_${competitor1[isDoubles ? 'teamId' : 'id']}_vs_${competitor2[isDoubles ? 'teamId' : 'id']}_r$round';
              final court = availableCourts[matchIndex % availableCourts.length];
              final timeSlot = availableTimeSlots.isNotEmpty ? availableTimeSlots[matchIndex % availableTimeSlots.length] : 'TBD';

              final matchData = isDoubles
                  ? {
                      'matchId': matchId,
                      'eventId': selectedEvent.name,
                      'matchType': selectedEvent.matchType,
                      'round': round,
                      'team1': competitor1['playerNames'],
                      'team2': competitor2['playerNames'],
                      'team1Ids': competitor1['playerIds'],
                      'team2Ids': competitor2['playerIds'],
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
                      'startTime': Timestamp.fromDate(
                        DateTime(
                          matchStartDate.year,
                          matchStartDate.month,
                          matchStartDate.day + (matchIndex ~/ availableCourts.length),
                          startHour,
                          startMinute,
                        ),
                      ),
                      'court': court,
                      'timeSlot': timeSlot,
                    }
                  : {
                      'matchId': matchId,
                      'eventId': selectedEvent.name,
                      'matchType': selectedEvent.matchType,
                      'round': round,
                      'player1': competitor1['name'] ?? await _getDisplayName(competitor1['id']),
                      'player2': competitor2['name'] ?? await _getDisplayName(competitor2['id']),
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
                      'startTime': Timestamp.fromDate(
                        DateTime(
                          matchStartDate.year,
                          matchStartDate.month,
                          matchStartDate.day + (matchIndex ~/ availableCourts.length),
                          startHour,
                          startMinute,
                        ),
                      ),
                      'court': court,
                      'timeSlot': timeSlot,
                    };

              newMatches.add(matchData);
              await FirebaseFirestore.instance
                  .collection('tournaments')
                  .doc(widget.tournament.id)
                  .collection('matches')
                  .doc(matchId)
                  .set(matchData);
              matchIndex++;
              nextRoundParticipants.add({
                'id': 'TBD',
                'winnerMatchId': matchId,
              });
            }

            if (currentRoundParticipants.length % 2 != 0) {
              final byeCompetitor = currentRoundParticipants.last;
              final byeMatchId = '${selectedEvent.name}_match_${isDoubles ? byeCompetitor['teamId'] : byeCompetitor['id']}_bye_r$round';
              final court = availableCourts[matchIndex % availableCourts.length];
              final timeSlot = availableTimeSlots.isNotEmpty ? availableTimeSlots[matchIndex % availableTimeSlots.length] : 'TBD';
              final byeMatchData = isDoubles
                  ? {
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
                      'startTime': Timestamp.fromDate(
                        DateTime(
                          matchStartDate.year,
                          matchStartDate.month,
                          matchStartDate.day + (matchIndex ~/ availableCourts.length),
                          startHour,
                          startMinute,
                        ),
                      ),
                      'court': court,
                      'timeSlot': timeSlot,
                    }
                  : {
                      'matchId': byeMatchId,
                      'eventId': selectedEvent.name,
                      'matchType': selectedEvent.matchType,
                      'round': round,
                      'player1': byeCompetitor['name'] ?? await _getDisplayName(byeCompetitor['id']),
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
                      'startTime': Timestamp.fromDate(
                        DateTime(
                          matchStartDate.year,
                          matchStartDate.month,
                          matchStartDate.day + (matchIndex ~/ availableCourts.length),
                          startHour,
                          startMinute,
                        ),
                      ),
                      'court': court,
                      'timeSlot': timeSlot,
                    };

              newMatches.add(byeMatchData);
              await FirebaseFirestore.instance
                  .collection('tournaments')
                  .doc(widget.tournament.id)
                  .collection('matches')
                  .doc(byeMatchId)
                  .set(byeMatchData);
              matchIndex++;
              nextRoundParticipants.add({
                'id': isDoubles ? byeCompetitor['teamId'] : byeCompetitor['id'],
                'winnerMatchId': byeMatchId,
              });
            }

            currentRoundParticipants = nextRoundParticipants;
            round++;
          }
          break;

        case 'round-robin':
          final n = competitorsList.length;
          final totalRounds = n - 1;
          final matchesPerRound = n ~/ 2;
          final rounds = List.generate(totalRounds, (_) => <Map<String, dynamic>>[]);

          List<Map<String, dynamic>> fixedCompetitors = List.from(competitorsList);
          if (n.isOdd) {
            fixedCompetitors.add({
              'id': 'bye',
              'teamId': 'bye',
              'playerNames': ['Bye'],
              'playerIds': ['bye'],
            });
          }

          for (var round = 0; round < totalRounds; round++) {
            for (var i = 0; i < matchesPerRound; i++) {
              final competitor1 = fixedCompetitors[i];
              final competitor2 = fixedCompetitors[fixedCompetitors.length - 1 - i];

              if ((isDoubles &&
                      (competitor1['teamId'] == 'bye' || competitor2['teamId'] == 'bye')) ||
                  (!isDoubles && (competitor1['id'] == 'bye' || competitor2['id'] == 'bye'))) {
                continue;
              }

              final matchId = '${selectedEvent.name}_match_${isDoubles ? competitor1['teamId'] : competitor1['id']}_vs_${isDoubles ? competitor2['teamId'] : competitor2['id']}_r${round + 1}';
              final court = availableCourts[i % availableCourts.length];
              final timeSlot = availableTimeSlots.isNotEmpty ? availableTimeSlots[i % availableTimeSlots.length] : 'TBD';

              final matchData = isDoubles
                  ? {
                      'matchId': matchId,
                      'eventId': selectedEvent.name,
                      'matchType': selectedEvent.matchType,
                      'round': round + 1,
                      'team1': competitor1['playerNames'],
                      'team2': competitor2['playerNames'],
                      'team1Ids': competitor1['playerIds'],
                      'team2Ids': competitor2['playerIds'],
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
                    }
                  : {
                      'matchId': matchId,
                      'eventId': selectedEvent.name,
                      'matchType': selectedEvent.matchType,
                      'round': round + 1,
                      'player1': competitor1['name'] ?? await _getDisplayName(competitor1['id']),
                      'player2': competitor2['name'] ?? await _getDisplayName(competitor2['id']),
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
                    };

              rounds[round].add(matchData);
            }

            final last = fixedCompetitors.last;
            for (var i = fixedCompetitors.length - 1; i > 1; i--) {
              fixedCompetitors[i] = fixedCompetitors[i - 1];
            }
            fixedCompetitors[1] = last;
          }

          final playerLastPlayDate = <String, DateTime>{};
          for (var round in rounds) {
            for (var match in round) {
              final competitor1Ids = isDoubles ? List<String>.from(match['team1Ids']) : [match['player1Id']];
              final competitor2Ids = isDoubles ? List<String>.from(match['team2Ids']) : [match['player2Id']];
              final allPlayerIds = [...competitor1Ids, ...competitor2Ids];

              DateTime candidateDate = matchStartDate;
              bool conflict;
              do {
                conflict = false;
                for (var playerId in allPlayerIds) {
                  final lastPlayDate = playerLastPlayDate[playerId];
                  if (lastPlayDate != null && candidateDate.difference(lastPlayDate).inDays.abs() < 1) {
                    conflict = true;
                    candidateDate = candidateDate.add(const Duration(days: 1));
                    break;
                  }
                }
              } while (conflict);

              match['startTime'] = Timestamp.fromDate(
                DateTime(candidateDate.year, candidateDate.month, candidateDate.day, startHour, startMinute),
              );

              for (var playerId in allPlayerIds) {
                playerLastPlayDate[playerId] = candidateDate;
              }

              newMatches.add(match);
              await FirebaseFirestore.instance
                  .collection('tournaments')
                  .doc(widget.tournament.id)
                  .collection('matches')
                  .doc(match['matchId'])
                  .set(match);
              matchStartDate = candidateDate.add(const Duration(days: 1));
            }
          }
          break;

        default:
          throw 'Unsupported tournament format: ${selectedEvent.format}';
      }

      final updatedEvents = widget.tournament.events.asMap().entries.map((entry) {
        if (entry.key == _selectedEventIndex) {
          return Event(
            name: entry.value.name,
            format: entry.value.format,
            level: entry.value.level,
            maxParticipants: entry.value.maxParticipants,
            bornAfter: entry.value.bornAfter,
            matchType: entry.value.matchType,
            matches: newMatches.map((m) => m['matchId'] as String).toList(),
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
          .update({'events': updatedEvents.map((e) => e.toFirestore()).toList()});

      if (mounted) {
        setState(() {
          _matches = newMatches;
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Matches Scheduled'),
          description: const Text('Match schedule has been successfully generated!'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to generate matches: $e'),
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

  Future<void> _createManualMatch(
      Map<String, dynamic> competitor1, Map<String, dynamic> competitor2, DateTime matchDateTime, int court, String timeSlot) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final selectedEvent = widget.tournament.events[_selectedEventIndex];
      final isDoubles = selectedEvent.matchType.toLowerCase().contains('doubles');
      String matchId;
      Map<String, dynamic> newMatch;

      if (isDoubles) {
        final team1Ids = competitor1['playerIds'] as List<String>;
        final team2Ids = competitor2['playerIds'] as List<String>;
        matchId = '${selectedEvent.name}_match_${team1Ids.join('_')}_vs_${team2Ids.join('_')}';
        newMatch = {
          'matchId': matchId,
          'eventId': selectedEvent.name,
          'matchType': selectedEvent.matchType,
          'round': _matches.isNotEmpty ? (_matches.last['round'] ?? 1) : 1,
          'team1': competitor1['playerNames'],
          'team2': competitor2['playerNames'],
          'team1Ids': team1Ids,
          'team2Ids': team2Ids,
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
          'startTime': Timestamp.fromDate(matchDateTime),
          'court': court,
          'timeSlot': timeSlot,
        };
      } else {
        matchId = '${selectedEvent.name}_match_${competitor1['id']}_vs_${competitor2['id']}';
        newMatch = {
          'matchId': matchId,
          'eventId': selectedEvent.name,
          'matchType': selectedEvent.matchType,
          'round': _matches.isNotEmpty ? (_matches.last['round'] ?? 1) : 1,
          'player1': competitor1['name'] ?? await _getDisplayName(competitor1['id']),
          'player2': competitor2['name'] ?? await _getDisplayName(competitor2['id']),
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
          'startTime': Timestamp.fromDate(matchDateTime),
          'court': court,
          'timeSlot': timeSlot,
        };
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .collection('matches')
          .doc(matchId)
          .set(newMatch);

      final updatedEvents = widget.tournament.events.asMap().entries.map((entry) {
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
          .update({'events': updatedEvents.map((e) => e.toFirestore()).toList()});

      if (mounted) {
        setState(() {
          _matches.add(newMatch);
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Match Created'),
          description: const Text('Manual match has been successfully created!'),
          autoCloseDuration: const Duration(seconds: 2),
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

  void _showManualMatchDialog(bool isCreator) {
    if (!isCreator || !_canGenerateMatches) return;
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final isDoubles = selectedEvent.matchType.toLowerCase().contains('doubles');
    final competitors = List<Map<String, dynamic>>.from(_participants);

    if (competitors.length < 2) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Insufficient Competitors'),
        description: const Text('At least two players are required to create a match.'),
        autoCloseDuration: const Duration(seconds: 2),
      );
      return;
    }

    List<Map<String, dynamic>> teams = [];
    if (isDoubles) {
      final shuffledParticipants = List<Map<String, dynamic>>.from(competitors)..shuffle();
      for (int i = 0; i < shuffledParticipants.length - 1; i += 2) {
        final player1 = shuffledParticipants[i];
        final player2 = shuffledParticipants[i + 1];
        teams.add({
          'teamId': 'team_${teams.length + 1}',
          'playerIds': [player1['id'], player2['id']],
          'playerNames': [
            player1['name'] ?? 'Unknown',
            player2['name'] ?? 'Unknown',
          ],
        });
      }
    }

    dynamic selectedCompetitor1;
    dynamic selectedCompetitor2;
    DateTime selectedDate = widget.tournament.startDate;
    TimeOfDay selectedTime = TimeOfDay(
      hour: widget.tournament.startDate.hour,
      minute: widget.tournament.startDate.minute,
    );
    int selectedCourt = 1;
    String selectedTimeSlot = selectedEvent.timeSlots.isNotEmpty ? selectedEvent.timeSlots[0] : 'TBD';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: _cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Create Manual Match', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85, minWidth: 200.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Event: ${selectedEvent.name} (${selectedEvent.matchType})',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: _accentColor)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<dynamic>(
                    decoration: InputDecoration(
                      labelText: isDoubles ? 'Select Team 1' : 'Select Player 1',
                      labelStyle: GoogleFonts.poppins(color: _textColor.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor.withOpacity(0.5))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor, width: 2)),
                      filled: true,
                      fillColor: _cardBackground.withOpacity(0.9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    dropdownColor: _cardBackground,
                    isExpanded: true,
                    items: (isDoubles ? teams : competitors).map((competitor) {
                      return DropdownMenuItem(
                        value: competitor,
                        child: Text(
                          isDoubles ? competitor['playerNames'].join(' & ') : competitor['name'] ?? competitor['id'],
                          style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedCompetitor1 = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<dynamic>(
                    decoration: InputDecoration(
                      labelText: isDoubles ? 'Select Team 2' : 'Select Player 2',
                      labelStyle: GoogleFonts.poppins(color: _textColor.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor.withOpacity(0.5))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor, width: 2)),
                      filled: true,
                      fillColor: _cardBackground.withOpacity(0.9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    dropdownColor: _cardBackground,
                    isExpanded: true,
                    items: (isDoubles ? teams : competitors).map((competitor) {
                      return DropdownMenuItem(
                        value: competitor,
                        child: Text(
                          isDoubles ? competitor['playerNames'].join(' & ') : competitor['name'] ?? competitor['id'],
                          style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedCompetitor2 = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text('Match Date: ${DateFormat('MMM dd, yyyy').format(selectedDate)}',
                        style: GoogleFonts.poppins(color: _textColor)),
                    trailing: Icon(Icons.calendar_today, color: _accentColor),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: widget.tournament.startDate,
                        lastDate: widget.tournament.endDate,
                      );
                      if (pickedDate != null) {
                        setStateDialog(() {
                          selectedDate = pickedDate;
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: Text('Match Time: ${selectedTime.format(context)}', style: GoogleFonts.poppins(color: _textColor)),
                    trailing: Icon(Icons.access_time, color: _accentColor),
                    onTap: () async {
                      final pickedTime = await showTimePicker(context: context, initialTime: selectedTime);
                      if (pickedTime != null) {
                        setStateDialog(() {
                          selectedTime = pickedTime;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: 'Select Court',
                      labelStyle: GoogleFonts.poppins(color: _textColor.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor.withOpacity(0.5))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor, width: 2)),
                      filled: true,
                      fillColor: _cardBackground.withOpacity(0.9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    dropdownColor: _cardBackground,
                    isExpanded: true,
                    value: selectedCourt,
                    items: List.generate(selectedEvent.numberOfCourts, (index) => index + 1).map((court) {
                      return DropdownMenuItem(
                        value: court,
                        child: Text('Court $court', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w500)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedCourt = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Select Time Slot',
                      labelStyle: GoogleFonts.poppins(color: _textColor.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor.withOpacity(0.5))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _accentColor, width: 2)),
                      filled: true,
                      fillColor: _cardBackground.withOpacity(0.9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    dropdownColor: _cardBackground,
                    isExpanded: true,
                    value: selectedTimeSlot,
                    items: selectedEvent.timeSlots.map((slot) {
                      return DropdownMenuItem(
                        value: slot,
                        child: Text(slot, style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.w500)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedTimeSlot = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.poppins(color: _secondaryText)),
            ),
            TextButton(
              onPressed: () {
                if (selectedCompetitor1 == null || selectedCompetitor2 == null) {
                  toastification.show(
                    context: context,
                    type: ToastificationType.error,
                    title: const Text('Selection Required'),
                    description: const Text('Please select both competitors.'),
                    autoCloseDuration: const Duration(seconds: 2),
                  );
                  return;
                }
                if (selectedCompetitor1 == selectedCompetitor2) {
                  toastification.show(
                    context: context,
                    type: ToastificationType.error,
                    title: const Text('Invalid Selection'),
                    description: const Text('Cannot create a match with the same competitor.'),
                    autoCloseDuration: const Duration(seconds: 2),
                  );
                  return;
                }
                Navigator.pop(context);
                final matchDateTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
                _createManualMatch(selectedCompetitor1, selectedCompetitor2, matchDateTime, selectedCourt, selectedTimeSlot);
              },
              child: Text('Create', style: GoogleFonts.poppins(color: _successColor, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
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

      final updatedEvents = widget.tournament.events.asMap().entries.map((entry) {
        if (entry.key == _selectedEventIndex) {
          final updatedMatches = List<String>.from(entry.value.matches)..remove(match['matchId']);
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
          .update({'events': updatedEvents.map((e) => e.toFirestore()).toList()});

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
      builder: (_) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm Delete', style: GoogleFonts.poppins(color: _textColor, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this match?', style: GoogleFonts.poppins(color: _secondaryText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: _secondaryText)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMatch(matchIndex);
            },
            child: Text('Delete', style: GoogleFonts.poppins(color: _errorColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
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
        autoCloseDuration: const Duration(seconds: 2),
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
        description: const Text('As the tournament creator, you cannot join as a participant.'),
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

    setState(() {
      _isLoading = true;
    });

    try {
      final selectedEvent = widget.tournament.events[_selectedEventIndex];
      if (selectedEvent.participants.length >= selectedEvent.maxParticipants) {
        throw 'This event has reached its maximum participants.';
      }

      final updatedEvents = widget.tournament.events.asMap().entries.map((entry) {
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
          .update({'events': updatedEvents.map((e) => e.toFirestore()).toList()});

      if (mounted) {
        setState(() {
          _participants.add({
            'id': userId,
            'name': null,
          });
          _hasJoined = true;
        });
        await _loadParticipants();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Joined Event'),
          description: Text('Successfully joined ${selectedEvent.name}!'),
          autoCloseDuration: const Duration(seconds: 2),
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

  Future<void> _withdrawFromTournament(BuildContext context) async {
    if (_isLoading) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final userId = authState.user.uid;

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedEvents = widget.tournament.events.asMap().entries.map((entry) {
        if (entry.key == _selectedEventIndex) {
          return Event(
            name: entry.value.name,
            format: entry.value.format,
            level: entry.value.level,
            maxParticipants: entry.value.maxParticipants,
            bornAfter: entry.value.bornAfter,
            matchType: entry.value.matchType,
            matches: entry.value.matches,
            participants: entry.value.participants.where((id) => id != userId).toList(),
            numberOfCourts: entry.value.numberOfCourts,
            timeSlots: entry.value.timeSlots,
          );
        }
        return entry.value;
      }).toList();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({'events': updatedEvents.map((e) => e.toFirestore()).toList()});

      if (mounted) {
        setState(() {
          _participants = _participants.where((p) => p['id'] != userId).toList();
          _hasJoined = false;
        });
        await _generateLeaderboardData();
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Withdrawn'),
          description: Text('You have successfully withdrawn from ${widget.tournament.events[_selectedEventIndex].name}.'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Withdrawal Failed'),
          description: Text('Failed to withdraw from event: $e'),
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

  DateTime get _withdrawDeadline {
    return widget.tournament.startDate.subtract(const Duration(days: 3));
  }

  bool get _canWithdraw {
    final now = DateTime.now().toUtc();
    return now.isBefore(_withdrawDeadline);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final isClosed = widget.tournament.endDate.isBefore(now);
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.uid : null;

    final isCreator = userId != null && widget.tournament.createdBy == userId;

    return Scaffold(
      backgroundColor: _secondaryColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        title: Text(
          widget.tournament.name,
          style: GoogleFonts.poppins(
            color: _cardBackground,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          if (isCreator)
            IconButton(
              icon: Icon(Icons.settings, color: _cardBackground),
              onPressed: _configureTournamentSettings,
            ),
        ],
      ),
      body: Column(
        children: [
          // Event Selection Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _cardBackground,
            child: DropdownButtonFormField<int>(
              decoration: InputDecoration(
                labelText: 'Select Event',
                labelStyle: GoogleFonts.poppins(color: _textColor.withOpacity(0.7)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _accentColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _accentColor.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _accentColor, width: 2),
                ),
              ),
              value: _selectedEventIndex,
              items: widget.tournament.events.asMap().entries.map((entry) {
                return DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    entry.value.name,
                    style: GoogleFonts.poppins(color: _textColor),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedEventIndex = value!;
                  _participants = widget.tournament.events[_selectedEventIndex].participants
                      .map((id) => {'id': id, 'name': null})
                      .toList();
                  _numberOfCourts = widget.tournament.events[_selectedEventIndex].numberOfCourts;
                  _timeSlots = widget.tournament.events[_selectedEventIndex].timeSlots;
                  _matches = [];
                  _hasJoined = false;
                  _checkIfJoined();
                  _loadParticipants();
                  _loadMatches();
                });
              },
            ),
          ),
          // Tab Bar
          Container(
            color: _primaryColor,
            child: TabBar(
              controller: _tabController,
              labelColor: _cardBackground,
              unselectedLabelColor: _cardBackground.withOpacity(0.6),
              indicatorColor: _accentColor,
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Participants'),
                Tab(text: 'Matches'),
                Tab(text: 'Leaderboard'),
                Tab(text: 'Rules'),
              ],
            ),
          ),
          // Tab Bar View
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Overview Tab
                AnimationLimiter(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: AnimationConfiguration.toStaggeredList(
                        duration: const Duration(milliseconds: 375),
                        childAnimationBuilder: (widget) => SlideAnimation(
                          verticalOffset: 50.0,
                          child: FadeInAnimation(child: widget),
                        ),
                        children: [
                          GestureDetector(
                            onTap: () => _showImageOptionsDialog(isCreator),
                            child: Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: _tournamentProfileImage != null && _tournamentProfileImage!.isNotEmpty
                                      ? NetworkImage(_tournamentProfileImage!)
                                      : const AssetImage('assets/tournament_placholder.jpg') as ImageProvider,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: CircleAvatar(
                                    backgroundColor: _accentColor,
                                    child: Icon(
                                      isCreator ? Icons.edit : Icons.visibility,
                                      color: _cardBackground,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.tournament.name,
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.tournament.description ?? 'No description available.',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: _secondaryText,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow(Icons.location_on, 'Venue', '${widget.tournament.venue}, ${widget.tournament.city}'),
                          _buildInfoRow(Icons.calendar_today, 'Date',
                              '${DateFormat('MMM dd, yyyy').format(widget.tournament.startDate)} - ${DateFormat('MMM dd, yyyy').format(widget.tournament.endDate)}'),
                          _buildInfoRow(Icons.access_time, 'Registration Ends',
                              DateFormat('MMM dd, yyyy').format(widget.tournament.registrationEnd)),
                          _buildInfoRow(Icons.monetization_on, 'Entry Fee',
                              '\$${widget.tournament.entryFee}${widget.tournament.extraFee != null ? ' + \$${widget.tournament.extraFee} (extra)' : ''}'),
                          _buildInfoRow(Icons.payment, 'Payment at Venue',
                              widget.tournament.canPayAtVenue ? 'Yes' : 'No'),
                          _buildInfoRow(Icons.person, 'Created By', widget.creatorName),
                          if (widget.tournament.contactName != null || widget.tournament.contactNumber != null)
                            _buildInfoRow(Icons.contact_phone, 'Contact',
                                '${widget.tournament.contactName ?? ''} ${widget.tournament.contactNumber ?? ''}'.trim()),
                          const SizedBox(height: 16),
                          if (_sponsorImage != null && _sponsorImage!.isNotEmpty)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sponsor',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: _textColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => _showFullImageDialog(_sponsorImage, 'Sponsor Image'),
                                  child: Container(
                                    height: 100,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(
                                        image: NetworkImage(_sponsorImage!),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!isClosed && !isCreator)
                                ElevatedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () => _hasJoined
                                          ? _canWithdraw
                                              ? _withdrawFromTournament(context)
                                              : toastification.show(
                                                  context: context,
                                                  type: ToastificationType.warning,
                                                  title: const Text('Withdrawal Closed'),
                                                  description: const Text('You can no longer withdraw from this event.'),
                                                  autoCloseDuration: const Duration(seconds: 2),
                                                )
                                          : _joinTournament(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _hasJoined ? _errorColor : _successColor,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _hasJoined ? 'Withdraw' : 'Join Event',
                                          style: GoogleFonts.poppins(
                                            color: _cardBackground,
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
                // Participants Tab
                AnimationLimiter(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
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
                                  child: Card(
                                    color: _cardBackground,
                                    elevation: 2,
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _accentColor,
                                        child: Text(
                                          participant['name']?.substring(0, 1).toUpperCase() ?? 'U',
                                          style: GoogleFonts.poppins(
                                            color: _cardBackground,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        participant['name'] ?? 'Loading...',
                                        style: GoogleFonts.poppins(
                                          color: _textColor,
                                          fontWeight: FontWeight.w600,
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
                // Matches Tab
                AnimationLimiter(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            if (isCreator && _canGenerateMatches)
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    ElevatedButton(
                                      onPressed: _generateMatches,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _successColor,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: Text(
                                        'Generate Matches',
                                        style: GoogleFonts.poppins(
                                          color: _cardBackground,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => _showManualMatchDialog(isCreator),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _accentColor,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: Text(
                                        'Add Manual Match',
                                        style: GoogleFonts.poppins(
                                          color: _cardBackground,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (_matches.isNotEmpty)
                                      ElevatedButton(
                                        onPressed: _resetMatches,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _errorColor,
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: Text(
                                          'Reset Matches',
                                          style: GoogleFonts.poppins(
                                            color: _cardBackground,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _matches.length,
                                itemBuilder: (context, index) {
                                  final match = _matches[index];
                                  final isDoubles = widget.tournament.events[_selectedEventIndex].matchType
                                      .toLowerCase()
                                      .contains('doubles');
                                  final competitor1 = isDoubles
                                      ? (match['team1'] as List<dynamic>).join(' & ')
                                      : match['player1'] ?? 'TBD';
                                  final competitor2 = isDoubles
                                      ? (match['team2'] as List<dynamic>).join(' & ')
                                      : match['player2'] ?? 'TBD';
                                  final startTime = (match['startTime'] as Timestamp?)?.toDate();
                                  final timeSlot = match['timeSlot'] ?? 'TBD';
                                  final court = match['court']?.toString() ?? 'TBD';
                                  final isParticipant = isDoubles
                                      ? (match['team1Ids']?.contains(userId) ?? false) ||
                                          (match['team2Ids']?.contains(userId) ?? false)
                                      : match['player1Id'] == userId || match['player2Id'] == userId;

                                  return AnimationConfiguration.staggeredList(
                                    position: index,
                                    duration: const Duration(milliseconds: 375),
                                    child: SlideAnimation(
                                      verticalOffset: 50.0,
                                      child: FadeInAnimation(
                                        child: Card(
                                          color: _cardBackground,
                                          elevation: 2,
                                          margin: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: ListTile(
                                            title: Text(
                                              '$competitor1 vs $competitor2',
                                              style: GoogleFonts.poppins(
                                                color: _textColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Text(
                                              'Round ${match['round'] ?? 'N/A'} | Court $court | $timeSlot${startTime != null ? ' | ${DateFormat('MMM dd, yyyy HH:mm').format(startTime)}' : ''}',
                                              style: GoogleFonts.poppins(color: _secondaryText),
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (match['completed'] == true)
                                                  Icon(
                                                    Icons.check_circle,
                                                    color: _successColor,
                                                  ),
                                                if (isCreator || _isUmpire || isParticipant)
                                                  IconButton(
                                                    icon: Icon(Icons.score, color: _accentColor),
                                                    onPressed: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) => MatchDetailsPage(
                                                            match: match,
                                  tournamentId: widget.tournament.id,
                                  isCreator: isCreator,
                                  isUmpire: _isUmpire,
                                  isDoubles: isDoubles,
                                  matchIndex: index, // Pass the matchIndex
                                  onDeleteMatch: () => _deleteMatch(index),
                                                          ),
                                                        ),
                                                      ).then((_) {
                                                        _loadMatches();
                                                        _generateLeaderboardData();
                                                      });
                                                    },
                                                  ),
                                                if (isCreator)
                                                  IconButton(
                                                    icon: Icon(Icons.delete, color: _errorColor),
                                                    onPressed: () => _showDeleteConfirmation(context, index),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                ),
                // Leaderboard Tab
                AnimationLimiter(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _leaderboardData.length,
                          itemBuilder: (context, index) {
                            final entry = _leaderboardData.entries.toList()[index];
                            final name = entry.value['name'] as String;
                            final score = entry.value['score'] as int;
                            final rank = index + 1;

                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: SlideAnimation(
                                verticalOffset: 50.0,
                                child: FadeInAnimation(
                                  child: Card(
                                    color: _cardBackground,
                                    elevation: 2,
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: rank == 1
                                            ? _goldColor
                                            : rank == 2
                                                ? _silverColor
                                                : rank == 3
                                                    ? _bronzeColor
                                                    : _accentColor,
                                        child: Text(
                                          '$rank',
                                          style: GoogleFonts.poppins(
                                            color: _cardBackground,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        name,
                                        style: GoogleFonts.poppins(
                                          color: _textColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      trailing: Text(
                                        'Wins: $score',
                                        style: GoogleFonts.poppins(
                                          color: _accentColor,
                                          fontWeight: FontWeight.w600,
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
                // Rules Tab
                AnimationLimiter(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: AnimationConfiguration.toStaggeredList(
                        duration: const Duration(milliseconds: 375),
                        childAnimationBuilder: (widget) => SlideAnimation(
                          verticalOffset: 50.0,
                          child: FadeInAnimation(child: widget),
                        ),
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
                            widget.tournament.rules ?? 'No specific rules provided.',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: _secondaryText,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Game Format: ${widget.tournament.gameFormat}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: _textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Game Type: ${widget.tournament.gameType}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: _textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Bring Own Equipment: ${widget.tournament.bringOwnEquipment ? 'Yes' : 'No'}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: _textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Cost Shared: ${widget.tournament.costShared ? 'Yes' : 'No'}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: _textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: _accentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: _secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
