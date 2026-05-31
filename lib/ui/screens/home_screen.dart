import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../core/narration/narration_player.dart';
import '../../core/voice_input/voice_input.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/memory_album.dart';
import '../../data/models/profile_photo.dart';
import '../../data/models/relation_conflict_record.dart';
import '../../data/local_db/local_database.dart';
import '../../data/repositories/memory_album_repository.dart';
import '../../logic/chat_provider.dart';
import 'data_preentry_screen.dart';

part 'home/home_shell.dart';
part 'home/chat_view.dart';
part 'home/memory_book_view.dart';
part 'home/memory_book_narration.dart';
part 'home/memory_book_album_panels.dart';
part 'home/memory_book_photos.dart';
part 'home/recent_notes_view.dart';
part 'home/settings_view.dart';
part 'home/shared_widgets.dart';
