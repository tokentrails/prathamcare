import 'package:flutter/material.dart';

import '../../data/models/admin_doctor.dart';
import 'doctor_status_chip.dart';

class DoctorListTile extends StatelessWidget {
  const DoctorListTile({
    super.key,
    required this.doctor,
    required this.onView,
    required this.onEdit,
    required this.onToggleStatus,
    this.busy = false,
  });

  final AdminDoctor doctor;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    doctor.fullName.isEmpty ? doctor.firstName : doctor.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                DoctorStatusChip(isActive: doctor.isActive),
              ],
            ),
            const SizedBox(height: 6),
            Text('${doctor.specialization} • ${doctor.registrationNumber}'),
            const SizedBox(height: 4),
            Text('${doctor.phoneNumber} • ${doctor.email}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onView,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onToggleStatus,
                  icon: Icon(doctor.isActive ? Icons.toggle_off_rounded : Icons.toggle_on_rounded, size: 18),
                  label: Text(doctor.isActive ? 'Deactivate' : 'Activate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
