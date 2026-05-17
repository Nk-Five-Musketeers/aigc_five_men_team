from server.database import DatabaseManager
import json

print('Starting test: create user')

db = DatabaseManager('elderly_care.db')
profile = {
    "birth_year": "1945年3月",
    "hometown": "湖南长沙",
    "career": "1965-1998 纺织厂工人",
    "hobbies": "听戏、种花、打牌",
    "food_preference": "喜欢清淡，不吃辣",
    "personality": "开朗、爱聊天、重感情",
    "taboo": "不提及已故老伴（太难过）",
    "dialect": "长沙话",
    "avatar_path": "/photos/main.jpg",
    "created_at": "2025/1/15"
}
ok = db.create_user("1", "张秀兰", age=80, profile=profile)
print('create_user returned:', ok)

# Verify by querying the users table directly
import sqlite3
conn = sqlite3.connect('elderly_care.db')
cur = conn.cursor()
cur.execute('SELECT id, name, birth_year, hometown, career, hobbies, food_preference, personality, taboo, dialect, avatar_path, profile_json FROM users WHERE id = ?', ('1',))
row = cur.fetchone()
print('queried row:', row)
if row is None:
    print('ERROR: no row found')
else:
    # show profile_json parsed
    print('profile_json (parsed):', json.loads(row[-1]) if row[-1] else None)
conn.close()
print('Done')
