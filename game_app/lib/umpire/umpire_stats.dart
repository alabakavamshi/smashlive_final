import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class UmpireStatsPage extends StatefulWidget {
  final String userId;
  final String userEmail;

  const UmpireStatsPage({super.key, required this.userId, required this.userEmail});

  @override
  State<UmpireStatsPage> createState() => _UmpireStatsPageState();
}

class _UmpireStatsPageState extends State<UmpireStatsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  int _totalMatches = 0;
  int _completedMatches = 0;
  int _ongoingMatches = 0;
  int _scheduledMatches = 0;
  int _totalTournaments = 0;

  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _secondaryColor = const Color(0xFFC1DADB);
  final Color _accentColor = const Color(0xFFF4A261);
  final Color _textColor = const Color(0xFF333333);
  final Color _secondaryText = const Color(0xFF757575);
  final Color _successColor = const Color(0xFF2A9D8F);
  final Color _moodColor = const Color(0xFFE9C46A);
  final Color _coolBlue = const Color(0xFFA8DADC);
  final Color _errorColor = const Color(0xFFE76F51);

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Query all matches assigned to this umpire using collectionGroup
      final matchesSnapshot = await FirebaseFirestore.instance
          .collectionGroup('matches')
          .where('umpire.email', isEqualTo: widget.userEmail.toLowerCase().trim())
          .get();

      debugPrint('Found ${matchesSnapshot.docs.length} matches for umpire stats');

      final Set<String> tournamentIds = {};
      int totalMatches = 0;
      int completedMatches = 0;
      int ongoingMatches = 0;
      int scheduledMatches = 0;

      for (var matchDoc in matchesSnapshot.docs) {
        try {
          final matchData = matchDoc.data();
          final path = matchDoc.reference.path;
          final tournamentId = path.split('/')[1]; // Extract tournament ID from path

          totalMatches++;
          tournamentIds.add(tournamentId);

          // Check match status
          if (matchData['completed'] == true) {
            completedMatches++;
          } else if (matchData['liveScores']?['isLive'] == true) {
            ongoingMatches++;
          } else {
            scheduledMatches++;
          }
        } catch (e) {
          debugPrint('Error processing match ${matchDoc.id}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _totalMatches = totalMatches;
          _completedMatches = completedMatches;
          _ongoingMatches = ongoingMatches;
          _scheduledMatches = scheduledMatches;
          _totalTournaments = tournamentIds.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching umpire stats: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load stats: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFCFB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Umpire Statistics',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18, // Fixed font size, will scale with textScaler
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _secondaryText),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: _secondaryText),
            onPressed: _fetchStats,
            tooltip: 'Refresh Stats',
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, Color(0xFF6C9A8B)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive sizing based on screen width
          final isSmallScreen = constraints.maxWidth < 600;
          final padding = isSmallScreen ? 16.0 : 24.0;
          final iconSize = isSmallScreen ? 40.0 : 48.0;
          final titleFontSize = isSmallScreen ? 16.0 : 20.0;
          final subtitleFontSize = isSmallScreen ? 12.0 : 14.0;
          final crossAxisCount = constraints.maxWidth < 600 ? 2 : 4;
          final childAspectRatio = isSmallScreen ? 1.2 : 1.0;

          return _isLoading
              ? Center(child: CircularProgressIndicator(color: _accentColor))
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(padding),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: iconSize, color: _errorColor),
                            SizedBox(height: padding),
                            Text(
                              'Failed to load statistics',
                              style: GoogleFonts.poppins(
                                color: _errorColor,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                              textScaler: MediaQuery.textScalerOf(context),
                            ),
                            SizedBox(height: padding / 2),
                            Text(
                              _errorMessage!,
                              style: GoogleFonts.poppins(
                                color: _secondaryText,
                                fontSize: subtitleFontSize,
                              ),
                              textAlign: TextAlign.center,
                              textScaler: MediaQuery.textScalerOf(context),
                            ),
                            SizedBox(height: padding),
                            ElevatedButton(
                              onPressed: _fetchStats,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: padding * 2,
                                  vertical: padding / 2,
                                ),
                              ),
                              child: Text(
                                'Try Again',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w500,
                                  fontSize: subtitleFontSize,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header section
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(padding),
                            margin: EdgeInsets.only(bottom: padding * 1.5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.gavel,
                                  size: iconSize,
                                  color: Colors.white,
                                ),
                                SizedBox(height: padding / 2),
                                Text(
                                  'Your Umpiring Overview',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textScaler: MediaQuery.textScalerOf(context),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: padding / 2),
                                Text(
                                  widget.userEmail,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: subtitleFontSize,
                                  ),
                                  textScaler: MediaQuery.textScalerOf(context),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),

                          // Main stats grid
                          GridView.count(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: padding,
                            mainAxisSpacing: padding,
                            childAspectRatio: childAspectRatio,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _buildStatCard(
                                title: 'Total Matches',
                                value: _totalMatches.toString(),
                                icon: Icons.sports_tennis,
                                color: _accentColor,
                                subtitle: 'All assigned matches',
                                isSmallScreen: isSmallScreen,
                              ),
                              _buildStatCard(
                                title: 'Tournaments',
                                value: _totalTournaments.toString(),
                                icon: Icons.emoji_events,
                                color: _moodColor,
                                subtitle: 'Events officiated',
                                isSmallScreen: isSmallScreen,
                              ),
                              _buildStatCard(
                                title: 'Completed',
                                value: _completedMatches.toString(),
                                icon: Icons.check_circle,
                                color: _successColor,
                                subtitle: 'Finished matches',
                                isSmallScreen: isSmallScreen,
                              ),
                              _buildStatCard(
                                title: 'In Progress',
                                value: _ongoingMatches.toString(),
                                icon: Icons.timer,
                                color: _coolBlue,
                                subtitle: 'Currently live',
                                isSmallScreen: isSmallScreen,
                              ),
                            ],
                          ),

                          SizedBox(height: padding * 1.5),

                          // Scheduled matches card
                          _buildFullWidthStatCard(
                            title: 'Scheduled Matches',
                            value: _scheduledMatches.toString(),
                            icon: Icons.schedule,
                            color: _primaryColor,
                            subtitle: 'Upcoming matches awaiting your officiating',
                            isSmallScreen: isSmallScreen,
                          ),

                          SizedBox(height: padding * 1.5),

                          // Performance overview
                          if (_totalMatches > 0) ...[
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(padding),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.analytics, color: _accentColor, size: isSmallScreen ? 20 : 24),
                                      SizedBox(width: padding / 2),
                                      Text(
                                        'Performance Overview',
                                        style: GoogleFonts.poppins(
                                          color: _textColor,
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textScaler: MediaQuery.textScalerOf(context),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: padding),
                                  _buildProgressRow(
                                    'Completion Rate',
                                    _completedMatches,
                                    _totalMatches,
                                    _successColor,
                                    isSmallScreen,
                                  ),
                                  SizedBox(height: padding / 2),
                                  _buildProgressRow(
                                    'Active Matches',
                                    _ongoingMatches,
                                    _totalMatches,
                                    _accentColor,
                                    isSmallScreen,
                                  ),
                                  SizedBox(height: padding / 2),
                                  _buildProgressRow(
                                    'Pending Matches',
                                    _scheduledMatches,
                                    _totalMatches,
                                    _primaryColor,
                                    isSmallScreen,
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(padding),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _secondaryColor),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: iconSize,
                                    color: _secondaryText,
                                  ),
                                  SizedBox(height: padding / 2),
                                  Text(
                                    'No Statistics Available',
                                    style: GoogleFonts.poppins(
                                      color: _textColor,
                                      fontSize: titleFontSize,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textScaler: MediaQuery.textScalerOf(context),
                                  ),
                                  SizedBox(height: padding / 2),
                                  Text(
                                    'You haven\'t been assigned to any matches yet. Once tournament organizers assign you to matches, your statistics will appear here.',
                                    style: GoogleFonts.poppins(
                                      color: _secondaryText,
                                      fontSize: subtitleFontSize,
                                    ),
                                    textAlign: TextAlign.center,
                                    textScaler: MediaQuery.textScalerOf(context),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    required bool isSmallScreen,
  }) {
    final padding = isSmallScreen ? 12.0 : 16.0;
    final iconSize = isSmallScreen ? 20.0 : 24.0;
    final valueFontSize = isSmallScreen ? 24.0 : 28.0;
    final titleFontSize = isSmallScreen ? 12.0 : 14.0;
    final subtitleFontSize = isSmallScreen ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(padding / 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
          SizedBox(height: padding / 2),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: _textColor,
              fontSize: valueFontSize,
              fontWeight: FontWeight.w700,
            ),
            textScaler: MediaQuery.textScalerOf(context),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            title,
            style: GoogleFonts.poppins(
              color: _textColor,
              fontSize: titleFontSize,
              fontWeight: FontWeight.w600,
            ),
            textScaler: MediaQuery.textScalerOf(context),
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            SizedBox(height: padding / 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                color: _secondaryText,
                fontSize: subtitleFontSize,
              ),
              textScaler: MediaQuery.textScalerOf(context),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFullWidthStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    required bool isSmallScreen,
  }) {
    final padding = isSmallScreen ? 12.0 : 20.0;
    final iconSize = isSmallScreen ? 24.0 : 32.0;
    final valueFontSize = isSmallScreen ? 28.0 : 32.0;
    final titleFontSize = isSmallScreen ? 14.0 : 16.0;
    final subtitleFontSize = isSmallScreen ? 12.0 : 14.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(padding / 1.5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
          SizedBox(width: padding),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                  textScaler: MediaQuery.textScalerOf(context),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: _textColor,
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                  textScaler: MediaQuery.textScalerOf(context),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  SizedBox(height: padding / 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      color: _secondaryText,
                      fontSize: subtitleFontSize,
                    ),
                    textScaler: MediaQuery.textScalerOf(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, int current, int total, Color color, bool isSmallScreen) {
    final percentage = total > 0 ? (current / total) : 0.0;
    final fontSize = isSmallScreen ? 12.0 : 14.0;
    final secondaryFontSize = isSmallScreen ? 10.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                color: _textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
              textScaler: MediaQuery.textScalerOf(context),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '$current/$total (${(percentage * 100).toStringAsFixed(0)}%)',
              style: GoogleFonts.poppins(
                color: _secondaryText,
                fontSize: secondaryFontSize,
              ),
              textScaler: MediaQuery.textScalerOf(context),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: isSmallScreen ? 4 : 6,
          ),
        ),
      ],
    );
  }
}