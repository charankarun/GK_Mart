import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../../core/errors/app_error_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/store_config.dart';
import '../../providers/store_providers.dart';
import '../../widgets/app_state_widgets.dart';

class StoreSettingsScreen extends ConsumerStatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  ConsumerState<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends ConsumerState<StoreSettingsScreen> {
  bool? _storeEnabled;
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  bool _initialized = false;

  void _initialize(StoreConfig config) {
    if (_initialized) return;
    _storeEnabled = config.storeEnabled;
    _openTime = TimeOfDay(hour: config.openHour, minute: config.openMinute);
    _closeTime = TimeOfDay(hour: config.closeHour, minute: config.closeMinute);
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(storeConfigProvider);
    final updateState = ref.watch(storeConfigUpdateControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Store Settings'),
      ),
      body: configAsync.when(
        data: (config) {
          _initialize(config);

          return updateState.when(
            data: (_) => _buildForm(context, updateState.isLoading),
            loading: () => _buildForm(context, true),
            error: (error, _) => Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.danger.withValues(alpha: 0.1),
                  child: Text(
                    AppErrorHandler.messageFor(error, fallback: 'Failed to save settings'),
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: _buildForm(context, false)),
              ],
            ),
          );
        },
        loading: () => const AppLoadingState(),
        error: (error, _) => AppRetryState(
          icon: Icons.error_outline_rounded,
          title: 'Unable to load settings',
          message: AppErrorHandler.messageFor(error),
          onRetry: () => ref.invalidate(storeConfigProvider),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, bool isLoading) {
    if (_storeEnabled == null || _openTime == null || _closeTime == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            side: const BorderSide(color: AppColors.border),
          ),
          color: AppColors.card,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                secondary: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _storeEnabled!
                        ? AppColors.softGreen
                        : AppColors.softOrange,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(
                    _storeEnabled!
                        ? Icons.storefront_rounded
                        : Icons.storefront_outlined,
                    color: _storeEnabled! ? AppColors.primary : AppColors.accent,
                  ),
                ),
                title: const Text(
                  'Store Active Status',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  _storeEnabled!
                      ? 'The store is active and accepting orders'
                      : 'The store is temporarily disabled',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                value: _storeEnabled!,
                onChanged: isLoading
                    ? null
                    : (val) {
                        setState(() => _storeEnabled = val);
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Operational Hours',
            style: TextStyle(
              color: AppColors.mutedText,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
        _TimeSelectorCard(
          title: 'Store Opens',
          time: _openTime!,
          icon: Icons.wb_sunny_outlined,
          iconColor: Colors.orange,
          isLoading: isLoading,
          onTap: () => _pickTime(true),
        ),
        const SizedBox(height: 12),
        _TimeSelectorCard(
          title: 'Store Closes',
          time: _closeTime!,
          icon: Icons.nightlight_round_outlined,
          iconColor: Colors.indigo,
          isLoading: isLoading,
          onTap: () => _pickTime(false),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              elevation: 0,
            ),
            onPressed: isLoading ? null : _saveSettings,
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save Settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickTime(bool isOpenTime) async {
    final initialTime = isOpenTime ? _openTime! : _closeTime!;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isOpenTime) {
        _openTime = picked;
      } else {
        _closeTime = picked;
      }
    });
  }

  Future<void> _saveSettings() async {
    if (_storeEnabled == null || _openTime == null || _closeTime == null) return;

    final config = StoreConfig(
      storeEnabled: _storeEnabled!,
      openHour: _openTime!.hour,
      openMinute: _openTime!.minute,
      closeHour: _closeTime!.hour,
      closeMinute: _closeTime!.minute,
    );

    await ref.read(storeConfigUpdateControllerProvider.notifier).updateConfig(config);

    if (!mounted) return;
    final state = ref.read(storeConfigUpdateControllerProvider);
    if (!state.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Store settings updated successfully!'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.of(context).pop();
    }
  }
}

class _TimeSelectorCard extends StatelessWidget {
  const _TimeSelectorCard({
    required this.title,
    required this.time,
    required this.icon,
    required this.iconColor,
    required this.isLoading,
    required this.onTap,
  });

  final String title;
  final TimeOfDay time;
  final IconData icon;
  final Color iconColor;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.card,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(time),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLoading)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.mutedText,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
