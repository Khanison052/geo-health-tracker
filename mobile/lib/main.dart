// ═══════════════════════════════════════════════════════════════════
// Geo-Health Tracker — Flutter Mobile App (Enterprise Edition)
// สำหรับ: อสม. รพ.สต. และผู้บริหาร ใช้บันทึกผู้ป่วยและปักหมุดพิกัด GPS
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
//import 'dart:io';
import 'dart:ui'; // 🌟 เพิ่มบรรทัดนี้เพื่อเรียกใช้เอฟเฟกต์เบลอกระจก (ImageFilter)

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
//import 'src/platform_api_host.dart';
import 'package:flutter/gestures.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const GeoHealthApp());
}

// ─── Shared Preferences Helper ─────────────────────────────────────────────
class AuthStorage {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}

// ─── Models ────────────────────────────────────────────────────────────────

class User {
  final int id;
  final String username;
  final String email;
  final String nameTh;
  final String role;
  // 🌟 1. เพิ่มตัวแปรมารับค่าพื้นที่
  final String? hospital;
  final String? healthRegion;
  final String? province;
  final String? district;
  final String? subdistrict;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.nameTh,
    required this.role,
    this.hospital,
    this.healthRegion,
    this.province,
    this.district,
    this.subdistrict,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      nameTh: json['name_th']?.toString() ?? '',
      role: json['role']?.toString() ?? 'volunteer',
      // 🌟 2. ดึงค่าจาก JSON ที่ Node.js ส่งมา
      hospital: json['hospital']?.toString(),
      healthRegion: json['health_region']?.toString(),
      province: json['province']?.toString(),
      district: json['district']?.toString(),
      subdistrict: json['subdistrict']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'name_th': nameTh,
    'role': role,
    // 🌟 3. บันทึกค่าลงในเครื่องมือถือ
    'hospital': hospital,
    'health_region': healthRegion,
    'province': province,
    'district': district,
    'subdistrict': subdistrict,
  };
}

class Disease {
  final String code;
  final String name;
  final String group;
  final Color color;
  final IconData icon;

  const Disease({
    required this.code,
    required this.name,
    required this.group,
    required this.color,
    required this.icon,
  });

  factory Disease.fromJson(Map<String, dynamic> json) {
    return Disease(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      color: const Color(0xFF1D9E75),
      icon: Icons.medical_services,
    );
  }
}

class Patient {
  final int id;
  final String name;
  final String diseaseCode;
  final String diseaseName;
  final double lat;
  final double lng;
  final String village;
  final String severity;
  final DateTime reportDate;

  const Patient({
    required this.id,
    required this.name,
    required this.diseaseCode,
    required this.diseaseName,
    required this.lat,
    required this.lng,
    required this.village,
    required this.severity,
    required this.reportDate,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      diseaseCode: json['disease_code']?.toString() ?? '',
      diseaseName: json['disease_name']?.toString() ?? '',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      village: json['village']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'mild',
      reportDate: DateTime.tryParse(json['report_date']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

// 🌟 1. โมเดลสถานที่
class CommunityPlace {
  final int id;
  final String name;
  final String type;
  final double lat;
  final double lng;

  const CommunityPlace({required this.id, required this.name, required this.type, required this.lat, required this.lng});

  factory CommunityPlace.fromJson(Map<String, dynamic> json) {
    return CommunityPlace(
      id: json['id'] as int,
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      lat: double.tryParse(json['lat'].toString()) ?? 0.0,
      lng: double.tryParse(json['lng'].toString()) ?? 0.0,
    );
  }
}

// 🌟 2. ฟังก์ชันดึงและส่งข้อมูลสถานที่ (วางรวมกับ Future<void> postPatient...)
Future<List<CommunityPlace>> fetchPlaces() async {
  try {
    final response = await http.get(Uri.parse('$kApiBase/places'));
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      return data.map((item) => CommunityPlace.fromJson(item as Map<String, dynamic>)).toList();
    }
  } catch (e) {
    debugPrint('fetchPlaces error: $e');
  }
  return <CommunityPlace>[];
}

Future<void> postPlace({required String name, required String type, required double lat, required double lng}) async {
  try {
    final response = await http.post(
      Uri.parse('$kApiBase/places'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'type': type, 'lat': lat, 'lng': lng}),
    );
    if (response.statusCode >= 400) throw Exception('ไม่สามารถบันทึกสถานที่ได้');
  } catch (e) {
    debugPrint('postPlace error: $e');
    rethrow;
  }
}

class Vulnerable {
  final int id;
  final String name;
  final String type;
  final double lat;
  final double lng;
  final String address;

  const Vulnerable({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    required this.address,
  });

  factory Vulnerable.fromJson(Map<String, dynamic> json) {
    return Vulnerable(
      id: json['id'] as int? ?? 0,
      name: json['name_th']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      // 🌟 ดักจับเคสที่ lat/lng เป็น String จาก Database
      lat: double.tryParse(json['lat']?.toString() ?? '0.0') ?? 0.0,
      lng: double.tryParse(json['lng']?.toString() ?? '0.0') ?? 0.0,
      address: json['address_detail']?.toString() ?? '',
    );
  }
}

Future<List<Vulnerable>> fetchVulnerables() async {
  try {
    // 🌟 ดึง Token และใส่ใน Headers เพื่อให้ Backend รู้ว่าใครกำลังขอข้อมูล
    final headers = await _getAuthHeaders();
    final response = await http.get(Uri.parse('$kApiBase/vulnerable'), headers: headers);
    
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];
      return data.map((item) => Vulnerable.fromJson(item as Map<String, dynamic>)).toList();
    }
  } catch (e) {
    debugPrint('fetchVulnerables error: $e');
  }
  return <Vulnerable>[];
}

const LatLng _defaultMapCenter = LatLng(14.9798, 102.0978);

// ─── Constants ─────────────────────────────────────────────────────────────

final kApiBase = 'https://geo-health-api.onrender.com/api'; // IP เซิร์ฟเวอร์จริง

// ─── Helper: Add Token to Headers ──────────────────────────────────────────
Future<Map<String, String>> _getAuthHeaders() async {
  final token = await AuthStorage.getToken();
  final headers = {'Content-Type': 'application/json'};
  if (token != null) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
}

// ─── Authentication Functions ─────────────────────────────────────────────

Future<User> registerUser({
  required String username,
  required String email,
  required String password,
  required String nameTh,
  required String hospital,      // 🌟 เพิ่มมาใหม่
  required String healthRegion,  // 🌟 เพิ่มมาใหม่
  required String province,      // 🌟 เพิ่มมาใหม่
  required String district,      // 🌟 เพิ่มมาใหม่
  required String subdistrict,   // 🌟 เพิ่มมาใหม่
}) async {
  try {
    final response = await http.post(
      Uri.parse('$kApiBase/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'name_th': nameTh,
        'hospital': hospital,           // 🌟 ส่งไป Node.js
        'health_region': healthRegion,  // 🌟 ส่งไป Node.js
        'province': province,           // 🌟 ส่งไป Node.js
        'district': district,           // 🌟 ส่งไป Node.js
        'subdistrict': subdistrict,     // 🌟 ส่งไป Node.js
      }),
    );

    if (response.statusCode != 201) {
      try {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? 'ไม่สามารถสมัครสมาชิกได้');
      } catch (_) {
        throw Exception('ไม่สามารถสมัครสมาชิกได้: ${response.statusCode} ${response.body}');
      }
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(data['user']);
  } catch (e) {
    debugPrint('registerUser error: $e');
    rethrow;
  }
}

Future<({User user, String token})> loginUser({
  required String username,
  required String password,
}) async {
  try {
    final response = await http.post(
      Uri.parse('$kApiBase/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      try {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
      } catch (_) {
        throw Exception('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง: ${response.statusCode} ${response.body}');
      }
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final user = User.fromJson(data['user']);
    final token = data['token'] as String;

    // Save to local storage
    await AuthStorage.saveToken(token);
    await AuthStorage.saveUser(user.toJson());

    return (user: user, token: token);
  } catch (e) {
    debugPrint('loginUser error: $e');
    rethrow;
  }
}

Future<void> logoutUser() async {
  await AuthStorage.clear();
}

Future<bool> isUserLoggedIn() async {
  final token = await AuthStorage.getToken();
  return token != null;
}

Future<List<Patient>> fetchPatients() async {
  try {
    final headers = await _getAuthHeaders();
    final response = await http.get(Uri.parse('$kApiBase/patients'), headers: headers);
    if (response.statusCode != 200) {
      return <Patient>[];
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((item) => Patient.fromJson(item as Map<String, dynamic>)).toList();
  } catch (e) {
    debugPrint('fetchPatients error: $e');
    return <Patient>[];
  }
}

Future<void> deletePatient(int id) async {
  try {
    final headers = await _getAuthHeaders();
    final response = await http.delete(
      Uri.parse('$kApiBase/patients/$id'),
      headers: headers,
    );
    if (response.statusCode >= 400) {
      throw Exception('ไม่สามารถลบข้อมูลได้');
    }
  } catch (e) {
    debugPrint('deletePatient error: $e');
    rethrow;
  }
}

Future<void> postPatient({
  required String name,
  required String diseaseCode,
  required double lat,
  required double lng,
  required Map<String, String> addressData,
  required String severity,
  int? age,
  String? gender,
  String? nationality,
  String? occupation,
  DateTime? onsetDate,
  DateTime? dateOfDeath,
}) async {
  try {
    // 🌟 1. ดึง Token ของคนที่กำลังใช้งานแอปอยู่
    final token = await AuthStorage.getToken();

    final response = await http.post(
      Uri.parse('$kApiBase/patients'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // 🌟 2. แนบ Token ไปให้ Backend รู้จักว่าใครเป็นคนกรอก
      },
      body: jsonEncode({
        'name': name,
        'disease_code': diseaseCode,
        'lat': lat,
        'lng': lng,
        'address': addressData, 
        'severity': severity,
        'age': age,
        'gender': gender,
        'nationality': nationality,
        'occupation': occupation,
        'onset_date': onsetDate?.toIso8601String(),
        'date_of_death': dateOfDeath?.toIso8601String(),
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception('ไม่สามารถบันทึกข้อมูลได้');
    }
  } catch (e) {
    debugPrint('postPatient error: $e');
    rethrow;
  }
}

// 🌟 ส่งข้อมูลคัดกรองสุขภาพจิต (อัปเดตเพิ่มพารามิเตอร์ SMI V-SCAN)
Future<void> postMentalScreening({
  required String name, required double lat, required double lng, required Map<String, String> addressData,
  int? age, String? gender, String? nationality, String? occupation,
  required String targetGroup, required String riskLevel,
  required String smiSleep, required String smiPace, required String smiTalk, // 🌟 เพิ่มมารับค่า SMI
  required String smiIrritable, required String smiParanoia,
  required String smiHistory, required String smiHistoryDetail,
  required String oasSelf, required String oasOthers, required String oasProperty, required String oasAssessor,
}) async {
  try {
    final token = await AuthStorage.getToken();

    final response = await http.post(
      Uri.parse('$kApiBase/mental-screening'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': name, 'lat': lat, 'lng': lng, 'address': addressData,
        'age': age, 'gender': gender, 'nationality': nationality, 'occupation': occupation,
        'target_group': targetGroup, 'risk_level': riskLevel,
        // 🌟 แนบค่า SMI ส่งไปให้ Backend
        'smi_sleep': smiSleep, 'smi_pace': smiPace, 'smi_talk': smiTalk,
        'smi_irritable': smiIrritable, 'smi_paranoia': smiParanoia,
        'smi_history': smiHistory, 'smi_history_detail': smiHistoryDetail,
        'oas_self': oasSelf, 'oas_others': oasOthers, 'oas_property': oasProperty, 'oas_assessor': oasAssessor, 
      }),
    );
    if (response.statusCode >= 400) throw Exception('ไม่สามารถบันทึกข้อมูลได้');
  } catch (e) {
    debugPrint('postMentalScreening error: $e');
    rethrow;
  }
}

// 🌟 ส่งข้อมูลติดตามผู้ป่วยจิตเวช
Future<void> postPsychiatricPatient({
  required String name, required double lat, required double lng, required Map<String, String> addressData,
  int? age, String? gender, String? nationality, String? occupation,
  required String psychiatricGroup, required String followUpStatus,
}) async {
  try {
    // 🌟 1. ดึง Token
    final token = await AuthStorage.getToken();

    final response = await http.post(
      Uri.parse('$kApiBase/psychiatric-patients'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // 🌟 2. แนบ Token
      },
      body: jsonEncode({
        'name': name, 'lat': lat, 'lng': lng, 'address': addressData,
        'age': age, 'gender': gender, 'nationality': nationality, 'occupation': occupation,
        'psychiatric_group': psychiatricGroup, 'follow_up_status': followUpStatus,
      }),
    );
    if (response.statusCode >= 400) throw Exception('ไม่สามารถบันทึกข้อมูลได้');
  } catch (e) {
    debugPrint('postPsychiatric error: $e');
    rethrow;
  }
}

Future<List<Disease>> searchDiseases(String query) async {
  final uri = Uri.parse('$kApiBase/diseases').replace(queryParameters: {
    if (query.isNotEmpty) 'q': query,
  });
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw Exception('ไม่สามารถดึงรายการโรคได้');
  }
  final data = jsonDecode(response.body) as List<dynamic>;
  return data.map((item) => Disease.fromJson(item as Map<String, dynamic>)).toList();
}

Color severityColor(String severity) {
  if (severity.toLowerCase() == 'รุนแรง' || severity.toLowerCase() == 'severe') {
    return Colors.red;
  }
  if (severity.toLowerCase() == 'ปานกลาง' || severity.toLowerCase() == 'moderate') {
    return Colors.orange;
  }
  return Colors.green;
}

// 🌟 3. ฟังก์ชันจับคู่ประเภทกับไอคอนหมุด (อัปเดตตามชื่อไฟล์จริง)
String getMarkerIconPath(String? placeType) {
  final String type = (placeType ?? '').trim();
  switch (type) {
    case 'สถานที่ราชการอื่นๆ': return 'assets/icons/logo_municipio.png';
    case 'บ้าน': return 'assets/icons/home.png';
    case 'บ้านร้าง': return 'assets/icons/abandoned_house.png';
    case 'โรงงาน': return 'assets/icons/factory.png';
    case 'วัด/สำนักสงฆ์': return 'assets/icons/temple.png';
    case 'สถานบริการสุขภาพ': return 'assets/icons/health_service.png';
    case 'อู่ซ่อมรถ': return 'assets/icons/service_car.png';
    case 'แหล่งน้ำ': return 'assets/icons/water.png';
    case 'ศาลาหมู่บ้าน': return 'assets/icons/village_pavilion.png';
    case 'ร้านค้า': return 'assets/icons/shop.png';
    case 'ปั๊มน้ำมัน': return 'assets/icons/gas_station.png';
    case 'ประปา': return 'assets/icons/water_supply.png';
    case 'โรงเรียน': return 'assets/icons/school.png';
    case 'ฟาร์มวัว': return 'assets/icons/cow.png';
    case 'ฟาร์มหมู': return 'assets/icons/pig.png';
    case 'ฟาร์มไก่': return 'assets/icons/chicken.png';
    case 'สถานีตำรวจ': return 'assets/icons/police.png';
    case 'บ้านผู้นำชุมชน': return 'assets/icons/Teacher_residence.png';
    case 'บ้านอสม.': return 'assets/icons/osomor.png';
    case 'อบต/เทศบาล': return 'assets/icons/municipio.png';
    case 'ตลาด': return 'assets/icons/market.png';
    case 'รีสอร์ท': return 'assets/icons/resort.png';
    case 'โรงแรม': return 'assets/icons/hotel.png';
    default: return 'assets/icons/home.png'; // รูปภาพเริ่มต้นถ้าหาไม่เจอ
  }
}

// 🌟 ฟังก์ชันใหม่: คืนค่าตำแหน่งไฟล์รูปภาพไอคอนตามประเภทโรค (แก้ไขให้อิงจากรหัสโรคก่อน)
String getPatientIconPath(String? diseaseCode, String? diseaseName) {
  final String code = (diseaseCode ?? '').trim().toUpperCase();
  final String disease = (diseaseName ?? '').trim().toLowerCase();

  // 1. เช็คจากรหัสโรคที่ถูกกำหนดมาจาก Node.js ก่อน
  if (code == 'PSY') {
    return 'assets/icons/icon_psychiatry.png'; // โรคจิตเวช
  } else if (code == 'MH') {
    return 'assets/icons/icon_mental_health.png'; // สุขภาพจิต
  } 
  
  // 2. ถ้าเป็นเคสเก่าๆ (หรือบางเคสที่ไม่ได้ผูกรหัสมา) ค่อยมาเช็คจากชื่อโรค
  else if (disease.contains('จิตเวช') || disease.contains('จิตเภท') || disease.contains('หลงผิด') || disease.contains('ซึมเศร้า')) {
    return 'assets/icons/icon_psychiatry.png';
  } else if (disease.contains('สุขภาพจิต') || disease.contains('เครียด') || disease.contains('เสพติด')) {
    return 'assets/icons/icon_mental_health.png';
  } 
  
  // 3. นอกนั้นถือเป็นโรคติดต่อ (506) ทั้งหมด
  else {
    return 'assets/icons/icon_infectious.png';
  }
}

class HomeSummary {
  final String areaName;
  final int newToday;
  final int totalThisMonth;
  final int vulnerableTotal;
  final int totalPatients;
  final int diseaseTotal;

  const HomeSummary({
    required this.areaName,
    required this.newToday,
    required this.totalThisMonth,
    required this.vulnerableTotal,
    required this.totalPatients,
    required this.diseaseTotal,
  });

  factory HomeSummary.fromJson(Map<String, dynamic> json) {
    return HomeSummary(
      areaName: json['area_name']?.toString() ?? 'พื้นที่รับผิดชอบ',
      // 🌟 แก้ไข: ใช้ int.tryParse() เพื่อดักจับกรณีที่ Database แอบส่งตัวเลขมาเป็นข้อความ (String)
      newToday: int.tryParse(json['new_today']?.toString() ?? '0') ?? 0,
      totalThisMonth: int.tryParse(json['total_this_month']?.toString() ?? '0') ?? 0,
      vulnerableTotal: int.tryParse(json['vulnerable_total']?.toString() ?? '0') ?? 0,
      totalPatients: int.tryParse(json['total_patients']?.toString() ?? '0') ?? 0,
      diseaseTotal: int.tryParse(json['disease_total']?.toString() ?? '0') ?? 0,
    );
  }
}

// 🌟 อัปเดต: เพิ่มการแนบ Token เพื่อให้ Backend ยอมส่งข้อมูลสถิติให้
Future<HomeSummary> fetchDashboardSummary() async {
  try {
    final headers = await _getAuthHeaders(); // 🌟 ดึง Token ของผู้ใช้
    final response = await http.get(
      Uri.parse('$kApiBase/stats/summary'), 
      headers: headers, // 🌟 แนบ Token ไปกับ Request
    );
    
    if (response.statusCode != 200) {
      throw Exception('ไม่สามารถดึงสถิติเบื้องต้นได้ (Status: ${response.statusCode})');
    }
    return HomeSummary.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  } catch (e) {
    debugPrint('fetchDashboardSummary error: $e');
    rethrow;
  }
}

// ─── App Root ───────────────────────────────────────────────────────────────

class GeoHealthApp extends StatelessWidget {
  const GeoHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo-Health Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1D9E75),
        fontFamily: 'Sarabun',
      ),
      home: const AuthCheckScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const MainScreen(),
      },
    );
  }
}

