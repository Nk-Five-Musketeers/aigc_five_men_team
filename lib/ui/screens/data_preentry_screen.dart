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
import '../../data/models/profile_video.dart';

class DataPreentryScreen extends StatefulWidget {
  const DataPreentryScreen({
    super.key,
    required this.ownerUserId,
    required this.onBack,
    this.onDataChanged,
  });

  final String ownerUserId;
  final VoidCallback onBack;
  final VoidCallback? onDataChanged;

  @override
  State<DataPreentryScreen> createState() => _DataPreentryScreenState();
}

class _DataPreentryScreenState extends State<DataPreentryScreen> {
  final _name = TextEditingController();
  final _birthYear = TextEditingController();
  final _hometown = TextEditingController();
  final _currentAddress = TextEditingController();
  final _career = TextEditingController();
  final _hobbies = TextEditingController();
  final _foodPreference = TextEditingController();
  final _personality = TextEditingController();
  final _taboo = TextEditingController();
  final _dialect = TextEditingController();
  final _careNotes = TextEditingController();
  final _medicalNotes = TextEditingController();

  final _personName = TextEditingController();
  final _personRelation = TextEditingController();
  final _personPhone = TextEditingController();
  final _personBirthday = TextEditingController();
  final _personLocation = TextEditingController();
  final _personAddress = TextEditingController();
  final _personContactFreq = TextEditingController();
  final _personNote = TextEditingController();

  final _eventTime = TextEditingController();
  final _eventTitle = TextEditingController();
  final _eventLocation = TextEditingController();
  final _eventPeople = TextEditingController();
  final _eventEmotion = TextEditingController();
  final _eventDescription = TextEditingController();

  final _photoPath = TextEditingController();
  final _photoCaption = TextEditingController();
  final _photoTime = TextEditingController();
  final _photoLocation = TextEditingController();
  final _photoPeople = TextEditingController();

