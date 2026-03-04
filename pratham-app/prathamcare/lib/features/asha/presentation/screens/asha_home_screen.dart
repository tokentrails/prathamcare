import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_pill_button.dart';
import '../../../../data/network/api_client.dart';
import 'asha_activity_screen.dart';
import 'voice_visit_screen.dart';

class ASHAHomeScreen extends StatefulWidget {
  const ASHAHomeScreen({super.key});

  @override
  State<ASHAHomeScreen> createState() => _ASHAHomeScreenState();
}

class _ASHAHomeScreenState extends State<ASHAHomeScreen> {
  final ApiClient _apiClient = ApiClient();

  int _selectedBottomTab = 0;
  bool _loading = false;
  int _pendingSyncCount = 0;
  int _queuedCount = 0;
  int _encounterCount = 0;
  int _transcriptionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _loading = true);
    try {
      final syncFuture = _apiClient.getSyncStatus();
      final encounterFuture = _apiClient.getEncounterHistory(limit: 30);
      final voiceFuture = _apiClient.getVoiceHistory(limit: 30);
      final results = await Future.wait([syncFuture, encounterFuture, voiceFuture]);

      final sync = results[0] as Map<String, dynamic>;
      final encounter = results[1] as Map<String, dynamic>;
      final voice = results[2] as Map<String, dynamic>;

      final queued = _asMapList(encounter['queued']);
      final encounters = _asMapList(encounter['encounters']);
      final voiceItems = _asMapList(voice['items']);

      if (!mounted) {
        return;
      }
      setState(() {
        _pendingSyncCount = (sync['pending_actions'] as num?)?.toInt() ?? 0;
        _queuedCount = queued.length;
        _encounterCount = encounters.length;
        _transcriptionCount = voiceItems.length;
      });
    } catch (_) {
      // Keep functional UI and current values.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCreateEncounter() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const VoiceVisitScreen(),
      ),
    );
    if (result == true) {
      await _loadDashboardData();
    }
  }

  Future<void> _openJobs(ASHAJobsView view) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ASHAActivityScreen(initialView: view),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: Row(
        children: [
          if (isDesktop) _buildDesktopSidebar(),
          Expanded(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _loadDashboardData,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(isDesktop)),
                    SliverToBoxAdapter(child: _buildTopMenu()),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1140),
                            child: isDesktop ? _buildDesktopContent() : _buildMobileContent(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildBottomNavigation(),
    );
  }

  Widget _buildHeader(bool isDesktop) {
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
                  'Good Morning',
                  style: TextStyle(color: AppColors.lightTextMuted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2),
                Text(
                  'ASHA Operations Dashboard',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  _pendingSyncCount == 0 ? 'All Synced' : '$_pendingSyncCount Pending Sync',
                  style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loading ? null : _loadDashboardData,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          if (!isDesktop)
            IconButton(
              onPressed: () => _openJobs(ASHAJobsView.overview),
              icon: const Icon(Icons.work_outline_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildTopMenu() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _MenuChip(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              selected: true,
              onTap: () {},
            ),
            const SizedBox(width: 8),
            _MenuChip(
              icon: Icons.work_outline_rounded,
              label: 'Jobs',
              selected: false,
              onTap: () => _openJobs(ASHAJobsView.overview),
            ),
            const SizedBox(width: 8),
            _MenuChip(
              icon: Icons.pending_actions_rounded,
              label: 'Queued',
              selected: false,
              onTap: () => _openJobs(ASHAJobsView.queued),
            ),
            const SizedBox(width: 8),
            _MenuChip(
              icon: Icons.assignment_turned_in_outlined,
              label: 'Encounters',
              selected: false,
              onTap: () => _openJobs(ASHAJobsView.encounters),
            ),
            const SizedBox(width: 8),
            _MenuChip(
              icon: Icons.graphic_eq_rounded,
              label: 'Transcriptions',
              selected: false,
              onTap: () => _openJobs(ASHAJobsView.transcriptions),
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
          flex: 12,
          child: Column(
            children: [
              _buildCreateEncounterPanel(),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 10,
          child: _buildJobsListPanel(),
        ),
      ],
    );
  }

  Widget _buildMobileContent() {
    return Column(
      children: [
        _buildCreateEncounterPanel(),
        const SizedBox(height: 12),
        _buildJobsListPanel(),
      ],
    );
  }

  Widget _buildCreateEncounterPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF129186)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x250F766E),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mic_none_rounded, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Create Encounter',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Record or upload home visit audio, extract clinical insights with AI, and submit the encounter.',
            style: TextStyle(color: Color(0xFFE2FFFB), fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppPillButton(
                  onPressed: _openCreateEncounter,
                  icon: Icons.add_rounded,
                  label: 'Create Encounter',
                  variant: AppPillButtonVariant.light,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppPillButton(
                  onPressed: () => _openJobs(ASHAJobsView.overview),
                  icon: Icons.work_outline_rounded,
                  label: 'Open Jobs',
                  variant: AppPillButtonVariant.dark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJobsListPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Job Categories',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Track processing and encounter state in one place',
            style: TextStyle(fontSize: 12.5, color: AppColors.lightTextMuted),
          ),
          const SizedBox(height: 12),
          _JobListTile(
            title: 'Queued Encounters',
            subtitle: 'Pending retries or unresolved mappings',
            count: _queuedCount,
            icon: Icons.pending_actions_rounded,
            accent: AppColors.lightWarning,
            onTap: () => _openJobs(ASHAJobsView.queued),
          ),
          _JobListTile(
            title: 'Encounters',
            subtitle: 'Submitted visits and current sync status',
            count: _encounterCount,
            icon: Icons.assignment_turned_in_outlined,
            accent: AppColors.primary,
            onTap: () => _openJobs(ASHAJobsView.encounters),
          ),
          _JobListTile(
            title: 'Transcriptions',
            subtitle: 'Audio jobs and extraction completion',
            count: _transcriptionCount,
            icon: Icons.graphic_eq_rounded,
            accent: AppColors.lightInfo,
            onTap: () => _openJobs(ASHAJobsView.transcriptions),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    const items = [
      (icon: Icons.home_filled, label: 'Home'),
      (icon: Icons.calendar_today_outlined, label: 'Schedule'),
      (icon: Icons.groups_outlined, label: 'Patients'),
      (icon: Icons.work_outline_rounded, label: 'Jobs'),
      (icon: Icons.person_outline_rounded, label: 'Profile'),
    ];

    return Container(
      width: 246,
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
                  width: 170,
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
                      _loading
                          ? 'Refreshing...'
                          : (_pendingSyncCount == 0 ? 'All data synced' : '$_pendingSyncCount pending sync'),
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

  Widget _buildBottomNavigation() {
    const items = [
      (icon: Icons.home_filled, label: 'Home'),
      (icon: Icons.calendar_today_outlined, label: 'Schedule'),
      (icon: Icons.groups_outlined, label: 'Patients'),
      (icon: Icons.work_outline_rounded, label: 'Jobs'),
      (icon: Icons.person_outline_rounded, label: 'Profile'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7EEED)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A0F766E),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: List.generate(items.length, (index) {
              final selected = _selectedBottomTab == index;
              return Expanded(
                child: InkWell(
                  onTap: () => _handleNavTap(index),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primarySoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          items[index].icon,
                          size: 20,
                          color: selected ? AppColors.primary : const Color(0xFF98A8A6),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items[index].label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? AppColors.primary : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
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
    if (index == 3) {
      setState(() => _selectedBottomTab = index);
      await _openJobs(ASHAJobsView.overview);
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

  static List<Map<String, dynamic>> _asMapList(dynamic v) {
    if (v is! List) {
      return const [];
    }
    return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
}

class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : AppColors.lightTextMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.lightTextSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobListTile extends StatelessWidget {
  const _JobListTile({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: accent.withOpacity(0.13),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.lightTextMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AppColors.lightPlaceholder),
          ],
        ),
      ),
    );
  }
}
