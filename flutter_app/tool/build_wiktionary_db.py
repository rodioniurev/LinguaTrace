#!/usr/bin/env python3
"""
Download Spanish Wiktionary data from kaikki.org and build SQLite database.
Run: python tool/build_wiktionary_db.py
Output: assets/dict/es_wiktionary.db
"""
import json, sqlite3, urllib.request, gzip, os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(SCRIPT_DIR, '..', 'assets', 'dict', 'es_wiktionary.db')
URL = 'https://kaikki.org/dictionary/Spanish/kaikki.org-dictionary-Spanish.jsonl.gz'

def main():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

    tmp = os.path.join(SCRIPT_DIR, 'es_wikt.jsonl.gz')
    print(f'Downloading Spanish Wiktionary data from kaikki.org...')
    urllib.request.urlretrieve(URL, tmp)

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL,
        pos TEXT,
        gender TEXT,
        definition TEXT,
        etymology TEXT,
        examples TEXT,
        conjugation TEXT,
        prepositions TEXT,
        synonyms TEXT
    )''')

    count = 0
    with gzip.open(tmp, 'rt', encoding='utf-8') as f:
        for line in f:
            try:
                entry = json.loads(line)
                word = entry.get('word', '').strip()
                if not word:
                    continue

                pos = entry.get('pos', '')
                senses = entry.get('senses', [])

                defs = []
                examples = []
                for sense in senses[:5]:
                    for gloss in sense.get('glosses', [])[:2]:
                        defs.append(gloss)
                    for ex in sense.get('examples', [])[:1]:
                        if 'text' in ex:
                            examples.append(ex['text'])

                gender = ''
                for tag in entry.get('tags', []):
                    if tag in ('masculine', 'feminine', 'neuter'):
                        gender = tag[0]
                        break

                etymology = entry.get('etymology_text', '')
                definition = ' | '.join(defs[:3]) if defs else ''

                c.execute(
                    'INSERT INTO words (word, pos, gender, definition, etymology, examples, synonyms) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    (word, pos, gender, definition, etymology[:200] if etymology else '',
                     json.dumps(examples[:2]), '[]')
                )
                count += 1
            except Exception:
                continue

    c.execute('CREATE INDEX idx_word ON words(word)')
    c.execute('CREATE INDEX idx_word_lower ON words(LOWER(word))')
    conn.commit()
    conn.close()

    os.remove(tmp)
    size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)
    print(f'Built {DB_PATH} with {count} entries ({size_mb:.1f} MB)')

if __name__ == '__main__':
    main()
