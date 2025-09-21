import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/umpire/matchcontrolpage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:toastification/toastification.dart';

class UmpireMatchesPage extends StatefulWidget {
  const UmpireMatchesPage({super.key});

  @override
  State<UmpireMatchesPage> createState() => _UmpireMatchesPageState();
}

class _UmpireMatchesPageState extends State<UmpireMatchesPage> {
  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _secondaryColor = const Color(0xFFC1DADB);
  final Color _accentColor = const Color(0xFFF4A261);
  final Color _textColor = const Color(0xFF333333);
  final Color _secondaryText = const Color(0xFF757575);
  final Color _successColor = const Color(0xFF4CAF50);
  final Color _errorColor = const Color(0xFFE76F51);

  final Map<String, tz.Location> _timezoneCache = {};
  final Map<String, String?> _countdownCache = {};
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _startCountdownUpdates();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownUpdates() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Only update if countdowns have changed
      bool needsUpdate = false;
      final newCountdowns = <String, String?>{};
      for (var entry in _countdownCache.keys) {
        final matchId = entry.split('-')[0];
        final match = _getMatchById(matchId);
        if (match != null) {
          final timezone = _timezoneCache[match['tournamentId']] ?? tz.getLocation('UTC');
          final newCountdown = _calculateCountdown(match, timezone);
          if (newCountdown != _countdownCache[entry]) {
            needsUpdate = true;
            newCountdowns[entry] = newCountdown;
          } else {
            newCountdowns[entry] = _countdownCache[entry];
          }
        }
      }
      if (needsUpdate && mounted) {
        setState(() {
          _countdownCache.clear();
          _countdownCache.addAll(newCountdowns);
        });
      }
    });
  }

  Map<String, dynamic>? _getMatchById(String matchId) {
    // This is a placeholder; you may need to adjust based on how you store matches
    // For example, fetch from a cached list of matches or query Firestore
    return null; // Replace with actual logic to retrieve match data
  }

  Future<tz.Location> _initializeTimezone(String tournamentId) async {
    if (_timezoneCache.containsKey(tournamentId)) {
      return _timezoneCache[tournamentId]!;
    }

    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .get();

      final timezone = tournamentDoc.data()?['timezone'] as String? ?? 'UTC';
      final tzLocation = tz.getLocation(timezone);
      _timezoneCache[tournamentId] = tzLocation;
      return tzLocation;
    } catch (e) {
      debugPrint('Error initializing timezone for tournament $tournamentId: $e');
      final tzLocation = tz.getLocation('UTC');
      _timezoneCache[tournamentId] = tzLocation;
      return tzLocation;
    }
  }

  // CRITICAL FIX: Match the exact logic from MatchControlPage
  DateTime _convertToTournamentTime(Map<String, dynamic> match, tz.Location timezoneLocation) {
    final startTime = match['startTime'] as Timestamp?;
    final timeslot = match['timeSlot'] as String?; // Note: using 'timeSlot' not 'timeslot'

    if (startTime == null) {
      debugPrint('No startTime for match: ${match['matchId']}');
      return DateTime.now();
    }

    var matchTime = startTime.toDate(); // Convert to local DateTime first
    
    // Apply timeslot logic exactly like MatchControlPage
    if (timeslot != null && RegExp(r'^\d{2}:\d{2}$').hasMatch(timeslot)) {
      try {
        final timeFormat = DateFormat('HH:mm');
        final parsedTime = timeFormat.parse(timeslot);
        matchTime = DateTime(
          matchTime.year,
          matchTime.month,
          matchTime.day,
          parsedTime.hour,
          parsedTime.minute,
        );
        final now = DateTime.now();
        if (matchTime.isBefore(now)) {
          matchTime = matchTime.add(const Duration(days: 1));
        }
      } catch (e) {
        debugPrint('Error parsing timeslot for match ${match['matchId']}: $e');
        // Fall back to original startTime
      }
    }

    // Convert to timezone-aware DateTime
    final tzMatchTime = tz.TZDateTime.from(matchTime, timezoneLocation);
    return tzMatchTime;
  }

  String? _calculateCountdown(Map<String, dynamic> match, tz.Location timezoneLocation) {
    final cacheKey = '${match['matchId']}-${match['startTime']?.seconds ?? 0}';
    if (_countdownCache.containsKey(cacheKey)) {
      return _countdownCache[cacheKey];
    }

    final isLive = match['liveScores']?['isLive'] == true;
    final isCompleted = match['completed'] == true;
    final startTime = match['startTime'] as Timestamp?;

    if (isLive || isCompleted || startTime == null) {
      return null;
    }

    final matchDateTime = _convertToTournamentTime(match, timezoneLocation);
    final nowInTournament = tz.TZDateTime.now(timezoneLocation);
    final difference = matchDateTime.difference(nowInTournament);

    debugPrint('Match ${match['matchId']} - Match time: $matchDateTime, Now: $nowInTournament, Difference: $difference');

    if (difference.isNegative) {
      return null; // Past matches are filtered out
    }

    final countdown = _formatDuration(difference);
    _countdownCache[cacheKey] = countdown;
    return countdown;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFDFCFB),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthLoading) {
                      return Center(
                        child: CircularProgressIndicator(color: _accentColor),
                      );
                    } else if (state is AuthAuthenticated) {
                      final umpireEmail = state.user.email;
                      if (umpireEmail == null) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.email_outlined, size: 48, color: _errorColor),
                              const SizedBox(height: 16),
                              Text(
                                'No email associated with this account',
                                style: GoogleFonts.poppins(
                                  color: _secondaryText,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return _buildMatchesList(umpireEmail);
                    } else {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: _errorColor),
                            const SizedBox(height: 16),
                            Text(
                              'Authentication required',
                              style: GoogleFonts.poppins(
                                color: _secondaryText,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please log in as an official',
                              style: GoogleFonts.poppins(
                                color: _secondaryText,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchesList(String umpireEmail) {
    debugPrint('Querying matches for umpireEmail: $umpireEmail');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('matches')
          .where('umpire.email', isEqualTo: umpireEmail)
          .snapshots(),
      builder: (context, assignedSnapshot) {
        debugPrint('Received assigned matches snapshot: ${assignedSnapshot.data?.docs.length} docs');
        if (assignedSnapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: _accentColor),
                const SizedBox(height: 16),
                Text(
                  'Loading your assignments...',
                  style: GoogleFonts.poppins(
                    color: _secondaryText,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        if (assignedSnapshot.hasError) {
          debugPrint('Assigned matches query error: ${assignedSnapshot.error.toString()}');
          return _buildErrorState('Error loading assigned matches: ${assignedSnapshot.error}');
        }

        final assignedMatches = <Map<String, dynamic>>[];
        if (assignedSnapshot.hasData) {
          for (var matchDoc in assignedSnapshot.data!.docs) {
            final matchData = matchDoc.data() as Map<String, dynamic>;
            final path = matchDoc.reference.path;
            final tournamentId = path.split('/')[1];
            debugPrint('Assigned match: ${matchDoc.id}, data: $matchData');
            final isCompleted = matchData['completed'] == true;
            if (isCompleted) {
              debugPrint('Skipping completed assigned match: ${matchDoc.id}');
              continue;
            }
            assignedMatches.add({
              ...matchData,
              'matchId': matchDoc.id,
              'tournamentId': tournamentId,
              'documentPath': path,
              'assignmentType': 'assigned',
            });
          }
        }

        debugPrint('Found ${assignedMatches.length} assigned matches for umpire');

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collectionGroup('matches')
              .where('umpire.email', isEqualTo: '')
              .snapshots(),
          builder: (context, availableSnapshot) {
            debugPrint('Received available matches snapshot: ${availableSnapshot.data?.docs.length} docs');
            final availableMatches = <Map<String, dynamic>>[];

            if (availableSnapshot.hasData) {
              for (var matchDoc in availableSnapshot.data!.docs) {
                final matchData = matchDoc.data() as Map<String, dynamic>;
                final path = matchDoc.reference.path;
                final tournamentId = path.split('/')[1];
                debugPrint('Available match: ${matchDoc.id}, data: $matchData');
                final isCompleted = matchData['completed'] == true;
                if (isCompleted) {
                  debugPrint('Skipping completed available match: ${matchDoc.id}');
                  continue;
                }
                availableMatches.add({
                  ...matchData,
                  'matchId': matchDoc.id,
                  'tournamentId': tournamentId,
                  'documentPath': path,
                  'assignmentType': 'available',
                });
              }
            }

            debugPrint('Found ${availableMatches.length} available matches');

            final allMatches = [...assignedMatches, ...availableMatches];

            if (allMatches.isEmpty) {
              return _buildEmptyState(umpireEmail);
            }

            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadTournamentData(allMatches),
              builder: (context, tournamentSnapshot) {
                if (tournamentSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: _accentColor),
                        const SizedBox(height: 16),
                        Text(
                          'Loading tournament details...',
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final enrichedMatches = tournamentSnapshot.data ?? [];
                if (enrichedMatches.isEmpty) {
                  return _buildEmptyState(umpireEmail);
                }

                _sortMatchesWithAvailable(enrichedMatches);

                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
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
                      child: _buildMatchStatsWithAvailable(enrichedMatches),
                    ),
                    Expanded(
                      child: AnimationLimiter(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: enrichedMatches.length,
                          itemBuilder: (context, index) {
                            final match = enrichedMatches[index];
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: SlideAnimation(
                                verticalOffset: 50.0,
                                child: FadeInAnimation(
                                  child: _buildMatchCardWithActions(match, context, umpireEmail, index),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: _errorColor),
          const SizedBox(height: 16),
          Text(
            'Error loading matches',
            style: GoogleFonts.poppins(
              color: _errorColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.poppins(
              color: _secondaryText,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _sortMatchesWithAvailable(List<Map<String, dynamic>> matches) {
    final now = DateTime.now(); // Use local time like MatchControlPage

    matches.sort((a, b) {
      final timeA = (a['startTime'] as Timestamp?)?.toDate() ?? DateTime(2100);
      final timeB = (b['startTime'] as Timestamp?)?.toDate() ?? DateTime(2100);
      final aIsAssigned = a['assignmentType'] == 'assigned';
      final bIsAssigned = b['assignmentType'] == 'assigned';
      final aIsLive = a['liveScores']?['isLive'] == true;
      final aIsCompleted = a['completed'] == true;
      final bIsLive = b['liveScores']?['isLive'] == true;
      final bIsCompleted = b['completed'] == true;
      final aIsReady = !aIsLive && !aIsCompleted && timeA.isBefore(now);
      final bIsReady = !bIsLive && !bIsCompleted && timeB.isBefore(now);

      if (aIsAssigned && !bIsAssigned) return -1;
      if (!aIsAssigned && bIsAssigned) return 1;

      if (aIsLive && !bIsLive) return -1;
      if (!aIsLive && bIsLive) return 1;
      if (aIsReady && !bIsReady && !bIsLive) return -1;
      if (!aIsReady && bIsReady && !aIsLive) return 1;
      if (!aIsLive && !aIsReady && !bIsLive && !bIsReady && !aIsCompleted && bIsCompleted) return -1;
      if (!aIsLive && !aIsReady && !bIsLive && !bIsReady && aIsCompleted && !bIsCompleted) return 1;

      return timeA.compareTo(timeB);
    });
  }

  Widget _buildMatchStatsWithAvailable(List<Map<String, dynamic>> matches) {
    int assignedCount = 0;
    int availableCount = 0;
    int liveCount = 0;
    int completedCount = 0;

    for (var match in matches) {
      if (match['assignmentType'] == 'assigned') {
        assignedCount++;
      } else {
        availableCount++;
      }

      if (match['liveScores']?['isLive'] == true) {
        liveCount++;
      } else if (match['completed'] == true) {
        completedCount++;
      }
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStatItem('Assigned', assignedCount, _primaryColor)),
            Expanded(child: _buildStatItem('Available', availableCount, _accentColor)),
            Expanded(child: _buildStatItem('Live', liveCount, _successColor)),
            Expanded(child: _buildStatItem('Completed', completedCount, _secondaryText)),
          ],
        ),
        if (availableCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Tap "Take Assignment" on available matches to officiate them',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: _secondaryText,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildMatchCardWithActions(Map<String, dynamic> match, BuildContext context, String umpireEmail, int index) {
    debugPrint('Building match card with data: $match');
    final isAssigned = match['assignmentType'] == 'assigned';
    final isDoubles = match['isDoubles'] ?? false;
    final team1 = isDoubles
        ? (match['team1'] as List<dynamic>?)?.join(' & ') ?? 'Team 1'
        : match['player1']?.toString() ?? 'Player 1';
    final team2 = isDoubles
        ? (match['team2'] as List<dynamic>?)?.join(' & ') ?? 'Team 2'
        : match['player2']?.toString() ?? 'Player 2';

    final isLive = match['liveScores']?['isLive'] == true;
    final isCompleted = match['completed'] == true;
    
    // CRITICAL FIX: Use the same timezone logic as MatchControlPage
    final timezoneLocation = _timezoneCache[match['tournamentId']] ?? tz.getLocation('UTC');
    final matchStartTime = _convertToTournamentTime(match, timezoneLocation);
    final now = DateTime.now(); // Use local time for comparison like MatchControlPage
    final isReady = !isLive && !isCompleted && matchStartTime.isBefore(now);

    // FIXED: Format date WITHOUT time (only date portion)
    DateFormat('MMM dd, yyyy').format(matchStartTime);
    final countdown = _calculateCountdown(match, timezoneLocation);

    String status;
    Color statusColor;
    IconData statusIcon;

    if (isLive) {
      status = 'In Progress';
      statusColor = _accentColor;
      statusIcon = Icons.play_circle_fill;
    } else if (isCompleted) {
      status = 'Completed';
      statusColor = _successColor;
      statusIcon = Icons.check_circle;
    } else if (isReady) {
      status = 'Ready to Start';
      statusColor = const Color(0xFFF4A261);
      statusIcon = Icons.play_arrow;
    } else {
      status = 'Scheduled';
      statusColor = _secondaryText;
      statusIcon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: !isAssigned
            ? _accentColor.withOpacity(0.05)
            : (isReady ? const Color(0xFFF4A261).withOpacity(0.05) : Colors.white),
        border: Border.all(
          color: !isAssigned
              ? _accentColor.withOpacity(0.3)
              : (isReady ? const Color(0xFFF4A261).withOpacity(0.3) : _primaryColor.withOpacity(0.2)),
          width: !isAssigned || isReady ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isAssigned
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MatchControlPage(
                        tournamentId: match['tournamentId'],
                        match: match,
                        matchIndex: index,
                        isDoubles: isDoubles,
                      ),
                    ),
                  );
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAssigned ? _primaryColor.withOpacity(0.15) : _accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAssigned ? 'ASSIGNED' : 'AVAILABLE',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isAssigned ? _primaryColor : _accentColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 16, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            status,
                            style: GoogleFonts.poppins(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '$team1 vs $team2',
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.emoji_events_outlined, size: 16, color: _secondaryText),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        match['tournamentName']?.toString() ?? 'Tournament',
                        style: GoogleFonts.poppins(
                          color: _secondaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Court and Time Slot Row - KEPT AS USUAL
                Row(
                  children: [
                    if (match['court'] != null) ...[
                      Icon(Icons.location_on_outlined, size: 16, color: _secondaryText),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Court ${match['court']}',
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (match['timeSlot'] != null) ...[
                      const SizedBox(width: 16),
                      Icon(Icons.access_time, size: 16, color: _secondaryText),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          match['timeSlot'], // Keep time slot display as usual
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Date Row - ONLY DATE (no time)
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 16, color: _secondaryText),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        // FIXED: Only show date without time
                        DateFormat('MMM dd, yyyy').format(matchStartTime),
                        style: GoogleFonts.poppins(
                          color: _secondaryText,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // COUNTDOWN - KEPT AS USUAL
                if (!isLive && !isCompleted && countdown != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _accentColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer, size: 16, color: _accentColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Starts in: $countdown', // Keep countdown display
                            style: GoogleFonts.poppins(
                              color: _accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isLive && match['liveScores'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accentColor.withOpacity(0.3)),
                    ),
                    child: _buildLiveScores(match, isDoubles),
                  ),
                ] else if (isCompleted && match['winner'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _successColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _successColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.emoji_events, size: 20, color: _successColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Winner: ${match['winner'] == (isDoubles ? 'team1' : 'player1') ? team1 : team2}',
                            style: GoogleFonts.poppins(
                              color: _successColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (!isAssigned && !isLive && !isCompleted) ...[
                  ElevatedButton(
                    onPressed: () => _takeAssignment(match, umpireEmail),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Take Assignment',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Icon(Icons.touch_app, size: 16, color: _primaryColor.withOpacity(0.7)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isAssigned
                              ? 'Tap to ${isLive ? 'manage match' : isCompleted ? 'view details' : 'start match'}'
                              : 'Available for assignment',
                          style: GoogleFonts.poppins(
                            color: _primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _takeAssignment(Map<String, dynamic> match, String umpireEmail) async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Take Assignment',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600,color: Colors.black),
          ),
          content: Text(
            'Do you want to officiate this match?',
            style: GoogleFonts.poppins(color: Colors.black),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _accentColor),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: umpireEmail)
          .limit(1)
          .get();

      String umpireName = 'Umpire';
      String umpirePhone = '';

      if (userQuery.docs.isNotEmpty) {
        final userData = userQuery.docs.first.data();
        umpireName = '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
        umpirePhone = userData['phone'] ?? '';
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(match['tournamentId'])
          .collection('matches')
          .doc(match['matchId'])
          .update({
        'umpire': {
          'name': umpireName,
          'email': umpireEmail,
          'phone': umpirePhone,
        },
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Assignment Taken'),
        description: const Text('You are now assigned to officiate this match!'),
        autoCloseDuration: const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('Error taking assignment: $e');
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Assignment Failed'),
        description: Text('Failed to take assignment: $e'),
        autoCloseDuration: const Duration(seconds: 2),
      );
    }
  }

  Widget _buildEmptyState(String umpireEmail) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 64, color: _secondaryText.withOpacity(0.5)),
          const SizedBox(height: 24),
          Text(
            'No matches assigned',
            style: GoogleFonts.poppins(
              color: _textColor,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You currently have no officiating assignments',
            style: GoogleFonts.poppins(
              color: _secondaryText,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: _secondaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _secondaryColor.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Text(
                  'Logged in as:',
                  style: GoogleFonts.poppins(
                    color: _secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  umpireEmail,
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.info_outline, color: _accentColor, size: 24),
                const SizedBox(height: 8),
                Text(
                  'Tournament organizers will assign matches to you. Check back later or contact them directly.',
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: _secondaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _loadTournamentData(List<Map<String, dynamic>> matches) async {
    final enrichedMatches = <Map<String, dynamic>>[];

    for (var match in matches) {
      try {
        final tournamentDoc = await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(match['tournamentId'])
            .get();

        String tournamentName = 'Unknown Tournament';
        String timezoneName = 'UTC';

        if (tournamentDoc.exists) {
          final tournamentData = tournamentDoc.data()!;
          tournamentName = tournamentData['name'] ?? 'Tournament';
          timezoneName = tournamentData['timezone'] as String? ?? 'UTC';
          await _initializeTimezone(match['tournamentId']);
        }

        final timezoneLocation = _timezoneCache[match['tournamentId']] ?? tz.getLocation('UTC');
        final countdown = _calculateCountdown(match, timezoneLocation);
        _countdownCache['${match['matchId']}-${match['startTime']?.seconds ?? 0}'] = countdown;

        enrichedMatches.add({
          ...match,
          'tournamentName': tournamentName,
          'timezone': timezoneName,
          'isDoubles': (match['matchType'] ?? '').toString().toLowerCase().contains('doubles'),
        });
      } catch (e) {
        debugPrint('Error loading tournament data for match ${match['matchId']}: $e');
        _countdownCache['${match['matchId']}-${match['startTime']?.seconds ?? 0}'] = null;
        enrichedMatches.add({
          ...match,
          'tournamentName': 'Unknown Tournament',
          'timezone': 'UTC',
          'isDoubles': false,
        });
      }
    }

    debugPrint('Enriched matches: ${enrichedMatches.length}');
    return enrichedMatches;
  }

  Widget _buildLiveScores(Map<String, dynamic> match, bool isDoubles) {
    final currentGame = match['liveScores']['currentGame'] ?? 1;
    final team1Key = isDoubles ? 'team1' : 'player1';
    final team2Key = isDoubles ? 'team2' : 'player2';
    final team1Scores = List<int>.from(match['liveScores'][team1Key] ?? [0, 0, 0]);
    final team2Scores = List<int>.from(match['liveScores'][team2Key] ?? [0, 0, 0]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.scoreboard, size: 16, color: _accentColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Live Score - Game $currentGame',
                style: GoogleFonts.poppins(
                  color: _accentColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              'Game 1: ${team1Scores[0]} - ${team2Scores[0]}',
              style: GoogleFonts.poppins(fontSize: 13, color: _textColor),
            ),
            Text(
              'Game 2: ${team1Scores[1]} - ${team2Scores[1]}',
              style: GoogleFonts.poppins(fontSize: 13, color: _textColor),
            ),
            Text(
              'Game 3: ${team1Scores[2]} - ${team2Scores[2]}',
              style: GoogleFonts.poppins(fontSize: 13, color: _textColor),
            ),
          ],
        ),
      ],
    );
  }
}