  int _section = 0;
  String _gender = '未填写';
  bool _personEmergency = false;
  bool _personActive = true;
  int _eventImportance = 3;
  ProfilePhotoCategory _photoCategory = ProfilePhotoCategory.family;
  bool _photoFavorite = false;
  int? _photoFamilyMemberId;
  int? _photoMemoryEventId;
  String? _webPhotoDataUri;
  String? _pickedPhotoName;
  bool _loading = true;
  List<NearbyPersonModel> _nearbyPeople = [];
  List<Map<String, dynamic>> _familyMembers = [];
  List<Map<String, dynamic>> _memoryEvents = [];
  List<ProfilePhotoModel> _photos = [];
  List<ProfileVideoModel> _videos = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didUpdateWidget(DataPreentryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerUserId != widget.ownerUserId) {
      _loadAll();
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _birthYear,
      _hometown,
      _currentAddress,
      _career,
      _hobbies,
      _foodPreference,
      _personality,
      _taboo,
      _dialect,
      _careNotes,
      _medicalNotes,
      _personName,
      _personRelation,
      _personPhone,
      _personBirthday,
      _personLocation,
      _personAddress,
      _personContactFreq,
      _personNote,
      _eventTime,
      _eventTitle,
      _eventLocation,
      _eventPeople,
      _eventEmotion,
      _eventDescription,
      _photoPath,
      _photoCaption,
      _photoTime,
      _photoLocation,
      _photoPeople,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _afterDataChanged() async {
    await _loadAll();
    widget.onDataChanged?.call();
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteNearbyPerson(NearbyPersonModel person) async {
    final name = person.name?.trim().isNotEmpty == true
        ? person.name!.trim()
        : '该亲属候选';
    final ok = await _confirmDelete(
      title: '删除亲属候选',
      message: '确定删除「$name」吗？若已确认入亲属表，对应家庭成员记录也会一并删除。',
    );
    if (!ok) return;
    await LocalDatabase.removeNearbyPerson(person.id);
    await _afterDataChanged();
    _toast('已删除');
  }

  Future<void> _deleteFamilyMember(Map<String, dynamic> row) async {
    final relation = _string(row['relation']);
    final name = _string(row['name']);
    final label = relation.isEmpty && name.isEmpty
        ? '该家庭成员'
        : '${relation.isEmpty ? '亲属' : relation} · ${name.isEmpty ? '未命名' : name}';
    final ok = await _confirmDelete(
      title: '删除家庭成员',
      message: '确定删除「$label」吗？删除后无法恢复。',
    );
    if (!ok) return;
    await LocalDatabase.deleteFamilyMember((row['id'] as num).toInt());
    await _afterDataChanged();
    _toast('家庭成员已删除');
  }

  Future<void> _deleteMemoryEvent(Map<String, dynamic> row) async {
    final title = _string(row['title']).isEmpty
        ? '未命名经历'
        : _string(row['title']);
    final ok = await _confirmDelete(
      title: '删除重要经历',
      message: '确定删除「$title」吗？删除后无法恢复。',
    );
    if (!ok) return;
    await LocalDatabase.deleteMemoryEvent((row['id'] as num).toInt());
    await _afterDataChanged();
    _toast('重要经历已删除');
  }

  Future<void> _deletePhoto(ProfilePhotoModel photo) async {
    final title = photo.caption?.trim().isNotEmpty == true
        ? photo.caption!.trim()
        : _photoCategoryLabel(photo.category);
    final ok = await _confirmDelete(
      title: '删除照片',
      message: '确定删除「$title」吗？数据库记录和本地文件都会删除。',
    );
    if (!ok) return;
    await LocalDatabase.deleteProfilePhoto(photo.id);
    await _afterDataChanged();
    _toast('照片已删除');
  }

  Future<void> _deleteVideo(ProfileVideoModel video) async {
    final title = video.caption?.trim().isNotEmpty == true
        ? video.caption!.trim()
        : '家庭视频';
    final ok = await _confirmDelete(
      title: '删除视频',
      message: '确定删除「$title」吗？数据库记录和本地文件都会删除。',
    );
    if (!ok) return;
    await LocalDatabase.deleteProfileVideo(video.id);
    await _afterDataChanged();
    _toast('视频已删除');
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await LocalDatabase.ensureUserExists(widget.ownerUserId,
        displayName: '王阿姨');
    final user = await LocalDatabase.getUserById(widget.ownerUserId);
    final nearbyRows =
        await LocalDatabase.getNearbyPeopleForUser(widget.ownerUserId);
    final families =
        await LocalDatabase.listFamilyMembersForUser(widget.ownerUserId);
    final events =
        await LocalDatabase.listMemoryEventsForUser(widget.ownerUserId);
    final photos = (await LocalDatabase.listProfilePhotosForUser(
      widget.ownerUserId,
    ))
        .where((p) => !p.isVideo)
        .toList();
    final videos =
        await LocalDatabase.listProfileVideosForUser(widget.ownerUserId);

    if (user != null) {
      _name.text = _string(user['name']);
      _birthYear.text = _string(user['birth_year']);
      _hometown.text = _string(user['hometown']);
      _currentAddress.text = _string(user['current_address']);
      _career.text = _string(user['career']);
      _hobbies.text = _string(user['hobbies']);
      _foodPreference.text = _string(user['food_preference']);
      _personality.text = _string(user['personality']);
      _taboo.text = _string(user['taboo']);
      _dialect.text = _string(user['dialect']);
      _careNotes.text = _string(user['care_notes']);
      _medicalNotes.text = _string(user['medical_notes']);
      final savedGender = _string(user['gender']);
      _gender = savedGender == '女' || savedGender == '男' ? savedGender : '未填写';
    }

    if (!mounted) return;
    setState(() {
      _nearbyPeople = nearbyRows.map(NearbyPersonModel.fromMap).toList();
      _familyMembers = families;
      _memoryEvents = events;
      _photos = photos;
      _videos = videos;
      _loading = false;
    });
  }

  Future<void> _saveProfile() async {
    await LocalDatabase.ensureUserExists(widget.ownerUserId,
        displayName: _name.text);
    await LocalDatabase.updateUser(widget.ownerUserId, {
      'name': _text(_name),
      'gender': _gender == '未填写' ? null : _gender,
      'birth_year': _text(_birthYear),
      'hometown': _text(_hometown),
      'current_address': _text(_currentAddress),
      'career': _text(_career),
      'hobbies': _text(_hobbies),
      'food_preference': _text(_foodPreference),
      'personality': _text(_personality),
      'taboo': _text(_taboo),
      'dialect': _text(_dialect),
      'care_notes': _text(_careNotes),
      'medical_notes': _text(_medicalNotes),
    });
    _toast('老人信息已保存');
    await _afterDataChanged();
  }

  Future<void> _saveNearbyPerson() async {
    if (_text(_personName).isEmpty) {
      _toast('请填写姓名');
      return;
    }
    await LocalDatabase.upsertNearbyPerson({
      'id': 'nearby_${DateTime.now().microsecondsSinceEpoch}',
      'owner_user_id': widget.ownerUserId,
      'name': _text(_personName),
      'relation': _text(_personRelation),
      'phone': _text(_personPhone),
      'birthday': _text(_personBirthday),
      'location': _text(_personLocation),
      'address': _text(_personAddress),
      'contact_freq': _text(_personContactFreq),
      'note': _text(_personNote),
      'is_emergency_contact': _personEmergency ? 1 : 0,
      'is_active': _personActive ? 1 : 0,
    });
    _clearPersonForm();
    await _afterDataChanged();
    _toast('亲属候选已保存');
  }

  Future<void> _confirmNearby(String id) async {
    final familyId = await LocalDatabase.confirmNearbyPersonAsFamilyMember(id);
    await _afterDataChanged();
    _toast(familyId == null ? '未找到候选记录' : '已确认入亲属表');
  }

  Future<void> _saveMemoryEvent() async {
    if (_text(_eventTitle).isEmpty && _text(_eventDescription).isEmpty) {
      _toast('请填写标题或概括');
      return;
    }
    await LocalDatabase.insertMemoryEvent({
      'owner_user_id': widget.ownerUserId,
      'event_time': _text(_eventTime),
      'title': _text(_eventTitle).isEmpty
          ? _text(_eventDescription)
          : _text(_eventTitle),
      'description': _text(_eventDescription),
      'location': _text(_eventLocation),
      'people_involved': _text(_eventPeople),
      'emotion': _text(_eventEmotion),
      'importance': _eventImportance,
      'source': 'pre_entry',
      'verified': 1,
    });
    _clearEventForm();
    await _afterDataChanged();
    _toast('重要经历已保存');
  }

  Future<void> _savePhoto() async {
    if (_text(_photoPath).isEmpty) {
      _toast('请填写照片路径');
      return;
    }
    final photoId = 'photo_${DateTime.now().microsecondsSinceEpoch}';
    late final String stablePath;
    try {
      stablePath = kIsWeb && _webPhotoDataUri != null
          ? _webPhotoDataUri!
          : await ProfilePhotoStorage.copyIntoAppStorage(
              _photoPath.text,
              preferredId: photoId,
            );
    } catch (e) {
      _toast('照片保存失败：$e');
      return;
    }

    final photo = ProfilePhotoModel(
      id: photoId,
      ownerUserId: widget.ownerUserId,
      filePath: stablePath,
      storageType: kIsWeb
          ? ProfilePhotoStorageType.webLocal
          : ProfilePhotoStorageType.filePath,
      category: _photoCategory,
      caption: _text(_photoCaption),
      photoTime: _text(_photoTime),
      location: _text(_photoLocation),
      peopleInvolved: _text(_photoPeople),
      familyMemberId: _photoCategory == ProfilePhotoCategory.family
          ? _photoFamilyMemberId
          : null,
      memoryEventId: _photoCategory == ProfilePhotoCategory.memory
          ? _photoMemoryEventId
          : null,
      isFavorite: _photoFavorite,
      metadata: {
        'source': 'pre_entry',
        'original_name': _pickedPhotoName ?? p.basename(_photoPath.text)
      },
    );
    await LocalDatabase.insertProfilePhoto(photo);
    await _syncPhotoToExistingTables(photo);
    _clearPhotoForm();
    await _afterDataChanged();
    _toast('照片已保存');
  }

  Future<void> _syncPhotoToExistingTables(ProfilePhotoModel photo) async {
    if (photo.category == ProfilePhotoCategory.avatar) {
      await LocalDatabase.updateUser(widget.ownerUserId, {
        'avatar_path': photo.filePath,
      });
    }
    if (photo.familyMemberId != null) {
      await LocalDatabase.updateFamilyMember(photo.familyMemberId!, {
        'photo_path': photo.filePath,
      });
    }
    if (photo.memoryEventId != null) {
      final row = await LocalDatabase.getMemoryEventById(photo.memoryEventId!);
      final existing = <String>[];
      final raw = row?['photo_paths'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          existing.addAll(List<String>.from(json.decode(raw)));
        } catch (_) {}
      }
      if (!existing.contains(photo.filePath)) {
        existing.add(photo.filePath);
      }
      await LocalDatabase.updateMemoryEvent(photo.memoryEventId!, {
        'photo_paths': json.encode(existing),
      });
    }
  }

  Future<void> _pickPhoto() async {
    const imageGroup = XTypeGroup(
      label: 'images',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
      mimeTypes: [
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/gif',
        'image/bmp'
      ],
    );
    final file = await openFile(acceptedTypeGroups: [imageGroup]);
    if (file == null) return;
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? 'image/jpeg';
      setState(() {
        _pickedPhotoName = file.name;
        _webPhotoDataUri = 'data:$mime;base64,${base64Encode(bytes)}';
        _photoPath.text = file.name;
      });
      return;
    }
    setState(() {
      _pickedPhotoName = file.name;
      _webPhotoDataUri = null;
      _photoPath.text = file.path;
    });
  }