// ─── Auth Check Screen (Splashscreen for Auth) ──────────────────────────────

class AuthCheckScreen extends StatelessWidget {
  const AuthCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: isUserLoggedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D9E75).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.health_and_safety,
                      size: 40,
                      color: Color(0xFF1D9E75),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Geo-Health Tracker',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data == true) {
          return const MainScreen();
        }

        return const LoginScreen();
      },
    );
  }
}

// ─── Login Screen ───────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await loginUser(username: username, password: password);
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (error) {
      setState(() => _errorMessage = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🌟 ฟังก์ชันลืมรหัสผ่าน (ใช้เลขบัตร ปชช. อย่างเดียว + ยืนยันรหัสผ่าน + รูปดวงตา)
  void _showForgotPasswordDialog() {
    final userCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    
    bool isLoading = false;
    bool obscureNewPass = true;      // ซ่อน/แสดง รหัสผ่านช่องแรก
    bool obscureConfirmPass = true;  // ซ่อน/แสดง รหัสผ่านช่องยืนยัน

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.lock_reset, color: Color(0xFF1D9E75)),
                  SizedBox(width: 8),
                  Text('ตั้งรหัสผ่านใหม่', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1D9E75))),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('กรุณากรอกเลขบัตรประชาชนที่ใช้สมัคร และตั้งรหัสผ่านใหม่ได้ทันที', style: TextStyle(fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 16),
                    
                    // 1. ช่องกรอกเลขบัตรประชาชน
                    TextField(
                      controller: userCtrl, 
                      decoration: const InputDecoration(labelText: 'เลขบัตรประชาชน 13 หลัก', prefixIcon: Icon(Icons.badge_outlined)), 
                      keyboardType: TextInputType.number,
                      maxLength: 13,
                    ),
                    const SizedBox(height: 6),
                    
                    // 2. ช่องกรอกรหัสผ่านใหม่ (พร้อมรูปดวงตา)
                    TextField(
                      controller: newPassCtrl, 
                      obscureText: obscureNewPass,
                      decoration: InputDecoration(
                        labelText: 'รหัสผ่านใหม่ (8 ตัวอักษรขึ้นไป)', 
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNewPass ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                          onPressed: () => setDialogState(() => obscureNewPass = !obscureNewPass), // สลับสถานะซ่อน/โชว์
                        ),
                      ), 
                    ),
                    const SizedBox(height: 12),

                    // 3. ช่องยืนยันรหัสผ่านใหม่ (พร้อมรูปดวงตา)
                    TextField(
                      controller: confirmPassCtrl, 
                      obscureText: obscureConfirmPass,
                      decoration: InputDecoration(
                        labelText: 'ยืนยันรหัสผ่านใหม่อีกครั้ง', 
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirmPass ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                          onPressed: () => setDialogState(() => obscureConfirmPass = !obscureConfirmPass), // สลับสถานะซ่อน/โชว์
                        ),
                      ), 
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    // 🌟 ดักจับข้อผิดพลาดก่อนส่งไปเซิร์ฟเวอร์
                    if (userCtrl.text.trim().length != 13) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกเลขบัตรประชาชนให้ครบ 13 หลัก'), backgroundColor: Colors.red));
                      return;
                    }
                    if (newPassCtrl.text.trim().length < 8) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร'), backgroundColor: Colors.red));
                      return;
                    }
                    if (newPassCtrl.text.trim() != confirmPassCtrl.text.trim()) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน!'), backgroundColor: Colors.red));
                      return;
                    }

                    setDialogState(() => isLoading = true);
                    
                    try {
                      final response = await http.post(
                        Uri.parse('$kApiBase/reset-password-by-id'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'username': userCtrl.text.trim(), 
                          'newPassword': newPassCtrl.text.trim()
                        }),
                      );
                      
                      if (response.statusCode == 200) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เปลี่ยนรหัสผ่านสำเร็จ! เข้าสู่ระบบด้วยรหัสใหม่ได้เลย'), backgroundColor: Colors.green));
                      } else {
                        final data = jsonDecode(response.body);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'] ?? 'เกิดข้อผิดพลาด'), backgroundColor: Colors.red));
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้'), backgroundColor: Colors.red));
                    } finally {
                      setDialogState(() => isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D9E75), foregroundColor: Colors.white),
                  child: isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                   : const Text('บันทึกรหัสผ่านใหม่'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. ภาพพื้นหลัง (ล่างสุด) เอาฟิล์มดำออกเพื่อให้ภาพสว่างและชัดเจน
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_bg.png',
              fit: BoxFit.cover,
            ),
          ),

          // 2. เนื้อหาหลัก
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  // ใส่เงาให้กรอบกระจกลอยเด่นขึ้นมา
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                    borderRadius: BorderRadius.circular(28),
                  ),
                  // 🌟 พระเอกของเรา ClipRRect + BackdropFilter ทำกระจกฝ้า
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0), // ความเบลอของกระจก
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4), // 🌟 ปรับพื้นให้เป็นสีขาวโปร่งแสง 40%
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5), // ขอบขาวใสเพิ่มมิติกระจก
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // --- โลโก้และชื่อแอป ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1D9E75),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.health_and_safety,
                                    size: 32,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Geo-Health Tracker',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        'ระบบติดตามสุขภาพท้องถิ่น',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Divider(height: 1, color: Colors.black.withValues(alpha: 0.1)),
                            const SizedBox(height: 20),
                            
                            const Text(
                              'เข้าสู่ระบบเพื่อใช้งาน',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16, 
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 20),
                            
                            // 🌟 ปรับช่องกรอกข้อมูลให้กึ่งใส เข้ากับสไตล์กระจก
                            TextField(
                              controller: _usernameController,
                              keyboardType: TextInputType.number,
                              maxLength: 13,
                              decoration: InputDecoration(
                                labelText: 'เลขประจำตัวประชาชน (13 หลัก)',
                                prefixIcon: const Icon(Icons.badge_outlined),
                                counterText: "", 
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.7), // สีขาวกึ่งใส
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'รหัสผ่าน',
                                prefixIcon: const Icon(Icons.lock_outline),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.7), // สีขาวกึ่งใส
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            
                            const SizedBox(height: 24),

                            // ปุ่มเข้าสู่ระบบ
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1D9E75),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : const Text('เข้าสู่ระบบ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            
                            const SizedBox(height: 16),

                            TextButton(
                              onPressed: _showForgotPasswordDialog,
                              child: const Text('ลืมรหัสผ่าน?', style: TextStyle(color: Color.fromARGB(255, 30, 6, 6), decoration: TextDecoration.underline)),
                            ),
                            
                            TextButton(
                              onPressed: () => _showRegisterDialog(),
                              child: const Text(
                                'ยังไม่มีบัญชี? สมัครใช้งานที่นี่',
                                style: TextStyle(
                                  color: Color(0xFF0F6E56), // ใช้สีเขียวเข้มขึ้นให้อ่านง่าย
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRegisterDialog() {
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    
    // 🌟 เพิ่ม Controller สำหรับข้อมูลพื้นที่
    final hospitalCtrl = TextEditingController();
    final regionCtrl = TextEditingController();
    final provinceCtrl = TextEditingController();
    final districtCtrl = TextEditingController();
    final subdistrictCtrl = TextEditingController();
    
    bool isRegistering = false;
    double passwordStrength = 0.0; // 🌟 เพิ่มตัวแปรเก็บระดับความปลอดภัย (0.0 - 1.0)
    bool isAgreed = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5), 
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent, 
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_add_rounded, color: Color(0xFF1D9E75), size: 30),
                          SizedBox(width: 10),
                          Text(
                            'สมัครสมาชิกใหม่',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'กรุณากรอกข้อมูลพื้นที่ปฏิบัติงานเพื่อรอการตรวจสอบ',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 25),

                      // ข้อมูลส่วนตัว
                      _buildRegisterInput(controller: usernameCtrl, label: 'เลขประจำตัวประชาชน (13 หลัก)', icon: Icons.badge_outlined, isNumber: true, limit: 13),
                      const SizedBox(height: 15),
                      _buildRegisterInput(controller: nameCtrl, label: 'ชื่อ-นามสกุล', icon: Icons.account_circle_outlined),
                      const SizedBox(height: 15),
                      _buildRegisterInput(controller: emailCtrl, label: 'อีเมล', icon: Icons.email_outlined),
                      const SizedBox(height: 15),
                      // 🌟 ส่วนที่แก้ไข: ช่องกรอกรหัสผ่าน + คำนวณความปลอดภัยแบบ Real-time
                      _buildRegisterInput(
                        controller: passwordCtrl, 
                        label: 'กำหนดรหัสผ่าน', 
                        icon: Icons.lock_outline, 
                        isPassword: true,
                        onChanged: (value) {
                          // คำนวณคะแนนรหัสผ่าน
                          double strength = 0;
                          if (value.isNotEmpty) {
                            if (value.length >= 8) strength += 0.25; // 1. ยาว 8 ตัวขึ้นไป
                            if (value.contains(RegExp(r'[A-Z]'))) strength += 0.25; // 2. มีพิมพ์ใหญ่
                            if (value.contains(RegExp(r'[a-z]'))) strength += 0.25; // 3. มีพิมพ์เล็ก
                            if (value.contains(RegExp(r'[0-9!@#\$&*~_]'))) strength += 0.25; // 4. มีตัวเลขหรืออักขระพิเศษ
                          }
                          // สั่งอัปเดตหน้าจอเฉพาะใน Dialog
                          setDialogState(() {
                            passwordStrength = strength;
                          });
                        }
                      ),
                      
                      // 🌟 หลอดสีแสดงความปลอดภัย (จะโชว์ก็ต่อเมื่อเริ่มพิมพ์)
                      if (passwordCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: LinearProgressIndicator(
                                  value: passwordStrength,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey.shade300,
                                  color: passwordStrength <= 0.25 ? Colors.redAccent 
                                       : passwordStrength <= 0.5 ? Colors.orange 
                                       : passwordStrength <= 0.75 ? Colors.amber.shade600 
                                       : const Color(0xFF1D9E75),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              passwordStrength <= 0.25 ? 'อ่อนแอ' 
                            : passwordStrength <= 0.5 ? 'พอใช้' 
                            : passwordStrength <= 0.75 ? 'ดี' 
                            : 'ปลอดภัยมาก',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: passwordStrength <= 0.25 ? Colors.redAccent 
                                     : passwordStrength <= 0.5 ? Colors.orange 
                                     : passwordStrength <= 0.75 ? Colors.amber.shade700 
                                     : const Color(0xFF1D9E75),
                              ),
                            )
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      // 🌟 คำแนะนำการตั้งรหัสผ่าน
                      const Text(
                        '💡 รหัสผ่านควรมีอย่างน้อย 8 ตัว ประกอบด้วยอักษรพิมพ์เล็ก พิมพ์ใหญ่ และตัวเลข/อักขระพิเศษ',
                        style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.3),
                      ),
                      const SizedBox(height: 15),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(color: Colors.black26),
                      ),
                      
                      // 🌟 ข้อมูลพื้นที่ปฏิบัติงาน
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ข้อมูลพื้นที่ปฏิบัติงาน (อสม.)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1D9E75)),
                        ),
                      ),
                      const SizedBox(height: 15),
                      
                      _buildRegisterInput(controller: hospitalCtrl, label: 'สังกัด รพ.สต. / โรงพยาบาล', icon: Icons.local_hospital_outlined),
                      const SizedBox(height: 15),
                      
                      Row(
                        children: [
                          Expanded(child: _buildRegisterInput(controller: regionCtrl, label: 'เขตสุขภาพที่', icon: Icons.map_outlined, isNumber: true)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildRegisterInput(controller: provinceCtrl, label: 'จังหวัด', icon: Icons.location_city_outlined)),
                        ],
                      ),
                      const SizedBox(height: 15),
                      
                      Row(
                        children: [
                          Expanded(child: _buildRegisterInput(controller: districtCtrl, label: 'อำเภอ', icon: Icons.map)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildRegisterInput(controller: subdistrictCtrl, label: 'ตำบล', icon: Icons.pin_drop_outlined)),
                        ],
                      ),
                      const SizedBox(height: 30),

                      // 🌟 ส่วน Checkbox ยินยอมข้อตกลง
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: isAgreed,
                              activeColor: const Color(0xFF1D9E75),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (value) {
                                setDialogState(() => isAgreed = value ?? false);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: 'ฉันได้อ่านและยอมรับ ',
                                style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                                children: [
                                  TextSpan(
                                    text: 'นโยบายความเป็นส่วนตัว (Privacy Policy)',
                                    style: const TextStyle(color: Color(0xFF1D9E75), fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                    
                                    // 🌟 3. เพิ่มการดักจับการคลิกตรงนี้!
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              title: const Row(
                                                children: [
                                                  Icon(Icons.privacy_tip, color: Color(0xFF1D9E75)),
                                                  SizedBox(width: 8),
                                                  Expanded(child: Text('นโยบายความเป็นส่วนตัว', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                                                ],
                                              ),
                                              content: const SingleChildScrollView(
                                                child: Text(privacyPolicyText, style: TextStyle(fontSize: 13, height: 1.5)),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(context).pop(),
                                                  child: const Text('ปิดหน้าต่าง', style: TextStyle(color: Color(0xFF1D9E75), fontWeight: FontWeight.bold)),
                                                ),
                                              ],
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            );
                                          },
                                        );
                                      },
                                  ),
                                  const TextSpan(
                                    text: ' และยินยอมให้ระบบประมวลผลข้อมูลส่วนบุคคลตาม พ.ร.บ. คุ้มครองข้อมูลส่วนบุคคล (PDPA)',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),

                      // ปุ่มกด
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: isRegistering ? null : () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: const Text('ยกเลิก', style: TextStyle(color: Colors.black54, fontSize: 16)),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isRegistering
                                  ? null
                                  : () async {
                                      // 🌟 1. ดึงค่าจากช่องกรอกทั้งหมด (พร้อมแปลงอีเมลเป็นตัวพิมพ์เล็ก)
                                      final username = usernameCtrl.text.trim();
                                      final name = nameCtrl.text.trim();
                                      final email = emailCtrl.text.trim().toLowerCase(); // บังคับตัวเล็ก แก้ปัญหาพิมพ์ .Com
                                      final password = passwordCtrl.text;
                                      final hospital = hospitalCtrl.text.trim();
                                      final region = regionCtrl.text.trim();
                                      final province = provinceCtrl.text.trim();
                                      final district = districtCtrl.text.trim();
                                      final subdistrict = subdistrictCtrl.text.trim();

                                      // 🌟 2. เช็คว่ากรอกข้อมูล "ครบทุกช่อง" หรือไม่
                                      if (username.isEmpty || name.isEmpty || email.isEmpty || password.isEmpty || 
                                          hospital.isEmpty || region.isEmpty || province.isEmpty || district.isEmpty || subdistrict.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ กรุณากรอกข้อมูลให้ครบทุกช่อง'), backgroundColor: Colors.redAccent));
                                        return;
                                      }

                                      // 🌟 3. เช็คความถูกต้องของเลขบัตร ปชช. (ต้อง 13 หลัก)
                                      if (username.length != 13) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ เลขประจำตัวประชาชนต้องครบ 13 หลัก'), backgroundColor: Colors.redAccent));
                                        return;
                                      }

                                      // 🌟 4. เช็คความถูกต้องของอีเมลด้วย RegEx (ต้องมี @ และ .)
                                      final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                                      if (!emailRegex.hasMatch(email)) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ รูปแบบอีเมลไม่ถูกต้อง (เช่น ลืมพิมพ์ .com)'), backgroundColor: Colors.redAccent));
                                        return;
                                      }

                                      // 🌟 5. เช็ครหัสผ่านขั้นต่ำ
                                      if (password.length < 8) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร'), backgroundColor: Colors.redAccent));
                                        return;
                                      }

                                      // 🌟 6. เช็คการกดยอมรับ PDPA
                                      if (!isAgreed) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ กรุณากดยอมรับนโยบายความเป็นส่วนตัวก่อนสมัครสมาชิก'), backgroundColor: Colors.redAccent));
                                        return; // หยุดการทำงาน
                                      }

                                      setDialogState(() => isRegistering = true);
                                      try {
                                        // 🌟 ส่งข้อมูลให้ฟังก์ชันครบทุกตัว (ใช้อีเมลที่จัดฟอร์แมตแล้ว)
                                        await registerUser(
                                          username: username,
                                          email: email,
                                          password: password,
                                          nameTh: name,
                                          hospital: hospital,
                                          healthRegion: region,
                                          province: province,
                                          district: district,
                                          subdistrict: subdistrict,
                                        );
                                        
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('✅ สมัครสมาชิกสำเร็จ โปรดเข้าสู่ระบบ'),
                                              backgroundColor: Color(0xFF1D9E75),
                                            ),
                                          );
                                        }
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('❌ ${error.toString().replaceFirst('Exception: ', '')}'),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
                                        }
                                      } finally {
                                        if (context.mounted) {
                                          setDialogState(() => isRegistering = false);
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1D9E75),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: isRegistering
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('ยืนยันสมัคร', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        ),
      ),
    );
  }

  // 🌟 Helper ฟังก์ชันสำหรับสร้างช่องกรอกข้อมูลในหน้าสมัครสมาชิกให้สวยงาม
  Widget _buildRegisterInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isNumber = false,
    int? limit,
    void Function(String)? onChanged, // 🌟 1. เพิ่มบรรทัดนี้
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLength: limit,
      onChanged: onChanged, // 🌟 2. เพิ่มบรรทัดนี้เพื่อส่งค่าเวลามีการพิมพ์
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14, color: Colors.black54),
        prefixIcon: Icon(icon, color: const Color(0xFF1D9E75), size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.5),
        counterText: "",
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF1D9E75), width: 1.5),
        ),
      ),
    );
  }
}

