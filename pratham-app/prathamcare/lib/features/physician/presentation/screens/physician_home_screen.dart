import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class PhysicianHomeScreen extends StatefulWidget {
  const PhysicianHomeScreen({super.key});

  @override
  State<PhysicianHomeScreen> createState() => _PhysicianHomeScreenState();
}

class _PhysicianHomeScreenState extends State<PhysicianHomeScreen> {
  int selectedBottomTab = 0;
  int selectedFilter = 0;

  static const filterLabels = ['All', 'Upcoming', 'Pending', 'Critical'];

  final List<_Appointment> appointments = const [
    _Appointment(
      patientName: 'Ram Kumar',
      details: 'Male, 45  •  #PT-2983',
      time: '09:30 AM',
      visitType: 'Video Visit',
      status: 'Critical',
      accentColor: Color(0xFFEF4444),
      statusBg: Color(0xFFFEF2F2),
      statusFg: Color(0xFFDC2626),
    ),
    _Appointment(
      patientName: 'Anita Desai',
      details: 'Female, 32  •  #PT-4102',
      time: '10:15 AM',
      visitType: 'In-Person',
      status: 'Follow-up',
      accentColor: AppColors.primary,
      statusBg: Color(0x1A0F756D),
      statusFg: AppColors.primary,
    ),
    _Appointment(
      patientName: 'Vikram Singh',
      details: 'Male, 58  •  #PT-9921',
      time: '11:00 AM',
      visitType: 'In-Person',
      status: 'New Patient',
      accentColor: Color(0xFF60A5FA),
      statusBg: Color(0xFFEFF6FF),
      statusFg: Color(0xFF2563EB),
    ),
  ];

