import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:game_app/umpire/matchcontrolpage.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class UmpireSchedulePage extends StatefulWidget {
  final String userId;
  final String userEmail;

  const UmpireSchedulePage({super.key, required this.userId, required this.userEmail});

  @override
  State<UmpireSchedulePage> createState() => _UmpireSchedulePageState();
}

class _UmpireSchedulePageState extends State<UmpireSchedulePage> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _matches = [];
  Set<DateTime> _matchDates = {};
  bool _isLoading = true;
  String? _errorMessage;
  bool _filterMatchesOnly = false;

  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _accentColor = const Color(0xFFF4A261);
  final Color _textColor = const Color(0xFF333333);
  final Color _secondaryText = const Color(0xFF757575);
  final Color _successColor = const Color(0xFF2A9D8F);
  final Color _moodColor = const Color(0xFFE9C46A);
  final Color _coolBlue = const Color(0xFFA8DADC);
  final Color _errorColor = const Color(0xFFE76F51);
  final Color _backgroundColor = const Color(0xFFFDFCFB);

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    _fetchMatches();
  }

  Future<void> _fetchMatches() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _matches = [];
      _matchDates = {};
    });

    try {
      // Query all matches assigned to this umpire using collectionGroup
      final matchesSnapshot = await FirebaseFirestore.instance
          .collectionGroup('matches')
          .where('umpire.email', isEqualTo: widget.userEmail.toLowerCase().trim())
          .get();

      debugPrint('Found ${matchesSnapshot.docs.length} matches for umpire schedule');

      final List<Map<String, dynamic>> allMatches = [];
      final Set<DateTime> matchDates = {};

      for (var matchDoc in matchesSnapshot.docs) {
        try {
          final matchData = matchDoc.data();
          final path = matchDoc.reference.path;
          final tournamentId = path.split('/')[1]; // Extract tournament ID from path

          // Load tournament data
          final tournamentDoc = await FirebaseFirestore.instance
              .collection('tournaments')
              .doc(tournamentId)
              .get();

          if (!tournamentDoc.exists) {
            debugPrint('Tournament $tournamentId not found');
            continue;
          }

          final tournamentData = tournamentDoc.data()!;
          final tournamentTimezone = tournamentData['timezone']?.toString() ?? 'Asia/Kolkata';
          
          tz.Location tzLocation;
          try {
            tzLocation = tz.getLocation(tournamentTimezone);
          } catch (e) {
            debugPrint('Invalid timezone $tournamentTimezone, defaulting to Asia/Kolkata');
            tzLocation = tz.getLocation('Asia/Kolkata');
          }

          final matchStartTime = matchData['startTime'] as Timestamp?;
          if (matchStartTime == null) continue;

          final matchTime = matchStartTime.toDate();
          final matchTimeInTz = tz.TZDateTime.from(matchTime, tzLocation);
          final matchDateOnly = DateTime(matchTimeInTz.year, matchTimeInTz.month, matchTimeInTz.day);

          matchDates.add(matchDateOnly);

          // Check if this match is for the selected date
          if (matchDateOnly.isAtSameMomentAs(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day))) {
            final isDoubles = (matchData['matchType'] ?? '').toString().toLowerCase().contains('doubles');
            
            allMatches.add({
              'matchId': matchDoc.id,
              'tournamentId': tournamentId,
              'tournamentName': tournamentData['name']?.toString() ?? 'Unnamed Tournament',
              'player1': isDoubles 
                  ? (matchData['team1'] as List<dynamic>?)?.join(' & ') ?? 'Team 1'
                  : matchData['player1']?.toString() ?? 'TBD',
              'player2': isDoubles
                  ? (matchData['team2'] as List<dynamic>?)?.join(' & ') ?? 'Team 2' 
                  : matchData['player2']?.toString() ?? 'TBD',
              'startTime': matchTime,
              'startTimeInTz': matchTimeInTz,
              'timezone': tournamentTimezone,
              'status': matchData['completed'] == true
                  ? 'completed'
                  : (matchData['liveScores']?['isLive'] == true ? 'ongoing' : 'scheduled'),
              'location': _buildLocationString(tournamentData),
              'match': matchData,
              'isDoubles': isDoubles,
              'court': matchData['court'],
              'timeSlot': matchData['timeSlot'],
              'eventId': matchData['eventId'],
              'round': matchData['round'] ?? 1,
            });
          }
        } catch (e) {
          debugPrint('Error processing match ${matchDoc.id}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _matches = allMatches..sort((a, b) => (a['startTimeInTz'] as tz.TZDateTime).compareTo(b['startTimeInTz'] as tz.TZDateTime));
          _matchDates = matchDates;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching matches: $e\nStack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load matches: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _buildLocationString(Map<String, dynamic> tournamentData) {
    final venue = tournamentData['venue']?.toString();
    final city = tournamentData['city']?.toString();
    
    if (venue != null && venue.isNotEmpty && city != null && city.isNotEmpty) {
      return '$venue, $city';
    } else if (city != null && city.isNotEmpty) {
      return city;
    } else {
      return 'Unknown Location';
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: _filterMatchesOnly
          ? (day) => _matchDates.any((d) => d.isAtSameMomentAs(DateTime(day.year, day.month, day.day)))
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accentColor,
              onPrimary: _backgroundColor,
              surface: Colors.white,
              onSurface: _textColor,
            ),
            dialogBackgroundColor: _backgroundColor,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      if (mounted) {
        setState(() {
          _selectedDate = picked;
        });
        await _fetchMatches();
      }
    }
  }

  Widget _buildCalendarRow() {
    return Column(
      children: [
        Container(
          height: 100,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 60,
            itemBuilder: (context, index) {
              final date = DateTime.now().add(Duration(days: index));
              final dateOnly = DateTime(date.year, date.month, date.day);
              final isSelected = dateOnly.isAtSameMomentAs(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day));
              final hasMatches = _matchDates.any((d) => d.isAtSameMomentAs(dateOnly));

              if (_filterMatchesOnly && !hasMatches) {
                return const SizedBox.shrink();
              }

              return GestureDetector(
                onTap: () {
                  if (mounted) {
                    setState(() {
                      _selectedDate = dateOnly;
                      _fetchMatches();
                    });
                  }
                },
                child: Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _accentColor
                        : hasMatches
                            ? _successColor
                            : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? _accentColor
                          : hasMatches
                              ? _successColor
                              : _coolBlue,
                      width: hasMatches ? 2 : 1,
                    ),
                    boxShadow: hasMatches
                        ? [
                            BoxShadow(
                              color: _successColor.withOpacity(0.3),
                              blurRadius: 4,
                              spreadRadius: 1,
                            )
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('MMM').format(date).toUpperCase(),
                        style: GoogleFonts.poppins(
                          color: isSelected ? _backgroundColor : _secondaryText,
                          fontSize: 10,
                          fontWeight: hasMatches ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEE').format(date),
                        style: GoogleFonts.poppins(
                          color: isSelected ? _backgroundColor : _secondaryText,
                          fontSize: 12,
                          fontWeight: hasMatches ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd').format(date),
                        style: GoogleFonts.poppins(
                          color: isSelected ? _backgroundColor : _textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (hasMatches)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSelected ? _backgroundColor : _successColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildLegendItem(_successColor, 'Match Days'),
                  const SizedBox(width: 16),
                  _buildLegendItem(_accentColor, 'Selected'),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.filter_alt,
                      color: _filterMatchesOnly ? _accentColor : _secondaryText,
                    ),
                    onPressed: () {
                      setState(() {
                        _filterMatchesOnly = !_filterMatchesOnly;
                      });
                    },
                    tooltip: 'Show only days with matches',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.poppins(color: _secondaryText, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMatchStatusChip(String status) {
    Color backgroundColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'completed':
        backgroundColor = _successColor;
        textColor = _backgroundColor;
        break;
      case 'ongoing':
        backgroundColor = _moodColor;
        textColor = _textColor;
        break;
      case 'cancelled':
        backgroundColor = _errorColor;
        textColor = _backgroundColor;
        break;
      default: // scheduled
        backgroundColor = _coolBlue;
        textColor = _textColor;
    }

    return Chip(
      label: Text(
        status.capitalize(),
        style: GoogleFonts.poppins(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: backgroundColor,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: Color(0xFF6C9A8B),
        elevation: 0,
        title: Text(
          'Umpire Schedule',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _secondaryText),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.calendar_month, color: _secondaryText),
            onPressed: () => _selectDate(context),
            tooltip: 'Open calendar',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: _secondaryText),
            onPressed: _fetchMatches,
            tooltip: 'Refresh schedule',
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6C9A8B), Color(0xFF6C9A8B)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildCalendarRow(),
          if (_isLoading)
            LinearProgressIndicator(
              minHeight: 2,
              color: _accentColor,
            ),
          Expanded(
            child: _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: _errorColor),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load schedule',
                            style: GoogleFonts.poppins(
                              color: _errorColor, 
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: GoogleFonts.poppins(color: _secondaryText, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchMatches,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              'Retry',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _matches.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_busy, size: 48, color: _secondaryText),
                            const SizedBox(height: 16),
                            Text(
                              'No matches scheduled for',
                              style: GoogleFonts.poppins(color: _secondaryText, fontSize: 18),
                            ),
                            Text(
                              DateFormat('MMMM dd, yyyy').format(_selectedDate),
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchMatches,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                'Refresh Data',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _matches.length,
                        itemBuilder: (context, index) {
                          final match = _matches[index];
                          final startTimeInTz = match['startTimeInTz'] as tz.TZDateTime;
                          final timezoneDisplay = match['timezone'] == 'Asia/Kolkata' ? 'IST' : match['timezone'];
                          final formattedTime = DateFormat('hh:mm a').format(startTimeInTz) + ' $timezoneDisplay';
                          
                          return Card(
                            color: Colors.white,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                            shadowColor: Colors.black.withOpacity(0.1),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${match['player1']} vs ${match['player2']}',
                                          style: GoogleFonts.poppins(
                                            color: _textColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      _buildMatchStatusChip(match['status']),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // Tournament and Round info
                                  Row(
                                    children: [
                                      Icon(Icons.emoji_events_outlined, color: _secondaryText, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          match['tournamentName'],
                                          style: GoogleFonts.poppins(color: _secondaryText, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _primaryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Round ${match['round']}',
                                          style: GoogleFonts.poppins(
                                            color: _primaryColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 8),
                                  
                                  // Court, Time Slot, and Time info
                                  Row(
                                    children: [
                                      if (match['court'] != null) ...[
                                        Icon(Icons.location_on_outlined, color: _secondaryText, size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Court ${match['court']}',
                                          style: GoogleFonts.poppins(color: _secondaryText, fontSize: 12),
                                        ),
                                        const SizedBox(width: 12),
                                      ],
                                      Icon(Icons.access_time, color: _secondaryText, size: 16),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          match['timeSlot'] ?? formattedTime,
                                          style: GoogleFonts.poppins(color: _secondaryText, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.info_outline, color: _accentColor, size: 20),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => MatchControlPage(
                                                tournamentId: match['tournamentId'],
                                                match: match['match'],
                                                matchIndex: 0, // This might need adjustment based on your MatchControlPage requirements
                                                isDoubles: match['isDoubles'],
                                              ),
                                            ),
                                          );
                                        },
                                        tooltip: 'View match details',
                                      ),
                                    ],
                                  ),
                                  
                                  // Location
                                  Row(
                                    children: [
                                      Icon(Icons.place_outlined, color: _secondaryText, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          match['location'],
                                          style: GoogleFonts.poppins(color: _secondaryText, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  // Event ID (for debugging/reference)
                                  if (match['eventId'] != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.category_outlined, color: _secondaryText, size: 14),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Event: ${match['eventId']}',
                                          style: GoogleFonts.poppins(
                                            color: _secondaryText.withOpacity(0.8),
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}