// ─── Main Screen (Bottom Navigation) ───────────────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  // 🌟 แก้ไข: สร้างฟังก์ชันช่วยสลับหน้าจอแทนการฝังลิสต์สเตตค้างไว้
  // ทุกครั้งที่สลับแท็บ ฟังก์ชันดึงข้อมูลพิกัด ประวัติ และ Dashboard จะถูกรันใหม่ทันทีเรียลไทม์
  Widget _getScreen(int index) {
    switch (index) {
      case 0: return const HomeScreen();
      case 1: return const ReportPatientScreen();
      case 2: return const MapScreen(); 
      case 3: return const ProfileScreen();
      default: return const HomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _getScreen(_tab), // 🌟 เปลี่ยนมาเรียกใช้งานผ่านฟังก์ชันแทนตัวแปรเดิม
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'หน้าหลัก'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'รายงานโรค'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'แผนที่'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'โปรไฟล์'),
        ],
      ),
    );
  }
}

// ─── 1. Home Screen ─────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentArea = 'กำลังค้นหาตำแหน่งปัจจุบัน...';
  //String? _assignedArea; // 🌟 1. เพิ่มตัวแปรใหม่เก็บพื้นที่รับผิดชอบจริง
  //String? _base64Image; 

  // 🌟 1. เพิ่มตัวแปรเก็บ Future 2 ตัวนี้เข้ามาครับ
  late Future<HomeSummary> _summaryFuture;
  late Future<List<AlertItem>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    // 🌟 2. สั่งดึงข้อมูล API แค่ "ครั้งเดียว" ตอนเริ่มโหลดหน้าจอ
    _summaryFuture = fetchDashboardSummary();
    _alertsFuture = fetchAlerts();
    _fetchCurrentLocation(); 
    // _loadProfileImage(); 
  }

  /*Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _base64Image = prefs.getString('profile_image_path');
      });
    }
  }*/

  Future<void> _fetchCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _currentArea = 'กรุณาเปิด GPS ในอุปกรณ์');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _currentArea = 'ไม่ได้รับอนุญาตให้เข้าถึง GPS');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _currentArea = 'กรุณาอนุญาต GPS ในตั้งค่าระบบ');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${pos.latitude}&lon=${pos.longitude}&accept-language=th');
      final response = await http.get(url, headers: {'User-Agent': 'GeoHealthTrackerApp'});
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        
        if (address != null && mounted) {
          String province = address['province'] ?? address['state'] ?? address['city'] ?? address['region'] ?? 'ไม่ระบุจังหวัด';
          String amphoe = address['district'] ?? address['city_district'] ?? address['county'] ?? 'ไม่ระบุอำเภอ';
          String tambon = address['suburb'] ?? address['town'] ?? address['village'] ?? address['quarter'] ?? 'ไม่ระบุตำบล';

          province = province.replaceAll('จังหวัด', '').trim();
          amphoe = amphoe.replaceAll('อำเภอ', '').replaceAll('เขต', '').trim();
          tambon = tambon.replaceAll('ตำบล', '').replaceAll('แขวง', '').trim();

          String displayAddress;
          if (province.contains('กรุงเทพ') || province.toLowerCase() == 'bangkok') {
            displayAddress = 'แขวง$tambon เขต$amphoe กรุงเทพมหานคร';
          } else {
            displayAddress = 'ต.$tambon อ.$amphoe จ.$province';
          }

          setState(() {
            _currentArea = 'พิกัดปัจจุบัน: $displayAddress';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _currentArea = 'พิกัดปัจจุบัน: ไม่สามารถระบุได้');
    }
  }

  Future<String?> _getLatestProfileImage() async {
    final user = await AuthStorage.getUser();
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('profile_base64_${user['id']}');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('หน้าหลัก'),
        elevation: 0,
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Text('ออกจากระบบ'),
                onTap: () async {
                  await logoutUser();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacementNamed('/login');
                  }
                },
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<HomeSummary>(
          //future: fetchDashboardSummary(),
          future: _summaryFuture,
          builder: (context, snapshot) {
            
            // 🌟 สร้างวิดเจ็ตแสดงเขตรับผิดชอบโดยเชื่อมข้อมูลจากตารางผู้ใช้งาน
            Widget buildAreaName() {
              return FutureBuilder<Map<String, dynamic>?>(
                future: AuthStorage.getUser(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.hasData && userSnapshot.data != null) {
                    final u = userSnapshot.data!;
                    // เช็คว่ามีข้อมูลพื้นที่ที่กรอกตอนสมัครไหม
                    if (u['hospital'] != null && u['hospital'].toString().isNotEmpty) {
                      String r = u['health_region'] != null ? 'เขตสุขภาพที่ ${u['health_region']} ' : '';
                      return Text(
                        '${u['hospital']} (ต.${u['subdistrict']} อ.${u['district']} จ.${u['province']})\n$r',
                        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      );
                    }
                  }
                  // 🔄 Fallback: หากเป็นคนเก่าที่ไม่มีข้อมูลเขต ให้ใช้พิกัด GPS ปัจจุบันแทนชั่วคราว
                  return Text(
                    _currentArea, 
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              );
            }

            Widget summaryCard;
            if (snapshot.connectionState == ConnectionState.waiting) {
              summaryCard = Container(
                width: double.infinity, padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: const Center(child: CircularProgressIndicator(color: Color(0xFF1D9E75))),
              );
            } else if (snapshot.hasError) {
              // 🌟 เปลี่ยน Error สีแดงน่ากลัว ให้เป็น UI ที่ดูเป็นมิตรและเข้าใจง่าย
              summaryCard = Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50, // พื้นหลังสีแดงอ่อนๆ ดูนุ่มนวล
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'ไม่สามารถเชื่อมต่อฐานข้อมูลได้',
                      style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'ระบบเซิร์ฟเวอร์อาจกำลังปรับปรุงหรือขัดข้องชั่วคราว\nกรุณารอสักครู่แล้วกดปุ่มลองใหม่อีกครั้งครับ',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // 🌟 กดปุ่มแล้วสั่งให้ดึงข้อมูลใหม่ทันที
                          setState(() {
                            _summaryFuture = fetchDashboardSummary();
                            _alertsFuture = fetchAlerts();
                          });
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('ลองโหลดข้อมูลใหม่', style: TextStyle(fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              final summary = snapshot.data!;
              summaryCard = Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D9E75), Color(0xFF0F6E56)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('พื้นที่รับผิดชอบปฏิบัติงาน', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    buildAreaName(), // 🌟 เรียกใช้วังก์ชันแสดงชื่อเขตจริงที่นี่
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _StatBadge(label: 'รายใหม่วันนี้', value: summary.newToday.toString()),
                        const SizedBox(width: 12),
                        _StatBadge(label: 'ทั้งหมดเดือนนี้', value: summary.totalThisMonth.toString()),
                        const SizedBox(width: 12),
                        _StatBadge(label: 'กลุ่มเปราะบาง', value: summary.vulnerableTotal.toString()),
                      ],
                    ),
                  ],
                ),
              );
            }

            // โค้ดส่วนเมนูลัด และรายการแจ้งเตือนด้านล่างยังคงเหมือนเดิมทั้งหมด...
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FutureBuilder<String?>(
                        future: _getLatestProfileImage(),
                        builder: (context, snapshot) {
                          final base64String = snapshot.data;
                          return Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                            child: base64String != null && base64String.isNotEmpty
                                ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(base64String), fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Icon(Icons.person, color: Colors.grey.shade600)))
                                : Icon(Icons.person, color: Colors.grey.shade600, size: 28),
                          );
                        }
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FutureBuilder<Map<String, dynamic>?>(
                          future: AuthStorage.getUser(),
                          builder: (context, userSnapshot) {
                            String userName = 'กำลังโหลด...'; 
                            if (userSnapshot.hasData && userSnapshot.data != null) {
                              userName = userSnapshot.data!['name_th'] ?? 'ไม่ระบุชื่อ';
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('สวัสดีครับ', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                Text(userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            );
                          }
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertScreen()));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  summaryCard,
                  const SizedBox(height: 20),
                  const Text('เมนูลัด', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.4,
                    children: [
                      _QuickAction(icon: Icons.add_circle, label: 'รายงานผู้ป่วยใหม่', color: const Color(0xFFE24B4A), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPatientScreen()))),
                      //_QuickAction(icon: Icons.person_search, label: 'กลุ่มเปราะบาง', color: const Color(0xFFBA7517), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportVulnerableScreen()))),
                      _QuickAction(icon: Icons.map, label: 'ดูแผนที่โรค', color: const Color(0xFF185FA5), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen()))),
                      _QuickAction(icon: Icons.history, label: 'ประวัติการรายงาน', color: const Color(0xFF639922), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportHistoryScreen()))),
                      _QuickAction(icon: Icons.add_location_alt, label: 'ปักหมุดสถานที่ชุมชน', color: Colors.deepPurple, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPlaceScreen()))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('การแจ้งเตือนล่าสุด', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  FutureBuilder<List<AlertItem>>(
                    //future: fetchAlerts(),
                    future: _alertsFuture,
                    builder: (context, alertSnapshot) {
                      if (alertSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1D9E75)));
                      final alerts = alertSnapshot.data ?? [];
                      if (alerts.isEmpty) {
                        return Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)), child: const Text('ยังไม่มีการแจ้งเตือนใหม่', style: TextStyle(fontSize: 13, color: Colors.grey)));
                      }
                      final latestAlert = alerts.first;
                      final timeStr = '${latestAlert.sentAt.toLocal().hour.toString().padLeft(2, '0')}:${latestAlert.sentAt.toLocal().minute.toString().padLeft(2, '0')} น.';
                      final color = latestAlert.status == 'sent' ? const Color(0xFF1D9E75) : const Color(0xFFBA7517);
                      return Container(
                        padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.notifications_active, color: color, size: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('แจ้งเตือนระบบ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey))]),
                                  const SizedBox(height: 4),
                                  Text(latestAlert.message, style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  const _StatBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ],
  );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── 2. Report Patient Screen (Multi-Form Tab View) ───────────────────────────────────────────────

class ReportPatientScreen extends StatefulWidget {
  const ReportPatientScreen({super.key});

  @override
  State<ReportPatientScreen> createState() => _ReportPatientScreenState();
}

class _ReportPatientScreenState extends State<ReportPatientScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // --- ตัวแปรสำหรับฟอร์มรวม (ใช้ร่วมกัน) ---
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  final _ageCtrl = TextEditingController();
  final _occupationCtrl = TextEditingController();
  final _nationalityCtrl = TextEditingController();
  String _selectedGender = 'ชาย';
  
  double? _lat, _lng;
  String _gpsStatus = 'ยังไม่ได้ระบุพิกัด';
  bool _gpsLoading = false;
  Map<String, String> _addressData = {};

  // --- ตัวแปรสำหรับฟอร์ม: โรคติดต่อ (Tab 1) ---
  final _formKeyInfectious = GlobalKey<FormState>();
  Disease? _selectedDisease;
  String _severity = 'mild';
  DateTime? _onsetDate;
  DateTime? _dateOfDeath;
  String _surveillanceDays = 'ไม่ต้องเฝ้าระวัง'; // 🌟 ระยะเวลาเฝ้าระวังใหม่

  // --- ตัวแปรสำหรับฟอร์ม: คัดกรองสุขภาพจิต (Tab 2) ---
  final _formKeyMentalScreening = GlobalKey<FormState>();
  String _mentalTargetGroup = 'ประชาชนทั่วไป (15-60 ปี)';
  String _mentalRiskLevel = 'กลุ่มปกติ';
  bool _isRiskForFollowUp = false; // ถ้าเสี่ยงให้ไปติดตาม

  // 🌟 เพิ่มตัวแปรเก็บคำตอบ SMI V-SCAN
  String _smiSleep = 'ไม่มี';
  String _smiPace = 'ไม่มี';
  String _smiTalk = 'ไม่มี';
  String _smiIrritable = 'ไม่มี';
  String _smiParanoia = 'ไม่มี';
  String _smiHistory = 'ไม่มี';
  String _smiHistoryDetail = 'ประวัติทางจิตเวช';

  // 🌟 เพิ่มตัวแปรเก็บคำตอบ OAS
  String _oasSelf = 'ไม่พบพฤติกรรมก้าวร้าวรุนแรงต่อตนเอง';
  String _oasOthers = 'ไม่พบพฤติกรรมก้าวร้าว';
  String _oasProperty = 'ไม่พบพฤติกรรม';
  final _oasAssessorCtrl = TextEditingController();

  // --- ตัวแปรสำหรับฟอร์ม: ผู้ป่วยจิตเวช (Tab 3) ---
  final _formKeyPsychiatric = GlobalKey<FormState>();
  String _psychiatricGroup = 'F20-F29 โรคจิตเภท/หลงผิด';
  String _psychiatricFollowUpStatus = 'ติดตามได้';

  bool _loading = false;

  // --- ตัวแปรสำหรับฟอร์ม: NCDs / กลุ่มเปราะบาง (Tab 4) ---
  final _formKeyVulnerable = GlobalKey<FormState>();
  
  // 1. ตัวแปรกลุ่มเปราะบาง
  String _vulnerableSelectedType = 'ไม่ระบุ';
  final List<String> _vulnerableTypes = ['ไม่ระบุ', 'ผู้สูงอายุ', 'ผู้ป่วยติดเตียง', 'คนพิการ', 'หญิงตั้งครรภ์', 'เด็กทารก'];
  
  // 2. ตัวแปรโรค NCDs
  List<String> _selectedNcds = [];
  final List<String> _ncdTypes = [
    'ไม่มี/ไม่ระบุ', 
    'เบาหวาน (Diabetes)', 
    'ความดันโลหิตสูง (Hypertension)', 
    'โรคหลอดเลือดหัวใจ (CVD)', 
    'โรคหลอดเลือดสมอง (Stroke)', 
    'โรคไตเรื้อรัง (CKD)', 
    'ถุงลมโป่งพอง/หอบหืด (COPD)',
    'โรคมะเร็ง (Cancer)',
    'โรคอ้วนลงพุง (Obesity)',
    'อื่นๆ'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _ageCtrl.dispose();
    _occupationCtrl.dispose();
    _nationalityCtrl.dispose();
    _oasAssessorCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _getAddress(double lat, double lng) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=th');
      final response = await http.get(url, headers: {'User-Agent': 'GeoHealthTrackerApp'});
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        
        if (address != null && mounted) {
          String province = address['province'] ?? address['state'] ?? address['city'] ?? address['region'] ?? 'ไม่ระบุจังหวัด';
          String amphoe = address['district'] ?? address['city_district'] ?? address['county'] ?? 'ไม่ระบุอำเภอ';
          String tambon = address['suburb'] ?? address['town'] ?? address['village'] ?? address['quarter'] ?? 'ไม่ระบุตำบล';
          String village = address['neighbourhood'] ?? address['hamlet'] ?? address['allotment'] ?? '';

          province = province.replaceAll('จังหวัด', '').trim();
          amphoe = amphoe.replaceAll('อำเภอ', '').replaceAll('เขต', '').trim();
          tambon = tambon.replaceAll('ตำบล', '').replaceAll('แขวง', '').trim();
          village = village.replaceAll('หมู่บ้าน', '').replaceAll('บ้าน', '').trim();

          String displayAddress = '';
          if (province.contains('กรุงเทพ') || province.toLowerCase() == 'bangkok') {
            province = 'กรุงเทพมหานคร';
            displayAddress = 'แขวง$tambon เขต$amphoe $province';
            if (village.isNotEmpty && village != tambon && village != amphoe) {
              displayAddress = '$village $displayAddress';
            }
          } else {
            displayAddress = 'ต.$tambon อ.$amphoe จ.$province';
            if (village.isNotEmpty && village != tambon && village != amphoe) {
              displayAddress = 'บ้าน$village $displayAddress';
            }
          }

          setState(() {
            _addressData = {
              'village': village.isNotEmpty ? village : tambon,
              'tambon': tambon,
              'amphoe': amphoe,
              'province': province,
            };
            _gpsStatus = displayAddress; 
          });
        }
      }
    } catch (e) {
      debugPrint('Address Error: $e');
    }
  }

  Future<void> _getGPS() async {
    setState(() {
      _gpsLoading = true;
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _gpsLoading = false;
        _gpsStatus = 'เปิดการใช้งาน Location ในอุปกรณ์ก่อน';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _gpsLoading = false;
        _gpsStatus = 'ต้องให้สิทธิ์ตำแหน่งก่อนใช้งาน';
      });
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;

        _latCtrl.text = _lat.toString();
        _lngCtrl.text = _lng.toString();

        _gpsStatus = 'กำลังแปลงที่อยู่...';
      });
      await _getAddress(pos.latitude, pos.longitude);
    } catch (_) {
      setState(() {
        _gpsStatus = 'ไม่สามารถรับพิกัดได้ ลองเลือกตำแหน่งบนแผนที่';
      });
    } finally {
      setState(() {
        _gpsLoading = false;
      });
    }
  }

  Future<void> _openLocationPicker() async {
    final LatLng? location = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialPosition:
              _lat != null && _lng != null ? LatLng(_lat!, _lng!) : _defaultMapCenter,
        ),
      ),
    );
    if (location != null) {
      setState(() {
        _lat = location.latitude;
        _lng = location.longitude;

        _latCtrl.text = _lat.toString();
        _lngCtrl.text = _lng.toString();

        _gpsStatus = 'กำลังแปลงที่อยู่...';
      });
      await _getAddress(location.latitude, location.longitude);
    }
  }

  Future<void> _openDiseasePicker() async {
    final Disease? disease = await showModalBottomSheet<Disease>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        var searchFuture = searchDiseases('');

        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ค้นหาโรค',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ชื่อโรคหรือรหัสโรค',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchFuture = searchDiseases(value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: FutureBuilder<List<Disease>>(
                        future: searchFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final suggestions = snapshot.data ?? [];
                          if (suggestions.isEmpty) {
                            return const Center(child: Text('ไม่พบโรคที่ค้นหา'));
                          }
                          return ListView.separated(
                            itemCount: suggestions.length,
                            separatorBuilder: (context, index) => const Divider(height: 0),
                            itemBuilder: (context, index) {
                              final disease = suggestions[index];
                              return ListTile(
                                leading: Icon(
                                  disease.icon,
                                  color: disease.color,
                                ),
                                title: Text(disease.name),
                                subtitle: Text(
                                  disease.group.isNotEmpty
                                      ? 'รหัส ${disease.code} • ${disease.group}'
                                      : 'รหัส ${disease.code}',
                                ),
                                onTap: () => Navigator.pop(context, disease),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (disease != null) {
      setState(() {
        _selectedDisease = disease;
      });
    }
  }

  Future<void> _selectDate(BuildContext context, bool isOnset) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isOnset) {
          _onsetDate = picked;
        } else {
          _dateOfDeath = picked;
        }
      });
    }
  }

  // 🌟 ฟังก์ชัน Submit รวม (ประมวลผลแยกตาม Tab ที่เลือก)
  Future<void> _submit() async {
    final int currentTab = _tabController.index;
    
    // ตรวจสอบฟอร์มแยกตาม Tab
    if (currentTab == 0 && !_formKeyInfectious.currentState!.validate()) return;
    if (currentTab == 1 && !_formKeyMentalScreening.currentState!.validate()) return;
    if (currentTab == 2 && !_formKeyPsychiatric.currentState!.validate()) return;
    if (currentTab == 3 && !_formKeyVulnerable.currentState!.validate()) return;

    if (_nameCtrl.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกชื่อผู้ป่วย'))); return; }
    if (_lat == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณารับพิกัด GPS ก่อน'))); return; }
    if (currentTab == 0 && _selectedDisease == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาเลือกโรคติดต่อ'))); return; }

    setState(() => _loading = true);

    try {
      final addressPayload = { ..._addressData, 'house_number': _addressCtrl.text };
      final parsedAge = int.tryParse(_ageCtrl.text);
      final parsedNationality = _nationalityCtrl.text.isEmpty ? null : _nationalityCtrl.text;
      final parsedOccupation = _occupationCtrl.text.isEmpty ? null : _occupationCtrl.text;
      
      // 🌟 ดึง Token ของคนที่ล็อกอินอยู่
      final _ = await AuthStorage.getToken(); 
      // 🌟 ดึง Headers ที่มี Authorization พร้อม Token ไว้ใช้กับ http.post
      final headers = await _getAuthHeaders(); 

      if (currentTab == 0) {
        // --- แท็บ 1: ส่งข้อมูลโรคติดต่อ 506 ---
        // ⚠️ ต้องไปแก้ในฟังก์ชัน postPatient ให้รับค่า headers หรือ token เข้าไปด้วย
        await postPatient(
          name: _nameCtrl.text, diseaseCode: _selectedDisease!.code, lat: _lat!, lng: _lng!,
          addressData: addressPayload, severity: _severity,
          age: parsedAge, gender: _selectedGender, nationality: parsedNationality,
          occupation: parsedOccupation, onsetDate: _onsetDate, dateOfDeath: _dateOfDeath,
          // เพิ่มส่ง Token หรือ headers ไปถ้าฟังก์ชัน postPatient ต้องการ (ขึ้นอยู่กับว่าพี่เขียนรับไว้ยังไง)
        );
      } else if (currentTab == 1) {
        // --- แท็บ 2: ส่งข้อมูลคัดกรองสุขภาพจิต ---
        await postMentalScreening(
          name: _nameCtrl.text, lat: _lat!, lng: _lng!, addressData: addressPayload,
          age: parsedAge, gender: _selectedGender, nationality: parsedNationality, occupation: parsedOccupation,
          targetGroup: _mentalTargetGroup, riskLevel: _mentalRiskLevel,
          // 🌟 ส่งค่า SMI V-SCAN ที่เลือกไว้เข้าไป (ดักเงื่อนไขถ้าไม่มีประวัติ ให้ส่งค่าว่างไปแทน)
          smiSleep: _smiSleep,
          smiPace: _smiPace,
          smiTalk: _smiTalk,
          smiIrritable: _smiIrritable,
          smiParanoia: _smiParanoia,
          smiHistory: _smiHistory,
          smiHistoryDetail: _smiHistory == 'มี' ? _smiHistoryDetail : '',

          // 🌟 ส่งค่า OAS ไป
          oasSelf: _oasSelf,
          oasOthers: _oasOthers,
          oasProperty: _oasProperty,
          oasAssessor: _oasAssessorCtrl.text,
        );
      } else if (currentTab == 2) {
        // --- แท็บ 3: ส่งข้อมูลติดตามผู้ป่วยจิตเวช ---
        await postPsychiatricPatient(
          name: _nameCtrl.text, lat: _lat!, lng: _lng!, addressData: addressPayload,
          age: parsedAge, gender: _selectedGender, nationality: parsedNationality, occupation: parsedOccupation,
          psychiatricGroup: _psychiatricGroup, followUpStatus: _psychiatricFollowUpStatus,
        );
      } else if (currentTab == 3) {
        // --- แท็บ 4: ส่งข้อมูลกลุ่มเปราะบาง / NCDs ---
        
        List<String> combinedTypes = [];
        if (_vulnerableSelectedType != 'ไม่ระบุ') {
          combinedTypes.add(_vulnerableSelectedType);
        }
        
        // ตรงนี้มีเงื่อนไขซ้ำซ้อนกัน ผมขอรวมให้เหลืออันเดียวนะครับ
        if (_selectedNcds.isNotEmpty) {
          combinedTypes.add('NCDs (${_selectedNcds.join(", ")})');
        }
        
        if (combinedTypes.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาระบุกลุ่มเปราะบาง หรือ โรค NCDs อย่างน้อย 1 อย่าง')));
          setState(() => _loading = false);
          return;
        }

        final finalType = combinedTypes.join(', ');
        final fullAddress = '${_addressCtrl.text} $_gpsStatus'.trim();
        
        // 🌟 แท็บ 4 นี้ใช้ http.post ตรงๆ เราก็ยัด headers ที่มี Token ลงไปเลย
        final response = await http.post(
          Uri.parse('$kApiBase/vulnerable'),
          headers: headers, // 👈 ตรงนี้คือจุดที่แนบ Token ไปให้ Backend ครับ
          body: jsonEncode({
            'name': _nameCtrl.text,
            'type': finalType, 
            'lat': _lat,
            'lng': _lng,
            'address': fullAddress, 
          }),
        );
        if (response.statusCode >= 400) throw Exception('ไม่สามารถบันทึกข้อมูลได้');
      }
    } catch (error) {
      if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
      return;
    }

    if (mounted) {
      setState(() => _loading = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [Icon(Icons.check_circle, color: Color(0xFF1D9E75)), SizedBox(width: 8), Text('บันทึกสำเร็จ')]),
          content: Text('บันทึกข้อมูลของ ${_nameCtrl.text} เรียบร้อยแล้ว พร้อมส่งแจ้งเตือนเข้า LINE'),
          actions: [
            TextButton(
              onPressed: () { 
                Navigator.pop(context);
                
                setState(() {
                  _nameCtrl.clear();
                  _addressCtrl.clear();
                  _ageCtrl.clear();
                  _occupationCtrl.clear();
                  _nationalityCtrl.clear();

                  _latCtrl.clear();
                  _lngCtrl.clear();

                  _lat = null;
                  _lng = null;
                  _gpsStatus = 'ยังไม่ได้ระบุพิกัด';
                  _selectedNcds.clear();
                  _oasAssessorCtrl.clear();
                });
              }, 
              child: const Text('ปิด')
            )
          ],
        ),
      );
    }
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint, filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      prefixIcon: Icon(icon, color: const Color(0xFF1D9E75)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  // 🌟 ฟังก์ชันสร้างคำถามแบบ มี/ไม่มี 
  Widget _buildSmiQuestion(String title, String value, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4)),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('มี', style: TextStyle(fontSize: 14)),
                  value: 'มี',
                  groupValue: value,
                  onChanged: onChanged,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: const Color(0xFF1D9E75),
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('ไม่มี', style: TextStyle(fontSize: 14)),
                  value: 'ไม่มี',
                  groupValue: value,
                  onChanged: onChanged,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: const Color(0xFF1D9E75),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🌟 ฟังก์ชันสร้างคำถาม OAS แบบ Dropdown
  Widget _buildOasDropdown(String title, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: value,
            items: items.map((t) => DropdownMenuItem(value: t, child: Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: onChanged,
            decoration: _buildInputDecoration('', Icons.warning_amber_rounded),
          ),
        ],
      ),
    );
  }

  // --- Widget สร้างฟอร์มข้อมูลส่วนตัวและ GPS (ใช้ร่วมกันทุก Tab) ---
  Widget _buildCommonForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ข้อมูลส่วนบุคคล', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1D9E75))),
        const Divider(),
        const SizedBox(height: 10),
        
        TextFormField(controller: _nameCtrl, decoration: _buildInputDecoration('ชื่อ-นามสกุล', Icons.person_outline)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextFormField(controller: _ageCtrl, keyboardType: TextInputType.number, decoration: _buildInputDecoration('อายุ (ปี)', Icons.cake_outlined))),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedGender, decoration: _buildInputDecoration('', Icons.wc),
                items: ['ชาย', 'หญิง'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => _selectedGender = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextFormField(controller: _nationalityCtrl, decoration: _buildInputDecoration('สัญชาติ', Icons.flag_outlined))),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _occupationCtrl, decoration: _buildInputDecoration('อาชีพ', Icons.work_outline))),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _addressCtrl, decoration: _buildInputDecoration('เลขที่บ้าน/ที่อยู่รายละเอียด', Icons.home_outlined)),
        const SizedBox(height: 16),

        const Text('พิกัด GPS (ดึงจากตำแหน่งปัจจุบัน, แผนที่ หรือกรอกเอง)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),

        // 🌟 เพิ่มช่องให้พิมพ์ / วางตัวเลขพิกัดเองได้
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _latCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _buildInputDecoration('ละติจูด (Lat)', Icons.explore_outlined),
                onChanged: (v) {
                  _lat = double.tryParse(v);
                  if (_lat != null && _lng != null) setState(() => _gpsStatus = 'พิกัดจากการกรอก (กรุณากดแปลงที่อยู่)');
                },
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: TextFormField(
                controller: _lngCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _buildInputDecoration('ลองจิจูด (Lng)', Icons.explore_outlined),
                onChanged: (v) {
                  _lng = double.tryParse(v);
                  if (_lat != null && _lng != null) setState(() => _gpsStatus = 'พิกัดจากการกรอก (กรุณากดแปลงที่อยู่)');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(_lat != null ? Icons.location_on : Icons.location_off, color: _lat != null ? const Color(0xFF1D9E75) : Colors.grey), 
                  const SizedBox(width: 8), 
                  Expanded(child: Text(_gpsStatus, style: const TextStyle(fontSize: 13))),
                  
                  // 🌟 เพิ่มปุ่ม "แปลงที่อยู่" เพื่อให้แอปดึงข้อมูล ตำบล/อำเภอ จากตัวเลขที่พิมพ์
                  if (_lat != null && _lng != null)
                    TextButton(
                      onPressed: () {
                        setState(() => _gpsStatus = 'กำลังแปลงที่อยู่...');
                        _getAddress(_lat!, _lng!);
                      },
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30)),
                      child: const Text('แปลงที่อยู่'),
                    ),
                ]
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _gpsLoading ? null : _openLocationPicker, icon: const Icon(Icons.map, size: 18), label: const Text('แผนที่', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton.icon(onPressed: _gpsLoading ? null : _getGPS, icon: _gpsLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.my_location, size: 18), label: Text(_gpsLoading ? 'กำลังรับ...' : 'รับพิกัด', style: const TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D9E75), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // --- Tab 1: โรคติดต่อ ---
  Widget _buildInfectiousTab() {
    return Form(
      key: _formKeyInfectious,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCommonForm(),
          const Text('ข้อมูลโรคติดต่อ (รง. 506)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1D9E75))),
          const Divider(),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _openDiseasePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
              child: Row(children: [Icon(_selectedDisease?.icon ?? Icons.search, color: _selectedDisease?.color ?? const Color(0xFF1D9E75), size: 20), const SizedBox(width: 10), Expanded(child: Text(_selectedDisease?.name ?? 'เลือกโรค 506', style: TextStyle(color: _selectedDisease == null ? Colors.grey.shade600 : Colors.black))), const Icon(Icons.arrow_drop_down, color: Colors.grey)]),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: InkWell(onTap: () => _selectDate(context, true), child: InputDecorator(decoration: _buildInputDecoration('เริ่มป่วย', Icons.calendar_today), child: Text(_onsetDate != null ? '${_onsetDate!.day}/${_onsetDate!.month}/${_onsetDate!.year + 543}' : 'เริ่มป่วย', style: TextStyle(color: _onsetDate != null ? Colors.black : Colors.grey))))),
              const SizedBox(width: 12),
              Expanded(child: InkWell(onTap: () => _selectDate(context, false), child: InputDecorator(decoration: _buildInputDecoration('เสียชีวิต', Icons.calendar_today_outlined), child: Text(_dateOfDeath != null ? '${_dateOfDeath!.day}/${_dateOfDeath!.month}/${_dateOfDeath!.year + 543}' : 'เสียชีวิต (ถ้ามี)', style: TextStyle(color: _dateOfDeath != null ? Colors.black : Colors.grey))))),
            ],
          ),
          const SizedBox(height: 16),
          const Text('การเฝ้าระวังโรค (Quarantine)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _surveillanceDays, decoration: _buildInputDecoration('', Icons.timer_outlined),
            items: ['ไม่ต้องเฝ้าระวัง', 'เฝ้าระวัง 7 วัน', 'เฝ้าระวัง 14 วัน', 'เฝ้าระวัง 28 วัน'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _surveillanceDays = v!),
          ),
          const SizedBox(height: 16),
          const Text('ความรุนแรง', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            children: [
              _SeverityChip(label: 'เล็กน้อย', value: 'mild', selected: _severity, color: const Color(0xFF639922), onTap: (v) => setState(() => _severity = v)),
              const SizedBox(width: 8),
              _SeverityChip(label: 'ปานกลาง', value: 'moderate', selected: _severity, color: const Color(0xFFBA7517), onTap: (v) => setState(() => _severity = v)),
              const SizedBox(width: 8),
              _SeverityChip(label: 'รุนแรง', value: 'severe', selected: _severity, color: const Color(0xFFE24B4A), onTap: (v) => setState(() => _severity = v)),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- Tab 2: คัดกรองสุขภาพจิต ---
  Widget _buildMentalScreeningTab() {
    return Form(
      key: _formKeyMentalScreening,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCommonForm(),
          const Text('แบบคัดกรองสุขภาพจิตเชิงรุก', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1D9E75))),
          const Divider(),
          const SizedBox(height: 10),
          const Text('เป้าหมายการประเมิน', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _mentalTargetGroup, isExpanded: true, decoration: _buildInputDecoration('', Icons.group_outlined),
            items: [
              'ประชาชนทั่วไป (15-60 ปี)',
              'ผู้มีความเครียด/วิตกกังวล',
              'ผู้ที่มีประวัติใช้สารเสพติด',
              'ผู้ที่มีพฤติกรรมก้าวร้าวรุนแรง',
              'ผู้มีความเสี่ยงทำร้ายตนเอง/ผู้อื่น',
              'ผู้ที่เคยรักษาทางจิตเวช'
            ].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _mentalTargetGroup = v!),
          ),
          const SizedBox(height: 16),

          // 🌟 แทรกส่วนคำถาม SMI V-SCAN ตรงนี้ 🌟
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.assignment_turned_in, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('คัดกรอง SMI V-SCAN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSmiQuestion('1. ไม่หลับไม่นอน - มีปัญหาการนอน นอนไม่หลับ ไม่ยอมนอน หลับ ๆ ตื่น ๆ *', _smiSleep, (v) => setState(() => _smiSleep = v!)),
                _buildSmiQuestion('2. เดินไปเดินมา - ผุดลุกผุดนั่ง นั่งไม่ติด เดินไปเดินมา มีพฤติกรรมแปลก ๆ *', _smiPace, (v) => setState(() => _smiPace = v!)),
                _buildSmiQuestion('3. พูดจาคนเดียว - พูด ยิ้ม หัวเราะคนเดียว *', _smiTalk, (v) => setState(() => _smiTalk = v!)),
                _buildSmiQuestion('4. หงุดหงิดฉุนเฉียว - อารมณ์แปรปรวน เดี๋ยวดีเดี๋ยวร้าย หงุดหงิดง่าย ฉุนเฉียว *', _smiIrritable, (v) => setState(() => _smiIrritable = v!)),
                _buildSmiQuestion('5. เที่ยวหวาดระแวง - มีอาการหวาดระแวง คิดว่าคนไม่หวังดี นินทาว่าร้าย มีคนคอยติดตาม *', _smiParanoia, (v) => setState(() => _smiParanoia = v!)),
                _buildSmiQuestion('6. มีประวัติด้านจิตเวชหรือไม่ *', _smiHistory, (v) => setState(() => _smiHistory = v!)),
                
                // หากตอบว่า "มี" ให้แสดงตัวเลือกย่อยขึ้นมา
                if (_smiHistory == 'มี') ...[
                  const Padding(
                    padding: EdgeInsets.only(left: 16, bottom: 4),
                    child: Text('ระบุรายละเอียดประวัติ:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 12),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('ประวัติทางจิตเวช', style: TextStyle(fontSize: 14)),
                          value: 'ประวัติทางจิตเวช',
                          groupValue: _smiHistoryDetail,
                          onChanged: (v) => setState(() => _smiHistoryDetail = v!),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: Colors.redAccent,
                        ),
                        RadioListTile<String>(
                          title: const Text('ประวัติการใช้สารเสพติด', style: TextStyle(fontSize: 14)),
                          value: 'ประวัติการใช้สารเสพติด',
                          groupValue: _smiHistoryDetail,
                          onChanged: (v) => setState(() => _smiHistoryDetail = v!),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: Colors.redAccent,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 🌟 สิ้นสุดส่วน SMI V-SCAN 🌟

          // 🌟 แทรกส่วนคำถามแบบประเมิน OAS ตรงนี้ 🌟
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.report_problem_outlined, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text('แบบประเมินพฤติกรรม OAS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildOasDropdown(
                  'พฤติกรรมก้าวร้าวต่อตนเอง *',
                  _oasSelf,
                  [
                    'ไม่พบพฤติกรรมก้าวร้าวรุนแรงต่อตนเอง',
                    'เร่งด่วน : ขีดข่วนผิวหนัง ตีตนเอง ดึงผม โขกศีรษะ (2 คะแนน)',
                    'ฉุกเฉิน : ทำร้ายตนเองรุนแรง มีเลือดออก หรือหมดสติ (3 คะแนน)'
                  ],
                  (v) => setState(() => _oasSelf = v!),
                ),
                _buildOasDropdown(
                  'พฤติกรรมก้าวร้าวต่อผู้อื่น *',
                  _oasOthers,
                  [
                    'ไม่พบพฤติกรรมก้าวร้าว',
                    'กึ่งเร่งด่วน : ตะโกน ด่าด้วยคำไม่รุนแรง (1 คะแนน)',
                    'เร่งด่วน : ข่มขู่ แสดงท่าทางคุกคาม (2 คะแนน)',
                    'ฉุกเฉิน : ทำร้ายจนได้รับบาดเจ็บ (3 คะแนน)'
                  ],
                  (v) => setState(() => _oasOthers = v!),
                ),
                _buildOasDropdown(
                  'พฤติกรรมก้าวร้าวต่อทรัพย์สิน *',
                  _oasProperty,
                  [
                    'ไม่พบพฤติกรรม',
                    'กึ่งเร่งด่วน : ทำของกระจัดกระจาย (1 คะแนน)',
                    'เร่งด่วน : ทุบ เตะ ขว้างสิ่งของ (2 คะแนน)',
                    'ฉุกเฉิน : ทำลายทรัพย์สินหรือจุดไฟเผา (3 คะแนน)'
                  ],
                  (v) => setState(() => _oasProperty = v!),
                ),
                const Text('ผู้ประเมิน ชื่อ อสม. *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _oasAssessorCtrl,
                  decoration: _buildInputDecoration('กรอกชื่อผู้ประเมิน', Icons.person_outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 🌟 สิ้นสุดส่วน OAS 🌟

          const Text('ผลการประเมินความเสี่ยง', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _mentalRiskLevel, decoration: _buildInputDecoration('', Icons.analytics_outlined),
            items: ['กลุ่มปกติ', 'กลุ่มเสี่ยง', 'กลุ่มเฝ้าระวัง', 'กลุ่มต้องติดตามเร่งด่วน'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) {
              setState(() {
                _mentalRiskLevel = v!;
                _isRiskForFollowUp = (v != 'กลุ่มปกติ');
              });
            },
          ),
          if (_isRiskForFollowUp) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.redAccent)),
              child: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.redAccent), SizedBox(width: 8), Expanded(child: Text('⚠️ มีความเสี่ยง: โปรดนำเข้าสู่ระบบการติดตาม/รักษาทางจิตเวช (ในแท็บถัดไป)', style: TextStyle(color: Colors.redAccent, fontSize: 13)))]),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- Tab 3: ผู้ป่วยจิตเวช ---
  Widget _buildPsychiatricTab() {
    return Form(
      key: _formKeyPsychiatric,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCommonForm(),
          const Text('ติดตามผู้ป่วยจิตเวช (ในระบบรักษา)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1D9E75))),
          const Divider(),
          const SizedBox(height: 10),
          const Text('กลุ่มผู้ป่วย', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _psychiatricGroup, isExpanded: true, decoration: _buildInputDecoration('', Icons.psychology_outlined),
            items: [
              'F20-F29 โรคจิตเภท/หลงผิด',
              'F32-F39 โรคซึมเศร้า/อารมณ์',
              'F10-F19 ความผิดปกติจากสารเสพติด'
            ].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _psychiatricGroup = v!),
          ),
          const SizedBox(height: 16),
          const Text('สถานะการติดตาม (เยี่ยมบ้าน)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _psychiatricFollowUpStatus, decoration: _buildInputDecoration('', Icons.directions_walk_outlined),
            items: ['ติดตามได้', 'ติดตามไม่ได้/ไม่พบ', 'เสียชีวิต', 'ยุติการติดตาม'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _psychiatricFollowUpStatus = v!),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // --- Tab 4: NCDs / กลุ่มเปราะบาง ---
  Widget _buildVulnerableTab() {
    return Form(
      key: _formKeyVulnerable,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCommonForm(),
          const Text('บันทึกกลุ่มเปราะบาง / NCDs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1D9E75))),
          const Divider(),
          const SizedBox(height: 10),
          
          // 🌟 ช่องที่ 1: เลือกกลุ่มเปราะบาง
          const Text('กลุ่มเปราะบาง', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _vulnerableSelectedType,
            items: _vulnerableTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _vulnerableSelectedType = v!),
            decoration: _buildInputDecoration('', Icons.accessible_forward),
          ),
          const SizedBox(height: 16),

          // 🌟 ช่องที่ 2: เลือกโรค NCDs (เปลี่ยนเป็นแบบเลือกได้หลายโรค)
          const Text('โรคเรื้อรัง (NCDs) *เลือกได้มากกว่า 1 โรค', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.redAccent)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50, 
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade100)
            ),
            child: Wrap(
              spacing: 8.0, 
              runSpacing: 8.0,
              children: _ncdTypes.map((ncd) {
                final isSelected = _selectedNcds.contains(ncd);
                return FilterChip(
                  label: Text(ncd, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
                  selected: isSelected,
                  selectedColor: Colors.redAccent,
                  checkmarkColor: Colors.white,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: isSelected ? Colors.redAccent : Colors.grey.shade300),
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedNcds.add(ncd);
                      } else {
                        _selectedNcds.remove(ncd);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F6),
      appBar: AppBar(
        title: const Text('บันทึก/คัดกรอง ข้อมูลสุขภาพ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1D9E75),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1D9E75),
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.coronavirus_outlined), text: 'โรคติดต่อ'),
            Tab(icon: Icon(Icons.assignment_ind_outlined), text: 'คัดกรองสุขภาพจิต'),
            Tab(icon: Icon(Icons.psychology), text: 'ติดตามจิตเวช'),
            Tab(icon: Icon(Icons.monitor_heart_outlined), text: 'กลุ่มเปราะบาง / NCDs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInfectiousTab(),
          _buildMentalScreeningTab(),
          _buildPsychiatricTab(),
          _buildVulnerableTab(),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]),
        child: SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D9E75), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _loading ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Text('บันทึกข้อมูลและรายงาน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _SeverityChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final Color color;
  final void Function(String) onTap;
  const _SeverityChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isSelected ? color : Colors.grey.shade600,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.initialPosition,
  });

  final LatLng initialPosition;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng _pickedPosition;
  final MapController _mapController = MapController();
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _pickedPosition = widget.initialPosition;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moveToMyLocation();
    });
  }

  void _onMapTap(TapPosition _, LatLng position) {
    setState(() {
      _pickedPosition = position;
    });
  }

  Future<void> _moveToMyLocation() async {
    if (!mounted) return;
    setState(() => _locating = true);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิด Location ในอุปกรณ์ก่อน')),
      );
      if (!mounted) return;
      setState(() => _locating = false);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ต้องให้สิทธิ์ตำแหน่งก่อนใช้งาน')),
      );
      if (!mounted) return;
      setState(() => _locating = false);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = LatLng(position.latitude, position.longitude);
      _mapController.move(latLng, 15);
      if (!mounted) return;
      setState(() {
        _pickedPosition = latLng;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถรับตำแหน่งปัจจุบันได้')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกตำแหน่งบนแผนที่'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: widget.initialPosition,
              zoom: 15,
              onTap: _onMapTap,
            ),
            children: [
              // 🌟 ใช้ Proxy ทะลุบล็อก Safari เพื่อดึง Google Maps
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geo_tracker',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pickedPosition,
                    width: 48,
                    height: 48,
                    builder: (context) => const Icon(
                      Icons.location_on,
                      color: Color(0xFF1D9E75),
                      size: 36,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 16,
            top: 16,
            child: FloatingActionButton.small(
              onPressed: _locating ? null : _moveToMyLocation,
              backgroundColor: const Color(0xFF1D9E75),
              child: _locating
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('แตะแผนที่เพื่อวางหมุด', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Lat: ${_pickedPosition.latitude.toStringAsFixed(5)}  lng: ${_pickedPosition.longitude.toStringAsFixed(5)}'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_pickedPosition),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D9E75),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('ยืนยันตำแหน่ง'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 3. Map Screen (RBAC + Ring Strategy) ──────────────────────────────────

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? _userLocation;
  bool _isLocating = true;
  bool _showAnalytics = true; 
  
  late Future<List<Patient>> _patientsFuture;
  late Future<List<Vulnerable>> _vulnerablesFuture;
  late Future<List<CommunityPlace>> _placesFuture;
  
  String _userRole = 'volunteer'; 

  @override
  void initState() {
    super.initState();
    _patientsFuture = fetchPatients();
    _vulnerablesFuture = fetchVulnerables();
    _placesFuture = fetchPlaces();
    _getUserLocation();
    _loadUserRole(); 
  }

  Future<void> _loadUserRole() async {
    final user = await AuthStorage.getUser();
    if (mounted && user != null) {
      setState(() {
        _userRole = user['role']?.toString().toLowerCase() ?? 'volunteer';
      });
    }
  }

  Future<void> _getUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location service disabled');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('Permission denied');
      
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() { _userLocation = LatLng(pos.latitude, pos.longitude); _isLocating = false; });
    } catch (e) {
      if (mounted) setState(() { _userLocation = _defaultMapCenter; _isLocating = false; });
    }
  }

  // 🌟 ฟังก์ชันคำนวณ "รัศมีควบคุมโรค" ตามหลักระบาดวิทยาอัตโนมัติ
  double _getRadiusForDisease(String diseaseName) {
    if (diseaseName.contains('ไข้เลือดออก') || diseaseName.contains('ซิกา') || diseaseName.contains('ปวดข้อยุงลาย') || diseaseName.contains('มาลาเรีย')) {
      return 100.0; // ยุงพาหะ: รัศมี 100 เมตร
    } else if (diseaseName.contains('โควิด') || diseaseName.contains('หวัด') || diseaseName.contains('ปอดอักเสบ') || diseaseName.contains('ไอกรน')) {
      return 50.0;  // ทางเดินหายใจ: ละแวกใกล้เคียง 50 เมตร
    } else if (diseaseName.contains('พิษสุนัขบ้า')) {
      return 3000.0; // สัตว์พาหะ: รัศมี 3 กิโลเมตร
    } else if (diseaseName.contains('อหิวาตกโรค') || diseaseName.contains('อาหารเป็นพิษ')) {
      return 200.0;  // แหล่งน้ำ/อาหาร: รัศมี 200 เมตร
    }
    return 150.0; // ค่าเริ่มต้นโรคอื่นๆ 150 เมตร
  }

  @override
  Widget build(BuildContext context) {
    final isExecutive = _userRole == 'admin' || _userRole == 'executive';
    final isHospital = _userRole == 'hospital' || _userRole == 'staff';
    final isVolunteer = _userRole == 'volunteer' || _userRole == 'user';

    return Scaffold(
      appBar: AppBar(
        title: Text(isExecutive ? 'แผนที่ภาพรวม (Heat Map)' : 'Automated Ring Strategy'), 
        centerTitle: true, 
        backgroundColor: Colors.white, 
        foregroundColor: Colors.black
      ),
      // ...
      body: _isLocating
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Color(0xFF1D9E75)), SizedBox(height: 16), Text('กำลังเตรียมระบบควบคุมโรค...')]))
          : FutureBuilder<List<dynamic>>(
              // 🌟 1. ดึงข้อมูล 3 ตัวให้ครบถ้วนในบรรทัดนี้
              future: Future.wait([_patientsFuture, _vulnerablesFuture, _placesFuture]), 
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('เกิดข้อผิดพลาด: ${snapshot.error}')));

                // 🌟 2. ดึงข้อมูลแยกเป็นลิสต์อย่างปลอดภัย โดยตรวจสอบความยาวของ List ก่อน
                final dataList = snapshot.data ?? [];
                
                final patients = dataList.isNotEmpty ? List<Patient>.from(dataList[0]) : <Patient>[];
                final vulnerables = dataList.length > 1 ? List<Vulnerable>.from(dataList[1]) : <Vulnerable>[];
                final places = dataList.length > 2 ? List<CommunityPlace>.from(dataList[2]) : <CommunityPlace>[];
                
                // 🌟 ระบบคำนวณ Ring Strategy ค้นหาบ้านเป้าหมายอัตโนมัติ
                final Distance distanceCalc = const Distance();
                List<Map<String, dynamic>> targetList = [];

                // --- 1. สร้างวงรัศมีตามชนิดโรค (Automated Buffer Zone) ---
                final analyticsCircles = patients.map((patient) {
                  double diseaseRadius = _getRadiusForDisease(patient.diseaseName);
                  
                  // คำนวณหาว่ามีกลุ่มเปราะบางคนไหนอยู่ในรัศมีของคนไข้รายนี้บ้าง
                  for (var vul in vulnerables) {
                    double dist = distanceCalc.as(LengthUnit.Meter, LatLng(patient.lat, patient.lng), LatLng(vul.lat, vul.lng));
                    if (dist <= diseaseRadius) {
                      // เช็คว่าคนนี้ถูกดึงมาหรือยัง (กันซ้ำ)
                      if (!targetList.any((t) => t['vulnerable'].id == vul.id)) {
                        targetList.add({
                          'vulnerable': vul,
                          'patient': patient,
                          'distance': dist,
                          'radius': diseaseRadius,
                        });
                      }
                    }
                  }

                  return CircleMarker(
                    point: LatLng(patient.lat, patient.lng),
                    color: severityColor(patient.severity).withValues(alpha: isExecutive ? 0.4 : 0.25),
                    borderColor: severityColor(patient.severity).withValues(alpha: 0.6),
                    borderStrokeWidth: isExecutive ? 0 : 1, 
                    useRadiusInMeter: true, 
                    radius: isExecutive ? diseaseRadius * 3 : diseaseRadius, // ผู้บริหารเห็นรัศมีกว้างกว่า
                  );
                }).toList();

                // จัดเรียงเป้าหมายตามระยะทาง (ใกล้สุดไปไกลสุด)
                targetList.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

                // --- 2. สร้างหมุด (Markers) ปกติ ---
                List<Marker> markers = [];
                
                // 🌟 ปลดล็อก: ให้อสม. และ รพ.สต. เห็นหมุดได้ทั้งคู่ (แต่ซ่อนชื่อถ้าเป็น อสม.)
                if (isHospital || isVolunteer) {
                  
                  // หมุดผู้ป่วย (โรคติดต่อ, จิตเวช, สุขภาพจิต)
                  markers.addAll(patients.map((patient) {
                    
                    return Marker(
                      point: LatLng(patient.lat, patient.lng), width: 48, height: 48,
                      builder: (context) => GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Icon(Icons.location_on, color: severityColor(patient.severity)), 
                                      const SizedBox(width: 10), 
                                      // 🌟 RBAC: ถ้าเป็นอสม. ให้ขึ้นว่า "(ปกปิดชื่อตาม PDPA)"
                                      Expanded(child: Text(isHospital ? patient.name : 'ผู้ป่วย (ปกปิดชื่อตาม PDPA)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))), 
                                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context), padding: EdgeInsets.zero, constraints: const BoxConstraints())
                                    ]),
                                    const SizedBox(height: 12),
                                    _PatientDetailRow(label: 'โรค', value: patient.diseaseName),
                                    _PatientDetailRow(label: 'พื้นที่', value: patient.village),
                                    _PatientDetailRow(label: 'ความรุนแรง', value: patient.severity, valueColor: severityColor(patient.severity)),
                                    const SizedBox(height: 16),
                                    // 🌟 ปุ่มนำทางสำหรับ: ผู้ป่วยโรคต่างๆ
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.navigation_outlined),
                                        label: const Text('เริ่มนำทางไปยังบ้านหลังนี้'),
                                        onPressed: () async {
                                          String mapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=${patient.lat},${patient.lng}&travelmode=driving';
                                          if (_userLocation != null) {
                                            mapsUrl += '&origin=${_userLocation!.latitude},${_userLocation!.longitude}';
                                          }
                                          final Uri url = Uri.parse(mapsUrl);
                                          if (await canLaunchUrl(url)) {
                                            await launchUrl(url, mode: LaunchMode.externalApplication);
                                          } else {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไม่สามารถเปิด Google Maps ได้')));
                                            }
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D9E75), foregroundColor: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        // 🌟 ดึงรูปภาพไอคอนโรคมาแสดงตรงนี้เลยครับ 🌟
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: severityColor(patient.severity), width: 3), // กรอบสีบอกความรุนแรง
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]
                          ),
                          padding: const EdgeInsets.all(4),
                          // ✅ แก้ไข: ส่งทั้ง รหัสโรค (diseaseCode) และ ชื่อโรค (diseaseName) เข้าไปให้ฟังก์ชันช่วยเลือกรูปภาพ
                          child: Image.asset(
                            getPatientIconPath(patient.diseaseCode, patient.diseaseName), 
                            errorBuilder: (ctx, err, stack) => Icon(Icons.person, color: severityColor(patient.severity)), // สำรองกรณีโหลดรูปไม่ได้
                          ),
                        ),
                      ),
                    );
                  }));
                  
                  // หมุดกลุ่มเปราะบาง / NCDs
                  markers.addAll(vulnerables.map((vul) {
                    bool isNCDs = vul.type.contains('NCDs');
                    
                    Widget markerWidget = isNCDs 
                        ? Image.asset(
                            'assets/ncd_pin.png', 
                            width: 44, 
                            height: 44, 
                            errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.monitor_heart, 
                                  color: Colors.blue, 
                                  size: 32,
                                )
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white, 
                              shape: BoxShape.circle, 
                              border: Border.all(color: Colors.orange, width: 3), 
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]
                            ), 
                            child: const Icon(Icons.accessible_forward, color: Colors.orange, size: 24)
                          );

                    return Marker(
                      point: LatLng(vul.lat, vul.lng), width: 48, height: 48,
                      builder: (context) => GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [Icon(isNCDs ? Icons.monitor_heart : Icons.accessible_forward, color: isNCDs ? Colors.blue : Colors.orange), const SizedBox(width: 10), Expanded(child: Text(vul.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context), padding: EdgeInsets.zero, constraints: const BoxConstraints())]),
                                    const SizedBox(height: 12),
                                    _PatientDetailRow(label: 'ประเภท', value: vul.type, valueColor: isNCDs ? Colors.blue : Colors.orange),
                                    _PatientDetailRow(label: 'ที่อยู่รายละเอียด', value: vul.address),
                                    
                                    const SizedBox(height: 16),
                                    // 🌟 เพิ่มปุ่มนำทางสำหรับกลุ่มเปราะบาง / NCDs ตรงนี้ (ผูกกับตัวแปร vul ปลายทางตรงเป๊ะ ไม่สลับแน่นอน)
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.navigation_outlined),
                                        label: const Text('เริ่มนำทางไปยังบ้านหลังนี้'),
                                        onPressed: () async {
                                          String mapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=${vul.lat},${vul.lng}&travelmode=driving';
                                          
                                          // ถ้ามีพิกัดของตัวเรา ให้ส่งพิกัดเราเป็นจุดเริ่มต้นบังคับเส้นทาง
                                          if (_userLocation != null) {
                                            mapsUrl += '&origin=${_userLocation!.latitude},${_userLocation!.longitude}';
                                          }

                                          final Uri url = Uri.parse(mapsUrl);
                                          if (await canLaunchUrl(url)) {
                                            await launchUrl(url, mode: LaunchMode.externalApplication);
                                          } else {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไม่สามารถเปิด Google Maps ได้')));
                                            }
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D9E75), foregroundColor: Colors.white),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        child: markerWidget,
                      ),
                    );
                  }));

                  // 🌟 หมุดสถานที่สำคัญในชุมชน
                  markers.addAll(places.map((place) {
                    return Marker(
                      point: LatLng(place.lat, place.lng), 
                      width: 48, height: 48,
                      builder: (context) => GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Row(children: [const Icon(Icons.place, color: Colors.blueAccent), const SizedBox(width: 8), Expanded(child: Text(place.name))]),
                              content: Text('ประเภทสถานที่: ${place.type}'),
                            ),
                          );
                        },
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(
                            getMarkerIconPath(place.type), // 🌟 ดึงรูปภาพตามประเภทสถานที่
                            errorBuilder: (ctx, err, stack) => const Icon(Icons.location_city, color: Colors.grey),
                          ),
                        ),
                      ),
                    );
                  }));
                }

                if (_userLocation != null) {
                  markers.add(Marker(point: _userLocation!, width: 48, height: 48, builder: (context) => const Stack(alignment: Alignment.center, children: [Icon(Icons.circle, color: Colors.blueAccent, size: 24), Icon(Icons.circle, color: Colors.white, size: 16), Icon(Icons.circle, color: Colors.blueAccent, size: 10)])));
                }

                return Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(center: _userLocation ?? _defaultMapCenter, zoom: isExecutive ? 13 : 15),
                      children: [
                        // 🌟 ใช้ Proxy ทะลุบล็อก Safari เพื่อดึง Google Maps
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.geo_tracker',
                        ),
                        if (_showAnalytics) CircleLayer(circles: analyticsCircles),
                        MarkerLayer(markers: markers),
                      ],
                    ),
                    
                    if (!isExecutive)
                      Positioned(
                        left: 16, right: 16, top: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))]),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('วงรัศมีควบคุมโรค', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              Switch(value: _showAnalytics, activeColor: const Color(0xFF1D9E75), onChanged: (value) => setState(() => _showAnalytics = value)),
                            ],
                          ),
                        ),
                      ),

                    // 🌟 แผงแจ้งสถานะสำหรับผู้บริหาร
                    if (isExecutive)
                      Positioned(
                        right: 16, top: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))]),
                          child: const Text('โหมดรวมนโยบาย (Heatmap)', style: TextStyle(fontSize: 13, color: Color(0xFF1D9E75), fontWeight: FontWeight.w600)),
                        ),
                      ),
                      
                    // 🌟 แผงสไลด์แสดง "เป้าหมายลงพื้นที่" (Draggable List)
                    if (!isExecutive && targetList.isNotEmpty && _showAnalytics)
                      DraggableScrollableSheet(
                        initialChildSize: 0.35, minChildSize: 0.15, maxChildSize: 0.7,
                        builder: (context, scrollController) {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 15, offset: const Offset(0, -2))],
                            ),
                            child: Column(
                              children: [
                                const SizedBox(height: 12),
                                Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.my_location, color: Color(0xFFE24B4A)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('เป้าหมายเร่งด่วน (Ring Strategy)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                            Text('พบบ้าน/กลุ่มเสี่ยง ${targetList.length} หลัง ในรัศมีระบาด', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: ListView.builder(
                                    controller: scrollController,
                                    padding: EdgeInsets.zero,
                                    itemCount: targetList.length,
                                    itemBuilder: (context, index) {
                                      final item = targetList[index];
                                      final vul = item['vulnerable'] as Vulnerable;
                                      final patient = item['patient'] as Patient;
                                      final dist = (item['distance'] as double).toStringAsFixed(0);
                                      final radius = (item['radius'] as double).toStringAsFixed(0);

                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                                          child: const Icon(Icons.home_outlined, color: Colors.red),
                                        ),
                                        // 🌟 RBAC: อสม. จะเห็นแค่ปกปิดชื่อ แต่ รพ.สต. จะเห็นชื่อและที่อยู่จริง
                                        title: Text(isVolunteer ? 'บ้านกลุ่มเปราะบาง (ปกปิดชื่อ)' : vul.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(isVolunteer ? '(ข้อมูลถูกปกปิดตามสิทธิ์)' : vul.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                            const SizedBox(height: 2),
                                            Text('⚠️ ห่างจากผู้ป่วยโรค${patient.diseaseName} $dist ม. (รัศมี $radius ม.)', style: const TextStyle(fontSize: 11, color: Color(0xFFBA7517), fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                        // 🌟 โค้ดปุ่มนำทางฉบับบังคับทั้ง "จุดเริ่มต้น" และ "ปลายทาง"
                                        trailing: ElevatedButton(
                                          onPressed: () async {
                                            // 💡 เปลี่ยนตรงนี้: จาก vul.lat/vul.lng ให้เป็น patient.lat/patient.lng
                                            final double destLat = patient.lat;
                                            final double destLng = patient.lng;

                                            // 1. กำหนดปลายทาง (destination) เป็นพิกัดของผู้ป่วยโรคติดต่อ
                                            String mapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving';

                                            // 2. บังคับกำหนดต้นทาง (origin) โดยใช้พิกัดปัจจุบันของเรา
                                            if (_userLocation != null) {
                                              mapsUrl += '&origin=${_userLocation!.latitude},${_userLocation!.longitude}';
                                            }

                                            final Uri url = Uri.parse(mapsUrl);

                                            try {
                                              if (await canLaunchUrl(url)) {
                                                await launchUrl(
                                                  url, 
                                                  mode: LaunchMode.externalApplication 
                                                );
                                              } else {
                                                throw 'Could not launch URL';
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('❌ ไม่สามารถเปิดแอปนำทางได้'),
                                                    backgroundColor: Colors.redAccent,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF1D9E75), 
                                            foregroundColor: Colors.white, 
                                            padding: const EdgeInsets.symmetric(horizontal: 12), 
                                            textStyle: const TextStyle(fontSize: 12)
                                          ),
                                          child: const Text('นำทาง'),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _PatientDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _PatientDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}

// ─── 4. Alert Screen ────────────────────────────────────────────────────────

class AlertItem {
  final int id;
  final String message;
  final DateTime sentAt;
  final String status;

  AlertItem({required this.id, required this.message, required this.sentAt, required this.status});

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    return AlertItem(
      id: json['id'] as int,
      message: json['message']?.toString() ?? 'ไม่มีข้อความ',
      sentAt: DateTime.tryParse(json['sent_at']?.toString() ?? '') ?? DateTime.now(),
      status: json['status']?.toString() ?? 'unknown',
    );
  }
}

// 🌟 ฟังก์ชันดึงการแจ้งเตือน (อัปเดตให้แนบ Token เพื่อเช็คสิทธิ์)
Future<List<AlertItem>> fetchAlerts() async {
  try {
    final headers = await _getAuthHeaders(); // 🌟 1. ดึง Token ของคนที่ Login
    final response = await http.get(Uri.parse('$kApiBase/alerts'), headers: headers); // 🌟 2. แนบไปกับ API
    
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AlertItem.fromJson(json)).toList();
    }
  } catch (e) {
    debugPrint('fetchAlerts error: $e');
  }
  return [];
}

class AlertScreen extends StatelessWidget {
  const AlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การแจ้งเตือน'), centerTitle: true),
      body: FutureBuilder<List<AlertItem>>(
        future: fetchAlerts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF1D9E75)));
          }
          if (snapshot.hasError) {
            return const Center(child: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ'));
          }
          
          final alerts = snapshot.data ?? [];
          
          if (alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('ยังไม่มีการแจ้งเตือนระบบ', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final alert = alerts[index];
              final timeStr = '${alert.sentAt.toLocal().hour.toString().padLeft(2, '0')}:${alert.sentAt.toLocal().minute.toString().padLeft(2, '0')} น.';
              
              return _AlertListItem(
                title: 'แจ้งเตือนระบบ (ID: ${alert.id})',
                body: alert.message,
                time: timeStr,
                color: alert.status == 'sent' ? const Color(0xFF1D9E75) : const Color(0xFFBA7517),
                icon: Icons.notifications_active,
              );
            },
          );
        },
      ),
    );
  }
}

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  // 🌟 เปลี่ยนจากการรับแค่ Patient มารับข้อมูลแบบรวม (Dynamic)
  late Future<List<dynamic>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      // 🌟 ดึงข้อมูล 2 แหล่งพร้อมกัน
      _historyFuture = Future.wait([
        fetchPatients(),
        fetchVulnerables()
      ]);
    });
  }

  // 🌟 ฟังก์ชันดาวน์โหลดรายงาน Excel
  Future<void> _exportToExcel() async {
    try {
      final token = await AuthStorage.getToken();
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ ไม่พบเซสชันการเข้าสู่ระบบ')));
        return;
      }

      // ส่งพาสพอร์ตความปลอดภัยไปทาง Query String เพื่อให้เปิดเว็บบราวเซอร์โหลดไฟล์ได้โดยตรง
      final Uri url = Uri.parse('$kApiBase/patients/export?token=$token');
        
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ ไม่สามารถเปิดโปรแกรมดาวน์โหลดไฟล์ได้'), backgroundColor: Colors.redAccent)
          );
        }
      }
    } catch (e) {
      debugPrint('Export error: $e');
    }
  }

  // 🌟 ฟังก์ชันลบข้อมูล ปรับปรุงให้รู้ว่าเป็นประเภทไหน
  Future<void> _confirmDelete(BuildContext context, int id, String name, bool isPatient) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: Text('คุณต้องการยกเลิกการรายงาน "$name" ใช่หรือไม่?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ลบข้อมูล', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm == true && context.mounted) {
      try {
        if (isPatient) {
          await deletePatient(id);
        } else {
          // หากคุณมี API deleteVulnerable ค่อยใส่ตรงนี้ครับ
          // await deleteVulnerable(id);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ฟังก์ชันลบกลุ่มเปราะบางยังไม่พร้อมใช้งาน'), backgroundColor: Colors.orange));
          return;
        }
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ลบข้อมูลสำเร็จ'), backgroundColor: Colors.green)
          );
          _loadData(); // 🌟 โหลดข้อมูลใหม่เพื่อรีเฟรชหน้าจอ
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาด: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F6),
      appBar: AppBar(
        title: const Text('ประวัติการรายงาน'), 
        centerTitle: true,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined, color: Color(0xFF1D9E75)),
            tooltip: 'ส่งออกไฟล์ Excel',
            onPressed: _exportToExcel, // 🌟 กดแล้วรันฟังก์ชันดาวน์โหลดทันที
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF1D9E75)));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('ไม่สามารถโหลดประวัติได้: ${snapshot.error}'),
              ),
            );
          }

          // 🌟 แยกข้อมูลที่ดึงมา
          final patients = List<Patient>.from(snapshot.data?[0] ?? []);
          final vulnerables = List<Vulnerable>.from(snapshot.data?[1] ?? []);
          
          if (patients.isEmpty && vulnerables.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('ยังไม่มีรายการรายงาน', style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          // 🌟 นำข้อมูลทั้งหมดมารวมกันใน List เดียว
          final List<dynamic> allHistory = [...patients, ...vulnerables];

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: allHistory.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = allHistory[index];
              
              if (item is Patient) {
                return _buildPatientCard(item, context);
              } else if (item is Vulnerable) {
                return _buildVulnerableCard(item, context);
              }
              return const SizedBox();
            },
          );
        },
      ),
    );
  }

  // 🌟 วิดเจ็ตการ์ดแสดงผู้ป่วย (506 / จิตเวช / สุขภาพจิต)
  Widget _buildPatientCard(Patient patient, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  patient.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1D9E75)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: () => _confirmDelete(context, patient.id, patient.name, true),
              ),
            ],
          ),
          const Divider(height: 16),
          Text('เรื่องที่รายงาน: ${patient.diseaseName}'),
          Text('พื้นที่: ${patient.village}'),
          Text('วันที่: ${patient.reportDate.toLocal().toString().split(' ')[0]}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.brightness_1, size: 10, color: severityColor(patient.severity)),
              const SizedBox(width: 6),
              Text('ระดับ/ความรุนแรง: ${patient.severity}'),
            ],
          ),
        ],
      ),
    );
  }

  // 🌟 วิดเจ็ตการ์ดแสดงกลุ่มเปราะบาง
  Widget _buildVulnerableCard(Vulnerable vul, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  vul.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
              ),
              // ลบกลุ่มเปราะบาง
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                onPressed: () => _confirmDelete(context, vul.id, vul.name, false),
              ),
            ],
          ),
          const Divider(height: 16),
          Text('กลุ่มเป้าหมาย/NCDs: ${vul.type}'),
          Text('ที่อยู่: ${vul.address}'),
        ],
      ),
    );
  }
}

