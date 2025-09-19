import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:toastification/toastification.dart';

class EventFormPage extends StatefulWidget {
  final String timezone;

  const EventFormPage({super.key, required this.timezone});

  @override
  State<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFFF5F5F5);
  static const Color secondaryColor = Color(0xFFFFFFFF);
  static const Color accentColor = Color(0xFF4E6BFF);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color borderColor = Color(0xFFB0B0B0);
  static const Color errorColor = Color(0xFFF44336);

  final List<_EventForm> _eventForms = [_EventForm()];
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
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
    _animationController.dispose();
    for (var event in _eventForms) {
      event.dispose();
    }
    super.dispose();
  }

  void _submitEvents() {
    if (_eventForms.isEmpty) {
      _showErrorToast('No Events', 'Please add at least one event.');
      return;
    }

    for (var i = 0; i < _eventForms.length; i++) {
      final event = _eventForms[i];
      if (!event.validate()) {
        print('Validation failed for Event ${i + 1}:');
        print('  Name: "${event.nameController.text.trim()}"');
        print('  Max Participants: "${event.maxParticipantsController.text.trim()}"');
        print('  Match Type: "${event.matchType}"');
        print('  Event Type: "${event.eventType}"');
        print('  Level: "${event.level}"');
        _showErrorToast('Invalid Event ${i + 1}', 'Please fill all required fields correctly for Event ${i + 1}.');
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    final events = _eventForms.map((form) {
      final maxParticipants = int.tryParse(form.maxParticipantsController.text.trim());
      print('Creating event: Name=${form.nameController.text.trim()}, MaxParticipants=$maxParticipants');
      return Event(
        name: form.nameController.text.trim(),
        format: form.eventType,
        level: form.level,
        maxParticipants: maxParticipants!,
        participants: [],
        bornAfter: form.bornAfter,
        matchType: form.matchType,
        matches: [],
      );
    }).toList();

    print('Returning ${events.length} events to CreateTournamentPage');
    if (mounted) {
      Navigator.pop(context, events);
    }
  }

  void _showErrorToast(String title, String message) {
    if (!mounted) return;
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      description: Text(message, style: GoogleFonts.poppins()),
      autoCloseDuration: const Duration(seconds: 4),
      style: ToastificationStyle.fillColored,
      alignment: Alignment.bottomCenter,
      backgroundColor: Colors.white,
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

  Widget _buildSectionContainer({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: secondaryColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
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
              fontWeight: FontWeight.w600,
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
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            spreadRadius: 1,
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
          labelText: label,
          hintText: hintText,
          hintStyle: GoogleFonts.poppins(
            color: textSecondary,
            fontSize: 14,
          ),
          labelStyle: GoogleFonts.poppins(
            color: textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: secondaryColor,
            border: Border.all(color: borderColor, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            value: value,
            items: items.map((item) {
              return DropdownMenuItem(
                value: item,
                child: Text(
                  item,
                  style: GoogleFonts.poppins(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (!mounted) return;
              setState(() => onChanged(value));
            },
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
            ),
            dropdownColor: secondaryColor,
            icon: Icon(Icons.arrow_drop_down, color: accentColor),
            style: GoogleFonts.poppins(color: textPrimary, fontSize: 15),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  Widget _buildEventForm(_EventForm event, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: secondaryColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Event ${index + 1}',
                style: GoogleFonts.poppins(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_eventForms.length > 1)
                IconButton(
                  icon: Icon(Icons.delete, color: errorColor),
                  onPressed: () {
                    if (!mounted) return;
                    setState(() {
                      _eventForms.removeAt(index);
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: event.nameController,
            label: 'Event Name',
            hintText: 'e.g., Men\'s Singles',
            icon: Icons.event,
            validator: (value) => value == null || value.trim().isEmpty ? 'Enter an event name' : null,
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Event Format',
            value: event.eventType,
            items: [
              'Knockout',
              'Round-Robin',
              'Double Elimination',
              'Group + Knockout',
              'Team Format',
              'Ladder',
              'Swiss Format',
            ],
            onChanged: (value) {
              if (!mounted) return;
              setState(() => event.eventType = value!);
            },
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Match Type',
            value: event.matchType,
            items: ['Men\'s Singles', 'Women\'s Singles', 'Men\'s Doubles', 'Women\'s Doubles', 'Mixed Doubles'],
            onChanged: (value) {
              if (!mounted) return;
              setState(() => event.matchType = value!);
            },
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Level',
            value: event.level,
            items: ['Beginner', 'Intermediate', 'Professional'],
            onChanged: (value) {
              if (!mounted) return;
              setState(() => event.level = value!);
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: event.maxParticipantsController,
            label: 'Max Participants',
            hintText: 'e.g., 16',
            icon: Icons.people,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter max participants';
              }
              final max = int.tryParse(value);
              if (max == null || max <= 0) {
                return 'Enter a valid number';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              final timeZone = tz.getLocation(widget.timezone);
              final now = tz.TZDateTime.now(timeZone);
              final picked = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: now.subtract(const Duration(days: 365 * 20)),
                lastDate: now,
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
                  event.bornAfter = tz.TZDateTime(
                    timeZone,
                    picked.year,
                    picked.month,
                    picked.day,
                  );
                });
              }
            },
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: secondaryColor,
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: accentColor, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    event.bornAfter == null
                        ? 'Players Born After (Optional)'
                        : DateFormat('MMM dd, yyyy').format(event.bornAfter!),
                    style: GoogleFonts.poppins(
                      color: event.bornAfter == null ? textSecondary : textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitEvents,
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
                'Save Events',
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

  @override
  Widget build(BuildContext context) {
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
                      horizontal: isWideScreen ? constraints.maxWidth * 0.15 : 20.0,
                      vertical: 16.0,
                    ),
                    child: CustomScrollView(
                      key: const ValueKey('event_form_scroll_view'),
                      slivers: [
                        SliverAppBar(
                          backgroundColor: secondaryColor.withOpacity(0.95),
                          elevation: 4,
                          leading: IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textPrimary, size: 24),
                            onPressed: () => Navigator.pop(context),
                          ),
                          title: Text(
                            'Add Events',
                            style: GoogleFonts.poppins(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 24,
                              letterSpacing: 0.5,
                            ),
                          ),
                          centerTitle: true,
                          pinned: true,
                          expandedHeight: 80,
                          flexibleSpace: FlexibleSpaceBar(
                            background: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [accentColor.withOpacity(0.1), secondaryColor],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildListDelegate([
                            const SizedBox(height: 24),
                            _buildSectionContainer(
                              title: 'Events',
                              children: [
                                ..._eventForms.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final event = entry.value;
                                  return Column(
                                    children: [
                                      _buildEventForm(event, index),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                }),
                                TextButton.icon(
                                  icon: Icon(Icons.add_circle_outline, color: accentColor),
                                  label: Text(
                                    'Add Another Event',
                                    style: GoogleFonts.poppins(
                                      color: accentColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  onPressed: () {
                                    if (!mounted) return;
                                    setState(() => _eventForms.add(_EventForm()));
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _buildSubmitButton(),
                            const SizedBox(height: 40),
                          ]),
                        ),
                      ],
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
}

class _EventForm {
  final TextEditingController nameController = TextEditingController();
  String eventType = 'Knockout';
  String level = 'Beginner';
  final TextEditingController maxParticipantsController = TextEditingController();
  tz.TZDateTime? bornAfter;
  String matchType = 'Men\'s Singles';

  bool validate() {
    final nameValid = nameController.text.trim().isNotEmpty;
    final maxParticipants = maxParticipantsController.text.trim();
    final maxParticipantsValid = maxParticipants.isNotEmpty &&
        int.tryParse(maxParticipants) != null &&
        int.parse(maxParticipants) > 0;
    final matchTypeValid = matchType.isNotEmpty;
    final eventTypeValid = eventType.isNotEmpty;
    final levelValid = level.isNotEmpty;
    return nameValid && maxParticipantsValid && matchTypeValid && eventTypeValid && levelValid;
  }

  void dispose() {
    nameController.dispose();
    maxParticipantsController.dispose();
  }
}