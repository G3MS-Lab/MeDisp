import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../domain/models.dart';
import '../widgets/local_image.dart';
import '../widgets/medis_image_card.dart';
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
                _DrugAllergyCardBox(profile: profile),
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

class _DrugAllergyCardBox extends StatelessWidget {
  const _DrugAllergyCardBox({required this.profile});
  final PatientProfile profile;

  @override
  Widget build(BuildContext context) {
    final hasAllergyText = profile.drugAllergies.trim().isNotEmpty;
    final hasImage = profile.drugAllergyCardImagePath != null;

    return Container(
      key: const Key('profile-drug-allergy-card'),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MeDisColors.error.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MeDisColors.error.withValues(alpha: 0.12),
              border: Border(
                bottom: BorderSide(
                  color: MeDisColors.error.withValues(alpha: 0.22),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.credit_card_rounded,
                  color: MeDisColors.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'บัตรแพ้ยาประจำตัว (Drug Allergy Card)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MeDisColors.error,
                    ),
                  ),
                ),
                if (profile.bloodType.trim().isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'เลือดกรุ๊ป ${profile.bloodType}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MeDisColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 16, color: MeDisColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        profile.name.trim().isEmpty
                            ? 'ผู้ป่วย'
                            : profile.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: MeDisColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.medication_liquid_outlined,
                        size: 16, color: MeDisColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hasAllergyText
                            ? 'ยาที่แพ้: ${profile.drugAllergies}'
                            : 'ยังไม่ได้ระบุรายการยาที่แพ้',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              hasAllergyText ? FontWeight.w700 : FontWeight.w500,
                          color: hasAllergyText
                              ? MeDisColors.error
                              : MeDisColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (hasImage) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Material(
                      color: Colors.white,
                      child: InkWell(
                        key: const Key('view-allergy-card-fullscreen'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => FullScreenImageScreen(
                              imagePath: profile.drugAllergyCardImagePath!,
                              title: 'บัตรแพ้ยาประจำตัว',
                            ),
                          ),
                        ),
                        child: SizedBox(
                          height: 170,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              localImage(
                                profile.drugAllergyCardImagePath!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      color: MeDisColors.subtle),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.62),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fullscreen_rounded,
                                          size: 16, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text(
                                        'แตะเพื่อดูเต็มจอ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
