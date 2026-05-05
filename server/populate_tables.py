#!/usr/bin/env python3
"""统一的填表/导入脚本：整合原有测试脚本与 auto_importer 的功能。

用法示例：
  python server/populate_tables.py --run auto_import --input server/sample_input.txt --user-id u_unified --db server/elderly_care_unified.db
  python server/populate_tables.py --run test_user --db server/test.db
"""
import sys
import os
import re
import json
import argparse
import sqlite3
from uuid import uuid4
from datetime import datetime

# ensure project root on path so we can import server.database
script_dir = os.path.dirname(__file__)
project_root = os.path.abspath(os.path.join(script_dir, '..'))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from server.database import DatabaseManager


def parse_profile(text):
    profile = {}
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        m = re.match(r'^(?:姓名|name)[:：]\s*(.+)$', line)
        if m:
            profile['name'] = m.group(1).strip(); continue
        m = re.match(r'^(?:出生年份|出生|birth)[：:\s]*(.+)$', line)
        if m:
            profile['birth_year'] = m.group(1).strip(); continue
        m = re.match(r'^(?:籍贯|家乡|hometown)[:：]\s*(.+)$', line)
        if m:
            profile['hometown'] = m.group(1).strip(); continue
        m = re.match(r'^(?:职业|职业经历|career)[:：]\s*(.+)$', line)
        if m:
            profile['career'] = m.group(1).strip(); continue
        m = re.match(r'^(?:爱好|兴趣|hobbies)[:：]\s*(.+)$', line)
        if m:
            profile['hobbies'] = m.group(1).strip(); continue
        m = re.match(r'^(?:饮食|饮食习惯|food_pref)[:：]\s*(.+)$', line)
        if m:
            profile['food_preference'] = m.group(1).strip(); continue
        m = re.match(r'^(?:性格|personality)[:：]\s*(.+)$', line)
        if m:
            profile['personality'] = m.group(1).strip(); continue
        m = re.match(r'^(?:忌讳|taboo)[:：]\s*(.+)$', line)
        if m:
            profile['taboo'] = m.group(1).strip(); continue
        m = re.match(r'^(?:方言|dialect)[:：]\s*(.+)$', line)
        if m:
            profile['dialect'] = m.group(1).strip(); continue
        m = re.match(r'^(?:头像|avatar)[:：]\s*(.+)$', line)
        if m:
            profile['avatar_path'] = m.group(1).strip(); continue
        m = re.match(r'^(?:创建时间|created_at)[:：]\s*(.+)$', line)
        if m:
            profile['created_at'] = m.group(1).strip(); continue
    return profile


def parse_nearby_people(text):
    people = []
    rel_keywords = r'(大儿子|儿子|女儿|朋友|老伴|妻子|丈夫|孙子|孙女|姐姐|弟弟|先生|太太|伴侣)'
    for line in text.splitlines():
        s = line.strip()
        if not s: continue
        m = re.search(r'我的?\s*' + rel_keywords + r'\s*([\u4e00-\u9fff·]{2,6})', s)
        if m:
            rel = m.group(1); name = m.group(2)
            people.append({'name': name, 'relation': rel}); continue
        m = re.match(r'([\u4e00-\u9fff·]{2,6})\s*[,，]\s*' + rel_keywords, s)
        if m:
            name = m.group(1); rel = m.group(2)
            people.append({'name': name, 'relation': rel}); continue
        m = re.match(rel_keywords + r'[:：\-]\s*([\u4e00-\u9fff·]{2,6})', s)
        if m:
            rel = m.group(1); name = m.group(2)
            people.append({'name': name, 'relation': rel}); continue
        if '联系频率' in s or '照片' in s or '生日' in s or '居住' in s:
            if people:
                last = people[-1]
                m = re.search(r'照片[:：]\s*([^\s,，]+)', s)
                if m: last['photo_path'] = m.group(1)
                m = re.search(r'生日[:：]\s*([^\s,，]+)', s)
                if m: last['birthday'] = m.group(1)
                m = re.search(r'居住[:：]\s*([^\s,，]+)', s)
                if m: last['location'] = m.group(1)
                m = re.search(r'联系频率[:：]\s*([^\s,，]+)', s)
                if m: last['contact_freq'] = m.group(1)
                m = re.search(r'备注[:：]\s*(.+)$', s)
                if m: last['note'] = m.group(1).strip()
    return people


def parse_life_events(text):
    events = []
    for line in text.splitlines():
        s = line.strip()
        if not s: continue
        if re.search(r'\d{4}年', s) and re.search(r'(工作|进入|结婚|出生|参加|毕业|入伍|迁入|移居)', s):
            m = re.search(r'(\d{4}年[^,，;；]*)', s)
            event_time = m.group(1) if m else None
            title = s[:60]
            events.append({'event_time': event_time, 'title': title, 'description': s})
    return events


