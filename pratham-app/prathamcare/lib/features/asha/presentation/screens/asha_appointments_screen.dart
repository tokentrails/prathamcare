import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
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

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFA),
        appBar: AppBar(
          title: const Text('Appointments'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: const Color(0xFF0B1220),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'New Requests'),
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: TabBarView(
                  children: [
                    _buildList(newRequests, 'No new appointment requests.'),
                    _buildList(upcoming, 'No upcoming appointments.'),
                    _buildList(completed, 'No completed appointments yet.'),
                  ],
                ),
              ),
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
            padding: const EdgeInsets.all(24),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final appointmentId = '${item['appointment_id'] ?? ''}'.trim();
        final status = '${item['status'] ?? ''}'.toLowerCase();
        final location = [
          '${item['village_or_ward'] ?? ''}'.trim(),
          '${item['block_or_taluk'] ?? ''}'.trim(),
          '${item['district'] ?? ''}'.trim(),
          '${item['state'] ?? ''}'.trim(),
        ].where((e) => e.isNotEmpty).join(', ');

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item['requestor_name'] ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Reason: ${item['reason_label'] ?? item['reason_code'] ?? '-'}'),
                Text(
                  'Preferred: ${item['preferred_date'] ?? '-'} ${item['preferred_time_slot'] ?? ''}',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                Text(
                  location.isEmpty ? 'Location not provided' : location,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (status == 'requested' || status == 'assigned')
                      OutlinedButton.icon(
                        onPressed: appointmentId.isEmpty ? null : () => _updateStatus(appointmentId, 'accepted'),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Accept'),
                      ),
                    if (status == 'requested' || status == 'assigned' || status == 'accepted')
                      OutlinedButton.icon(
                        onPressed: appointmentId.isEmpty
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Reschedule flow can be added with a date change endpoint.')),
                                );
                              },
                        icon: const Icon(Icons.event_repeat_rounded),
                        label: const Text('Reschedule'),
                      ),
                    if (status != 'completed' && status != 'cancelled')
                      OutlinedButton.icon(
                        onPressed: appointmentId.isEmpty ? null : () => _updateStatus(appointmentId, 'cancelled'),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel'),
                      ),
                    if (status == 'assigned' || status == 'accepted' || status == 'in_progress')
                      ElevatedButton.icon(
                        onPressed: appointmentId.isEmpty ? null : () => _startEncounter(appointmentId),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start Encounter'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
        status.replaceAll('_', ' '),
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}
