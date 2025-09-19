import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/tournaments/tournament_details_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:timezone/timezone.dart' as tz;

class JoinedTournamentsPage extends StatefulWidget {
  final String userId;

  const JoinedTournamentsPage({super.key, required this.userId});

  @override
  State<JoinedTournamentsPage> createState() => _JoinedTournamentsPageState();
}

class _JoinedTournamentsPageState extends State<JoinedTournamentsPage> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Add a small delay to show the loading state
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _withdrawFromTournament(BuildContext context, Tournament tournament) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Confirm Withdrawal',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF333333),
          ),
        ),
        content: Text(
          'Are you sure you want to withdraw from "${tournament.name}"? This action cannot be undone.',
          style: GoogleFonts.poppins(
            color: const Color(0xFF757575),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: const Color(0xFF757575),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Withdraw',
              style: GoogleFonts.poppins(
                color: const Color(0xFFE76F51),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Show loading indicator
      if (!context.mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C9A8B)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Withdrawing...',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF333333),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournament.id)
          .get();
      
      final data = tournamentDoc.data();
      if (data == null) throw Exception('Tournament data not found');

      final events = (data['events'] as List<dynamic>?)
              ?.map((e) => Event.fromFirestore(e as Map<String, dynamic>))
              .toList() ??
          [];
      
      if (!events.any((event) => event.participants.contains(widget.userId))) {
        throw Exception('You are not registered for any event in this tournament');
      }

      final updatedEvents = events
          .map((event) => Event(
                name: event.name,
                format: event.format,
                level: event.level,
                maxParticipants: event.maxParticipants,
                participants: event.participants.contains(widget.userId)
                    ? event.participants.where((id) => id != widget.userId).toList()
                    : event.participants,
                bornAfter: event.bornAfter,
                matchType: event.matchType,
                matches: event.matches,
                timeSlots: event.timeSlots,
                numberOfCourts: event.numberOfCourts,
              ))
          .toList();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournament.id)
          .update({
        'events': updatedEvents.map((e) => e.toFirestore()).toList(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Close loading dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (context.mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: Text(
            'Withdrawn Successfully',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFDFCFB),
            ),
          ),
          description: Text(
            'You have successfully withdrawn from "${tournament.name}".',
            style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB)),
          ),
          autoCloseDuration: const Duration(seconds: 3),
          backgroundColor: const Color(0xFF2A9D8F),
          foregroundColor: const Color(0xFFFDFCFB),
          alignment: Alignment.bottomCenter,
          borderRadius: BorderRadius.circular(12),
        );
      }
    } catch (e) {
      debugPrint('Error withdrawing from tournament ${tournament.id}: $e');
      
      // Close loading dialog if still open
      if (context.mounted) {
        Navigator.pop(context);
      }
      
      if (context.mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: Text(
            'Withdrawal Failed',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFDFCFB),
            ),
          ),
          description: Text(
            'Failed to withdraw from tournament: ${e.toString()}',
            style: GoogleFonts.poppins(color: const Color(0xFFFDFCFB)),
          ),
          autoCloseDuration: const Duration(seconds: 4),
          backgroundColor: const Color(0xFFE76F51),
          foregroundColor: const Color(0xFFFDFCFB),
          alignment: Alignment.bottomCenter,
          borderRadius: BorderRadius.circular(12),
        );
      }
    }
  }

  String _formatDateRange(DateTime start, DateTime end, String timezone) {
    try {
      final location = tz.getLocation(timezone);
      final startDate = tz.TZDateTime.from(start, location);
      final endDate = tz.TZDateTime.from(end, location);
      
      if (startDate.year == endDate.year && startDate.month == endDate.month) {
        return '${DateFormat('MMM dd').format(startDate)} - ${DateFormat('dd, yyyy').format(endDate)}';
      } else if (startDate.year == endDate.year) {
        return '${DateFormat('MMM dd').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}';
      }
      return '${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}';
    } catch (e) {
      // Fallback to UTC if timezone is invalid
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
        return const Color(0xFFF4A261);
      case 'Live':
        return const Color(0xFF2A9D8F);
      case 'Completed':
        return const Color(0xFF757575);
      default:
        return const Color(0xFFFDFCFB);
    }
  }

  void _showFullImageDialog(BuildContext context, String? imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
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
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF6C9A8B),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Close',
                style: GoogleFonts.poppins(
                  color: const Color(0xFFFDFCFB),
                  fontWeight: FontWeight.w600,
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
        case 'deadline-exceeded':
          return 'Request timed out. Please try again';
        default:
          return 'Failed to load tournaments. Error: ${error.message}';
      }
    }
    return 'An unexpected error occurred. Please try again.';
  }

  Widget _buildTournamentCard(Tournament tournament, int index) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final status = _getTournamentStatus(tournament);
    
    return AnimationConfiguration.staggeredList(
      position: index,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TournamentDetailsPage(
                    tournament: tournament,
                    creatorName: tournament.contactName ?? '',
                  ),
                ),
              );
            },
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              margin: EdgeInsets.only(bottom: isTablet ? 20 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: InkWell(
                          onTap: () => _showFullImageDialog(context, tournament.profileImage),
                          child: Container(
                            height: isTablet ? 200 : 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: tournament.profileImage != null &&
                                        tournament.profileImage!.isNotEmpty
                                    ? NetworkImage(tournament.profileImage!)
                                    : const AssetImage('assets/tournament_placholder.jpg')
                                        as ImageProvider,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 12 : 10,
                            vertical: isTablet ? 8 : 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            status,
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFFDFCFB),
                              fontSize: isTablet ? 14 : 12,
                              fontWeight: FontWeight.w600,
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
                            fontSize: isTablet ? 20 : 18,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: isTablet ? 12 : 8),
                        _buildInfoRow(
                          Icons.location_on_outlined,
                          '${tournament.venue}, ${tournament.city}',
                          isTablet,
                        ),
                        SizedBox(height: isTablet ? 8 : 4),
                        _buildInfoRow(
                          Icons.calendar_today_outlined,
                          _formatDateRange(
                            tournament.startDate,
                            tournament.endDate,
                            tournament.timezone,
                          ),
                          isTablet,
                        ),
                        SizedBox(height: isTablet ? 8 : 4),
                        _buildInfoRow(
                          Icons.sports_tennis_outlined,
                          tournament.gameFormat,
                          isTablet,
                        ),
                        SizedBox(height: isTablet ? 8 : 4),
                        if (tournament.events.isNotEmpty)
                          _buildInfoRow(
                            Icons.event_outlined,
                            '${tournament.events.length} Event${tournament.events.length > 1 ? 's' : ''}: ${tournament.events.map((e) => '${e.name} (${e.matchType})').take(2).join(', ')}${tournament.events.length > 2 ? '...' : ''}',
                            isTablet,
                          ),
                        SizedBox(height: isTablet ? 16 : 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Entry Fee: ₹${tournament.entryFee.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF333333),
                                fontSize: isTablet ? 16 : 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            ElevatedButton(
                              onPressed: tournament.registrationEnd.isAfter(DateTime.now()) && status != 'Completed'
                                  ? () => _withdrawFromTournament(context, tournament)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE76F51),
                                disabledBackgroundColor: const Color(0xFF757575),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 20 : 16,
                                  vertical: isTablet ? 12 : 8,
                                ),
                                elevation: 2,
                              ),
                              child: Text(
                                tournament.registrationEnd.isBefore(DateTime.now()) || status == 'Completed'
                                    ? 'Cannot Withdraw'
                                    : 'Withdraw',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFFDFCFB),
                                  fontSize: isTablet ? 14 : 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildInfoRow(IconData icon, String text, bool isTablet) {
    return Row(
      children: [
        Icon(
          icon,
          size: isTablet ? 18 : 16,
          color: const Color(0xFF757575),
        ),
        SizedBox(width: isTablet ? 8 : 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: const Color(0xFF757575),
              fontSize: isTablet ? 15 : 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: isTablet ? 80 : 64,
                  color: const Color(0xFF757575),
                ),
                SizedBox(height: isTablet ? 20 : 16),
                Text(
                  'No tournaments joined yet',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF333333),
                    fontSize: isTablet ? 20 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: isTablet ? 12 : 8),
                Text(
                  'Join a tournament to get started',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF757575),
                    fontSize: isTablet ? 16 : 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String errorMessage) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    return AnimationConfiguration.staggeredList(
      position: 0,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  color: const Color(0xFFE76F51),
                  size: isTablet ? 64 : 48,
                ),
                SizedBox(height: isTablet ? 20 : 16),
                Text(
                  'Error Loading Tournaments',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF333333),
                    fontSize: isTablet ? 20 : 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: isTablet ? 12 : 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 40 : 32),
                  child: Text(
                    errorMessage,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF757575),
                      fontSize: isTablet ? 16 : 14,
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 20 : 16),
                ElevatedButton(
                  onPressed: () => setState(() {
                    _isLoading = true;
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    });
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C9A8B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24 : 20,
                      vertical: isTablet ? 14 : 12,
                    ),
                  ),
                  child: Text(
                    'Try Again',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFFDFCFB),
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 16 : 14,
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    debugPrint('Current userId: ${widget.userId}');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF6C9A8B),
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFDFCFB),
        appBar: AppBar(
          title: AnimationConfiguration.staggeredList(
            position: 0,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              horizontalOffset: 50.0,
              child: FadeInAnimation(
                child: Text(
                  'Joined Tournaments',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFFDFCFB),
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 24 : 20,
                  ),
                ),
              ),
            ),
          ),
          leading: AnimationConfiguration.staggeredList(
            position: 1,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              horizontalOffset: -50.0,
              child: FadeInAnimation(
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Color(0xFFFDFCFB),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6C9A8B), Color(0xFFC1DADB)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        body: _isLoading
            ? AnimationConfiguration.staggeredList(
                position: 0,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: const Color(0xFF6C9A8B),
                            strokeWidth: isTablet ? 3 : 2.5,
                          ),
                          SizedBox(height: isTablet ? 20 : 16),
                          Text(
                            'Loading tournaments...',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF757575),
                              fontSize: isTablet ? 16 : 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('tournaments').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: const Color(0xFF6C9A8B),
                        strokeWidth: isTablet ? 3 : 2.5,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    debugPrint('Firestore Error: ${snapshot.error}');
                    return _buildErrorState(_getErrorMessage(snapshot.error));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState();
                  }

                  final tournaments = snapshot.data!.docs
                      .map((doc) {
                        try {
                          final data = doc.data() as Map<String, dynamic>;
                          return Tournament(
                            id: doc.id,
                            name: data['name'] ?? 'Unnamed Tournament',
                            description: data['description'],
                            venue: data['venue'] ?? '',
                            city: data['city'] ?? '',
                            startDate: (data['startDate'] as Timestamp).toDate(),
                            endDate: (data['endDate'] as Timestamp).toDate(),
                            registrationEnd: (data['registrationEnd'] as Timestamp).toDate(),
                            entryFee: (data['entryFee'] as num?)?.toDouble() ?? 0.0,
                            extraFee: (data['extraFee'] as num?)?.toDouble(),
                            canPayAtVenue: data['canPayAtVenue'] ?? false,
                            status: data['status'] ?? 'active',
                            createdBy: data['createdBy'] ?? '',
                            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
                                              ? (eventData['bornAfter'] as Timestamp).toDate()
                                              : null,
                                          matchType: eventData['matchType'] ?? 'Men\'s Singles',
                                          matches: List<String>.from(eventData['matches'] ?? []),
                                          timeSlots: List<String>.from(eventData['timeSlots'] ?? []),
                                          numberOfCourts: (eventData['numberOfCourts'] as num?)?.toInt() ?? 1,
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
                      .where((tournament) => tournament.events.any((event) => event.participants.contains(widget.userId)))
                      .toList();

                  if (tournaments.isEmpty) {
                    return _buildEmptyState();
                  }

                  return AnimationConfiguration.synchronized(
                    duration: const Duration(milliseconds: 600),
                    child: ListView.builder(
                      padding: EdgeInsets.all(isTablet ? 20 : 16),
                      itemCount: tournaments.length,
                      itemBuilder: (context, index) {
                        return _buildTournamentCard(tournaments[index], index);
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}