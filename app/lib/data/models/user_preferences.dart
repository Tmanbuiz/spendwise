/// Per-user settings that shape onboarding and reporting.
class UserPreferences {
  const UserPreferences({
    this.selectedBankIds = const <String>{},
    this.onboardingComplete = false,
    this.notificationAccessConfirmed = false,
    this.currency = 'CAD',
    this.monthStartDay = 1,
    this.autoCategorize = true,
  });

  /// Banks the user told us to watch. Notifications from other packages are
  /// ignored outright, which keeps unrelated apps out of the capture path.
  final Set<String> selectedBankIds;

  final bool onboardingComplete;

  /// The user has been through the permission screen and granted access at
  /// least once. The live permission state is always re-checked from Android;
  /// this only controls whether onboarding is shown again.
  final bool notificationAccessConfirmed;

  final String currency;

  /// Which day of the month a budget period starts on, for users whose pay
  /// cycle is not the 1st.
  final int monthStartDay;

  final bool autoCategorize;

  UserPreferences copyWith({
    Set<String>? selectedBankIds,
    bool? onboardingComplete,
    bool? notificationAccessConfirmed,
    String? currency,
    int? monthStartDay,
    bool? autoCategorize,
  }) {
    return UserPreferences(
      selectedBankIds: selectedBankIds ?? this.selectedBankIds,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      notificationAccessConfirmed:
          notificationAccessConfirmed ?? this.notificationAccessConfirmed,
      currency: currency ?? this.currency,
      monthStartDay: monthStartDay ?? this.monthStartDay,
      autoCategorize: autoCategorize ?? this.autoCategorize,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'selected_bank_ids': selectedBankIds.toList()..sort(),
        'onboarding_complete': onboardingComplete,
        'notification_access_confirmed': notificationAccessConfirmed,
        'currency': currency,
        'month_start_day': monthStartDay,
        'auto_categorize': autoCategorize,
      };

  static UserPreferences fromJson(Map<String, Object?> json) {
    final banks = (json['selected_bank_ids'] as List<Object?>?)
            ?.whereType<String>()
            .toSet() ??
        const <String>{};
    return UserPreferences(
      selectedBankIds: banks,
      onboardingComplete: (json['onboarding_complete'] as bool?) ?? false,
      notificationAccessConfirmed:
          (json['notification_access_confirmed'] as bool?) ?? false,
      currency: (json['currency'] as String?) ?? 'CAD',
      monthStartDay: (json['month_start_day'] as num?)?.toInt() ?? 1,
      autoCategorize: (json['auto_categorize'] as bool?) ?? true,
    );
  }
}
