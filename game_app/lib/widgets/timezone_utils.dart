import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class TimezoneUtils {
  // Map IANA timezone to human-readable abbreviations
  static const Map<String, String> _timezoneAbbreviations = {
    // North America
    'America/New_York': 'EST/EDT',
    'America/Los_Angeles': 'PST/PDT',
    'America/Chicago': 'CST/CDT',
    'America/Phoenix': 'MST',
    'America/Denver': 'MST/MDT',
    'America/Anchorage': 'AKST/AKDT',
    'Pacific/Honolulu': 'HST',
    'America/Toronto': 'EST/EDT',
    'America/Vancouver': 'PST/PDT',
    'America/Mexico_City': 'CST',
    'America/Edmonton': 'MST/MDT',
    'America/Winnipeg': 'CST/CDT',
    'America/Halifax': 'AST/ADT',
    'America/St_Johns': 'NST/NDT',

    // South America
    'America/Argentina/Buenos_Aires': 'ART',
    'America/Sao_Paulo': 'BRT',
    'America/Lima': 'PET',
    'America/Bogota': 'COT',
    'America/Santiago': 'CLT',
    'America/Caracas': 'VET',

    // Europe
    'Europe/London': 'GMT/BST',
    'Europe/Paris': 'CET/CEST',
    'Europe/Berlin': 'CET/CEST',
    'Europe/Rome': 'CET/CEST',
    'Europe/Madrid': 'CET/CEST',
    'Europe/Amsterdam': 'CET/CEST',
    'Europe/Brussels': 'CET/CEST',
    'Europe/Vienna': 'CET/CEST',
    'Europe/Prague': 'CET/CEST',
    'Europe/Budapest': 'CET/CEST',
    'Europe/Warsaw': 'CET/CEST',
    'Europe/Stockholm': 'CET/CEST',
    'Europe/Oslo': 'CET/CEST',
    'Europe/Copenhagen': 'CET/CEST',
    'Europe/Helsinki': 'EET/EEST',
    'Europe/Athens': 'EET/EEST',
    'Europe/Lisbon': 'WET/WEST',
    'Europe/Dublin': 'GMT/IST',
    'Europe/Zurich': 'CET/CEST',
    'Europe/Moscow': 'MSK',
    'Europe/Istanbul': 'TRT',

    // Asia
    'Asia/Kolkata': 'IST',
    'Asia/Singapore': 'SGT',
    'Asia/Kuala_Lumpur': 'MYT',
    'Asia/Jakarta': 'WIB',
    'Asia/Bangkok': 'ICT',
    'Asia/Manila': 'PHT',
    'Asia/Shanghai': 'CST',
    'Asia/Hong_Kong': 'HKT',
    'Asia/Taipei': 'CST',
    'Asia/Seoul': 'KST',
    'Asia/Tokyo': 'JST',
    'Asia/Dubai': 'GST',
    'Asia/Riyadh': 'AST',
    'Asia/Qatar': 'AST',
    'Asia/Jerusalem': 'IST',
    'Asia/Baghdad': 'AST',
    'Asia/Tehran': 'IRST',
    'Asia/Karachi': 'PKT',
    'Asia/Dhaka': 'BST',

    // Australia & Pacific
    'Australia/Sydney': 'AEST/AEDT',
    'Australia/Melbourne': 'AEST/AEDT',
    'Australia/Brisbane': 'AEST',
    'Australia/Perth': 'AWST/AWDT',
    'Australia/Adelaide': 'ACST/ACDT',
    'Australia/Darwin': 'ACST',
    'Australia/Hobart': 'AEST/AEDT',
    'Pacific/Auckland': 'NZST/NZDT',
    'Pacific/Fiji': 'FJT',

    // Africa
    'Africa/Cairo': 'EET/EEST',
    'Africa/Johannesburg': 'SAST',
    'Africa/Nairobi': 'EAT',
    'Africa/Lagos': 'WAT',
    'Africa/Accra': 'GMT',
    'Africa/Casablanca': 'WET/WEST',
    'Africa/Tunis': 'CET/CEST',
    'Africa/Algiers': 'CET/CEST',
  };

  // Map city names to IANA timezones (your existing mapping)
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

  /// Get timezone abbreviation from IANA timezone identifier
  static String getTimezoneAbbreviation(String ianaTimezone) {
    return _timezoneAbbreviations[ianaTimezone] ?? ianaTimezone;
  }

  /// Get IANA timezone from city name
  static String? getTimezoneFromCity(String cityName) {
    final lowerCity = cityName.toLowerCase().trim();
    return _cityToTimezone[lowerCity];
  }

  /// Get timezone abbreviation from city name
  static String? getAbbreviationFromCity(String cityName) {
    final ianaTimezone = getTimezoneFromCity(cityName);
    if (ianaTimezone != null) {
      return getTimezoneAbbreviation(ianaTimezone);
    }
    return null;
  }

  /// Format date with timezone abbreviation
  static String formatDateWithAbbreviation(
    DateTime dateTime,
    String ianaTimezone, {
    String dateFormat = 'MMM dd, yyyy',
    String timeFormat = 'h:mm a',
  }) {
    final tzLocation = tz.getLocation(ianaTimezone);
    final tzDateTime = tz.TZDateTime.from(dateTime, tzLocation);
    
    final dateFormatter = DateFormat(dateFormat);
    final timeFormatter = DateFormat(timeFormat);
    
    final abbreviation = getTimezoneAbbreviation(ianaTimezone);
    return '${dateFormatter.format(tzDateTime)} • ${timeFormatter.format(tzDateTime)} ($abbreviation)';
  }


  static String getCurrentAbbreviation(String ianaTimezone) {
    try {
      final location = tz.getLocation(ianaTimezone);
      final now = tz.TZDateTime.now(location);
      final offset = now.timeZoneOffset;
      
      // Simple abbreviation based on offset (this is a basic implementation)
      // You might want to enhance this based on specific timezone rules
      if (offset.isNegative) {
        final hours = offset.inHours.abs();
        return 'UTC-${hours.toString().padLeft(2, '0')}';
      } else {
        final hours = offset.inHours;
        return hours == 0 ? 'UTC' : 'UTC+${hours.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return getTimezoneAbbreviation(ianaTimezone);
    }
  }
}