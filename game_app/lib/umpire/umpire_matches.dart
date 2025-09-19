import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/screens/countdown_text.dart';
import 'package:game_app/umpire/matchcontrolpage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
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

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
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
              // Header
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
        return _buildErrorState('Error loading assigned matches');
      }

      // Get assigned matches
      final assignedMatches = <Map<String, dynamic>>[];
      if (assignedSnapshot.hasData) {
        for (var matchDoc in assignedSnapshot.data!.docs) {
          final matchData = matchDoc.data() as Map<String, dynamic>;
          final path = matchDoc.reference.path;
          final tournamentId = path.split('/')[1];
          
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

      // Also check for available matches (with empty umpire email) that can be self-assigned
      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collectionGroup('matches')
            .where('umpire.email', isEqualTo: '')  // Empty umpire email
            .snapshots(),
        builder: (context, availableSnapshot) {
          final availableMatches = <Map<String, dynamic>>[];
          
          if (availableSnapshot.hasData) {
            for (var matchDoc in availableSnapshot.data!.docs) {
              final matchData = matchDoc.data() as Map<String, dynamic>;
              final path = matchDoc.reference.path;
              final tournamentId = path.split('/')[1];
              
              // Only show matches that haven't started and aren't completed
              if (matchData['liveScores']?['isLive'] != true && 
                  matchData['completed'] != true) {
                availableMatches.add({
                  ...matchData,
                  'matchId': matchDoc.id,
                  'tournamentId': tournamentId,
                  'documentPath': path,
                  'assignmentType': 'available',
                });
              }
            }
          }

          debugPrint('Found ${availableMatches.length} available matches');

          // Combine both lists
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

              // Sort matches by priority: Assigned Live > Assigned Ready > Available > Assigned Scheduled > Assigned Completed
              _sortMatchesWithAvailable(enrichedMatches);

              return Column(
                children: [
                  // Stats header
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
                  
                  // Matches list
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
                                child: _buildMatchCardWithActions(match, context, umpireEmail),
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
        ),
      ],
    ),
  );
}


void _sortMatchesWithAvailable(List<Map<String, dynamic>> matches) {
  final now = DateTime.now();
  
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

    // Priority: Assigned matches first, then available
    if (aIsAssigned && !bIsAssigned) return -1;
    if (!aIsAssigned && bIsAssigned) return 1;
    
    // Within same assignment type: Live > Ready to Start > Scheduled > Completed
    if (aIsLive && !bIsLive) return -1;
    if (!aIsLive && bIsLive) return 1;
    if (aIsReady && !bIsReady && !bIsLive) return -1;
    if (!aIsReady && bIsReady && !aIsLive) return 1;
    if (!aIsLive && !aIsReady && !bIsLive && !bIsReady && !aIsCompleted && bIsCompleted) return -1;
    if (!aIsLive && !aIsReady && !bIsLive && !bIsReady && aIsCompleted && !bIsCompleted) return 1;
    
    // Within same status, sort by time
    if (aIsCompleted && bIsCompleted) return timeB.compareTo(timeA);
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

Widget _buildMatchCardWithActions(Map<String, dynamic> match, BuildContext context, String umpireEmail) {
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
  final matchStartTime = (match['startTime'] as Timestamp?)?.toDate();
  final now = DateTime.now();
  final isReady = !isLive && !isCompleted && 
                 matchStartTime != null && matchStartTime.isBefore(now);
  
  // Determine status
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
            : (isReady 
                ? const Color(0xFFF4A261).withOpacity(0.3)
                : _primaryColor.withOpacity(0.2)),
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
        onTap: isAssigned ? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MatchControlPage(
                tournamentId: match['tournamentId'],
                match: match,
                matchIndex: 0,
                isDoubles: isDoubles,
              ),
            ),
          );
        } : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with assignment status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isAssigned 
                          ? _primaryColor.withOpacity(0.15)
                          : _accentColor.withOpacity(0.15),
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
              
              // Teams
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
              
              // Tournament name
              Row(
                children: [
                  Icon(Icons.emoji_events_outlined, size: 16, color: _secondaryText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      match['tournamentName']?.toString() ?? 'Tournament',
                      style: GoogleFonts.poppins(
                        color: _secondaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Court and time slot
              Row(
                children: [
                  if (match['court'] != null) ...[
                    Icon(Icons.location_on_outlined, size: 16, color: _secondaryText),
                    const SizedBox(width: 4),
                    Text(
                      'Court ${match['court']}',
                      style: GoogleFonts.poppins(
                        color: _secondaryText,
                        fontSize: 14,
                      ),
                    ),
                    if (match['timeSlot'] != null) ...[
                      const SizedBox(width: 16),
                      Icon(Icons.access_time, size: 16, color: _secondaryText),
                      const SizedBox(width: 4),
                      Text(
                        match['timeSlot'],
                        style: GoogleFonts.poppins(
                          color: _secondaryText,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              
              if (matchStartTime != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 16, color: _secondaryText),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM d, y • h:mm a').format(matchStartTime),
                      style: GoogleFonts.poppins(
                        color: _secondaryText,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
              
              // Live scores or match result
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
                      Text(
                        'Winner: ${match['winner'] == (isDoubles ? 'team1' : 'player1') ? team1 : team2}',
                        style: GoogleFonts.poppins(
                          color: _successColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!isLive && !isCompleted && matchStartTime != null) ...[
                const SizedBox(height: 12),
                CountdownText(
                  matchTime: Timestamp.fromDate(matchStartTime),
                  tournamentTime: Timestamp.fromDate(matchStartTime),
                ),
              ],
              
              // Action section
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
                    Text(
                      isAssigned 
                          ? 'Tap to ${isLive ? 'manage match' : isCompleted ? 'view details' : 'start match'}'
                          : 'Available for assignment',
                      style: GoogleFonts.poppins(
                        color: _primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
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
    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Take Assignment',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Do you want to officiate this match?',
          style: GoogleFonts.poppins(),
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

    // Get current user details
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

    // Update the match with umpire details
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
        }

        enrichedMatches.add({
          ...match,
          'tournamentName': tournamentName,
          'timezone': timezoneName,
          'isDoubles': (match['matchType'] ?? '').toString().toLowerCase().contains('doubles'),
        });
      } catch (e) {
        debugPrint('Error loading tournament data: $e');
        enrichedMatches.add({
          ...match,
          'tournamentName': 'Unknown Tournament',
          'timezone': 'UTC',
          'isDoubles': false,
        });
      }
    }

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
            Text(
              'Live Score - Game $currentGame',
              style: GoogleFonts.poppins(
                color: _accentColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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