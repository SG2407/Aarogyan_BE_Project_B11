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
  final _dobCtrl = TextEditingController();
  String? _sex;
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String? _bloodGroup;
  final _cityCtrl = TextEditingController();

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

  @override
  void dispose() {
    _dobCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final data = <String, dynamic>{};
      if (_dobCtrl.text.isNotEmpty) data['date_of_birth'] = _dobCtrl.text;
      if (_sex != null) data['biological_sex'] = _sex;
      if (_heightCtrl.text.isNotEmpty)
        data['height_cm'] = double.tryParse(_heightCtrl.text);
      if (_weightCtrl.text.isNotEmpty)
        data['weight_kg'] = double.tryParse(_weightCtrl.text);
      if (_bloodGroup != null) data['blood_group'] = _bloodGroup;
      if (_cityCtrl.text.isNotEmpty) data['city'] = _cityCtrl.text.trim();

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Set Up Your Profile'),
        actions: [
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Skip',
                style: TextStyle(color: AppColors.textSecondary)),
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
        color: AppColors.secondary,
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
              colorScheme: const ColorScheme.light(primary: AppColors.primary),
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
