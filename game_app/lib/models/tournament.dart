import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

class Tournament {
  final String id;
  final String name;
  final String? description;
  final String venue;
  final String city;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime registrationEnd;
  final double entryFee;
  final double? extraFee;
  final bool canPayAtVenue;
  final String status;
  final String createdBy;
  final DateTime createdAt;
  final String? rules;
  final String gameFormat;
  final String gameType;
  final bool bringOwnEquipment;
  final bool costShared;
  final String? profileImage;
  final String? sponsorImage;
  final String? contactName;
  final String? contactNumber;
  final String timezone;
  late final List<Event> events;

  Tournament({
    required this.id,
    required this.name,
    this.description,
    required this.venue,
    required this.city,
    required this.startDate,
    required this.endDate,
    required this.registrationEnd,
    required this.entryFee,
    this.extraFee,
    required this.canPayAtVenue,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.rules,
    required this.gameFormat,
    required this.gameType,
    required this.bringOwnEquipment,
    required this.costShared,
    this.profileImage,
    this.sponsorImage,
    this.contactName,
    this.contactNumber,
    required this.timezone,
    required this.events,
  });

  TimeOfDay getStartTime() {
    final tzDateTime = tz.TZDateTime.from(startDate, tz.getLocation(timezone));
    return TimeOfDay(hour: tzDateTime.hour, minute: tzDateTime.minute);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'venue': venue,
      'city': city,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'registrationEnd': Timestamp.fromDate(registrationEnd),
      'entryFee': entryFee,
      'extraFee': extraFee,
      'canPayAtVenue': canPayAtVenue,
      'status': status,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'rules': rules,
      'gameFormat': gameFormat,
      'gameType': gameType,
      'bringOwnEquipment': bringOwnEquipment,
      'costShared': costShared,
      'profileImage': profileImage,
      'sponsorImage': sponsorImage,
      'contactName': contactName,
      'contactNumber': contactNumber,
      'timezone': timezone,
      'events': events.map((e) => e.toFirestore()).toList(),
    };
  }

  factory Tournament.fromFirestore(Map<String, dynamic> data, String id) {
    return Tournament(
      id: id,
      name: data['name'] ?? 'Unnamed Tournament',
      description: data['description'],
      venue: data['venue'] ?? 'Unknown Venue',
      city: data['city'] ?? 'Unknown City',
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 7)),
      registrationEnd: (data['registrationEnd'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 3)),
      entryFee: (data['entryFee'] as num?)?.toDouble() ?? 0.0,
      extraFee: (data['extraFee'] as num?)?.toDouble(),
      canPayAtVenue: data['canPayAtVenue'] ?? false,
      status: data['status'] ?? 'unknown',
      createdBy: data['createdBy'] ?? 'unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      rules: data['rules'],
      gameFormat: data['gameFormat'] ?? 'Unknown',
      gameType: data['gameType'] ?? 'Unknown',
      bringOwnEquipment: data['bringOwnEquipment'] ?? false,
      costShared: data['costShared'] ?? false,
      profileImage: data['profileImage'],
      sponsorImage: data['sponsorImage'],
      contactName: data['contactName'],
      contactNumber: data['contactNumber'],
      timezone: data['timezone'] ?? 'UTC',
      events: (data['events'] as List<dynamic>?)
              ?.map((e) => Event.fromFirestore(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class Event {
  final String name;
  final String format;
  final String level;
  final int maxParticipants;
  final List<String> participants;
  final DateTime? bornAfter;
  final String matchType;
  final List<String> matches;
  final int numberOfCourts;
  final List<String> timeSlots;

  Event({
    required this.name,
    required this.format,
    required this.level,
    required this.maxParticipants,
    required this.participants,
    this.bornAfter,
    required this.matchType,
    required this.matches,
    this.numberOfCourts = 1,
    this.timeSlots = const [],
  });

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'format': format,
      'level': level,
      'maxParticipants': maxParticipants,
      'participants': participants,
      'bornAfter': bornAfter != null ? Timestamp.fromDate(bornAfter!) : null,
      'matchType': matchType,
      'matches': matches,
      'numberOfCourts': numberOfCourts,
      'timeSlots': timeSlots,
    };
  }

  factory Event.fromFirestore(Map<String, dynamic> data) {
    return Event(
      name: data['name'] ?? 'Unknown Event',
      format: data['format'] ?? 'Unknown',
      level: data['level'] ?? 'Unknown',
      maxParticipants: data['maxParticipants'] ?? 0,
      participants: List<String>.from(data['participants'] ?? []),
      bornAfter: (data['bornAfter'] as Timestamp?)?.toDate(),
      matchType: data['matchType'] ?? "Men's Singles",
      matches: List<String>.from(data['matches'] ?? []),
      numberOfCourts: data['numberOfCourts'] ?? 1,
      timeSlots: List<String>.from(data['timeSlots'] ?? []),
    );
  }
}