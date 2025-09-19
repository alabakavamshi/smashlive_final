import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_event.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/screens/player_profile.dart';
import 'package:game_app/auth_pages/welcome_screen.dart';
import 'package:game_app/umpire/umpire_matches.dart';
import 'package:game_app/umpire/umpire_schedule.dart';
import 'package:game_app/umpire/umpire_stats.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:toastification/toastification.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class StringExtension {
  StringExtension(this.value);
  final String value;

  String capitalize() {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }
}

class UmpireHomePage extends StatefulWidget {
  const UmpireHomePage({super.key});

  @override
  State<UmpireHomePage> createState() => _UmpireHomePageState();
}

class _UmpireHomePageState extends State<UmpireHomePage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  String _location = 'Hyderabad, India';
  String _userCity = 'hyderabad';
  Position? _lastPosition;
  final TextEditingController _locationController = TextEditingController();
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _fadeAnimation;
  bool _showToast = false;
  String? _toastMessage;
  ToastificationType? _toastType;
  bool _hasNavigated = false;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _upcomingMatches = [];

  // Color scheme
  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _secondaryColor = const Color(0xFFC1DADB);
  final Color _accentColor = const Color(0xFFF4A261);
  final Color _textColor = const Color(0xFF333333);
  final Color _secondaryText = const Color(0xFF757575);
  final Color _successColor = const Color(0xFF2A9D8F);
  final Color _errorColor = const Color(0xFFE76F51);
  final Color _backgroundColor = const Color(0xFFFDFCFB);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeUserData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserLocationData();
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeOutQuint),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
    );
    _animationController?.forward();
  }

  Future<void> _loadUserLocationData() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(authState.user.uid);
      final userDoc = await userDocRef.get();
      
      if (userDoc.exists && userDoc.data()?['city']?.toString().isNotEmpty == true) {
        if (mounted) {
          setState(() {
            _userCity = userDoc.data()!['city'].toString().toLowerCase();
            _location = '${StringExtension(_userCity).capitalize()}, India';
          });
        }
      } else if (!kIsWeb) {
        _getUserLocation();
      } else {
        if (mounted) {
          setState(() {
            _location = 'Hyderabad, India';
            _userCity = 'hyderabad';
          });
        }
      }
    }
  }

  Future<void> _initializeUserData() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(authState.user.uid);
    final userDoc = await userDocRef.get();

    final defaultUser = {
      'createdAt': Timestamp.now(),
      'displayName': authState.user.email?.split('@')[0] ?? 'Umpire',
      'email': authState.user.email ?? '',
      'firstName': 'Umpire',
      'lastName': '',
      'gender': 'unknown',
      'phone': '',
      'profileImage': '',
      'city': _userCity.isNotEmpty ? _userCity : 'hyderabad',
      'updatedAt': Timestamp.now(),
    };

    if (!userDoc.exists) {
      await userDocRef.set(defaultUser);
      if (mounted) {
        setState(() => _userData = defaultUser);
      }
    } else {
      if (mounted) {
        setState(() => _userData = userDoc.data() ?? defaultUser);
      }
    }
  }

  Stream<Map<String, dynamic>?> _userDataStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Stream.value(null);
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(authState.user.uid)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  Stream<List<Map<String, dynamic>>> _upcomingMatchesStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      debugPrint('No authenticated user found');
      return Stream.value([]);
    }

    final umpireEmail = authState.user.email?.toLowerCase().trim();
    debugPrint('Authenticated umpire email: $umpireEmail');

    // Use collectionGroup to query matches across all tournaments
    return FirebaseFirestore.instance
        .collectionGroup('matches')
        .where('umpire.email', isEqualTo: umpireEmail)
        .snapshots()
        .asyncMap((matchSnapshot) async {
      List<Map<String, dynamic>> upcomingMatches = [];
      final now = DateTime.now();
      
      debugPrint('Found ${matchSnapshot.docs.length} matches for umpire');

      for (var matchDoc in matchSnapshot.docs) {
        try {
          final matchData = matchDoc.data();
          final path = matchDoc.reference.path;
          final tournamentId = path.split('/')[1]; // Extract tournament ID from path

          // Skip completed matches
          if (matchData['completed'] == true) {
            continue;
          }

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
          final matchStartTime = matchData['startTime'] as Timestamp?;
          
          if (matchStartTime == null) {
            debugPrint('No startTime for match: ${matchDoc.id}');
            continue;
          }

          final matchTime = matchStartTime.toDate();
          final isLive = (matchData['liveScores'] as Map<String, dynamic>?)?['isLive'] == true;
          
          String status;
          if (isLive) {
            status = 'LIVE';
          } else if (matchTime.isAfter(now)) {
            status = 'SCHEDULED';
          } else {
            status = 'PAST';
          }

          // Determine if it's doubles
          final isDoubles = (matchData['matchType'] ?? '').toString().toLowerCase().contains('doubles');
          
          // Get player/team names
          String player1Name, player2Name;
          if (isDoubles) {
            final team1 = matchData['team1'] as List<dynamic>?;
            final team2 = matchData['team2'] as List<dynamic>?;
            player1Name = team1?.join(' & ') ?? 'Team 1';
            player2Name = team2?.join(' & ') ?? 'Team 2';
          } else {
            player1Name = matchData['player1']?.toString() ?? 'Player 1';
            player2Name = matchData['player2']?.toString() ?? 'Player 2';
          }

          upcomingMatches.add({
            'id': matchDoc.id,
            'tournamentId': tournamentId,
            'name': '${tournamentData['name'] ?? 'Tournament'} - ${matchData['eventId'] ?? 'Match'}',
            'startDate': matchStartTime,
            'location': _buildLocationString(tournamentData),
            'status': status,
            'player1Name': player1Name,
            'player2Name': player2Name,
            'isDoubles': isDoubles,
            'tournamentName': tournamentData['name'] ?? 'Unknown Tournament',
            'court': matchData['court'],
            'timeSlot': matchData['timeSlot'],
            'round': matchData['round'] ?? 1,
          });

          debugPrint('Processed match: ${matchDoc.id}, Status: $status');
        } catch (e) {
          debugPrint('Error processing match ${matchDoc.id}: $e');
        }
      }

      // Sort by date and status priority
      upcomingMatches.sort((a, b) {
        // Priority: LIVE > SCHEDULED > PAST
        final aStatus = a['status'] as String;
        final bStatus = b['status'] as String;
        
        if (aStatus == 'LIVE' && bStatus != 'LIVE') return -1;
        if (aStatus != 'LIVE' && bStatus == 'LIVE') return 1;
        
        if (aStatus == 'SCHEDULED' && bStatus == 'PAST') return -1;
        if (aStatus == 'PAST' && bStatus == 'SCHEDULED') return 1;
        
        // Within same status, sort by date
        final aDate = (a['startDate'] as Timestamp).toDate();
        final bDate = (b['startDate'] as Timestamp).toDate();
        return aDate.compareTo(bDate);
      });

      debugPrint('Upcoming matches count: ${upcomingMatches.length}');
      return upcomingMatches.take(5).toList();
    });
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

  Color _getMatchStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'SCHEDULED':
        return _accentColor;
      case 'LIVE':
        return _successColor;
      case 'PAST':
        return const Color(0xFFE9C46A);
      case 'COMPLETED':
        return const Color(0xFFE9C46A);
      case 'CANCELLED':
        return _errorColor;
      default:
        return _secondaryText;
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  // Keep existing location methods but make them more responsive
  Future<void> _getUserLocation() async {
    if (!mounted || kIsWeb) return;

    try {
      if (_lastPosition == null) {
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          _lastPosition = lastPosition;
          await _updateLocationFromPosition(lastPosition);
          return;
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _handleLocationServiceDisabled();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _handlePermissionDenied();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _handlePermissionDeniedForever();
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
      } on TimeoutException {
        throw TimeoutException('Location fetch timed out');
      }

      _lastPosition = position;
      await _updateLocationFromPosition(position);
      
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated && mounted) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authState.user.uid)
            .update({'city': _userCity});
      }

      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Location updated to $_location';
          _toastType = ToastificationType.success;
        });
      }
        } catch (e) {
      _handleLocationError(e);
    }
  }

  Future<void> _updateLocationFromPosition(Position position) async {
    if (!mounted) return;

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        if (mounted) {
          setState(() {
            _location = '${place.locality ?? 'Hyderabad'}, ${place.country ?? 'India'}';
            _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
          });
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      if (mounted) {
        setState(() {
          _location = 'Hyderabad, India';
          _userCity = 'hyderabad';
        });
      }
    }
  }

  Future<void> _handleLocationServiceDisabled() async {
    if (!mounted) return;
    final opened = await Geolocator.openLocationSettings();
    if (!opened && mounted) {
      setState(() {
        _location = 'Hyderabad, India';
        _userCity = 'hyderabad';
        _showToast = true;
        _toastMessage = 'Please enable location services manually.';
        _toastType = ToastificationType.warning;
      });
    }
  }

  void _handlePermissionDenied() {
    if (!mounted) return;
    _showPermissionDeniedDialog();
  }

  void _handlePermissionDeniedForever() {
    if (!mounted) return;
    _showPermissionDeniedForeverDialog();
  }

  void _handleLocationError(dynamic e) {
    debugPrint('Location error: $e');
    if (mounted) {
      setState(() {
        _location = 'Hyderabad, India';
        _userCity = 'hyderabad';
        _showToast = true;
        _toastMessage = 'Failed to fetch location. Using default: Hyderabad.';
        _toastType = ToastificationType.error;
      });
    }
  }

  Future<bool?> _showLogoutConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ScaleTransition(
          scale: _scaleAnimation!,
          child: FadeTransition(
            opacity: _fadeAnimation!,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _secondaryColor.withOpacity(0.7)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Confirm Logout',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Are you sure you want to logout?',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          backgroundColor: Colors.white.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          backgroundColor: _errorColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Logout',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Location Permission Denied',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This app needs location permission to fetch your current location. Please enable it in settings.',
          style: GoogleFonts.poppins(
            color: _secondaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: _secondaryText),
            ),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            child: Text(
              'Enable',
              style: GoogleFonts.poppins(color: _primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedForeverDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Location Permission Denied Forever',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Location permission has been permanently denied. You can enable it in app settings.',
          style: GoogleFonts.poppins(
            color: _secondaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: _secondaryText),
            ),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            child: Text(
              'Enable',
              style: GoogleFonts.poppins(color: _primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserWelcomeCard() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _userDataStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _userData == null) {
          return Center(child: CircularProgressIndicator(color: _accentColor));
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading user data',
              style: GoogleFonts.poppins(color: _errorColor),
            ),
          );
        }

        _userData = snapshot.data ?? _userData;
        if (_userData == null) {
          return Center(child: CircularProgressIndicator(color: _accentColor));
        }

        final displayName = _userData!['firstName']?.toString().isNotEmpty == true
            ? '${StringExtension(_userData!['firstName'].toString()).capitalize()} ${_userData!['lastName']?.toString().isNotEmpty == true ? StringExtension(_userData!['lastName'].toString()).capitalize() : ''}'
            : 'Umpire';

        return LayoutBuilder(
          builder: (context, constraints) {
            final isSmallScreen = constraints.maxWidth < 400;
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome Back,',
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                        ),
                        Text(
                          displayName,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: isSmallScreen ? 18 : 22,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _upcomingMatchesStream(),
                          builder: (context, matchesSnapshot) {
                            if (matchesSnapshot.hasData) {
                              _upcomingMatches = matchesSnapshot.data!;
                            }
                            return Row(
                              children: [
                                Icon(Icons.sports_tennis, 
                                     size: isSmallScreen ? 14 : 16, 
                                     color: Colors.white),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${_upcomingMatches.length} Upcoming Matches',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: isSmallScreen ? 11 : 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (!isSmallScreen) const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => setState(() => _selectedIndex = 2),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: isSmallScreen ? 30 : 40,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        backgroundImage: _userData!['profileImage']?.toString().isNotEmpty == true
                            ? (_userData!['profileImage'].toString().startsWith('http')
                                ? CachedNetworkImageProvider(_userData!['profileImage'])
                                : AssetImage(_userData!['profileImage']) as ImageProvider)
                            : const AssetImage('assets/logo.png') as ImageProvider,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUpcomingMatches() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _upcomingMatchesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: _accentColor));
        }
        
        if (snapshot.hasError) {
          debugPrint('Snapshot error: ${snapshot.error}');
          return Center(
            child: Text(
              'Error loading matches',
              style: GoogleFonts.poppins(color: _errorColor),
            ),
          );
        }
        
        _upcomingMatches = snapshot.data ?? [];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isSmallScreen = constraints.maxWidth < 400;
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Upcoming Matches',
                        style: GoogleFonts.poppins(
                          color: _textColor,
                          fontSize: isSmallScreen ? 16 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.sports_tennis,
                          color: _primaryColor,
                          size: isSmallScreen ? 18 : 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (_upcomingMatches.isEmpty)
                    Column(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: isSmallScreen ? 40 : 48,
                          color: _secondaryText.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No matches assigned',
                          style: GoogleFonts.poppins(
                            color: _secondaryText,
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tournament organizers will assign matches to you',
                          style: GoogleFonts.poppins(
                            color: _secondaryText.withOpacity(0.8),
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() => _selectedIndex = 1),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 20 : 24, 
                              vertical: isSmallScreen ? 10 : 12
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'View Matches',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: isSmallScreen ? 13 : 14,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    ..._upcomingMatches.map((match) {
                      final startDate = (match['startDate'] as Timestamp).toDate();
                      final player1Name = match['player1Name'] as String;
                      final player2Name = match['player2Name'] as String;
                      final tournamentName = match['tournamentName'] as String;
                      final status = match['status'] as String;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                        decoration: BoxDecoration(
                          color: _backgroundColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _getMatchStatusColor(status).withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Date container
                                Container(
                                  padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
                                  decoration: BoxDecoration(
                                    color: _getMatchStatusColor(status),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _getMatchStatusColor(status).withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        DateFormat('MMM').format(startDate).toUpperCase(),
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: isSmallScreen ? 10 : 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        DateFormat('dd').format(startDate),
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: isSmallScreen ? 16 : 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                const SizedBox(width: 12),
                                
                                // Match details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              tournamentName,
                                              style: GoogleFonts.poppins(
                                                color: _textColor,
                                                fontSize: isSmallScreen ? 14 : 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _getMatchStatusColor(status).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: _getMatchStatusColor(status).withOpacity(0.3),
                                              ),
                                            ),
                                            child: Text(
                                              status.toUpperCase(),
                                              style: GoogleFonts.poppins(
                                                color: _getMatchStatusColor(status),
                                                fontSize: isSmallScreen ? 9 : 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      
                                      const SizedBox(height: 6),
                                      
                                      // Location and match type
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.location_on_outlined,
                                            size: isSmallScreen ? 12 : 14,
                                            color: _secondaryText,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              match['location'] as String,
                                              style: GoogleFonts.poppins(
                                                color: _secondaryText,
                                                fontSize: isSmallScreen ? 11 : 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (match['court'] != null) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              'Court ${match['court']}',
                                              style: GoogleFonts.poppins(
                                                color: _secondaryText,
                                                fontSize: isSmallScreen ? 10 : 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      
                                      const SizedBox(height: 6),
                                      
                                      // Time and round info
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: isSmallScreen ? 12 : 14,
                                            color: _secondaryText,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            match['timeSlot'] ?? DateFormat('h:mm a').format(startDate),
                                            style: GoogleFonts.poppins(
                                              color: _secondaryText,
                                              fontSize: isSmallScreen ? 11 : 12,
                                            ),
                                          ),
                                          if (match['round'] != null) ...[
                                            const SizedBox(width: 12),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _primaryColor.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Round ${match['round']}',
                                                style: GoogleFonts.poppins(
                                                  color: _primaryColor,
                                                  fontSize: isSmallScreen ? 9 : 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      
                                      const SizedBox(height: 8),
                                      
                                      // Players/Teams
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              player1Name,
                                              style: GoogleFonts.poppins(
                                                color: _textColor,
                                                fontSize: isSmallScreen ? 12 : 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _secondaryText.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'vs',
                                              style: GoogleFonts.poppins(
                                                color: _secondaryText,
                                                fontSize: isSmallScreen ? 10 : 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              player2Name,
                                              style: GoogleFonts.poppins(
                                                color: _textColor,
                                                fontSize: isSmallScreen ? 12 : 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ],
                                      ),
                                      
                                      // Match type indicator
                                      if (match['isDoubles'] == true) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.people_outline,
                                              size: isSmallScreen ? 12 : 14,
                                              color: _accentColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Doubles Match',
                                              style: GoogleFonts.poppins(
                                                color: _accentColor,
                                                fontSize: isSmallScreen ? 10 : 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 400;
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Actions',
                style: GoogleFonts.poppins(
                  color: _textColor,
                  fontSize: isSmallScreen ? 16 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              
              // Use responsive grid
              isSmallScreen 
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildQuickActionButton(
                            icon: Icons.sports_tennis,
                            label: 'Matches',
                            color: _primaryColor,
                            onTap: () => setState(() => _selectedIndex = 1),
                            isSmall: isSmallScreen,
                          ),
                          _buildQuickActionButton(
                            icon: Icons.schedule,
                            label: 'Schedule',
                            color: _accentColor,
                            onTap: () => _navigateToSchedule(),
                            isSmall: isSmallScreen,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildQuickActionButton(
                        icon: Icons.bar_chart,
                        label: 'Statistics',
                        color: _successColor,
                        onTap: () => _navigateToStats(),
                        isSmall: isSmallScreen,
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickActionButton(
                        icon: Icons.sports_tennis,
                        label: 'Matches',
                        color: _primaryColor,
                        onTap: () => setState(() => _selectedIndex = 1),
                        isSmall: isSmallScreen,
                      ),
                      _buildQuickActionButton(
                        icon: Icons.schedule,
                        label: 'Schedule',
                        color: _accentColor,
                        onTap: () => _navigateToSchedule(),
                        isSmall: isSmallScreen,
                      ),
                      _buildQuickActionButton(
                        icon: Icons.bar_chart,
                        label: 'Statistics',
                        color: _successColor,
                        onTap: () => _navigateToStats(),
                        isSmall: isSmallScreen,
                      ),
                    ],
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isSmall = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isSmall ? 14 : 16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(
              icon, 
              color: color, 
              size: isSmall ? 24 : 28
            ),
          ),
          SizedBox(height: isSmall ? 6 : 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: _textColor,
              fontSize: isSmall ? 11 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToSchedule() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UmpireSchedulePage(
            userId: authState.user.uid,
            userEmail: authState.user.email ?? '',
          ),
        ),
      );
    }
  }

  void _navigateToStats() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UmpireStatsPage(
            userId: authState.user.uid,
            userEmail: authState.user.email ?? '',
          ),
        ),
      );
    }
  }

  void _onItemTapped(int index) {
    if (index < 0 || index >= 3) {
      debugPrint('Invalid index: $index');
      return;
    }
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showToast && _toastMessage != null && _toastType != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toastification.show(
          context: context,
          type: _toastType!,
          title: Text(
            _toastType == ToastificationType.success
                ? 'Success'
                : _toastType == ToastificationType.error
                    ? 'Error'
                    : 'Info',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          description: Text(
            _toastMessage!,
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          autoCloseDuration: const Duration(seconds: 3),
          backgroundColor: _toastType == ToastificationType.success
              ? _successColor
              : _toastType == ToastificationType.error
                  ? _errorColor
                  : _accentColor,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
        if (mounted) {
          setState(() {
            _showToast = false;
            _toastMessage = null;
            _toastType = null;
          });
        }
      });
    }

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated && mounted && !_hasNavigated) {
          _hasNavigated = true;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        } else if (state is AuthError && mounted) {
          setState(() {
            _showToast = true;
            _toastMessage = state.message;
            _toastType = ToastificationType.error;
          });
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthUnauthenticated) {
            return const WelcomeScreen();
          }

          if (state is AuthLoading) {
            return Scaffold(
              backgroundColor: _backgroundColor,
              body: Center(child: CircularProgressIndicator(color: _accentColor)),
            );
          }

          final List<Widget> pages = [
            SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildUserWelcomeCard(),
                  _buildQuickActions(),
                  _buildUpcomingMatches(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            const UmpireMatchesPage(),
            const PlayerProfilePage(),
          ];

          return WillPopScope(
            onWillPop: () async {
              if (_selectedIndex != 0) {
                if (mounted) {
                  setState(() => _selectedIndex = 0);
                }
                return false;
              }
              return true;
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSmallScreen = constraints.maxWidth < 400;
                
                return Scaffold(
                  backgroundColor: _backgroundColor,
                  appBar: _selectedIndex == 0
                    ? AppBar(
                        elevation: 0,
                        toolbarHeight: isSmallScreen ? 70 : 80,
                        backgroundColor: Colors.white,
                        flexibleSpace: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                            ),
                          ),
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SmashLive Umpire',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w800,
                                fontSize: isSmallScreen ? 20 : 24,
                                color: Colors.white,
                              ),
                            ),
                            if (!isSmallScreen) const SizedBox(height: 4),
                          ],
                        ),
                        actions: [
                          IconButton(
                            icon: Container(
                              padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.2),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.logout,
                                color: Colors.white,
                                size: isSmallScreen ? 18 : 20,
                              ),
                            ),
                            onPressed: () async {
                              if (state is AuthAuthenticated && mounted) {
                                final shouldLogout = await _showLogoutConfirmationDialog();
                                if (shouldLogout == true) {
                                  context.read<AuthBloc>().add(AuthLogoutEvent());
                                  setState(() {
                                    _showToast = true;
                                    _toastMessage = 'You have been logged out successfully.';
                                    _toastType = ToastificationType.success;
                                  });
                                }
                              }
                            },
                          ),
                        ],
                      )
                    : _selectedIndex == 1
                        ? AppBar(
                            backgroundColor: _primaryColor,
                            elevation: 0,
                            title: Text(
                              'My Officiating Schedule',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: isSmallScreen ? 18 : 22,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            centerTitle: true,
                          )
                        : null,
                  body: pages[_selectedIndex],
                  bottomNavigationBar: Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 12 : 16,
                      vertical: isSmallScreen ? 12 : 16,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BottomNavigationBar(
                        backgroundColor: Colors.white,
                        selectedItemColor: _primaryColor,
                        unselectedItemColor: const Color(0xFF9E9E9E),
                        currentIndex: _selectedIndex,
                        onTap: _onItemTapped,
                        type: BottomNavigationBarType.fixed,
                        elevation: 0,
                        selectedLabelStyle: GoogleFonts.poppins(
                          fontSize: isSmallScreen ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelStyle: GoogleFonts.poppins(
                          fontSize: isSmallScreen ? 11 : 12,
                          fontWeight: FontWeight.w500,
                        ),
                        items: [
                          BottomNavigationBarItem(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _selectedIndex == 0 
                                    ? _primaryColor.withOpacity(0.15)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _selectedIndex == 0 
                                    ? Icons.home_filled 
                                    : Icons.home_outlined,
                                size: isSmallScreen ? 22 : 24,
                              ),
                            ),
                            label: 'Home',
                          ),
                          BottomNavigationBarItem(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _selectedIndex == 1 
                                    ? _primaryColor.withOpacity(0.15)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _selectedIndex == 1 
                                    ? Icons.sports_tennis 
                                    : Icons.sports_tennis_outlined,
                                size: isSmallScreen ? 22 : 24,
                              ),
                            ),
                            label: 'Matches',
                          ),
                          BottomNavigationBarItem(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _selectedIndex == 2 
                                    ? _primaryColor.withOpacity(0.15)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _selectedIndex == 2 
                                    ? Icons.person 
                                    : Icons.person_outline,
                                size: isSmallScreen ? 22 : 24,
                              ),
                            ),
                            label: 'Profile',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}