// ─── 5. Report Vulnerable Screen (หน้าเพิ่มกลุ่มเปราะบาง) ──────────────────

class ReportVulnerableScreen extends StatefulWidget {
  const ReportVulnerableScreen({super.key});

  @override
  State<ReportVulnerableScreen> createState() => _ReportVulnerableScreenState();
}

class _ReportVulnerableScreenState extends State<ReportVulnerableScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController(); 

  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  
  String _selectedType = 'ผู้สูงอายุ';
  final List<String> _types = ['ผู้สูงอายุ', 'ผู้ป่วยติดเตียง', 'คนพิการ', 'ผู้มีรายได้น้อย', 'ผู้ป่วย NCDs'];
  
  // 🌟 1. เปลี่ยนตัวแปรมารองรับการเลือกหลายโรค (เก็บเป็น List)
  List<String> _selectedNcds = [];
  final List<String> _ncdTypes = [
    'เบาหวาน (Diabetes)', 
    'ความดันโลหิตสูง (Hypertension)', 
    'โรคหลอดเลือดหัวใจ (CVD)', 
    'โรคหลอดเลือดสมอง (Stroke)', 
    'โรคไตเรื้อรัง (CKD)', 
    'ถุงลมโป่งพอง/หอบหืด (COPD)',
    'โรคมะเร็ง (Cancer)',
    'โรคอ้วนลงพุง (Obesity)',
    'อื่นๆ'
  ];
  
  bool _loading = false;
  bool _gpsLoading = false;
  String _gpsStatus = 'ยังไม่ได้ระบุพิกัด';
  double? _lat, _lng;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _getAddress(double lat, double lng) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=th');
      final response = await http.get(url, headers: {'User-Agent': 'GeoHealthTrackerApp'});
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        
        if (address != null && mounted) {
          String province = address['province'] ?? address['state'] ?? address['city'] ?? address['region'] ?? 'ไม่ระบุจังหวัด';
          String amphoe = address['district'] ?? address['city_district'] ?? address['county'] ?? 'ไม่ระบุอำเภอ';
          String tambon = address['suburb'] ?? address['town'] ?? address['village'] ?? address['quarter'] ?? 'ไม่ระบุตำบล';

          province = province.replaceAll('จังหวัด', '').trim();
          amphoe = amphoe.replaceAll('อำเภอ', '').replaceAll('เขต', '').trim();
          tambon = tambon.replaceAll('ตำบล', '').replaceAll('แขวง', '').trim();

          String displayAddress = '';
          if (province.contains('กรุงเทพ') || province.toLowerCase() == 'bangkok') {
            displayAddress = 'แขวง$tambon เขต$amphoe กรุงเทพมหานคร';
          } else {
            displayAddress = 'ต.$tambon อ.$amphoe จ.$province';
          }

          setState(() {
            _gpsStatus = displayAddress; 
          });
        }
      }
    } catch (e) {
      debugPrint('Address Error: $e');
    }
  }

  Future<void> _getGPS() async {
    setState(() => _gpsLoading = true);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _gpsLoading = false;
        _gpsStatus = 'เปิดการใช้งาน Location ในอุปกรณ์ก่อน';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() {
        _gpsLoading = false;
        _gpsStatus = 'ต้องให้สิทธิ์ตำแหน่งก่อนใช้งาน';
      });
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;

        // 🌟 2. อัปเดตตัวเลขลงช่องกรอกด้วย
        _latCtrl.text = _lat.toString();
        _lngCtrl.text = _lng.toString();

        _gpsStatus = 'กำลังแปลงที่อยู่...';
      });
      await _getAddress(pos.latitude, pos.longitude);
    } catch (_) {
      setState(() => _gpsStatus = 'ไม่สามารถรับพิกัดได้ ลองเลือกบนแผนที่');
    } finally {
      setState(() => _gpsLoading = false);
    }
  }

  Future<void> _openLocationPicker() async {
    final LatLng? location = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialPosition: _lat != null && _lng != null ? LatLng(_lat!, _lng!) : const LatLng(14.9798, 102.0978),
        ),
      ),
    );
    if (location != null) {
      setState(() {
        _lat = location.latitude;
        _lng = location.longitude;

        _latCtrl.text = _lat.toString();
        _lngCtrl.text = _lng.toString();

        _gpsStatus = 'เลือกพิกัดจากแผนที่สำเร็จ' ;
      });
      await _getAddress(location.latitude, location.longitude);
    }
  }

  Future<void> _submitVulnerable() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาระบุพิกัด GPS')));
      return;
    }

    setState(() => _loading = true);

    try {
      final fullAddress = '${_addressCtrl.text} $_gpsStatus'.trim();
      final finalType = _selectedType == 'ผู้ป่วย NCDs' ? 'ผู้ป่วย NCDs (${_selectedNcds.join(", ")})' : _selectedType;

      final headers = await _getAuthHeaders();

      final response = await http.post(
        Uri.parse('$kApiBase/vulnerable'),
        headers: headers,
        body: jsonEncode({
          'name': _nameCtrl.text,
          'type': finalType, 
          'lat': _lat,
          'lng': _lng,
          'address': fullAddress, 
        }),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ บันทึกข้อมูลสำเร็จ'), backgroundColor: Color(0xFF1D9E75)),
          );
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red.shade800,
          )
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F6),
      appBar: AppBar(
        title: const Text('บันทึกกลุ่มเปราะบาง / NCDs'),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ชื่อ-นามสกุล', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  hintText: 'กรอกชื่อ-นามสกุล',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกชื่อ' : null,
              ),
              const SizedBox(height: 16),

              const Text('ประเภท', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedType,
                items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _selectedType = v!),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 16),

              if (_selectedType == 'ผู้ป่วย NCDs') ...[
                const Text('ระบุโรค NCDs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.redAccent)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedNcds.isNotEmpty ? _selectedNcds.first : null,
                  isExpanded: true,
                  items: _ncdTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => _selectedNcds = [v!]),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.red.shade50, 
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.monitor_heart_outlined, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const Text('บ้านเลขที่ / รายละเอียดที่อยู่', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                  hintText: 'เช่น เลขที่บ้าน, หมู่บ้าน, ซอย',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                  prefixIcon: const Icon(Icons.home_outlined),
                ),
              ),
              const SizedBox(height: 16),

              const Text('พิกัด GPS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _lat != null ? Icons.location_on : Icons.location_off,
                          color: _lat != null ? const Color(0xFFBA7517) : Colors.grey, 
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_gpsStatus, style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _gpsLoading ? null : _openLocationPicker,
                            icon: const Icon(Icons.map, size: 18),
                            label: const Text('เลือกตำแหน่ง'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _gpsLoading ? null : _getGPS,
                            icon: _gpsLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.my_location, size: 18),
                            label: Text(_gpsLoading ? 'กำลังรับพิกัด' : 'รับพิกัด GPS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFBA7517),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submitVulnerable,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D9E75),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text('บันทึกข้อมูล', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertListItem extends StatelessWidget {
  final String title;
  final String body;
  final String time;
  final Color color;
  final IconData icon;
  const _AlertListItem({
    required this.title,
    required this.body,
    required this.time,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─── 6. Profile Screen ──────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  String? _base64Image; 
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // 🌟 แก้ไข: ให้โหลดข้อมูลจากเครื่องก่อน แล้วไปดึงของใหม่จาก Server มาอัปเดตทับ
  Future<void> _loadUserData() async {
    // 1. ดึงข้อมูลเดิมจากในเครื่องมาแสดงผลก่อน (เพื่อให้หน้าจอไม่กระตุก)
    final localUser = await AuthStorage.getUser();
    if (localUser != null) {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _user = localUser;
          _base64Image = prefs.getString('profile_base64_${localUser['id']}');
        });
      }
    }

    // 2. แอบไปดึงข้อมูลล่าสุดจาก Server (/api/auth/verify) เผื่อแอดมินเปลี่ยน Role ให้
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(Uri.parse('$kApiBase/auth/verify'), headers: headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverUser = data['user'] as Map<String, dynamic>;
        
        // บันทึกข้อมูลที่อัปเดตแล้วทับลงไปในเครื่อง
        await AuthStorage.saveUser(serverUser);
        
        if (mounted) {
          setState(() {
            _user = serverUser; // รีเฟรชหน้าจอให้โชว์ Role ล่าสุด
          });
        }
      }
    } catch (e) {
      debugPrint('Sync profile error: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null && _user != null) {
        final bytes = await image.readAsBytes();
        final String base64Str = base64Encode(bytes);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_base64_${_user!['id']}', base64Str); 

        setState(() {
          _base64Image = base64Str;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('อัปเดตภาพโปรไฟล์สำเร็จ'), backgroundColor: Color(0xFF1D9E75)),
          );
        }
      }
    } catch (e) {
      debugPrint('Pick image error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F6),
      appBar: AppBar(
        title: const Text('โปรไฟล์ของฉัน'),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1D9E75), width: 4),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: ClipOval(
                      child: _base64Image != null && _base64Image!.isNotEmpty
                          ? Image.memory(
                              base64Decode(_base64Image!),
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 60, color: Colors.grey),
                            )
                          : const Icon(Icons.person, size: 60, color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFBA7517), 
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _user!['name_th'] ?? 'ไม่ระบุชื่อ',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              // 🌟 เช็ค Role เพื่อแสดงตำแหน่งให้ถูกต้อง
              _user!['role'] == 'hospital' || _user!['role'] == 'staff'
                  ? 'เจ้าหน้าที่ รพ.สต. / สาธารณสุข'
                  : _user!['role'] == 'admin' || _user!['role'] == 'executive'
                      ? 'สสอ. / สสจ.'
                      : 'อาสาสมัครสาธารณสุขประจำหมู่บ้าน (อสม.)',
              style: TextStyle(
                fontSize: 14, 
                color: _user!['role'] == 'hospital' ? const Color(0xFF185FA5) : Colors.grey.shade600, // รพ.สต. ให้ข้อความเป็นสีน้ำเงิน
                fontWeight: _user!['role'] == 'hospital' ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 32),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFF1D9E75).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.person_outline, color: Color(0xFF1D9E75)),
                    ),
                    title: const Text('ชื่อผู้ใช้ (Username)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    subtitle: Text(_user!['username'] ?? '-', style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.email_outlined, color: Colors.orange),
                    ),
                    title: const Text('อีเมล', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    subtitle: Text(_user!['email'] ?? '-', style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
                  ),
                  // 🌟 เพิ่ม Divider และ ListTile ข้อมูลสังกัดตรงนี้
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.local_hospital_outlined, color: Colors.blue),
                    ),
                    title: const Text('สังกัด (รพ.สต./รพ.)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    subtitle: Text(_user!['hospital'] ?? 'ไม่ระบุ', style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await logoutUser();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacementNamed('/login');
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('ออกจากระบบ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 7. Report Place Screen (หน้าปักหมุดสถานที่) ─────────────────────────
class ReportPlaceScreen extends StatefulWidget {
  const ReportPlaceScreen({super.key});
  @override
  State<ReportPlaceScreen> createState() => _ReportPlaceScreenState();
}

class _ReportPlaceScreenState extends State<ReportPlaceScreen> {
  final _nameCtrl = TextEditingController();

  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  double? _lat, _lng;
  String _gpsStatus = 'แตะเพื่อเลือกพิกัด';
  bool _loading = false;
  
  String _selectedType = 'บ้าน';
  final List<String> _placeTypes = [
    'บ้าน', 'บ้านร้าง', 'สถานที่ราชการอื่นๆ', 'โรงงาน', 'วัด/สำนักสงฆ์', 
    'สถานบริการสุขภาพ', 'อู่ซ่อมรถ', 'แหล่งน้ำ', 'ศาลาหมู่บ้าน', 'ร้านค้า', 
    'ปั๊มน้ำมัน', 'ประปา', 'โรงเรียน', 'ฟาร์มวัว', 'ฟาร์มหมู', 
    'ฟาร์มไก่', 'สถานีตำรวจ', 'บ้านผู้นำชุมชน', 'บ้านอสม.', 'อบต/เทศบาล', 'ตลาด', 'รีสอร์ท', 'โรงแรม'
  ];

  // 🌟 อย่าลืมใส่ dispose คืนหน่วยความจำด้วยนะครับ 🌟
  @override
  void dispose() {
    _nameCtrl.dispose();
    _latCtrl.dispose(); 
    _lngCtrl.dispose(); 
    super.dispose();
  }

  Future<void> _openLocationPicker() async {
    final LatLng? location = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initialPosition: _lat != null && _lng != null ? LatLng(_lat!, _lng!) : _defaultMapCenter)),
    );
    if (location != null) {
      setState(() { _lat = location.latitude; _lng = location.longitude; _gpsStatus = 'Lat: ${_lat!.toStringAsFixed(4)}, Lng: ${_lng!.toStringAsFixed(4)}'; });
    }
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.isEmpty || _lat == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกชื่อและเลือกพิกัด GPS')));
      return;
    }
    setState(() => _loading = true);
    try {
      await postPlace(name: _nameCtrl.text, type: _selectedType, lat: _lat!, lng: _lng!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ ปักหมุดสถานที่สำเร็จ'), backgroundColor: Color(0xFF1D9E75)));
        
        // ✅ เคลียร์ค่าแทนการ Pop
        setState(() {
          _nameCtrl.clear();
          _latCtrl.clear();
          _lngCtrl.clear();
          _lat = null;
          _lng = null;
          _gpsStatus = 'แตะเพื่อเลือกพิกัด';
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ เกิดข้อผิดพลาด'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F6),
      appBar: AppBar(title: const Text('ปักหมุดสถานที่สำคัญ'), backgroundColor: Colors.white, centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ชื่อสถานที่', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _nameCtrl, decoration: InputDecoration(filled: true, fillColor: Colors.white, hintText: 'เช่น วัดป่าไร่, ศาลาหมู่ 5', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 16),
            const Text('ประเภทสถานที่', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedType,
              items: _placeTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _selectedType = v!),
              decoration: InputDecoration(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 16),
            const Text('พิกัด GPS (ดึงจากแผนที่ หรือกรอกเอง)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            // 🌟 4.1 เพิ่มช่องให้พิมพ์ / วางตัวเลขพิกัดเองได้
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'ละติจูด (Lat)',
                      filled: true, fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.explore_outlined, color: Color(0xFF1D9E75)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (v) {
                      _lat = double.tryParse(v);
                      if (_lat != null && _lng != null) setState(() => _gpsStatus = 'พิกัดจากการกรอกด้วยตนเอง');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lngCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'ลองจิจูด (Lng)',
                      filled: true, fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.explore_outlined, color: Color(0xFF1D9E75)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (v) {
                      _lng = double.tryParse(v);
                      if (_lat != null && _lng != null) setState(() => _gpsStatus = 'พิกัดจากการกรอกด้วยตนเอง');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 🌟 4.2 กล่องแสดงสถานะและปุ่มเปิดแผนที่
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(_lat != null ? Icons.location_on : Icons.location_off, color: _lat != null ? const Color(0xFF1D9E75) : Colors.grey),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_gpsStatus, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _openLocationPicker,
                      icon: const Icon(Icons.map, size: 18),
                      label: const Text('เลือกตำแหน่งบนแผนที่'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFF1D9E75)),
                        foregroundColor: const Color(0xFF1D9E75),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(onPressed: _loading ? null : _submit, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D9E75), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _loading ? const CircularProgressIndicator() : const Text('บันทึกหมุด', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            )
          ],
        ),
      ),
    );
  }
}

const String privacyPolicyText = '''
นโยบายความเป็นส่วนตัวและประกาศการคุ้มครองข้อมูลส่วนบุคคล (Privacy Policy & Privacy Notice)
สำหรับแอปพลิเคชัน Geo-Health Tracker
มีผลบังคับใช้เมื่อวันที่: 16/06/2569

แอปพลิเคชัน Geo-Health Tracker ตระหนักถึงความสำคัญของการคุ้มครองข้อมูลส่วนบุคคลตามพระราชบัญญัติคุ้มครองข้อมูลส่วนบุคคล พ.ศ. 2562 (PDPA) เราจึงจัดทำนโยบายและประกาศฉบับนี้ขึ้น เพื่อชี้แจงให้ท่านทราบถึงวิธีการจัดเก็บ ใช้ และเปิดเผยข้อมูลส่วนบุคคล

1. คำแถลงนโยบาย และผู้ที่มีส่วนเกี่ยวข้อง
แอปพลิเคชันนี้มีวัตถุประสงค์เพื่อใช้เป็นเครื่องมือสำหรับเฝ้าระวัง ป้องกันโรค และติดตามสุขภาพของประชาชนในชุมชน โดยครอบคลุมผู้ใช้งานระบบ (อสม., เจ้าหน้าที่) และเจ้าของข้อมูล (ประชาชน, ผู้ป่วย)

2. ข้อมูลส่วนบุคคลที่เก็บรวบรวม
ระบบจะเก็บข้อมูลส่วนบุคคลทั่วไป (ชื่อ, เบอร์โทร, พิกัด GPS) และข้อมูลที่มีความอ่อนไหว (ประวัติสุขภาพ, ผลประเมิน SMI V-SCAN และ OAS)

3. จุดประสงค์ในการประมวลผลข้อมูล
เพื่อยืนยันตัวตน เฝ้าระวังโรคติดต่อ คัดกรองสุขภาพจิต และแจ้งเตือนข้อมูลที่สำคัญผ่านระบบ

4. การส่งต่อและระยะเวลาจัดเก็บ
ข้อมูลของท่านจะถูกเก็บรักษาเป็นความลับ และส่งต่อให้เจ้าหน้าที่สาธารณสุขระดับ รพ.สต., สสอ., สสจ. เท่านั้น โดยจะทำลายอย่างปลอดภัยเมื่อพ้นกำหนดตามมาตรฐานกระทรวงสาธารณสุข

5. ช่องทางการติดต่อผู้ควบคุมข้อมูลส่วนบุคคล (DPO)
นายศุภนนท์ ครุฑโพธิ์ศรี นักวิชาการสาธารณสุข (ระบาดวิทยาและโรคติดต่อ)
รพ.สต.หนองช้างแล่น 38 ม.3 ต.หนองช้างแล่น อ.ห้วยยอด จ.ตรัง 92130
อีเมล: notsuphanon081039@gmail.com | เบอร์โทรศัพท์: 0835015424
''';