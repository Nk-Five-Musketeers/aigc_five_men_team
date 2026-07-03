part of '../data_preentry_screen.dart';

class DataPreentryScreen extends StatefulWidget {
  const DataPreentryScreen({
    super.key,
    required this.ownerUserId,
    required this.onBack,
  });

  final String ownerUserId;
  final VoidCallback onBack;

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
    final photos =
        await LocalDatabase.listProfilePhotosForUser(widget.ownerUserId);

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
    await _loadAll();
    _toast('亲属候选已保存');
  }

  Future<void> _confirmNearby(String id) async {
    final familyId = await LocalDatabase.confirmNearbyPersonAsFamilyMember(id);
    await _loadAll();
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
    await _loadAll();
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
    await _loadAll();
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
          _Subhead(label: '候选列表'),
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
          ..._memoryEvents.take(6).map(_memoryTile),
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
          ..._photos.take(8).map(_photoTile),
        ],
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
            onPressed: () async {
              await LocalDatabase.removeNearbyPerson(person.id);
              await _loadAll();
            },
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
        onPressed: () async {
          await LocalDatabase.deleteMemoryEvent((row['id'] as num).toInt());
          await _loadAll();
        },
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
              await _loadAll();
            },
            icon: Icon(
              photo.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: photo.isFavorite ? AppTheme.accent : null,
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () async {
              await LocalDatabase.deleteProfilePhoto(photo.id);
              await _loadAll();
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
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
