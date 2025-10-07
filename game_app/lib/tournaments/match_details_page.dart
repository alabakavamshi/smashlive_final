import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class MatchDetailsPage extends StatefulWidget {
  final String tournamentId;
  final Map<String, dynamic> match;
  final int matchIndex;
  final bool isCreator;
  final bool isDoubles;
  final bool isUmpire;
  final VoidCallback onDeleteMatch;

  const MatchDetailsPage({
    super.key,
    required this.tournamentId,
    required this.match,
    required this.matchIndex,
    required this.isCreator,
    required this.isDoubles,
    required this.isUmpire,
    required this.onDeleteMatch,
  });

  @override
  State<MatchDetailsPage> createState() => _MatchDetailsPageState();
}

class _MatchDetailsPageState extends State<MatchDetailsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late Map<String, dynamic> _match;
  final _umpireNameController = TextEditingController();
  final _umpireEmailController = TextEditingController();
  final _umpirePhoneController = TextEditingController();
  late String _initialUmpireName;
  late String _initialUmpireEmail;
  late String _initialUmpirePhone;
  String? _currentServer;
  String? _lastServer;
  int? _lastTeam1Score;
  int? _lastTeam2Score;
  bool _showPlusOneTeam1 = false;
  bool _showPlusOneTeam2 = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _debounceTimer;
  Timer? _countdownTimer;
  String? _countdown;
  Timestamp? _matchStartTime;
  tz.Location? _timezoneLocation;
  bool _isTimezoneInitialized = false;
  List<String> _timeSlots = [];
  int _numberOfCourts = 1;

