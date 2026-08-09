import 'package:flutter/material.dart';

import '../application/app_scope.dart';
import 'reminder_settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.of(context).profile;
    return Container(
      color: const Color(0xFFAACBFA),
      child: Column(children: [
        const SizedBox(height: 20),
        const Text('Profile', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        const CircleAvatar(radius: 52, backgroundColor: Colors.white, child: Icon(Icons.person, size: 65, color: Color(0xFF6AA6FF))),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(52))),
            child: ListView(padding: const EdgeInsets.fromLTRB(32, 30, 32, 24), children: [
              Center(child: Text(profile.name, style: const TextStyle(fontSize: 22))),
              const SizedBox(height: 12),
              const _ProfileField('เพศ', 'ชาย'),
              _ProfileField('อีเมล', profile.email),
              _ProfileField('เบอร์โทรศัพท์', profile.phone),
              _ProfileField('กรุ๊ปเลือด', profile.bloodType),
              _ProfileField('วันเดือนปีเกิด', profile.birthDate),
              _ProfileField('ที่อยู่', profile.address),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.alarm_rounded, color: Color(0xFF6AA6FF)),
                  title: const Text('เวลาอาหารและการแจ้งเตือน', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('ตั้งเวลา เตือนล่วงหน้า และจำนวนครั้ง'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReminderSettingsScreen())),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD7D7D7)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFFC8C8C8), fontSize: 17)), const SizedBox(height: 5), Text(value, style: const TextStyle(color: Color(0xFF454545), fontSize: 20))]),
      );
}
