import 'package:flutter/material.dart';
import 'package:visitarian_flutter/app/app.dart';
import 'package:visitarian_flutter/app/bootstrap.dart';

Future<void> main() async {
  await bootstrapApp(() async {
    runApp(const VisitaRianApp());
  });
}