@override
void initState() {
  super.initState();
  tz.initializeTimeZones();
  _match = Map.from(widget.match);
  _umpireNameController.text = _match['umpire']?['name'] ?? '';
  _umpireEmailController.text = _match['umpire']?['email'] ?? '';
  _umpirePhoneController.text = _match['umpire']?['phone'] ?? '';
  _initialUmpireName = _umpireNameController.text;
  _initialUmpireEmail = _umpireEmailController.text;
  _initialUmpirePhone = _umpirePhoneController.text;
  _lastTeam1Score = _getCurrentScore(true);
  _lastTeam2Score = _getCurrentScore(false);
  print('Initial matchStartTime: $_matchStartTime');
  print('Match data: $_match');
  _matchStartTime = _match['startTime'] as Timestamp?;
  _listenToTournamentUpdates();
  _initializeTimezone().then((_) {
    _initializeServer();
    _listenToMatchUpdates();
    _loadTournamentSettings();
    _startCountdown(); 
  });
  
  _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
    CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
  );
  _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
    CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
  );
}

  @override
  void dispose() {
    _umpireNameController.dispose();
    _umpireEmailController.dispose();
    _umpirePhoneController.dispose();
    _animationController.dispose();
    _debounceTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // Add this method to your _MatchDetailsPageState class

void _listenToTournamentUpdates() {
  FirebaseFirestore.instance
      .collection('tournaments')
      .doc(widget.tournamentId)
      .snapshots()
      .listen((snapshot) {
    if (!mounted) return;
    if (!snapshot.exists || snapshot.data() == null) {
      debugPrint('Tournament document does not exist or is empty');
      return;
    }
    
    final data = snapshot.data()!;
    try {
      // Update time slots and courts from the latest tournament data
      if (data['events'] != null) {
        final events = List<Map<String, dynamic>>.from(data['events']);
        final eventName = _match['eventId'];
        
        // Find the current event and update settings
        for (var event in events) {
          if (event['name'] == eventName) {
            if (mounted) {
              setState(() {
                _timeSlots = List<String>.from(event['timeSlots'] ?? []);
                _numberOfCourts = event['numberOfCourts'] ?? 1;
              });
            }
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error processing tournament updates in MatchDetailsPage: $e');
    }
  }, onError: (e) {
    debugPrint('Error in tournament updates listener: $e');
  });
}



  Future<void> _loadTournamentSettings() async {
    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      
      final data = tournamentDoc.data();
      if (data != null && data['events'] != null) {
        final events = List<Map<String, dynamic>>.from(data['events']);
        final eventName = _match['eventId'];
        
        // Find the current event
        for (var event in events) {
          if (event['name'] == eventName) {
            setState(() {
              _timeSlots = List<String>.from(event['timeSlots'] ?? []);
              _numberOfCourts = event['numberOfCourts'] ?? 1;
            });
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading tournament settings: $e');
    }
  }

Future<void> _initializeTimezone() async {
  try {
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();

    final timezone = tournamentDoc.data()?['timezone'] as String? ?? 'UTC';

    setState(() {
      try {
        _timezoneLocation = tz.getLocation(timezone);
      } catch (e) {
        debugPrint('Invalid timezone: $timezone, defaulting to UTC');
        _timezoneLocation = tz.getLocation('UTC');
      }
      _isTimezoneInitialized = true;
    });
    
    return; // Return here to indicate completion
  } catch (e) {
    debugPrint('Error initializing timezone: $e');
    setState(() {
      _timezoneLocation = tz.getLocation('UTC');
      _isTimezoneInitialized = true;
    });
    return; // Return here to indicate completion
  }
}

DateTime _convertToTournamentTime(Timestamp timestamp) {
  if (_timezoneLocation == null) {
    return timestamp.toDate(); // Fallback
  }
  
  // Convert the stored timestamp to tournament timezone
  final storedTime = timestamp.toDate();
  
  // Create a new datetime in the tournament's timezone
  final tournamentTime = tz.TZDateTime(
    _timezoneLocation!,
    storedTime.year,
    storedTime.month,
    storedTime.day,
    storedTime.hour,
    storedTime.minute,
    storedTime.second,
  );
  
  return tournamentTime;
}


Future<void> _startCountdown() async {
  if (!_isTimezoneInitialized || _timezoneLocation == null) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer(
      const Duration(milliseconds: 100),
      _startCountdown,
    );
    return;
  }

  if (_match['liveScores']?['isLive'] == true || _match['completed'] == true) {
    setState(() => _countdown = null);
    _countdownTimer?.cancel();
    return;
  }

  if (_matchStartTime == null) {
    setState(() => _countdown = 'Not scheduled yet');
    _countdownTimer?.cancel();
    return;
  }

  // Get match time in tournament timezone
  final matchDateTime = _convertToTournamentTime(_matchStartTime!);
  
  // Get current time in tournament timezone
  final nowInTournament = tz.TZDateTime.now(_timezoneLocation!);
  
  final difference = matchDateTime.difference(nowInTournament);

  // Debug output
  print('Match DateTime (Tournament): $matchDateTime');
  print('Now (Tournament): $nowInTournament');
  print('Difference: $difference');

  if (difference.isNegative) {
    setState(() => _countdown = 'Match should have started');
    _countdownTimer?.cancel();
  } else {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final currentNowInTournament = tz.TZDateTime.now(_timezoneLocation!);
      final currentDifference = matchDateTime.difference(currentNowInTournament);

      if (currentDifference.isNegative) {
        setState(() => _countdown = 'Match should have started');
        timer.cancel();
      } else {
        setState(() {
          _countdown = _formatDuration(currentDifference);
        });
      }
    });
  }
}


String _formatDuration(Duration duration) {
  if (duration.inDays >= 1) {
    return '${duration.inDays}d ${duration.inHours % 24}h ${duration.inMinutes % 60}m';
  } else if (duration.inHours >= 1) {
    return '${duration.inHours}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s';
  } else if (duration.inMinutes >= 1) {
    return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
  } else {
    return '${duration.inSeconds}s';
  }
}


String _formatDateWithTimezone(DateTime date) {
  final timeSlot = _match['timeSlot']?.toString();
  final court = _match['court'] != null ? 'Court ${_match['court']}' : '';
  
  // Format the complete date with time
  String baseInfo = DateFormat('MMM dd, yyyy • HH:mm').format(date);
  
  List<String> additionalInfo = [];
  if (timeSlot != null && timeSlot.isNotEmpty) {
    additionalInfo.add('Slot: $timeSlot');
  }
  if (court.isNotEmpty) {
    additionalInfo.add(court);
  }
  
  if (additionalInfo.isNotEmpty) {
    return '$baseInfo • ${additionalInfo.join(' • ')}';
  }
  
  return baseInfo;
}


Future<void> _updateMatchStartTime() async {
  if (_isLoading ||
      _match['liveScores']?['isLive'] == true ||
      _match['completed'] == true ||
      !_isTimezoneInitialized) {
    return;
  }

  setState(() => _isLoading = true);

  try {
    // Get tournament dates
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();
    
    final data = tournamentDoc.data();
    if (data == null) {
      throw Exception('Tournament data not found');
    }

    // Get tournament time bounds
    final tournamentStartDate = (data['startDate'] as Timestamp).toDate();
    final tournamentEndDate = (data['endDate'] as Timestamp).toDate();
    
    // Use current match date if available, otherwise use tournament start date
    DateTime selectedDate = _matchStartTime != null 
        ? _matchStartTime!.toDate()
        : tournamentStartDate;

    // Get all matches to check for conflicts
    final matchesSnapshot = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .collection('matches')
        .where('eventId', isEqualTo: _match['eventId'])
        .get();

    // Create a map of occupied time slots and courts for each date
    final occupiedSlotsByDate = <String, Map<String, Set<int>>>{};
    
    for (var matchDoc in matchesSnapshot.docs) {
      final matchData = matchDoc.data();
      if (matchDoc.id != _match['matchId'] && // Skip current match
          matchData['startTime'] != null && 
          matchData['timeSlot'] != null && 
          matchData['court'] != null) {
        
        final matchDate = (matchData['startTime'] as Timestamp).toDate();
        final dateKey = DateFormat('yyyy-MM-dd').format(matchDate);
        final timeSlot = matchData['timeSlot'] as String;
        final court = matchData['court'] as int;
        
        if (!occupiedSlotsByDate.containsKey(dateKey)) {
          occupiedSlotsByDate[dateKey] = <String, Set<int>>{};
        }
        if (!occupiedSlotsByDate[dateKey]!.containsKey(timeSlot)) {
          occupiedSlotsByDate[dateKey]![timeSlot] = <int>{};
        }
        occupiedSlotsByDate[dateKey]![timeSlot]!.add(court);
      }
    }

    // Step 1: Date selection
    final newDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: tournamentStartDate,
      lastDate: tournamentEndDate,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6C9A8B),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (newDate == null) {
      setState(() => _isLoading = false);
      return;
    }

    selectedDate = newDate;
    final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);

    // Step 2: Time slot and court selection
    String? selectedTimeSlot;
    int? selectedCourt;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            'Select Time Slot & Court for ${DateFormat('MMM dd, yyyy').format(selectedDate)}',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF333333),
            ),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Time Slot Selection
                  Text(
                    'Available Time Slots:',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  if (_timeSlots.isEmpty)
                    Text(
                      'No time slots configured',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF757575),
                      ),
                    )
                  else
                    ..._timeSlots.map((slot) {
                      final occupiedCourts = occupiedSlotsByDate[dateKey]?[slot] ?? <int>{};
                      final isFullyOccupied = occupiedCourts.length >= _numberOfCourts;
                      final isSelected = selectedTimeSlot == slot;
                      
                      return Card(
                        color: isFullyOccupied 
                            ? Colors.grey[200]
                            : (isSelected ? const Color(0xFF6C9A8B).withOpacity(0.1) : Colors.white),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(
                            slot,
                            style: GoogleFonts.poppins(
                              color: isFullyOccupied ? Colors.grey[500] : const Color(0xFF333333),
                            ),
                          ),
                          trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF6C9A8B)) : null,
                          onTap: isFullyOccupied ? null : () {
                            setStateDialog(() {
                              selectedTimeSlot = slot;
                              selectedCourt = null; // Reset court selection when time slot changes
                            });
                          },
                          subtitle: isFullyOccupied 
                              ? const Text('Fully booked', style: TextStyle(color: Colors.red))
                              : Text('${_numberOfCourts - occupiedCourts.length} courts available'),
                        ),
                      );
                    }),
                  
                  const SizedBox(height: 16),
                  
                  // Court Selection
                  if (selectedTimeSlot != null) ...[
                    Text(
                      'Available Courts for $selectedTimeSlot:',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_numberOfCourts, (index) {
                        final court = index + 1;
                        final isOccupied = occupiedSlotsByDate[dateKey]?[selectedTimeSlot]?.contains(court) ?? false;
                        final isSelected = selectedCourt == court;
                        
                        return FilterChip(
                          label: Text('Court $court'),
                          selected: isSelected,
                          onSelected: isOccupied ? null : (selected) {
                            setStateDialog(() {
                              selectedCourt = selected ? court : null;
                            });
                          },
                          selectedColor: const Color(0xFF6C9A8B),
                          checkmarkColor: Colors.white,
                          backgroundColor: isOccupied 
                              ? Colors.grey[200] 
                              : const Color(0xFFC1DADB).withOpacity(0.3),
                          labelStyle: GoogleFonts.poppins(
                            color: isOccupied 
                                ? Colors.grey[500] 
                                : (isSelected ? Colors.white : const Color(0xFF333333)),
                          ),
                          avatar: isOccupied 
                              ? const Icon(Icons.block, size: 16, color: Colors.red)
                              : null,
                        );
                      }),
                    ),
                  ] else ...[
                    Text(
                      'Select a time slot first',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF757575),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedTimeSlot != null && selectedCourt != null)
                  ? () => Navigator.pop(context, {
                        'timeSlot': selectedTimeSlot,
                        'court': selectedCourt,
                      })
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C9A8B),
              ),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == null) {
      setState(() => _isLoading = false);
      return;
    }

    selectedTimeSlot = result['timeSlot'];
    selectedCourt = result['court'];

    // Parse the time slot to get start time
    final timeParts = selectedTimeSlot!.split('-');
    if (timeParts.length != 2) {
      throw Exception('Invalid time slot format');
    }

    final startTimeParts = timeParts[0].trim().split(':');
    if (startTimeParts.length != 2) {
      throw Exception('Invalid time format in time slot');
    }

    final startHour = int.parse(startTimeParts[0]);
    final startMinute = int.parse(startTimeParts[1]);

    
    final newDateTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      startHour,
      startMinute,
    );

    // Convert to UTC for storage
    final utcDateTime = newDateTime.toUtc();

    // Update the match in the subcollection
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .collection('matches')
        .doc(_match['matchId'])
        .update({
      'startTime': Timestamp.fromDate(utcDateTime),
      'court': selectedCourt!,
      'timeSlot': selectedTimeSlot!,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    setState(() {
      _match = {
        ..._match,
        'startTime': Timestamp.fromDate(utcDateTime),
        'court': selectedCourt,
        'timeSlot': selectedTimeSlot,
      };
      _matchStartTime = Timestamp.fromDate(utcDateTime);
      _startCountdown(); // Restart countdown with new calculated time
    });

    toastification.show(
      context: context,
      type: ToastificationType.success,
      title: const Text('Schedule Updated'),
      description: Text(
        'Match scheduled for ${DateFormat('MMM dd, yyyy').format(newDateTime)} at $selectedTimeSlot on Court $selectedCourt',
      ),
      autoCloseDuration: const Duration(seconds: 2),
    );
  } catch (e) {
    debugPrint('Error updating match schedule: $e');
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: const Text('Update Failed'),
      description: Text('Failed to update schedule: ${e.toString()}'),
      autoCloseDuration: const Duration(seconds: 2),
    );
  } finally {
    setState(() => _isLoading = false);
  }
}


  
  void _initializeServer() {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final team1Scores = List<int>.from(
      liveScores[widget.isDoubles ? 'team1' : 'player1'] ?? [0, 0, 0],
    );
    final team2Scores = List<int>.from(
      liveScores[widget.isDoubles ? 'team2' : 'player2'] ?? [0, 0, 0],
    );

    if (!liveScores.containsKey('isLive') || !liveScores['isLive']) {
      _currentServer = widget.isDoubles ? 'team1' : 'player1';
      _lastServer = _currentServer;
    } else if (liveScores['currentServer'] != null) {
      _currentServer = liveScores['currentServer'];
      _lastServer = _currentServer;
    } else {
      String? lastSetWinner;
      for (int i = 0; i < currentGame - 1; i++) {
        if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 ||
            team1Scores[i] == 30) {
          lastSetWinner = widget.isDoubles ? 'team1' : 'player1';
        } else if (team2Scores[i] >= 21 &&
                (team2Scores[i] - team1Scores[i]) >= 2 ||
            team2Scores[i] == 30) {
          lastSetWinner = widget.isDoubles ? 'team2' : 'player2';
        }
      }
      if (team1Scores[currentGame - 1] == 0 &&
          team2Scores[currentGame - 1] == 0 &&
          lastSetWinner != null) {
        _currentServer = lastSetWinner;
        _lastServer = _currentServer;
      } else if (_lastTeam1Score != null && _lastTeam2Score != null) {
        if (team1Scores[currentGame - 1] > _lastTeam1Score!) {
          _currentServer = widget.isDoubles ? 'team1' : 'player1';
          _lastServer = _currentServer;
        } else if (team2Scores[currentGame - 1] > _lastTeam2Score!) {
          _currentServer = widget.isDoubles ? 'team2' : 'player2';
          _lastServer = _currentServer;
        } else {
          _currentServer =
              _lastServer ?? (widget.isDoubles ? 'team1' : 'player1');
        }
      } else {
        _currentServer = widget.isDoubles ? 'team1' : 'player1';
        _lastServer = _currentServer;
      }
    }
  }


