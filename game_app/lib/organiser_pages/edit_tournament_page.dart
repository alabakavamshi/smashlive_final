import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class EditTournamentPage extends StatefulWidget {
  final Tournament tournament;

  const EditTournamentPage({super.key, required this.tournament});

  @override
  State<EditTournamentPage> createState() => _EditTournamentPageState();
}

class _EditTournamentPageState extends State<EditTournamentPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _venueController = TextEditingController();
  final _cityController = TextEditingController();
  final _entryFeeController = TextEditingController();
  final _extraFeeController = TextEditingController();
  final _rulesController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactNumberController = TextEditingController();
  late tz.TZDateTime _selectedStartDate;
  late TimeOfDay _selectedStartTime;
  late tz.TZDateTime _selectedEndDate;
  late tz.TZDateTime _selectedRegistrationEnd;
  late String _gameFormat;
  late String _gameType;
  late bool _bringOwnEquipment;
  late bool _costShared;
  late bool _canPayAtVenue;
  String? _profileImage;
  String? _sponsorImage;
  bool _isLoading = false;
  bool _isUploadingProfileImage = false;
  bool _isUploadingSponsorImage = false;
  bool _isFetchingLocation = false;
  bool _isCityValid = true;
  bool _isValidatingCity = false;
  Timer? _debounceTimer;
  late String _selectedTimezone;
  List<Event> _events = [];

  late String _initialName;
  late String? _initialDescription;
  late String _initialVenue;
  late String _initialCity;
  late String _initialEntryFee;
  late String _initialExtraFee;
  late String _initialRules;
  late tz.TZDateTime _initialStartDate;
  late TimeOfDay _initialStartTime;
  late tz.TZDateTime _initialEndDate;
  late tz.TZDateTime _initialRegistrationEnd;
  late bool _initialBringOwnEquipment;
  late bool _initialCostShared;
  late bool _initialCanPayAtVenue;
  late String? _initialProfileImage;
  late String? _initialSponsorImage;
  late String _initialTimezone;
  late String? _initialContactName;
  late String? _initialContactNumber;
  late List<Event> _initialEvents;

  final List<String> _gameFormatOptions = [
    "Men's Singles",
    "Women's Singles",
    "Men's Doubles",
    "Women's Doubles",
    "Mixed Doubles",
  ];
  final List<String> _gameTypeOptions = [
    'Badminton',
    'Tennis',
    'Table Tennis',
    'Squash',
    'Pickleball',
  ];

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _nameController.text = widget.tournament.name;
    _descriptionController.text = widget.tournament.description ?? '';
    _venueController.text = widget.tournament.venue;
    _cityController.text = widget.tournament.city;
    _entryFeeController.text = widget.tournament.entryFee.toStringAsFixed(2);
    _extraFeeController.text = widget.tournament.extraFee?.toStringAsFixed(2) ?? '';
    _rulesController.text = widget.tournament.rules?.isNotEmpty ?? false
        ? widget.tournament.rules!
        : '''
1. Matches are best of 3 games, each played to 21 points with a 2-point lead required to win.
2. A rally point system is used; a point is scored on every serve.
3. Players change sides after each game and at 11 points in the third game.
4. A 60-second break is allowed between games, and a 120-second break at 11 points in a game.
5. Service must be diagonal, below the waist, and the shuttle must land within the opponent's court.
6. Faults include: shuttle landing out of bounds, double hits, or player touching the net.
7. Respect the umpire's decisions and maintain sportsmanship at all times.
''';
    _contactNameController.text = widget.tournament.contactName ?? '';
    _contactNumberController.text = widget.tournament.contactNumber ?? '';
    _selectedStartDate = tz.TZDateTime.from(widget.tournament.startDate, tz.getLocation(widget.tournament.timezone));
    _selectedStartTime = widget.tournament.getStartTime();
    _selectedEndDate = tz.TZDateTime.from(widget.tournament.endDate, tz.getLocation(widget.tournament.timezone));
    _selectedRegistrationEnd = tz.TZDateTime.from(widget.tournament.registrationEnd, tz.getLocation(widget.tournament.timezone));
    _gameFormat = _gameFormatOptions.contains(widget.tournament.gameFormat)
        ? widget.tournament.gameFormat
        : _gameFormatOptions[0];
    _gameType = _gameTypeOptions.contains(widget.tournament.gameType)
        ? widget.tournament.gameType
        : _gameTypeOptions[0];
    _bringOwnEquipment = widget.tournament.bringOwnEquipment;
    _costShared = widget.tournament.costShared;
    _canPayAtVenue = widget.tournament.canPayAtVenue;
    _profileImage = widget.tournament.profileImage;
    _sponsorImage = widget.tournament.sponsorImage;
    _selectedTimezone = widget.tournament.timezone;
    _events = widget.tournament.events;

    _initialName = _nameController.text;
    _initialDescription = _descriptionController.text;
    _initialVenue = _venueController.text;
    _initialCity = _cityController.text;
    _initialEntryFee = _entryFeeController.text;
    _initialExtraFee = _extraFeeController.text;
    _initialRules = _rulesController.text;
    _initialStartDate = _selectedStartDate;
    _initialStartTime = _selectedStartTime;
    _initialEndDate = _selectedEndDate;
    _initialRegistrationEnd = _selectedRegistrationEnd;
    _initialBringOwnEquipment = _bringOwnEquipment;
    _initialCostShared = _costShared;
    _initialCanPayAtVenue = _canPayAtVenue;
    _initialProfileImage = _profileImage;
    _initialSponsorImage = _sponsorImage;
    _initialTimezone = _selectedTimezone;
    _initialContactName = _contactNameController.text;
    _initialContactNumber = _contactNumberController.text;
    _initialEvents = List.from(_events);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _cityController.dispose();
    _entryFeeController.dispose();
    _extraFeeController.dispose();
    _rulesController.dispose();
    _contactNameController.dispose();
    _contactNumberController.dispose();
    super.dispose();
  }

  bool _hasChanges() {
    return _nameController.text != _initialName ||
        _descriptionController.text != _initialDescription ||
        _venueController.text != _initialVenue ||
        _cityController.text != _initialCity ||
        _entryFeeController.text != _initialEntryFee ||
        _extraFeeController.text != _initialExtraFee ||
        _rulesController.text != _initialRules ||
        _selectedStartDate != _initialStartDate ||
        _selectedStartTime != _initialStartTime ||
        _selectedEndDate != _initialEndDate ||
        _selectedRegistrationEnd != _initialRegistrationEnd ||
        _bringOwnEquipment != _initialBringOwnEquipment ||
        _costShared != _initialCostShared ||
        _canPayAtVenue != _initialCanPayAtVenue ||
        _profileImage != _initialProfileImage ||
        _sponsorImage != _initialSponsorImage ||
        _selectedTimezone != _initialTimezone ||
        _contactNameController.text != _initialContactName ||
        _contactNumberController.text != _initialContactNumber ||
        _events.length != _initialEvents.length ||
        _events.asMap().entries.any((entry) {
          int idx = entry.key;
          Event event = entry.value;
          Event initialEvent = _initialEvents[idx];
          return event.name != initialEvent.name ||
              event.format != initialEvent.format ||
              event.level != initialEvent.level ||
              event.maxParticipants != initialEvent.maxParticipants ||
              event.bornAfter != initialEvent.bornAfter ||
              event.matchType != initialEvent.matchType ||
              event.matches != initialEvent.matches ||
              event.participants != initialEvent.participants;
        });
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges()) return true;

    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white24),
        ),
        title: Text(
          'Unsaved Changes',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'You have unsaved changes. Are you sure you want to leave?',
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Colors.blueGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Leave',
              style: GoogleFonts.poppins(
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    return shouldPop ?? false;
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final timeZone = tz.getLocation(_selectedTimezone);
    final now = tz.TZDateTime.now(timeZone);
    final firstDate = _selectedStartDate.isBefore(now) ? _selectedStartDate : now;
    final initialDate = _selectedStartDate.isBefore(now) ? now : _selectedStartDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueGrey,
              onPrimary: Colors.white,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final newDateTime = tz.TZDateTime(
        timeZone,
        picked.year,
        picked.month,
        picked.day,
        _selectedStartTime.hour,
        _selectedStartTime.minute,
      );
      if (newDateTime.isBefore(now)) {
        _showErrorToast('Invalid Start Date', 'Start date cannot be in the past.');
        return;
      }
      setState(() {
        _selectedStartDate = newDateTime;
        if (_selectedEndDate.isBefore(_selectedStartDate)) {
          _selectedEndDate = _selectedStartDate;
          _showErrorToast(
            'End Date Adjusted',
            'End date was adjusted to match start date.',
          );
        }
        if (_selectedRegistrationEnd.isAfter(_selectedStartDate)) {
          _selectedRegistrationEnd = _selectedStartDate;
          _showErrorToast(
            'Registration End Adjusted',
            'Registration end date was adjusted to match start date.',
          );
        }
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final timeZone = tz.getLocation(_selectedTimezone);
    final initialDate = _selectedEndDate.isBefore(_selectedStartDate) ? _selectedStartDate : _selectedEndDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _selectedStartDate,
      lastDate: tz.TZDateTime.now(timeZone).add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueGrey,
              onPrimary: Colors.white,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedEndDate = tz.TZDateTime(
          timeZone,
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      });
    }
  }

  Future<void> _selectRegistrationEndDate(BuildContext context) async {
    final timeZone = tz.getLocation(_selectedTimezone);
    final initialDate = _selectedRegistrationEnd.isAfter(_selectedStartDate)
        ? _selectedStartDate
        : _selectedRegistrationEnd;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: tz.TZDateTime.now(timeZone),
      lastDate: _selectedStartDate,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueGrey,
              onPrimary: Colors.white,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedRegistrationEnd = tz.TZDateTime(
          timeZone,
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      });
    }
  }

  Future<void> _selectStartTime(BuildContext context) async {
    final timeZone = tz.getLocation(_selectedTimezone);

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedStartTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueGrey,
              onPrimary: Colors.white,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedStartTime) {
      final newDateTime = tz.TZDateTime(
        timeZone,
        _selectedStartDate.year,
        _selectedStartDate.month,
        _selectedStartDate.day,
        picked.hour,
        picked.minute,
      );
      if (newDateTime.isBefore(tz.TZDateTime.now(timeZone))) {
        _showErrorToast('Invalid Start Time', 'Start time cannot be in the past.');
        return;
      }
      setState(() {
        _selectedStartTime = picked;
        _selectedStartDate = newDateTime;
        if (_selectedRegistrationEnd.isAfter(_selectedStartDate)) {
          _selectedRegistrationEnd = _selectedStartDate;
          _showErrorToast(
            'Registration End Adjusted',
            'Registration end date was adjusted to match start date.',
          );
        }
      });
    }
  }

  Future<void> _validateCityWithGeocoding(String city) async {
    if (city.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isCityValid = false;
          _isValidatingCity = false;
          _cityController.clear();
          _selectedTimezone = 'UTC';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isValidatingCity = true;
      });
    }

    final normalizedCity = city.trim().toLowerCase();

    try {
      List<Location> locations = await locationFromAddress(normalizedCity).timeout(const Duration(seconds: 5));
      if (locations.isNotEmpty) {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          locations.first.latitude,
          locations.first.longitude,
        ).timeout(const Duration(seconds: 5));

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final fetchedCity = place.locality ?? place.administrativeArea;
          const cityToTimezone = {
            'new york': 'America/New_York',
            'los angeles': 'America/Los_Angeles',
            'california': 'America/Los_Angeles',
            'san francisco': 'America/Los_Angeles',
            'chicago': 'America/Chicago',
            'houston': 'America/Chicago',
            'phoenix': 'America/Phoenix',
            'philadelphia': 'America/New_York',
            'san antonio': 'America/Chicago',
            'san diego': 'America/Los_Angeles',
            'dallas': 'America/Chicago',
            'austin': 'America/Chicago',
            'toronto': 'America/Toronto',
            'montreal': 'America/Toronto',
            'vancouver': 'America/Vancouver',
            'calgary': 'America/Edmonton',
            'ottawa': 'America/Toronto',
            'mexico city': 'America/Mexico_City',
            'tijuana': 'America/Tijuana',
            'monterrey': 'America/Monterrey',
            'london': 'Europe/London',
            'paris': 'Europe/Paris',
            'berlin': 'Europe/Berlin',
            'rome': 'Europe/Rome',
            'madrid': 'Europe/Madrid',
            'mumbai': 'Asia/Kolkata',
            'delhi': 'Asia/Kolkata',
            'bangalore': 'Asia/Kolkata',
            'hyderabad': 'Asia/Kolkata',
            'chennai': 'Asia/Kolkata',
            'kolkata': 'Asia/Kolkata',
            'singapore': 'Asia/Singapore',
            'tokyo': 'Asia/Tokyo',
            'beijing': 'Asia/Shanghai',
            'shanghai': 'Asia/Shanghai',
            'hong kong': 'Asia/Hong_Kong',
            'dubai': 'Asia/Dubai',
            'sydney': 'Australia/Sydney',
            'melbourne': 'Australia/Melbourne',
            'brisbane': 'Australia/Brisbane',
            'perth': 'Australia/Perth',
            'sao paulo': 'America/Sao_Paulo',
            'rio de janeiro': 'America/Sao_Paulo',
            'buenos aires': 'America/Argentina/Buenos_Aires',
            'lima': 'America/Lima',
            'cairo': 'Africa/Cairo',
            'nairobi': 'Africa/Nairobi',
            'lagos': 'Africa/Lagos',
            'johannesburg': 'Africa/Johannesburg',
          };

          final timezoneName = cityToTimezone[normalizedCity] ?? 'UTC';

          if (fetchedCity != null) {
            if (mounted) {
              setState(() {
                _cityController.text = fetchedCity;
                _isCityValid = true;
                _isValidatingCity = false;
                _selectedTimezone = timezoneName;
              });
            }
            return;
          }
        }
      }

      if (normalizedCity.length > 2) {
        List<Location> suggestionLocations = await locationFromAddress(normalizedCity).timeout(const Duration(seconds: 5));
        if (suggestionLocations.isNotEmpty) {
          List<Placemark> suggestions = await placemarkFromCoordinates(
            suggestionLocations.first.latitude,
            suggestionLocations.first.longitude,
          ).timeout(const Duration(seconds: 5));
          if (suggestions.isNotEmpty) {
            final suggestedCity = suggestions.first.locality ?? suggestions.first.administrativeArea;
            const cityToTimezone = {
              'new york': 'America/New_York',
              'los angeles': 'America/Los_Angeles',
              'california': 'America/Los_Angeles',
              'san francisco': 'America/Los_Angeles',
              'chicago': 'America/Chicago',
              'houston': 'America/Chicago',
              'phoenix': 'America/Phoenix',
              'philadelphia': 'America/New_York',
              'san antonio': 'America/Chicago',
              'san diego': 'America/Los_Angeles',
              'dallas': 'America/Chicago',
              'austin': 'America/Chicago',
              'toronto': 'America/Toronto',
              'montreal': 'America/Toronto',
              'vancouver': 'America/Vancouver',
              'calgary': 'America/Edmonton',
              'ottawa': 'America/Toronto',
              'mexico city': 'America/Mexico_City',
              'tijuana': 'America/Tijuana',
              'monterrey': 'America/Monterrey',
              'london': 'Europe/London',
              'paris': 'Europe/Paris',
              'berlin': 'Europe/Berlin',
              'rome': 'Europe/Rome',
              'madrid': 'Europe/Madrid',
              'mumbai': 'Asia/Kolkata',
              'delhi': 'Asia/Kolkata',
              'bangalore': 'Asia/Kolkata',
              'hyderabad': 'Asia/Kolkata',
              'chennai': 'Asia/Kolkata',
              'kolkata': 'Asia/Kolkata',
              'singapore': 'Asia/Singapore',
              'tokyo': 'Asia/Tokyo',
              'beijing': 'Asia/Shanghai',
              'shanghai': 'Asia/Shanghai',
              'hong kong': 'Asia/Hong_Kong',
              'dubai': 'Asia/Dubai',
              'sydney': 'Australia/Sydney',
              'melbourne': 'Australia/Melbourne',
              'brisbane': 'Australia/Brisbane',
              'perth': 'Australia/Perth',
              'sao paulo': 'America/Sao_Paulo',
              'rio de janeiro': 'America/Sao_Paulo',
              'buenos aires': 'America/Argentina/Buenos_Aires',
              'lima': 'America/Lima',
              'cairo': 'Africa/Cairo',
              'nairobi': 'Africa/Nairobi',
              'lagos': 'Africa/Lagos',
              'johannesburg': 'Africa/Johannesburg',
            };

            final timezoneName = cityToTimezone[normalizedCity] ?? 'UTC';

            if (suggestedCity != null) {
              if (mounted) {
                setState(() {
                  _cityController.text = suggestedCity;
                  _isCityValid = true;
                  _isValidatingCity = false;
                  _selectedTimezone = timezoneName;
                });
              }
              return;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _isCityValid = false;
          _isValidatingCity = false;
          _cityController.clear();
          _selectedTimezone = 'UTC';
        });
        _showErrorToast('Invalid City', 'No matching city found for "$normalizedCity"');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCityValid = false;
          _isValidatingCity = false;
          _cityController.clear();
          _selectedTimezone = 'UTC';
        });
        _showErrorToast('Invalid City', 'Geocoding failed for "$normalizedCity": $e');
      }
    }
  }

  void _debounceCityValidation(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 2000), () {
      _validateCityWithGeocoding(value);
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isFetchingLocation = true;
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorToast('Location Permission Denied', 'Please enable location permissions.');
          setState(() {
            _isFetchingLocation = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showErrorToast('Location Permission Denied Forever', 'Please enable location permissions in settings.');
        setState(() {
          _isFetchingLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final city = place.locality ?? place.administrativeArea;
        if (city != null) {
          const cityToTimezone = {
            'new york': 'America/New_York',
            'los angeles': 'America/Los_Angeles',
            'california': 'America/Los_Angeles',
            'san francisco': 'America/Los_Angeles',
            'chicago': 'America/Chicago',
            'houston': 'America/Chicago',
            'phoenix': 'America/Phoenix',
            'philadelphia': 'America/New_York',
            'san antonio': 'America/Chicago',
            'san diego': 'America/Los_Angeles',
            'dallas': 'America/Chicago',
            'austin': 'America/Chicago',
            'toronto': 'America/Toronto',
            'montreal': 'America/Toronto',
            'vancouver': 'America/Vancouver',
            'calgary': 'America/Edmonton',
            'ottawa': 'America/Toronto',
            'mexico city': 'America/Mexico_City',
            'tijuana': 'America/Tijuana',
            'monterrey': 'America/Monterrey',
            'london': 'Europe/London',
            'paris': 'Europe/Paris',
            'berlin': 'Europe/Berlin',
            'rome': 'Europe/Rome',
            'madrid': 'Europe/Madrid',
            'mumbai': 'Asia/Kolkata',
            'delhi': 'Asia/Kolkata',
            'bangalore': 'Asia/Kolkata',
            'hyderabad': 'Asia/Kolkata',
            'chennai': 'Asia/Kolkata',
            'kolkata': 'Asia/Kolkata',
            'singapore': 'Asia/Singapore',
            'tokyo': 'Asia/Tokyo',
            'beijing': 'Asia/Shanghai',
            'shanghai': 'Asia/Shanghai',
            'hong kong': 'Asia/Hong_Kong',
            'dubai': 'Asia/Dubai',
            'sydney': 'Australia/Sydney',
            'melbourne': 'Australia/Melbourne',
            'brisbane': 'Australia/Brisbane',
            'perth': 'Australia/Perth',
            'sao paulo': 'America/Sao_Paulo',
            'rio de janeiro': 'America/Sao_Paulo',
            'buenos aires': 'America/Argentina/Buenos_Aires',
            'lima': 'America/Lima',
            'cairo': 'Africa/Cairo',
            'nairobi': 'Africa/Nairobi',
            'lagos': 'Africa/Lagos',
            'johannesburg': 'Africa/Johannesburg',
          };

          final timezoneName = cityToTimezone[city.toLowerCase()] ?? 'UTC';

          setState(() {
            _cityController.text = city;
            _isCityValid = true;
            _isFetchingLocation = false;
            _selectedTimezone = timezoneName;
          });
        } else {
          _showErrorToast('Invalid Location', 'Could not determine a valid city from current location.');
          setState(() {
            _isFetchingLocation = false;
          });
        }
      }
    } catch (e) {
      _showErrorToast('Location Error', 'Failed to get current location: $e');
      setState(() {
        _isFetchingLocation = false;
      });
    }
  }

  Future<void> _uploadImage({required bool isProfileImage}) async {
    final field = isProfileImage ? 'Profile' : 'Sponsor';
    if (isProfileImage ? _isUploadingProfileImage : _isUploadingSponsorImage) return;
    setState(() {
      if (isProfileImage) {
        _isUploadingProfileImage = true;
      } else {
        _isUploadingSponsorImage = true;
      }
    });

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) {
        if (mounted) {
          setState(() {
            if (isProfileImage) {
              _isUploadingProfileImage = false;
            } else {
              _isUploadingSponsorImage = false;
            }
          });
        }
        return;
      }

      final file = File(pickedFile.path);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('${isProfileImage ? 'tournament_images' : 'sponsor_images'}/${widget.tournament.id}_${isProfileImage ? 'profile' : 'sponsor'}.jpg');
      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update({isProfileImage ? 'profileImage' : 'sponsorImage': downloadUrl});

      if (mounted) {
        setState(() {
          if (isProfileImage) {
            _profileImage = downloadUrl;
          } else {
            _sponsorImage = downloadUrl;
          }
        });
        _showSuccessToast('$field Image Uploaded', '$field image updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        _showErrorToast('Upload Failed', 'Failed to upload $field image: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isProfileImage) {
            _isUploadingProfileImage = false;
          } else {
            _isUploadingSponsorImage = false;
          }
        });
      }
    }
  }

  void _showEventDialog({Event? event, int? index}) {
    final eventNameController = TextEditingController(text: event?.name ?? '');
    String? eventFormat = event?.format ?? 'Knockout';
    String? eventLevel = event?.level ?? 'Beginner';
    String? eventMatchType = event?.matchType ?? 'Men\'s Singles';
    final eventMaxParticipantsController = TextEditingController(text: event?.maxParticipants.toString() ?? '');
    tz.TZDateTime? eventBornAfter = event?.bornAfter != null
        ? tz.TZDateTime.from(event!.bornAfter!, tz.getLocation(_selectedTimezone))
        : null;

    final formKey = GlobalKey<FormState>();
    final formatOptions = [
      'Knockout',
      'Round-Robin',
      'Double Elimination',
      'Group + Knockout',
      'Team Format',
      'Ladder',
      'Swiss Format',
    ];
    final levelOptions = ['Beginner', 'Intermediate', 'Professional'];
    final matchTypeOptions = ['Men\'s Singles', 'Women\'s Singles', 'Men\'s Doubles', 'Women\'s Doubles', 'Mixed Doubles'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white24),
        ),
        title: Text(
          event == null ? 'Add Event' : 'Edit Event',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(
                  controller: eventNameController,
                  label: 'Event Name',
                  validator: (value) => value?.trim().isEmpty ?? true ? 'Enter event name' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: eventFormat,
                  decoration: InputDecoration(
                    labelText: 'Format',
                    labelStyle: GoogleFonts.poppins(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  dropdownColor: Colors.black,
                  style: GoogleFonts.poppins(color: Colors.white),
                  items: formatOptions
                      .map((format) => DropdownMenuItem(
                            value: format,
                            child: Text(format, style: GoogleFonts.poppins(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    eventFormat = value;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: eventMatchType,
                  decoration: InputDecoration(
                    labelText: 'Match Type',
                    labelStyle: GoogleFonts.poppins(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  dropdownColor: Colors.black,
                  style: GoogleFonts.poppins(color: Colors.white),
                  items: matchTypeOptions
                      .map((matchType) => DropdownMenuItem(
                            value: matchType,
                            child: Text(matchType, style: GoogleFonts.poppins(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    eventMatchType = value;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: eventLevel,
                  decoration: InputDecoration(
                    labelText: 'Level',
                    labelStyle: GoogleFonts.poppins(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  dropdownColor: Colors.black,
                  style: GoogleFonts.poppins(color: Colors.white),
                  items: levelOptions
                      .map((level) => DropdownMenuItem(
                            value: level,
                            child: Text(level, style: GoogleFonts.poppins(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    eventLevel = value;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: eventMaxParticipantsController,
                  label: 'Max Participants',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Enter max participants';
                    final max = int.tryParse(value);
                    if (max == null || max <= 0) return 'Enter a valid number';
                    if ((eventMatchType == 'Men\'s Doubles' || eventMatchType == 'Women\'s Doubles' || eventMatchType == 'Mixed Doubles') && max % 2 != 0) {
                      return 'Max participants must be even for Doubles';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: eventBornAfter ?? tz.TZDateTime.now(tz.getLocation(_selectedTimezone)),
                      firstDate: tz.TZDateTime.now(tz.getLocation(_selectedTimezone)).subtract(const Duration(days: 365 * 20)),
                      lastDate: tz.TZDateTime.now(tz.getLocation(_selectedTimezone)),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Colors.blueGrey,
                              onPrimary: Colors.white,
                              surface: Colors.black,
                              onSurface: Colors.white,
                            ),
                            dialogBackgroundColor: Colors.black,
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      eventBornAfter = tz.TZDateTime(
                        tz.getLocation(_selectedTimezone),
                        picked.year,
                        picked.month,
                        picked.day,
                      );
                    }
                  },
                  child: _buildDateTimeField(
                    label: 'Born After',
                    value: eventBornAfter == null
                        ? 'Select Born After Date'
                        : DateFormat('MMM dd, yyyy').format(eventBornAfter!),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: Colors.blueGrey),
            ),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final newEvent = Event(
                  name: eventNameController.text.trim(),
                  format: eventFormat!,
                  level: eventLevel!,
                  maxParticipants: int.parse(eventMaxParticipantsController.text),
                  participants: event?.participants ?? [],
                  bornAfter: eventBornAfter,
                  matchType: eventMatchType!,
                  matches: event?.matches ?? [],
                );
                setState(() {
                  if (event == null) {
                    _events.add(newEvent);
                  } else {
                    _events[index!] = newEvent;
                  }
                });
                Navigator.pop(context);
              }
            },
            child: Text(
              event == null ? 'Add' : 'Update',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateTournament() async {
    if (!_formKey.currentState!.validate()) return;

    if (_events.isEmpty) {
      _showErrorToast('Events Required', 'Please add at least one event.');
      return;
    }

    if (_selectedEndDate.isBefore(_selectedStartDate)) {
      _showErrorToast('Invalid Date Range', 'End date must be on or after start date.');
      return;
    }

    if (_selectedRegistrationEnd.isAfter(_selectedStartDate)) {
      _showErrorToast('Invalid Registration End', 'Registration end must be on or before start date.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedTournament = Tournament(
        id: widget.tournament.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        venue: _venueController.text.trim(),
        city: _cityController.text.trim(),
        startDate: _selectedStartDate.toUtc(),
        endDate: _selectedEndDate.toUtc(),
        registrationEnd: _selectedRegistrationEnd.toUtc(),
        entryFee: double.tryParse(_entryFeeController.text.trim()) ?? 0.0,
        extraFee: _extraFeeController.text.trim().isEmpty ? null : double.tryParse(_extraFeeController.text.trim()),
        canPayAtVenue: _canPayAtVenue,
        status: widget.tournament.status,
        createdBy: widget.tournament.createdBy,
        createdAt: widget.tournament.createdAt,
        rules: _rulesController.text.trim(),
        gameFormat: _gameFormat,
        gameType: _gameType,
        bringOwnEquipment: _bringOwnEquipment,
        costShared: _costShared,
        profileImage: _profileImage,
        sponsorImage: _sponsorImage,
        contactName: _contactNameController.text.trim().isEmpty ? null : _contactNameController.text.trim(),
        contactNumber: _contactNumberController.text.trim().isEmpty ? null : _contactNumberController.text.trim(),
        timezone: _selectedTimezone,
        events: _events,
      );

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update(updatedTournament.toFirestore());

      if (mounted) {
        _showSuccessToast('Event Updated', '"${updatedTournament.name}" has been updated.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showErrorToast('Update Failed', 'Failed to update event: $e');
      }
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
      title: Text(title),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
      backgroundColor: Colors.grey[800],
      foregroundColor: Colors.white,
      alignment: Alignment.bottomCenter,
    );
  }

  void _showErrorToast(String title, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text(title),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 5),
      backgroundColor: Colors.grey[800],
      foregroundColor: Colors.white,
      alignment: Alignment.bottomCenter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            'Edit Event',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // Profile Image Field
                GestureDetector(
                  onTap: _isUploadingProfileImage ? null : () => _uploadImage(isProfileImage: true),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blueGrey, width: 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _profileImage != null && _profileImage!.isNotEmpty
                                ? Image.network(
                                    _profileImage!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Image.asset(
                                      'assets/tournament_placholder.jpg',
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Image.asset(
                                    'assets/tournament_placholder.jpg',
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isUploadingProfileImage ? 'Uploading Profile Image...' : 'Tap to upload profile image',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_isUploadingProfileImage)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Sponsor Image Field
                GestureDetector(
                  onTap: _isUploadingSponsorImage ? null : () => _uploadImage(isProfileImage: false),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blueGrey, width: 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _sponsorImage != null && _sponsorImage!.isNotEmpty
                                ? Image.network(
                                    _sponsorImage!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Image.asset(
                                      'assets/tournament_placholder.jpg',
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Image.asset(
                                    'assets/tournament_placholder.jpg',
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isUploadingSponsorImage ? 'Uploading Sponsor Image...' : 'Tap to upload sponsor image',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_isUploadingSponsorImage)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _nameController,
                  label: 'Event Name',
                  validator: (value) => value?.trim().isEmpty ?? true ? 'Enter a name' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _venueController,
                  label: 'Venue',
                  validator: (value) => value?.trim().isEmpty ?? true ? 'Enter a venue' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _cityController,
                        label: 'City',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter a city';
                          return !_isCityValid ? 'Enter a valid city' : null;
                        },
                        onChanged: _debounceCityValidation,
                        suffix: _isValidatingCity
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Icon(
                                _isCityValid ? Icons.check_circle : Icons.error,
                                color: _isCityValid ? Colors.green : Colors.red,
                                size: 20,
                              ),
                      ),
                    ),
                    IconButton(
                      icon: _isFetchingLocation
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(
                              Icons.my_location,
                              color: Colors.white,
                              size: 20,
                            ),
                      onPressed: _isFetchingLocation ? null : () => _getCurrentLocation(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Timezone: $_selectedTimezone',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectStartDate(context),
                        child: _buildDateTimeField(
                          label: 'Start Date',
                          value: DateFormat('MMM dd, yyyy').format(_selectedStartDate),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectStartTime(context),
                        child: _buildDateTimeField(
                          label: 'Start Time',
                          value: _selectedStartTime.format(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _selectRegistrationEndDate(context),
                  child: _buildDateTimeField(
                    label: 'Registration End',
                    value: DateFormat('MMM dd, yyyy').format(_selectedRegistrationEnd),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _selectEndDate(context),
                  child: _buildDateTimeField(
                    label: 'End Date',
                    value: DateFormat('MMM dd, yyyy').format(_selectedEndDate),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Time in $_selectedTimezone',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _entryFeeController,
                  label: 'Entry Fee',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Enter an entry fee';
                    final fee = double.tryParse(value);
                    return fee == null || fee < 0 ? 'Enter a valid amount' : null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _extraFeeController,
                  label: 'Extra Fee (Optional)',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final fee = double.tryParse(value);
                    return fee == null || fee < 0 ? 'Enter a valid amount' : null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _gameFormat,
                  decoration: InputDecoration(
                    labelText: 'Game Format',
                    labelStyle: GoogleFonts.poppins(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  dropdownColor: Colors.black,
                  style: GoogleFonts.poppins(color: Colors.white),
                  items: _gameFormatOptions
                      .map((format) => DropdownMenuItem(
                            value: format,
                            child: Text(format, style: GoogleFonts.poppins(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _gameFormat = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _gameType,
                  decoration: InputDecoration(
                    labelText: 'Game Type',
                    labelStyle: GoogleFonts.poppins(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  dropdownColor: Colors.black,
                  style: GoogleFonts.poppins(color: Colors.white),
                  items: _gameTypeOptions
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(type, style: GoogleFonts.poppins(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _gameType = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _contactNameController,
                  label: 'Contact Name (Optional)',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _contactNumberController,
                  label: 'Contact Number (Optional)',
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final phoneRegExp = RegExp(r'^\+?[1-9]\d{1,14}$');
                    return phoneRegExp.hasMatch(value) ? null : 'Enter a valid phone number';
                  },
                ),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  title: 'Bring Own Equipment',
                  subtitle: 'Participants must bring their own equipment',
                  value: _bringOwnEquipment,
                  onChanged: (value) => setState(() => _bringOwnEquipment = value),
                ),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  title: 'Cost Shared',
                  subtitle: 'Costs are shared among participants',
                  value: _costShared,
                  onChanged: (value) => setState(() => _costShared = value),
                ),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  title: 'Can Pay at Venue',
                  subtitle: 'Participants can pay the entry fee at the venue',
                  value: _canPayAtVenue,
                  onChanged: (value) => setState(() => _canPayAtVenue = value),
                ),
                const SizedBox(height: 16),
                // Events Section
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Events',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, color: Colors.white),
                            onPressed: () => _showEventDialog(),
                          ),
                        ],
                      ),
                      if (_events.isEmpty)
                        Text(
                          'No events added. Add an event to continue.',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        )
                      else
                        ..._events.asMap().entries.map((entry) {
                          final index = entry.key;
                          final event = entry.value;
                          return ListTile(
                            title: Text(
                              event.name,
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                            subtitle: Text(
                              '${event.format} • ${event.matchType} • ${event.level}',
                              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.white70),
                                  onPressed: () => _showEventDialog(event: event, index: index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _events.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _isLoading ? null : _updateTournament,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isLoading ? Colors.grey[700] : Colors.blueGrey[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          : Text(
                              'Update Event',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
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
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool enabled = true,
    Widget? suffix,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        controller: controller,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        cursorColor: Colors.white,
        keyboardType: keyboardType,
        maxLines: maxLines,
        enabled: enabled,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white54),
          suffixIcon: suffix,
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildDateTimeField({required String label, required String value}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (label == 'Start Date' && _selectedStartDate.isBefore(tz.TZDateTime.now(tz.getLocation(_selectedTimezone))))
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 20,
            ),
          if (label == 'End Date' && _selectedEndDate.isBefore(_selectedStartDate))
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 20,
            ),
          if (label == 'Registration End' && _selectedRegistrationEnd.isAfter(_selectedStartDate))
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 20,
            ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blueGrey,
            inactiveTrackColor: Colors.white24,
          ),
        ],
      ),
    );
  }
}