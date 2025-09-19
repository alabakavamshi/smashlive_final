import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:toastification/toastification.dart';

class ManagePlayersPage extends StatefulWidget {
  final String userId;

  const ManagePlayersPage({super.key, required this.userId});

  @override
  State<ManagePlayersPage> createState() => _ManagePlayersPageState();
}

class _ManagePlayersPageState extends State<ManagePlayersPage> {
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Color scheme
  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _accentColor = const Color(0xFFF4A261);
  final Color _textColor = const Color(0xFF333333);
  final Color _secondaryText = const Color(0xFF757575);
  final Color _successColor = const Color(0xFF2A9D8F);
  final Color _errorColor = const Color(0xFFE76F51);
  final Color _backgroundColor = const Color(0xFFFDFCFB);

  @override
  void initState() {
    super.initState();
    _fetchParticipants();
  }

  Future<void> _fetchParticipants() async {
    setState(() => _isLoading = true);
    
    try {
      // Get tournaments created by this user
      final tournamentsQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('createdBy', isEqualTo: widget.userId)
          .get();

      final List<Map<String, dynamic>> allParticipants = [];
      
      for (var tournamentDoc in tournamentsQuery.docs) {
        final tournamentData = tournamentDoc.data();
        final tournamentName = tournamentData['name']?.toString() ?? 'Unnamed Tournament';
        final events = List<Map<String, dynamic>>.from(tournamentData['events'] ?? []);
        
        // Process each event in the tournament
        for (var event in events) {
          final eventName = event['name']?.toString() ?? 'Unknown Event';
          final participants = List<String>.from(event['participants'] ?? []);
          
          // Get user details for each participant
          for (var participantId in participants) {
            try {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(participantId)
                  .get();
              
              String name = 'Unknown Player';
              String email = 'No email';
              String gender = 'Unknown';
              
              if (userDoc.exists) {
                final userData = userDoc.data()!;
                final firstName = userData['firstName']?.toString() ?? '';
                final lastName = userData['lastName']?.toString() ?? '';
                name = '$firstName $lastName'.trim();
                if (name.isEmpty) name = 'Unknown Player';
                email = userData['email']?.toString() ?? 'No email';
                gender = userData['gender']?.toString() ?? 'Unknown';
              }
              
              // Calculate wins by checking completed matches
              final wins = await _calculatePlayerWins(tournamentDoc.id, participantId, eventName);
              
              allParticipants.add({
                'tournamentId': tournamentDoc.id,
                'tournamentName': tournamentName,
                'eventName': eventName,
                'userId': participantId,
                'name': name,
                'email': email,
                'gender': gender,
                'wins': wins,
              });
            } catch (e) {
              debugPrint('Error processing participant $participantId: $e');
            }
          }
        }
      }

      setState(() {
        _participants = allParticipants;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load participants: $e';
        _isLoading = false;
      });
    }
  }

  Future<int> _calculatePlayerWins(String tournamentId, String playerId, String eventName) async {
    try {
      final matchesSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .collection('matches')
          .where('eventId', isEqualTo: eventName)
          .where('completed', isEqualTo: true)
          .get();

      int wins = 0;
      for (var matchDoc in matchesSnapshot.docs) {
        final matchData = matchDoc.data();
        final winner = matchData['winner'] as String?;
        
        if (winner != null) {
          // Check if this player won (handles both singles and doubles)
          if (winner == 'player1' && matchData['player1Id'] == playerId) {
            wins++;
          } else if (winner == 'player2' && matchData['player2Id'] == playerId) {
            wins++;
          } else if (winner == 'team1' && (matchData['team1Ids'] as List?)?.contains(playerId) == true) {
            wins++;
          } else if (winner == 'team2' && (matchData['team2Ids'] as List?)?.contains(playerId) == true) {
            wins++;
          }
        }
      }
      return wins;
    } catch (e) {
      debugPrint('Error calculating wins for player $playerId: $e');
      return 0;
    }
  }