int _getCurrentScore(bool isTeam1) {
  final liveScores = _match['liveScores'] ?? {};
  final currentGame = liveScores['currentGame'] ?? 1;
  final scores = List<int>.from(
    liveScores[isTeam1
            ? (widget.isDoubles ? 'team1' : 'player1')
            : (widget.isDoubles ? 'team2' : 'player2')] ??
        [0, 0, 0],
  );
  return scores[currentGame - 1];
}


  String _getServiceCourt(bool isTeam1) {
    final liveScores = _match['liveScores'] ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final scores = List<int>.from(
      liveScores[isTeam1
              ? (widget.isDoubles ? 'team1' : 'player1')
              : (widget.isDoubles ? 'team2' : 'player2')] ??
          [0, 0, 0],
    );
    return scores[currentGame - 1].isEven ? 'Right' : 'Left';
  }


void _listenToMatchUpdates() {
  FirebaseFirestore.instance
      .collection('tournaments')
      .doc(widget.tournamentId)
      .collection('matches')
      .doc(_match['matchId'])
      .snapshots()
      .listen((snapshot) {
    if (!mounted) return;
    if (!snapshot.exists || snapshot.data() == null) {
      debugPrint('Match document does not exist or is empty');
      return;
    }
    
    final newMatchData = snapshot.data()!;
    try {
      // Get current scores before update
      final oldTeam1Score = _getCurrentScore(true);
      final oldTeam2Score = _getCurrentScore(false);
      
      // Update match data
      final updatedMatch = {'matchId': snapshot.id, ...newMatchData};
      
      // Get new scores after update
      final newTeam1Score = _getCurrentScoreFromMatch(updatedMatch, true);
      final newTeam2Score = _getCurrentScoreFromMatch(updatedMatch, false);
      
      // Show animations for score changes
      if (newTeam1Score > oldTeam1Score) {
        setState(() {
          _showPlusOneTeam1 = true;
          _animationController.forward().then((_) {
            _animationController.reverse();
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) setState(() => _showPlusOneTeam1 = false);
            });
          });
        });
      } else if (newTeam2Score > oldTeam2Score) {
        setState(() {
          _showPlusOneTeam2 = true;
          _animationController.forward().then((_) {
            _animationController.reverse();
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) setState(() => _showPlusOneTeam2 = false);
            });
          });
        });
      }
      
      setState(() {
        _match = updatedMatch;
        if (_matchStartTime == null || _match['startTime'] != _matchStartTime) {
          _matchStartTime = _match['startTime'] as Timestamp?;
        }
        _umpireNameController.text = _match['umpire']?['name'] ?? '';
        _umpireEmailController.text = _match['umpire']?['email'] ?? '';
        _umpirePhoneController.text = _match['umpire']?['phone'] ?? '';
        _initialUmpireName = _umpireNameController.text;
        _initialUmpireEmail = _umpireEmailController.text;
        _initialUmpirePhone = _umpirePhoneController.text;
        _lastTeam1Score = newTeam1Score;
        _lastTeam2Score = newTeam2Score;
        _initializeServer();
        _startCountdown();
      });
    } catch (e) {
      debugPrint('Error processing match updates: $e');
    }
  }, onError: (e) {
    debugPrint('Error in match updates listener: $e');
  });
}


  int _getCurrentScoreFromMatch(Map<String, dynamic> match, bool isTeam1) {
  final liveScores = match['liveScores'] ?? {};
  final currentGame = liveScores['currentGame'] ?? 1;
  final scores = List<int>.from(
    liveScores[isTeam1
            ? (widget.isDoubles ? 'team1' : 'player1')
            : (widget.isDoubles ? 'team2' : 'player2')] ??
        [0, 0, 0],
  );
  return scores[currentGame - 1];
}


  bool get _isUmpireButtonDisabled {
    final name = _umpireNameController.text.trim();
    final email = _umpireEmailController.text.trim();
    final phone = _umpirePhoneController.text.trim();
    final isLive = _match['liveScores']?['isLive'] == true;
    return isLive ||
        (name.isEmpty && email.isEmpty && phone.isEmpty) ||
        (name == _initialUmpireName &&
            email == _initialUmpireEmail &&
            phone == _initialUmpirePhone);
  }

  Future<void> _fetchUserData(String email) async {
    if (_match['liveScores']?['isLive'] == true) return;
    if (email.isEmpty ||
        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      return;
    }

    try {
      final query =
          await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .where('role', isEqualTo: 'umpire')
              .limit(1)
              .get();

      if (query.docs.isNotEmpty && mounted) {
        final userData = query.docs.first.data();
        setState(() {
          _umpireNameController.text =
              '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                  .trim();
          _umpirePhoneController.text = userData['phone'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
  }

  

Future<void> _updateUmpireDetails() async {
  if (_isLoading || _isUmpireButtonDisabled) return;
  if (_match['liveScores']?['isLive'] == true) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text('Update Not Allowed', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Umpire details cannot be updated after the match has started.', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFFE76F51),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
    return;
  }

  final name = _umpireNameController.text.trim();
  final email = _umpireEmailController.text.trim();
  final phone = _umpirePhoneController.text.trim();

  // Validation logic remains the same...
  if (email.isEmpty) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text('Email Required', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Please enter an email address.', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFFE76F51),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
    return;
  }

  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text('Invalid Email', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Please enter a valid email address.', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFFE76F51),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    // Update the match document in the subcollection
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .collection('matches')
        .doc(_match['matchId'])
        .update({
      'umpire': {'name': name, 'email': email, 'phone': phone},
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    // Handle umpire credentials as before...
    final umpireQuery = await FirebaseFirestore.instance
        .collection('umpire_credentials')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (umpireQuery.docs.isNotEmpty) {
      final umpireDocId = umpireQuery.docs.first.id;
      await FirebaseFirestore.instance
          .collection('umpire_credentials')
          .doc(umpireDocId)
          .update({
            'name': name,
            'phone': phone,
            'tournamentId': widget.tournamentId,
            'updatedAt': Timestamp.now(),
          });
    } else {
      final newUmpireDoc = FirebaseFirestore.instance.collection('umpire_credentials').doc();
      await newUmpireDoc.set({
        'uid': newUmpireDoc.id,
        'name': name,
        'email': email,
        'phone': phone,
        'tournamentId': widget.tournamentId,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    }

    _initialUmpireName = name;
    _initialUmpireEmail = email;
    _initialUmpirePhone = phone;

    toastification.show(
      context: context,
      type: ToastificationType.success,
      title: Text('Umpire Details Saved', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Umpire details have been saved successfully.', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFF2A9D8F),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
  } catch (e) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text('Save Failed', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Failed to save umpire details: $e', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFFE76F51),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
  } finally {
    setState(() => _isLoading = false);
  }
}

Future<void> _startMatch() async {
  if (_isLoading) return;
  setState(() => _isLoading = true);

  try {
    // Update the match document in the subcollection
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .collection('matches')
        .doc(_match['matchId'])
        .update({
      'liveScores': {
        'isLive': true,
        'startTime': Timestamp.now(),
        'currentGame': 1,
        'currentServer': widget.isDoubles ? 'team1' : 'player1',
        widget.isDoubles ? 'team1' : 'player1': [0, 0, 0],
        widget.isDoubles ? 'team2' : 'player2': [0, 0, 0],
      },
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    toastification.show(
      context: context,
      type: ToastificationType.success,
      title: Text('Match Started', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('The match is now live.', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFF2A9D8F),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
  } catch (e) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text('Start Failed', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Failed to start match: $e', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFFE76F51),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
  } finally {
    setState(() => _isLoading = false);
  }
}

Future<void> _updateLiveScore(bool isTeam1, int gameIndex, int delta) async {
  if (_isLoading || !widget.isUmpire) return;
  setState(() => _isLoading = true);

  try {
    final currentScores = Map<String, dynamic>.from(_match['liveScores']);
    final key = isTeam1 ? (widget.isDoubles ? 'team1' : 'player1') : (widget.isDoubles ? 'team2' : 'player2');
    final scores = List<int>.from(currentScores[key]);
    final newScore = (scores[gameIndex] + delta).clamp(0, 30);
    scores[gameIndex] = newScore;

    // Update the match document in the subcollection
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .collection('matches')
        .doc(_match['matchId'])
        .update({
      'liveScores': {
        ...currentScores,
        key: scores,
      },
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    // Check if set is won and advance if needed
    final team1Scores = List<int>.from(currentScores[widget.isDoubles ? 'team1' : 'player1']);
    final team2Scores = List<int>.from(currentScores[widget.isDoubles ? 'team2' : 'player2']);
    final currentSetScore = isTeam1 ? scores[gameIndex] : team1Scores[gameIndex];
    final opponentSetScore = isTeam1 ? team2Scores[gameIndex] : scores[gameIndex];

    if ((currentSetScore >= 21 && (currentSetScore - opponentSetScore >= 2)) || currentSetScore == 30) {
      await _advanceGame();
    }

    toastification.show(
      context: context,
      type: ToastificationType.success,
      title: Text('Score Updated', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Live score has been updated.', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFF2A9D8F),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
  } catch (e) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text('Update Failed', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Failed to update score: $e', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFFE76F51),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
  } finally {
    setState(() => _isLoading = false);
  }
}



Future<void> _advanceGame() async {
  if (_isLoading || !widget.isUmpire) return;
  setState(() => _isLoading = true);

  try {
    final currentScores = Map<String, dynamic>.from(_match['liveScores']);
    final currentGame = currentScores['currentGame'] as int;
    final team1Scores = List<int>.from(currentScores[widget.isDoubles ? 'team1' : 'player1']);
    final team2Scores = List<int>.from(currentScores[widget.isDoubles ? 'team2' : 'player2']);

    int team1Wins = 0;
    int team2Wins = 0;
    for (int i = 0; i < currentGame; i++) {
      if (team1Scores[i] >= 21 && (team1Scores[i] - team2Scores[i]) >= 2 || team1Scores[i] == 30) {
        team1Wins++;
      } else if (team2Scores[i] >= 21 && (team2Scores[i] - team1Scores[i]) >= 2 || team2Scores[i] == 30) {
        team2Wins++;
      }
    }

    String? winner;
    if (team1Wins >= 2) {
      winner = widget.isDoubles ? 'team1' : 'player1';
    } else if (team2Wins >= 2) {
      winner = widget.isDoubles ? 'team2' : 'player2';
    }

    if (winner != null) {
      // Match completed
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .collection('matches')
          .doc(_match['matchId'])
          .update({
        'completed': true,
        'winner': winner,
        'liveScores': {...currentScores, 'isLive': false},
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      setState(() {
        _match = {
          ..._match,
          'completed': true,
          'winner': winner,
          'liveScores': {...currentScores, 'isLive': false},
        };
      });

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: Text('Match Completed', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
        description: Text(
          'Winner: ${winner == 'team1' || winner == 'player1' ? (widget.isDoubles ? _match['team1'].join(', ') : _match['player1']) : (widget.isDoubles ? _match['team2'].join(', ') : _match['player2'])}',
          style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB)),
        ),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF2A9D8F),
        foregroundColor: const Color(0xFFFDFCFB),
        alignment: Alignment.bottomCenter,
      );
    } else if (currentGame < 3) {
      // Advance to next game
      String? newServer;
      if (team1Scores[currentGame - 1] >= 21 && (team1Scores[currentGame - 1] - team2Scores[currentGame - 1]) >= 2 || team1Scores[currentGame - 1] == 30) {
        newServer = widget.isDoubles ? 'team1' : 'player1';
      } else if (team2Scores[currentGame - 1] >= 21 && (team2Scores[currentGame - 1] - team1Scores[currentGame - 1]) >= 2 || team2Scores[currentGame - 1] == 30) {
        newServer = widget.isDoubles ? 'team2' : 'player2';
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .collection('matches')
          .doc(_match['matchId'])
          .update({
        'liveScores': {
          ...currentScores,
          'currentGame': currentGame + 1,
          'currentServer': newServer ?? currentScores['currentServer'],
        },
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      setState(() {
        _match = {
          ..._match,
          'liveScores': {
            ...currentScores,
            'currentGame': currentGame + 1,
            'currentServer': newServer ?? currentScores['currentServer'],
          },
        };
        _initializeServer();
      });

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: Text('Game Advanced', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
        description: Text('Moved to the next game.', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
        autoCloseDuration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF2A9D8F),
        foregroundColor: const Color(0xFFFDFCFB),
        alignment: Alignment.bottomCenter,
      );
    }
  } catch (e) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text('Advance Failed', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      description: Text('Failed to advance game: $e', style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB))),
      autoCloseDuration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFFE76F51),
      foregroundColor: const Color(0xFFFDFCFB),
      alignment: Alignment.bottomCenter,
    );
  } finally {
    setState(() => _isLoading = false);
  }
}



List<Map<String, dynamic>> _getAllSetResults() {
  final liveScores = _match['liveScores'] ?? {};
  final team1Scores = List<int>.from(
    liveScores[widget.isDoubles ? 'team1' : 'player1'] ?? [0, 0, 0],
  );
  final team2Scores = List<int>.from(
    liveScores[widget.isDoubles ? 'team2' : 'player2'] ?? [0, 0, 0],
  );

  return List.generate(3, (index) {
    final team1Score = team1Scores.length > index ? team1Scores[index] : null;
    final team2Score = team2Scores.length > index ? team2Scores[index] : null;

    String? winner;
    if (team1Score != null && team2Score != null) {
      if ((team1Score >= 21 && (team1Score - team2Score) >= 2) || team1Score == 30) {
        winner = widget.isDoubles ? _match['team1'].join(', ') : _match['player1'];
      } else if ((team2Score >= 21 && (team2Score - team1Score) >= 2) || team2Score == 30) {
        winner = widget.isDoubles ? _match['team2'].join(', ') : _match['player2'];
      }
    }

    return {
      'setNumber': index + 1,
      'team1Score': team1Score,
      'team2Score': team2Score,
      'winner': winner,
      'isCompleted': winner != null,
    };
  });
}


  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    int? maxLength,
    bool isRequired = false,
    ValueChanged<String>? onChanged,
  }) {
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            maxLength: maxLength,
            style: GoogleFonts.poppins(
              color: const Color(0xFF333333),
              fontSize: 14,
            ),
            decoration: InputDecoration(
              label: RichText(
                text: TextSpan(
                  text: label,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF757575),
                    fontSize: 14,
                  ),
                  children:
                      isRequired
                          ? [
                            const TextSpan(
                              text: ' *',
                              style: TextStyle(color: Color(0xFFE76F51)),
                            ),
                          ]
                          : [],
                ),
              ),
              hintText: isRequired ? 'Required' : null,
              hintStyle: GoogleFonts.poppins(
                color: const Color(0xFF757575).withOpacity(0.7),
                fontSize: 14,
              ),
              prefixIcon: Icon(icon, color: const Color(0xFFF4A261), size: 20),
              suffixIcon: suffixIcon,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFC1DADB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF6C9A8B),
                  width: 1.5,
                ),
              ),
              counterStyle: GoogleFonts.poppins(
                color: const Color(0xFF757575),
                fontSize: 12,
              ),
              filled: true,
              fillColor: const Color(0xFFC1DADB).withOpacity(0.1),
            ),
            onChanged: (value) {
              setState(() {});
              if (onChanged != null) onChanged(value);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildModernButton({
    required String text,
    required LinearGradient gradient,
    required bool isLoading,
    VoidCallback? onPressed,
  }) {
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: GestureDetector(
            onTap: isLoading || onPressed == null ? null : onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              decoration: BoxDecoration(
                gradient:
                    isLoading || onPressed == null
                        ? LinearGradient(
                          colors: [
                            const Color(0xFF757575),
                            const Color(0xFF757575).withOpacity(0.7),
                          ],
                        )
                        : gradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF333333).withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child:
                  isLoading
                      ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Color(0xFFFDFCFB),
                          strokeWidth: 2,
                        ),
                      )
                      : Text(
                        text,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFDFCFB),
                        ),
                      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE9C46A).withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE9C46A).withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: const Color(0xFFE9C46A),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection({
    required String title,
    required List<Widget> children,
    bool isLive = false,
  }) {
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isLive
                        ? const Color(0xFFE76F51)
                        : const Color(0xFFC1DADB).withOpacity(0.5),
                width: isLive ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF333333).withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF333333),
                      ),
                    ),
                    if (isLive) _buildLiveStatusBadge(),
                  ],
                ),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }




  Widget _buildLiveStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE76F51), Color(0xFFF4A261)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE76F51).withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFDFCFB),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFDFCFB),
            ),
          ),
        ],
      ),
    );
  }

