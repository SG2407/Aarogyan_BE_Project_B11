import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/profile_repository.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/section_header.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // Section 1 controllers
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

  final List<String> _sexOptions = ['Male', 'Female', 'Intersex'];
  final List<String> _bloodGroups = [
    'A+',
    'A−',
    'B+',
    'B−',
    'AB+',
    'AB−',
    'O+',
    'O−',
    'Unknown'
  ];
  final List<String> _languageOpts = [
    'English',
    'Hindi',
    'Marathi',
  ];

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _dobCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _cityCtrl.dispose();
    _regionCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final data = <String, dynamic>{};
      if (_fullNameCtrl.text.isNotEmpty)
        data['full_name'] = _fullNameCtrl.text.trim();
      if (_dobCtrl.text.isNotEmpty) data['date_of_birth'] = _dobCtrl.text;
      if (_sex != null) data['biological_sex'] = _sex;
      if (_heightCtrl.text.isNotEmpty)
        data['height_cm'] = double.tryParse(_heightCtrl.text);
      if (_weightCtrl.text.isNotEmpty)
        data['weight_kg'] = double.tryParse(_weightCtrl.text);
      if (_bloodGroup != null) data['blood_group'] = _bloodGroup;
      if (_cityCtrl.text.isNotEmpty) data['city'] = _cityCtrl.text.trim();
      if (_regionCtrl.text.isNotEmpty)
        data['region_state'] = _regionCtrl.text.trim();
      if (_preferredLanguage != null)
        data['preferred_language'] = _preferredLanguage;
      if (_emergencyNameCtrl.text.isNotEmpty)
        data['emergency_contact_name'] = _emergencyNameCtrl.text.trim();
      if (_emergencyPhoneCtrl.text.isNotEmpty)
        data['emergency_contact_phone'] = _emergencyPhoneCtrl.text.trim();

      await ref.read(profileRepositoryProvider).upsertProfile(data);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Your Profile'),
        actions: [
          TextButton(
            onPressed: () => context.go('/home'),
            child: Text('Skip',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5))),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProgress(),
                const SizedBox(height: 32),
                const SectionHeader(
                  title: 'Personal Information',
                  subtitle:
                      'This helps personalise your health recommendations',
                ),
                const SizedBox(height: 24),
                AppTextField(
                  controller: _fullNameCtrl,
                  label: 'Full Name',
                  hint: 'Your full name',
                ),
                const SizedBox(height: 16),
                _buildDateField(),
                const SizedBox(height: 16),
                _buildDropdown('Biological Sex', _sexOptions, _sex,
                    (v) => setState(() => _sex = v)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _heightCtrl,
                        label: 'Height (cm)',
                        keyboard: TextInputType.number,
                        hint: 'e.g. 170',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        controller: _weightCtrl,
                        label: 'Weight (kg)',
                        keyboard: TextInputType.number,
                        hint: 'e.g. 65',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDropdown('Blood Group', _bloodGroups, _bloodGroup,
                    (v) => setState(() => _bloodGroup = v)),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _cityCtrl,
                  label: 'City (optional)',
                  hint: 'Your city',
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _regionCtrl,
                  label: 'State / Region (optional)',
                  hint: 'e.g. Maharashtra',
                ),
                const SizedBox(height: 16),
                _buildDropdown(
                  'Preferred Language',
                  _languageOpts,
                  _preferredLanguage,
                  (v) => setState(() => _preferredLanguage = v),
                ),
                const SizedBox(height: 32),
                const SectionHeader(
                  title: 'Emergency Contact',
                  subtitle: 'Who should be contacted in a medical emergency?',
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _emergencyNameCtrl,
                  label: 'Contact Name (optional)',
                  hint: 'e.g. Jane Doe',
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _emergencyPhoneCtrl,
                  label: 'Contact Phone (optional)',
                  keyboard: TextInputType.phone,
                  hint: 'e.g. +91 98765 43210',
                ),
                const SizedBox(height: 40),
                AppButton(
                  label: 'Save & Continue',
                  onPressed: _saving ? null : _saveAndContinue,
                  isLoading: _saving,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text("I'll fill this later"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'A complete profile helps the AI give better, more personalised health guidance.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      controller: _dobCtrl,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Date of Birth',
        prefixIcon: Icon(Icons.calendar_today_outlined),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(1990),
          firstDate: DateTime(1900),
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
          _dobCtrl.text =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> options,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
