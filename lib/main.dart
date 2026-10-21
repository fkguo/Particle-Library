import 'dart:async';

import 'package:flutter/material.dart';

import 'app/pdg_app.dart';
import 'core/app_paths.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve the application support directory while the first frame is being
  // built. The first asynchronous filesystem call starts dart:io's I/O service
  // and otherwise lands on the boot path as a visible stall.
  unawaited(appSupportDirectory());
  runApp(const PdgApp());
}
