# -*- coding: utf-8 -*-
"""Rebuild proverbs.db (schema v4).

Combines:
  1. Non-Kiselev rows from the existing v3 DB (wikiquote-*, refranero,
     lidioms) — kept as-is, no network re-scrape needed.
  2. A fresh Kiselev extraction with the fixed two-layer parser (the v3
     import had a systematic ±1 proverb-equivalent shift).
  3. Optional curated core with Permyakov-style concept keys and Spanish
     regionalisms: tool/data/curated_core.json
     [{text_ru, text_es, text_en, literal_en, concept_key, region,
       equivalence, confidence, notes}, ...]

Schema v4 = v3 columns + concept_key + region; the FTS table is dropped —
both apps now match against an in-memory normalized index.

Usage:  py -3.10 tool/rebuild_db_v4.py [--kiselev-json path] [--public]

--public builds the redistributable database: no Kiselev pairs (a
commercial dictionary) and none of the carried-over rows whose sources
may not be redistributed (Refranero multilingüe, LIdioms). Without the
Kiselev PDF the script builds without Kiselev as well.
"""
import argparse
import json
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APP_DB = os.path.join(HERE, '..', 'assets', 'proverbs', 'proverbs.db')
LEGACY_DB = os.path.join(HERE, '..', '..', 'legacy', 'assets', 'proverbs.db')
CURATED_JSON = os.path.join(HERE, 'data', 'curated_core.json')

COLS = ['text_ru', 'text_es', 'text_en', 'text_de', 'text_fr', 'text_uk',
        'text_tr', 'literal_en', 'source', 'confidence', 'concept_key',
        'region']


# Short tokens that are legitimate words — everything else of length ≤2 in
# quantity signals glyph-gap damage ("Cua ndo un to nto da en ,h ilar").
_OK_SHORT = {
    # es
    'a', 'al', 'de', 'del', 'el', 'la', 'lo', 'le', 'un', 'en', 'es', 'y',
    'o', 'u', 'ni', 'no', 'se', 'si', 'su', 'te', 'tu', 'me', 'mi', 'da',
    'va', 'ha', 'he', 'as', 'ay', 'oh', 'os', 'id', 'ir', 've', 'vi', 'fe',
    'ya', 'yo', 'do', 'di', 'e', 'ti', 'tú', 'él', 'sí',
    # ru
    'а', 'б', 'бы', 'в', 'во', 'да', 'до', 'ж', 'же', 'за', 'и', 'из', 'к',
    'ко', 'ли', 'на', 'не', 'ни', 'но', 'о', 'об', 'он', 'от', 'по', 'с',
    'со', 'та', 'то', 'ты', 'у', 'уж', 'ум', 'что', 'я', 'их', 'им', 'ей',
    'ее', 'её', 'ну', 'мы', 'вы', 'из-', 'ль', 'эх', 'ох', 'ах',
    # en
    'i', 'am', 'an', 'as', 'at', 'be', 'by', 'go', 'he', 'if', 'in', 'is',
    'it', 'my', 'of', 'on', 'or', 'so', 'to', 'up', 'us', 'we',
}


_VOWELISH = set('aeiouyаеёиоуыэюяоу')


def is_damaged(text):
    """True when a text looks glyph-gap damaged ("Cua ndo un to nto da en
    ,h ilar", "расшибет. ,."). Signals, combinable:
      - single-consonant tokens ("h", "n") — near-impossible in real text;
      - punctuation debris (", ." / ". ,." runs);
      - many short fragments that are not real words.
    """
    if not text:
        return False
    tokens = re.findall(r'[^\s]+', text)
    if len(tokens) < 3:
        return False

    hard_singles = 0
    bad_short = 0
    for t in tokens:
        w = re.sub(r'[^a-zá-ÿа-яё]', '', t.lower())
        # Single-letter REAL words (в, к, с, у, y, a, o…) are fine; a lone
        # consonant that isn't a word ("h", "n", "р") is a glyph fragment.
        if len(w) == 1 and w not in _VOWELISH and w not in _OK_SHORT:
            hard_singles += 1
        elif 0 < len(w) <= 2 and w not in _OK_SHORT:
            bad_short += 1

    debris = bool(re.search(r'[,.;]\s+[,.;]', text))

    if hard_singles >= 2:
        return True
    if hard_singles >= 1 and (debris or bad_short >= 1):
        return True
    if debris and bad_short >= 2:
        return True
    total_bad = hard_singles + bad_short
    return total_bad >= 2 and total_bad / len(tokens) > 0.18


