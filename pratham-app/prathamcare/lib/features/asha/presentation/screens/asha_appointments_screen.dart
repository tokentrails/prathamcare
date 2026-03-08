import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../data/network/api_client.dart';
import 'voice_visit_screen.dart';

class ASHAAppointmentsScreen extends StatefulWidget {
  const ASHAAppointmentsScreen({super.key});

  @override
  State<ASHAAppointmentsScreen> createState() => _ASHAAppointmentsScreenState();
}

class _ASHAAppointmentsScreenState extends State<ASHAAppointmentsScreen> {
  final ApiClient _apiClient = ApiClient();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _allItems = const [];
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _apiClient.getASHAAppointments(limit: 50);
      if (!mounted) return;
      setState(() {
        _allItems = _asMapList(res['items']);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _updateStatus(String appointmentId, String status) async {
    try {
      await _apiClient.updateAppointmentStatus(appointmentId: appointmentId, status: status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appointment marked $status.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${e.code}: ${e.message}')),
      );
    }
  }

  Future<void> _startEncounter(String appointmentId) async {
    try {
      final res = await _apiClient.startAppointmentEncounter(appointmentId: appointmentId);
      final launch = (res['launch'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final patientId = '${launch['patient_id'] ?? ''}'.trim();
      if (patientId.isEmpty || !mounted) {
        return;
      }
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => VoiceVisitScreen(
            patientId: patientId,
            appointmentId: appointmentId,
            appointmentContext: (res['appointment'] as Map?)?.cast<String, dynamic>(),
          ),
        ),
      );
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Encounter submitted and appointment closed.')),
        );
        await _load();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${e.code}: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final newRequests = _allItems.where((e) {
      final s = '${e['status'] ?? ''}'.toLowerCase();
      return s == 'requested' || s == 'assigned';
    }).toList();
    final upcoming = _allItems.where((e) {
      final s = '${e['status'] ?? ''}'.toLowerCase();
      return s == 'accepted' || s == 'in_progress';
    }).toList();
    final completed = _allItems.where((e) {
      final s = '${e['status'] ?? ''}'.toLowerCase();
      return s == 'completed' || s == 'cancelled';
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Appointments'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0B1220),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: _buildSegmentedControl(),
                  ),
                  Expanded(
                    child: _selectedTab == 0
                        ? _buildList(newRequests, 'No new appointment requests.')
                        : _selectedTab == 1
                            ? _buildList(upcoming, 'No upcoming appointments.')
                            : _buildList(completed, 'No completed appointments yet.'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSegmentedControl() {
    const tabs = ['New Requests', 'Upcoming', 'Completed'];
    const outerHeight = 52.0;
    const inset = 6.0;
    const gap = 4.0;
    const segmentRadius = 24.0;
    const segmentHeight = outerHeight - (inset * 2);

    return SizedBox(
      height: outerHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = (constraints.maxWidth - (inset * 2) - (gap * 2)) / 3;
          final selectedLeft = inset + _selectedTab * (segmentWidth + gap);

          return ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: ColoredBox(
              color: const Color(0x99E2E8F0),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    top: inset,
                    left: selectedLeft,
                    width: segmentWidth,
                    height: segmentHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(segmentRadius),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0D000000),
                            blurRadius: 0,
                            spreadRadius: 1,
                          ),
                          BoxShadow(
                            color: Color(0x0D000000),
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(inset),
                      child: Row(
                        children: [
                          for (var i = 0; i < tabs.length; i++) ...[
                            if (i > 0) const SizedBox(width: gap),
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() => _selectedTab = i),
                                borderRadius: BorderRadius.circular(segmentRadius),
                                child: Center(
                                  child: Text(
                                    tabs[i],
                                    style: TextStyle(
                                      color: i == _selectedTab ? AppColors.primary : const Color(0xFF475569),
                                      fontSize: 13,
                                      height: 1.2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, String emptyText) {
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _ErrorCard(message: _error!),
          ),
        ],
      );
    }
    if (items.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 16),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final appointmentId = '${item['appointment_id'] ?? ''}'.trim();
        final status = '${item['status'] ?? ''}'.toLowerCase();
        final locationParts = [
          '${item['village_or_ward'] ?? ''}'.trim(),
          '${item['block_or_taluk'] ?? ''}'.trim(),
          '${item['district'] ?? ''}'.trim(),
          '${item['state'] ?? ''}'.trim(),
        ].where((e) => e.isNotEmpty).toList();
        final location = locationParts.join(', ');

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F756D),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: const Center(
                      child: Icon(Icons.person_outline_rounded, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['requestor_name'] ?? '-'}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _StatusChip(status: status),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildInfoRow(Icons.medical_information_outlined, 'Reason', '${item['reason_label'] ?? item['reason_code'] ?? '-'}'),
              const SizedBox(height: 10),
              _buildInfoRow(Icons.calendar_today_outlined, 'Preferred', '${item['preferred_date'] ?? '-'} ${item['preferred_time_slot'] ?? ''}'),
              const SizedBox(height: 10),
              _buildInfoRow(Icons.location_on_outlined, 'Location', location.isEmpty ? 'Not provided' : location),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (status != 'completed' && status != 'cancelled')
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: (status == 'requested' || status == 'assigned' || status == 'accepted' || status == 'in_progress') ? 8.0 : 0.0),
                        child: AppPillButton(
                          onPressed: appointmentId.isEmpty ? null : () => _updateStatus(appointmentId, 'cancelled'),
                          icon: Icons.close_rounded,
                          label: 'Cancel',
                          variant: AppPillButtonVariant.light,
                          height: 44,
                        ),
                      ),
                    ),
                  if (status == 'requested' || status == 'assigned')
                    Expanded(
                      flex: 2,
                      child: AppPillButton(
                        onPressed: appointmentId.isEmpty ? null : () => _updateStatus(appointmentId, 'accepted'),
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Accept',
                        variant: AppPillButtonVariant.primary,
                        height: 44,
                      ),
                    ),
                  if (status == 'accepted' || status == 'in_progress')
                    Expanded(
                      flex: 2,
                      child: AppPillButton(
                        onPressed: appointmentId.isEmpty ? null : () => _startEncounter(appointmentId),
                        icon: Icons.play_arrow_rounded,
                        label: 'Start Encounter',
                        variant: AppPillButtonVariant.dark,
                        height: 44,
                      ),
                    ),
                ],
              ),
              if (status == 'requested' || status == 'assigned' || status == 'accepted') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: appointmentId.isEmpty
                        ? null
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Reschedule flow can be added with a date change endpoint.')),
                            );
                          },
                    icon: const Icon(Icons.event_repeat_rounded, size: 18),
                    label: const Text('Reschedule'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.lightPlaceholder),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.lightTextSecondary),
              children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: value, style: const TextStyle(color: AppColors.lightTextPrimary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static List<Map<String, dynamic>> _asMapList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.lightError),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isDone = status == 'completed';
    final isCancel = status == 'cancelled';
    final bg = isDone
        ? const Color(0xFFDCFCE7)
        : isCancel
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFE0F2FE);
    final fg = isDone
        ? const Color(0xFF166534)
        : isCancel
            ? const Color(0xFF991B1B)
            : const Color(0xFF075985);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w800, letterSpacing: 0.5),
      ),
    );
  }
}
