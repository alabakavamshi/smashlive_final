import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_event.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/player_pages/match_history_page.dart';
import 'package:game_app/screens/play_page.dart';
import 'package:game_app/screens/player_profile.dart';
import 'package:game_app/auth_pages/welcome_screen.dart';
import 'package:game_app/tournaments/match_details_page.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:iconsax/iconsax.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

extension StringExtension on String {
  String capitalize() {
    return isNotEmpty
        ? '${this[0].toUpperCase()}${substring(1).toLowerCase()}'
        : this;
  }
}

class PlayerHomePage extends StatefulWidget {
  const PlayerHomePage({super.key});

  @override
  State<PlayerHomePage> createState() => _PlayerHomePageState();
}

class _PlayerHomePageState extends State<PlayerHomePage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  String _location = 'Hyderabad, India';
  String _userCity = 'hyderabad';
  bool _isLoadingLocation = false;
  bool _locationFetchCompleted = false;
  bool _hasNavigated = false;
  bool _showToast = false;
  String? _toastMessage;
  ToastificationType? _toastType;
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _upcomingMatches = [];
  final TextEditingController _locationController = TextEditingController();
  AnimationController? _animationController;
  final _scrollController = ScrollController();

  // Added for city suggestions
  bool _isFetchingSuggestions = false;
  Timer? _debounceTimer;
  OverlayEntry? _overlayEntry;
  List<String> _citySuggestions = [];
  final FocusNode _cityFocusNode = FocusNode();
  final String _googlePlacesApiKey = dotenv.get('GOOGLE_PLACES_API_KEY');

  final Color _darkBackground = const Color(0xFF121212);
  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _textColor = Colors.white;
  final Color _secondaryTextColor = const Color(0xFFC1DADB);
  final Color _inputBackground = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _initializeAnimations();
    _initializeUserData();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb) {
        await _getUserLocation();
      } else {
        if (mounted) {
          setState(() {
            _location = 'Hyderabad, India';
            _userCity = 'hyderabad';
            _locationFetchCompleted = true;
            _isLoadingLocation = false;
          });
        }
      }
    });

    _cityFocusNode.addListener(() {
      if (!_cityFocusNode.hasFocus) {
        _removeOverlay();
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animationController?.forward();
  }

  Future<void> _initializeUserData() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final userDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(authState.user.uid);
    final userDoc = await userDocRef.get();

    final defaultUser = {
      'createdAt': Timestamp.now(),
      'displayName': authState.user.email?.split('@')[0] ?? 'Player',
      'email': authState.user.email ?? '',
      'firstName': 'Player',
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
      debugPrint('No authenticated user found');
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

    final userId = authState.user.uid;
    return FirebaseFirestore.instance.collection('tournaments').snapshots().map(
      (querySnapshot) {
        List<Map<String, dynamic>> allMatches = [];
        List<Map<String, dynamic>> liveMatches = [];
        final now = tz.TZDateTime.now(tz.getLocation('Asia/Kolkata'));

        for (var doc in querySnapshot.docs) {
          final data = doc.data();
          final participants = data['participants'] as List<dynamic>? ?? [];
          final isParticipant = participants.any(
            (p) => p is Map<String, dynamic> && p['id'] == userId,
          );
          if (!isParticipant) continue;

          final matches = data['matches'] as List<dynamic>? ?? [];
          final tournamentTimezone = data['timezone']?.toString() ?? 'Asia/Kolkata';
          tz.Location tzLocation;
          try {
            tzLocation = tz.getLocation(tournamentTimezone);
          } catch (e) {
            debugPrint('Invalid timezone for tournament ${doc.id}: $tournamentTimezone, defaulting to Asia/Kolkata');
            tzLocation = tz.getLocation('Asia/Kolkata');
          }

          for (var match in matches) {
            try {
              final matchData = match as Map<String, dynamic>;
              final player1Id = matchData['player1Id']?.toString() ?? '';
              final player2Id = matchData['player2Id']?.toString() ?? '';
              final team1Ids = List<String>.from(matchData['team1Ids'] ?? []);
              final team2Ids = List<String>.from(matchData['team2Ids'] ?? []);
              final isUserMatch =
                  player1Id == userId ||
                  player2Id == userId ||
                  team1Ids.contains(userId) ||
                  team2Ids.contains(userId);

              if (!isUserMatch) continue;

              final matchStartTime = (matchData['startDate'] as Timestamp?)?.toDate() ??
                  (data['startDate'] as Timestamp).toDate();
              final matchStartTimeInTz = tz.TZDateTime.from(matchStartTime, tzLocation);

              final isLive = (matchData['liveScores'] as Map<String, dynamic>?)?['isLive'] == true;
              final status = matchData['completed'] == true
                  ? 'COMPLETED'
                  : isLive
                      ? 'LIVE'
                      : matchStartTimeInTz.isAfter(now)
                          ? 'SCHEDULED'
                          : 'PAST';

              final matchInfo = {
                'matchId': matchData['matchId']?.toString() ?? '',
                'tournamentId': doc.id,
                'tournamentName': data['name']?.toString() ?? 'Unnamed Tournament',
                'player1': matchData['player1']?.toString() ?? 'Unknown',
                'player2': matchData['player2']?.toString() ?? 'Unknown',
                'player1Id': player1Id,
                'player2Id': player2Id,
                'team1': List<String>.from(matchData['team1'] ?? ['Unknown']),
                'team2': List<String>.from(matchData['team2'] ?? ['Unknown']),
                'team1Ids': team1Ids,
                'team2Ids': team2Ids,
                'completed': matchData['completed'] ?? false,
                'round': matchData['round']?.toString() ?? '1',
                'startTime': Timestamp.fromDate(matchStartTime),
                'startTimeInTz': matchStartTimeInTz,
                'timezone': tournamentTimezone,
                'isDoubles': matchData['team1Ids'] != null &&
                    matchData['team2Ids'] != null &&
                    matchData['team1Ids'].isNotEmpty &&
                    matchData['team2Ids'].isNotEmpty,
                'liveScores': matchData['liveScores'] ?? {'isLive': false, 'currentGame': 1},
                'location': (data['venue']?.toString().isNotEmpty == true &&
                        data['city']?.toString().isNotEmpty == true)
                    ? '${data['venue']}, ${data['city']}'
                    : data['city']?.toString() ?? 'Unknown',
                'status': status,
              };

              allMatches.add(matchInfo);
              if (status == 'LIVE') {
                liveMatches.add(matchInfo);
              }
            } catch (e) {
              debugPrint('Error processing match in tournament ${doc.id}: $e');
            }
          }
        }

        if (mounted) {
          setState(() {
          });
        }

        allMatches.sort(
          (a, b) => (a['startTimeInTz'] as tz.TZDateTime).compareTo(b['startTimeInTz'] as tz.TZDateTime),
        );
        return allMatches.take(5).toList();
      },
    );
  }

  @override
  void dispose() {
    _locationController.dispose();
    _animationController?.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    _cityFocusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  String _normalizeCity(String city) {
    return city.split(',')[0].trim().toLowerCase();
  }

  Future<void> _fetchCitySuggestions(String query) async {
    if (query.isEmpty || query.length < 2) {
      setState(() {
        _isFetchingSuggestions = false;
        _citySuggestions = [];
      });
      _removeOverlay();
      return;
    }

    setState(() {
      _isFetchingSuggestions = true;
    });

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeQueryComponent(query)}&types=(cities)&key=$_googlePlacesApiKey',
      );
      debugPrint('Requesting Places API: $url');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List<dynamic>?;
          if (predictions != null && predictions.isNotEmpty) {
            final suggestions = predictions
                .map<String>((prediction) => prediction['description'] as String)
                .where((city) => city.isNotEmpty)
                .toList();
            if (mounted) {
              setState(() {
                _citySuggestions = suggestions;
                _isFetchingSuggestions = false;
              });
              if (_citySuggestions.isNotEmpty && context.mounted) {
                final renderBox = _cityFocusNode.context?.findRenderObject() as RenderBox?;
                if (renderBox != null) {
                  _showSuggestionsOverlay(_citySuggestions, context, renderBox);
                }
              } else {
                _removeOverlay();
              }
            }
          } else {
            if (mounted) {
              setState(() {
                _citySuggestions = [];
                _isFetchingSuggestions = false;
              });
              _removeOverlay();
            }
          }
        } else {
          debugPrint('Google Places API error: ${data['status']}, message: ${data['error_message']}');
          if (mounted) {
            setState(() {
              _citySuggestions = [];
              _isFetchingSuggestions = false;
              _showToast = true;
              _toastMessage = data['error_message'] ?? 'Failed to fetch suggestions';
              _toastType = ToastificationType.error;
            });
          }
          _removeOverlay();
          _fetchCitySuggestionsFallback(query);
        }
      } else {
        debugPrint('HTTP error: ${response.statusCode}, body: ${response.body}');
        if (mounted) {
          setState(() {
            _citySuggestions = [];
            _isFetchingSuggestions = false;
            _showToast = true;
            _toastMessage = 'Failed to fetch suggestions';
            _toastType = ToastificationType.error;
          });
        }
        _removeOverlay();
        _fetchCitySuggestionsFallback(query);
      }
    } catch (e) {
      debugPrint('Error fetching city suggestions: $e');
      if (mounted) {
        setState(() {
          _citySuggestions = [];
          _isFetchingSuggestions = false;
          _showToast = true;
          _toastMessage = 'Failed to fetch suggestions';
          _toastType = ToastificationType.error;
        });
      }
      _removeOverlay();
      _fetchCitySuggestionsFallback(query);
    }
  }




