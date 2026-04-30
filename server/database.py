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
            
            # 用户基本信息表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS users (
                    user_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    age INTEGER,
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
                    FOREIGN KEY(user_id) REFERENCES users(user_id)
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
                    FOREIGN KEY(user_id) REFERENCES users(user_id)
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
                    FOREIGN KEY(user_id) REFERENCES users(user_id)
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
                    FOREIGN KEY(user_id) REFERENCES users(user_id)
                )
            ''')
            
            conn.commit()
    
    def create_user(self, user_id: str, name: str, age: Optional[int] = None, profile: Optional[Dict] = None) -> bool:
        """创建新用户"""
        with self.lock:
            try:
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.cursor()
                    profile_json = json.dumps(profile or {})
                    cursor.execute(
                        'INSERT INTO users (user_id, name, age, profile_json) VALUES (?, ?, ?, ?)',
                        (user_id, name, age, profile_json)
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