def parse_daily_records(text):
    records = []
    for line in text.splitlines():
        s = line.strip()
        if not s: continue
        mdate = re.search(r'(\d{4}[-/年]\d{1,2}[-/月]?\d{0,2}|\d{4}年\d{1,2}月|\d{4}年)', s)
        if mdate and any(k in s for k in ('早餐', '午餐', '晚餐', '活动', '心情')):
            record = {'date': mdate.group(0)}
            m = re.search(r'早餐[:：]\s*([^\s，,]+(?:[，,][^\s，,]+)*)', s)
            if m: record['breakfast'] = m.group(1)
            m = re.search(r'午餐[:：]\s*([^\s，,]+(?:[，,][^\s，,]+)*)', s)
            if m: record['lunch'] = m.group(1)
            m = re.search(r'晚餐[:：]\s*([^\s，,]+(?:[，,][^\s，,]+)*)', s)
            if m: record['dinner'] = m.group(1)
            m = re.search(r'活动[:：]\s*(.+)$', s)
            if m: record['activities'] = m.group(1).strip()
            m = re.search(r'见[了]?谁[:：]?\s*(.+)$', s)
            if m: record['people_met'] = m.group(1).strip()
            m = re.search(r'去[了]?哪(?:儿|里)[:：]?\s*(.+)$', s)
            if m: record['places_went'] = m.group(1).strip()
            m = re.search(r'心情[:：]\s*(.+)$', s)
            if m: record['mood'] = m.group(1).strip()
            m = re.search(r'原始提取[:：]\s*(\{.+\})', s)
            if m:
                try:
                    record['raw_extract'] = json.loads(m.group(1))
                except Exception:
                    record['raw_extract'] = {'raw': m.group(1)}
            records.append(record)
        else:
            if any(k in s for k in ('早餐', '午餐', '晚餐', '活动', '心情', '见了', '去了')):
                record = {}
                m = re.search(r'(\d{4}[-/年]\d{1,2}[-/月]?\d{0,2})', s)
                if m: record['date'] = m.group(1)
                m = re.search(r'早餐[:：]\s*([^，,]+)', s)
                if m: record['breakfast'] = m.group(1).strip()
                m = re.search(r'午餐[:：]\s*([^，,]+)', s)
                if m: record['lunch'] = m.group(1).strip()
                m = re.search(r'晚餐[:：]\s*([^，,]+)', s)
                if m: record['dinner'] = m.group(1).strip()
                m = re.search(r'活动[:：]\s*(.+)$', s)
                if m: record['activities'] = m.group(1).strip()
                m = re.search(r'见[了]?谁[:：]?\s*(.+)$', s)
                if m: record['people_met'] = m.group(1).strip()
                m = re.search(r'去[了]?哪(?:儿|里)[:：]?\s*(.+)$', s)
                if m: record['places_went'] = m.group(1).strip()
                m = re.search(r'心情[:：]\s*(.+)$', s)
                if m: record['mood'] = m.group(1).strip()
                if record: records.append(record)
    return records


