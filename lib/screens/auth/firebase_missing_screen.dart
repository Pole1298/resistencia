import 'package:flutter/material.dart';

class FirebaseMissingScreen extends StatelessWidget {
  const FirebaseMissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            Text('Firebase no configurado', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text(
              'Esta versión requiere Firebase (OTP + Firestore).\n\n1) Colocá el google-services.json en android/app/\n2) Aplicá Google Services en Gradle\n3) Recompilá.',
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
