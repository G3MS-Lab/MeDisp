import 'package:flutter/material.dart';

import '../application/app_scope.dart';

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
    if (!formKey.currentState!.validate()) return;
    final controller = AppScope.of(context);
    final success = registerMode
        ? await controller.register(name.text, email.text, password.text)
        : await controller.signIn(email.text, password.text);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(controller.errorMessage ?? 'ไม่สามารถดำเนินการได้')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: formKey,
                child: Column(children: [
                  const CircleAvatar(
                      radius: 46,
                      backgroundColor: Color(0xFF6AA6FF),
                      child: Icon(Icons.monitor_heart_outlined,
                          size: 50, color: Colors.white)),
                  const SizedBox(height: 18),
                  const Text('MeDis',
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF313131))),
                  Text(
                      registerMode
                          ? 'สร้างบัญชีผู้ป่วย'
                          : 'เข้าสู่ระบบเพื่อจัดการยา',
                      style: const TextStyle(color: Colors.grey)),
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
                      obscureText: obscurePassword,
                      onFieldSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                          labelText: 'รหัสผ่าน',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              onPressed: () => setState(
                                  () => obscurePassword = !obscurePassword),
                              icon: Icon(obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined))),
                      validator: (value) => value == null ||
                              value.length < (registerMode ? 8 : 6)
                          ? 'รหัสผ่านต้องมีอย่างน้อย ${registerMode ? 8 : 6} ตัว'
                          : null),
                  const SizedBox(height: 22),
                  SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                          onPressed: controller.busy ? null : submit,
                          child: controller.busy
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : Text(registerMode
                                  ? 'สมัครสมาชิก'
                                  : 'เข้าสู่ระบบ'))),
                  TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => setState(() => registerMode = !registerMode),
                      child: Text(registerMode
                          ? 'มีบัญชีแล้ว? เข้าสู่ระบบ'
                          : 'ยังไม่มีบัญชี? สมัครสมาชิก')),
                  const SizedBox(height: 12),
                  const Text(
                      'ข้อมูลยาเป็นข้อมูลสุขภาพ โปรดใช้รหัสผ่านที่ไม่ซ้ำกับบริการอื่น',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
