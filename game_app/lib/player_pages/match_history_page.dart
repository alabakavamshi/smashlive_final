import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:game_app/tournaments/match_details_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:iconsax/iconsax.dart';

class MatchHistoryPage extends StatefulWidget {
  final String playerId;

  const MatchHistoryPage({super.key, required this.playerId});

  @override
  State<MatchHistoryPage> createState() => _MatchHistoryPageState();
}

class _MatchHistoryPageState extends State<MatchHistoryPage> {
  List<Map<String, dynamic>> _matches = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Color scheme
  final Color _darkBackground = const Color(0xFF121212);
  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _accentColor = const Color(0xFFF4A261);
  final Color _textColor = Colors.white;
  final Color _secondaryTextColor = const Color(0xFFC1DADB);
  final Color _inputBackground = const Color(0xFF1E1E1E);
  final Color _successColor = const Color(0xFF2A9D8F);
  final Color _errorColor = const Color(0xFFE76F51);

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _fetchPlayerMatches();
  }

  Future<void> _fetchPlayerMatches() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('Searching matches for player: ${widget.playerId}');

      // First, get all tournaments
      final tournamentsQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .get();

      debugPrint('Found ${tournamentsQuery.docs.length} tournaments');

      final List<Map<String, dynamic>> playerMatches = [];

      for (var tournamentDoc in tournamentsQuery.docs) {
        final tournamentData = tournamentDoc.data();
        final tournamentTimezone = tournamentData['timezone']?.toString() ?? 'Asia/Kolkata';
        
        tz.Location tzLocation;
        try {
          tzLocation = tz.getLocation(tournamentTimezone);
        } catch (e) {
          debugPrint('Invalid timezone for tournament ${tournamentDoc.id}: $tournamentTimezone, defaulting to Asia/Kolkata');
          tzLocation = tz.getLocation('Asia/Kolkata');
        }

        // Now check the matches subcollection
        final matchesSnapshot = await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(tournamentDoc.id)
            .collection('matches')
            .get();

        for (var matchDoc in matchesSnapshot.docs) {
          final match = matchDoc.data();
          
          debugPrint('Match: ${match['player1']} vs ${match['player2']}');
          debugPrint('Player IDs: ${match['player1Id']} | ${match['player2Id']}');
          debugPrint('Team IDs: ${match['team1Ids']} | ${match['team2Ids']}');

          if (_isPlayerInMatch(match) && match['completed'] == true) {
            debugPrint('MATCH FOUND FOR PLAYER ${widget.playerId}');
            
            final startTime = match['startTime'] as Timestamp? ?? tournamentData['startDate'] as Timestamp?;
            tz.TZDateTime? startTimeInTz;
            
            if (startTime != null) {
              startTimeInTz = tz.TZDateTime.from(startTime.toDate(), tzLocation);
            }
            
            playerMatches.add({
              ...match,
              'matchId': matchDoc.id,
              'tournamentId': tournamentDoc.id,
              'tournamentName': tournamentData['name'] ?? 'Unnamed Tournament',
              'startTime': startTime,
              'startTimeInTz': startTimeInTz,
              'timezone': tournamentTimezone,
              'endDate': tournamentData['endDate'] as Timestamp?,
              'venue': tournamentData['venue'] ?? 'Unknown Venue',
              'city': tournamentData['city'] ?? 'Unknown City',
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          _matches = playerMatches
            ..sort((a, b) {
              final aTime = a['startTimeInTz'] as tz.TZDateTime?;
              final bTime = b['startTimeInTz'] as tz.TZDateTime?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
          _isLoading = false;
          
          if (playerMatches.isEmpty) {
            _showToast('No completed matches found for this player', ToastificationType.info);
            debugPrint('NO MATCHES FOUND - Check player ID and match data');
          } else {
            debugPrint('Successfully found ${playerMatches.length} matches');
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching matches: $e\nStack: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load matches: ${e.toString()}';
          _isLoading = false;
        });
        _showToast('Error loading matches', ToastificationType.error);
      }
    }
  }

  void _showToast(String message, ToastificationType type) {
    toastification.show(
      context: context,
      type: type,
      title: Text(
        type == ToastificationType.error ? 'Error' : 'Info',
        style: GoogleFonts.poppins(
          color: _textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      description: Text(
        message,
        style: GoogleFonts.poppins(color: _textColor),
      ),
      autoCloseDuration: const Duration(seconds: 3),
      backgroundColor: type == ToastificationType.error ? _errorColor : _accentColor,
      foregroundColor: _textColor,
      alignment: Alignment.bottomCenter,
      borderRadius: BorderRadius.circular(12),
    );
  }

  bool _isPlayerInMatch(Map<String, dynamic> match) {
    final player1Id = match['player1Id']?.toString() ?? '';
    final player2Id = match['player2Id']?.toString() ?? '';
    final team1Ids = (match['team1Ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final team2Ids = (match['team2Ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    return player1Id == widget.playerId ||
           player2Id == widget.playerId ||
           team1Ids.contains(widget.playerId) ||
           team2Ids.contains(widget.playerId);
  }

  String _getMatchResult(Map<String, dynamic> match) {
    final liveScores = match['liveScores'] as Map<String, dynamic>? ?? {};
    final isDoubles = match['team1Ids'] != null && (match['team1Ids'] as List).isNotEmpty;
    
    final player1Scores = List<int>.from(liveScores[isDoubles ? 'team1' : 'player1'] ?? []);
    final player2Scores = List<int>.from(liveScores[isDoubles ? 'team2' : 'player2'] ?? []);
    final winner = match['winner']?.toString();
    final player1Id = match['player1Id']?.toString() ?? '';
    final player2Id = match['player2Id']?.toString() ?? '';
    final team1Ids = (match['team1Ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final team2Ids = (match['team2Ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    int player1Sets = 0;
    int player2Sets = 0;
    for (int i = 0; i < player1Scores.length && i < player2Scores.length; i++) {
      final p1Score = player1Scores[i];
      final p2Score = player2Scores[i];
      if ((p1Score >= 21 && (p1Score - p2Score) >= 2) || p1Score == 30) {
        player1Sets++;
      } else if ((p2Score >= 21 && (p2Score - p1Score) >= 2) || p2Score == 30) {
        player2Sets++;
      }
    }
    final setScore = '$player1Sets-$player2Sets';

    bool isPlayerWinner = false;
    if (isDoubles) {
      isPlayerWinner = (winner == 'team1' && team1Ids.contains(widget.playerId)) ||
                      (winner == 'team2' && team2Ids.contains(widget.playerId));
    } else {
      isPlayerWinner = (winner == 'player1' && player1Id == widget.playerId) ||
                      (winner == 'player2' && player2Id == widget.playerId);
    }

    return isPlayerWinner ? 'Won: $setScore' : 'Lost: $setScore';
  }

  Color _getResultColor(Map<String, dynamic> match) {
    final winner = match['winner']?.toString();
    final player1Id = match['player1Id']?.toString() ?? '';
    final player2Id = match['player2Id']?.toString() ?? '';
    final team1Ids = (match['team1Ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final team2Ids = (match['team2Ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final isDoubles = team1Ids.isNotEmpty && team2Ids.isNotEmpty;

    bool isPlayerWinner = false;
    if (isDoubles) {
      isPlayerWinner = (winner == 'team1' && team1Ids.contains(widget.playerId)) ||
                      (winner == 'team2' && team2Ids.contains(widget.playerId));
    } else {
      isPlayerWinner = (winner == 'player1' && player1Id == widget.playerId) ||
                      (winner == 'player2' && player2Id == widget.playerId);
    }

    return isPlayerWinner ? _successColor : _errorColor;
  }

  void _navigateToMatchDetails(Map<String, dynamic> match) {
    final isDoubles = match['team1Ids'] != null && 
                     (match['team1Ids'] as List).isNotEmpty && 
                     match['team2Ids'] != null && 
                     (match['team2Ids'] as List).isNotEmpty;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchDetailsPage(
          tournamentId: match['tournamentId'],
          match: match,
          matchIndex: _matches.indexOf(match),
          isCreator: false,
          isDoubles: isDoubles,
          isUmpire: false,
          onDeleteMatch: () {},
        ),
      ),
    );
  }

  Widget _buildMatchCard(BuildContext context, Map<String, dynamic> match, int index) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    final isDoubles = match['team1Ids'] != null && (match['team1Ids'] as List).isNotEmpty;
    final player1Name = isDoubles 
        ? (match['team1'] as List?)?.join(', ') ?? 'Team 1'
        : match['player1'] as String? ?? 'Player 1';
    final player2Name = isDoubles 
        ? (match['team2'] as List?)?.join(', ') ?? 'Team 2'
        : match['player2'] as String? ?? 'Player 2';
    
    final result = _getMatchResult(match);
    final resultColor = _getResultColor(match);
    final startTimeInTz = match['startTimeInTz'] as tz.TZDateTime?;
    
    String formattedTime = 'Date not available';
    if (startTimeInTz != null) {
      final timezoneDisplay = match['timezone'] == 'Asia/Kolkata' ? 'IST' : match['timezone'];
      formattedTime = '${DateFormat('MMM dd, yyyy, hh:mm a').format(startTimeInTz)} $timezoneDisplay';
    }

    return AnimationConfiguration.staggeredList(
      position: index,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Container(
            margin: EdgeInsets.only(bottom: isTablet ? 20 : 16),
            padding: EdgeInsets.all(isTablet ? 24 : 20),
            decoration: BoxDecoration(
              color: _inputBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _primaryColor.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match['tournamentName'] as String,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    fontSize: isTablet ? 18 : 16,
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        player1Name,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: _textColor,
                          fontSize: isTablet ? 16 : 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 16 : 12,
                        vertical: isTablet ? 8 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: resultColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: resultColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: isTablet ? 10 : 8,
                            height: isTablet ? 10 : 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: resultColor,
                            ),
                          ),
                          SizedBox(width: isTablet ? 8 : 6),
                          Text(
                            'COMPLETED',
                            style: GoogleFonts.poppins(
                              color: resultColor,
                              fontSize: isTablet ? 12 : 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 12 : 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        player2Name,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: _textColor,
                          fontSize: isTablet ? 16 : 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      result,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 20 : 18,
                        color: resultColor,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 12 : 8),
                Text(
                  'Time: $formattedTime',
                  style: GoogleFonts.poppins(
                    color: _secondaryTextColor,
                    fontSize: isTablet ? 14 : 12,
                  ),
                ),
                if (match['venue'] != null && match['venue'].isNotEmpty) ...[
                  SizedBox(height: isTablet ? 8 : 4),
                  Text(
                    'Venue: ${match['venue']}, ${match['city']}',
                    style: GoogleFonts.poppins(
                      color: _secondaryTextColor,
                      fontSize: isTablet ? 14 : 12,
                    ),
                  ),
                ],
                SizedBox(height: isTablet ? 20 : 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _navigateToMatchDetails(match),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      minimumSize: Size(double.infinity, isTablet ? 56 : 50),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    child: Text(
                      'View Match Details',
                      style: GoogleFonts.poppins(
                        color: _textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 18 : 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(isTablet ? 32 : 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Iconsax.warning_2,
                    color: _errorColor,
                    size: isTablet ? 64 : 48,
                  ),
                  SizedBox(height: isTablet ? 24 : 16),
                  Text(
                    'Error Loading Matches',
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: isTablet ? 22 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: isTablet ? 12 : 8),
                  Text(
                    _errorMessage ?? 'An unknown error occurred',
                    style: GoogleFonts.poppins(
                      color: _secondaryTextColor,
                      fontSize: isTablet ? 16 : 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isTablet ? 24 : 16),
                  ElevatedButton(
                    onPressed: _fetchPlayerMatches,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 32 : 24,
                        vertical: isTablet ? 16 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Try Again',
                      style: GoogleFonts.poppins(
                        color: _textColor,
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 16 : 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(isTablet ? 32 : 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Iconsax.story,
                    color: _secondaryTextColor.withOpacity(0.7),
                    size: isTablet ? 80 : 60,
                  ),
                  SizedBox(height: isTablet ? 24 : 16),
                  Text(
                    'No completed matches found',
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: isTablet ? 22 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: isTablet ? 12 : 8),
                  Text(
                    'Participate in tournaments to build your match history',
                    style: GoogleFonts.poppins(
                      color: _secondaryTextColor,
                      fontSize: isTablet ? 16 : 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      backgroundColor: _darkBackground,
      appBar: AppBar(
        title: Text(
          'Match History',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 24 : 20,
            color: _textColor,
          ),
        ),
        backgroundColor: _darkBackground,
        elevation: 0,
        leading: AnimationConfiguration.staggeredList(
          position: 0,
          duration: const Duration(milliseconds: 500),
          child: SlideAnimation(
            verticalOffset: 50.0,
            child: FadeInAnimation(
              child: IconButton(
                icon: Icon(Iconsax.arrow_left_2, color: _textColor, size: isTablet ? 28 : 24),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
        actions: [
          AnimationConfiguration.staggeredList(
            position: 1,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: IconButton(
                  icon: Icon(Iconsax.refresh, color: _textColor, size: isTablet ? 28 : 24),
                  onPressed: _fetchPlayerMatches,
                  tooltip: 'Refresh History',
                ),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: _darkBackground,
        padding: EdgeInsets.all(isTablet ? 28 : 24),
        child: _isLoading
            ? AnimationConfiguration.staggeredList(
                position: 0,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                        strokeWidth: isTablet ? 3.5 : 3,
                      ),
                    ),
                  ),
                ),
              )
            : _errorMessage != null
                ? _buildErrorState(context)
                : _matches.isEmpty
                    ? _buildEmptyState(context)
                    : AnimationConfiguration.synchronized(
                        duration: const Duration(milliseconds: 600),
                        child: ListView.builder(
                          itemCount: _matches.length,
                          itemBuilder: (context, index) {
                            return _buildMatchCard(context, _matches[index], index);
                          },
                        ),
                      ),
      ),
    );
  }
}