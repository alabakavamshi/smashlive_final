import 'dart:async';
import 'dart:io' show Platform;
import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_event.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:toastification/toastification.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

class LoginPage extends StatefulWidget {
  final String? role;

  const LoginPage({super.key, this.role});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  late final List<TextEditingController> _otpControllers;
  AuthBloc? _authBloc;

  bool _usePhone = false;
  bool _showOtpField = false;
  String? _verificationId;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isDialogOpen = false;
  int _signupStep = 0;

  final List<bool> _authModeSelection = [true, false];

  CountryCode _selectedCountry = CountryCode(
    code: 'IN',
    name: 'India',
    dialCode: '+91',
  );

  // Color palette
  final Color _darkBackground = const Color(0xFF121212);
  final Color _primaryColor = const Color(0xFF6C9A8B);
  final Color _textColor = Colors.white;
  final Color _secondaryTextColor = const Color(0xFFC1DADB);
  final Color _inputBackground = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _testFirestoreConnectivity();
    _initializeAppCheck();
  }

  Future<void> _initializeAppCheck() async {
    try {
      if (Platform.isIOS) {
        await FirebaseAppCheck.instance.activate(
          appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
        );
        debugPrint('App Check activated with App Attest for iOS');
      } else if (Platform.isAndroid) {
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        );
        debugPrint('App Check activated with Play Integrity for Android');
      } else {
        debugPrint('Platform not supported for App Check');
      }
    } catch (e) {
      debugPrint('App Check activation failed: $e');
    }
  }

  void _initializeControllers() {
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _passwordController = TextEditingController();
    _otpControllers = List.generate(6, (_) => TextEditingController());
  }

  void _resetAllData() {
    _emailController.clear();
    _phoneController.clear();
    _passwordController.clear();
    for (var controller in _otpControllers) {
      controller.clear();
    }
    if (mounted) {
      setState(() {
        _showOtpField = false;
        _verificationId = null;
        _signupStep = 0;
        _isLoading = false;
      });
    }
    debugPrint('All login data reset');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authBloc = context.read<AuthBloc>();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _testFirestoreConnectivity() async {
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('Firestore test skipped - user not authenticated');
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'testTimestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('Firestore connectivity test successful');
    } catch (e, stackTrace) {
      debugPrint('Firestore connectivity test failed: $e\nStack: $stackTrace');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Connection Error'),
          description: Text('Failed to connect to Firestore: $e'),
          autoCloseDuration: const Duration(seconds: 5),
        );
      }
    }
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return 'Email cannot be empty';
    final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegExp.hasMatch(email)) return 'Invalid email format';
    return null;
  }

  String? _validatePhone(String phone) {
    phone = _normalizePhoneNumber(phone);
    if (phone.isEmpty) return 'Phone number cannot be empty';
    if (phone.length < 8 || phone.length > 15) {
      return 'Invalid phone number length';
    }
    if (!RegExp(r'^\+[0-9]{1,4}[0-9]{7,14}$').hasMatch(phone)) {
      return 'Invalid phone number format';
    }
    return null;
  }

  String _normalizePhoneNumber(String phone) {
    phone = phone.trim();
    if (!phone.startsWith(_selectedCountry.dialCode ?? '')) {
      return '${_selectedCountry.dialCode}$phone';
    }
    return phone;
  }

  Future<bool> _checkFieldUniqueness(String field, String value) async {
    try {
      if (field == 'phone') value = _normalizePhoneNumber(value);
      debugPrint('Checking uniqueness for $field: $value');
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(field, isEqualTo: value.trim())
          .get()
          .timeout(const Duration(seconds: 10));
      debugPrint('Uniqueness check result for $field: ${querySnapshot.docs.isEmpty ? 'Unique' : 'Not unique'}');
      return querySnapshot.docs.isEmpty;
    } catch (e, stackTrace) {
      debugPrint('checkFieldUniqueness error: $e\nStack: $stackTrace');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to check $field uniqueness: $e'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
      return false;
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final email = _emailController.text.trim();
    if (_validateEmail(email) != null) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Validation Error'),
        description: const Text('Please enter a valid email address'),
        autoCloseDuration: const Duration(seconds: 2),
      );
      return;
    }

    try {
      await firebase_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('Password Reset Email Sent'),
          description: Text('A password reset email has been sent to $email'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('sendPasswordResetEmail error: $e\nStack: $stackTrace');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to send password reset email: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<void> _checkAndCompleteMissingDetails(BuildContext context, String uid) async {
    debugPrint('Checking missing details for UID: $uid at ${DateTime.now()}');
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      debugPrint('User document exists: ${userDoc.exists}');

      if (!userDoc.exists) {
        debugPrint('User document not found for UID: $uid, triggering profile creation');
        final completer = Completer<void>();
        await _collectMissingDetails(context, uid, completer);
        await completer.future;
        if (mounted) {
          debugPrint('Post-dialog navigation for UID: $uid');
          _navigateBasedOnRole(uid);
        }
        return;
      }

      final data = userDoc.data()!;
      debugPrint('User data: $data');
      
      if (data['isProfileComplete'] == true) {
        debugPrint('Profile is complete (isProfileComplete=true), navigating for UID: $uid');
        if (mounted) {
          _navigateBasedOnRole(uid);
        }
        return;
      }
      
      final bool hasFirstName = data.containsKey('firstName') && 
          data['firstName'] != null && 
          data['firstName'].toString().trim().isNotEmpty;
      
      final bool hasLastName = data.containsKey('lastName') && 
          data['lastName'] != null && 
          data['lastName'].toString().trim().isNotEmpty;
      
      final bool hasProfileImage = data.containsKey('profileImage') && 
          data['profileImage'] != null && 
          data['profileImage'].toString().trim().isNotEmpty;
      
      final bool hasGender = data.containsKey('gender') && 
          data['gender'] != null && 
          data['gender'].toString().trim().isNotEmpty;

      final bool isProfileComplete = hasFirstName && hasLastName && hasProfileImage && hasGender;

      debugPrint('Profile completeness check: '
          'firstName=$hasFirstName, '
          'lastName=$hasLastName, '
          'profileImage=$hasProfileImage, '
          'gender=$hasGender, '
          'isComplete=$isProfileComplete');

      if (!isProfileComplete) {
        if (_isDialogOpen) {
          debugPrint('Dialog already open, skipping for UID: $uid');
          return;
        }
        
        debugPrint('Missing details detected, showing dialog for UID: $uid');
        final completer = Completer<void>();
        await _collectMissingDetails(context, uid, completer);
        await completer.future;
        debugPrint('Dialog completed for UID: $uid');
        
        if (mounted) {
          debugPrint('Post-dialog navigation for UID: $uid');
          _navigateBasedOnRole(uid);
        }
      } else {
        debugPrint('Profile has all required fields, navigating for UID: $uid');
        if (mounted) {
          _navigateBasedOnRole(uid);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('checkAndCompleteMissingDetails error: $e\nStack: $stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to check user details: $e'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _collectMissingDetails(BuildContext context, String uid, Completer<void> completer) async {
    if (_isDialogOpen) {
      debugPrint('Dialog already open, skipping for UID: $uid at ${DateTime.now()}');
      completer.complete();
      return;
    }

    if (!mounted) {
      debugPrint('Widget not mounted, skipping dialog for UID: $uid at ${DateTime.now()}');
      completer.complete();
      return;
    }

    setState(() => _isDialogOpen = true);
    debugPrint('Opening dialog for UID: $uid at ${DateTime.now()}');

    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final phoneController = TextEditingController();
    final List<TextEditingController> otpControllers = List.generate(6, (_) => TextEditingController());
    String? verificationId;
    bool isPhoneVerifying = false;
    bool isDialogClosing = false;
    String? selectedGender;
    int? selectedProfileImageIndex;

    final bool isPhoneLogin = _usePhone;
    final String userPhone = _normalizePhoneNumber(_phoneController.text.trim());

    if (isPhoneLogin && userPhone.isNotEmpty) {
      phoneController.text = userPhone;
    }

    final List<String> genders = ['Male', 'Female'];
    final List<String> profileImages = [
      'assets/sketch1.jpg',
      'assets/sketch2.jpeg',
      'assets/sketch3.jpeg',
      'assets/sketch4.jpeg',
    ];

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            debugPrint('Dialog builder entered for UID: $uid at ${DateTime.now()}');
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 280,
                  maxWidth: MediaQuery.of(context).size.width * 0.8,
                  minHeight: 300,
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: _darkBackground,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(child: SizedBox(width: 50, child: _buildStepIndicator(0, "Profile"))),
                              const SizedBox(width: 8),
                              _buildStepConnector(),
                              const SizedBox(width: 8),
                              Flexible(child: SizedBox(width: 50, child: _buildStepIndicator(1, "Basic Info"))),
                              const SizedBox(width: 8),
                              _buildStepConnector(),
                              const SizedBox(width: 8),
                              Flexible(child: SizedBox(width: 50, child: _buildStepIndicator(2, isPhoneLogin ? "Phone Confirm" : "Phone"))),
                              const SizedBox(width: 8),
                              _buildStepConnector(),
                              const SizedBox(width: 8),
                              Flexible(child: SizedBox(width: 50, child: _buildStepIndicator(3, "Gender"))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_signupStep == 0) ...[
                          Text(
                            'Step 1: Select Profile Image',
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 120,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: List.generate(
                                  profileImages.length,
                                  (index) => Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    child: GestureDetector(
                                      onTap: () {
                                        if (!isDialogClosing) {
                                          setDialogState(() {
                                            selectedProfileImageIndex = index;
                                            debugPrint('Selected profile image index: $index at ${DateTime.now()}');
                                          });
                                        }
                                      },
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: selectedProfileImageIndex == index
                                                ? _primaryColor
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.asset(
                                            profileImages[index],
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              debugPrint('Image load error: $error at ${DateTime.now()}');
                                              return Container(
                                                color: Colors.grey,
                                                child: const Icon(Icons.error, color: Colors.red),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ] else if (_signupStep == 1) ...[
                          Text(
                            'Step 2: Basic Information',
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: firstNameController,
                            style: GoogleFonts.poppins(color: _textColor),
                            decoration: InputDecoration(
                              labelText: 'First Name',
                              labelStyle: GoogleFonts.poppins(color: _secondaryTextColor),
                              filled: true,
                              fillColor: _inputBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: _secondaryTextColor.withOpacity(0.2)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: _primaryColor, width: 2),
                              ),
                              prefixIcon: Icon(Icons.person, color: _secondaryTextColor),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: lastNameController,
                            style: GoogleFonts.poppins(color: _textColor),
                            decoration: InputDecoration(
                              labelText: 'Last Name',
                              labelStyle: GoogleFonts.poppins(color: _secondaryTextColor),
                              filled: true,
                              fillColor: _inputBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: _secondaryTextColor.withOpacity(0.2)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: _primaryColor, width: 2),
                              ),
                              prefixIcon: Icon(Icons.person, color: _secondaryTextColor),
                            ),
                          ),
                        ] else if (_signupStep == 2) ...[
                          if (isPhoneLogin) ...[
                            Text(
                              'Step 3: Phone Confirmation',
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Your verified phone number:',
                              style: GoogleFonts.poppins(color: _textColor),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              userPhone,
                              style: GoogleFonts.poppins(
                                color: _primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'This phone number is already verified and will be saved to your profile.',
                              style: GoogleFonts.poppins(
                                color: _secondaryTextColor,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ] else ...[
                            Text(
                              'Step 3: Add Phone (Optional)',
                              style: GoogleFonts.poppins(
                                color: _textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  width: 100,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _inputBackground,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(10),
                                      bottomLeft: Radius.circular(10),
                                    ),
                                    border: Border.all(color: _secondaryTextColor.withOpacity(0.2)),
                                  ),
                                  child: CountryCodePicker(
                                    onChanged: (CountryCode country) {
                                      if (!isDialogClosing) {
                                        setDialogState(() {
                                          _selectedCountry = country;
                                          debugPrint('Country selected: ${country.name} at ${DateTime.now()}');
                                        });
                                      }
                                    },
                                    initialSelection: 'IN',
                                    favorite: ['+91', 'IN'],
                                    showCountryOnly: false,
                                    showOnlyCountryWhenClosed: false,
                                    alignLeft: false,
                                    textStyle: GoogleFonts.poppins(
                                      color: _textColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    dialogTextStyle: GoogleFonts.poppins(
                                      color: _textColor,
                                      fontSize: 12,
                                    ),
                                    searchDecoration: InputDecoration(
                                      hintText: 'Search country...',
                                      hintStyle: GoogleFonts.poppins(color: _secondaryTextColor),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    dialogBackgroundColor: _darkBackground,
                                    backgroundColor: Colors.transparent,
                                    flagWidth: 18,
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: phoneController,
                                    keyboardType: TextInputType.phone,
                                    style: GoogleFonts.poppins(color: _textColor),
                                    decoration: InputDecoration(
                                      labelText: 'Phone Number (Optional)',
                                      labelStyle: GoogleFonts.poppins(color: _secondaryTextColor),
                                      filled: true,
                                      fillColor: _inputBackground,
                                      border: OutlineInputBorder(
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(10),
                                          bottomRight: Radius.circular(10),
                                        ),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(10),
                                          bottomRight: Radius.circular(10),
                                        ),
                                        borderSide: BorderSide(color: _secondaryTextColor.withOpacity(0.2)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: const BorderRadius.only(
                                          topRight: Radius.circular(10),
                                          bottomRight: Radius.circular(10),
                                        ),
                                        borderSide: BorderSide(color: _primaryColor, width: 2),
                                      ),
                                      prefixIcon: Icon(Icons.phone, color: _secondaryTextColor),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (verificationId != null) ...[
                              const SizedBox(height: 10),
                              _buildOtpFields(otpControllers),
                            ],
                            const SizedBox(height: 12),
                            if (verificationId == null)
                              _buildModernButton(
                                text: isPhoneVerifying ? 'Sending...' : 'Send OTP',
                                onPressed: isPhoneVerifying
                                    ? null
                                    : () async {
                                        if (isDialogClosing) return;
                                        final phone = _normalizePhoneNumber(phoneController.text.trim());
                                        
                                        if (phone.isEmpty) {
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (mounted && !isDialogClosing) {
                                              setDialogState(() {
                                                _signupStep++;
                                                debugPrint('No phone provided, skipping to step $_signupStep');
                                              });
                                            }
                                          });
                                          return;
                                        }
                                        
                                        final phoneError = _validatePhone(phone);
                                        if (phoneError != null) {
                                          toastification.show(
                                            context: dialogContext,
                                            type: ToastificationType.error,
                                            title: const Text('Validation Error'),
                                            description: Text(phoneError),
                                            autoCloseDuration: const Duration(seconds: 2),
                                          );
                                          return;
                                        }
                                        final isPhoneUnique = await _checkFieldUniqueness('phone', phone);
                                        if (!isPhoneUnique) {
                                          toastification.show(
                                            context: dialogContext,
                                            type: ToastificationType.error,
                                            title: const Text('Validation Error'),
                                            description: const Text('Phone number already in use.'),
                                            autoCloseDuration: const Duration(seconds: 2),
                                          );
                                          return;
                                        }
                                        setDialogState(() {
                                          isPhoneVerifying = true;
                                          debugPrint('Sending OTP for $phone at ${DateTime.now()}');
                                        });
                                        try {
                                          await firebase_auth.FirebaseAuth.instance.verifyPhoneNumber(
                                            phoneNumber: phone,
                                            timeout: const Duration(seconds: 60),
                                            verificationCompleted: (credential) async {
                                              final user = firebase_auth.FirebaseAuth.instance.currentUser;
                                              if (user != null && !isDialogClosing) {
                                                try {
                                                  await user.linkWithCredential(credential);
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    if (mounted && !isDialogClosing) {
                                                      setDialogState(() {
                                                        _signupStep++;
                                                        debugPrint('Phone linked, advanced to step $_signupStep');
                                                      });
                                                    }
                                                  });
                                                } catch (e, stackTrace) {
                                                  debugPrint('Auto phone link error: $e\nStack: $stackTrace');
                                                  toastification.show(
                                                    context: dialogContext,
                                                    type: ToastificationType.error,
                                                    title: const Text('Phone Link Error'),
                                                    description: Text('Error: $e'),
                                                    autoCloseDuration: const Duration(seconds: 2),
                                                  );
                                                }
                                              }
                                            },
                                            verificationFailed: (e) {
                                              setDialogState(() {
                                                isPhoneVerifying = false;
                                                debugPrint('Phone verification failed: ${e.message}');
                                              });
                                              toastification.show(
                                                context: dialogContext,
                                                type: ToastificationType.error,
                                                title: const Text('Phone Verification Failed'),
                                                description: Text('Error: ${e.message}'),
                                                autoCloseDuration: const Duration(seconds: 2),
                                              );
                                            },
                                            codeSent: (verId, _) {
                                              setDialogState(() {
                                                verificationId = verId;
                                                isPhoneVerifying = false;
                                                debugPrint('Code sent to $phone, verificationId: $verId');
                                              });
                                            },
                                            codeAutoRetrievalTimeout: (_) {},
                                          );
                                        } catch (e, stackTrace) {
                                          debugPrint('Phone verification error: $e\nStack: $stackTrace');
                                          setDialogState(() {
                                            isPhoneVerifying = false;
                                          });
                                        }
                                      },
                              )
                            else
                              _buildModernButton(
                                text: isPhoneVerifying ? 'Verifying...' : 'Verify OTP',
                                onPressed: isPhoneVerifying
                                    ? null
                                    : () async {
                                        if (isDialogClosing) return;
                                        final otp = otpControllers.map((c) => c.text).join();
                                        if (otp.length != 6 || verificationId == null) {
                                          toastification.show(
                                            context: dialogContext,
                                            type: ToastificationType.error,
                                            title: const Text('Validation Error'),
                                            description: const Text('Enter a valid 6-digit OTP'),
                                            autoCloseDuration: const Duration(seconds: 2),
                                          );
                                          return;
                                        }
                                        setDialogState(() {
                                          isPhoneVerifying = true;
                                          debugPrint('Verifying OTP at ${DateTime.now()}');
                                        });
                                        try {
                                          final credential = firebase_auth.PhoneAuthProvider.credential(
                                            verificationId: verificationId!,
                                            smsCode: otp,
                                          );
                                          final user = firebase_auth.FirebaseAuth.instance.currentUser;
                                          if (user != null && !isDialogClosing) {
                                            await user.linkWithCredential(credential);
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              if (mounted && !isDialogClosing) {
                                                setDialogState(() {
                                                  _signupStep++;
                                                  debugPrint('Phone linked, advanced to step $_signupStep');
                                                });
                                              }
                                            });
                                          }
                                        } catch (e, stackTrace) {
                                          debugPrint('OTP verification error: $e\nStack: $stackTrace');
                                          toastification.show(
                                            context: dialogContext,
                                            type: ToastificationType.error,
                                            title: const Text('OTP Verification Failed'),
                                            description: Text('Error: $e'),
                                            autoCloseDuration: const Duration(seconds: 2),
                                          );
                                        } finally {
                                          setDialogState(() {
                                            isPhoneVerifying = false;
                                            debugPrint('OTP verification completed at ${DateTime.now()}');
                                          });
                                        }
                                      },
                              ),
                          ]
                        ] else if (_signupStep == 3) ...[
                          Text(
                            'Step 4: Select Gender',
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Column(
                            children: genders.map((gender) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5.0),
                                child: ListTile(
                                  title: Text(
                                    gender,
                                    style: GoogleFonts.poppins(color: _textColor, fontSize: 14),
                                  ),
                                  leading: Radio<String>(
                                    value: gender,
                                    groupValue: selectedGender,
                                    onChanged: (String? value) {
                                      if (!isDialogClosing) {
                                        setDialogState(() {
                                          selectedGender = value;
                                          debugPrint('Gender selected: $value at ${DateTime.now()}');
                                        });
                                      }
                                    },
                                    fillColor: MaterialStateProperty.resolveWith<Color>(
                                      (Set<MaterialState> states) {
                                        if (states.contains(MaterialState.selected)) {
                                          return _primaryColor;
                                        }
                                        return _textColor;
                                      },
                                    ),
                                  ),
                                  tileColor: _inputBackground,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (_signupStep > 0)
                              SizedBox(
                                width: 100,
                                child: _buildModernButton(
                                  text: 'Back',
                                  onPressed: () {
                                    if (isDialogClosing) return;
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (mounted && !isDialogClosing) {
                                        setDialogState(() {
                                          if (_signupStep == 2 && !isPhoneLogin) {
                                            verificationId = null;
                                            for (var controller in otpControllers) {
                                              controller.clear();
                                            }
                                          }
                                          _signupStep--;
                                          debugPrint('Back to step $_signupStep at ${DateTime.now()}');
                                        });
                                      }
                                    });
                                  },
                                ),
                              ),
                            SizedBox(
                              width: 100,
                              child: _buildModernButton(
                                text: _signupStep < 3 ? 'Next' : 'Complete',
                                onPressed: () async {
                                  if (isDialogClosing) return;
                                  debugPrint('Button pressed: ${_signupStep < 3 ? 'Next' : 'Complete'} at ${DateTime.now()}');
                                  
                                  if (_signupStep < 3) {
                                    if (_signupStep == 0 && selectedProfileImageIndex == null) {
                                      toastification.show(
                                        context: dialogContext,
                                        type: ToastificationType.error,
                                        title: const Text('Validation Error'),
                                        description: const Text('Please select a profile image'),
                                        autoCloseDuration: const Duration(seconds: 2),
                                      );
                                      return;
                                    } else if (_signupStep == 1 &&
                                        (firstNameController.text.trim().isEmpty ||
                                            lastNameController.text.trim().isEmpty)) {
                                      toastification.show(
                                        context: dialogContext,
                                        type: ToastificationType.error,
                                        title: const Text('Validation Error'),
                                        description: const Text('Please fill all required fields'),
                                        autoCloseDuration: const Duration(seconds: 2),
                                      );
                                      return;
                                    } else if (_signupStep == 2 && isPhoneLogin) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (mounted && !isDialogClosing) {
                                          setDialogState(() {
                                            _signupStep++;
                                            debugPrint('Phone login user, skipping to step $_signupStep');
                                          });
                                        }
                                      });
                                    } else {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (mounted && !isDialogClosing) {
                                          setDialogState(() {
                                            _signupStep++;
                                            debugPrint('Advanced to step $_signupStep at ${DateTime.now()}');
                                          });
                                        }
                                      });
                                    }
                                  } else {
                                    if (selectedGender == null) {
                                      toastification.show(
                                        context: dialogContext,
                                        type: ToastificationType.error,
                                        title: const Text('Validation Error'),
                                        description: const Text('Please select your gender'),
                                        autoCloseDuration: const Duration(seconds: 2),
                                      );
                                      return;
                                    }
                                    try {
                                      isDialogClosing = true;
                                      debugPrint('Saving profile for UID: $uid at ${DateTime.now()}');
                                      
                                      final String phoneToSave = isPhoneLogin 
                                          ? userPhone 
                                          : (phoneController.text.isEmpty ? '' : _normalizePhoneNumber(phoneController.text.trim()));
                                      
                                      await FirebaseFirestore.instance.collection('users').doc(uid).set({
                                        'email': _emailController.text.trim(),
                                        'firstName': firstNameController.text.trim(),
                                        'lastName': lastNameController.text.trim(),
                                        'phone': phoneToSave,
                                        'gender': selectedGender,
                                        'profileImage': profileImages[selectedProfileImageIndex!],
                                        'location': await _fetchUserLocation(),
                                        'createdAt': FieldValue.serverTimestamp(),
                                        'role': widget.role ?? 'player',
                                        'isProfileComplete': true,
                                      }, SetOptions(merge: true));
                                      
                                      debugPrint('User details saved for UID: $uid at ${DateTime.now()}');
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (mounted) {
                                          debugPrint('Closing dialog for UID: $uid at ${DateTime.now()}');
                                          Navigator.pop(dialogContext);
                                          _authBloc?.add(AuthRefreshProfileEvent(uid));
                                          completer.complete();
                                        }
                                      });
                                    } catch (e, stackTrace) {
                                      debugPrint('Error saving profile: $e\nStack: $stackTrace');
                                      isDialogClosing = false;
                                      toastification.show(
                                        context: dialogContext,
                                        type: ToastificationType.error,
                                        title: const Text('Error'),
                                        description: Text('Failed to save profile: $e'),
                                        autoCloseDuration: const Duration(seconds: 2),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('collectMissingDetails error: $e\nStack: $stackTrace');
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Error'),
          description: Text('Failed to collect missing details: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
      completer.complete();
    } finally {
      firstNameController.dispose();
      lastNameController.dispose();
      phoneController.dispose();
      for (var controller in otpControllers) {
        controller.dispose();
      }
      if (mounted) {
        setState(() => _isDialogOpen = false);
      }
      debugPrint('Dialog closed for UID: $uid at ${DateTime.now()}');
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<Map<String, double?>?> _fetchUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return null;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied forever');
        return null;
      }
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      debugPrint('Location fetched: ${position.latitude}, ${position.longitude}');
      return {'latitude': position.latitude, 'longitude': position.longitude};
    } catch (e, stackTrace) {
      debugPrint('Failed to fetch location: $e\nStack: $stackTrace');
      return null;
    }
  }

  void _navigateBasedOnRole(String uid) async {
    debugPrint('Navigating based on role for UID: $uid');
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!userDoc.exists) {
        debugPrint('User document not found for UID: $uid, triggering profile creation');
        final completer = Completer<void>();
        await _collectMissingDetails(context, uid, completer);
        await completer.future;
        return;
      }

      final data = userDoc.data()!;
      final role = data['role'] ?? 'player';
      debugPrint('User role: $role');

      if (mounted) {
        debugPrint('Navigating to /$role for UID: $uid');
        Navigator.of(context).pushNamedAndRemoveUntil('/$role', (route) => false);
      } else {
        debugPrint('Widget not mounted, skipping navigation for UID: $uid');
      }
    } catch (e, stackTrace) {
      debugPrint('navigateBasedOnRole error: $e\nStack: $stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Navigation Error'),
          description: Text('Error: $e. Please complete your profile.'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _handleLoginButtonPress() async {
    debugPrint('=== LOGIN BUTTON PRESSED ===');
    if (!mounted || _isLoading || _authBloc == null) {
      debugPrint('Cannot proceed: mounted=$mounted, isLoading=$_isLoading, authBloc=$_authBloc');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_usePhone) {
        await _handlePhoneLogin();
      } else {
        await _handleEmailLogin();
      }
    } catch (e, stackTrace) {
      debugPrint('Login error: $e\nStack: $stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Login Error'),
          description: Text('Error: ${e.toString()}'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _handlePhoneLogin() async {
    debugPrint('=== PHONE LOGIN STARTED ===');
    if (!mounted || _authBloc == null) {
      debugPrint('Cannot proceed: mounted=$mounted, authBloc=$_authBloc');
      setState(() => _isLoading = false);
      return;
    }

    try {
      if (!_showOtpField) {
        await _sendOtp();
      } else {
        await _verifyOtp();
      }
    } catch (e, stackTrace) {
      debugPrint('Phone login error: $e\nStack: $stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Phone Auth Error'),
          description: Text('Unexpected error: ${e.toString()}'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _handleEmailLogin() async {
    if (_authBloc == null) return;
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (email.isEmpty) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Validation Error'),
          description: const Text('Please enter your email'),
          autoCloseDuration: const Duration(seconds: 2),
        );
        debugPrint('Email empty');
        setState(() => _isLoading = false);
        return;
      }

      if (password.isEmpty) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Validation Error'),
          description: const Text('Please enter your password'),
          autoCloseDuration: const Duration(seconds: 2),
        );
        debugPrint('Password empty');
        setState(() => _isLoading = false);
        return;
      }

      final emailError = _validateEmail(email);
      if (emailError != null) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Validation Error'),
          description: Text(emailError),
          autoCloseDuration: const Duration(seconds: 2),
        );
        debugPrint('Email error: $emailError');
        setState(() => _isLoading = false);
        return;
      }

      _authBloc!.add(
        AuthLoginEvent(email: email, password: password, role: widget.role),
      );
    } catch (e, stackTrace) {
      debugPrint('handleEmailLogin error: $e\nStack: $stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Email Auth Error'),
          description: Text('Error: $e'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<void> _sendOtp() async {
    final phone = _normalizePhoneNumber(_phoneController.text.trim());
    debugPrint('Sending OTP to: $phone');

    if (phone.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Validation Error'),
          description: const Text('Please enter a phone number'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
      return;
    }

    final phoneError = _validatePhone(phone);
    if (phoneError != null) {
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Validation Error'),
          description: Text(phoneError),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
      return;
    }

    try {
      final isPhoneUnique = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone.trim())
          .get()
          .then((snapshot) => snapshot.docs.isEmpty);

      if (isPhoneUnique) {
        if (mounted) {
          setState(() => _isLoading = false);
          toastification.show(
            context: context,
            type: ToastificationType.error,
            title: const Text('Account Not Found'),
            description: const Text('No account found with this phone number. Please sign up.'),
            autoCloseDuration: const Duration(seconds: 3),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Phone check error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Connection Error'),
          description: const Text('Could not verify phone number. Please try again.'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
      return;
    }

    try {
      await firebase_auth.FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          debugPrint('Auto-verification completed');
          try {
            final userCredential = await firebase_auth.FirebaseAuth.instance.signInWithCredential(credential);
            if (mounted) {
              setState(() => _isLoading = false);
              await _checkAndCompleteMissingDetails(context, userCredential.user!.uid);
            }
          } catch (e) {
            debugPrint('Auto-verification sign-in error: $e');
            if (mounted) {
              setState(() => _isLoading = false);
            }
          }
        },
        verificationFailed: (e) {
          debugPrint('Verification failed: ${e.message}');
          if (mounted) {
            setState(() => _isLoading = false);
            toastification.show(
              context: context,
              type: ToastificationType.error,
              title: const Text('Verification Failed'),
              description: Text('Error: ${e.message}'),
              autoCloseDuration: const Duration(seconds: 3),
            );
          }
        },
        codeSent: (verificationId, _) {
          debugPrint('OTP sent successfully');
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _showOtpField = true;
              _isLoading = false;
            });
            toastification.show(
              context: context,
              type: ToastificationType.success,
              title: const Text('OTP Sent'),
              description: Text('Code sent to $phone'),
              autoCloseDuration: const Duration(seconds: 3),
            );
          }
        },
        codeAutoRetrievalTimeout: (_) {
          debugPrint('Code auto-retrieval timed out');
          if (mounted) {
            setState(() => _isLoading = false);
          }
        },
      );
    } catch (e) {
      debugPrint('OTP sending error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('OTP Error'),
          description: const Text('Failed to send OTP. Please try again.'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpControllers.map((c) => c.text).join();
    debugPrint('Verifying OTP: $otp');

    if (otp.length != 6 || _verificationId == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Validation Error'),
          description: const Text('Please enter a valid 6-digit OTP'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
      return;
    }

    try {
      final credential = firebase_auth.PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      final userCredential = await firebase_auth.FirebaseAuth.instance.signInWithCredential(credential);
      debugPrint('OTP verification successful for UID: ${userCredential.user?.uid}');

      if (mounted) {
        setState(() => _isLoading = false);
        await _checkAndCompleteMissingDetails(context, userCredential.user!.uid);
      }
    } catch (e) {
      debugPrint('OTP verification error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Verification Failed'),
          description: const Text('Invalid OTP. Please try again.'),
          autoCloseDuration: const Duration(seconds: 3),
        );
      }
    }
  }

  Widget _buildBackButton() {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: _textColor),
      onPressed: () => Navigator.pop(context),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome Back',
          style: GoogleFonts.poppins(
            color: _textColor,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Login to continue your journey',
          style: GoogleFonts.poppins(color: _secondaryTextColor, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Row(
      children: [
        Container(
          width: 120,
          decoration: BoxDecoration(
            color: _inputBackground,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
            border: Border.all(color: _secondaryTextColor.withOpacity(0.2)),
          ),
          child: CountryCodePicker(
            onChanged: (CountryCode country) {
              setState(() {
                _selectedCountry = country;
              });
            },
            initialSelection: 'IN',
            favorite: ['+91', 'IN'],
            showCountryOnly: false,
            showOnlyCountryWhenClosed: false,
            alignLeft: false,
            textStyle: GoogleFonts.poppins(
              color: _textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            dialogTextStyle: GoogleFonts.poppins(
              color: _textColor,
              fontSize: 14,
            ),
            searchDecoration: InputDecoration(
              hintText: 'Search country...',
              hintStyle: GoogleFonts.poppins(color: _secondaryTextColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            dialogBackgroundColor: _darkBackground,
            backgroundColor: Colors.transparent,
            flagWidth: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.poppins(color: _textColor),
            decoration: InputDecoration(
              labelText: 'Phone Number',
              labelStyle: GoogleFonts.poppins(color: _secondaryTextColor),
              filled: true,
              fillColor: _inputBackground,
              border: OutlineInputBorder(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                borderSide: BorderSide(color: _secondaryTextColor.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
              prefixIcon: Icon(Icons.phone, color: _secondaryTextColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool isPhone = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: _textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: _secondaryTextColor),
        filled: true,
        fillColor: _inputBackground,
        border: OutlineInputBorder(
          borderRadius: isPhone
              ? const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                )
              : BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: isPhone
              ? const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                )
              : BorderRadius.circular(12),
          borderSide: BorderSide(color: _secondaryTextColor.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: isPhone
              ? const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                )
              : BorderRadius.circular(12),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
        prefixIcon: Icon(icon, color: _secondaryTextColor),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildOtpFields(List<TextEditingController> controllers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(6, (index) {
        return SizedBox(
          width: 48,
          height: 48,
          child: TextField(
            controller: controllers[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: _textColor,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            maxLength: 1,
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: _inputBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _secondaryTextColor.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _primaryColor, width: 2),
              ),
            ),
            onChanged: (value) {
              if (value.length == 1 && index < 5) {
                FocusScope.of(context).nextFocus();
              } else if (value.isEmpty && index > 0) {
                FocusScope.of(context).previousFocus();
              }
            },
          ),
        );
      }),
    );
  }

  Widget _buildModernButton({
    required String text,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                text,
                style: GoogleFonts.poppins(
                  color: _textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }

  Widget _buildSignupPrompt() {
    return Center(
      child: TextButton(
        onPressed: () {
          Navigator.of(context).pushReplacementNamed('/signup');
        },
        child: RichText(
          text: TextSpan(
            text: 'Don\'t have an account? ',
            style: GoogleFonts.poppins(color: _secondaryTextColor),
            children: [
              TextSpan(
                text: 'Sign Up',
                style: GoogleFonts.poppins(
                  color: _primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int stepNumber, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _signupStep == stepNumber ? Colors.cyanAccent : Colors.grey,
          ),
          child: Center(
            child: Text(
              (stepNumber + 1).toString(),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector() {
    return Container(
      width: 20,
      height: 2,
      color: Colors.grey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBackground,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) async {
          if (state is AuthLoading) {
            debugPrint('Auth loading state');
          } else if (state is AuthAuthenticated) {
            debugPrint('Authenticated with UID: ${state.user.uid}');
            setState(() => _isLoading = false);
            await _checkAndCompleteMissingDetails(context, state.user.uid);
          } else if (state is AuthError) {
            debugPrint('Auth error: ${state.message}');
            if (mounted) {
              setState(() => _isLoading = false);
              toastification.show(
                context: context,
                type: ToastificationType.error,
                title: const Text('Authentication Error'),
                description: Text(state.message),
                autoCloseDuration: const Duration(seconds: 2),
              );
            }
          } else if (state is AuthUnauthenticated) {
            debugPrint('Unauthenticated state');
            setState(() => _isLoading = false);
            _resetAllData();
          }
        },
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBackButton(),
                const SizedBox(height: 16),
                _buildHeader(),
                const SizedBox(height: 32),
                Center(
                  child: ToggleButtons(
                    isSelected: _authModeSelection,
                    onPressed: (index) {
                      setState(() {
                        _usePhone = index == 1;
                        _authModeSelection[0] = !_usePhone;
                        _authModeSelection[1] = _usePhone;
                        _showOtpField = false;
                        _verificationId = null;
                        _resetAllData();
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    selectedColor: _textColor,
                    fillColor: _primaryColor.withOpacity(0.8),
                    borderColor: _secondaryTextColor.withOpacity(0.2),
                    selectedBorderColor: _primaryColor,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Text(
                          'Email',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: _textColor,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Text(
                          'Phone',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: _textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (!_usePhone) ...[
                  _buildModernTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email,
                  ),
                  const SizedBox(height: 12),
                  _buildModernTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: _secondaryTextColor,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _sendPasswordResetEmail,
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.poppins(
                          color: _primaryColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  if (!_showOtpField) ...[
                    _buildPhoneInput(),
                  ] else ...[
                    _buildOtpFields(_otpControllers),
                  ],
                ],
                const SizedBox(height: 20),
                _buildModernButton(
                  text: _isLoading
                      ? 'Processing...'
                      : _usePhone && _showOtpField
                          ? 'Verify OTP'
                          : 'Log In',
                  onPressed: _isLoading ? null : _handleLoginButtonPress,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 20),
                _buildSignupPrompt(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}