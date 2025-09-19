import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class SchedulePage extends StatefulWidget {
  final String userId;

  const SchedulePage({super.key, required this.userId});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _matches = [];
  Set<DateTime> _tournamentDates = {};
  Set<DateTime> _matchDates = {};
  bool _isLoading = true;
  String? _errorMessage;
  bool _filterMatchesOnly = false;

  // Color scheme
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
    _fetchTournamentsAndMatches();
  }

  Future<void> _fetchTournamentsAndMatches() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      final tournamentsQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('createdBy', isEqualTo: widget.userId)
          .where('status', whereIn: ['open', 'ongoing'])
          .orderBy('startDate', descending: false)
          .get();

      final List<Map<String, dynamic>> allMatches = [];
      final Set<DateTime> tournamentDates = {};
      final Set<DateTime> matchDates = {};

      for (var doc in tournamentsQuery.docs) {
        final data = doc.data();
        final tournamentId = doc.id;
        final tournamentName = data['name']?.toString() ?? 'Unnamed Tournament';
        final tournamentTimezone = data['timezone']?.toString() ?? 'Asia/Kolkata';
        
        tz.Location tzLocation;
        try {
          tzLocation = tz.getLocation(tournamentTimezone);
        } catch (e) {
          debugPrint('Invalid timezone for tournament $tournamentId: $tournamentTimezone, defaulting to Asia/Kolkata');
          tzLocation = tz.getLocation('Asia/Kolkata');
        }

        final startDate = (data['startDate'] as Timestamp).toDate();
        final startDateInTz = tz.TZDateTime.from(startDate, tzLocation);
        final endDate = (data['endDate'] as Timestamp?)?.toDate() ?? startDate;
        final endDateInTz = tz.TZDateTime.from(endDate, tzLocation);

        // Add tournament date range
        for (var date = startDateInTz;
            date.isBefore(endDateInTz.add(const Duration(days: 1)));
            date = date.add(const Duration(days: 1))) {
          tournamentDates.add(DateTime(date.year, date.month, date.day));
        }

        // Process matches from the matches subcollection
        try {
          final matchesSnapshot = await FirebaseFirestore.instance
              .collection('tournaments')
              .doc(tournamentId)
              .collection('matches')
              .get();

          for (var matchDoc in matchesSnapshot.docs) {
            final matchData = matchDoc.data();
            
            if (matchData['startTime'] != null) {
              final matchTime = (matchData['startTime'] as Timestamp).toDate();
              final matchTimeInTz = tz.TZDateTime.from(matchTime, tzLocation);
              final matchDate = DateTime(matchTimeInTz.year, matchTimeInTz.month, matchTimeInTz.day);

              matchDates.add(matchDate);

              if (matchDate.day == _selectedDate.day &&
                  matchDate.month == _selectedDate.month &&
                  matchDate.year == _selectedDate.year) {
                
                // Get player names
                String player1Name = 'TBD';
                String player2Name = 'TBD';
                
                if (matchData['player1Id'] != null) {
                  final player1Doc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(matchData['player1Id'])
                      .get();
                  if (player1Doc.exists) {
                    final player1Data = player1Doc.data()!;
                    player1Name = '${player1Data['firstName'] ?? ''} ${player1Data['lastName'] ?? ''}'.trim();
                  }
                }
                
                if (matchData['player2Id'] != null) {
                  final player2Doc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(matchData['player2Id'])
                      .get();
                  if (player2Doc.exists) {
                    final player2Data = player2Doc.data()!;
                    player2Name = '${player2Data['firstName'] ?? ''} ${player2Data['lastName'] ?? ''}'.trim();
                  }
                }

                allMatches.add({
                  'matchId': matchDoc.id,
                  'tournamentId': tournamentId,
                  'tournamentName': tournamentName,
                  'player1': player1Name,
                  'player2': player2Name,
                  'startTime': matchTime,
                  'startTimeInTz': matchTimeInTz,
                  'timezone': tournamentTimezone,
                  'status': matchData['status']?.toString() ?? 'scheduled',
                  'completed': matchData['completed'] ?? false,
                  'court': matchData['court']?.toString() ?? 'Court 1',
                  'round': matchData['round']?.toString() ?? 'Round 1',
                });
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching matches for tournament $tournamentId: $e');
        }
      }

      if (mounted) {
        setState(() {
          _matches = allMatches..sort((a, b) => (a['startTimeInTz'] as tz.TZDateTime).compareTo(b['startTimeInTz'] as tz.TZDateTime));
          _tournamentDates = tournamentDates;
          _matchDates = matchDates;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load matches: ${e.toString()}';
          _isLoading = false;
        });
      }
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
      setState(() {
        _selectedDate = picked;
      });
      await _fetchTournamentsAndMatches();
    }
  }

  Widget _buildCalendarRow() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth > 600;
    final double itemWidth = isTablet ? 70 : 60;
    
    return Column(
      children: [
        Container(
          height: isTablet ? 110 : 100,
          margin: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 12 : 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 60,
            itemBuilder: (context, index) {
              final date = DateTime.now().add(Duration(days: index - 30)); // Show 30 days before and 30 days after
              final dateOnly = DateTime(date.year, date.month, date.day);
              final isSelected = dateOnly.day == _selectedDate.day &&
                  dateOnly.month == _selectedDate.month &&
                  dateOnly.year == _selectedDate.year;

              final hasTournament = _tournamentDates.any((d) =>
                  d.day == dateOnly.day && d.month == dateOnly.month && d.year == dateOnly.year);

              final hasMatches = _matchDates.any((d) =>
                  d.day == dateOnly.day && d.month == dateOnly.month && d.year == dateOnly.year);

              if (_filterMatchesOnly && !hasMatches) {
                return const SizedBox.shrink();
              }

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDate = dateOnly;
                  });
                  _fetchTournamentsAndMatches();
                },
                child: Container(
                  width: itemWidth,
                  margin: EdgeInsets.only(right: isTablet ? 12 : 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _accentColor
                        : hasMatches
                            ? _successColor
                            : hasTournament
                                ? _moodColor
                                : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? _accentColor
                          : hasMatches
                              ? _successColor
                              : hasTournament
                                  ? _moodColor
                                  : _coolBlue,
                      width: hasMatches ? 2 : (hasTournament ? 1.5 : 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
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
                          fontSize: isTablet ? 12 : 10,
                        ),
                      ),
                      SizedBox(height: isTablet ? 6 : 4),
                      Text(
                        DateFormat('EEE').format(date),
                        style: GoogleFonts.poppins(
                          color: isSelected ? _backgroundColor : _secondaryText,
                          fontSize: isTablet ? 14 : 12,
                        ),
                      ),
                      SizedBox(height: isTablet ? 6 : 4),
                      Text(
                        DateFormat('dd').format(date),
                        style: GoogleFonts.poppins(
                          color: isSelected ? _backgroundColor : _textColor,
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.bold,
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
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: isTablet ? 16 : 12,
                children: [
                  _buildLegendItem(_successColor, 'Match Days'),
                  _buildLegendItem(_moodColor, 'Tournament Days'),
                  _buildLegendItem(_accentColor, 'Selected'),
                ],
              ),
              IconButton(
                icon: Icon(
                  Icons.filter_alt,
                  color: _filterMatchesOnly ? _accentColor : _secondaryText,
                  size: isTablet ? 28 : 24,
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
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isTablet ? 14 : 12,
          height: isTablet ? 14 : 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: isTablet ? 6 : 4),
        Text(
          text,
          style: GoogleFonts.poppins(
            color: _secondaryText, 
            fontSize: isTablet ? 14 : 12
          ),
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
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: backgroundColor,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match, bool isTablet) {
    final startTimeInTz = match['startTimeInTz'] as tz.TZDateTime;
    final timezoneDisplay = match['timezone'] == 'Asia/Kolkata' ? 'IST' : match['timezone'];
    final formattedTime = DateFormat('hh:mm a').format(startTimeInTz) + ' $timezoneDisplay';
    
    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 16 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.all(isTablet ? 20 : 16),
        leading: Container(
          width: isTablet ? 60 : 50,
          height: isTablet ? 60 : 50,
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sports_tennis,
            color: _primaryColor,
            size: isTablet ? 28 : 24,
          ),
        ),
        title: Text(
          '${match['player1']} vs ${match['player2']}',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 18 : 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: isTablet ? 8 : 6),
            Row(
              children: [
                Icon(Icons.event, color: _secondaryText, size: isTablet ? 18 : 16),
                SizedBox(width: isTablet ? 8 : 6),
                Text(
                  match['tournamentName'],
                  style: GoogleFonts.poppins(
                    color: _secondaryText,
                    fontSize: isTablet ? 14 : 12,
                  ),
                ),
              ],
            ),
            SizedBox(height: isTablet ? 6 : 4),
            Row(
              children: [
                Icon(Icons.access_time, color: _secondaryText, size: isTablet ? 18 : 16),
                SizedBox(width: isTablet ? 8 : 6),
                Text(
                  formattedTime,
                  style: GoogleFonts.poppins(
                    color: _secondaryText,
                    fontSize: isTablet ? 14 : 12,
                  ),
                ),
              ],
            ),
            SizedBox(height: isTablet ? 6 : 4),
            Row(
              children: [
                Icon(Icons.place, color: _secondaryText, size: isTablet ? 18 : 16),
                SizedBox(width: isTablet ? 8 : 6),
                Text(
                  match['court'],
                  style: GoogleFonts.poppins(
                    color: _secondaryText,
                    fontSize: isTablet ? 14 : 12,
                  ),
                ),
              ],
            ),
            SizedBox(height: isTablet ? 8 : 6),
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8, vertical: isTablet ? 4 : 3),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    match['round'],
                    style: GoogleFonts.poppins(
                      color: _accentColor,
                      fontSize: isTablet ? 12 : 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: isTablet ? 12 : 8),
                _buildMatchStatusChip(match['status']),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth > 600;
    
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        title: Text(
          'Match Schedule',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isTablet ? 24 : 20,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white, size: isTablet ? 30 : 24),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.calendar_month, color: Colors.white, size: isTablet ? 28 : 24),
            onPressed: () => _selectDate(context),
            tooltip: 'Open calendar',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white, size: isTablet ? 28 : 24),
            onPressed: _fetchTournamentsAndMatches,
            tooltip: 'Refresh schedule',
          ),
        ],
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
                      padding: EdgeInsets.all(isTablet ? 24 : 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: _errorColor),
                          SizedBox(height: isTablet ? 24 : 16),
                          Text(
                            'Error Loading Schedule',
                            style: GoogleFonts.poppins(
                              color: _errorColor,
                              fontSize: isTablet ? 22 : 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: isTablet ? 12 : 8),
                          Text(
                            _errorMessage!,
                            style: GoogleFonts.poppins(
                              color: _secondaryText,
                              fontSize: isTablet ? 16 : 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: isTablet ? 24 : 16),
                          ElevatedButton(
                            onPressed: _fetchTournamentsAndMatches,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 32 : 24,
                                vertical: isTablet ? 16 : 12,
                              ),
                            ),
                            child: Text(
                              'Try Again',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500,
                                fontSize: isTablet ? 16 : 14,
                              ),
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
                            Icon(
                              Icons.event_busy, 
                              size: isTablet ? 64 : 48, 
                              color: _secondaryText.withOpacity(0.5)
                            ),
                            SizedBox(height: isTablet ? 24 : 16),
                            Text(
                              'No matches scheduled for',
                              style: GoogleFonts.poppins(
                                color: _secondaryText,
                                fontSize: isTablet ? 20 : 18,
                              ),
                            ),
                            SizedBox(height: isTablet ? 8 : 6),
                            Text(
                              DateFormat('MMMM dd, yyyy').format(_selectedDate),
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontSize: isTablet ? 24 : 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(isTablet ? 20 : 16),
                        itemCount: _matches.length,
                        itemBuilder: (context, index) {
                          return _buildMatchCard(_matches[index], isTablet);
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
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}