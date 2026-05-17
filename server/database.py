"""
数据库模块：存储老人信息、对话历史、日常活动等
"""
import sqlite3
import json
from datetime import datetime
from typing import List, Dict, Optional, Any
import threading

class DatabaseManager:
    """数据库管理器 - 处理所有数据持久化"""
    
    def __init__(self, db_path: str = "elderly_care.db"):
        self.db_path = db_path
        self.lock = threading.Lock()
        self._init_database()
    
    def _init_database(self) -> None:
        """初始化数据库表结构"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # 用户基本信息表（扩展为老人基础信息）
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    birth_year TEXT,
                    hometown TEXT,
                    career TEXT,
                    hobbies TEXT,
                    food_preference TEXT,
                    personality TEXT,
                    taboo TEXT,
                    dialect TEXT,
                    avatar_path TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    profile_json TEXT
                )
            ''')
            
            # 对话历史表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS conversations (
                    conv_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                )
            ''')
            
            # 内存/记忆表 - 存储提取的关键信息
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS memories (
                    memory_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    category TEXT NOT NULL,
                    content TEXT NOT NULL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    last_recalled_at TEXT,
                    recall_count INTEGER DEFAULT 0,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                )
            ''')
            
            # 日常活动记录表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS daily_activities (
                    activity_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    activity_type TEXT NOT NULL,
                    content TEXT NOT NULL,
                    activity_date TEXT NOT NULL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                )
            ''')
            
            # 认知干预记录表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS interventions (
                    intervention_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    intervention_type TEXT NOT NULL,
                    content TEXT NOT NULL,
                    response TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                )
            ''')

            # 经历/事件表 - 存储重要的生活事件与回忆资料
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS life_events (
                    event_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    event_time TEXT,
                    title TEXT,
                    description TEXT,
                    location TEXT,
                    people_involved TEXT,
                    emotion TEXT,
                    photo_paths TEXT,
                    video_paths TEXT,
                    importance INTEGER,
                    source TEXT,
                    verified INTEGER DEFAULT 0,
                    used_count INTEGER DEFAULT 0,
                    last_used TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                )
            ''')
            cursor.execute('CREATE INDEX IF NOT EXISTS idx_life_events_user ON life_events(user_id)')
            
            # 每日生活记录表（早餐/午餐/晚餐/活动/心情等）
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS daily_life_records (
                    record_id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    date TEXT,
                    breakfast TEXT,
                    lunch TEXT,
                    dinner TEXT,
                    activities TEXT,
                    people_met TEXT,
                    places_went TEXT,
                    mood TEXT,
                    raw_extract TEXT,
                    source_dialog_id TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    updated_at TEXT,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                )
            ''')
            cursor.execute('CREATE INDEX IF NOT EXISTS idx_daily_life_user_date ON daily_life_records(user_id, date)')
            
            conn.commit()
    
    def create_user(self, user_id: str, name: str, age: Optional[int] = None, profile: Optional[Dict] = None) -> bool:
        """创建新用户。为了兼容，保留 `user_id` 参数名，但在数据库中使用 `id` 列。额外信息会放到 `profile_json` 中。"""
        with self.lock:
            try:
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.cursor()
                    p = dict(profile or {})
                    if age is not None:
                        # 将年龄保存在 profile 中以兼容旧调用
                        p.setdefault('age', age)
                    profile_json = json.dumps(p)
                    cursor.execute(
                        'INSERT INTO users (id, name, profile_json) VALUES (?, ?, ?)',
                        (user_id, name, profile_json)
                    )
                    conn.commit()
                return True
            except sqlite3.IntegrityError:
                return False
    
    def add_conversation(self, user_id: str, role: str, content: str) -> str:
        """添加对话记录"""
        conv_id = datetime.now().isoformat()
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    'INSERT INTO conversations (conv_id, user_id, role, content) VALUES (?, ?, ?, ?)',
                    (conv_id, user_id, role, content)
                )
                conn.commit()
        return conv_id
    
    def get_conversation_history(self, user_id: str, limit: int = 10) -> List[Dict]:
        """获取用户的对话历史"""
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''SELECT role, content, timestamp FROM conversations 
                       WHERE user_id = ? ORDER BY timestamp DESC LIMIT ?''',
                    (user_id, limit)
                )
                rows = cursor.fetchall()
                return [
                    {'role': row[0], 'content': row[1], 'timestamp': row[2]}
                    for row in reversed(rows)
                ]
    
    def add_memory(self, user_id: str, category: str, content: str) -> str:
        """添加记忆项目"""
        memory_id = datetime.now().isoformat()
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''INSERT INTO memories (memory_id, user_id, category, content) 
                       VALUES (?, ?, ?, ?)''',
                    (memory_id, user_id, category, content)
                )
                conn.commit()
        return memory_id
    
    def get_memories_by_category(self, user_id: str, category: str, limit: int = 5) -> List[Dict]:
        """获取某个类别的记忆"""
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''SELECT memory_id, content, last_recalled_at, recall_count 
                       FROM memories WHERE user_id = ? AND category = ? 
                       ORDER BY last_recalled_at, recall_count LIMIT ?''',
                    (user_id, category, limit)
                )
                rows = cursor.fetchall()
                return [
                    {
                        'memory_id': row[0],
                        'content': row[1],
                        'last_recalled_at': row[2],
                        'recall_count': row[3]
                    }
                    for row in rows
                ]
    
    def recall_memory(self, memory_id: str) -> None:
        """记录记忆的回忆时间和次数"""
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''UPDATE memories SET last_recalled_at = CURRENT_TIMESTAMP, 
                       recall_count = recall_count + 1 WHERE memory_id = ?''',
                    (memory_id,)
                )
                conn.commit()
    
    def add_daily_activity(self, user_id: str, activity_type: str, content: str, activity_date: str) -> str:
        """添加日常活动记录 (activity_type: 'meal', 'exercise', 'medication', 'event', etc.)"""
        activity_id = datetime.now().isoformat()
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''INSERT INTO daily_activities (activity_id, user_id, activity_type, content, activity_date) 
                       VALUES (?, ?, ?, ?, ?)''',
                    (activity_id, user_id, activity_type, content, activity_date)
                )
                conn.commit()
        return activity_id
    
    def get_recent_activities(self, user_id: str, days: int = 7) -> List[Dict]:
        """获取最近几天的活动记录"""
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''SELECT activity_type, content, activity_date FROM daily_activities 
                       WHERE user_id = ? AND date(activity_date) >= date('now', '-' || ? || ' days')
                       ORDER BY activity_date DESC''',
                    (user_id, days)
                )
                rows = cursor.fetchall()
                return [
                    {
                        'activity_type': row[0],
                        'content': row[1],
                        'activity_date': row[2]
                    }
                    for row in rows
                ]
    
    def add_intervention(self, user_id: str, intervention_type: str, content: str) -> str:
        """添加认知干预记录"""
        intervention_id = datetime.now().isoformat()
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''INSERT INTO interventions (intervention_id, user_id, intervention_type, content) 
                       VALUES (?, ?, ?, ?)''',
                    (intervention_id, user_id, intervention_type, content)
                )
                conn.commit()
        return intervention_id
    
    def update_intervention_response(self, intervention_id: str, response: str) -> None:
        """更新干预的响应"""
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    'UPDATE interventions SET response = ? WHERE intervention_id = ?',
                    (response, intervention_id)
                )
                conn.commit()
    
    def get_recent_interventions(self, user_id: str, limit: int = 5) -> List[Dict]:
        """获取最近的干预记录"""
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''SELECT intervention_type, content, response FROM interventions 
                       WHERE user_id = ? ORDER BY created_at DESC LIMIT ?''',
                    (user_id, limit)
                )
                rows = cursor.fetchall()
                return [
                    {
                        'intervention_type': row[0],
                        'content': row[1],
                        'response': row[2]
                    }
                    for row in rows
                ]

    def add_life_event(self,
                       user_id: str,
                       title: str,
                       event_time: Optional[str] = None,
                       description: Optional[str] = None,
                       location: Optional[str] = None,
                       people_involved: Optional[str] = None,
                       emotion: Optional[str] = None,
                       photo_paths: Optional[List[str]] = None,
                       video_paths: Optional[List[str]] = None,
                       importance: Optional[int] = None,
                       source: Optional[str] = None,
                       verified: bool = False) -> str:
        """添加一条经历/事件记录，返回生成的 event_id"""
        event_id = datetime.now().isoformat()
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                pp = json.dumps(photo_paths or [])
                vp = json.dumps(video_paths or [])
                cursor.execute(
                    '''INSERT INTO life_events (event_id, user_id, event_time, title, description, location, people_involved, emotion, photo_paths, video_paths, importance, source, verified) 
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                    (event_id, user_id, event_time, title, description, location, people_involved, emotion, pp, vp, importance, source, 1 if verified else 0)
                )
                conn.commit()
        return event_id

    def get_life_events(self, user_id: str, limit: int = 50) -> List[Dict]:
        """获取某用户的经历事件列表（按创建时间倒序）"""
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''SELECT event_id, event_time, title, description, location, people_involved, emotion, photo_paths, video_paths, importance, source, verified, used_count, last_used, created_at, updated_at 
                       FROM life_events WHERE user_id = ? ORDER BY created_at DESC LIMIT ?''',
                    (user_id, limit)
                )
                rows = cursor.fetchall()
                res = []
                for r in rows:
                    photo_paths = json.loads(r[7]) if r[7] else []
                    video_paths = json.loads(r[8]) if r[8] else []
                    res.append({
                        'event_id': r[0],
                        'event_time': r[1],
                        'title': r[2],
                        'description': r[3],
                        'location': r[4],
                        'people_involved': r[5],
                        'emotion': r[6],
                        'photo_paths': photo_paths,
                        'video_paths': video_paths,
                        'importance': r[9],
                        'source': r[10],
                        'verified': (r[11] == 1),
                        'used_count': r[12],
                        'last_used': r[13],
                        'created_at': r[14],
                        'updated_at': r[15],
                    })
                return res

    def mark_event_verified(self, event_id: str, verified: bool) -> None:
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute('UPDATE life_events SET verified = ? WHERE event_id = ?', (1 if verified else 0, event_id))
                conn.commit()

    def record_event_use(self, event_id: str) -> None:
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute('''UPDATE life_events SET last_used = CURRENT_TIMESTAMP, used_count = used_count + 1 WHERE event_id = ?''', (event_id,))
                conn.commit()

    def add_daily_record(self,
                         user_id: str,
                         date: Optional[str] = None,
                         breakfast: Optional[str] = None,
                         lunch: Optional[str] = None,
                         dinner: Optional[str] = None,
                         activities: Optional[str] = None,
                         people_met: Optional[str] = None,
                         places_went: Optional[str] = None,
                         mood: Optional[str] = None,
                         raw_extract: Optional[Dict] = None,
                         source_dialog_id: Optional[str] = None) -> str:
        """添加每日生活记录，返回 record_id"""
        record_id = datetime.now().isoformat()
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                re_json = json.dumps(raw_extract or {})
                cursor.execute(
                    '''INSERT INTO daily_life_records (record_id, user_id, date, breakfast, lunch, dinner, activities, people_met, places_went, mood, raw_extract, source_dialog_id) 
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                    (record_id, user_id, date, breakfast, lunch, dinner, activities, people_met, places_went, mood, re_json, source_dialog_id)
                )
                conn.commit()
        return record_id

    def get_daily_records(self, user_id: str, limit: int = 100) -> List[Dict]:
        """按创建时间倒序获取每日生活记录"""
        with self.lock:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute(
                    '''SELECT record_id, date, breakfast, lunch, dinner, activities, people_met, places_went, mood, raw_extract, source_dialog_id, created_at, updated_at
                       FROM daily_life_records WHERE user_id = ? ORDER BY created_at DESC LIMIT ?''',
                    (user_id, limit)
                )
                rows = cursor.fetchall()
                res = []
                for r in rows:
                    raw = {}
                    try:
                        raw = json.loads(r[9]) if r[9] else {}
                    except Exception:
                        raw = {}
                    res.append({
                        'record_id': r[0],
                        'date': r[1],
                        'breakfast': r[2],
                        'lunch': r[3],
                        'dinner': r[4],
                        'activities': r[5],
                        'people_met': r[6],
                        'places_went': r[7],
                        'mood': r[8],
                        'raw_extract': raw,
                        'source_dialog_id': r[10],
                        'created_at': r[11],
                        'updated_at': r[12],
                    })
                return res
