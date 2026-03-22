import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_provider.dart';
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
  final _dobCtrl = TextEditingController();
  String? _sex;
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String? _bloodGroup;
  final _cityCtrl = TextEditingController();

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

  // Section 5: Recent vitals (local display only — not stored in backend)
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
    _dobCtrl.text = d['date_of_birth'] ?? '';
    _sex = d['biological_sex'];
    _heightCtrl.text = (d['height_cm'] ?? '').toString();
    _weightCtrl.text = (d['weight_kg'] ?? '').toString();
    _bloodGroup = d['blood_group'];
    _cityCtrl.text = d['city'] ?? '';

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
        if (_dobCtrl.text.isNotEmpty) 'date_of_birth': _dobCtrl.text,
        if (_sex != null) 'biological_sex': _sex,
        if (_heightCtrl.text.isNotEmpty)
          'height_cm': double.tryParse(_heightCtrl.text),
        if (_weightCtrl.text.isNotEmpty)
          'weight_kg': double.tryParse(_weightCtrl.text),
        if (_bloodGroup != null) 'blood_group': _bloodGroup,
        if (_cityCtrl.text.isNotEmpty) 'city': _cityCtrl.text,
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
      });
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved!')),
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
      _dobCtrl,
      _heightCtrl,
      _weightCtrl,
      _cityCtrl,
      _conditionsCtrl,
      _allergiesCtrl,
      _surgeriesCtrl,
      _familyHistoryCtrl,
      _dietCtrl,
      _sleepCtrl,
      _medicationsCtrl,
      _supplementsCtrl,
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
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
              return IconButton(
                tooltip: isDark ? 'Switch to Light' : 'Switch to Dark',
                icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
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
          const SectionHeader(title: 'Personal Information'),
          const SizedBox(height: 12),
          _DateField(controller: _dobCtrl, label: 'Date of Birth'),
          const SizedBox(height: 12),
          _DropdownField(
            label: 'Biological Sex',
            value: _sex,
            items: _sexOptions,
            onChanged: (v) => setState(() => _sex = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: AppTextField(
                    controller: _heightCtrl,
                    label: 'Height (cm)',
                    keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(
                child: AppTextField(
                    controller: _weightCtrl,
                    label: 'Weight (kg)',
                    keyboard: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          _DropdownField(
            label: 'Blood Group',
            value: _bloodGroup,
            items: _bloodGroups,
            onChanged: (v) => setState(() => _bloodGroup = v),
          ),
          const SizedBox(height: 12),
          AppTextField(controller: _cityCtrl, label: 'City'),
          const SizedBox(height: 24),

          // Medical History
          const SectionHeader(title: 'Medical History'),
          const SizedBox(height: 12),
          AppTextField(
            controller: _conditionsCtrl,
            label: 'Chronic Conditions (comma-separated)',
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _allergiesCtrl,
            label: 'Allergies (comma-separated)',
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _surgeriesCtrl,
            label: 'Past Surgeries (comma-separated)',
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _familyHistoryCtrl,
            label: 'Family History (comma-separated)',
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          // Lifestyle
          const SectionHeader(title: 'Lifestyle'),
          const SizedBox(height: 12),
          _DropdownField(
            label: 'Smoking Status',
            value: _smokingStatus,
            items: _smokingOpts,
            onChanged: (v) => setState(() => _smokingStatus = v),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: 'Alcohol Use',
            value: _alcoholUse,
            items: _alcoholOpts,
            onChanged: (v) => setState(() => _alcoholUse = v),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: 'Activity Level',
            value: _activityLevel,
            items: _activityOpts,
            onChanged: (v) => setState(() => _activityLevel = v),
          ),
          const SizedBox(height: 12),
          AppTextField(
              controller: _dietCtrl, label: 'Diet Type (e.g. Vegetarian)'),
          const SizedBox(height: 12),
          AppTextField(
              controller: _sleepCtrl,
              label: 'Sleep Hours/Night',
              keyboard: TextInputType.number),
          const SizedBox(height: 24),

          // Current Medications
          const SectionHeader(title: 'Current Medications'),
          const SizedBox(height: 12),
          AppTextField(
            controller: _medicationsCtrl,
            label: 'Medications (one per line)',
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _supplementsCtrl,
            label: 'Supplements (one per line)',
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // Vitals
          const SectionHeader(title: 'Recent Vitals'),
          const SizedBox(height: 12),
          AppTextField(
              controller: _bpCtrl, label: 'Blood Pressure (e.g. 120/80)'),
          const SizedBox(height: 12),
          AppTextField(
              controller: _sugarCtrl,
              label: 'Blood Sugar (mg/dL)',
              keyboard: TextInputType.number),
          const SizedBox(height: 12),
          AppTextField(
              controller: _cholesterolCtrl,
              label: 'Cholesterol (mg/dL)',
              keyboard: TextInputType.number),
          const SizedBox(height: 12),
          AppTextField(
              controller: _spo2Ctrl,
              label: 'SpO2 (%)',
              keyboard: TextInputType.number),
          const SizedBox(height: 32),

          AppButton(
            label: _saving ? 'Saving...' : 'Save Profile',
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text('Log Out', style: TextStyle(color: Colors.red)),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log Out'),
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
              colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary),
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
