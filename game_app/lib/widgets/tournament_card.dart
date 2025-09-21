import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/widgets/timezone_utils.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class TournamentCard extends StatefulWidget {
  final Tournament tournament;
  final String creatorName;
  final bool isCreator;
  final VoidCallback? onImageTap;
  final VoidCallback? onMoreEventsTap;

  const TournamentCard({
    super.key,
    required this.tournament,
    required this.creatorName,
    required this.isCreator,
    this.onImageTap,
    this.onMoreEventsTap,
  });

  @override
  State<TournamentCard> createState() => _TournamentCardState();
}

class _TournamentCardState extends State<TournamentCard> {
  int _selectedEventIndex = 0;

  void _selectEvent(int index) {
    setState(() {
      _selectedEventIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvent = widget.tournament.events[_selectedEventIndex];
    final startTime = tz.TZDateTime.from(
        widget.tournament.startDate, tz.getLocation(widget.tournament.timezone));
    final participantsText =
        '${selectedEvent.participants.length}/${selectedEvent.maxParticipants}';
    
    // Use TimezoneUtils to get the abbreviation
    final timezoneAbbreviation = TimezoneUtils.getTimezoneAbbreviation(
        widget.tournament.timezone);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isSmallScreen = constraints.maxWidth < 400;
        final double imageHeight = isSmallScreen ? 120 : 140;
        final double titleFontSize = isSmallScreen ? 16 : 18;
        final double detailFontSize = isSmallScreen ? 12 : 13;
        final double sponsorImageSize = isSmallScreen ? 40 : 50;

        return Container(
          margin: EdgeInsets.symmetric(
            vertical: 8,
            horizontal: isSmallScreen ? 12 : 16,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Creator section at the top
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isSmallScreen ? 12 : 16,
                  isSmallScreen ? 12 : 16,
                  isSmallScreen ? 12 : 16,
                  8,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Created by ${widget.creatorName}',
                        style: GoogleFonts.poppins(
                          fontSize: isSmallScreen ? 12 : 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    if (widget.isCreator)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Your Event',
                          style: GoogleFonts.poppins(
                            fontSize: isSmallScreen ? 10 : 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1976D2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Divider
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 12 : 16),
                child: const Divider(height: 1, color: Color(0xFFEEEEEE)),
              ),

              // Tournament image and details
              Padding(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        GestureDetector(
                          onTap: widget.onImageTap,
                          child: Container(
                            width: double.infinity,
                            height: imageHeight,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey[100],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: widget.tournament.profileImage != null &&
                                      widget.tournament.profileImage!.isNotEmpty
                                  ? Image.network(
                                      widget.tournament.profileImage!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Image.asset(
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
                        ),
                        Positioned(
                          top: isSmallScreen ? 8 : 12,
                          right: isSmallScreen ? 8 : 12,
                          child: Container(
                            width: sponsorImageSize,
                            height: sponsorImageSize,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[100],
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: widget.tournament.sponsorImage != null &&
                                      widget.tournament.sponsorImage!.isNotEmpty
                                  ? Image.network(
                                      widget.tournament.sponsorImage!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Image.asset(
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
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.tournament.name,
                      style: GoogleFonts.poppins(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      icon: Icons.sports,
                      text:
                          '${widget.tournament.gameType} • ${widget.tournament.gameFormat}',
                      fontSize: detailFontSize,
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow(
                      icon: Icons.location_on,
                      text: '${widget.tournament.venue}, ${widget.tournament.city}',
                      fontSize: detailFontSize,
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow(
                      icon: Icons.calendar_today,
                      // Updated to use timezone abbreviation
                      text:
                          '${DateFormat('MMM dd, yyyy').format(tz.TZDateTime.from(widget.tournament.startDate, tz.getLocation(widget.tournament.timezone)))} - ${DateFormat('MMM dd, yyyy').format(tz.TZDateTime.from(widget.tournament.endDate, tz.getLocation(widget.tournament.timezone)))} • ${DateFormat('h:mm a').format(startTime)} ($timezoneAbbreviation)',
                      fontSize: detailFontSize,
                    ),
                    const SizedBox(height: 12),
                    
                    // Events row with horizontal scrolling
                    _buildEventsRow(isSmallScreen),
                  ],
                ),
              ),

              // Participants section with accent color
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 178, 177, 177),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_alt_outlined,
                            size: 18, color: Color(0xFF757575)),
                        const SizedBox(width: 6),
                        Text(
                          'Participants',
                          style: GoogleFonts.poppins(
                            fontSize: isSmallScreen ? 12 : 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF757575),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        participantsText,
                        style: GoogleFonts.poppins(
                          fontSize: isSmallScreen ? 12 : 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEventsRow(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Events:',
          style: GoogleFonts.poppins(
            fontSize: isSmallScreen ? 12 : 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF616161),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: isSmallScreen ? 36 : 40,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.tournament.events.length,
                  itemBuilder: (context, index) {
                    final event = widget.tournament.events[index];
                    final isSelected = index == _selectedEventIndex;
                    
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          event.name,
                          style: GoogleFonts.poppins(
                            fontSize: isSmallScreen ? 11 : 12,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? Colors.white : const Color(0xFF616161),
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            _selectEvent(index);
                          }
                        },
                        selectedColor: const Color(0xFF1976D2),
                        backgroundColor: Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 12 : 16,
                          vertical: isSmallScreen ? 4 : 6,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.onMoreEventsTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: InkWell(
                    onTap: widget.onMoreEventsTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 12 : 16,
                        vertical: isSmallScreen ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'More',
                        style: GoogleFonts.poppins(
                          fontSize: isSmallScreen ? 11 : 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF616161),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow({required IconData icon, required String text, required double fontSize}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF9E9E9E)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              color: const Color(0xFF616161),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}