  List<_Appointment> get visibleAppointments {
    switch (selectedFilter) {
      case 1:
        return appointments.where((a) => a.status == 'Follow-up' || a.status == 'New Patient').toList();
      case 2:
        return appointments.where((a) => a.status == 'Follow-up').toList();
      case 3:
        return appointments.where((a) => a.status == 'Critical').toList();
      default:
        return appointments;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F8),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildAIBriefingCard()),
            SliverToBoxAdapter(child: _buildQuickActions()),
            SliverToBoxAdapter(child: _buildPendingActions()),
            SliverToBoxAdapter(child: _buildScheduleSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 130)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTap('Voice capture'),
        elevation: 8,
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.mic_none_rounded, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFFE5E7EB),
                    child: Icon(Icons.person, color: Color(0xFF0E1B1A)),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        border: Border.all(color: Colors.white, width: 2),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dr. Sharma',
                      style: TextStyle(
                        color: Color(0xFF0E1B1A),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Cardiology Dept.',
                      style: TextStyle(
                        color: Color(0xFF4F9690),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _logout,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.logout_rounded, size: 20, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final selected = index == selectedFilter;
                return InkWell(
                  onTap: () => setState(() => selectedFilter = index),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: selected ? null : Border.all(color: const Color(0xFFF3F4F6)),
                      boxShadow: selected
                          ? const [
                              BoxShadow(
                                color: Color(0x330F756D),
                                blurRadius: 15,
                                offset: Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      filterLabels[index],
                      style: TextStyle(
                        color: selected ? Colors.white : const Color(0xFF4F9690),
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemCount: filterLabels.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIBriefingCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F756D),
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 6,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF0F756D), Color(0xFF38BDF8)]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Color(0x1A0F756D),
                        child: Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'AI CLINICAL BRIEFING',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Morning Insights',
                    style: TextStyle(
                      color: Color(0xFF0E1B1A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text.rich(
                    TextSpan(
                      style: TextStyle(color: Color(0xFF4F9690), fontSize: 14, height: 1.6),
                      children: [
                        TextSpan(text: 'Analysis of overnight labs indicates '),
                        TextSpan(
                          text: '3 patients',
                          style: TextStyle(color: Color(0xFF0E1B1A), fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: ' with critical lipid profiles. Immediate review suggested for HbA1c anomalies in Ward 4.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _showTap('View full report'),
                    borderRadius: BorderRadius.circular(32),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x0D0F756D),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'View Full Report',
                            style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _quickAction(
              title: 'Start Encounter',
              icon: Icons.health_and_safety_outlined,
              selected: true,
              onTap: () => _showTap('Start encounter'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _quickAction(
              title: 'Quick Note',
              icon: Icons.note_alt_outlined,
              selected: false,
              onTap: () => _showTap('Quick note'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction({
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(48),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(48),
          border: selected ? null : Border.all(color: const Color(0xFFF3F4F6)),
          boxShadow: [
            BoxShadow(
              color: selected ? const Color(0x400F756D) : const Color(0x140F756D),
              blurRadius: selected ? 15 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : AppColors.primary, size: 22),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingActions() {
    final items = const [
      ('Lab Results', '5', Icons.description_outlined, Color(0xFFFF7A1A), Color(0xFFFFF7ED)),
      ('Prescriptions', '12', Icons.medication_outlined, Color(0xFF3B82F6), Color(0xFFEFF6FF)),
      ('Referrals', '3', Icons.folder_shared_outlined, Color(0xFF8B5CF6), Color(0xFFF5F3FF)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Pending Actions',
              style: TextStyle(color: Color(0xFF0E1B1A), fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 134,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: () => _showTap(item.$1),
                  child: Container(
                    width: 110,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: const Color(0xFFF9FAFB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: item.$5,
                          child: Icon(item.$3, size: 16, color: item.$4),
                        ),
                        Text(item.$2, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                        Text(item.$1, style: const TextStyle(color: Color(0xFF4F9690), fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    "Today's Schedule",
                    style: TextStyle(color: Color(0xFF0E1B1A), fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _showTap('See all schedule'),
                child: const Text(
                  'See All',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...visibleAppointments.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _appointmentCard(a),
              )),
        ],
      ),
    );
  }

  Widget _appointmentCard(_Appointment appointment) {
    final isVideo = appointment.visitType == 'Video Visit';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFFF9FAFB)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 6,
              decoration: BoxDecoration(color: appointment.accentColor, borderRadius: BorderRadius.circular(6)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 17, 17, 12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(radius: 24, backgroundColor: Color(0xFFF3F4F6), child: Icon(Icons.person)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appointment.patientName,
                            style: const TextStyle(color: Color(0xFF0E1B1A), fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            appointment.details,
                            style: const TextStyle(color: Color(0xFF4F9690), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: appointment.statusBg, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        appointment.status,
                        style: TextStyle(color: appointment.statusFg, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF9FAFB)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 15, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      appointment.time,
                      style: const TextStyle(color: Color(0xFF0E1B1A), fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 16),
                    Icon(isVideo ? Icons.videocam_outlined : Icons.location_on_outlined, size: 15, color: const Color(0xFF4F9690)),
                    const SizedBox(width: 6),
                    Text(
                      appointment.visitType,
                      style: const TextStyle(color: Color(0xFF4F9690), fontSize: 12),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      onSelected: _showTap,
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'Open patient', child: Text('Open patient')),
                        PopupMenuItem(value: 'Reschedule', child: Text('Reschedule')),
                        PopupMenuItem(value: 'Cancel', child: Text('Cancel')),
                      ],
                      icon: const Icon(Icons.more_vert, color: AppColors.primary, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = const [
      ('Home', Icons.home_outlined),
      ('Schedule', Icons.calendar_month_outlined),
      ('Patients', Icons.groups_outlined),
      ('Profile', Icons.person_outline_rounded),
    ];

    return BottomAppBar(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 6,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(2, (i) => _navItem(i, items[i].$1, items[i].$2)),
            ),
          ),
          const SizedBox(width: 56),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(2, (i) {
                final idx = i + 2;
                return _navItem(idx, items[idx].$1, items[idx].$2);
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, String label, IconData icon) {
    final active = index == selectedBottomTab;
    return InkWell(
      onTap: () async {
        setState(() => selectedBottomTab = index);
        if (label == 'Profile') {
          await Navigator.of(context).pushNamed('/profile');
          if (!mounted) {
            return;
          }
          setState(() => selectedBottomTab = 0);
          return;
        }
        _showTap(label);
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: active ? AppColors.primary : const Color(0xFF4F9690)),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.primary : const Color(0xFF4F9690),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTap(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(action), duration: const Duration(milliseconds: 900)),
    );
  }

  void _logout() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }
}

class _Appointment {
  final String patientName;
  final String details;
  final String time;
  final String visitType;
  final String status;
  final Color accentColor;
  final Color statusBg;
  final Color statusFg;

  const _Appointment({
    required this.patientName,
    required this.details,
    required this.time,
    required this.visitType,
    required this.status,
    required this.accentColor,
    required this.statusBg,
    required this.statusFg,
  });
}