def insert_nearby_into_db(conn, people, owner_user_id):
    cur = conn.cursor()
    cur.execute('''CREATE TABLE IF NOT EXISTS nearby_people(
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        name TEXT,
        relation TEXT,
        photo_path TEXT,
        phone TEXT,
        birthday TEXT,
        location TEXT,
        address TEXT,
        contact_freq TEXT,
        note TEXT,
        is_emergency_contact INTEGER DEFAULT 0,
        distance_meters REAL,
        is_active INTEGER DEFAULT 1,
        metadata TEXT,
        created_at TEXT,
        updated_at TEXT
    )''')
    for p in people:
        pid = str(uuid4())
        cur.execute('INSERT OR REPLACE INTO nearby_people (id, owner_user_id, name, relation, photo_path, birthday, location, contact_freq, note, is_active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    (pid, owner_user_id, p.get('name'), p.get('relation'), p.get('photo_path'), p.get('birthday'), p.get('location'), p.get('contact_freq'), p.get('note'), 1, datetime.now().isoformat()))
    conn.commit()


def insert_test_user(db_path, user_id='u_test_1'):
    dm = DatabaseManager(db_path=db_path)
    profile = {
        'birth_year': '1945年3月',
        'hometown': '湖南长沙',
        'career': '1965-1998 纺织厂工人',
        'hobbies': '听戏、种花、打牌',
        'food_preference': '喜欢清淡，不吃辣',
        'personality': '开朗、爱聊天、重感情',
        'taboo': '不提及已故老伴（太难过）',
        'dialect': '长沙话',
        'avatar_path': '/photos/main.jpg',
        'created_at': '2025/1/15'
    }
    ok = dm.create_user(user_id, '张秀兰', profile=profile)
    print('create_user returned:', ok)


def insert_test_nearby(db_path, owner_user_id='u_test_1'):
    conn = sqlite3.connect(db_path)
    insert_nearby_into_db(conn, [
        {'name': '李建国', 'relation': '大儿子', 'photo_path': '/photos/lijg.jpg', 'birthday': '1970年5月', 'location': '北京', 'contact_freq': '每月一次', 'note': '老人最挂念的人'}
    ], owner_user_id)
    conn.close()
    print('Inserted nearby person for', owner_user_id)


def insert_test_event(db_path, user_id='u_test_1'):
    dm = DatabaseManager(db_path=db_path)
    eid = dm.add_life_event(user_id=user_id, title='进纺织厂工作', event_time='1968年夏天', description='23岁进入长沙第三纺织厂，开始学徒并很快成为正式工。', importance=5, source='家属录入', verified=True)
    print('Inserted life_event', eid)


def insert_test_daily(db_path, user_id='u_test_1'):
    dm = DatabaseManager(db_path=db_path)
    rid = dm.add_daily_record(user_id=user_id, date='2026-05-05', breakfast='小米粥、馒头', lunch='饺子', dinner='米饭炒青菜', activities='上午浇花，下午看电视', people_met='邻居王阿姨来串门', places_went='下楼在院子里走了一圈', mood='挺高兴的', raw_extract={'source':'ai','dialog_id':42}, source_dialog_id='42')
    print('Inserted daily record', rid)


def auto_import_file(db_path, input_path, user_id=None):
    txt = ''
    with open(input_path, 'r', encoding='utf-8') as f:
        txt = f.read()
    profile = parse_profile(txt)
    nearby = parse_nearby_people(txt)
    events = parse_life_events(txt)
    daily = parse_daily_records(txt)

    dm = DatabaseManager(db_path=db_path)
    uid = user_id or ('user_' + uuid4().hex[:8])
    name = profile.get('name', uid)
    ok = dm.create_user(uid, name, profile=profile)
    if not ok:
        print('User exists; updating columns if provided')
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cols = ['birth_year','hometown','career','hobbies','food_preference','personality','taboo','dialect','avatar_path','created_at']
    updates = []
    params = []
    for c in cols:
        if profile.get(c) is not None:
            updates.append(f"{c} = ?")
            params.append(profile.get(c))
    if updates:
        params.append(uid)
        cur.execute(f"UPDATE users SET {', '.join(updates)} WHERE id = ?", params)
        conn.commit()
    if nearby:
        insert_nearby_into_db(conn, nearby, uid)
    for e in events:
        dm.add_life_event(user_id=uid, title=e.get('title') or '事件', event_time=e.get('event_time'), description=e.get('description'))
    for r in daily:
        dm.add_daily_record(user_id=uid, date=r.get('date'), breakfast=r.get('breakfast'), lunch=r.get('lunch'), dinner=r.get('dinner'), activities=r.get('activities'), people_met=r.get('people_met'), places_went=r.get('places_went'), mood=r.get('mood'), raw_extract=r.get('raw_extract'), source_dialog_id=str(r.get('raw_extract', {}).get('dialog_id') or r.get('source_dialog_id') or ''))
    print('Auto-import finished for user:', uid)
    conn.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--run', choices=['test_user','test_nearby','test_event','test_daily','auto_import','all'], default='all')
    p.add_argument('--db', default=os.path.join(script_dir, 'elderly_care_unified.db'))
    p.add_argument('--input', default=os.path.join(script_dir, 'sample_input.txt'))
    p.add_argument('--user-id', default=None)
    args = p.parse_args()

    if args.run in ('test_user','all'):
        insert_test_user(args.db, user_id=args.user_id or 'u_test_1')
    if args.run in ('test_nearby','all'):
        insert_test_nearby(args.db, owner_user_id=args.user_id or 'u_test_1')
    if args.run in ('test_event','all'):
        insert_test_event(args.db, user_id=args.user_id or 'u_test_1')
    if args.run in ('test_daily','all'):
        insert_test_daily(args.db, user_id=args.user_id or 'u_test_1')
    if args.run in ('auto_import','all'):
        if not os.path.exists(args.input):
            print('Input file not found:', args.input)
        else:
            auto_import_file(args.db, args.input, args.user_id)


if __name__ == '__main__':
    main()
