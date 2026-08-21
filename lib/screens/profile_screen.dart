import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import 'profile_edit_screen.dart';
import 'reminder_settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final profile = controller.profile;
    return ColoredBox(
      color: const Color(0xFFF4F7FC),
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _ProfileHeader(profile: profile)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          sliver: SliverList.list(children: [
            _ProfileSection(
              title: 'ข้อมูลส่วนตัว',
              icon: Icons.badge_outlined,
              children: [
                _InfoRow(Icons.cake_outlined, 'วันเกิด', profile.birthDate),
                _InfoRow(Icons.wc_outlined, 'เพศ', profile.gender),
                _InfoRow(Icons.phone_outlined, 'โทรศัพท์', profile.phone),
                _InfoRow(Icons.email_outlined, 'อีเมล', profile.email),
                _InfoRow(Icons.home_outlined, 'ที่อยู่', profile.address),
              ],
            ),
            _ProfileSection(
              title: 'ข้อมูลสุขภาพ',
              icon: Icons.monitor_heart_outlined,
              children: [
                _InfoRow(
                    Icons.bloodtype_outlined, 'หมู่เลือด', profile.bloodType),
                _InfoRow(Icons.height, 'ส่วนสูง',
                    profile.heightCm == null ? '' : '${profile.heightCm} ซม.'),
                _InfoRow(Icons.monitor_weight_outlined, 'น้ำหนัก',
                    profile.weightKg == null ? '' : '${profile.weightKg} กก.'),
                _InfoRow(Icons.medical_information_outlined, 'โรคประจำตัว',
                    profile.medicalConditions),
              ],
            ),
            _ProfileSection(
              title: 'ผู้ดูแลและกรณีฉุกเฉิน',
              icon: Icons.health_and_safety_outlined,
              children: [
                _InfoRow(
                    Icons.person_outline, 'ชื่อผู้ดูแล', profile.caregiverName),
                _InfoRow(Icons.people_outline, 'ความสัมพันธ์',
                    profile.caregiverRelationship),
                _InfoRow(Icons.phone_in_talk_outlined, 'เบอร์ผู้ดูแล',
                    profile.caregiverPhone),
                _InfoRow(Icons.emergency_outlined, 'เบอร์ฉุกเฉิน',
                    profile.emergencyPhone,
                    valueColor: const Color(0xFFD83B3B)),
              ],
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                leading: const _FeatureIcon(
                    icon: Icons.alarm_rounded, color: Color(0xFF397BD9)),
                title: const Text('เวลาอาหารและการแจ้งเตือน',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('ตั้งเวลาแจ้งเตือนสำหรับแต่ละมื้อ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ReminderSettingsScreen())),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: controller.signOut,
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD83B3B),
                  side: const BorderSide(color: Color(0x33D83B3B)),
                  minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.logout),
              label: const Text('ออกจากระบบ'),
            ),
          ]),
        )
      ]),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});
  final PatientProfile profile;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF79AEEF), Color(0xFFB7D5FA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(34))),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('โปรไฟล์ผู้ป่วย',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
            IconButton.filledTonal(
                tooltip: 'แก้ไขข้อมูล',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ProfileEditScreen())),
                icon: const Icon(Icons.edit_outlined))
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white),
                child: const CircleAvatar(
                    radius: 43,
                    backgroundColor: Color(0xFFEAF2FD),
                    child: Icon(Icons.person_rounded,
                        size: 56, color: Color(0xFF397BD9)))),
            const SizedBox(width: 18),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(profile.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(profile.email,
                      style: const TextStyle(color: Color(0xEEFFFFFF))),
                ]))
          ])
        ]),
      );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection(
      {required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: const Color(0xFF397BD9)),
                const SizedBox(width: 9),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800))
              ]),
              const Divider(height: 24),
              ...children,
            ]),
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value, {this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 21, color: const Color(0xFF8291A5)),
          const SizedBox(width: 12),
          SizedBox(
              width: 104,
              child: Text(label,
                  style: const TextStyle(color: Color(0xFF68778B)))),
          Expanded(
              child: Text(value.trim().isEmpty ? 'ยังไม่ได้ระบุ' : value,
                  style: TextStyle(
                      color: value.trim().isEmpty
                          ? const Color(0xFFADB5C0)
                          : valueColor ?? const Color(0xFF253246),
                      fontWeight: FontWeight.w600)))
        ]),
      );
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(13)),
      child: Icon(icon, color: color));
}
