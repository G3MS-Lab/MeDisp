import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_scope.dart';
import '../widgets/medis_ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool registerMode = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (AppScope.of(context).busy) return;
    if (!formKey.currentState!.validate()) return;
    final controller = AppScope.of(context);
    if (registerMode) {
      await controller.register(name.text, email.text, password.text);
    } else {
      await controller.signIn(email.text, password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(children: [
                  const CircleAvatar(
                      radius: 36,
                      backgroundColor: MeDisColors.primarySoft,
                      child: Icon(Icons.monitor_heart_outlined,
                          size: 40, color: MeDisColors.primary)),
                  const SizedBox(height: 18),
                  const Text('MeDis',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: MeDisColors.text)),
                  Text(
                      registerMode
                          ? 'สร้างบัญชีผู้ป่วย'
                          : 'เข้าสู่ระบบเพื่อจัดการยา',
                      style: const TextStyle(color: MeDisColors.muted)),
                  const SizedBox(height: 30),
                  if (registerMode) ...[
                    TextFormField(
                        controller: name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'ชื่อผู้ป่วย',
                            prefixIcon: Icon(Icons.person_outline)),
                        validator: (value) =>
                            value == null || value.trim().length < 2
                                ? 'กรุณาระบุชื่อ'
                                : null),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                      controller: email,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          labelText: 'อีเมล',
                          prefixIcon: Icon(Icons.email_outlined)),
                      validator: (value) =>
                          value == null || !value.contains('@')
                              ? 'อีเมลไม่ถูกต้อง'
                              : null),
                  const SizedBox(height: 14),
                  TextFormField(
                      controller: password,
                      autofillHints: registerMode
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      obscureText: obscurePassword,
                      onFieldSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                          labelText: 'รหัสผ่าน',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              tooltip: obscurePassword
                                  ? 'แสดงรหัสผ่าน'
                                  : 'ซ่อนรหัสผ่าน',
                              onPressed: () => setState(
                                  () => obscurePassword = !obscurePassword),
                              icon: Icon(obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined))),
                      validator: (value) => value == null ||
                              value.length < (registerMode ? 8 : 6)
                          ? 'รหัสผ่านต้องมีอย่างน้อย ${registerMode ? 8 : 6} ตัว'
                          : null),
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    MeDisNotice(
                        message: controller.errorMessage!,
                        color: MeDisColors.error,
                        icon: Icons.error_outline),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                      width: double.infinity,
                      // The button grows with accessibility text sizes.
                      child: FilledButton(
                          onPressed: controller.busy ? null : submit,
                          child: controller.busy
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2)),
                                    const SizedBox(width: 10),
                                    Text(registerMode
                                        ? 'กำลังสมัคร...'
                                        : 'กำลังเข้าสู่ระบบ...'),
                                  ],
                                )
                              : Text(registerMode
                                  ? 'สมัครสมาชิก'
                                  : 'เข้าสู่ระบบ'))),
                  TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => setState(() {
                                registerMode = !registerMode;
                                formKey.currentState?.reset();
                                controller.errorMessage = null;
                              }),
                      child: Text(registerMode
                          ? 'มีบัญชีแล้ว? เข้าสู่ระบบ'
                          : 'ยังไม่มีบัญชี? สมัครสมาชิก')),
                  const SizedBox(height: 12),
                  const Text(
                      'ข้อมูลยาเป็นข้อมูลสุขภาพ โปรดใช้รหัสผ่านที่ไม่ซ้ำกับบริการอื่น',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: MeDisColors.muted)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
