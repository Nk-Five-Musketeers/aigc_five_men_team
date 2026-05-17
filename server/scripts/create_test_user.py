import os
import json
import sqlite3
import importlib.util

here = os.path.dirname(os.path.abspath(__file__))
server_dir = os.path.join(here, '..')
fixtures_db_dir = os.path.join(server_dir, 'fixtures', 'databases')
os.makedirs(fixtures_db_dir, exist_ok=True)
db_file = os.path.join(fixtures_db_dir, 'test_elderly_care.db')

# 动态加载 server/database.py，避免包导入问题
spec = importlib.util.spec_from_file_location(
    'server_database', os.path.join(server_dir, 'database.py')
)
server_db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_db)
DatabaseManager = getattr(server_db, 'DatabaseManager')

print('Using DB file:', db_file)
manager = DatabaseManager(db_path=db_file)

profile = {
    'birth_year': '1945 年 3月',
    'hometown': '湖南长沙',
    'career': '1965-1998 纺织厂工人',
    'hobbies': '听戏、种花、打牌',
    'food_preference': '清淡，不吃辣',
    'personality': '开朗、爱聊天、重感情',
    'taboo': '不提及已故老伴（太难过）',
    'dialect': '长沙话',
    'avatar_path': '/photos/main.jpg'
}

ok = manager.create_user('test_user_1', '张秀兰', age=81, profile=profile)
print('create_user returned:', ok)

# 打印 users 表结构
conn = sqlite3.connect(db_file)
cur = conn.cursor()
cur.execute("PRAGMA table_info(users)")
cols = cur.fetchall()
print('\nusers table schema:')
for c in cols:
    print(c)

# 查询插入的行
cur.execute('SELECT id, name, profile_json, created_at FROM users WHERE id = ?', ('test_user_1',))
row = cur.fetchone()
print('\nInserted row:')
print(row)

# 显示解析后的 profile_json
if row and row[2]:
    try:
        p = json.loads(row[2])
        print('\nParsed profile_json:')
        for k, v in p.items():
            print(f'{k}: {v}')
    except Exception as e:
        print('Failed to parse profile_json:', e)

conn.close()
print('\nDone.')
