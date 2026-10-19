import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/medis_ui.dart';
import 'profile_edit_screen.dart';
import 'reminder_settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final profile = controller.profile;
    return ColoredBox(
      color: MeDisColors.background,
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
                _InfoRow(Icons.warning_amber_rounded, 'ประวัติแพ้ยา',
                    profile.drugAllergies,
                    valueColor: MeDisColors.error),
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
                    valueColor: MeDisColors.error),
              ],
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                leading: const _FeatureIcon(
                    icon: Icons.alarm_rounded, color: MeDisColors.primary),
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
              onPressed: () async {
                final confirmed = await confirmMeDisAction(context,
                    title: 'ออกจากระบบ?',
                    message: 'ข้อมูลที่บันทึกไว้จะยังอยู่ในบัญชีของคุณ',
                    actionLabel: 'ออกจากระบบ');
                if (confirmed) await controller.signOut();
              },
              style: OutlinedButton.styleFrom(
                  foregroundColor: MeDisColors.error,
                  side: const BorderSide(color: MeDisColors.error),
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
        padding: MeDisSpace.pagePadding,
        child: Column(children: [
          MeDisPageHeader(
              title: 'โปรไฟล์',
              subtitle: 'ข้อมูลของคุณและผู้ดูแล',
              trailing: IconButton.outlined(
                  tooltip: 'แก้ไขข้อมูลผู้ป่วย',
                  onPressed: () async {
                    final confirmed = await confirmMeDisAction(context,
                        title: 'แก้ไขข้อมูลผู้ป่วย',
                        message: 'สไลด์เพื่อเปิดฟอร์มแก้ไขข้อมูลของคุณ',
                        actionLabel: 'เปิดฟอร์มแก้ไข');
                    if (confirmed && context.mounted) {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfileEditScreen()));
                    }
                  },
                  icon: const Icon(Icons.edit_outlined))),
          Row(children: [
            Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white),
                child: const CircleAvatar(
                    radius: 32,
                    backgroundColor: MeDisColors.primarySoft,
                    child: Icon(Icons.person_rounded,
                        size: 38, color: MeDisColors.primary))),
            const SizedBox(width: 18),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(profile.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: MeDisColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(profile.email,
                      style: const TextStyle(color: MeDisColors.muted)),
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
  Widget build(BuildContext context) =>
      MeDisSection(title: title, icon: icon, children: children);
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
          Icon(icon, size: 21, color: MeDisColors.subtle),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        color: MeDisColors.muted, fontSize: 13)),
                const SizedBox(height: 2),
                Text(value.trim().isEmpty ? 'ยังไม่ได้ระบุ' : value,
                    style: TextStyle(
                        color: value.trim().isEmpty
                            ? MeDisColors.subtle
                            : valueColor ?? MeDisColors.text,
                        fontWeight: FontWeight.w500)),
              ]))
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