Future<void> _fetchCitySuggestionsFallback(String query) async {
  try {
    final locations = await locationFromAddress(query).timeout(const Duration(seconds: 5));
    final placemarks = await Future.wait(
      locations.take(5).map((loc) => placemarkFromCoordinates(loc.latitude, loc.longitude)),
    );

    final suggestions = placemarks
        .expand((placemarkList) => placemarkList)
        .map((placemark) {
          final city = placemark.locality ?? '';
          final state = placemark.administrativeArea ?? '';
          final country = placemark.country ?? '';
          
          // Build location string with available components
          List<String> parts = [];
          if (city.isNotEmpty) parts.add(city);
          if (state.isNotEmpty) parts.add(state);
          if (country.isNotEmpty) parts.add(country);
          
          return parts.join(', ');
        })
        .where((city) => city.isNotEmpty)
        .toSet()
        .toList();

    if (mounted) {
      setState(() {
        _citySuggestions = suggestions;
        _isFetchingSuggestions = false;
      });
      if (_citySuggestions.isNotEmpty && context.mounted) {
        final renderBox = _cityFocusNode.context?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          _showSuggestionsOverlay(_citySuggestions, context, renderBox);
        }
      } else {
        _removeOverlay();
      }
    }
  } catch (e) {
    debugPrint('Fallback location error: $e');
    if (mounted) {
      setState(() {
        _citySuggestions = [];
        _isFetchingSuggestions = false;
      });
      _removeOverlay();
    }
  }
}




  void _showSuggestionsOverlay(List<String> suggestions, BuildContext context, RenderBox renderBox) {
    _removeOverlay();

    final width = renderBox.size.width;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + renderBox.size.height + 4,
        width: width,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: _inputBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _secondaryTextColor.withOpacity(0.2),
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
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final city = suggestions[index];
                return ListTile(
                  title: Text(
                    city,
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    if (mounted) {
                      setState(() {
                        _locationController.text = city;
                        _location = city;
                        _userCity = _normalizeCity(city);
                        _showToast = true;
                        
                        _toastType = ToastificationType.success;
                      });
                      _removeOverlay();
                      _searchLocation(city); // Update location
                      Navigator.pop(context); // Close dialog
                    }
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _debounceCityValidation(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _fetchCitySuggestions(value);
    });
  }

  Future<void> _getUserLocation() async {
    if (kIsWeb || !mounted) return;

    setState(() {
      _isLoadingLocation = true;
      _locationFetchCompleted = false;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _location = 'Hyderabad, India';
            _userCity = 'hyderabad';
            _showToast = true;
            _toastMessage = 'Location services disabled';
            _toastType = ToastificationType.warning;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _location = 'Hyderabad, India';
              _userCity = 'hyderabad';
              _showToast = true;
              _toastMessage = 'Location permission denied';
              _toastType = ToastificationType.error;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _location = 'Hyderabad, India';
            _userCity = 'hyderabad';
            _showToast = true;
            _toastMessage = 'Location permission denied forever';
            _toastType = ToastificationType.error;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 5));

      if (mounted) {
       setState(() {
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final city = placemark.locality ?? 'Unknown';
          final country = placemark.country ?? '';
          _location = country.isNotEmpty ? '$city, $country' : city;
          _userCity = city.toLowerCase();
        } else {
          _location = 'Hyderabad, India';  // Keep as fallback only
          _userCity = 'hyderabad';
        }
        _showToast = true;
        _toastType = ToastificationType.success;
      });
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
       
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationFetchCompleted = true;
        });
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Please enter a location';
          _toastType = ToastificationType.error;
        });
      }
      return;
    }

    try {
      final locations = await locationFromAddress(
        query,
      ).timeout(const Duration(seconds: 5));
      if (locations.isEmpty) {
        throw Exception('No locations found');
      }

      final location = locations.first;
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      ).timeout(const Duration(seconds: 3));

      if (mounted) {
       setState(() {
            if (placemarks.isNotEmpty) {
              final placemark = placemarks.first;
              final city = placemark.locality ?? query;
              final country = placemark.country ?? '';
              _location = country.isNotEmpty ? '$city, $country' : city;
              _userCity = city.toLowerCase();
            } else {
              _location = query;  
              _userCity = _normalizeCity(query);
            }
            _showToast = true;
            _toastType = ToastificationType.success;
          });

      }
    } catch (e) {
      debugPrint('Search location error: $e');
      if (mounted) {
        setState(() {
          _location = query;
          _userCity = _normalizeCity(query);
          _showToast = true;
         
          _toastType = ToastificationType.success;
        });
      }
    }
  }

  void _showLocationSearchDialog() {
    _locationController.clear();
    _animationController?.forward();

    showModalBottomSheet(
      context: context,
      backgroundColor: _darkBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimationConfiguration.staggeredList(
                position: 0,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Text(
                      'Select Location',
                      style: GoogleFonts.poppins(
                        color: _textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AnimationConfiguration.staggeredList(
                position: 1,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _getUserLocation();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: _inputBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _secondaryTextColor.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Iconsax.location,
                              color: _primaryColor,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Use Current Location',
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            _isLoadingLocation
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF6C9A8B),
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.chevron_right,
                                    color: _secondaryTextColor,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AnimationConfiguration.staggeredList(
                position: 2,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Or search for a location',
                          style: GoogleFonts.poppins(
                            color: _secondaryTextColor,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _locationController,
                          focusNode: _cityFocusNode,
                          onChanged: _debounceCityValidation,
                          style: GoogleFonts.poppins(
                            color: _textColor,
                          ),
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            hintText: 'Enter city name',
                            hintStyle: GoogleFonts.poppins(
                              color: _secondaryTextColor.withOpacity(0.7),
                            ),
                            filled: true,
                            fillColor: _inputBackground,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: Icon(
                              Iconsax.search_normal,
                              color: _secondaryTextColor,
                            ),
                            suffixIcon: _isFetchingSuggestions
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF6C9A8B),
                                      ),
                                    ),
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AnimationConfiguration.staggeredList(
                position: 3,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: _inputBackground,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_locationController.text.isNotEmpty) {
                                _searchLocation(_locationController.text);
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: _primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                            child: Text(
                              'Search',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: _textColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) => _removeOverlay());
  }

  Widget _buildWelcomeCard() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _userDataStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _userData == null) {
          return AnimationConfiguration.staggeredList(
            position: 0,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C9A8B)),
                  ),
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return AnimationConfiguration.staggeredList(
            position: 0,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: Center(
                  child: Text(
                    'Error loading user data',
                    style: GoogleFonts.poppins(
                      color: Colors.redAccent,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        _userData = snapshot.data ?? _userData;
        if (_userData == null) {
          return AnimationConfiguration.staggeredList(
            position: 0,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C9A8B)),
                  ),
                ),
              ),
            ),
          );
        }

        final displayName =
            _userData!['firstName']?.toString().isNotEmpty == true
                ? '${StringExtension(_userData!['firstName'].toString()).capitalize()} ${_userData!['lastName']?.toString().isNotEmpty == true ? StringExtension(_userData!['lastName'].toString()).capitalize() : ''}'
                : 'Player';

        return AnimationConfiguration.staggeredList(
          position: 0,
          duration: const Duration(milliseconds: 500),
          child: SlideAnimation(
            verticalOffset: 50.0,
            child: FadeInAnimation(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _inputBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _secondaryTextColor.withOpacity(0.2),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome Back,',
                            style: GoogleFonts.poppins(
                              color: _primaryColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayName,
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _upcomingMatchesStream(),
                            builder: (context, matchesSnapshot) {
                              if (matchesSnapshot.hasData) {
                                _upcomingMatches = matchesSnapshot.data!;
                              }
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _primaryColor.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Iconsax.calendar,
                                      size: 14,
                                      color: _primaryColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_upcomingMatches.length} Upcoming Matches',
                                      style: GoogleFonts.poppins(
                                        color: _primaryColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _selectedIndex = 2),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _primaryColor,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _userData!['profileImage']?.toString().isNotEmpty == true
                              ? (_userData!['profileImage'].toString().startsWith('http')
                                  ? CachedNetworkImage(
                                      imageUrl: _userData!['profileImage'],
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: _inputBackground,
                                        child: Icon(
                                          Iconsax.user,
                                          color: _primaryColor,
                                          size: 30,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: _inputBackground,
                                        child: Icon(
                                          Iconsax.user,
                                          color: _primaryColor,
                                          size: 30,
                                        ),
                                      ),
                                    )
                                  : Image.asset(
                                      _userData!['profileImage'],
                                      fit: BoxFit.cover,
                                    ))
                              : Container(
                                  color: _inputBackground,
                                  child: Icon(
                                    Iconsax.user,
                                    color: _primaryColor,
                                    size: 30,
                                  ),
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
      },
    );
  }

  Widget _buildActionButtons() {
    return AnimationConfiguration.staggeredList(
      position: 1,
      duration: const Duration(milliseconds: 500),
      child: SlideAnimation(
        verticalOffset: 50.0,
        child: FadeInAnimation(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _inputBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _secondaryTextColor.withOpacity(0.2),
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
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCircularActionButton(
                          icon: Iconsax.cup,
                          label: 'Tournaments',
                          onTap: () => setState(() => _selectedIndex = 1),
                        ),
                        _buildCircularActionButton(
                          icon: Iconsax.play_circle,
                          label: 'Live Matches',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LiveMatchesPage(),
                              ),
                            );
                          },
                        ),
                        _buildCircularActionButton(
                          icon: Iconsax.clock,
                          label: 'My Matches',
                          onTap: () async {
                            final authState = context.read<AuthBloc>().state;
                            if (authState is AuthAuthenticated) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MatchHistoryPage(playerId: authState.user.uid),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          _buildModernButton(
                            text: 'Play',
                            onTap: () {
                              setState(() {
                                _showToast = true;
                                _toastMessage = 'Play Feature Coming Soon!';
                                _toastType = ToastificationType.info;
                              });
                            },
                          ),
                          const SizedBox(height: 2),
                          _buildModernButton(
                            text: 'Book',
                            onTap: () {
                              setState(() {
                                _showToast = true;
                                _toastMessage = 'Book Feature Coming Soon!';
                                _toastType = ToastificationType.info;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        height: 156,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _textColor.withOpacity(0.2),
                              ),
                              child: Icon(
                                Iconsax.favorite_chart,
                                color: _textColor,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Train',
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernButton({
    required String text,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.all(8),
      height: 70,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryColor, _primaryColor.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextButton(
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              text == 'Play' ? Iconsax.play : Iconsax.calendar,
              color: _textColor,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: GoogleFonts.poppins(
                color: _textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _inputBackground,
              border: Border.all(
                color: _secondaryTextColor.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: _primaryColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: _textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showLogoutConfirmationDialog() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _darkBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimationConfiguration.staggeredList(
                position: 0,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Icon(
                      Iconsax.logout,
                      color: _primaryColor,
                      size: 40,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AnimationConfiguration.staggeredList(
                position: 1,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Text(
                      'Confirm Logout',
                      style: GoogleFonts.poppins(
                        color: _textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimationConfiguration.staggeredList(
                position: 2,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Text(
                      'Are you sure you want to logout?',
                      style: GoogleFonts.poppins(
                        color: _secondaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              AnimationConfiguration.staggeredList(
                position: 3,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            backgroundColor: _inputBackground,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                          ),
                          child: Text(
                            'Logout',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: _textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
            style: GoogleFonts.poppins(
              color: _textColor,
            ),
          ),
          description: Text(
            _toastMessage!,
            style: GoogleFonts.poppins(
              color: _secondaryTextColor,
            ),
          ),
          autoCloseDuration: const Duration(seconds: 3),
          backgroundColor:
              _toastType == ToastificationType.success
                  ? _primaryColor
                  : _toastType == ToastificationType.error
                      ? Colors.redAccent
                      : Colors.amber,
          foregroundColor: _textColor,
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
        if (state is AuthUnauthenticated && !_hasNavigated && mounted) {
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
              backgroundColor: _darkBackground,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loading...',
                      style: GoogleFonts.poppins(
                        color: _textColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final List<Widget> pages = [
            SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildWelcomeCard(),
                  _buildActionButtons(),
                  AnimationConfiguration.staggeredList(
                    position: 2,
                    duration: const Duration(milliseconds: 500),
                    child: SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Made with ❤️ by SmashLive',
                            style: GoogleFonts.poppins(
                              color: _secondaryTextColor.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            PlayPage(userCity: _userCity, key: ValueKey(_userCity)),
            const PlayerProfilePage(),
          ];

          return WillPopScope(
            onWillPop: () async {
              if (_selectedIndex != 0) {
                setState(() => _selectedIndex = 0);
                return false;
              }
              return true;
            },
            child: Scaffold(
              backgroundColor: _darkBackground,
              appBar: _selectedIndex != 2
                  ? AppBar(
                      elevation: 0,
                      toolbarHeight: 90,
                      backgroundColor: Colors.transparent,
                      flexibleSpace: Container(
                        decoration: BoxDecoration(
                          color: Color(0xFF6C9A8B),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimationConfiguration.staggeredList(
                            position: 0,
                            duration: const Duration(milliseconds: 500),
                            child: SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(
                                child: Text(
                                  'SmashLive',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 28,
                                    color: _textColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimationConfiguration.staggeredList(
                            position: 1,
                            duration: const Duration(milliseconds: 500),
                            child: SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(
                                child: GestureDetector(
                                  onTap: _showLocationSearchDialog,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Iconsax.location,
                                        color: _textColor,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      _isLoadingLocation && !_locationFetchCompleted
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                              ),
                                            )
                                          : Flexible(
                                              child: Text(
                                                _location,
                                                style: GoogleFonts.poppins(
                                                  color: _textColor,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: _textColor,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        AnimationConfiguration.staggeredList(
                          position: 2,
                          duration: const Duration(milliseconds: 500),
                          child: SlideAnimation(
                            verticalOffset: 50.0,
                            child: FadeInAnimation(
                              child: IconButton(
                                icon: Icon(
                                  Iconsax.logout,
                                  color: _textColor,
                                ),
                                onPressed: () async {
                                  final shouldLogout = await _showLogoutConfirmationDialog();
                                  if (shouldLogout == true && mounted) {
                                    context.read<AuthBloc>().add(AuthLogoutEvent());
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
              body: AnimationConfiguration.synchronized(
                duration: const Duration(milliseconds: 600),
                child: pages[_selectedIndex],
              ),
              bottomNavigationBar: AnimationConfiguration.staggeredList(
                position: 0,
                duration: const Duration(milliseconds: 500),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: _inputBackground,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BottomNavigationBar(
                          backgroundColor: _inputBackground,
                          selectedItemColor: _primaryColor,
                          unselectedItemColor: _secondaryTextColor.withOpacity(0.7),
                          currentIndex: _selectedIndex,
                          onTap: _onItemTapped,
                          type: BottomNavigationBarType.fixed,
                          elevation: 0,
                          selectedLabelStyle: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          unselectedLabelStyle: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          items: [
                            BottomNavigationBarItem(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _selectedIndex == 0
                                      ? _primaryColor.withOpacity(0.2)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _selectedIndex == 0
                                      ? Iconsax.home_25
                                      : Iconsax.home_2,
                                  size: 24,
                                ),
                              ),
                              label: 'Home',
                            ),
                            BottomNavigationBarItem(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _selectedIndex == 1
                                      ? _primaryColor.withOpacity(0.2)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _selectedIndex == 1
                                      ? Iconsax.cup5
                                      : Iconsax.cup,
                                  size: 24,
                                ),
                              ),
                              label: 'Tournaments',
                            ),
                            BottomNavigationBarItem(
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _selectedIndex == 2
                                      ? _primaryColor.withOpacity(0.2)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _selectedIndex == 2
                                      ? Iconsax.profile_tick5
                                      : Iconsax.profile_tick,
                                  size: 24,
                                ),
                              ),
                              label: 'Profile',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}



class LiveMatchesPage extends StatefulWidget {
  const LiveMatchesPage({super.key});

  @override
  State<LiveMatchesPage> createState() => _LiveMatchesPageState();
}

class _LiveMatchesPageState extends State<LiveMatchesPage> {
  List<Map<String, dynamic>> _liveMatches = [];
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<QuerySnapshot>? _matchesSubscription;
  Timer? _refreshTimer;

  // Color scheme
  static const Color _darkBackground = Color(0xFF121212);
  static const Color _primaryColor = Color(0xFF6C9A8B);
  static const Color _textColor = Colors.white;
  static const Color _secondaryTextColor = Color(0xFFC1DADB);
  static const Color _inputBackground = Color(0xFF1E1E1E);
  static const Color _errorColor = Color(0xFFE76F51);
  static const Color _successColor = Color(0xFF2A9D8F);

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _setupLiveMatchesStream();
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _matchesSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _fetchLiveMatches();
      }
    });
  }

  void _setupLiveMatchesStream() {
    _fetchLiveMatches();
  }

  Future<void> _fetchLiveMatches() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('Fetching live matches...');

      // Get all tournaments
      final tournamentsQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .get();

      debugPrint('Found ${tournamentsQuery.docs.length} tournaments');

      final List<Map<String, dynamic>> liveMatches = [];

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

        // Check the matches subcollection for live matches
        final matchesSnapshot = await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(tournamentDoc.id)
            .collection('matches')
            .where('liveScores.isLive', isEqualTo: true)
            .get();

        for (var matchDoc in matchesSnapshot.docs) {
          final match = matchDoc.data();
          
          debugPrint('Live match found: ${match['player1']} vs ${match['player2']}');
          
          final startTime = match['startTime'] as Timestamp? ?? tournamentData['startDate'] as Timestamp?;
          tz.TZDateTime? startTimeInTz;
          
          if (startTime != null) {
            startTimeInTz = tz.TZDateTime.from(startTime.toDate(), tzLocation);
          }
          
          liveMatches.add({
            ...match,
            'matchId': matchDoc.id,
            'tournamentId': tournamentDoc.id,
            'tournamentName': tournamentData['name'] ?? 'Unnamed Tournament',
            'startTime': startTime,
            'startTimeInTz': startTimeInTz,
            'timezone': tournamentTimezone,
            'venue': tournamentData['venue'] ?? 'Unknown Venue',
            'city': tournamentData['city'] ?? 'Unknown City',
          });
        }
      }

      if (mounted) {
        setState(() {
          _liveMatches = liveMatches
            ..sort((a, b) {
              // Sort by match start time, most recent first
              final aTime = a['startTimeInTz'] as tz.TZDateTime?;
              final bTime = b['startTimeInTz'] as tz.TZDateTime?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
          _isLoading = false;
          
          if (liveMatches.isEmpty) {
            debugPrint('No live matches found');
          } else {
            debugPrint('Successfully found ${liveMatches.length} live matches');
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching live matches: $e\nStack: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load live matches: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
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
          matchIndex: _liveMatches.indexOf(match),
          isCreator: false,
          isDoubles: isDoubles,
          isUmpire: false,
          onDeleteMatch: () {},
        ),
      ),
    );
  }

  Widget _buildLiveMatchCard(BuildContext context, Map<String, dynamic> match, int index) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    
    final isDoubles = match['team1Ids'] != null && (match['team1Ids'] as List).isNotEmpty;
    final player1Name = isDoubles 
        ? (match['team1'] as List?)?.join(', ') ?? 'Team 1'
        : match['player1'] as String? ?? 'Player 1';
    final player2Name = isDoubles 
        ? (match['team2'] as List?)?.join(', ') ?? 'Team 2'
        : match['player2'] as String? ?? 'Player 2';
    
    final liveScores = match['liveScores'] as Map<String, dynamic>? ?? {};
    final currentGame = liveScores['currentGame'] ?? 1;
    final team1Key = isDoubles ? 'team1' : 'player1';
    final team2Key = isDoubles ? 'team2' : 'player2';
    final player1Scores = List<int>.from(liveScores[team1Key] ?? [0, 0, 0]);
    final player2Scores = List<int>.from(liveScores[team2Key] ?? [0, 0, 0]);
    final currentSetScore1 = player1Scores.length >= currentGame ? player1Scores[currentGame - 1] : 0;
    final currentSetScore2 = player2Scores.length >= currentGame ? player2Scores[currentGame - 1] : 0;
    
    // Calculate set wins
    int player1SetWins = 0;
    int player2SetWins = 0;
    for (int i = 0; i < currentGame - 1; i++) {
      if (i < player1Scores.length && i < player2Scores.length) {
        final p1Score = player1Scores[i];
        final p2Score = player2Scores[i];
        if ((p1Score >= 21 && (p1Score - p2Score) >= 2) || p1Score == 30) {
          player1SetWins++;
        } else if ((p2Score >= 21 && (p2Score - p1Score) >= 2) || p2Score == 30) {
          player2SetWins++;
        }
      }
    }
    
    final startTimeInTz = match['startTimeInTz'] as tz.TZDateTime?;
    String formattedTime = 'Time not available';
    if (startTimeInTz != null) {
      final timezoneDisplay = match['timezone'] == 'Asia/Kolkata' ? 'IST' : match['timezone'];
      formattedTime = '${DateFormat('hh:mm a').format(startTimeInTz)} $timezoneDisplay';
    }

    // Get current server info
    final currentServer = liveScores['currentServer'];
    final isPlayer1Serving = currentServer == team1Key;
    final isPlayer2Serving = currentServer == team2Key;

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
                color: _primaryColor.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: _primaryColor.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tournament name and Live badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        match['tournamentName'] as String,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                          fontSize: isTablet ? 18 : 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 14 : 12,
                        vertical: isTablet ? 8 : 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE76F51), Color(0xFFF4A261)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE76F51).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: isTablet ? 10 : 8,
                            height: isTablet ? 10 : 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: isTablet ? 8 : 6),
                          Text(
                            'LIVE',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: isTablet ? 12 : 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 16 : 12),
                
                // Match participants and scores
                Container(
                  padding: EdgeInsets.all(isTablet ? 20 : 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _primaryColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Player 1
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (isPlayer1Serving) ...[
                                  Icon(
                                    Icons.sports_tennis,
                                    color: _successColor,
                                    size: isTablet ? 18 : 16,
                                  ),
                                  SizedBox(width: isTablet ? 8 : 6),
                                ],
                                Expanded(
                                  child: Text(
                                    player1Name,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      color: _textColor,
                                      fontSize: isTablet ? 16 : 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              if (player1SetWins > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _successColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$player1SetWins',
                                    style: GoogleFonts.poppins(
                                      color: _successColor,
                                      fontSize: isTablet ? 14 : 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                SizedBox(width: isTablet ? 12 : 8),
                              ],
                              Text(
                                currentSetScore1.toString(),
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isTablet ? 32 : 28,
                                  color: _primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: isTablet ? 12 : 8),
                      Container(
                        height: 1,
                        color: _secondaryTextColor.withOpacity(0.3),
                      ),
                      SizedBox(height: isTablet ? 12 : 8),
                      // Player 2
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (isPlayer2Serving) ...[
                                  Icon(
                                    Icons.sports_tennis,
                                    color: _successColor,
                                    size: isTablet ? 18 : 16,
                                  ),
                                  SizedBox(width: isTablet ? 8 : 6),
                                ],
                                Expanded(
                                  child: Text(
                                    player2Name,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      color: _textColor,
                                      fontSize: isTablet ? 16 : 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              if (player2SetWins > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _successColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$player2SetWins',
                                    style: GoogleFonts.poppins(
                                      color: _successColor,
                                      fontSize: isTablet ? 14 : 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                SizedBox(width: isTablet ? 12 : 8),
                              ],
                              Text(
                                currentSetScore2.toString(),
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isTablet ? 32 : 28,
                                  color: _primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: isTablet ? 16 : 12),
                
                // Match info
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: isTablet ? 18 : 16,
                      color: _secondaryTextColor,
                    ),
                    SizedBox(width: isTablet ? 8 : 6),
                    Text(
                      'Started at $formattedTime',
                      style: GoogleFonts.poppins(
                        color: _secondaryTextColor,
                        fontSize: isTablet ? 14 : 12,
                      ),
                    ),
                  ],
                ),
                
                if (match['court'] != null) ...[
                  SizedBox(height: isTablet ? 8 : 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: isTablet ? 18 : 16,
                        color: _secondaryTextColor,
                      ),
                      SizedBox(width: isTablet ? 8 : 6),
                      Text(
                        'Court ${match['court']}',
                        style: GoogleFonts.poppins(
                          color: _secondaryTextColor,
                          fontSize: isTablet ? 14 : 12,
                        ),
                      ),
                    ],
                  ),
                ],
                
                SizedBox(height: isTablet ? 8 : 4),
                Row(
                  children: [
                    Icon(
                      Icons.sports_tennis,
                      size: isTablet ? 18 : 16,
                      color: _secondaryTextColor,
                    ),
                    SizedBox(width: isTablet ? 8 : 6),
                    Text(
                      'Set $currentGame • ${match['eventId'] ?? 'Event'}',
                      style: GoogleFonts.poppins(
                        color: _secondaryTextColor,
                        fontSize: isTablet ? 14 : 12,
                      ),
                    ),
                  ],
                ),
                
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
                      'View Live Match',
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
                    Iconsax.play_circle,
                    color: _secondaryTextColor.withOpacity(0.7),
                    size: isTablet ? 80 : 60,
                  ),
                  SizedBox(height: isTablet ? 24 : 16),
                  Text(
                    'No live matches at the moment',
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: isTablet ? 22 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: isTablet ? 12 : 8),
                  Text(
                    'Check back later for live match updates',
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
                    'Error Loading Live Matches',
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
                    onPressed: _fetchLiveMatches,
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF121212),
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _darkBackground,
        appBar: AppBar(
          title: AnimationConfiguration.staggeredList(
            position: 0,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              horizontalOffset: 50.0,
              child: FadeInAnimation(
                child: Text(
                  'Live Matches',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 24 : 20,
                    color: _textColor,
                  ),
                ),
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_inputBackground, _darkBackground],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          leading: AnimationConfiguration.staggeredList(
            position: 1,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              horizontalOffset: -50.0,
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
              position: 2,
              duration: const Duration(milliseconds: 500),
              child: SlideAnimation(
                horizontalOffset: 50.0,
                child: FadeInAnimation(
                  child: IconButton(
                    icon: Icon(Iconsax.refresh, color: _textColor, size: isTablet ? 28 : 24),
                    onPressed: _fetchLiveMatches,
                    tooltip: 'Refresh Live Matches',
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
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                              strokeWidth: isTablet ? 3.5 : 3,
                            ),
                            SizedBox(height: isTablet ? 20 : 16),
                            Text(
                              'Loading live matches...',
                              style: GoogleFonts.poppins(
                                color: _secondaryTextColor,
                                fontSize: isTablet ? 16 : 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : _errorMessage != null
                  ? _buildErrorState(context)
                  : _liveMatches.isEmpty
                      ? _buildEmptyState(context)
                      : AnimationConfiguration.synchronized(
                          duration: const Duration(milliseconds: 600),
                          child: RefreshIndicator(
                            onRefresh: _fetchLiveMatches,
                            color: _primaryColor,
                            backgroundColor: _inputBackground,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _liveMatches.length,
                              itemBuilder: (context, index) {
                                return _buildLiveMatchCard(context, _liveMatches[index], index);
                              },
                            ),
                          ),
                        ),
        ),
      ),
    );
  }
}