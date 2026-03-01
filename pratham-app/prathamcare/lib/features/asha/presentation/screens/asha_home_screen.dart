import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/network/api_client.dart';
import 'voice_visit_screen.dart';

class ASHAHomeScreen extends StatefulWidget {
  const ASHAHomeScreen({super.key});

  @override
  State<ASHAHomeScreen> createState() => _ASHAHomeScreenState();
}

class _ASHAHomeScreenState extends State<ASHAHomeScreen> {
  final ApiClient _apiClient = ApiClient();

  int _selectedBottomTab = 0;
  int _pendingSyncCount = 0;
  bool _loadingSync = false;

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    setState(() => _loadingSync = true);
    try {
      final res = await _apiClient.getSyncStatus();
      setState(() {
        _pendingSyncCount = (res['pending_actions'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {
      // Keep default for now. Auth wiring will be added with Cognito token flow.
    } finally {
      if (mounted) {
        setState(() => _loadingSync = false);
      }
    }
  }

  Future<void> _openVoiceVisit() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const VoiceVisitScreen(patientId: 'patient-demo-001'),
      ),
    );

    if (result == true) {
      _loadSyncStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFA),
      body: Row(
        children: [
          if (isDesktop) _buildDesktopSidebar(),
          Expanded(
            child: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktopContent = constraints.maxWidth >= 980;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1220),
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(child: _buildHeader()),
                          SliverToBoxAdapter(child: _buildStatusPills()),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
                            sliver: SliverToBoxAdapter(
                              child: desktopContent ? _buildDesktopContent() : _buildMobileContent(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openVoiceVisit,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.mic_none_rounded, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: isDesktop ? null : _buildBottomNavigation(),
    );
  }

  Widget _buildDesktopSidebar() {
    const items = [
      (icon: Icons.home_filled, label: 'Home'),
      (icon: Icons.calendar_today_outlined, label: 'Schedule'),
      (icon: Icons.groups_outlined, label: 'Patients'),
      (icon: Icons.description_outlined, label: 'Reports'),
      (icon: Icons.person_outline_rounded, label: 'Profile'),
    ];

    return Container(
      width: 236,
      decoration: const BoxDecoration(
        color: Color(0xFFFCFDFC),
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5ECEA)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F756D),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/images/pratham-logo.png',
                  width: 166,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Workspace',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                child: InkWell(
                  onTap: () => _handleNavTap(i),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _selectedBottomTab == i ? const Color(0x170F756D) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: _selectedBottomTab == i ? Border.all(color: const Color(0x330F756D)) : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Icon(
                          items[i].icon,
                          size: 20,
                          color: _selectedBottomTab == i ? AppColors.primary : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            items[i].label,
                            style: TextStyle(
                              fontSize: 14,
                              color: _selectedBottomTab == i ? AppColors.primary : const Color(0xFF64748B),
                              fontWeight: _selectedBottomTab == i ? FontWeight.w700 : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_selectedBottomTab == i)
                          const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5ECEA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loadingSync ? 'Checking sync...' : (_pendingSyncCount == 0 ? 'All data synced' : '$_pendingSyncCount pending sync'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
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

  Widget _buildDesktopContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              _buildStatsStrip(),
              const SizedBox(height: 20),
              _buildAiBriefing(),
              const SizedBox(height: 20),
              _buildQuickActions(),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildTodayVisits(),
        ),
      ],
    );
  }

  Widget _buildMobileContent() {
    return Column(
      children: [
        _buildStatsStrip(),
        const SizedBox(height: 20),
        _buildAiBriefing(),
        const SizedBox(height: 20),
        _buildQuickActions(),
        const SizedBox(height: 20),
        _buildTodayVisits(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good morning,',
                  style: TextStyle(color: Color(0xFF8A9099), fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  'Sunita',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPills() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined, size: 14, color: Color(0xFF059669)),
                const SizedBox(width: 6),
                Text(
                  _loadingSync ? 'Checking...' : (_pendingSyncCount == 0 ? 'Synced' : '$_pendingSyncCount Pending Sync'),
                  style: const TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF9FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF0284C7)),
                SizedBox(width: 6),
                Text(
                  'Hubballi Block',
                  style: TextStyle(color: Color(0xFF0284C7), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip() {
    return Row(
      children: const [
        Expanded(child: _StatCard(value: '8', label: 'Visits\nToday', valueColor: AppColors.primary)),
        SizedBox(width: 12),
        Expanded(child: _StatCard(value: '3', label: 'High\nRisk', valueColor: Color(0xFFEF4444))),
        SizedBox(width: 12),
        Expanded(child: _StatCard(value: '2', label: 'Pending\nSync', valueColor: Color(0xFFF59E0B))),
      ],
    );
  }

  Widget _buildAiBriefing() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x1F0F756D), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0F756D), Color(0xFF38BDF8)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text(
                      'AI BRIEFING',
                      style: TextStyle(fontSize: 11, letterSpacing: 0.5, color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('8 visits today.', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(height: 1.5, color: Color(0xB30B1220), fontSize: 15),
                    children: const [
                      TextSpan(text: 'Priority: ', style: TextStyle(color: AppColors.lightError, fontWeight: FontWeight.w700)),
                      TextSpan(text: 'Meena Devi needs urgent BP check due to yesterday\'s high reading.'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () {},
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0x0D0F756D),
                      border: Border.all(color: const Color(0x330F756D)),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('View Today\'s Plan', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('Quick Actions', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: [
            _ActionCard(
              title: 'Voice Visit',
              icon: Icons.mic_none_rounded,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onTap: _openVoiceVisit,
            ),
            _ActionCard(
              title: 'Scan ABHA',
              icon: Icons.qr_code_scanner_rounded,
              onTap: () {},
            ),
            _ActionCard(
              title: 'ANC Register',
              icon: Icons.assignment_outlined,
              onTap: () {},
            ),
            _ActionCard(
              title: 'Emergency',
              icon: Icons.warning_amber_rounded,
              backgroundColor: const Color(0xFFFEF2F2),
              foregroundColor: const Color(0xFFDC2626),
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTodayVisits() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Today\'s Visits', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            ),
            TextButton(onPressed: () {}, child: const Text('See All')),
          ],
        ),
        const SizedBox(height: 10),
        const _VisitCard(
          patientName: 'Meena Devi',
          time: '10:00 AM',
          tag: 'ANC',
          status: 'Pending',
          risk: 'High Risk',
          color: Color(0xFFEF4444),
        ),
        const SizedBox(height: 10),
        const _VisitCard(
          patientName: 'Priya Sharma',
          time: '11:00 AM',
          tag: 'ANC',
          status: 'Pending',
          risk: '',
          color: Color(0xFFF59E0B),
        ),
        const SizedBox(height: 10),
        const _VisitCard(
          patientName: 'Raju Kumar',
          time: '09:15 AM',
          tag: 'FU',
          status: 'Done',
          risk: '',
          color: Color(0xFF22C55E),
          done: true,
        ),
      ],
    );
  }

  Widget _buildBottomNavigation() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedBottomTab,
      onTap: _handleNavTap,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: const Color(0xFF94A3B8),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), label: 'Schedule'),
        BottomNavigationBarItem(icon: Icon(Icons.groups_outlined), label: 'Patients'),
        BottomNavigationBarItem(icon: Icon(Icons.description_outlined), label: 'Reports'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: 'Profile'),
      ],
    );
  }

  Future<void> _handleNavTap(int index) async {
    if (index == 0) {
      setState(() => _selectedBottomTab = 0);
      return;
    }
    if (index == 4) {
      setState(() => _selectedBottomTab = index);
      await Navigator.of(context).pushNamed('/profile');
      if (!mounted) {
        return;
      }
      setState(() => _selectedBottomTab = 0);
      return;
    }
    setState(() => _selectedBottomTab = index);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This section is coming soon.')),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, required this.valueColor});

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x140F756D), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: valueColor, fontSize: 32, fontWeight: FontWeight.w700)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF8A9099))),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
    this.backgroundColor = Colors.white,
    this.foregroundColor = const Color(0xFF0B1220),
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(28),
          border: backgroundColor == Colors.white ? Border.all(color: const Color(0xFFE2E8F0)) : null,
          boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(
              backgroundColor: foregroundColor.withOpacity(backgroundColor == Colors.white ? 0.1 : 0.2),
              child: Icon(icon, color: foregroundColor),
            ),
            Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: foregroundColor)),
          ],
        ),
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.patientName,
    required this.time,
    required this.tag,
    required this.status,
    required this.risk,
    required this.color,
    this.done = false,
  });

  final String patientName;
  final String time;
  final String tag;
  final String status;
  final String risk;
  final Color color;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x140F756D), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(width: 6, height: done ? 90 : 106, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(time, style: TextStyle(color: done ? const Color(0xFF94A3B8) : const Color(0xFF8A9099))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                        child: Text(tag, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    patientName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (risk.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(999)),
                      child: Text(risk, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: done ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                  child: Icon(done ? Icons.check_rounded : Icons.chevron_right_rounded, color: done ? const Color(0xFF16A34A) : const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 10,
                    color: done ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
