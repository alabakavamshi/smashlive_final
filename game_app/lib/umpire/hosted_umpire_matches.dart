import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:game_app/widgets/timezone_utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class UmpiredMatchesPage extends StatefulWidget {
  final String userId;

  const UmpiredMatchesPage({super.key, required this.userId});

  @override
  State<UmpiredMatchesPage> createState() => _UmpiredMatchesPageState();
}

class _UmpiredMatchesPageState extends State<UmpiredMatchesPage> {
  final currentUserEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
  final Color _primaryColor = const Color(0xFF6C9A8B);
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
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Umpired Matches',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
          
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collectionGroup('matches')
                .where('umpire.email', isEqualTo: currentUserEmail)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: _primaryColor),
                );
              }
              
              if (snapshot.hasError) {
                debugPrint('Error loading umpired matches: ${snapshot.error}');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: constraints.maxWidth < 600 ? 48 : 64, color: _errorColor),
                      SizedBox(height: constraints.maxWidth < 600 ? 16 : 24),
                      Text(
                        'Error loading matches',
                        style: GoogleFonts.poppins(
                          color: _errorColor,
                          fontSize: constraints.maxWidth < 600 ? 18 : 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: constraints.maxWidth < 600 ? 8 : 12),
                      Text(
                        'Please try again later',
                        style: GoogleFonts.poppins(
                          color: _secondaryText,
                          fontSize: constraints.maxWidth < 600 ? 14 : 16,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.gavel, 
                        size: constraints.maxWidth < 600 ? 64 : 80, 
                        color: _primaryColor.withOpacity(0.5)
                      ),
                      SizedBox(height: constraints.maxWidth < 600 ? 16 : 24),
                      Text(
                        'No umpired matches',
                        style: GoogleFonts.poppins(
                          color: _textColor,
                          fontSize: constraints.maxWidth < 600 ? 18 : 22,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: constraints.maxWidth < 600 ? 8 : 12),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: constraints.maxWidth < 600 ? 40 : 100
                        ),
                        child: Text(
                          'You have not been assigned as umpire for any matches yet',
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: constraints.maxWidth < 600 ? 14 : 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadMatchesWithTournamentData(snapshot.data!.docs),
                builder: (context, matchesSnapshot) {
                  if (matchesSnapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: _primaryColor),
                    );
                  }

                  final matches = matchesSnapshot.data ?? [];
                  if (matches.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.gavel, 
                            size: constraints.maxWidth < 600 ? 64 : 80, 
                            color: _primaryColor.withOpacity(0.5)
                          ),
                          SizedBox(height: constraints.maxWidth < 600 ? 16 : 24),
                          Text(
                            'No umpired matches',
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontSize: constraints.maxWidth < 600 ? 18 : 22,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  matches.sort((a, b) {
                    final aTime = a['startTime'] as DateTime? ?? DateTime.now();
                    final bTime = b['startTime'] as DateTime? ?? DateTime.now();
                    return bTime.compareTo(aTime);
                  });

                  return ListView.builder(
                    padding: EdgeInsets.all(horizontalPadding),
                    itemCount: matches.length,
                    itemBuilder: (context, index) => _buildMatchCard(
                      matches[index], 
                      constraints.maxWidth
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadMatchesWithTournamentData(List<QueryDocumentSnapshot> matchDocs) async {
    final matches = <Map<String, dynamic>>[];

    for (var matchDoc in matchDocs) {
      try {
        final matchData = matchDoc.data() as Map<String, dynamic>;
        final path = matchDoc.reference.path;
        final tournamentId = path.split('/')[1];

        final tournamentDoc = await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(tournamentId)
            .get();

        String tournamentName = 'Unknown Tournament';
        String gameFormat = 'Unknown Format';
        String timezone = 'UTC';
        String venue = 'Unknown venue';
        String city = 'Unknown city';

        if (tournamentDoc.exists) {
          final tournamentData = tournamentDoc.data()!;
          tournamentName = tournamentData['name'] ?? 'Unknown Tournament';
          gameFormat = tournamentData['gameFormat'] ?? 'Unknown Format';
          timezone = tournamentData['timezone'] ?? 'UTC';
          venue = tournamentData['venue'] ?? 'Unknown venue';
          city = tournamentData['city'] ?? 'Unknown city';
        }

        final timezoneAbbreviation = TimezoneUtils.getTimezoneAbbreviation(timezone);

        tz.Location tzLocation;
        try {
          tzLocation = tz.getLocation(timezone);
        } catch (e) {
          debugPrint('Invalid timezone $timezone, defaulting to UTC');
          tzLocation = tz.getLocation('UTC');
        }

        DateTime startTime;
        if (matchData['startTime'] is Timestamp) {
          startTime = (matchData['startTime'] as Timestamp).toDate();
        } else if (matchData['startTime'] is DateTime) {
          startTime = matchData['startTime'] as DateTime;
        } else {
          debugPrint('Invalid startTime format for match ${matchDoc.id}, defaulting to now');
          startTime = DateTime.now();
        }

        final startTimeInTz = tz.TZDateTime.from(startTime, tzLocation);

        matches.add({
          ...matchData,
          'matchId': matchDoc.id,
          'tournamentId': tournamentId,
          'tournamentName': tournamentName,
          'gameFormat': gameFormat,
          'startTime': startTime,
          'startTimeInTz': startTimeInTz,
          'timezone': timezone,
          'timezoneAbbreviation': timezoneAbbreviation,
          'venue': venue,
          'city': city,
          'isDoubles': (matchData['matchType'] ?? '').toString().toLowerCase().contains('doubles'),
        });
      } catch (e) {
        debugPrint('Error processing match ${matchDoc.id}: $e');
      }
    }

    return matches;
  }

  Widget _buildMatchCard(Map<String, dynamic> match, double screenWidth) {
    final isSmallScreen = screenWidth < 600;
    final isDoubles = match['isDoubles'] ?? false;
    final team1 = isDoubles
        ? (match['team1'] as List<dynamic>?)?.join(' & ') ?? 'Team 1'
        : match['player1'] ?? 'Player 1';
    final team2 = isDoubles
        ? (match['team2'] as List<dynamic>?)?.join(' & ') ?? 'Team 2'
        : match['player2'] ?? 'Player 2';
    
    final isCompleted = match['completed'] ?? false;
    final isLive = match['liveScores']?['isLive'] ?? false;
    final currentGame = match['liveScores']?['currentGame'] ?? 1;
    
    final team1Scores = List<int>.from(
        match['liveScores']?[isDoubles ? 'team1' : 'player1'] ?? [0, 0, 0]);
    final team2Scores = List<int>.from(
        match['liveScores']?[isDoubles ? 'team2' : 'player2'] ?? [0, 0, 0]);
    
    final startTime = match['startTime'] as DateTime;
    final timeSlot = match['timeSlot'] as String?;
    final tournamentName = match['tournamentName'];
    final gameFormat = match['gameFormat'];
    final round = match['round'] ?? 1;
    final timezone = match['timezone'] ?? 'UTC';
    final timezoneDisplay = match['timezoneAbbreviation'] ?? 'UTC';
    final venue = match['venue'];
    final city = match['city'];
    final location = venue != null && venue.isNotEmpty ? '$venue, $city' : city;

    // Parse timeSlot to get start time
    DateTime? displayTime;
    try {
      if (timeSlot != null && RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}$').hasMatch(timeSlot)) {
        final timeFormat = DateFormat('HH:mm');
        final slotStartTime = timeFormat.parse(timeSlot.split('-')[0]);
        final tzLocation = tz.getLocation(timezone);
        displayTime = tz.TZDateTime(
          tzLocation,
          startTime.year,
          startTime.month,
          startTime.day,
          slotStartTime.hour,
          slotStartTime.minute,
        );
        // Adjust for next day if timeSlot is earlier than current time
        final nowInTz = tz.TZDateTime.now(tzLocation);
        if (displayTime.isBefore(nowInTz) && displayTime.day == nowInTz.day) {
          displayTime = displayTime.add(const Duration(days: 1));
        }
      } else {
        displayTime = match['startTimeInTz'] as tz.TZDateTime;
      }
    } catch (e) {
      debugPrint('Error parsing timeSlot for match ${match['matchId']}: $e');
      displayTime = match['startTimeInTz'] as tz.TZDateTime;
    }

    final formattedTime = TimezoneUtils.formatDateWithAbbreviation(
            displayTime,
            timezone,
            dateFormat: 'MMM d, y',
            timeFormat: 'h:mm a',
          );

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isCompleted) {
      statusColor = _successColor;
      statusText = 'Completed';
      statusIcon = Icons.check_circle;
    } else if (isLive) {
      statusColor = _accentColor;
      statusText = 'In Progress';
      statusIcon = Icons.live_tv;
    } else {
      statusColor = _primaryColor;
      statusText = 'Scheduled';
      statusIcon = Icons.schedule;
    }

    return Container(
      margin: EdgeInsets.only(bottom: isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    tournamentName,
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 10 : 12,
                    vertical: isSmallScreen ? 6 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                    border: Border.all(color: _primaryColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Round $round',
                    style: GoogleFonts.poppins(
                      color: _primaryColor,
                      fontSize: isSmallScreen ? 12 : 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Text(
              '$team1 vs $team2',
              style: GoogleFonts.poppins(
                color: _textColor,
                fontSize: isSmallScreen ? 18 : 22,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Wrap(
              spacing: isSmallScreen ? 12 : 16,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sports_tennis, size: isSmallScreen ? 14 : 16, color: _secondaryText),
                    SizedBox(width: isSmallScreen ? 4 : 6),
                    Text(
                      gameFormat,
                      style: GoogleFonts.poppins(
                        color: _secondaryText,
                        fontSize: isSmallScreen ? 12 : 14,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: isSmallScreen ? 14 : 16, color: _secondaryText),
                    SizedBox(width: isSmallScreen ? 4 : 6),
                    Text(
                      timezoneDisplay,
                      style: GoogleFonts.poppins(
                        color: _secondaryText,
                        fontSize: isSmallScreen ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 12 : 16,
                vertical: isSmallScreen ? 6 : 8,
              ),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                border: Border.all(color: statusColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: isSmallScreen ? 14 : 16, color: statusColor),
                  SizedBox(width: isSmallScreen ? 6 : 8),
                  Text(
                    statusText,
                    style: GoogleFonts.poppins(
                      color: statusColor,
                      fontSize: isSmallScreen ? 12 : 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Wrap(
              spacing: isSmallScreen ? 16 : 24,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: isSmallScreen ? 14 : 16, color: _secondaryText),
                    SizedBox(width: isSmallScreen ? 8 : 10),
                    Text(
                      formattedTime.split(' • ')[0], // Display date only
                      style: GoogleFonts.poppins(
                        color: _secondaryText,
                        fontSize: isSmallScreen ? 14 : 16,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: isSmallScreen ? 14 : 16, color: _secondaryText),
                    SizedBox(width: isSmallScreen ? 8 : 10),
                    Text(
                      formattedTime.split(' • ')[1], // Display time with timezone abbreviation
                      style: GoogleFonts.poppins(
                        color: _secondaryText,
                        fontSize: isSmallScreen ? 14 : 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Row(
              children: [
                Icon(Icons.location_on, size: isSmallScreen ? 14 : 16, color: _secondaryText),
                SizedBox(width: isSmallScreen ? 8 : 10),
                Expanded(
                  child: Text(
                    location,
                    style: GoogleFonts.poppins(
                      color: _secondaryText,
                      fontSize: isSmallScreen ? 14 : 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (isLive) ...[
              SizedBox(height: isSmallScreen ? 12 : 16),
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                  border: Border.all(color: _accentColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.scoreboard, size: isSmallScreen ? 16 : 18, color: _accentColor),
                    SizedBox(width: isSmallScreen ? 8 : 12),
                    Text(
                      'Live Score: ${team1Scores[currentGame - 1]} - ${team2Scores[currentGame - 1]}',
                      style: GoogleFonts.poppins(
                        color: _accentColor,
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isCompleted && match['winner'] != null) ...[
              SizedBox(height: isSmallScreen ? 12 : 16),
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                decoration: BoxDecoration(
                  color: _successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                  border: Border.all(color: _successColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events, size: isSmallScreen ? 16 : 18, color: _successColor),
                    SizedBox(width: isSmallScreen ? 8 : 12),
                    Expanded(
                      child: Text(
                        'Winner: ${match['winner'] == (isDoubles ? 'team1' : 'player1') ? team1 : team2}',
                        style: GoogleFonts.poppins(
                          color: _successColor,
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}