  void _clearPersonForm() {
    for (final controller in [
      _personName,
      _personRelation,
      _personPhone,
      _personBirthday,
      _personLocation,
      _personAddress,
      _personContactFreq,
      _personNote,
    ]) {
      controller.clear();
    }
    setState(() {
      _personEmergency = false;
      _personActive = true;
    });
  }

  void _clearEventForm() {
    for (final controller in [
      _eventTime,
      _eventTitle,
      _eventLocation,
      _eventPeople,
      _eventEmotion,
      _eventDescription,
    ]) {
      controller.clear();
    }
    setState(() => _eventImportance = 3);
  }

  void _clearPhotoForm() {
    for (final controller in [
      _photoPath,
      _photoCaption,
      _photoTime,
      _photoLocation,
      _photoPeople,
    ]) {
      controller.clear();
    }
    setState(() {
      _photoFavorite = false;
      _photoFamilyMemberId = null;
      _photoMemoryEventId = null;
      _webPhotoDataUri = null;
      _pickedPhotoName = null;
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _string(Object? value) => value?.toString() ?? '';

  String _text(TextEditingController controller) => controller.text.trim();

  @override
  Widget build(BuildContext context) {
    final sections = [
      _StepItem(Icons.badge_rounded, '老人'),
      _StepItem(Icons.group_rounded, '亲属'),
      _StepItem(Icons.auto_stories_rounded, '经历'),
      _StepItem(Icons.photo_library_rounded, '照片'),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _BackLine(title: '数据预录入', onBack: widget.onBack),
        const SizedBox(height: 12),
        _StepPicker(
          items: sections,
          current: _section,
          onChanged: (index) => setState(() => _section = index),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 42),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: switch (_section) {
              0 => _profileSection(),
              1 => _peopleSection(),
              2 => _eventsSection(),
              _ => _photosSection(),
            },
          ),
      ],
    );
  }

  Widget _profileSection() {
    return _Panel(
      key: const ValueKey('profile'),
      icon: Icons.badge_rounded,
      title: '老人基本信息',
      trailing: FilledButton.icon(
        onPressed: _saveProfile,
        icon: const Icon(Icons.save_rounded),
        label: const Text('保存'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Subhead(label: '身份信息'),
          _Input(label: '姓名', controller: _name),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '性别',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSoft,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '未填写', label: Text('未填')),
                ButtonSegment(value: '女', label: Text('女')),
                ButtonSegment(value: '男', label: Text('男')),
              ],
              selected: {_gender},
              onSelectionChanged: (value) {
                setState(() => _gender = value.first);
              },
            ),
          ),
          const SizedBox(height: 14),
          _Input(label: '出生年月/年龄', controller: _birthYear),
          _Input(label: '籍贯', controller: _hometown),
          _Input(label: '现居地', controller: _currentAddress),
          const SizedBox(height: 8),
          const _Subhead(label: '生活偏好'),
          _Input(label: '职业经历', controller: _career, maxLines: 2),
          _Input(label: '兴趣爱好', controller: _hobbies, maxLines: 2),
          _Input(label: '饮食习惯', controller: _foodPreference, maxLines: 2),
          _Input(label: '性格特点', controller: _personality, maxLines: 2),
          _Input(label: '忌讳话题', controller: _taboo, maxLines: 2),
          _Input(label: '方言/说话习惯', controller: _dialect, maxLines: 2),
          const SizedBox(height: 8),
          const _Subhead(label: '照护与健康'),
          _Input(label: '照护提醒', controller: _careNotes, maxLines: 3),
          _Input(label: '健康注意事项', controller: _medicalNotes, maxLines: 3),
        ],
      ),
    );
  }

  Widget _peopleSection() {
    return _Panel(
      key: const ValueKey('people'),
      icon: Icons.group_rounded,
      title: '亲属信息',
      trailing: FilledButton.icon(
        onPressed: _saveNearbyPerson,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('保存'),
      ),
      child: Column(
        children: [
          _Input(label: '姓名', controller: _personName),
          _Input(label: '与老人的关系', controller: _personRelation),
          _Input(label: '电话/联系方式', controller: _personPhone),
          _Input(label: '生日', controller: _personBirthday),
          _Input(label: '居住地', controller: _personLocation),
          _Input(label: '详细地址', controller: _personAddress),
          _Input(label: '联系频率', controller: _personContactFreq),
          _Input(label: '记忆点/相处提醒', controller: _personNote, maxLines: 3),
          SwitchListTile(
            value: _personEmergency,
            contentPadding: EdgeInsets.zero,
            title: const Text('紧急联系人'),
            onChanged: (value) => setState(() => _personEmergency = value),
          ),
          SwitchListTile(
            value: _personActive,
            contentPadding: EdgeInsets.zero,
            title: const Text('仍常联系/在世'),
            onChanged: (value) => setState(() => _personActive = value),
          ),
          const SizedBox(height: 8),
          _Subhead(label: '已确认亲属'),
          if (_familyMembers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无已确认亲属。保存候选后点「确认入亲属表」。',
                style: TextStyle(color: AppTheme.textSoft, fontSize: 18),
              ),
            )
          else
            ..._familyMembers.map(_familyTile),
          const SizedBox(height: 8),
          _Subhead(label: '候选列表'),
          if (_nearbyPeople.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无候选记录。',
                style: TextStyle(color: AppTheme.textSoft, fontSize: 18),
              ),
            )
          else
            ..._nearbyPeople.map(_nearbyTile),
        ],
      ),
    );
  }

  Widget _eventsSection() {
    return _Panel(
      key: const ValueKey('events'),
      icon: Icons.auto_stories_rounded,
      title: '重要经历',
      trailing: FilledButton.icon(
        onPressed: _saveMemoryEvent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('保存'),
      ),
      child: Column(
        children: [
          _Input(label: '时间', controller: _eventTime),
          _Input(label: '地点', controller: _eventLocation),
          _Input(label: '标题', controller: _eventTitle),
          _Input(label: '涉及人物', controller: _eventPeople),
          _Input(label: '情绪/感受', controller: _eventEmotion),
          _Input(label: '一段话概括', controller: _eventDescription, maxLines: 4),
          Row(
            children: [
              const Text('重要程度', style: TextStyle(fontWeight: FontWeight.w800)),
              Expanded(
                child: Slider(
                  value: _eventImportance.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_eventImportance',
                  onChanged: (value) {
                    setState(() => _eventImportance = value.round());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Subhead(label: '已保存经历'),
          if (_memoryEvents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无已保存经历。',
                style: TextStyle(color: AppTheme.textSoft, fontSize: 18),
              ),
            )
          else
            ..._memoryEvents.map(_memoryTile),
        ],
      ),
    );
  }

  Widget _photosSection() {
    return _Panel(
      key: const ValueKey('photos'),
      icon: Icons.photo_library_rounded,
      title: '照片录入',
      trailing: FilledButton.icon(
        onPressed: _savePhoto,
        icon: const Icon(Icons.add_photo_alternate_rounded),
        label: const Text('保存'),
      ),
      child: Column(
        children: [
          DropdownButtonFormField<ProfilePhotoCategory>(
            initialValue: _photoCategory,
            decoration: _inputDecoration('分类'),
            items: const [
              DropdownMenuItem(
                  value: ProfilePhotoCategory.avatar, child: Text('老人头像')),
              DropdownMenuItem(
                  value: ProfilePhotoCategory.family, child: Text('家庭照片')),
              DropdownMenuItem(
                  value: ProfilePhotoCategory.memory, child: Text('经历照片')),
              DropdownMenuItem(
                  value: ProfilePhotoCategory.daily, child: Text('日常照片')),
              DropdownMenuItem(
                  value: ProfilePhotoCategory.other, child: Text('其他')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _photoCategory = value;
                _photoFamilyMemberId = null;
                _photoMemoryEventId = null;
              });
            },
          ),
          const SizedBox(height: 10),
          if (_photoCategory == ProfilePhotoCategory.family)
            DropdownButtonFormField<int>(
              initialValue: _photoFamilyMemberId,
              decoration: _inputDecoration('关联亲属'),
              items: _familyMembers
                  .map(
                    (row) => DropdownMenuItem(
                      value: (row['id'] as num).toInt(),
                      child: Text(
                        '${_string(row['relation']).isEmpty ? '亲属' : _string(row['relation'])} · ${_string(row['name'])}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _photoFamilyMemberId = value),
            ),
          if (_photoCategory == ProfilePhotoCategory.memory)
            DropdownButtonFormField<int>(
              initialValue: _photoMemoryEventId,
              decoration: _inputDecoration('关联经历'),
              items: _memoryEvents
                  .map(
                    (row) => DropdownMenuItem(
                      value: (row['id'] as num).toInt(),
                      child: Text(_string(row['title']).isEmpty
                          ? '未命名经历'
                          : _string(row['title'])),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _photoMemoryEventId = value),
            ),
          if (_photoCategory == ProfilePhotoCategory.family ||
              _photoCategory == ProfilePhotoCategory.memory)
            const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('选择照片'),
            ),
          ),
          const SizedBox(height: 10),
          _Input(label: kIsWeb ? '照片名称' : '照片文件路径', controller: _photoPath),
          _Input(label: '标题/说明', controller: _photoCaption),
          _Input(label: '拍摄时间', controller: _photoTime),
          _Input(label: '拍摄地点', controller: _photoLocation),
          _Input(label: '照片里的人', controller: _photoPeople),
          SwitchListTile(
            value: _photoFavorite,
            contentPadding: EdgeInsets.zero,
            title: const Text('重点照片'),
            onChanged: (value) => setState(() => _photoFavorite = value),
          ),
          const SizedBox(height: 8),
          _Subhead(label: '照片库'),
          if (_photos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无照片。',
                style: TextStyle(color: AppTheme.textSoft, fontSize: 18),
              ),
            )
          else
            ..._photos.map(_photoTile),
          const SizedBox(height: 16),
          const _Subhead(label: '视频库'),
          if (_videos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无视频。可在陪伴页用「+」上传。',
                style: TextStyle(color: AppTheme.textSoft, fontSize: 18),
              ),
            )
          else
            ..._videos.map(_videoTile),
        ],
      ),
    );
  }

  Widget _familyTile(Map<String, dynamic> row) {
    final relation = _string(row['relation']);
    final name = _string(row['name']);
    final title = relation.isEmpty && name.isEmpty
        ? '未命名亲属'
        : '${relation.isEmpty ? '亲属' : relation} · ${name.isEmpty ? '未命名' : name}';
    final isActive = (row['is_active'] as int?) != 0;
    return _ListTileShell(
      title: title,
      subtitle: [
        _string(row['birthday']),
        _string(row['location']),
        _string(row['contact_freq']),
        _string(row['notes']),
        if (!isActive) '已标记为不再联系',
      ].where((e) => e.trim().isNotEmpty).join('；'),
      trailing: IconButton(
        tooltip: '删除',
        onPressed: () => _deleteFamilyMember(row),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }

  Widget _nearbyTile(NearbyPersonModel person) {
    final confirmed =
        (person.metadata?['confirmed_as_family_member'] as bool?) ??
            (person.metadata?['family_member_id'] != null);
    return _ListTileShell(
      title:
          '${person.relation?.isNotEmpty == true ? person.relation : '亲属'} · ${person.name ?? '未命名'}',
      subtitle: [
        person.phone,
        person.location ?? person.address,
        person.note,
      ].where((e) => e != null && e.trim().isNotEmpty).join('；'),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: confirmed ? '已确认' : '确认入亲属表',
            onPressed: confirmed ? null : () => _confirmNearby(person.id),
            icon: Icon(
              confirmed
                  ? Icons.verified_rounded
                  : Icons.playlist_add_check_rounded,
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _deleteNearbyPerson(person),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _memoryTile(Map<String, dynamic> row) {
    final title =
        _string(row['title']).isEmpty ? '未命名经历' : _string(row['title']);
    final time = _string(row['event_time']);
    return _ListTileShell(
      title: time.isEmpty ? title : '$time · $title',
      subtitle: _string(row['description']),
      trailing: IconButton(
        tooltip: '删除',
        onPressed: () => _deleteMemoryEvent(row),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }

  Widget _photoTile(ProfilePhotoModel photo) {
    final title = photo.caption?.trim().isEmpty == false
        ? photo.caption!
        : _photoCategoryLabel(photo.category);
    return _ListTileShell(
      leading: _photoPreview(photo.filePath),
      title: title,
      subtitle: [
        _photoCategoryLabel(photo.category),
        photo.photoTime,
        photo.location,
        photo.peopleInvolved,
      ].where((e) => e != null && e.trim().isNotEmpty).join('；'),
      trailing: Wrap(
        spacing: 0,
        children: [
          IconButton(
            tooltip: photo.isFavorite ? '取消重点' : '标为重点',
            onPressed: () async {
              await LocalDatabase.setProfilePhotoFavorite(
                photo.id,
                !photo.isFavorite,
              );
              await _afterDataChanged();
            },
            icon: Icon(
              photo.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: photo.isFavorite ? AppTheme.accent : null,
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _deletePhoto(photo),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Widget _videoTile(ProfileVideoModel video) {
    final title = video.caption?.trim().isNotEmpty == true
        ? video.caption!
        : '家庭视频';
    return _ListTileShell(
      leading: const Icon(Icons.videocam_rounded, color: AppTheme.primaryDeep),
      title: title,
      subtitle: [
        video.videoTime,
        video.location,
        video.peopleInvolved,
      ].where((e) => e != null && e.trim().isNotEmpty).join('；'),
      trailing: IconButton(
        tooltip: '删除',
        onPressed: () => _deleteVideo(video),
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }

  Widget _photoPreview(String path) {
    if (path.startsWith('data:image/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          path,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 52,
            height: 52,
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }
    if (kIsWeb) {
      return const Icon(Icons.photo_rounded, color: AppTheme.primaryDeep);
    }
    final file = File(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        file,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          width: 52,
          height: 52,
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }

  String _photoCategoryLabel(ProfilePhotoCategory category) {
    return switch (category) {
      ProfilePhotoCategory.avatar => '老人头像',
      ProfilePhotoCategory.family => '家庭照片',
      ProfilePhotoCategory.memory => '经历照片',
      ProfilePhotoCategory.daily => '日常照片',
      ProfilePhotoCategory.other => '其他',
    };
  }
}

class _StepItem {
  _StepItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _StepPicker extends StatelessWidget {
  const _StepPicker({
    required this.items,
    required this.current,
    required this.onChanged,
  });

  final List<_StepItem> items;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _StepButton(
              index: i + 1,
              label: items[i].label,
              active: current == i,
              done: current > i,
              onTap: () => onChanged(i),
            ),
          ),
          if (i != items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.index,
    required this.label,
    required this.active,
    required this.done,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool active;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color borderColor;
    if (active) {
      bg = AppTheme.primary;
      fg = Colors.white;
      borderColor = AppTheme.primary;
    } else if (done) {
      bg = AppTheme.surface2;
      fg = AppTheme.primaryDeep;
      borderColor = AppTheme.surface2;
    } else {
      bg = AppTheme.surface1;
      fg = AppTheme.textSoft;
      borderColor = AppTheme.borderHairline;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        onTap: onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? Colors.white24 : Colors.transparent,
                  border: Border.all(color: fg, width: 1.4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text,
                      height: 1.2,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: AppTheme.borderHairline,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: maxLines,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w500,
          color: AppTheme.text,
        ),
        decoration: _inputDecoration(label),
      ),
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppTheme.surface1,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    labelStyle: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w500,
      color: AppTheme.textSoft,
    ),
    floatingLabelStyle: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppTheme.primaryDeep,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      borderSide: const BorderSide(color: AppTheme.borderHairline, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      borderSide: const BorderSide(color: AppTheme.borderHairline, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      borderSide:
          const BorderSide(color: AppTheme.primaryDeep, width: 1.6),
    ),
  );
}

class _Subhead extends StatelessWidget {
  const _Subhead({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _ListTileShell extends StatelessWidget {
  const _ListTileShell({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.leading,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (subtitle.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.textSoft,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _BackLine extends StatelessWidget {
  const _BackLine({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            iconSize: 26,
            style: IconButton.styleFrom(
              foregroundColor: AppTheme.primaryDeep,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppTheme.text,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
