import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/organiser_pages/organiserhomepage.dart';
import 'package:game_app/tournaments/event_form_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CreateTournamentPage extends StatefulWidget {
  final String userId;
  final VoidCallback? onBackPressed;
  final VoidCallback? onTournamentCreated;

  const CreateTournamentPage({
    super.key,
    required this.userId,
    this.onBackPressed,
    this.onTournamentCreated,
  });

  @override
  State<CreateTournamentPage> createState() => _CreateTournamentPageState();
}

class _CreateTournamentPageState extends State<CreateTournamentPage> with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFFF5F5F5);
  static const Color secondaryColor = Color(0xFFFFFFFF);
  static const Color accentColor = Color(0xFF4E6BFF);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color borderColor = Color(0xFFB0B0B0);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color errorColor = Color(0xFFF44336);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _venueController = TextEditingController();
  final _venueAddressController = TextEditingController();
  final _cityController = TextEditingController();
  final _entryFeeController = TextEditingController();
  final _extraFeeController = TextEditingController();
  final _rulesController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactNumberController = TextEditingController();
  tz.TZDateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  tz.TZDateTime? _selectedEndDate;
  tz.TZDateTime? _registrationEndDate;
  final String _playStyle = "Men's Singles";
  final String _eventType = 'Knockout';
  final bool _bringOwnEquipment = false;
  final bool _costShared = false;
  bool _canPayAtVenue = false;
  bool _isLoading = false;
  String? _fetchedCity;
  bool _isFetchingLocation = false;
  bool _isCityValid = true;
  bool _isValidatingCity = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  String _fullAddress = '';
  Timer? _debounceTimer;
  String _selectedTimezone = 'UTC';
  File? _profileImage;
  File? _sponsorImage;
  bool _isFetchingSuggestions = false;
  final FocusNode _cityFocusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  List<String> _citySuggestions = [];
  final String _googlePlacesApiKey = dotenv.get('GOOGLE_PLACES_API_KEY');
  late TextEditingController _timezoneSearchController;

  static const Map<String, String> _cityToTimezone = {
    // North America
    'new york': 'America/New_York',
    'los angeles': 'America/Los_Angeles',
    'chicago': 'America/Chicago',
    'phoenix': 'America/Phoenix',
    'denver': 'America/Denver',
    'anchorage': 'America/Anchorage',
    'honolulu': 'Pacific/Honolulu',
    'toronto': 'America/Toronto',
    'vancouver': 'America/Vancouver',
    'mexico city': 'America/Mexico_City',
    'montreal': 'America/Toronto',
    'calgary': 'America/Edmonton',
    'winnipeg': 'America/Winnipeg',
    'halifax': 'America/Halifax',
    'st. john\'s': 'America/St_Johns',
    // South America
    'buenos aires': 'America/Argentina/Buenos_Aires',
    'sao paulo': 'America/Sao_Paulo',
    'rio de janeiro': 'America/Sao_Paulo',
    'lima': 'America/Lima',
    'bogota': 'America/Bogota',
    'santiago': 'America/Santiago',
    'caracas': 'America/Caracas',
    // Europe
    'london': 'Europe/London',
    'paris': 'Europe/Paris',
    'berlin': 'Europe/Berlin',
    'rome': 'Europe/Rome',
    'madrid': 'Europe/Madrid',
    'amsterdam': 'Europe/Amsterdam',
    'brussels': 'Europe/Brussels',
    'vienna': 'Europe/Vienna',
    'prague': 'Europe/Prague',
    'budapest': 'Europe/Budapest',
    'warsaw': 'Europe/Warsaw',
    'stockholm': 'Europe/Stockholm',
    'oslo': 'Europe/Oslo',
    'copenhagen': 'Europe/Copenhagen',
    'helsinki': 'Europe/Helsinki',
    'athens': 'Europe/Athens',
    'lisbon': 'Europe/Lisbon',
    'dublin': 'Europe/Dublin',
    'zurich': 'Europe/Zurich',
    'moscow': 'Europe/Moscow',
    'istanbul': 'Europe/Istanbul',
    // Asia
    'mumbai': 'Asia/Kolkata',
    'delhi': 'Asia/Kolkata',
    'bangalore': 'Asia/Kolkata',
    'chennai': 'Asia/Kolkata',
    'kolkata': 'Asia/Kolkata',
    'hyderabad': 'Asia/Kolkata',
    'singapore': 'Asia/Singapore',
    'kuala lumpur': 'Asia/Kuala_Lumpur',
    'jakarta': 'Asia/Jakarta',
    'bangkok': 'Asia/Bangkok',
    'manila': 'Asia/Manila',
    'hanoi': 'Asia/Bangkok',
    'ho chi minh city': 'Asia/Bangkok',
    'beijing': 'Asia/Shanghai',
    'shanghai': 'Asia/Shanghai',
    'hong kong': 'Asia/Hong_Kong',
    'taipei': 'Asia/Taipei',
    'seoul': 'Asia/Seoul',
    'tokyo': 'Asia/Tokyo',
    'osaka': 'Asia/Tokyo',
    'dubai': 'Asia/Dubai',
    'abu dhabi': 'Asia/Dubai',
    'riyadh': 'Asia/Riyadh',
    'doha': 'Asia/Qatar',
    'tel aviv': 'Asia/Jerusalem',
    'jerusalem': 'Asia/Jerusalem',
    'baghdad': 'Asia/Baghdad',
    'tehran': 'Asia/Tehran',
    'karachi': 'Asia/Karachi',
    'dhaka': 'Asia/Dhaka',
    // Australia & Pacific
    'sydney': 'Australia/Sydney',
    'melbourne': 'Australia/Melbourne',
    'brisbane': 'Australia/Brisbane',
    'perth': 'Australia/Perth',
    'adelaide': 'Australia/Adelaide',
    'darwin': 'Australia/Darwin',
    'hobart': 'Australia/Hobart',
    'auckland': 'Pacific/Auckland',
    'wellington': 'Pacific/Auckland',
    'fiji': 'Pacific/Fiji',
    // Africa
    'cairo': 'Africa/Cairo',
    'johannesburg': 'Africa/Johannesburg',
    'cape town': 'Africa/Johannesburg',
    'nairobi': 'Africa/Nairobi',
    'lagos': 'Africa/Lagos',
    'accra': 'Africa/Accra',
    'casablanca': 'Africa/Casablanca',
    'tunis': 'Africa/Tunis',
    'algiers': 'Africa/Algiers',
  };

  static const Map<String, String> _timezoneAliases = {
    'utc': 'UTC',
    'gmt': 'Europe/London',
    'bst': 'Europe/London',
    'est': 'America/New_York',
    'edt': 'America/New_York',
    'cst': 'America/Chicago',
    'cdt': 'America/Chicago',
    'mst': 'America/Denver',
    'mdt': 'America/Denver',
    'pst': 'America/Los_Angeles',
    'pdt': 'America/Los_Angeles',
    'akst': 'America/Anchorage',
    'hst': 'Pacific/Honolulu',
    'ist': 'Asia/Kolkata',
    'jst': 'Asia/Tokyo',
    'kst': 'Asia/Seoul',
    'cst china': 'Asia/Shanghai',
    'aest': 'Australia/Sydney',
    'aedt': 'Australia/Sydney',
    'acst': 'Australia/Adelaide',
    'awst': 'Australia/Perth',
    'nzst': 'Pacific/Auckland',
    'cet': 'Europe/Paris',
    'cest': 'Europe/Paris',
    'eet': 'Europe/Helsinki',
    'msk': 'Europe/Moscow',
  };

  final List<String> _allTimezones = tz.timeZoneDatabase.locations.keys.toList()
    ..sort((a, b) => a.compareTo(b));

  final FocusNode _timezoneFocusNode = FocusNode();
  bool _showTimezoneDropdown = false;

  @override
  void initState() {
    super.initState();
    _rulesController.text = _defaultRules();
    _initializeAnimations();
    _initLocationServices();
    tz.initializeTimeZones();

    _cityFocusNode.addListener(_onCityFocusChanged);
    _timezoneFocusNode.addListener(_onTimezoneFocusChanged);
    _timezoneSearchController = TextEditingController();
    _timezoneSearchController.addListener(() {
      setState(() {});
    });
  }

  String _defaultRules() {
    return '''
1. Matches follow BWF regulations - best of 3 games to 21 points
2. Players must report 15 minutes before scheduled match time
3. Proper sports attire and non-marking shoes required
4. Tournament director reserves right to modify rules
5. Disputes resolved by tournament committee
''';
  }

  void _onCityFocusChanged() {
    if (!_cityFocusNode.hasFocus && _citySuggestions.isNotEmpty) {
      // Delay removal to allow tap to work
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!_cityFocusNode.hasFocus) {
          _removeOverlay();
        }
      });
    }
  }

  void _onTimezoneFocusChanged() {
    if (!_timezoneFocusNode.hasFocus) {
      _hideTimezoneDropdown();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() {
      _citySuggestions = [];
    });
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
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&types=(cities)&key=$_googlePlacesApiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = data['predictions'] as List<dynamic>?;

        if (predictions != null && predictions.isNotEmpty) {
          final suggestions = predictions
              .map<String>((prediction) => prediction['description'] as String)
              .where((city) => city.isNotEmpty)
              .toList();

          setState(() {
            _citySuggestions = suggestions;
            _isFetchingSuggestions = false;
          });

          if (_citySuggestions.isNotEmpty && context.mounted && _cityFocusNode.hasFocus) {
            final renderBox = context.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              _showSuggestionsOverlay(_citySuggestions, context, renderBox);
            }
          } else {
            _removeOverlay();
          }
        } else {
          setState(() {
            _citySuggestions = [];
            _isFetchingSuggestions = false;
          });
          _removeOverlay();
          _fetchCitySuggestionsFallback(query);
        }
      } else {
        setState(() {
          _isFetchingSuggestions = false;
        });
        _removeOverlay();
        _fetchCitySuggestionsFallback(query);
      }
    } catch (e) {
      setState(() {
        _isFetchingSuggestions = false;
      });
      _removeOverlay();
      _fetchCitySuggestionsFallback(query);
    }
  }

  Future<void> _fetchCitySuggestionsFallback(String query) async {
    try {
      final locations = await locationFromAddress(query);
      final placemarks = await Future.wait(
        locations.take(5).map((loc) => placemarkFromCoordinates(loc.latitude, loc.longitude)),
      );

      final suggestions = placemarks
          .expand((placemarkList) => placemarkList)
          .map((placemark) => placemark.locality ?? placemark.administrativeArea ?? '')
          .where((city) => city.isNotEmpty)
          .toSet()
          .toList();

      setState(() {
        _citySuggestions = suggestions;
        _isFetchingSuggestions = false;
      });

      if (_citySuggestions.isNotEmpty && context.mounted && _cityFocusNode.hasFocus) {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          _showSuggestionsOverlay(_citySuggestions, context, renderBox);
        }
      } else {
        _removeOverlay();
      }
    } catch (e) {
      setState(() {
        _isFetchingSuggestions = false;
      });
      _removeOverlay();
    }
  }

  void _showSuggestionsOverlay(List<String> suggestions, BuildContext context, RenderBox renderBox) {
    _removeOverlay();

    if (!context.mounted || !_cityFocusNode.hasFocus) return;

    final width = renderBox.size.width;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + renderBox.size.height + 4,
        width: width,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: secondaryColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
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
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    _handleCitySelection(city);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && _overlayEntry != null) {
        Overlay.of(context).insert(_overlayEntry!);
      }
    });
  }

  void _handleCitySelection(String city) async {
  setState(() {
    _cityController.text = city;
    _isCityValid = true;
    _selectedTimezone = _getTimezoneForCity(city.toLowerCase());
    _citySuggestions = [];
  });
  
  await _validateCityWithGeocoding(city);
  await _fetchFullAddress(city); 
  _removeOverlay();
  _cityFocusNode.unfocus();
}



