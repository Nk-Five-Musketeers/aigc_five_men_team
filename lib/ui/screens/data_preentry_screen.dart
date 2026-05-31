import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../config/theme.dart';
import '../../core/services/profile_photo_storage.dart';
import '../../data/local_db/local_database.dart';
import '../../data/models/nearby_person.dart';
import '../../data/models/profile_photo.dart';

part 'data_preentry/data_preentry_shell.dart';
part 'data_preentry/data_preentry_widgets.dart';