Widget _buildDetailRow({
  required IconData icon,
  required String label,
  required String value,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFFF4A261), size: 18),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: const Color(0xFF757575),
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF333333),
              fontWeight: FontWeight.w400,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    ),
  );
}

  Widget _buildSetScoreCard({
    required int setNumber,
    required int? team1Score,
    required int? team2Score,
    required String? winner,
    required bool isCurrentSet,
  }) {
    final isCompleted = winner != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isCurrentSet
                ? const Color(0xFF2A9D8F).withOpacity(0.1)
                : const Color(0xFFFDFCFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isCurrentSet
                  ? const Color(0xFF2A9D8F)
                  : const Color(0xFFC1DADB).withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF333333).withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Set $setNumber',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: isCurrentSet ? FontWeight.w600 : FontWeight.w500,
              color:
                  isCurrentSet
                      ? const Color(0xFF2A9D8F)
                      : const Color(0xFF333333),
            ),
          ),
          Row(
            children: [
              Text(
                team1Score != null ? '$team1Score' : '-',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight:
                      winner ==
                              (widget.isDoubles
                                  ? _match['team1'].join(', ')
                                  : _match['player1'])
                          ? FontWeight.w700
                          : FontWeight.w500,
                  color: const Color(0xFF333333),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF757575),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                team2Score != null ? '$team2Score' : '-',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight:
                      winner ==
                              (widget.isDoubles
                                  ? _match['team2'].join(', ')
                                  : _match['player2'])
                          ? FontWeight.w700
                          : FontWeight.w500,
                  color: const Color(0xFF333333),
                ),
              ),
            ],
          ),
          if (isCompleted)
            Icon(Icons.check_circle, color: const Color(0xFF2A9D8F), size: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = _match['completed'] == true;
    final isLive = _match['liveScores']?['isLive'] == true;
    final currentSet = _match['liveScores']?['currentGame'] ?? 1;
    final allSetResults = _getAllSetResults();
    final currentSetIndex = currentSet - 1;

    int team1Wins = 0;
    int team2Wins = 0;
    for (final set in allSetResults) {
      if (set['winner'] ==
          (widget.isDoubles ? _match['team1'].join(', ') : _match['player1'])) {
        team1Wins++;
      } else if (set['winner'] ==
          (widget.isDoubles ? _match['team2'].join(', ') : _match['player2'])) {
        team2Wins++;
      }
    }

    final matchWinner =
        isCompleted
            ? (_match['winner'] == 'team1' || _match['winner'] == 'player1'
                ? (widget.isDoubles
                    ? _match['team1'].join(', ')
                    : _match['player1'])
                : (widget.isDoubles
                    ? _match['team2'].join(', ')
                    : _match['player2']))
            : null;


    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF6C9A8B),
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFDFCFB),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: const Color(0xFF6C9A8B),
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  color: const Color(0xFFFDFCFB),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  widget.isDoubles
                      ? 'Team Match Details'
                      : 'Singles Match Details',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFFDFCFB),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                actions: [
                  if (widget.isCreator && !isCompleted)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') {
                          widget.onDeleteMatch();
                          Navigator.pop(context);
                        }
                      },
                      itemBuilder:
                          (context) => [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete Match',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFE76F51),
                                ),
                              ),
                            ),
                          ],
                      icon: const Icon(
                        Icons.more_vert,
                        color: Color(0xFFFDFCFB),
                      ),
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: AnimationConfiguration.synchronized(
                    duration: const Duration(milliseconds: 1000),
                    child: Column(
                      children: AnimationConfiguration.toStaggeredList(
                        duration: const Duration(milliseconds: 500),
                        childAnimationBuilder:
                            (child) => SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(child: child),
                            ),
                        children: [
                          _buildDetailSection(
                            title: 'Match Information',
                            children: [
                              _buildDetailRow(
                                icon: Icons.sports_tennis,
                                label: 'Round',
                                value: 'Round ${_match['round']}',
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.isDoubles
                                            ? _match['team1'].join(', ')
                                            : _match['player1'],
                                        style: GoogleFonts.poppins(
                                          color: const Color(0xFF333333),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Text(
                                        'vs',
                                        style: GoogleFonts.poppins(
                                          color: const Color(0xFF757575),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        widget.isDoubles
                                            ? _match['team2'].join(', ')
                                            : _match['player2'],
                                        style: GoogleFonts.poppins(
                                          color: const Color(0xFF333333),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                             _buildDetailRow(
  icon: Icons.access_time,
  label: 'Start Time',
  value: _matchStartTime != null && _isTimezoneInitialized
      ? _formatDateWithTimezone(_convertToTournamentTime(_matchStartTime!))
      : 'Not scheduled',
),
                              _buildDetailRow(
                                icon: Icons.schedule,
                                label: 'Time Slot',
                                value: _match['timeSlot']?.toString() ?? 'Not scheduled',
                              ),
                              _buildDetailRow(
                                icon: Icons.location_on,
                                label: 'Court',
                                value: _match['court'] != null ? 'Court ${_match['court']}' : 'Not assigned',
                              ),
                             if (_countdown == null && !_isTimezoneInitialized)
                              _buildDetailRow(
                                icon: Icons.timer,
                                label: 'Countdown',
                                value: 'Loading...',
                              ),
                             if (_countdown != null)
                              _buildDetailRow(
                                icon: Icons.timer,
                                label: 'Countdown',
                                value: _countdown!,
                              ),
                              if (matchWinner != null)
                                _buildDetailRow(
                                  icon: Icons.emoji_events,
                                  label: 'Winner',
                                  value: matchWinner,
                                ),
                              if (widget.isCreator && !isLive && !isCompleted)
                                const SizedBox(height: 12),
                              if (widget.isCreator && !isLive && !isCompleted)
                                _buildModernButton(
                                  text: 'Update Schedule',
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF2A9D8F),
                                      Color(0xFF6C9A8B),
                                    ],
                                  ),
                                  isLoading: _isLoading,
                                  onPressed: _updateMatchStartTime,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildDetailSection(
                            title: 'Live Score',
                            isLive: isLive,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          widget.isDoubles
                                              ? _match['team1'].join(', ')
                                              : _match['player1'],
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: const Color(0xFF333333),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Text(
                                              _getCurrentScore(true).toString(),
                                              style: GoogleFonts.poppins(
                                                fontSize: 32,
                                                color: const Color(0xFF2A9D8F),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (_showPlusOneTeam1)
                                              Positioned(
                                                top: -10,
                                                child: FadeTransition(
                                                  opacity: _fadeAnimation,
                                                  child: ScaleTransition(
                                                    scale: _scaleAnimation,
                                                    child: Text(
                                                      '+1',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 16,
                                                            color: const Color(
                                                              0xFFE76F51,
                                                            ),
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (isLive && widget.isUmpire)
                                          Column(
                                            children: [
                                              const SizedBox(height: 8),
                                              _buildScoreButton(
                                                label: '+1',
                                                onPressed:
                                                    () => _updateLiveScore(
                                                      true,
                                                      currentSetIndex,
                                                      1,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              _buildScoreButton(
                                                label: '-1',
                                                onPressed:
                                                    () => _updateLiveScore(
                                                      true,
                                                      currentSetIndex,
                                                      -1,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        if (isLive)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Text(
                                              _currentServer ==
                                                      (widget.isDoubles
                                                          ? 'team1'
                                                          : 'player1')
                                                  ? 'Serving (${_getServiceCourt(true)})'
                                                  : '',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: const Color(0xFF757575),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Text(
                                      ':',
                                      style: GoogleFonts.poppins(
                                        fontSize: 24,
                                        color: const Color(0xFF333333),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          widget.isDoubles
                                              ? _match['team2'].join(', ')
                                              : _match['player2'],
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: const Color(0xFF333333),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Text(
                                            _getCurrentScore(false).toString(),
                                            style: GoogleFonts.poppins(
                                              fontSize: 32,
                                              color: const Color(0xFF2A9D8F),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (_showPlusOneTeam2)
                                            Positioned(
                                              top: -10,
                                              child: FadeTransition(
                                                opacity: _fadeAnimation,
                                                child: ScaleTransition(
                                                  scale: _scaleAnimation,
                                                  child: Text(
                                                    '+1',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 16,
                                                      color: const Color(0xFFE76F51),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (isLive && widget.isUmpire)
                                        Column(
                                          children: [
                                            const SizedBox(height: 8),
                                            _buildScoreButton(
                                              label: '+1',
                                              onPressed: () => _updateLiveScore(
                                                false,
                                                currentSetIndex,
                                                1,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            _buildScoreButton(
                                              label: '-1',
                                              onPressed: () => _updateLiveScore(
                                                false,
                                                currentSetIndex,
                                                -1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (isLive)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            _currentServer ==
                                                    (widget.isDoubles
                                                        ? 'team2'
                                                        : 'player2')
                                                ? 'Serving (${_getServiceCourt(false)})'
                                                : '',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: const Color(0xFF757575),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                             
                                 )   ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Current Set: $currentSet',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2A9D8F),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Column(
                                children:
                                    allSetResults.asMap().entries.map((entry) {
                                      final set = entry.value;
                                      final isCurrentSet =
                                          entry.key == currentSetIndex;
                                      return _buildSetScoreCard(
                                        setNumber: set['setNumber'],
                                        team1Score: set['team1Score'],
                                        team2Score: set['team2Score'],
                                        winner: set['winner'],
                                        isCurrentSet: isCurrentSet,
                                      );
                                    }).toList(),
                              ),
                              if (team1Wins > 0 || team2Wins > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Set Wins: ${widget.isDoubles ? _match['team1'].join(', ') : _match['player1']} ($team1Wins) vs ${widget.isDoubles ? _match['team2'].join(', ') : _match['player2']} ($team2Wins)',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF333333),
                                    ),
                                  ),
                                ),
                              if (widget.isUmpire && !isLive && !isCompleted)
                                const SizedBox(height: 12),
                              if (widget.isUmpire && !isLive && !isCompleted)
                                _buildModernButton(
                                  text: 'Start Match',
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF2A9D8F),
                                      Color(0xFF6C9A8B),
                                    ],
                                  ),
                                  isLoading: _isLoading,
                                  onPressed: _startMatch,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildDetailSection(
                            title: 'Umpire Details',
                            children: [
                              _buildModernTextField(
                                controller: _umpireNameController,
                                label: 'Umpire Name',
                                icon: Icons.person,
                                isRequired: false,
                              ),
                              const SizedBox(height: 12),
                              _buildModernTextField(
                                controller: _umpireEmailController,
                                label: 'Umpire Email',
                                icon: Icons.email,
                                keyboardType: TextInputType.emailAddress,
                                isRequired: true,
                                onChanged: (value) {
                                  _debounceTimer?.cancel();
                                  _debounceTimer = Timer(
                                    const Duration(milliseconds: 500),
                                    () => _fetchUserData(value),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildModernTextField(
                                controller: _umpirePhoneController,
                                label: 'Umpire Phone',
                                icon: Icons.phone,
                                keyboardType: TextInputType.phone,
                                maxLength: 13,
                                isRequired: false,
                              ),
                              const SizedBox(height: 12),
                              if (widget.isCreator)
                                _buildModernButton(
                                  text: 'Save Umpire Details',
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF2A9D8F),
                                      Color(0xFF6C9A8B),
                                    ],
                                  ),
                                  isLoading: _isLoading,
                                  onPressed:
                                      _isUmpireButtonDisabled
                                          ? null
                                          : _updateUmpireDetails,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}