Future<void> _fetchFullAddress(String city) async {
  try {
    final locations = await locationFromAddress(city);
    if (locations.isNotEmpty) {
      final place = locations.first;
      final placemarks = await placemarkFromCoordinates(
        place.latitude,
        place.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final country = placemark.country ?? '';
        // Store the full address including country
        _fullAddress = '$city, $country';
      }
    }
  } catch (e) {
    print('Error fetching full address: $e');
    _fullAddress = city; // Fallback to just city
  }
}


  Future<void> _validateCityWithGeocoding(String city) async {
    if (city.isEmpty) {
      setState(() {
        _isCityValid = false;
        _selectedTimezone = 'UTC';
      });
      return;
    }

    setState(() {
      _isValidatingCity = true;
    });

    try {
      String timezone = _getTimezoneForCity(city);

      if (timezone == 'UTC') {
        final locations = await locationFromAddress(city);
        if (locations.isNotEmpty) {
          final place = locations.first;
          try {
            final timezoneName = await _getTimezoneFromCoordinates(
              place.latitude,
              place.longitude,
            );
            if (timezoneName != null) {
              timezone = timezoneName;
            } else {
              final placemarks = await placemarkFromCoordinates(
                place.latitude,
                place.longitude,
              );
              if (placemarks.isNotEmpty) {
                final countryCode = placemarks.first.isoCountryCode?.toLowerCase();
                timezone = _getCountryTimezone(countryCode) ?? 'UTC';
              }
            }
          } catch (e) {
            print('Error getting timezone from coordinates: $e');
            timezone = 'UTC';
          }
        }
      }

      try {
        tz.getLocation(timezone);
        setState(() {
          _isCityValid = true;
          _selectedTimezone = timezone;
          _isValidatingCity = false;
        });
      } catch (e) {
        setState(() {
          _isCityValid = true;
          _selectedTimezone = 'UTC';
          _isValidatingCity = false;
        });
      }
    } catch (e) {
      setState(() {
        _isCityValid = false;
        _selectedTimezone = 'UTC';
        _isValidatingCity = false;
      });
    }
  }

  Future<String?> _getTimezoneFromCoordinates(double lat, double lng) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/timezone/json?'
          'location=$lat,$lng&timestamp=$timestamp&key=$_googlePlacesApiKey',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return data['timeZoneId'];
        }
      }
      return null;
    } catch (e) {
      print('Error fetching timezone from coordinates: $e');
      return null;
    }
  }

  String? _getCountryTimezone(String? countryCode) {
    const countryTimezones = {
      'in': 'Asia/Kolkata',
      'au': 'Australia/Sydney',
      'gb': 'Europe/London',
      'us': 'America/Los_Angeles',
      'jp': 'Asia/Tokyo',
      'cn': 'Asia/Shanghai',
      'sg': 'Asia/Singapore',
      'ae': 'Asia/Dubai',
      'ru': 'Europe/Moscow',
      'fr': 'Europe/Paris',
      'de': 'Europe/Berlin',
    };
    return countryCode != null ? countryTimezones[countryCode.toLowerCase()] : null;
  }

  String _getTimezoneForCity(String city) {
    final cityLower = city.toLowerCase().trim();
    if (_cityToTimezone.containsKey(cityLower)) {
      return _cityToTimezone[cityLower]!;
    }
    for (final entry in _cityToTimezone.entries) {
      if (cityLower.contains(entry.key) || entry.key.contains(cityLower)) {
        return entry.value;
      }
    }
    return 'UTC';
  }

  Future<void> _selectDate(BuildContext context, {required bool isStartDate, bool isRegistration = false}) async {
    final timeZone = tz.getLocation(_selectedTimezone);
    final now = tz.TZDateTime.now(timeZone);

    DateTime firstDate = now;
    if (!isStartDate && !isRegistration && _selectedDate != null) {
      firstDate = _selectedDate!;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate || isRegistration ? now : (_selectedEndDate ?? (_selectedDate ?? now)),
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: accentColor,
              onPrimary: Colors.white,
              surface: secondaryColor,
              onSurface: textPrimary,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: accentColor),
            ),
            dialogBackgroundColor: secondaryColor,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        if (isRegistration) {
          _registrationEndDate = tz.TZDateTime(
            timeZone,
            picked.year,
            picked.month,
            picked.day,
          );
        } else if (isStartDate) {
          _selectedDate = tz.TZDateTime(
            timeZone,
            picked.year,
            picked.month,
            picked.day,
          );
        } else {
          _selectedEndDate = tz.TZDateTime(
            timeZone,
            picked.year,
            picked.month,
            picked.day,
          );
        }
      });
      if (isStartDate && !isRegistration) {
        await _selectTime(context);
      }
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final timeZone = tz.getLocation(_selectedTimezone);
    final now = tz.TZDateTime.now(timeZone);

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: accentColor,
              onPrimary: Colors.white,
              surface: secondaryColor,
              onSurface: textPrimary,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: accentColor),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _pickImage(bool isProfile) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null && mounted) {
      setState(() {
        if (isProfile) {
          _profileImage = File(pickedFile.path);
        } else {
          _sponsorImage = File(pickedFile.path);
        }
      });
    }
  }

  void _discardImage(bool isProfile) {
    setState(() {
      if (isProfile) {
        _profileImage = null;
      } else {
        _sponsorImage = null;
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _venueAddressController.dispose();
    _cityController.dispose();
    _entryFeeController.dispose();
    _extraFeeController.dispose();
    _rulesController.dispose();
    _maxParticipantsController.dispose();
    _contactNameController.dispose();
    _contactNumberController.dispose();
    _animationController.dispose();
    _cityFocusNode.dispose();
    _timezoneFocusNode.dispose();
    _timezoneSearchController.dispose();
    _removeOverlay();
    _hideTimezoneDropdown();
    super.dispose();
  }

  Future<void> _initLocationServices() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorToast('Location Error', 'Location services are disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        _showErrorToast('Location Error', 'Location permissions denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showErrorToast('Location Error', 'Location permissions denied. Please enable in settings.');
      return;
    }

    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;

    setState(() {
      _isFetchingLocation = true;
    });

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      ).timeout(const Duration(seconds: 15));

      List<Placemark> placemarks = [];
      try {
        placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      } catch (e) {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      }

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final city = place.locality ?? place.administrativeArea ?? place.subAdministrativeArea ?? place.name;
        if (city != null && city.isNotEmpty) {
          final cityLower = city.toLowerCase();
          String timezoneName = _getTimezoneForCity(cityLower);
          try {
            tz.getLocation(timezoneName);
            setState(() {
              _fetchedCity = city;
              _isCityValid = true;
              _selectedTimezone = timezoneName;
            });
          } catch (e) {
            setState(() {
              _fetchedCity = city;
              _isCityValid = true;
              _selectedTimezone = 'UTC';
            });
            _showErrorToast('Timezone Error', 'Could not determine timezone for $city, defaulting to UTC');
          }
        } else {
          _showErrorToast('Location Error', 'Unable to determine city from location');
        }
      } else {
        _showErrorToast('Location Error', 'No placemarks found for the current location');
      }
    } on TimeoutException {
      _showErrorToast('Location Error', 'Location request timed out');
    } catch (e) {
      _showErrorToast('Location Error', 'Failed to fetch location: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
        });
      }
    }
  }

  void _debounceCityValidation(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _fetchCitySuggestions(value);
      _validateCityWithGeocoding(value);
    });
  }

  Future<void> _createTournament(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDate == null || _selectedTime == null) {
      _showErrorToast('Start Date & Time Required', 'Please select a start date and time');
      return;
    }

    if (_selectedEndDate == null) {
      _showErrorToast('End Date Required', 'Please select an end date');
      return;
    }

    if (_registrationEndDate == null) {
      _showErrorToast('Registration End Date Required', 'Please select a registration end date');
      return;
    }

    if (!_isCityValid) {
      _showErrorToast('Invalid City', 'Please enter a valid city');
      return;
    }

    final timeZone = tz.getLocation(_selectedTimezone);
    final startDateTimeLocal = tz.TZDateTime(
      timeZone,
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    final startDateTimeUTC = startDateTimeLocal.toUtc();
    final endDateLocal = tz.TZDateTime(
      timeZone,
      _selectedEndDate!.year,
      _selectedEndDate!.month,
      _selectedEndDate!.day,
      23, 59, 59,
    );
    final endDateUTC = endDateLocal.toUtc();
    final registrationEndLocal = tz.TZDateTime(
      timeZone,
      _registrationEndDate!.year,
      _registrationEndDate!.month,
      _registrationEndDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    final registrationEndUTC = registrationEndLocal.toUtc();
    
    // Get current time in the selected timezone
    final currentTimeInTimezone = tz.TZDateTime.now(timeZone);

    // FIXED: Registration end date must be AFTER current time
    if (registrationEndLocal.isBefore(currentTimeInTimezone)) {
      _showErrorToast('Invalid Registration Date', 'Registration end date must be in the future');
      return;
    }

    // Registration end date must be BEFORE tournament start date
    if (registrationEndUTC.isAfter(startDateTimeUTC)) {
      _showErrorToast('Invalid Registration Date', 'Registration must end before the tournament starts');
      return;
    }

    if (endDateUTC.isBefore(startDateTimeUTC)) {
      _showErrorToast('Invalid Date Range', 'End date must be on or after start date');
      return;
    }

    final events = await Navigator.push<List<Event>>(
      context,
      MaterialPageRoute(
        builder: (context) => EventFormPage(timezone: _selectedTimezone),
      ),
    );

    if (events == null || events.isEmpty) {
      _showErrorToast('No Events', 'Please add at least one event');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? profileImageUrl;
      String? sponsorImageUrl;

      if (_profileImage != null) {
        final profileStorageRef = FirebaseStorage.instance.ref().child(
          'tournament_images/${DateTime.now().millisecondsSinceEpoch}_profile.jpg',
        );
        await profileStorageRef.putFile(_profileImage!);
        profileImageUrl = await profileStorageRef.getDownloadURL();
      }

      if (_sponsorImage != null) {
        final sponsorStorageRef = FirebaseStorage.instance.ref().child(
          'sponsor_images/${DateTime.now().millisecondsSinceEpoch}_sponsor.jpg',
        );
        await sponsorStorageRef.putFile(_sponsorImage!);
        sponsorImageUrl = await sponsorStorageRef.getDownloadURL();
      }

      final tournamentRef = FirebaseFirestore.instance.collection('tournaments').doc();

      final newTournament = Tournament(
        id: tournamentRef.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
        venue: _venueController.text.trim(),
        city: _cityController.text.trim(),
        startDate: startDateTimeUTC,
        endDate: endDateUTC,
        registrationEnd: registrationEndUTC,
        entryFee: double.tryParse(_entryFeeController.text.trim()) ?? 0.0,
        extraFee: double.tryParse(_extraFeeController.text.trim()),
        canPayAtVenue: _canPayAtVenue,
        status: 'open',
        createdBy: widget.userId,
        createdAt: DateTime.now().toUtc(),
        rules: _rulesController.text.trim().isNotEmpty ? _rulesController.text.trim() : null,
        gameFormat: _playStyle,
        gameType: _eventType,
        bringOwnEquipment: _bringOwnEquipment,
        costShared: _costShared,
        profileImage: profileImageUrl,
        sponsorImage: sponsorImageUrl,
        contactName: _contactNameController.text.trim(),
        contactNumber: _contactNumberController.text.trim(),
        timezone: _selectedTimezone,
        events: events,
      );

      // FIXED: Firestore response parsing error - use proper serialization
      final tournamentData = newTournament.toFirestore();
      await tournamentRef.set(tournamentData);
      
      print('Saved tournament with ID: ${tournamentRef.id} with ${events.length} events');
      _showSuccessToast('Tournament Created', '"${newTournament.name}" has been successfully created');

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 1500));
        widget.onTournamentCreated?.call();
        print('Navigating to OrganizerHomePage with userCity: ${_cityController.text.trim()}');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OrganizerHomePage(
              initialIndex: 2,
              userCity: _fullAddress.isNotEmpty ? _fullAddress : _cityController.text.trim(),
            ),
          ),
        );
      }
    } on FirebaseException catch (e) {
      print('Firestore error: ${e.message}');
      _showErrorToast('Creation Failed', 'Firestore error: ${e.message}');
    } catch (e) {
      print('Error creating tournament: ${e.toString()}');
      _showErrorToast('Creation Failed', 'Failed to create tournament: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessToast(String title, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.success,
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
      description: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
      autoCloseDuration: const Duration(seconds: 4),
      style: ToastificationStyle.fillColored,
      alignment: Alignment.bottomCenter,
      backgroundColor: successColor,
      foregroundColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8,
          spreadRadius: 2,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  void _showErrorToast(String title, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
      description: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
      autoCloseDuration: const Duration(seconds: 4),
      style: ToastificationStyle.fillColored,
      alignment: Alignment.bottomCenter,
      backgroundColor: errorColor,
      foregroundColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8,
          spreadRadius: 2,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  String? _validateCity(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a city';
    }
    return null;
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a contact number';
    }
    if (!RegExp(r'^\+\d{1,3}\d{6,14}$').hasMatch(value)) {
      return 'Enter a valid phone number with country code (e.g., +1234567890)';
    }
    return null;
  }

  Widget _buildRequiredLabel(String text, {required bool isRequired}) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text,
            style: GoogleFonts.poppins(
              color: textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isRequired)
            const TextSpan(
              text: ' *',
              style: TextStyle(
                color: errorColor,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      backgroundColor: primaryColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryColor, Color(0xFFE0E0E0)],
            stops: [0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWideScreen = constraints.maxWidth > 600;
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWideScreen ? constraints.maxWidth * 0.1 : 16.0,
                      vertical: 16.0,
                    ),
                    child: Form(
                      key: _formKey,
                      child: CustomScrollView(
                        slivers: [
                          SliverAppBar(
                            backgroundColor: Color(0xFF6C9A8B),
                            elevation: 4,
                            leading: IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 24),
                              onPressed: () {
                                if (widget.onBackPressed != null) {
                                  widget.onBackPressed!();
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                            ),
                            title: Text(
                              'Create Tournament',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 24,
                                letterSpacing: 0.5,
                              ),
                            ),
                            centerTitle: true,
                            pinned: true,
                            expandedHeight: 80,
                            floating: false,
                            snap: false,
                            stretch: true,
                            surfaceTintColor: Colors.transparent,
                          ),
                          SliverList(
                            delegate: SliverChildListDelegate([
                              const SizedBox(height: 24),
                              _buildSectionContainer(
                                title: 'Info',
                                children: [
                                  _buildTextField(
                                    controller: _nameController,
                                    label: 'Tournament Name',
                                    hintText: 'e.g., Summer Badminton Championship',
                                    icon: Icons.event,
                                    isRequired: true,
                                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a tournament name' : null,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _descriptionController,
                                    label: 'Description',
                                    hintText: 'Describe your tournament...',
                                    icon: Icons.description,
                                    maxLines: 4,
                                    isRequired: false,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildImagePickerField(isProfile: true),
                                  const SizedBox(height: 16),
                                  _buildImagePickerField(isProfile: false),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _contactNameController,
                                    label: 'Contact Name',
                                   
                                    icon: Icons.person,
                                    isRequired: true,
                                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a contact name' : null,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _contactNumberController,
                                    label: 'Contact Number',
                                  
                                    icon: Icons.phone,
                                    keyboardType: TextInputType.phone,
                                    isRequired: true,
                                    validator: _validatePhoneNumber,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildSectionContainer(
                                title: 'Address',
                                children: [
                                  _buildTextField(
                                    controller: _venueAddressController,
                                    label: 'Venue Address',
                                    hintText: 'e.g., 123 Main St',
                                    icon: Icons.map,
                                    maxLines: 3,
                                    isRequired: true,
                                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a venue address' : null,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _venueController,
                                    label: 'Venue Name',
                                    hintText: 'e.g., City Sports Complex',
                                    icon: Icons.location_on,
                                    isRequired: true,
                                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a venue name' : null,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildCityFieldWithSuggestions(),
                                  const SizedBox(height: 16),
                                  _buildTimezoneSelector(),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildSectionContainer(
                                title: 'Timeline',
                                children: [
                                  _buildDateTimeSelector(isSmallScreen: isSmallScreen),
                                  const SizedBox(height: 16),
                                  GestureDetector(
                                    onTap: () => _selectDate(context, isStartDate: false, isRegistration: true),
                                    child: Container(
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: secondaryColor,
                                        border: Border.all(color: borderColor, width: 1),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_today, color: accentColor, size: 20),
                                          const SizedBox(width: 12),
                                          Text(
                                            _registrationEndDate == null
                                                ? 'Registration End Date'
                                                : DateFormat('MMM dd, yyyy').format(_registrationEndDate!),
                                            style: GoogleFonts.poppins(
                                              color: _registrationEndDate == null ? textSecondary : textPrimary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_registrationEndDate != null && _selectedTime != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Registration ends at ${_selectedTime!.format(context)} on ${DateFormat('MMM dd, yyyy').format(_registrationEndDate!)}',
                                        style: GoogleFonts.poppins(
                                          color: textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildSectionContainer(
                                title: 'Price',
                                children: [
                                  isSmallScreen
                                      ? Column(
                                          children: [
                                            _buildTextField(
                                              controller: _entryFeeController,
                                              label: 'Entry Fee (\$)',
                                              hintText: '0 for free entry',
                                              icon: Icons.attach_money,
                                              keyboardType: TextInputType.number,
                                              isRequired: true,
                                              validator: (value) {
                                                if (value == null || value.trim().isEmpty) {
                                                  return 'Enter an entry fee';
                                                }
                                                final fee = double.tryParse(value);
                                                if (fee == null || fee < 0) {
                                                  return 'Enter a valid amount';
                                                }
                                                return null;
                                              },
                                            ),
                                            const SizedBox(height: 16),
                                            _buildTextField(
                                              controller: _extraFeeController,
                                              label: 'Extra Fee (\$)',
                                              hintText: 'Optional extra fee',
                                              icon: Icons.add_circle,
                                              keyboardType: TextInputType.number,
                                              isRequired: false,
                                            ),
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            Expanded(
                                              child: _buildTextField(
                                                controller: _entryFeeController,
                                                label: 'Entry Fee (\$)',
                                                hintText: '0 for free entry',
                                                icon: Icons.attach_money,
                                                keyboardType: TextInputType.number,
                                                isRequired: true,
                                                validator: (value) {
                                                  if (value == null || value.trim().isEmpty) {
                                                    return 'Enter an entry fee';
                                                  }
                                                  final fee = double.tryParse(value);
                                                  if (fee == null || fee < 0) {
                                                    return 'Enter a valid amount';
                                                  }
                                                  return null;
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: _buildTextField(
                                                controller: _extraFeeController,
                                                label: 'Extra Fee (\$)',
                                                hintText: 'Optional extra fee',
                                                icon: Icons.add_circle,
                                                keyboardType: TextInputType.number,
                                                isRequired: false,
                                              ),
                                            ),
                                          ],
                                        ),
                                  const SizedBox(height: 16),
                                  _buildSwitchTile(
                                    title: 'Can Pay at Venue',
                                    subtitle: 'Participants can pay fees at the venue',
                                    value: _canPayAtVenue,
                                    onChanged: (value) {
                                      setState(() {
                                        _canPayAtVenue = value;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildNextButton(context),
                              const SizedBox(height: 40),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionContainer({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    IconData? icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    Widget? suffix,
    ValueChanged<String>? onChanged,
    required bool isRequired,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequiredLabel(label, isRequired: isRequired),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            style: GoogleFonts.poppins(
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: accentColor,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: GoogleFonts.poppins(
                color: textSecondary.withOpacity(0.6),
                fontSize: 14,
              ),
              prefixIcon: icon != null ? Icon(icon, color: accentColor, size: 20) : null,
              suffixIcon: suffix,
              filled: true,
              fillColor: secondaryColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: borderColor, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: accentColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: validator,
          ),
        ),
      ],
    );
  }

  Widget _buildCityFieldWithSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequiredLabel('City', isRequired: true),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: _cityController,
            focusNode: _cityFocusNode,
            style: GoogleFonts.poppins(
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: accentColor,
            onChanged: _debounceCityValidation,
            decoration: InputDecoration(
              hintText: 'Select your city',
              hintStyle: GoogleFonts.poppins(
                color: textSecondary.withOpacity(0.6),
                fontSize: 14,
              ),
              prefixIcon: Icon(Icons.location_city, color: accentColor, size: 20),
              suffixIcon: _isValidatingCity || _isFetchingSuggestions
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    )
                  : Icon(
                      _isCityValid ? Icons.check_circle : Icons.error,
                      color: _isCityValid ? successColor : errorColor,
                      size: 20,
                    ),
              filled: true,
              fillColor: secondaryColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: borderColor, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: accentColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: _validateCity,
          ),
        ),
        if (_citySuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: secondaryColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _citySuggestions.length,
              itemBuilder: (context, index) {
                final city = _citySuggestions[index];
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    city,
                    style: GoogleFonts.poppins(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    _handleCitySelection(city);
                  },
                );
              },
            ),
          ),
        if (!_isFetchingLocation)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: Icon(
                Icons.my_location,
                color: _fetchedCity != null ? accentColor : textSecondary,
                size: 16,
              ),
              label: Text(
                'Use current location',
                style: GoogleFonts.poppins(
                  color: _fetchedCity != null ? accentColor : textSecondary,
                  fontSize: 12,
                ),
              ),
              onPressed: _fetchedCity != null
                  ? () async {
                      if (mounted) {
                        setState(() {
                          _cityController.text = _fetchedCity!;
                          _isValidatingCity = true;
                        });
                        await _validateCityWithGeocoding(_fetchedCity!);
                      }
                    }
                  : null,
            ),
          ),
      ],
    );
  }

  bool _matchesTimezone(String timezone, String query) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    final lowerTz = timezone.toLowerCase();
    if (lowerTz.contains(lowerQuery)) return true;
    for (final entry in _timezoneAliases.entries) {
      if (entry.key.toLowerCase().contains(lowerQuery) && entry.value == timezone) {
        return true;
      }
    }
    return false;
  }

Widget _buildTimezoneSelector() {
  final filteredTimezones = _timezoneSearchController.text.isNotEmpty
      ? _allTimezones.where((tz) => _matchesTimezone(tz, _timezoneSearchController.text)).toList()
      : _allTimezones;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildRequiredLabel('Timezone', isRequired: false),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () {
          _timezoneFocusNode.requestFocus();
          _toggleTimezoneDropdown();
        },
        child: AbsorbPointer(
          absorbing: true,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: secondaryColor,
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedTimezone,
                    style: GoogleFonts.poppins(
                      color: textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  _showTimezoneDropdown ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: textSecondary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
      if (_showTimezoneDropdown)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: secondaryColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _timezoneSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search timezone or abbreviation',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filteredTimezones.length,
                  itemBuilder: (context, index) {
                    final timezone = filteredTimezones[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text(
                        timezone,
                        style: GoogleFonts.poppins(
                          color: textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedTimezone = timezone;
                        });
                        _hideTimezoneDropdown();
                        _timezoneFocusNode.unfocus();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

  void _toggleTimezoneDropdown() {
    setState(() {
      if (_showTimezoneDropdown) {
        _showTimezoneDropdown = false;
      } else {
        _showTimezoneDropdown = true;
        _timezoneSearchController.clear();
      }
    });
  }

  void _hideTimezoneDropdown() {
    setState(() {
      _showTimezoneDropdown = false;
    });
  }

  Widget _buildImagePickerField({required bool isProfile}) {
    final imageFile = isProfile ? _profileImage : _sponsorImage;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequiredLabel(isProfile ? 'Profile Picture' : 'Sponsor Picture', isRequired: false),
        const SizedBox(height: 8),
        Stack(
          children: [
            GestureDetector(
              onTap: () => _pickImage(isProfile),
              child: Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: secondaryColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: imageFile == null
                    ? Center(
                        child: Icon(
                          Icons.add_photo_alternate,
                          color: textSecondary,
                          size: 40,
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          imageFile,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
              ),
            ),
            if (imageFile != null)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _discardImage(isProfile),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: errorColor.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateTimeSelector({required bool isSmallScreen}) {
    final timeZone = tz.getLocation(_selectedTimezone);
    final startDateLocal = _selectedDate != null ? tz.TZDateTime.from(_selectedDate!, timeZone) : null;
    final startTime = _selectedTime ?? (startDateLocal != null
        ? TimeOfDay(hour: startDateLocal.hour, minute: startDateLocal.minute)
        : null);
    final endDateLocal = _selectedEndDate != null ? tz.TZDateTime.from(_selectedEndDate!, timeZone) : null;

    if (isSmallScreen) {
      return Column(
        children: [
          GestureDetector(
            onTap: () => _selectDate(context, isStartDate: true),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: secondaryColor,
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: accentColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    startDateLocal == null
                        ? 'Start Date *'
                        : DateFormat('MMM dd, yyyy').format(startDateLocal),
                    style: GoogleFonts.poppins(
                      color: startDateLocal == null ? textSecondary : textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _selectTime(context),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: secondaryColor,
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time, color: accentColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    startTime == null ? 'Start Time *' : startTime.format(context),
                    style: GoogleFonts.poppins(
                      color: startTime == null ? textSecondary : textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _selectDate(context, isStartDate: false),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: secondaryColor,
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: accentColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    endDateLocal == null
                        ? 'End Date *'
                        : DateFormat('MMM dd, yyyy').format(endDateLocal),
                    style: GoogleFonts.poppins(
                      color: endDateLocal == null ? textSecondary : textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_selectedDate != null && _selectedTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Time in ${_selectedTimezone == 'Asia/Kolkata' ? 'IST' : _selectedTimezone}',
                style: GoogleFonts.poppins(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
        ],
      );
    } else {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectDate(context, isStartDate: true),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: secondaryColor,
                      border: Border.all(color: borderColor, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: accentColor, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          startDateLocal == null
                              ? 'Start Date *'
                              : DateFormat('MMM dd, yyyy').format(startDateLocal),
                          style: GoogleFonts.poppins(
                            color: startDateLocal == null ? textSecondary : textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectTime(context),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: secondaryColor,
                      border: Border.all(color: borderColor, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time, color: accentColor, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          startTime == null ? 'Start Time *' : startTime.format(context),
                          style: GoogleFonts.poppins(
                            color: startTime == null ? textSecondary : textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _selectDate(context, isStartDate: false),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: secondaryColor,
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: accentColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    endDateLocal == null
                        ? 'End Date *'
                        : DateFormat('MMM dd, yyyy').format(endDateLocal),
                    style: GoogleFonts.poppins(
                      color: endDateLocal == null ? textSecondary : textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_selectedDate != null && _selectedTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Time in ${_selectedTimezone == 'Asia/Kolkata' ? 'IST' : _selectedTimezone}',
                style: GoogleFonts.poppins(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
        ],
      );
    }
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: GoogleFonts.poppins(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.poppins(
          color: textSecondary,
          fontSize: 14,
        ),
      ),
      value: value,
      activeColor: accentColor,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildNextButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _createTournament(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
          shadowColor: accentColor.withOpacity(0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                'Next',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}