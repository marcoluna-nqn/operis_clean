// lib/services/company_info_service.dart
import 'dart:io';

class CompanyInfo {
  final String nombre;
  final String email;
  final String direccion;
  final int color; // ARGB
  final String? logoPath;

  const CompanyInfo({
    this.nombre = '',
    this.email = '',
    this.direccion = '',
    this.color = 0xFF00BCD4,
    this.logoPath,
  });

  CompanyInfo copyWith({
    String? nombre,
    String? email,
    String? direccion,
    int? color,
    String? logoPath,
  }) =>
      CompanyInfo(
        nombre: nombre ?? this.nombre,
        email: email ?? this.email,
        direccion: direccion ?? this.direccion,
        color: color ?? this.color,
        logoPath: logoPath ?? this.logoPath,
      );
}

class CompanyInfoService {
  static CompanyInfo _mem = const CompanyInfo();

  static Future<CompanyInfo> load() async => _mem;

  static Future<void> save(CompanyInfo info) async {
    _mem = info;
  }

  static Future<void> saveLogo(File file) async {
    _mem = _mem.copyWith(logoPath: file.path);
  }
}
