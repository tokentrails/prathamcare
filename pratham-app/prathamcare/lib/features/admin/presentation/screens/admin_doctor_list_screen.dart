import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/network/api_client.dart';
import '../../../../data/repositories/cognito_auth_repository.dart';
import '../../data/models/admin_doctor.dart';
import '../widgets/doctor_list_tile.dart';
import 'admin_doctor_detail_screen.dart';
import 'admin_doctor_form_screen.dart';

class AdminDoctorListScreen extends StatefulWidget {
  const AdminDoctorListScreen({super.key});

  @override
  State<AdminDoctorListScreen> createState() => _AdminDoctorListScreenState();
}

class _AdminDoctorListScreenState extends State<AdminDoctorListScreen> {
  final ApiClient _apiClient = ApiClient();
  final CognitoAuthRepository _authRepository = CognitoAuthRepository.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _specializationController = TextEditingController();

  bool _loading = true;
  bool _busyStatusUpdate = false;
  String? _error;
  List<AdminDoctor> _items = <AdminDoctor>[];
  bool? _activeFilter;
  String _role = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _specializationController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final role = (await _authRepository.getRoleFromIdToken() ?? '').trim().toLowerCase();
    if (!mounted) {
      return;
    }
    setState(() => _role = role);
    if (_isAdmin) {
      await _loadDoctors();
      return;
    }
    setState(() {
      _loading = false;
      _error = null;
      _items = <AdminDoctor>[];
    });
  }

  Future<void> _loadDoctors() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _apiClient.adminListDoctors(
        query: _searchController.text.trim(),
        specialization: _specializationController.text.trim(),
        active: _activeFilter,
        limit: 100,
      );
      final rawItems = data['items'];
      final mapped = <AdminDoctor>[];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map<String, dynamic>) {
            mapped.add(AdminDoctor.fromJson(item));
          }
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _items = mapped);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '${e.code}: ${e.message}');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to load doctors');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool get _isAdmin => _role == 'clinic_admin' || _role == 'ops_admin' || _role == 'admin';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Doctor Management'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadDoctors,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _openCreate,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add Doctor'),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: RefreshIndicator(
              onRefresh: _loadDoctors,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!_isAdmin)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.lightErrorSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Only clinic_admin and ops_admin can manage doctors.',
                        style: TextStyle(color: AppColors.lightError),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _buildFilters(),
                  const SizedBox(height: 10),
                  if (_loading) const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: AppColors.lightError)),
                  if (!_loading && _error == null && _items.isEmpty)
                    const Text(
                      'No doctors found for this filter.',
                      style: TextStyle(color: AppColors.lightTextMuted),
                    ),
                  ..._items.map(
                    (doctor) => DoctorListTile(
                      doctor: doctor,
                      busy: _busyStatusUpdate || !_isAdmin,
                      onView: () => _openDetail(doctor),
                      onEdit: () => _openEdit(doctor),
                      onToggleStatus: () => _toggleStatus(doctor),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by name/email/phone/registration',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 760;
                final specField = Expanded(
                  child: TextField(
                    controller: _specializationController,
                    decoration: const InputDecoration(
                      labelText: 'Specialization',
                      border: OutlineInputBorder(),
                    ),
                  ),
                );
                final statusField = Expanded(
                  child: DropdownButtonFormField<bool?>(
                    value: _activeFilter,
                    items: const [
                      DropdownMenuItem<bool?>(value: null, child: Text('All Statuses')),
                      DropdownMenuItem<bool?>(value: true, child: Text('Active')),
                      DropdownMenuItem<bool?>(value: false, child: Text('Inactive')),
                    ],
                    onChanged: _loading ? null : (value) => setState(() => _activeFilter = value),
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                  ),
                );
                if (isNarrow) {
                  return Column(
                    children: [
                      specField,
                      const SizedBox(height: 10),
                      statusField,
                      const SizedBox(height: 10),
                      _filterButtons(),
                    ],
                  );
                }
                return Row(
                  children: [
                    specField,
                    const SizedBox(width: 10),
                    statusField,
                    const SizedBox(width: 10),
                    _filterButtons(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: _loading ? null : _loadDoctors,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Apply'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _loading
              ? null
              : () {
                  _searchController.clear();
                  _specializationController.clear();
                  setState(() => _activeFilter = null);
                  _loadDoctors();
                },
          child: const Text('Reset'),
        ),
      ],
    );
  }

  Future<void> _openCreate() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const AdminDoctorFormScreen(),
      ),
    );
    if (changed == true) {
      await _loadDoctors();
    }
  }

  Future<void> _openEdit(AdminDoctor doctor) async {
    final full = await _fetchDoctor(doctor.doctorId);
    if (full == null || !mounted) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AdminDoctorFormScreen(initialDoctor: full),
      ),
    );
    if (changed == true) {
      await _loadDoctors();
    }
  }

  Future<void> _openDetail(AdminDoctor doctor) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminDoctorDetailScreen(doctorId: doctor.doctorId),
      ),
    );
  }

  Future<void> _toggleStatus(AdminDoctor doctor) async {
    if (!_isAdmin || _busyStatusUpdate) {
      return;
    }
    setState(() => _busyStatusUpdate = true);
    try {
      await _apiClient.adminUpdateDoctorStatus(
        doctorId: doctor.doctorId,
        isActive: !doctor.isActive,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Doctor ${doctor.isActive ? 'deactivated' : 'activated'}')),
      );
      await _loadDoctors();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${e.code}: ${e.message}')),
      );
    } finally {
      if (mounted) {
        setState(() => _busyStatusUpdate = false);
      }
    }
  }

  Future<AdminDoctor?> _fetchDoctor(String doctorId) async {
    try {
      final payload = await _apiClient.adminGetDoctorById(doctorId: doctorId);
      return AdminDoctor.fromJson(payload);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.code}: ${e.message}')),
        );
      }
      return null;
    }
  }
}
