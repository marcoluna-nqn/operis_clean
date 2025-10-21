import 'package:flutter/foundation.dart';

/// Estados posibles de la licencia.
enum LicenseStatus { valid, trial, expired, invalid }

@immutable
class LicenseState {
  final LicenseStatus status;
  final DateTime? trialEndsAt;

  const LicenseState._(this.status, this.trialEndsAt);

  const LicenseState.valid()   : this._(LicenseStatus.valid,   null);
  const LicenseState.expired() : this._(LicenseStatus.expired, null);
  const LicenseState.invalid() : this._(LicenseStatus.invalid, null);

  /// Trial con fecha de fin (puede ser null si querés “sin fecha”).
  const LicenseState.trial({required DateTime? endsAt})
      : this._(LicenseStatus.trial, endsAt);

  bool get isTrialActive =>
      status == LicenseStatus.trial &&
          (trialEndsAt == null || DateTime.now().isBefore(trialEndsAt!));

  bool get isExpired =>
      status == LicenseStatus.expired ||
          (status == LicenseStatus.trial && !isTrialActive);

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'trialEndsAt': trialEndsAt?.toIso8601String(),
  };

  factory LicenseState.fromMap(Map<String, dynamic> map) {
    final statusName = (map['status'] as String?) ?? 'trial';
    final endIso = map['trialEndsAt'] as String?;
    final endsAt = endIso != null ? DateTime.tryParse(endIso) : null;
    final st = LicenseStatus.values.firstWhere(
            (e) => e.name == statusName, orElse: () => LicenseStatus.trial);
    switch (st) {
      case LicenseStatus.valid:   return const LicenseState.valid();
      case LicenseStatus.expired: return const LicenseState.expired();
      case LicenseStatus.invalid: return const LicenseState.invalid();
      case LicenseStatus.trial:   return LicenseState.trial(endsAt: endsAt);
    }
  }
}
