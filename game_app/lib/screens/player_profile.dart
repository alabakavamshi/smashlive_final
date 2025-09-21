import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/auth_pages/welcome_screen.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_event.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/models/user_model.dart';
import 'package:game_app/organiser_pages/hosted_tournaments_page.dart';
import 'package:game_app/player_pages/joined_tournaments.dart';
import 'package:game_app/umpire/hosted_umpire_matches.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:toastification/toastification.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

// Enhanced Profile Information Page with better UX
class EnhancedProfileInformationPage extends StatefulWidget {
  final User user;
  final AppUser appUser;

  const EnhancedProfileInformationPage({
    super.key,
    required this.user,
    required this.appUser,
  });

  @override
  State<EnhancedProfileInformationPage> createState() => _EnhancedProfileInformationPageState();
}

class _EnhancedProfileInformationPageState extends State<EnhancedProfileInformationPage>
    with TickerProviderStateMixin {
  
  // Controllers
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  // Animation Controllers
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Form Keys
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _otpFormKey = GlobalKey<FormState>();

  // State Variables
  final List<String> _genderOptions = ['Male', 'Female'];
  final List<String> _avatarOptions = [
    'assets/sketch1.jpg',
    'assets/sketch2.jpeg',
    'assets/sketch3.jpeg',
    'assets/sketch4.jpeg',
  ];
  bool _isUploadingImage = false;
  String? _profileImageUrl;
  bool _isEditing = false;
  bool _isVerifyingPhone = false;
  String? _verificationId;
  String? _originalPhoneNumber;
  String? _originalEmail;
  String? _originalFirstName;
  String? _originalLastName;
  String? _originalGender;
  bool _isVerifyingEmail = false;
  bool _isSaving = false;
  
  // Phone verification state
  PhoneVerificationStep _phoneStep = PhoneVerificationStep.idle;
  int _otpResendTimer = 0;
  Timer? _resendTimer;
  
  // Focus nodes
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _otpFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_fadeController);
  }

  void _initializeControllers() {
    _firstNameController.text = widget.appUser.firstName;
    _lastNameController.text = widget.appUser.lastName;
    _emailController.text = widget.appUser.email ?? widget.user.email ?? '';
    _phoneController.text = widget.appUser.phone ?? widget.user.phoneNumber ?? '';
    _genderController.text = widget.appUser.gender ?? _genderOptions[0];
    _profileImageUrl = widget.appUser.profileImage ?? 'assets/logo.png';
    
    // Store original values
    _originalFirstName = _firstNameController.text;
    _originalLastName = _lastNameController.text;
    _originalPhoneNumber = _phoneController.text;
    _originalEmail = _emailController.text;
    _originalGender = _genderController.text;

    // Add listeners to detect changes
    _firstNameController.addListener(_onFormDataChanged);
    _lastNameController.addListener(_onFormDataChanged);
    _emailController.addListener(_onFormDataChanged);
    _phoneController.addListener(_onFormDataChanged);
    _genderController.addListener(_onFormDataChanged);
  }

  void _onFormDataChanged() {
    setState(() {
      // This will trigger a rebuild and update the save button state
    });
  }

  bool _hasChanges() {
    return _firstNameController.text != _originalFirstName ||
           _lastNameController.text != _originalLastName ||
           _emailController.text != _originalEmail ||
           _phoneController.text != _originalPhoneNumber ||
           _genderController.text != _originalGender ||
           _profileImageUrl != (widget.appUser.profileImage ?? 'assets/logo.png');
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    _resendTimer?.cancel();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _genderController.dispose();
    _otpController.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  void _showToast(String message, ToastificationType type, {IconData? icon}) {
    toastification.show(
      context: context,
      type: type,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 4),
      style: ToastificationStyle.fillColored,
      alignment: Alignment.topCenter,
      animationDuration: const Duration(milliseconds: 300),
      icon: icon != null ? Icon(icon) : null,
    );
  }

  void _startResendTimer() {
    _otpResendTimer = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _otpResendTimer--;
        if (_otpResendTimer <= 0) {
          timer.cancel();
        }
      });
    });
  }

  Future<String> _uploadImageSimple(XFile imageFile, String uid) async {
    try {
      debugPrint('Starting upload for UID: $uid');
      
      // Create a unique filename with proper extension
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(imageFile.path).toLowerCase();
      final fileName = 'profile_${uid}_$timestamp$extension';
      
      debugPrint('Creating storage reference for: $fileName');
      
      // Create reference with user-specific path
      final Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child(uid)
          .child(fileName);

      debugPrint('Converting XFile to File');
      final File file = File(imageFile.path);
      
      // Check if file exists and validate
      if (!await file.exists()) {
        throw Exception('Selected file does not exist');
      }
      
      final fileSize = await file.length();
      debugPrint('File exists, size: ${fileSize / 1024} KB');
      
      // Check file size (limit to 5MB)
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('File size too large. Maximum size is 5MB');
      }
      
      // Determine content type based on file extension
      String contentType = 'image/jpeg'; // default
      switch (extension) {
        case '.png':
          contentType = 'image/png';
          break;
        case '.jpg':
        case '.jpeg':
          contentType = 'image/jpeg';
          break;
        case '.gif':
          contentType = 'image/gif';
          break;
        case '.webp':
          contentType = 'image/webp';
          break;
        default:
          contentType = 'image/jpeg';
      }
      
      debugPrint('Content type: $contentType');
      debugPrint('Starting upload...');
      
      // Create upload task with proper metadata
      final UploadTask uploadTask = storageRef.putFile(
        file,
        SettableMetadata(
          contentType: contentType,
          customMetadata: {
            'userId': uid,
            'uploadTime': DateTime.now().toIso8601String(),
          },
        ),
      );

      // Listen for state changes with timeout
      uploadTask.snapshotEvents.listen(
        (TaskSnapshot snapshot) {
          final progress = snapshot.totalBytes > 0 
              ? (snapshot.bytesTransferred / snapshot.totalBytes) * 100 
              : 0.0;
          debugPrint('Upload progress: ${progress.toStringAsFixed(2)}%');
          debugPrint('Upload state: ${snapshot.state}');
        },
        onError: (error) {
          debugPrint('Upload stream error: $error');
        },
      );

      // Wait for upload to complete with timeout
      final TaskSnapshot snapshot = await uploadTask.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          debugPrint('Upload timed out');
          uploadTask.cancel();
          throw Exception('Upload timed out after 5 minutes');
        },
      );
      
      debugPrint('Upload completed with state: ${snapshot.state}');

      if (snapshot.state == TaskState.success) {
        debugPrint('Getting download URL...');
        
        // Get download URL with retry mechanism
        String? downloadURL;
        int retries = 3;
        
        while (retries > 0 && downloadURL == null) {
          try {
            downloadURL = await storageRef.getDownloadURL();
            break;
          } catch (e) {
            retries--;
            debugPrint('Failed to get download URL, retries left: $retries');
            if (retries > 0) {
              await Future.delayed(const Duration(seconds: 2));
            } else {
              rethrow;
            }
          }
        }
        
        if (downloadURL == null) {
          throw Exception('Failed to get download URL after retries');
        }
        
        debugPrint('✅ Download URL obtained successfully');
        return downloadURL;
      } else {
        throw Exception('Upload failed with state: ${snapshot.state}');
      }
    } on TimeoutException catch (e) {
      debugPrint('❌ Upload timeout: $e');
      throw Exception('Upload timed out. Please check your internet connection and try again.');
    } on FirebaseException catch (e) {
      debugPrint('❌ Firebase error: ${e.code} - ${e.message}');
      
      // Handle specific Firebase errors
      switch (e.code) {
        case 'storage/unauthorized':
          throw Exception('Upload not authorized. Please check your permissions.');
        case 'storage/canceled':
          throw Exception('Upload was canceled.');
        case 'storage/unknown':
          throw Exception('An unknown error occurred. Please check your internet connection and try again.');
        case 'storage/object-not-found':
          throw Exception('File upload failed. Please try again.');
        case 'storage/bucket-not-found':
          throw Exception('Storage bucket not found. Please contact support.');
        case 'storage/project-not-found':
          throw Exception('Firebase project not found. Please contact support.');
        case 'storage/quota-exceeded':
          throw Exception('Storage quota exceeded. Please contact support.');
        case 'storage/unauthenticated':
          throw Exception('User not authenticated. Please log in again.');
        case 'storage/retry-limit-exceeded':
          throw Exception('Too many attempts. Please try again later.');
        case 'storage/invalid-checksum':
          throw Exception('File upload failed due to integrity check. Please try again.');
        default:
          throw Exception('Upload failed: ${e.message ?? 'Unknown Firebase error'}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Upload error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      if (e.toString().contains('timed out')) {
        throw Exception('Upload timed out. Please check your connection and try again.');
      } else {
        throw Exception('Upload failed: ${e.toString()}');
      }
    }
  }

  Future<void> _showImageSelectionDialog(String uid) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Profile Image',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Choose an avatar:',
                style: GoogleFonts.poppins(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _avatarOptions.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await _updateProfileImage(_avatarOptions[index], uid);
                        },
                        child: CircleAvatar(
                          radius: 40,
                          backgroundImage: AssetImage(_avatarOptions[index]),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'OR',
                  style: GoogleFonts.poppins(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _uploadFromGallery(uid);
                  },
                  icon: const Icon(Icons.upload),
                  label: const Text('Upload from Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 227, 227, 233),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateProfileImage(String imagePath, String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'profileImage': imagePath});
      setState(() => _profileImageUrl = imagePath);
      context.read<AuthBloc>().add(AuthRefreshProfileEvent(uid));
      _showToast('Profile image updated!', ToastificationType.success, icon: Icons.check_circle);
    } catch (e) {
      _showToast('Failed to update image: $e', ToastificationType.error, icon: Icons.error_outline);
    }
  }

  Future<void> _uploadFromGallery(String uid) async {
    setState(() => _isUploadingImage = true);
    
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        debugPrint('Image selected: ${image.path}');
        
        // Validate file before upload
        final file = File(image.path);
        if (!await file.exists()) {
          throw Exception('Selected image file not found');
        }
        
        final fileSize = await file.length();
        if (fileSize == 0) {
          throw Exception('Selected image file is empty');
        }
        
        debugPrint('Starting upload process...');
        final String downloadURL = await _uploadImageSimple(image, uid);
        
        debugPrint('Updating Firestore...');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({
          'profileImage': downloadURL,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        
        setState(() => _profileImageUrl = downloadURL);
        context.read<AuthBloc>().add(AuthRefreshProfileEvent(uid));
        _showToast('Profile image updated successfully!', ToastificationType.success, icon: Icons.check_circle);
      } else {
        debugPrint('No image selected');
      }
    } catch (e) {
      debugPrint('Error in image upload process: $e');
      String errorMessage = 'Failed to update profile image';
      
      if (e.toString().contains('timed out')) {
        errorMessage = 'Upload timed out. Please try again with a better connection.';
      } else if (e.toString().contains('too large')) {
        errorMessage = 'Image file is too large. Please select a smaller image.';
      } else if (e.toString().contains('not authorized')) {
        errorMessage = 'Upload not authorized. Please log in again.';
      }
      
      _showToast(errorMessage, ToastificationType.error, icon: Icons.error_outline);
    } finally {
      setState(() => _isUploadingImage = false);
    }
  }

  // Enhanced phone verification with better UX
  Future<void> _initiatePhoneVerification() async {
    if (_phoneController.text == _originalPhoneNumber) {
      _showToast('Phone number unchanged', ToastificationType.info);
      return;
    }

    final isValid = _validatePhoneNumber(_phoneController.text);
    if (!isValid) return;

    setState(() {
      _phoneStep = PhoneVerificationStep.sending;
      _isVerifyingPhone = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _phoneController.text,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _handleAutoVerification(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _phoneStep = PhoneVerificationStep.error;
            _isVerifyingPhone = false;
          });
          _showToast(
            'Verification failed: ${_getPhoneErrorMessage(e)}',
            ToastificationType.error,
            icon: Icons.error_outline,
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _phoneStep = PhoneVerificationStep.waitingForOtp;
            _isVerifyingPhone = false;
          });
          _startResendTimer();
          _fadeController.forward();
          _slideController.forward();
          _showToast(
            'OTP sent to ${_phoneController.text}',
            ToastificationType.success,
            icon: Icons.sms,
          );
          // Auto focus OTP field
          Future.delayed(const Duration(milliseconds: 500), () {
            _otpFocusNode.requestFocus();
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      setState(() {
        _phoneStep = PhoneVerificationStep.error;
        _isVerifyingPhone = false;
      });
      _showToast('Error: ${e.toString()}', ToastificationType.error);
    }
  }

  Future<void> _handleAutoVerification(PhoneAuthCredential credential) async {
    try {
      await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
      await _updatePhoneInFirestore();
      setState(() {
        _phoneStep = PhoneVerificationStep.verified;
        _originalPhoneNumber = _phoneController.text;
      });
      _showToast(
        'Phone number verified automatically',
        ToastificationType.success,
        icon: Icons.verified,
      );
    } catch (e) {
      _showToast('Auto-verification failed: ${e.toString()}', ToastificationType.error);
    }
  }

  Future<void> _verifyOtpCode() async {
    if (!_otpFormKey.currentState!.validate()) return;
    if (_verificationId == null) return;

    setState(() {
      _isVerifyingPhone = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text,
      );
      
      await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
      await _updatePhoneInFirestore();
      
      setState(() {
        _phoneStep = PhoneVerificationStep.verified;
        _isVerifyingPhone = false;
        _originalPhoneNumber = _phoneController.text;
      });
      
      _resendTimer?.cancel();
      _showToast(
        'Phone number verified successfully',
        ToastificationType.success,
        icon: Icons.verified,
      );
      
    } catch (e) {
      setState(() {
        _isVerifyingPhone = false;
      });
      _showToast('Invalid OTP. Please try again.', ToastificationType.error);
    }
  }

  Future<void> _updatePhoneInFirestore() async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .update({'phone': _phoneController.text});
  }

  // Enhanced email verification with better flow
  Future<void> _initiateEmailVerification() async {
    if (_emailController.text == _originalEmail) {
      _showToast('Email unchanged', ToastificationType.info);
      return;
    }

    if (!_validateEmail(_emailController.text)) return;

    setState(() {
      _isVerifyingEmail = true;
    });

    try {
      await FirebaseAuth.instance.currentUser?.verifyBeforeUpdateEmail(_emailController.text);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({'email': _emailController.text});
      
      setState(() {
        _isVerifyingEmail = false;
        _originalEmail = _emailController.text;
      });
      
      _showToast(
        'Verification email sent. Please check your inbox.',
        ToastificationType.success,
        icon: Icons.email,
      );
    } catch (e) {
      setState(() {
        _isVerifyingEmail = false;
      });
      _showToast('Failed to update email: ${e.toString()}', ToastificationType.error);
    }
  }

  bool _validatePhoneNumber(String phone) {
    if (phone.isEmpty) {
      _showToast('Phone number is required', ToastificationType.error);
      return false;
    }
    if (!phone.startsWith('+')) {
      _showToast('Phone number must include country code', ToastificationType.error);
      return false;
    }
    return true;
  }

  bool _validateEmail(String email) {
    if (email.isEmpty) {
      _showToast('Email is required', ToastificationType.error);
      return false;
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showToast('Please enter a valid email', ToastificationType.error);
      return false;
    }
    return true;
  }

  String _getPhoneErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Invalid phone number format';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later';
      default:
        return e.message ?? 'Unknown error occurred';
    }
  }

  Future<void> _saveAllChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasChanges()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Save basic profile info
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'gender': _genderController.text.trim(),
        'profileImage': _profileImageUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update original values after successful save
      _originalFirstName = _firstNameController.text;
      _originalLastName = _lastNameController.text;
      _originalGender = _genderController.text;

      setState(() {
        _isEditing = false;
        _isSaving = false;
      });

      _showToast(
        'Profile updated successfully',
        ToastificationType.success,
        icon: Icons.check_circle,
      );
      
      context.read<AuthBloc>().add(AuthRefreshProfileEvent(widget.user.uid));
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      _showToast('Failed to update profile: ${e.toString()}', ToastificationType.error);
    }
  }

  // Enhanced form field with better styling and validation
  Widget _buildEnhancedFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffix,
    FocusNode? focusNode,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? helperText,
    bool obscureText = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.white60, size: 20),
              suffixIcon: suffix,
              hintText: 'Enter $label',
              hintStyle: GoogleFonts.poppins(
                color: Colors.white38,
                fontSize: 16,
              ),
              helperText: helperText,
              helperStyle: GoogleFonts.poppins(
                color: Colors.white54,
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF007AFF),
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 1,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
            ),
            validator: validator,
            keyboardType: keyboardType,
            readOnly: readOnly,
            onTap: onTap,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            obscureText: obscureText,
          ),
        ],
      ),
    );
  }

  // Phone verification widget with enhanced UX
  Widget _buildPhoneVerificationWidget() {
    return Column(
      children: [
        _buildEnhancedFormField(
          controller: _phoneController,
          label: 'Phone Number',
          icon: Icons.phone_outlined,
          focusNode: _phoneFocusNode,
          keyboardType: TextInputType.phone,
          readOnly: _phoneStep == PhoneVerificationStep.waitingForOtp,
          helperText: 'Include country code (e.g., +1234567890)',
          validator: (value) {
            if (value?.isEmpty ?? true) return 'Phone number is required';
            if (!value!.startsWith('+')) return 'Include country code';
            return null;
          },
          suffix: _buildPhoneSuffixWidget(),
        ),
        
        // OTP verification section with animation
        if (_phoneStep == PhoneVerificationStep.waitingForOtp)
          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF007AFF).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.sms_outlined,
                          color: Color(0xFF007AFF),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Verify Phone Number',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF007AFF),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the 6-digit code sent to ${_phoneController.text}',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _otpFormKey,
                      child: TextFormField(
                        controller: _otpController,
                        focusNode: _otpFocusNode,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: '●  ●  ●  ●  ●  ●',
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.white38,
                            fontSize: 18,
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF007AFF),
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value?.length != 6) return 'Enter 6-digit code';
                          return null;
                        },
                        onChanged: (value) {
                          if (value.length == 6) {
                            _verifyOtpCode();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _otpResendTimer > 0 ? null : () {
                            _initiatePhoneVerification();
                          },
                          icon: Icon(
                            Icons.refresh,
                            size: 18,
                            color: _otpResendTimer > 0 ? Colors.white38 : const Color(0xFF007AFF),
                          ),
                          label: Text(
                            _otpResendTimer > 0 
                                ? 'Resend in ${_otpResendTimer}s'
                                : 'Resend Code',
                            style: GoogleFonts.poppins(
                              color: _otpResendTimer > 0 ? Colors.white38 : const Color(0xFF007AFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _isVerifyingPhone ? null : _verifyOtpCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isVerifyingPhone
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Verify',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
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
      ],
    );
  }

  Widget _buildPhoneSuffixWidget() {
    switch (_phoneStep) {
      case PhoneVerificationStep.sending:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        );
      case PhoneVerificationStep.waitingForOtp:
        return IconButton(
          icon: const Icon(Icons.edit, color: Colors.white60),
          onPressed: () {
            setState(() {
              _phoneStep = PhoneVerificationStep.idle;
              _otpController.clear();
              _resendTimer?.cancel();
            });
            _fadeController.reset();
            _slideController.reset();
          },
        );
      case PhoneVerificationStep.verified:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(
            Icons.verified,
            color: Colors.green,
            size: 20,
          ),
        );
      case PhoneVerificationStep.error:
        return IconButton(
          icon: const Icon(Icons.refresh, color: Colors.redAccent),
          onPressed: () {
            setState(() {
              _phoneStep = PhoneVerificationStep.idle;
            });
          },
        );
      default:
        return IconButton(
          icon: const Icon(Icons.send, color: Color(0xFF007AFF)),
          onPressed: _initiatePhoneVerification,
        );
    }
  }

  // Enhanced email field
  Widget _buildEmailField() {
    return _buildEnhancedFormField(
      controller: _emailController,
      label: 'Email Address',
      icon: Icons.email_outlined,
      focusNode: _emailFocusNode,
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value?.isEmpty ?? true) return 'Email is required';
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
          return 'Enter a valid email';
        }
        return null;
      },
      suffix: _emailController.text != _originalEmail
          ? IconButton(
              icon: _isVerifyingEmail
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, color: Color(0xFF007AFF)),
              onPressed: _isVerifyingEmail ? null : _initiateEmailVerification,
            )
          : widget.user.emailVerified
              ? const Icon(Icons.verified, color: Colors.green)
              : const Icon(Icons.warning, color: Colors.amber),
    );
  }

  Widget _buildProfileHeader(User user, AppUser appUser) {
    final displayName = "${appUser.firstName} ${appUser.lastName}".trim();

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            GestureDetector(
              onTap: _isUploadingImage ? null : () => _showImageSelectionDialog(user.uid),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF818CF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _isUploadingImage
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : ClipOval(
                        child: _profileImageUrl != null
                            ? (_profileImageUrl!.startsWith('http') || _profileImageUrl!.startsWith('https')
                                ? Image.network(
                                    _profileImageUrl!,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Image.asset(
                                      'assets/logo.png',
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Image.asset(
                                    _profileImageUrl!,
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Image.asset(
                                      'assets/logo.png',
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ))
                            : Image.asset(
                                'assets/logo.png',
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                      ),
              ),
            ),
            if (!_isUploadingImage)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF1E293B),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.edit,
                  size: 16,
                  color: Colors.white,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          displayName,
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _getRoleColor(appUser.role).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _getRoleColor(appUser.role),
              width: 1,
            ),
          ),
          child: Text(
            appUser.role.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _getRoleColor(appUser.role),
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'player':
        return const Color(0xFF10B981);
      case 'organizer':
        return const Color(0xFFF59E0B);
      case 'umpire':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C9A8B),
        elevation: 0,
        title: Text(
          'Personal Information',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isEditing)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
              icon: const Icon(Icons.edit, color: Color.fromARGB(255, 1, 32, 66), size: 18),
              label: Text(
                'Edit',
                style: GoogleFonts.poppins(
                  color: Color.fromARGB(255, 1, 32, 66),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1C1C1E),
              Color(0xFF2C2C2E),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                        MediaQuery.of(context).padding.top - 
                        kToolbarHeight - 40,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Center(child: _buildProfileHeader(widget.user, widget.appUser)),
                  const SizedBox(height: 32),
                  
                  if (_isEditing) ...[
                    // Edit mode
                    Text(
                      'BASIC INFORMATION',
                      style: GoogleFonts.poppins(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: _buildEnhancedFormField(
                            controller: _firstNameController,
                            label: 'First Name',
                            icon: Icons.person_outline,
                            validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildEnhancedFormField(
                            controller: _lastNameController,
                            label: 'Last Name',
                            icon: Icons.person_outline,
                            validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    
                    _buildEnhancedFormField(
                      controller: _genderController,
                      label: 'Gender',
                      icon: Icons.person,
                      readOnly: true,
                      onTap: () => _showGenderSelector(),
                      suffix: const Icon(Icons.arrow_drop_down, color: Colors.white60),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    Text(
                      'CONTACT INFORMATION',
                      style: GoogleFonts.poppins(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    _buildEmailField(),
                    _buildPhoneVerificationWidget(),
                    
                    const SizedBox(height: 32),
                    
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : () {
                              setState(() {
                                _isEditing = false;
                                _phoneStep = PhoneVerificationStep.idle;
                                _otpController.clear();
                                _resendTimer?.cancel();
                                // Reset to original values
                                _firstNameController.text = _originalFirstName ?? '';
                                _lastNameController.text = _originalLastName ?? '';
                                _phoneController.text = _originalPhoneNumber ?? '';
                                _emailController.text = _originalEmail ?? '';
                                _genderController.text = _originalGender ?? '';
                                _profileImageUrl = widget.appUser.profileImage ?? 'assets/logo.png';
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: Colors.white.withOpacity(0.3)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: (_isSaving || !_hasChanges()) ? null : _saveAllChanges,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hasChanges() ? const Color(0xFF007AFF) : Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: _isSaving
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Saving...',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    'Save Changes',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Display mode
                    _buildInfoSection(
                      title: 'BASIC INFORMATION',
                      items: [
                        InfoItem(
                          icon: Icons.person_outline,
                          label: 'Name',
                          value: '${widget.appUser.firstName} ${widget.appUser.lastName}',
                        ),
                        InfoItem(
                          icon: Icons.person,
                          label: 'Gender',
                          value: widget.appUser.gender ?? 'Not specified',
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    _buildInfoSection(
                      title: 'CONTACT INFORMATION',
                      items: [
                        InfoItem(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: widget.appUser.email ?? widget.user.email ?? 'Not set',
                          status: _getEmailStatus(),
                        ),
                        InfoItem(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: widget.appUser.phone ?? widget.user.phoneNumber ?? 'Not set',
                          status: _getPhoneStatus(),
                        ),
                      ],
                    ),
                  ],
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showGenderSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Gender',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              ..._genderOptions.map((gender) {
                return ListTile(
                  leading: Icon(
                    _genderController.text == gender
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: const Color(0xFF007AFF),
                  ),
                  title: Text(
                    gender,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _genderController.text = gender;
                    });
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoSection({
    required String title,
    required List<InfoItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            color: Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          child: Column(
            children: items.map((item) => _buildInfoItem(item)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(InfoItem item) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            item.icon,
            color: Colors.white60,
            size: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: GoogleFonts.poppins(
                    color: Colors.white60,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.value,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.status != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        item.status!.icon,
                        color: item.status!.color,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.status!.text,
                        style: GoogleFonts.poppins(
                          color: item.status!.color,
                          fontSize: 12,
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
    );
  }

  StatusInfo? _getEmailStatus() {
    if (widget.user.email != null && widget.user.email!.isNotEmpty) {
      return widget.user.emailVerified
          ? StatusInfo(
              icon: Icons.verified,
              text: 'Verified',
              color: Colors.green,
            )
          : StatusInfo(
              icon: Icons.warning,
              text: 'Not verified',
              color: Colors.amber,
            );
    }
    return null;
  }

  StatusInfo? _getPhoneStatus() {
    if (widget.appUser.phone != null && widget.appUser.phone!.isNotEmpty) {
      return StatusInfo(
        icon: Icons.verified,
        text: 'Verified',
        color: Colors.green,
      );
    }
    return null;
  }
}

// Enums and helper classes
enum PhoneVerificationStep {
  idle,
  sending,
  waitingForOtp,
  verified,
  error,
}

class InfoItem {
  final IconData icon;
  final String label;
  final String value;
  final StatusInfo? status;

  InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.status,
  });
}

class StatusInfo {
  final IconData icon;
  final String text;
  final Color color;

  StatusInfo({
    required this.icon,
    required this.text,
    required this.color,
  });
}


class PlayerProfilePage extends StatefulWidget {
  const PlayerProfilePage({super.key});

  @override
  State<PlayerProfilePage> createState() => _PlayerProfilePageState();
}

class _PlayerProfilePageState extends State<PlayerProfilePage> {
  Map<String, dynamic>? _playerStats;
  final bool _isUploadingImage = false;
  String? _profileImageUrl;
  bool _isVerifyingPhone = false;
  bool _isOtpSent = false;
  String? _verificationId;
  bool _isVerifyingEmail = false;
  final TextEditingController _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        context.read<AuthBloc>().add(AuthRefreshProfileEvent(user.uid));
      }
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _showToast(String message, ToastificationType type) {
    toastification.show(
      context: context,
      type: type,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
      style: ToastificationStyle.fillColored,
      alignment: Alignment.topCenter,
      animationDuration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _sendEmailVerification() async {
    setState(() {
      _isVerifyingEmail = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        _showToast('Verification email sent to ${user.email}', ToastificationType.success);
      }
    } catch (e) {
      _showToast('Failed to send verification email: ${e.toString()}', ToastificationType.error);
    } finally {
      setState(() {
        _isVerifyingEmail = false;
      });
    }
  }

  Widget _buildEmailVerificationPrompt(User user) {
    if (user.email != null && user.email!.isNotEmpty && !user.emailVerified) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.amber, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your email is not verified. Please verify to secure your account.',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _isVerifyingEmail ? null : _sendEmailVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isVerifyingEmail
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Text(
                      'Verify Now',
                      style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.w500),
                    ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _fetchPlayerStats(String userId) async {
    try {
      final tournamentsQuery = await FirebaseFirestore.instance
          .collection('tournaments')
          .get();

      int totalMatches = 0;
      int wins = 0;
      int losses = 0;
      int currentStreak = 0;
      int longestWinStreak = 0;
      int longestLossStreak = 0;
      String bestTournamentResult = 'N/A';
      final tournamentResults = <String, String>{};

      for (var tournamentDoc in tournamentsQuery.docs) {
        final tournamentData = tournamentDoc.data();
        final matches = List<Map<String, dynamic>>.from(tournamentData['matches'] ?? []);

        bool playedInTournament = false;
        int tournamentWins = 0;
        int tournamentLosses = 0;

        for (var match in matches) {
          final player1Id = match['player1Id']?.toString() ?? '';
          final player2Id = match['player2Id']?.toString() ?? '';
          final team1Ids = List<String>.from(match['team1Ids'] ?? []);
          final team2Ids = List<String>.from(match['team2Ids'] ?? []);

          if (player1Id == userId ||
              player2Id == userId ||
              team1Ids.contains(userId) ||
              team2Ids.contains(userId)) {
            final isCompleted = match['completed'] == true;
            if (isCompleted) {
              totalMatches++;
              playedInTournament = true;

              final winner = match['winner']?.toString();
              if (winner == 'player1' && player1Id == userId ||
                  winner == 'player2' && player2Id == userId ||
                  winner == 'team1' && team1Ids.contains(userId) ||
                  winner == 'team2' && team2Ids.contains(userId)) {
                wins++;
                tournamentWins++;
                currentStreak = currentStreak >= 0 ? currentStreak + 1 : 1;
                longestWinStreak = currentStreak > longestWinStreak ? currentStreak : longestWinStreak;
              } else if (winner != null && winner.isNotEmpty) {
                losses++;
                tournamentLosses++;
                currentStreak = currentStreak <= 0 ? currentStreak - 1 : -1;
                longestLossStreak = (-currentStreak) > longestLossStreak ? -currentStreak : longestLossStreak;
              }
            }
          }
        }

        if (playedInTournament && (tournamentWins > 0 || tournamentLosses > 0)) {
          tournamentResults[tournamentDoc.id] = '$tournamentWins-$tournamentLosses';
        }
      }

      if (tournamentResults.isNotEmpty) {
        bestTournamentResult = tournamentResults.values.reduce((a, b) {
          final aParts = a.split('-').map(int.parse).toList();
          final bParts = b.split('-').map(int.parse).toList();
          final aWinRate = aParts[0] / (aParts[0] + aParts[1]);
          final bWinRate = bParts[0] / (bParts[0] + bParts[1]);
          return aWinRate > bWinRate ? a : b;
        });
      }

      if (mounted) {
        setState(() {
          _playerStats = {
            'totalMatches': totalMatches,
            'wins': wins,
            'losses': losses,
            'winPercentage': totalMatches > 0 ? (wins / totalMatches * 100) : 0.0,
            'currentStreak': currentStreak,
            'longestWinStreak': longestWinStreak,
            'longestLossStreak': longestLossStreak,
            'bestTournamentResult': bestTournamentResult,
          };
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      _showToast('Failed to fetch stats', ToastificationType.error);
    }
  }

  Future<void> _deleteAccount(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
        await user.delete();
        context.read<AuthBloc>().add(AuthLogoutEvent());
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
        _showToast('Account deleted', ToastificationType.success);
      }
    } catch (e) {
      _showToast('Failed to delete account: ${e.toString()}', ToastificationType.error);
    }
  }

  Future<void> _reauthenticateWithPhone(String phoneNumber, String uid) async {
    setState(() {
      _isVerifyingPhone = true;
    });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await FirebaseAuth.instance.currentUser?.reauthenticateWithCredential(credential);
          setState(() {
            _isVerifyingPhone = false;
            _isOtpSent = false;
          });
          await _deleteAccount(uid);
        } catch (e) {
          setState(() {
            _isVerifyingPhone = false;
          });
          _showToast('Re-authentication failed: ${e.toString()}', ToastificationType.error);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() {
          _isVerifyingPhone = false;
        });
        _showToast('Phone verification failed: ${e.message}', ToastificationType.error);
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _isOtpSent = true;
          _isVerifyingPhone = false;
        });
        _showToast('OTP sent to $phoneNumber', ToastificationType.success);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _verifyPhoneOtpForDelete(String otp, String uid) async {
    if (_verificationId == null) return;

    setState(() {
      _isVerifyingPhone = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      await FirebaseAuth.instance.currentUser?.reauthenticateWithCredential(credential);
      setState(() {
        _isOtpSent = false;
        _isVerifyingPhone = false;
        _otpController.clear();
      });
      await _deleteAccount(uid);
    } catch (e) {
      setState(() {
        _isVerifyingPhone = false;
      });
      _showToast('Invalid OTP. Please try again', ToastificationType.error);
    }
  }

  Future<void> _showReauthenticationDialog(String uid) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final phoneController = TextEditingController();
    bool usePhone = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Verify Your Identity',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'For security, please enter your credentials to continue',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setDialogState(() {
                            usePhone = false;
                            _isOtpSent = false;
                            _otpController.clear();
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: !usePhone ? Colors.white.withOpacity(0.1) : null,
                          side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          'Email',
                          style: GoogleFonts.poppins(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setDialogState(() {
                            usePhone = true;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: usePhone ? Colors.white.withOpacity(0.1) : null,
                          side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          'Phone',
                          style: GoogleFonts.poppins(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!usePhone) ...[
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: GoogleFonts.poppins(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.email, color: Colors.white70),
                    ),
                    style: GoogleFonts.poppins(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: GoogleFonts.poppins(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.lock, color: Colors.white70),
                    ),
                    style: GoogleFonts.poppins(color: Colors.white),
                    obscureText: true,
                  ),
                ] else ...[
                  TextField(
                    controller: phoneController,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      labelStyle: GoogleFonts.poppins(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.phone, color: Colors.white70),
                      suffixIcon: _isVerifyingPhone
                          ? const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    style: GoogleFonts.poppins(color: Colors.white),
                    keyboardType: TextInputType.phone,
                    readOnly: _isOtpSent,
                  ),
                  if (_isOtpSent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otpController,
                      decoration: InputDecoration(
                        labelText: 'Enter OTP',
                        labelStyle: GoogleFonts.poppins(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.sms, color: Colors.white70),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () async {
                            if (_otpController.text.length == 6) {
                              await _verifyPhoneOtpForDelete(_otpController.text, uid);
                            }
                          },
                        ),
                      ),
                      style: GoogleFonts.poppins(color: Colors.white),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isOtpSent = false;
                          _otpController.clear();
                        });
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (!usePhone) {
                          try {
                            final email = emailController.text.trim();
                            final password = passwordController.text.trim();
                            if (email.isEmpty || password.isEmpty) {
                              _showToast('Fields cannot be empty', ToastificationType.error);
                              return;
                            }
                            final credential = EmailAuthProvider.credential(
                              email: email,
                              password: password,
                            );
                            await FirebaseAuth.instance.currentUser?.reauthenticateWithCredential(credential);
                            Navigator.pop(context);
                            await _deleteAccount(uid);
                          } catch (e) {
                            _showToast('Authentication failed: ${e.toString()}', ToastificationType.error);
                          }
                        } else {
                          if (!_isOtpSent) {
                            if (phoneController.text.isEmpty) {
                              _showToast('Phone number cannot be empty', ToastificationType.error);
                              return;
                            }
                            await _reauthenticateWithPhone(phoneController.text, uid);
                            setDialogState(() {});
                          } else if (_otpController.text.length == 6) {
                            await _verifyPhoneOtpForDelete(_otpController.text, uid);
                          } else {
                            _showToast('Please enter a valid OTP', ToastificationType.error);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        usePhone && !_isOtpSent ? 'Send OTP' : 'Continue',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildProfileHeader(User user, AppUser? appUser) {
    final displayName = appUser != null ? "${appUser.firstName} ${appUser.lastName}".trim() : 'User';
    final email = appUser?.email ?? user.email ?? 'No email provided';
    final role = appUser?.role ?? 'Unknown';
    final phone = appUser?.phone ?? user.phoneNumber ?? 'No phone provided';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(20),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _profileImageUrl != null
                          ? (_profileImageUrl!.startsWith('assets/')
                              ? Image.asset(
                                  _profileImageUrl!,
                                  fit: BoxFit.contain,
                                )
                              : Image.network(
                                  _profileImageUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => Image.asset(
                                    'assets/logo.png',
                                    fit: BoxFit.contain,
                                  ),
                                ))
                          : Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                ),
              );
            },
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF818CF8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _isUploadingImage
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : ClipOval(
                          child: _profileImageUrl != null
                              ? (_profileImageUrl!.startsWith('assets/')
                                  ? Image.asset(
                                      _profileImageUrl!,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Image.asset(
                                        'assets/logo.png',
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Image.network(
                                      _profileImageUrl!,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Image.asset(
                                        'assets/logo.png',
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    ))
                              : Image.asset(
                                  'assets/logo.png',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  phone,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getRoleColor(role).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _getRoleColor(role),
                width: 1,
              ),
            ),
            child: Text(
              role.toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _getRoleColor(role),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'player':
        return const Color(0xFF10B981);
      case 'organizer':
        return const Color(0xFFF59E0B);
      case 'umpire':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  Widget _buildPlayerStatsSection(User user, AppUser? appUser) {
    return Column(
      children: [
        _buildSectionHeader('PLAYER STATS'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem('Matches', _playerStats?['totalMatches']?.toString() ?? '0'),
                    _buildStatItem('Wins', _playerStats?['wins']?.toString() ?? '0'),
                    _buildStatItem('Losses', _playerStats?['losses']?.toString() ?? '0'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatItem(
                        'Win %',
                        _playerStats?['winPercentage'] != null
                            ? '${_playerStats!['winPercentage'].toStringAsFixed(1)}'
                            : '0'),
                    _buildStatItem(
                        'Streak',
                        _playerStats?['currentStreak'] != null
                            ? (_playerStats!['currentStreak'] > 0
                                ? 'W-${_playerStats!['currentStreak']}'
                                : 'L-${_playerStats!['currentStreak']}')
                            : '-'),
                    _buildStatItem('Best', _playerStats?['bestTournamentResult']?.toString() ?? '-'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5), size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.logout, size: 48, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                'Log Out?',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to log out of your account?',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        context.read<AuthBloc>().add(AuthLogoutEvent());
                        Navigator.pop(context);
                        _showToast('Logged out successfully', ToastificationType.success);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Log Out',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoButton(User user, AppUser appUser) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EnhancedProfileInformationPage(
                  user: user,
                  appUser: appUser,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: Color(0xFF007AFF), size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personal Information',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'View and edit your profile details',
                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5), size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<AppUser?> _fetchUserFromFirestore(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        return AppUser.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching user from Firestore: $e');
      return null;
    }
  }

  void _showDeleteAccountConfirmationDialog(String uid) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                'Delete Account?',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will permanently delete your account and all associated data. This action cannot be undone.',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showReauthenticationDialog(uid);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Delete',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthInitial || state is AuthLoading) {
            return const Scaffold(
              backgroundColor: Color(0xFF1C1C1E),
              body: Center(child: CircularProgressIndicator(color: Colors.white)),
            );
          }

          if (state is AuthAuthenticated) {
            final user = state.user;
            if (state.appUser == null) {
              return FutureBuilder<AppUser?>(
                future: _fetchUserFromFirestore(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      backgroundColor: Color(0xFF1C1C1E),
                      body: Center(child: CircularProgressIndicator(color: Colors.white)),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return const Scaffold(
                      backgroundColor: Color(0xFF1C1C1E),
                      body: Center(child: Text('Error loading profile', style: TextStyle(color: Colors.white))),
                    );
                  }
                  final appUser = snapshot.data!;
                  _profileImageUrl = appUser.profileImage ?? 'assets/logo.png';
                  if (appUser.role.toLowerCase() == 'player') {
                    _fetchPlayerStats(user.uid);
                  }
                  return _buildScaffold(context, user, appUser);
                },
              );
            }
            final appUser = state.appUser!;
            _profileImageUrl = appUser.profileImage ?? 'assets/logo.png';
            if (appUser.role.toLowerCase() == 'player') {
              _fetchPlayerStats(user.uid);
            }
            return _buildScaffold(context, user, appUser);
          }

          return const Scaffold(
            backgroundColor: Color(0xFF1C1C1E),
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        },
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, User user, AppUser appUser) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C9A8B),
        elevation: 0,
        title: Text(
          'Profile',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1C1C1E),
              Color(0xFF2C2C2E),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _buildProfileHeader(user, appUser)),
              const SizedBox(height: 32),
              _buildEmailVerificationPrompt(user),
              const SizedBox(height: 16),
              _buildProfileInfoButton(user, appUser),
              if (appUser.role.toLowerCase() == 'player')
                _buildPlayerStatsSection(user, appUser),
              _buildSectionHeader('ACTIVITY'),
              if (appUser.role == 'organizer')
                _buildActionButton(
                  icon: Icons.tour,
                  label: 'Hosted Tournaments',
                  description: 'View and manage your hosted tournaments',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => HostedTournamentsPage(userId: user.uid)),
                  ),
                  color: const Color(0xFF8B5CF6),
                ),
              if (appUser.role == 'player')
                _buildActionButton(
                  icon: Icons.event,
                  label: 'Joined Tournaments',
                  description: 'View your tournament participations',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => JoinedTournamentsPage(userId: user.uid)),
                  ),
                  color: const Color(0xFF10B981),
                ),
              if (appUser.role == 'umpire')
                _buildActionButton(
                  icon: Icons.gavel,
                  label: 'Umpired Matches',
                  description: 'View matches you are officiating',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => UmpiredMatchesPage(userId: user.uid)),
                  ),
                  color: const Color(0xFF3B82F6),
                ),
              _buildSectionHeader('ACCOUNT'),
              _buildActionButton(
                icon: Icons.logout,
                label: 'Log Out',
                description: 'Sign out from your account',
                onTap: _showLogoutConfirmationDialog,
                color: const Color(0xFF007AFF),
              ),
              _buildActionButton(
                icon: Icons.delete_forever,
                label: 'Delete Account',
                description: 'Permanently delete your account',
                onTap: () => _showDeleteAccountConfirmationDialog(user.uid),
                color: const Color(0xFFDC2626),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}