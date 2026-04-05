import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../data/profile_repository.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../auth/presentation/auth_notifier.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loading = true;
  bool _saving = false;

  // Section 1: Personal
  final _fullNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  String? _sex;
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String? _bloodGroup;
  final _cityCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  String? _preferredLanguage;
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  // Section 2: Medical history
  final _conditionsCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _surgeriesCtrl = TextEditingController();
  final _familyHistoryCtrl = TextEditingController();

  // Section 3: Lifestyle
  String? _smokingStatus;
  String? _alcoholUse;
  String? _activityLevel;
  final _dietCtrl = TextEditingController();
  final _sleepCtrl = TextEditingController();

  // Section 4: Current medications
  final _medicationsCtrl = TextEditingController();
  final _supplementsCtrl = TextEditingController();

  // Section 5: Mental health
  String? _stressLevel;
  String? _anxietyLevel;
  String? _depressionLevel;
  String? _therapyOngoing;
  final _mentalNotesCtrl = TextEditingController();

  // Section 6: Recent vitals (local display only — not stored in backend)
  final _bpCtrl = TextEditingController();
  final _sugarCtrl = TextEditingController();
  final _cholesterolCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();

  static const _sexOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];
  static const _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
    'Unknown'
  ];
  static const _smokingOpts = ['Never', 'Former', 'Occasional', 'Daily'];
  static const _alcoholOpts = ['None', 'Occasional', 'Moderate', 'Heavy'];
  static const _activityOpts = [
    'Sedentary',
    'Lightly Active',
    'Moderately Active',
    'Very Active'
  ];
  static const _stressOpts = ['Low', 'Moderate', 'High'];
  static const _anxietyOpts = ['None', 'Mild', 'Moderate', 'Severe'];
  static const _depressionOpts = ['None', 'Mild', 'Moderate', 'Severe'];
  static const _therapyOpts = ['Yes', 'No'];
  static const _languageOpts = [
    'English',
    'Hindi',
    'Marathi',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      final data = await repo.getProfile();
      _populateFromData(data);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _populateFromData(Map<String, dynamic> d) {
    _fullNameCtrl.text = d['full_name'] ?? '';
    _dobCtrl.text = d['date_of_birth'] ?? '';
    _sex = d['biological_sex'];
    _heightCtrl.text = (d['height_cm'] ?? '').toString();
    _weightCtrl.text = (d['weight_kg'] ?? '').toString();
    _bloodGroup = d['blood_group'];
    _cityCtrl.text = d['city'] ?? '';
    _regionCtrl.text = d['region_state'] ?? '';
    _preferredLanguage = d['preferred_language'];
    _emergencyNameCtrl.text = d['emergency_contact_name'] ?? '';
    _emergencyPhoneCtrl.text = d['emergency_contact_phone'] ?? '';

    final conditions = d['existing_conditions'] as List? ?? [];
    _conditionsCtrl.text =
        conditions.map((e) => e['condition_name'] ?? '').join(', ');

    final allergies = d['allergies'] as List? ?? [];
    _allergiesCtrl.text =
        allergies.map((e) => e['allergy_name'] ?? '').join(', ');

    final surgeries = d['past_medical_history'] as List? ?? [];
    _surgeriesCtrl.text =
        surgeries.map((e) => e['description'] ?? '').join(', ');

    final family = d['family_medical_history'] as List? ?? [];
    _familyHistoryCtrl.text =
        family.map((e) => e['condition_name'] ?? '').join(', ');

    final life = d['lifestyle'] as Map<String, dynamic>? ?? {};
    _smokingStatus = life['smoking_status'];
    _alcoholUse = life['alcohol_consumption'];
    _activityLevel = life['activity_level'];
    _dietCtrl.text = life['dietary_preference'] ?? '';
    _sleepCtrl.text = (life['avg_sleep_hours'] ?? '').toString();

    final meds = d['current_medications'] as List? ?? [];
    _medicationsCtrl.text =
        meds.map((e) => e['medication_name'] ?? '').join('\n');

    final supps = d['supplements'] as List? ?? [];
    _supplementsCtrl.text =
        supps.map((e) => e['supplement_name'] ?? '').join('\n');

    final mental = d['mental_health'] as Map<String, dynamic>? ?? {};
    _stressLevel = mental['stress_level'];
    _anxietyLevel = mental['anxiety_level'];
    _depressionLevel = mental['depression_screening'];
    _therapyOngoing = mental['therapy_ongoing'];
    _mentalNotesCtrl.text = mental['notes'] ?? '';

    // vitals fields don't exist in backend model — leave empty
    _bpCtrl.text = '';
    _sugarCtrl.text = '';
    _cholesterolCtrl.text = '';
    _spo2Ctrl.text = '';
  }

  List<String> _splitList(String raw) =>
      raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.updateProfile({
        if (_fullNameCtrl.text.isNotEmpty)
          'full_name': _fullNameCtrl.text.trim(),
        if (_dobCtrl.text.isNotEmpty) 'date_of_birth': _dobCtrl.text,
        if (_sex != null) 'biological_sex': _sex,
        if (_heightCtrl.text.isNotEmpty)
          'height_cm': double.tryParse(_heightCtrl.text),
        if (_weightCtrl.text.isNotEmpty)
          'weight_kg': double.tryParse(_weightCtrl.text),
        if (_bloodGroup != null) 'blood_group': _bloodGroup,
        if (_cityCtrl.text.isNotEmpty) 'city': _cityCtrl.text.trim(),
        if (_regionCtrl.text.isNotEmpty)
          'region_state': _regionCtrl.text.trim(),
        if (_preferredLanguage != null)
          'preferred_language': _preferredLanguage,
        if (_emergencyNameCtrl.text.isNotEmpty)
          'emergency_contact_name': _emergencyNameCtrl.text.trim(),
        if (_emergencyPhoneCtrl.text.isNotEmpty)
          'emergency_contact_phone': _emergencyPhoneCtrl.text.trim(),
        // existing_conditions: list of {condition_name}
        if (_conditionsCtrl.text.isNotEmpty)
          'existing_conditions': _splitList(_conditionsCtrl.text)
              .map((e) => {'condition_name': e})
              .toList(),
        // allergies: list of {allergy_type, allergy_name}
        if (_allergiesCtrl.text.isNotEmpty)
          'allergies': _splitList(_allergiesCtrl.text)
              .map((e) => {'allergy_type': 'Other', 'allergy_name': e})
              .toList(),
        // past_medical_history: list of {history_type, description}
        if (_surgeriesCtrl.text.isNotEmpty)
          'past_medical_history': _splitList(_surgeriesCtrl.text)
              .map((e) => {'history_type': 'Surgery', 'description': e})
              .toList(),
        // family_medical_history: list of {condition_name, relation}
        if (_familyHistoryCtrl.text.isNotEmpty)
          'family_medical_history': _splitList(_familyHistoryCtrl.text)
              .map((e) => {'condition_name': e, 'relation': 'Unknown'})
              .toList(),
        // current_medications: list of {medication_name, dosage, frequency}
        if (_medicationsCtrl.text.trim().isNotEmpty)
          'current_medications': _medicationsCtrl.text
              .split('\n')
              .where((e) => e.trim().isNotEmpty)
              .map((e) => {
                    'medication_name': e.trim(),
                    'dosage': '-',
                    'frequency': '-'
                  })
              .toList(),
        // supplements: list of {supplement_name}
        if (_supplementsCtrl.text.trim().isNotEmpty)
          'supplements': _supplementsCtrl.text
              .split('\n')
              .where((e) => e.trim().isNotEmpty)
              .map((e) => {'supplement_name': e.trim()})
              .toList(),
        // lifestyle object
        'lifestyle': {
          if (_smokingStatus != null) 'smoking_status': _smokingStatus,
          if (_alcoholUse != null) 'alcohol_consumption': _alcoholUse,
          if (_activityLevel != null) 'activity_level': _activityLevel,
          if (_dietCtrl.text.isNotEmpty) 'dietary_preference': _dietCtrl.text,
          if (_sleepCtrl.text.isNotEmpty)
            'avg_sleep_hours': double.tryParse(_sleepCtrl.text),
        },
        // mental_health object
        'mental_health': {
          if (_stressLevel != null) 'stress_level': _stressLevel,
          if (_anxietyLevel != null) 'anxiety_level': _anxietyLevel,
          if (_depressionLevel != null)
            'depression_screening': _depressionLevel,
          if (_therapyOngoing != null) 'therapy_ongoing': _therapyOngoing,
          if (_mentalNotesCtrl.text.isNotEmpty)
            'notes': _mentalNotesCtrl.text.trim(),
        },
      });
      ref.invalidate(profileProvider);
      if (mounted) {
        final lang = ref.read(preferredLanguageProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appStr(lang, 'profile_saved'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _fullNameCtrl,
      _dobCtrl,
      _heightCtrl,
      _weightCtrl,
      _cityCtrl,
      _regionCtrl,
      _emergencyNameCtrl,
      _emergencyPhoneCtrl,
      _conditionsCtrl,
      _allergiesCtrl,
      _surgeriesCtrl,
      _familyHistoryCtrl,
      _dietCtrl,
      _sleepCtrl,
      _medicationsCtrl,
      _supplementsCtrl,
      _mentalNotesCtrl,
      _bpCtrl,
      _sugarCtrl,
      _cholesterolCtrl,
      _spo2Ctrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(preferredLanguageProvider);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appStr(lang, 'my_profile')),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
              return IconButton(
                tooltip: isDark
                    ? appStr(lang, 'switch_to_light')
                    : appStr(lang, 'switch_to_dark'),
                icon: Icon(isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded),
                onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Personal
          SectionHeader(title: appStr(lang, 'personal_info')),
          const SizedBox(height: 12),
          AppTextField(
              controller: _fullNameCtrl, label: appStr(lang, 'full_name')),
          const SizedBox(height: 12),
          _DateField(
              controller: _dobCtrl, label: appStr(lang, 'date_of_birth')),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'biological_sex'),
            value: _sex,
            items: _sexOptions,
            onChanged: (v) => setState(() => _sex = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: AppTextField(
                    controller: _heightCtrl,
                    label: appStr(lang, 'height_cm'),
                    keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(
                child: AppTextField(
                    controller: _weightCtrl,
                    label: appStr(lang, 'weight_kg'),
                    keyboard: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'blood_group'),
            value: _bloodGroup,
            items: _bloodGroups,
            onChanged: (v) => setState(() => _bloodGroup = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: AppTextField(
                    controller: _cityCtrl, label: appStr(lang, 'city'))),
            const SizedBox(width: 12),
            Expanded(
                child: AppTextField(
                    controller: _regionCtrl,
                    label: appStr(lang, 'state_region'))),
          ]),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'preferred_language'),
            value: _preferredLanguage,
            items: _languageOpts,
            onChanged: (v) => setState(() => _preferredLanguage = v),
          ),
          const SizedBox(height: 24),

          // Emergency Contact
          SectionHeader(
            title: appStr(lang, 'emergency_contact'),
            subtitle: appStr(lang, 'emergency_contact_sub'),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _emergencyNameCtrl,
            label: appStr(lang, 'contact_name'),
            hint: appStr(lang, 'contact_name_hint'),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _emergencyPhoneCtrl,
            label: appStr(lang, 'contact_phone'),
            keyboard: TextInputType.phone,
          ),
          const SizedBox(height: 24),

          // Medical History
          SectionHeader(title: appStr(lang, 'medical_history')),
          const SizedBox(height: 12),
          AppTextField(
            controller: _conditionsCtrl,
            label: appStr(lang, 'chronic_conditions'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _allergiesCtrl,
            label: appStr(lang, 'allergies_label'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _surgeriesCtrl,
            label: appStr(lang, 'past_surgeries'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _familyHistoryCtrl,
            label: appStr(lang, 'family_history'),
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          // Lifestyle
          SectionHeader(title: appStr(lang, 'lifestyle')),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'smoking_status'),
            value: _smokingStatus,
            items: _smokingOpts,
            onChanged: (v) => setState(() => _smokingStatus = v),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'alcohol_use'),
            value: _alcoholUse,
            items: _alcoholOpts,
            onChanged: (v) => setState(() => _alcoholUse = v),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'activity_level'),
            value: _activityLevel,
            items: _activityOpts,
            onChanged: (v) => setState(() => _activityLevel = v),
          ),
          const SizedBox(height: 12),
          AppTextField(controller: _dietCtrl, label: appStr(lang, 'diet_type')),
          const SizedBox(height: 12),
          AppTextField(
              controller: _sleepCtrl,
              label: appStr(lang, 'sleep_hours'),
              keyboard: TextInputType.number),
          const SizedBox(height: 24),

          // Current Medications
          SectionHeader(title: appStr(lang, 'current_medications')),
          const SizedBox(height: 12),
          AppTextField(
            controller: _medicationsCtrl,
            label: appStr(lang, 'medications_label'),
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _supplementsCtrl,
            label: appStr(lang, 'supplements_label'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // Mental Health
          SectionHeader(
            title: appStr(lang, 'mental_title'),
            subtitle: appStr(lang, 'mental_health_sub'),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'stress_level'),
            value: _stressLevel,
            items: _stressOpts,
            onChanged: (v) => setState(() => _stressLevel = v),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'anxiety_level'),
            value: _anxietyLevel,
            items: _anxietyOpts,
            onChanged: (v) => setState(() => _anxietyLevel = v),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'depression_screening'),
            value: _depressionLevel,
            items: _depressionOpts,
            onChanged: (v) => setState(() => _depressionLevel = v),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: appStr(lang, 'therapy_ongoing'),
            value: _therapyOngoing,
            items: _therapyOpts,
            onChanged: (v) => setState(() => _therapyOngoing = v),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _mentalNotesCtrl,
            label: appStr(lang, 'mental_notes'),
            hint: appStr(lang, 'mental_notes_hint'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // Vitals
          SectionHeader(title: appStr(lang, 'recent_vitals')),
          const SizedBox(height: 12),
          AppTextField(
              controller: _bpCtrl, label: appStr(lang, 'blood_pressure')),
          const SizedBox(height: 12),
          AppTextField(
              controller: _sugarCtrl,
              label: appStr(lang, 'blood_sugar'),
              keyboard: TextInputType.number),
          const SizedBox(height: 12),
          AppTextField(
              controller: _cholesterolCtrl,
              label: appStr(lang, 'cholesterol'),
              keyboard: TextInputType.number),
          const SizedBox(height: 12),
          AppTextField(
              controller: _spo2Ctrl,
              label: appStr(lang, 'spo2'),
              keyboard: TextInputType.number),
          const SizedBox(height: 32),

          AppButton(
            label:
                _saving ? appStr(lang, 'saving') : appStr(lang, 'save_profile'),
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.red),
            label: Text(appStr(lang, 'log_out'),
                style: const TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final lang = ref.read(preferredLanguageProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appStr(lang, 'log_out_title')),
        content: Text(appStr(lang, 'log_out_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(appStr(lang, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(appStr(lang, 'log_out')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authNotifierProvider.notifier).logout();
    }
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      onChanged: onChanged,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items:
          items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
    );
  }
}

class _DateField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  const _DateField({required this.controller, required this.label});

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.cake_outlined),
      ),
      onTap: () async {
        final initial =
            DateTime.tryParse(widget.controller.text) ?? DateTime(1990);
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1920),
          lastDate: DateTime.now(),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(ctx)
                  .colorScheme
                  .copyWith(primary: AppColors.primary),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          widget.controller.text =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          setState(() {});
        }
      },
    );
  }
}
