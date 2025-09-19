import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class TournamentHistoryPage extends StatelessWidget {
  final String userId;

  const TournamentHistoryPage({super.key, required this.userId});

  String _formatDateRange(DateTime start, DateTime end, String timezone) {
    try {
      final tzLocation = tz.getLocation(timezone);
      final startDate = tz.TZDateTime.from(start, tzLocation);
      final endDate = tz.TZDateTime.from(end, tzLocation);
      
      if (startDate.year == endDate.year && startDate.month == endDate.month) {
        return '${DateFormat('MMM dd').format(startDate)} - ${DateFormat('dd, yyyy').format(endDate)}';
      } else if (startDate.year == endDate.year) {
        return '${DateFormat('MMM dd').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}';
      }
      return '${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}';
    } catch (e) {
      // Fallback if timezone conversion fails
      if (start.year == end.year && start.month == end.month) {
        return '${DateFormat('MMM dd').format(start)} - ${DateFormat('dd, yyyy').format(end)}';
      } else if (start.year == end.year) {
        return '${DateFormat('MMM dd').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}';
      }
      return '${DateFormat('MMM dd, yyyy').format(start)} - ${DateFormat('MMM dd, yyyy').format(end)}';
    }
  }

  String _getTournamentStatus(Tournament tournament) {
    final now = DateTime.now();
    if (now.isBefore(tournament.startDate)) {
      return 'Upcoming';
    } else if (now.isAfter(tournament.startDate) && now.isBefore(tournament.endDate)) {
      return 'Live';
    } else {
      return 'Completed';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Upcoming':
        return const Color(0xFFF4A261); // Accent color
      case 'Live':
        return const Color(0xFF2A9D8F); // Success color
      case 'Completed':
        return const Color(0xFF757575); // Secondary text color
      default:
        return const Color(0xFFFDFCFB); // Background color
    }
  }

  void _showFullImageDialog(BuildContext context, String? imageUrl) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth > 600;
    
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(isTablet ? 40 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
                maxWidth: MediaQuery.of(context).size.width * (isTablet ? 0.8 : 0.9),
              ),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        'assets/tournament_placeholder.jpg',
                        fit: BoxFit.contain,
                      ),
                    )
                  : Image.asset(
                      'assets/tournament_placeholder.jpg',
                      fit: BoxFit.contain,
                    ),
            ),
            SizedBox(height: isTablet ? 20 : 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 24 : 16,
                  vertical: isTablet ? 12 : 8,
                ),
                backgroundColor: const Color(0xFF6C9A8B), // Primary color
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Close',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 16 : 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getErrorMessage(dynamic error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You don\'t have permission to access tournaments';
        case 'unavailable':
          return 'Network is unavailable. Please check your connection';
        default:
          return 'Failed to load tournaments. Error: ${error.message}';
      }
    }
    return 'An unexpected error occurred. Please try again.';
  }

  Widget _buildTournamentCard(BuildContext context, Tournament tournament, bool isTablet) {
    final status = _getTournamentStatus(tournament);
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: EdgeInsets.only(bottom: isTablet ? 20 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: InkWell(
                  onTap: () => _showFullImageDialog(context, tournament.profileImage),
                  child: Container(
                    height: isTablet ? 160 : 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: tournament.profileImage != null &&
                                tournament.profileImage!.isNotEmpty
                            ? NetworkImage(tournament.profileImage!)
                            : const AssetImage('assets/tournament_placeholder.jpg')
                                as ImageProvider,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: isTablet ? 12 : 8,
                right: isTablet ? 12 : 8,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 12 : 8,
                    vertical: isTablet ? 6 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: isTablet ? 14 : 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tournament.name,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF333333),
                    fontSize: isTablet ? 22 : 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: isTablet ? 12 : 8),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: isTablet ? 20 : 16,
                      color: const Color(0xFF757575),
                    ),
                    SizedBox(width: isTablet ? 8 : 4),
                    Expanded(
                      child: Text(
                        '${tournament.venue}, ${tournament.city}',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF757575),
                          fontSize: isTablet ? 16 : 14,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 8 : 4),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: isTablet ? 20 : 16,
                      color: const Color(0xFF757575),
                    ),
                    SizedBox(width: isTablet ? 8 : 4),
                    Text(
                      _formatDateRange(
                        tournament.startDate,
                        tournament.endDate,
                        tournament.timezone,
                      ),
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF757575),
                        fontSize: isTablet ? 16 : 14,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 8 : 4),
                Row(
                  children: [
                    Icon(
                      Icons.sports_tennis_outlined,
                      size: isTablet ? 20 : 16,
                      color: const Color(0xFF757575),
                    ),
                    SizedBox(width: isTablet ? 8 : 4),
                    Text(
                      tournament.gameFormat,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF757575),
                        fontSize: isTablet ? 16 : 14,
                      ),
                    ),
                  ],
                ),
                if (tournament.events.isNotEmpty) ...[
                  SizedBox(height: isTablet ? 8 : 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: isTablet ? 20 : 16,
                        color: const Color(0xFF757575),
                      ),
                      SizedBox(width: isTablet ? 8 : 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${tournament.events.length} Event${tournament.events.length > 1 ? 's' : ''}:',
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF757575),
                                fontSize: isTablet ? 16 : 14,
                              ),
                            ),
                            SizedBox(height: isTablet ? 4 : 2),
                            ...tournament.events.map((event) => Text(
                              '• ${event.name} (${event.matchType})',
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF757575),
                                fontSize: isTablet ? 14 : 12,
                              ),
                            )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: isTablet ? 12 : 8),
                Text(
                  'Entry Fee: ₹${tournament.entryFee.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF333333),
                    fontSize: isTablet ? 16 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, dynamic error, bool isTablet) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 32 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: const Color(0xFFE76F51),
              size: isTablet ? 64 : 48,
            ),
            SizedBox(height: isTablet ? 24 : 16),
            Text(
              'Error Loading Tournaments',
              style: GoogleFonts.poppins(
                color: const Color(0xFF333333),
                fontSize: isTablet ? 22 : 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: isTablet ? 12 : 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 40 : 32),
              child: Text(
                _getErrorMessage(error),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF757575),
                  fontSize: isTablet ? 16 : 14,
                ),
              ),
            ),
            SizedBox(height: isTablet ? 24 : 16),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C9A8B),
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
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: isTablet ? 16 : 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isTablet) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 32 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: isTablet ? 80 : 64,
              color: const Color(0xFF757575).withOpacity(0.7),
            ),
            SizedBox(height: isTablet ? 24 : 16),
            Text(
              'No tournament history',
              style: GoogleFonts.poppins(
                color: const Color(0xFF333333),
                fontSize: isTablet ? 22 : 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: isTablet ? 12 : 8),
            Text(
              'Participate in tournaments to view your history',
              style: GoogleFonts.poppins(
                color: const Color(0xFF757575),
                fontSize: isTablet ? 16 : 14,
              ),
              textAlign: TextAlign.center,
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
      backgroundColor: const Color(0xFFFDFCFB),
      appBar: AppBar(
        title: Text(
          'Tournament History',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 24 : 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: const Color(0xFF6C9A8B),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tournaments')
            .orderBy('startDate', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: const Color(0xFFF4A261),
                strokeWidth: isTablet ? 3.0 : 2.5,
              ),
            );
          }

          if (snapshot.hasError) {
            debugPrint('Firestore Error: ${snapshot.error}');
            return _buildErrorState(context, snapshot.error, isTablet);
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState(context, isTablet);
          }

          final tournaments = snapshot.data!.docs
              .map((doc) {
                try {
                  final data = doc.data() as Map<String, dynamic>;
                  
                  // Helper function to safely convert Timestamp to DateTime
                  DateTime safeTimestampToDate(dynamic value, [DateTime? fallback]) {
                    if (value is Timestamp) {
                      return value.toDate();
                    }
                    return fallback ?? DateTime.now();
                  }

                  return Tournament(
                    id: doc.id,
                    name: data['name'] ?? 'Unnamed Tournament',
                    description: data['description'],
                    venue: data['venue'] ?? '',
                    city: data['city'] ?? '',
                    startDate: safeTimestampToDate(data['startDate']),
                    endDate: safeTimestampToDate(data['endDate']),
                    registrationEnd: safeTimestampToDate(data['registrationEnd']),
                    entryFee: (data['entryFee'] as num?)?.toDouble() ?? 0.0,
                    extraFee: (data['extraFee'] as num?)?.toDouble(),
                    canPayAtVenue: data['canPayAtVenue'] ?? false,
                    status: data['status'] ?? 'active',
                    createdBy: data['createdBy'] ?? '',
                    createdAt: safeTimestampToDate(data['createdAt']),
                    rules: data['rules'] ?? '',
                    gameFormat: data['gameFormat'] ?? 'Unknown Format',
                    gameType: data['gameType'] ?? 'Unknown Type',
                    bringOwnEquipment: data['bringOwnEquipment'] ?? false,
                    costShared: data['costShared'] ?? false,
                    profileImage: data['profileImage'],
                    sponsorImage: data['sponsorImage'],
                    contactName: data['contactName'],
                    contactNumber: data['contactNumber'],
                    timezone: data['timezone'] ?? 'UTC',
                    events: (data['events'] as List<dynamic>?)
                            ?.map((eventData) => Event(
                                  name: eventData['name'] ?? '',
                                  format: eventData['format'] ?? '',
                                  level: eventData['level'] ?? 'All Levels',
                                  maxParticipants: (eventData['maxParticipants'] as num?)?.toInt() ?? 1,
                                  participants: List<String>.from(eventData['participants'] ?? []),
                                  bornAfter: eventData['bornAfter'] != null
                                      ? safeTimestampToDate(eventData['bornAfter'])
                                      : null,
                                  matchType: eventData['matchType'] ?? 'Men\'s Singles',
                                  matches: List<String>.from(eventData['matches'] ?? []),
                                ))
                            .toList() ??
                        [],
                  );
                } catch (e) {
                  debugPrint('Error parsing tournament ${doc.id}: $e');
                  return null;
                }
              })
              .where((tournament) => tournament != null)
              .cast<Tournament>()
              .where((tournament) => tournament.events.any((event) => event.participants.contains(userId)))
              .toList();

          if (tournaments.isEmpty) {
            return _buildEmptyState(context, isTablet);
          }

          return ListView.builder(
            padding: EdgeInsets.all(isTablet ? 20 : 16),
            itemCount: tournaments.length,
            itemBuilder: (context, index) {
              final tournament = tournaments[index];
              return _buildTournamentCard(context, tournament, isTablet);
            },
          );
        },
      ),
    );
  }
}