  Future<void> _removeParticipant(String tournamentId, String eventName, String userId) async {
    setState(() => _isLoading = true);
    
    try {
      // Get tournament document
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .get();
      
      if (!tournamentDoc.exists) {
        throw 'Tournament not found';
      }
      
      final tournamentData = tournamentDoc.data()!;
      final events = List<Map<String, dynamic>>.from(tournamentData['events'] ?? []);
      
      // Find and update the specific event
      bool eventFound = false;
      for (int i = 0; i < events.length; i++) {
        if (events[i]['name'] == eventName) {
          final participants = List<String>.from(events[i]['participants'] ?? []);
          participants.removeWhere((id) => id == userId);
          events[i]['participants'] = participants;
          eventFound = true;
          break;
        }
      }
      
      if (!eventFound) {
        throw 'Event not found in tournament';
      }
      
      // Update the tournament document
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .update({
        'events': events,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      // Remove from local list
      setState(() {
        _participants.removeWhere((p) => 
          p['tournamentId'] == tournamentId && 
          p['eventName'] == eventName && 
          p['userId'] == userId);
      });
      
      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: Text(
          'Success',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        description: Text(
          'Participant removed successfully',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: _successColor,
      );
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: Text(
          'Error',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        description: Text(
          'Failed to remove participant: $e',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: _errorColor,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        title: Text(
          'Manage Players',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchParticipants,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _accentColor))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: _errorColor),
                        const SizedBox(height: 16),
                        Text(
                          'Error Loading Players',
                          style: GoogleFonts.poppins(
                            color: _errorColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchParticipants,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            'Try Again',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _participants.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: _secondaryText.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No participants found',
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Players will appear here once they join your tournaments',
                            style: GoogleFonts.poppins(
                              color: _secondaryText,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Stats header
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.all(16),
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatItem(
                                'Total Players',
                                _participants.length.toString(),
                                Icons.people,
                                _accentColor,
                              ),
                              _buildStatItem(
                                'Tournaments',
                                _participants.map((p) => p['tournamentId']).toSet().length.toString(),
                                Icons.emoji_events,
                                _primaryColor,
                              ),
                              _buildStatItem(
                                'Events',
                                _participants.map((p) => '${p['tournamentId']}-${p['eventName']}').toSet().length.toString(),
                                Icons.sports_tennis,
                                _successColor,
                              ),
                            ],
                          ),
                        ),
                        
                        // Players list
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _participants.length,
                            itemBuilder: (context, index) {
                              final participant = _participants[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
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
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  leading: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: _primaryColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      color: _primaryColor,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    participant['name'],
                                    style: GoogleFonts.poppins(
                                      color: _textColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        participant['email'],
                                        style: GoogleFonts.poppins(
                                          color: _secondaryText,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${participant['tournamentName']} • ${participant['eventName']}',
                                        style: GoogleFonts.poppins(
                                          color: _secondaryText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _accentColor.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Gender: ${participant['gender'].toString().capitalize()}',
                                              style: GoogleFonts.poppins(
                                                color: _accentColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _successColor.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Wins: ${participant['wins']}',
                                              style: GoogleFonts.poppins(
                                                color: _successColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.delete_outline, color: _errorColor),
                                    onPressed: () => _showRemoveConfirmDialog(participant),
                                    tooltip: 'Remove player',
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

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: _secondaryText,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _showRemoveConfirmDialog(Map<String, dynamic> participant) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove Participant',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to remove this participant?',
              style: GoogleFonts.poppins(color: _secondaryText),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    participant['name'],
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'From: ${participant['eventName']}',
                    style: GoogleFonts.poppins(
                      color: _secondaryText,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Tournament: ${participant['tournamentName']}',
                    style: GoogleFonts.poppins(
                      color: _secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: _secondaryText),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _removeParticipant(
                participant['tournamentId'],
                participant['eventName'],
                participant['userId'],
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _errorColor,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Remove',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
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