def norm_key(ru, es, en=''):
    clean = lambda s: re.sub(r'[^a-zа-яё]+', '', (s or '').lower().replace('ё', 'е'))
    kru, kes = clean(ru), clean(es)
    # Single-language EN rows (wikiquote-en) must not all collapse into one
    # ('', '') bucket — key them by their English text instead.
    ken = clean(en) if not kru and not kes else ''
    return (kru, kes, ken)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--kiselev-json', default=None,
                    help='pre-parsed Kiselev pairs (skips PDF re-parse)')
    ap.add_argument('--extra-json', action='append', default=[],
                    help='extra rows to merge (repeatable)')
    ap.add_argument('--enrich-json', default=None,
                    help='{norm_ru: {text_en, literal_en}} applied to Kiselev rows')
    ap.add_argument('--public', action='store_true',
                    help='redistributable build: no Kiselev, Refranero or LIdioms rows')
    args = ap.parse_args()
    # Sources that may not be redistributed; kept only in a private build.
    private_sources = ('refranero', 'lidioms') if args.public else ()

    rows = []          # dicts keyed by COLS
    seen = set()

    n_damaged = [0]

    def add(rec):
        # Trailing punctuation debris from the layered PDF ("mano. ,.") is
        # repairable — strip it instead of rejecting the row.
        for c in ('text_ru', 'text_es'):
            v = rec.get(c)
            if v:
                rec[c] = re.sub(r'\s*[,.;]\s*[,.;][\s,.;]*$', '.', v).strip()
        # Reject glyph-gap damaged rows ("Заставь дурака ... расши бет" /
        # "Cua ndo un to nto...") — clean duplicates of these pairs exist.
        if is_damaged(rec.get('text_ru')) or is_damaged(rec.get('text_es')):
            n_damaged[0] += 1
            return
        key = norm_key(rec.get('text_ru'), rec.get('text_es'),
                       rec.get('text_en'))
        if key == ('', '', ''):
            return
        if key in seen:
            return
        seen.add(key)
        rows.append({c: rec.get(c) for c in COLS})

    # 1. curated core FIRST — highest quality, wins dedup collisions
    n_curated = 0
    if os.path.exists(CURATED_JSON):
        with open(CURATED_JSON, encoding='utf-8') as f:
            curated = json.load(f)
        for e in curated:
            add({
                'text_ru': e.get('text_ru') or None,
                'text_es': e.get('text_es') or None,
                'text_en': e.get('text_en') or None,
                'literal_en': e.get('literal_en') or None,
                'source': 'curated',
                'confidence': float(e.get('confidence') or 0.9),
                'concept_key': e.get('concept_key') or None,
                'region': e.get('region') or None,
            })
            n_curated += 1
        print(f'curated core: {n_curated} entries')
    else:
        print('curated core: not found (ok, merge later)')

    # 2. fresh Kiselev pairs
    sys.path.insert(0, HERE)
    from build_proverbs_db import parse_kiselev_pdf, DEFAULT_KISELEV_PDF
    if args.public:
        kis = []
        print('kiselev: skipped (--public)')
    elif args.kiselev_json and os.path.exists(args.kiselev_json):
        with open(args.kiselev_json, encoding='utf-8') as f:
            kis = json.load(f)
        print(f'kiselev (from json): {len(kis)} pairs')
    elif os.path.exists(DEFAULT_KISELEV_PDF):
        kis = parse_kiselev_pdf(DEFAULT_KISELEV_PDF)
    else:
        kis = []
        print('kiselev: PDF not found, building without it')

    # 2a. enrich Kiselev with English (pivoted equivalents + MT literals)
    if args.enrich_json and os.path.exists(args.enrich_json):
        with open(args.enrich_json, encoding='utf-8') as f:
            enrich = json.load(f)
        nkey = lambda s: re.sub(r'[^a-zа-я]+', '',
                                (s or '').lower().replace('ё', 'е'))
        n_en = n_lit = 0
        for r in kis:
            e = enrich.get(nkey(r.get('text_ru')))
            if not e:
                continue
            if e.get('text_en') and not r.get('text_en'):
                r['text_en'] = e['text_en']
                n_en += 1
            if e.get('literal_en') and not r.get('literal_en'):
                r['literal_en'] = e['literal_en']
                n_lit += 1
        print(f'kiselev enriched: text_en +{n_en}, literal_en +{n_lit}')

    for r in kis:
        add(r)

    # 2b. extra rows (fresh wiki fetch, native es refranero, ...)
    for path in args.extra_json:
        if not os.path.exists(path):
            print(f'extra json missing: {path}')
            continue
        with open(path, encoding='utf-8') as f:
            extra = json.load(f)
        for r in extra:
            add(r)
        print(f'extra rows merged from {os.path.basename(path)}: {len(extra)}')

    # 3. non-Kiselev rows from the current DB
    kept = 0
    con = sqlite3.connect(APP_DB)
    con.row_factory = sqlite3.Row
    have_cols = {r[1] for r in con.execute('PRAGMA table_info(proverbs)')}
    sel_cols = [c for c in COLS if c in have_cols]
    # kiselev comes fresh from the parser and curated fresh from JSON —
    # never carry either over from the previous build.
    for r in con.execute(
            f"SELECT {', '.join(sel_cols)} FROM proverbs "
            "WHERE source IS NULL OR source NOT IN ('kiselev', 'curated')"):
        rec = dict(r)
        if rec.get('source') in private_sources:
            continue
        add(rec)
        kept += 1
    con.close()
    print(f'non-kiselev rows carried over: {kept}')

    # 3b. prune single-language rows whose text already appears inside a
    # multi-language pair — they'd show up as noisy one-line duplicates in
    # search results next to the full pair.
    def clean(s):
        return re.sub(r'[^a-zа-яё]+', '', (s or '').lower().replace('ё', 'е'))

    def lang_count(r):
        return sum(1 for c in ('text_ru', 'text_es', 'text_en') if r.get(c))

    paired_norms = set()
    for r in rows:
        if lang_count(r) >= 2:
            for c in ('text_ru', 'text_es', 'text_en'):
                if r.get(c):
                    paired_norms.add(clean(r[c]))
    pruned = []
    dropped_single = 0
    for r in rows:
        if lang_count(r) == 1:
            only = next(r[c] for c in ('text_ru', 'text_es', 'text_en') if r.get(c))
            if clean(only) in paired_norms:
                dropped_single += 1
                continue
        pruned.append(r)
    rows = pruned
    print(f'single-language duplicates of pairs dropped: {dropped_single}')
    print(f'glyph-damaged rows rejected: {n_damaged[0]}')
    print(f'total unique rows: {len(rows)}')

    # 4. write both DBs (the legacy desktop app only where it is checked out)
    targets = [APP_DB]
    if os.path.isdir(os.path.dirname(os.path.dirname(os.path.abspath(LEGACY_DB)))):
        targets.append(LEGACY_DB)
    for path in targets:
        path = os.path.abspath(path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path):
            os.remove(path)
        out = sqlite3.connect(path)
        out.execute(f'''
            CREATE TABLE proverbs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                text_ru TEXT, text_es TEXT, text_en TEXT,
                text_de TEXT, text_fr TEXT, text_uk TEXT, text_tr TEXT,
                literal_en TEXT, source TEXT,
                confidence REAL DEFAULT 0.5,
                embedding BLOB,
                concept_key TEXT,
                region TEXT
            )''')
        for c in ('text_ru', 'text_es', 'text_en', 'concept_key'):
            out.execute(f'CREATE INDEX idx_{c} ON proverbs({c})')
        out.executemany(
            f"INSERT INTO proverbs ({', '.join(COLS)}) "
            f"VALUES ({', '.join('?' * len(COLS))})",
            [[r[c] for c in COLS] for r in rows])
        out.commit()
        out.execute('VACUUM')
        out.close()
        size = os.path.getsize(path) / 1024
        print(f'written: {path} ({size:.0f} KB)')

    # 5. stats
    con = sqlite3.connect(APP_DB)
    for label, sql in [
        ('total', 'SELECT COUNT(*) FROM proverbs'),
        ('with ru', "SELECT COUNT(*) FROM proverbs WHERE text_ru IS NOT NULL AND text_ru != ''"),
        ('with es', "SELECT COUNT(*) FROM proverbs WHERE text_es IS NOT NULL AND text_es != ''"),
        ('with en', "SELECT COUNT(*) FROM proverbs WHERE text_en IS NOT NULL AND text_en != ''"),
        ('ru+es pairs', "SELECT COUNT(*) FROM proverbs WHERE text_ru != '' AND text_ru IS NOT NULL AND text_es != '' AND text_es IS NOT NULL"),
        ('with concept_key', "SELECT COUNT(*) FROM proverbs WHERE concept_key IS NOT NULL AND concept_key != ''"),
        ('regional', "SELECT COUNT(*) FROM proverbs WHERE region IS NOT NULL AND region != ''"),
    ]:
        n = con.execute(sql).fetchone()[0]
        print(f'  {label}: {n}')
    print('  by source:', con.execute(
        'SELECT source, COUNT(*) FROM proverbs GROUP BY source ORDER BY 2 DESC').fetchall())
    con.close()


if __name__ == '__main__':
    main()
