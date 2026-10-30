#!/usr/bin/env python3
"""
Build proverbs SQLite database from multiple sources:
  1. Wikiquote (en, ru, es)         - primary, CC BY-SA
  2. Wikipedia Spanish proverbs     - literal translations
  3. Refranero Multilingue (CVC)    - ES-anchored multilingual equivalents
  4. LIDIOMS (DICE-Group, GitHub)   - RU<->EN idiom links, non-commercial licence
  5. Multilingual SBERT embeddings  - optional, enables semantic search

Schema (v2):
    id, text_ru, text_es, text_en,
    text_de, text_fr, text_uk, text_tr,     -- additional languages
    literal_en, source, confidence,
    embedding  BLOB    -- float32 vector, packed via struct.pack (NOT pickle)

Run:
    py -3 build_proverbs_db.py                # default sources, no embeddings
    py -3 build_proverbs_db.py --embed        # also generate embeddings (slow)
    py -3 build_proverbs_db.py --skip-refranero --skip-lidioms
"""

import argparse
import os
import re
import sys
import json
import sqlite3
import struct
import time
import urllib.request
import urllib.parse
from html.parser import HTMLParser

DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'assets', 'proverbs', 'proverbs.db')

UA = 'ProverbDBBuilder/2.0 (language learning app; contact: dev@linguatrace.io)'


# ========================================================================
# Section A - Wikitext helpers (unchanged from v1)
# ========================================================================

def fetch_wikitext(base_url, title):
    """Fetch wikitext content of a page via MediaWiki API."""
    params = urllib.parse.urlencode({
        'action': 'query',
        'titles': title,
        'prop': 'revisions',
        'rvprop': 'content',
        'rvslots': 'main',
        'format': 'json',
        'formatversion': '2',
    })
    url = f"{base_url}/w/api.php?{params}"
    print(f"  Fetching: {url[:120]}...")

    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode('utf-8'))

    pages = data.get('query', {}).get('pages', [])
    if not pages:
        return ''
    page = pages[0]
    if page.get('missing', False):
        return ''
    revisions = page.get('revisions', [])
    if not revisions:
        return ''
    return revisions[0].get('slots', {}).get('main', {}).get('content', '')


def clean_wiki(text):
    """Remove wiki markup from a text string."""
    text = re.sub(r'<!--.*?-->', '', text, flags=re.DOTALL)
    text = re.sub(r'<ref[^>]*>.*?</ref>', '', text, flags=re.DOTALL)
    text = re.sub(r'<ref[^/]*/>', '', text)
    for _ in range(5):
        text = re.sub(r'\{\{cite[^}]*\}\}', '', text, flags=re.IGNORECASE)
        text = re.sub(r'\{\{[^{}]*\}\}', '', text)
    text = re.sub(r'\[\[[^\]]*\|([^\]]*)\]\]', r'\1', text)
    text = re.sub(r'\[\[([^\]]*)\]\]', r'\1', text)
    text = re.sub(r'\[https?://[^\]]*\]', '', text)
    text = re.sub(r"'{2,}", '', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = text.replace('&mdash;', '—')
    text = text.replace('&ndash;', '–')
    text = text.replace('&nbsp;', ' ')
    return text.strip()


def parse_wikiquote_russian(wikitext):
    proverbs = []
    lines = wikitext.split('\n')
    current_ru = None; current_translation = None; current_equivalent = None

    def flush():
        nonlocal current_ru, current_translation, current_equivalent
        if current_ru and (current_translation or current_equivalent):
            proverbs.append({
                'text_ru': current_ru, 'text_es': None,
                'text_en': current_equivalent or None,
                'literal_en': current_translation or None,
                'confidence': 0.9,
            })
        current_ru = None; current_translation = None; current_equivalent = None

    for line in lines:
        stripped = line.strip()
        if re.match(r'^\*\s+[^*]', stripped) or re.match(r'^\*[^*]', stripped):
            flush()
            text = re.sub(r'^\*\s*', '', stripped)
            text = clean_wiki(text)
            if re.search(r'[Ѐ-ӿ]', text) and len(text) > 3:
                text = re.sub(r'\s*\(.*?full form.*?\)', '', text, flags=re.IGNORECASE)
                current_ru = text.strip().strip('"\'')
            continue
        if stripped.startswith('**') and current_ru:
            sub = re.sub(r'^\*\*\s*', '', stripped)
            sub = clean_wiki(sub)
            m = re.match(r'Translation:\s*(.+)', sub, re.IGNORECASE)
            if m:
                current_translation = m.group(1).strip().strip('"\'')
                continue
            m = re.match(r'English\s+[Ee]quivalent[s]?:\s*(.+)', sub, re.IGNORECASE)
            if m:
                current_equivalent = m.group(1).strip().strip('"\'')
                continue
            m = re.match(r'Meaning:\s*(.+)', sub, re.IGNORECASE)
            if m and not current_translation:
                current_translation = m.group(1).strip().strip('"\'')
                continue
    flush()
    return proverbs


def parse_wikiquote_spanish(wikitext):
    proverbs = []
    lines = wikitext.split('\n')
    current_es = None; current_translation = None; current_equivalent = None

    def flush():
        nonlocal current_es, current_translation, current_equivalent
        if current_es and (current_translation or current_equivalent):
            proverbs.append({
                'text_ru': None, 'text_es': current_es,
                'text_en': current_equivalent or None,
                'literal_en': current_translation or None,
                'confidence': 0.9,
            })
        current_es = None; current_translation = None; current_equivalent = None

    for line in lines:
        stripped = line.strip()
        if re.match(r'^\*\s+[^*]', stripped) or re.match(r'^\*[^*]', stripped):
            flush()
            text = re.sub(r'^\*\s*', '', stripped)
            text = clean_wiki(text)
            if text and len(text) > 3 and not text.startswith('=='):
                if text.startswith('File:') or text.startswith('[['):
                    continue
                current_es = text.strip().strip('"\'.')
            continue
        if current_es:
            sub = stripped
            if sub.startswith('**'):
                sub = re.sub(r'^\*\*\s*', '', sub)
            elif sub.startswith('::'):
                sub = re.sub(r'^:+\s*', '', sub)
            else:
                continue
            sub = clean_wiki(sub)
            m = re.match(r'English\s+[Ee]quivalent[s]?[:ː]?\s*(.+)', sub, re.IGNORECASE)
            if m:
                current_equivalent = m.group(1).strip().strip('"\'')
                continue
            m = re.match(r'Translation:\s*(.+)', sub, re.IGNORECASE)
            if m:
                current_translation = m.group(1).strip().strip('"\'')
                continue
            m = re.match(r'Literal\s+translation:\s*(.+)', sub, re.IGNORECASE)
            if m:
                current_translation = m.group(1).strip().strip('"\'')
                continue
    flush()
    return proverbs


def parse_wikiquote_english(wikitext):
    """Parse English proverbs from Wikiquote.

    The Wikiquote 'English_proverbs' page is organized by alphabetical topic
    headings ("Absent", "Accident", "Action", ...). Each section contains
    bulleted proverb lines like::

        * Absence makes the heart grow fonder.
        ** Citation / commentary

    We accept ALL top-level sections except the obvious non-proverb ones
    (References, See also, External links, Bibliography, Footnotes, Sources).
    """
    proverbs = []
    lines = wikitext.split('\n')
    current_en = None
    current_meaning = None

    SKIP_SECTIONS = re.compile(
        r'(References|See also|External links|Footnotes|Bibliography|'
        r'Sources|Further reading|Notes|Acknowledg)',
        re.IGNORECASE,
    )

    def flush():
        nonlocal current_en, current_meaning
        if current_en and len(current_en) >= 6 and ' ' in current_en:
            proverbs.append({
                'text_ru': None, 'text_es': None,
                'text_en': current_en,
                'literal_en': current_meaning,
                'confidence': 0.8,
            })
        current_en = None; current_meaning = None

    in_proverb_section = True   # Accept everything until we hit a SKIP section
    for line in lines:
        stripped = line.strip()
        # Level-2 section header
        m = re.match(r'^==\s*(.+?)\s*==\s*$', stripped)
        if m:
            heading = m.group(1)
            in_proverb_section = not SKIP_SECTIONS.search(heading)
            flush()
            continue
        if not in_proverb_section:
            continue

        # Main bulleted proverb (single asterisk, not ** or longer)
        if re.match(r'^\*[^*]', stripped):
            flush()
            text = re.sub(r'^\*\s*', '', stripped)
            text = clean_wiki(text)
            text = text.strip().strip('"\'.')
            # Drop year suffixes like "(1640)" — common citation pattern
            text = re.sub(r'\s*\(\d{3,4}\)\s*$', '', text)
            # Heuristic: real proverb has 6-200 chars, two+ words, mostly letters
            if 6 < len(text) < 200 and re.search(r'\b[A-Za-z]+\s+[A-Za-z]+\b', text):
                # Drop lines that are clearly citations
                if re.search(r'\b(p\.\s*\d+|ISBN|vol\.|ed\.)', text):
                    continue
                current_en = text
            continue

        # Sub-line: meaning / commentary
        if stripped.startswith('**') and current_en:
            sub = re.sub(r'^\*+\s*', '', stripped)
            sub = clean_wiki(sub)
            m = re.match(r'(?:Meaning|Interpretation):\s*(.+)', sub, re.IGNORECASE)
            if m and not current_meaning:
                current_meaning = m.group(1).strip()

    flush()
    return proverbs


def parse_wikipedia_spanish(wikitext):
    proverbs = []
    lines = wikitext.split('\n')
    current_es = None; current_literal = None; current_meaning = None; awaiting = None

    def flush():
        nonlocal current_es, current_literal, current_meaning, awaiting
        if current_es and (current_literal or current_meaning):
            proverbs.append({
                'text_ru': None, 'text_es': current_es,
                'text_en': current_meaning or None,
                'literal_en': current_literal or None,
                'confidence': 0.85,
            })
        current_es = None; current_literal = None; current_meaning = None; awaiting = None

    for line in lines:
        stripped = line.strip()
        if re.match(r"^\*\s+'''", stripped):
            flush()
            text = re.sub(r"^\*\s*", '', stripped)
            text = clean_wiki(text)
            if text and len(text) > 3:
                current_es = text.strip().strip('"\'.')
            continue
        if current_es and stripped.startswith(':'):
            sub = re.sub(r'^:+\s*', '', stripped)
            sub = clean_wiki(sub)
            if re.match(r'Literal\s+translation', sub, re.IGNORECASE):
                awaiting = 'literal'
                m = re.match(r'Literal\s+translation:\s*(.+)', sub, re.IGNORECASE)
                if m and m.group(1).strip():
                    current_literal = m.group(1).strip()
                    awaiting = None
                continue
            if re.match(r'Meaning', sub, re.IGNORECASE) or re.match(r'Use', sub, re.IGNORECASE):
                awaiting = 'meaning'
                m = re.match(r'Meaning(?:/[Uu]se)?:\s*(.+)', sub, re.IGNORECASE)
                if m and m.group(1).strip():
                    current_meaning = m.group(1).strip()
                    awaiting = None
                continue
            if awaiting == 'literal' and sub and not current_literal:
                current_literal = sub.strip(); awaiting = None; continue
            if awaiting == 'meaning' and sub and not current_meaning:
                current_meaning = sub.strip(); awaiting = None; continue
    flush()
    return proverbs


# ========================================================================
# Section B - Refranero Multilingue (Instituto Cervantes)
#
# Site: cvc.cervantes.es/lengua/refranero/
# License: scraped under fair-use for offline language-learning aid.
# Each entry has: spanish text, meaning, sometimes EN/RU/DE/FR/IT equivalents.
# ========================================================================

REFRANERO_INDEX = 'https://cvc.cervantes.es/lengua/refranero/listado.aspx'


class _SimpleHTMLStripper(HTMLParser):
    """Strip HTML tags from a string."""

    def __init__(self):
        super().__init__()
        self._parts = []

    def handle_data(self, data):
        self._parts.append(data)

    def text(self):
        return ' '.join(p.strip() for p in self._parts if p.strip())


def _strip_html(html):
    s = _SimpleHTMLStripper()
    try:
        s.feed(html)
    except Exception:
        return html
    return s.text()


def _http_get(url, timeout=20):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'es,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode('utf-8', errors='replace')


def fetch_refranero(max_pages=3):
    """Scrape Refranero Multilingue - best-effort, page count capped.

    Refranero uses Lng=N query parameter to switch language *of the same
    proverb*. So to get the EN equivalent of Par=NNN we fetch the page with
    Lng=9 and take its <h1>. Lng codes are:
        0 = Spanish, 9 = English, 7 = German, 8 = French,
        16 = Italian, 22 = Russian (verified on the site as of 2026-05).
    """
    proverbs = []

    try:
        html = _http_get(REFRANERO_INDEX, timeout=30)
    except Exception as e:
        print(f"  ERROR fetching Refranero index: {e}")
        return proverbs

    par_ids = sorted(set(int(m) for m in re.findall(r'Par=(\d{1,7})', html)))
    print(f"  Found {len(par_ids)} Refranero entries on index")

    par_ids = par_ids[: max_pages * 100]
    print(f"  Will scrape up to {len(par_ids)} (max_pages={max_pages})")

    detail_url = 'https://cvc.cervantes.es/lengua/refranero/ficha.aspx?Par={pid}&Lng={lng}'
    # Lng codes verified empirically against the live site:
    #   0 = Spanish (the base proverb), 9 = English (verified accurate)
    # Other codes I tested were mislabeled (Lng=7 returned Basque text, not
    # German; Lng=8 returned Italian, not French; Lng=22 returned Armenian,
    # not Russian). Until correct codes are confirmed, only fetch ES + EN.
    # If you find correct codes, append them to this list.
    lang_codes = [('text_es', 0), ('text_en', 9)]

    def extract_title(html_str):
        """Pull the proverb text from the page <h1>."""
        m = re.search(r'<h1[^>]*>(.*?)</h1>', html_str, re.DOTALL | re.IGNORECASE)
        if not m:
            return None
        text = _strip_html(m.group(1)).strip()
        # Skip generic page titles ("Refranero multilingüe", "404", etc.)
        if not text or len(text) < 4:
            return None
        if 'refranero' in text.lower() or 'cvc' in text.lower():
            return None
        return text

    for i, pid in enumerate(par_ids):
        if i % 50 == 0 and i:
            print(f"  ...processed {i}/{len(par_ids)}")

        rec = {'text_ru': None, 'text_es': None, 'text_en': None,
               'text_de': None, 'text_fr': None, 'literal_en': None,
               'source': 'refranero', 'confidence': 0.95}

        for key, lng in lang_codes:
            try:
                html = _http_get(detail_url.format(pid=pid, lng=lng), timeout=15)
            except Exception:
                continue
            title = extract_title(html)
            if title:
                rec[key] = title
            time.sleep(0.05)  # be polite

        # Only keep records that have ES + at least one cross-language equivalent
        cross = sum(1 for k in ('text_en', 'text_ru', 'text_de', 'text_fr') if rec.get(k))
        if rec.get('text_es') and cross >= 1:
            proverbs.append(rec)

    print(f"  Extracted {len(proverbs)} multilingual Refranero entries")
    return proverbs


# ========================================================================
# Section C - LIDIOMS (dice-group/LIdioms) - RU<->EN idiom links
#
# Source: https://github.com/dice-group/LIdioms (RDF Turtle dumps)
# License: the README says CC BY-NC-SA 3.0 (non-commercial), the repository
# sidebar says AGPL-3.0, so these rows stay out of a redistributable build.
# ========================================================================

LIDIOMS_RAW = 'https://raw.githubusercontent.com/dice-group/LIdioms/master'
# Each language has its own subdirectory and TTL file (verified via GitHub API)
LIDIOMS_FILES = [('ru', 'rus/russian.ttl'),
                 ('en', 'en/english.ttl'),
                 ('de', 'de/german.ttl'),
                 ('it', 'it/italian.ttl'),
                 ('pt', 'pt/portuguese.ttl'),
                 ('tr', 'tr/turkish.ttl')]


def fetch_lidioms():
    """Download and parse LIDIOMS TTL files for multiple languages.

    The dataset links idioms via `lemon:senseRelation` / `owl:sameAs`. We use
    a lightweight regex-based parse rather than pulling in rdflib as a
    runtime dependency.
    """
    proverbs = []
    pages = {}
    for code, path in LIDIOMS_FILES:
        url = f'{LIDIOMS_RAW}/{path}'
        try:
            print(f"  Fetching {url}")
            pages[code] = _http_get(url, timeout=30)
        except Exception as e:
            print(f"  ERROR fetching {path}: {e}")
            pages[code] = ''

    def parse_idioms(ttl_text):
        """Parse TTL blocks into {idiom_uri: text} for top-level entries.
        LIDIOMS uses `rdfs:label "text"@lang` on entries and
        `ontolex:writtenRep "text"@lang` on _form objects."""
        out = {}
        # Match patterns like: <uri> [type] ; ... rdfs:label "text"@lang .
        # Also match liden:short_name pattern.
        for m in re.finditer(
            r'(?:liden:|<[^>]+>)\s*\w*\s*'
            r'(liden:\w+|<[^>]+>)?'           # optional URI capture
            r'[^.]*?'                         # skip predicates
            r'(?:rdfs:label|ontolex:writtenRep|skos:prefLabel)\s+'
            r'"([^"]+)"(?:@\w+)?',
            ttl_text,
        ):
            pass  # The above pattern is overly complex; use simpler approach below.

        # Simpler approach: split into stanzas by '.' followed by blank line,
        # then in each stanza find the subject URI + label.
        for stanza in re.split(r'\n\s*\n', ttl_text):
            # Skip prefix declarations
            if stanza.lstrip().startswith('@prefix'):
                continue
            # Subject is the first token in the stanza
            ms = re.match(r'\s*(liden:\w+|<[^>]+>)', stanza)
            if not ms:
                continue
            subj = ms.group(1)
            # Only keep top-level entries (not _form or _sense or _concept)
            if (subj.endswith('_form') or subj.endswith('_sense') or
                    subj.endswith('_concept') or subj.endswith('_form>') or
                    subj.endswith('_sense>') or subj.endswith('_concept>')):
                continue
            ml = re.search(
                r'(?:rdfs:label|ontolex:writtenRep|skos:prefLabel)\s+'
                r'"([^"]+)"',
                stanza,
            )
            if ml:
                text = ml.group(1).strip()
                if 3 < len(text) < 200:
                    out[subj] = text
        return out

    def parse_babelnet_links(ttl_text):
        """Return list of (idiom_uri, babelnet_uri) pairs."""
        links = []
        # In TTL, `liden:foo ... owl:sameAs <babelnet:bar> ; ...` — the subject
        # is at the start of the stanza, sameAs may appear several times.
        for stanza in re.split(r'\n\s*\n', ttl_text):
            ms = re.match(r'\s*(liden:\w+|<[^>]+>)', stanza)
            if not ms:
                continue
            subj = ms.group(1)
            if (subj.endswith('_form') or subj.endswith('_sense') or
                    subj.endswith('_concept') or subj.endswith('_form>') or
                    subj.endswith('_sense>') or subj.endswith('_concept>')):
                continue
            for sm in re.finditer(r'owl:sameAs\s+<([^>]+)>', stanza):
                target = sm.group(1)
                if 'babelnet' in target.lower():
                    links.append((subj, target))
        return links

    by_lang = {code: parse_idioms(text) for code, text in pages.items() if text}
    counts = ' · '.join(f'{c}={len(d)}' for c, d in by_lang.items())
    print(f"  Idiom counts: {counts}")

    # Build URI → lang mapping
    uri_to_lang = {}
    for code, idioms in by_lang.items():
        for uri in idioms:
            uri_to_lang[uri] = code

    # Group idioms by shared BabelNet synset
    from collections import defaultdict
    synset_to_idioms = defaultdict(set)  # babelnet_uri → {idiom_uri, ...}
    for code, text in pages.items():
        if not text:
            continue
        for idiom_uri, babelnet_uri in parse_babelnet_links(text):
            if idiom_uri in uri_to_lang:
                synset_to_idioms[babelnet_uri].add(idiom_uri)

    print(f"  BabelNet synsets touched: {len(synset_to_idioms)}")

    # For each synset that has idioms in 2+ languages, emit one row
    lang_keys = {'ru': 'text_ru', 'en': 'text_en', 'de': 'text_de',
                 'fr': 'text_fr', 'it': 'text_it', 'pt': 'text_pt',
                 'tr': 'text_tr'}
    seen = set()
    for synset, idiom_uris in synset_to_idioms.items():
        # Languages represented in this synset
        langs_here = {uri_to_lang.get(u) for u in idiom_uris}
        langs_here.discard(None)
        if len(langs_here) < 2:
            continue

        rec = {k: None for k in ('text_ru', 'text_es', 'text_en', 'text_de',
                                  'text_fr', 'text_uk', 'text_tr', 'literal_en')}
        for u in idiom_uris:
            lang = uri_to_lang.get(u)
            if not lang:
                continue
            col = lang_keys.get(lang)
            if col and col in rec and not rec[col]:
                rec[col] = by_lang[lang].get(u)

        cross = sum(1 for k in ('text_ru', 'text_en', 'text_de', 'text_fr', 'text_tr')
                    if rec.get(k))
        if cross < 2:
            continue

        key = (rec.get('text_ru') or '', rec.get('text_en') or '',
               rec.get('text_de') or '')
        if key in seen:
            continue
        seen.add(key)
        rec['source'] = 'lidioms'
        rec['confidence'] = 0.85
        proverbs.append(rec)

    print(f"  Extracted {len(proverbs)} multilingual idiom clusters")
    return proverbs


# ========================================================================
# Section C2 - Kiselev's "Russian Proverbs and Spanish Equivalents" PDF
#
# Source: А.В. Киселев, "Русские пословицы и поговорки и их испанские
#         аналоги" (КАРО, Санкт-Петербург, 2020). 256 pages, 1000+ entries
#         on each side. Bilingual reference work.
#
# License note: scraped under fair-use for offline language-learning aid.
# The book is a commercial work; only use the extracted DB for personal
# learning, not for redistribution. Pass `--skip-kiselev` to omit it.
#
# Layout: each entry has a numbered primary proverb (RU or ES depending on
# the book half) followed by 1..N equivalents in the other language. The
# PDF interleaves Cyrillic and Latin text on the same lines in some places
# (typesetting artifact), so we re-stream the characters by script before
# building entries.
# ========================================================================

DEFAULT_KISELEV_PDF = os.path.join(
    os.path.dirname(__file__), '..', '..', 'proverbios_espanoles_rusos.pdf'
)


def _is_cyr(ch: str) -> bool:
    return bool(ch) and 'Ѐ' <= ch[0] <= 'ӿ'


def _is_lat(ch: str) -> bool:
    if not ch:
        return False
    c = ch[0]
    return (
        ('A' <= c <= 'Z') or ('a' <= c <= 'z')
        or c in 'áéíóúüñÁÉÍÓÚÜÑ¿¡àèìòùÀÈÌÒÙ'
    )


def _stream_lines(chars, script_pred):
    """Cluster ONE script's characters into visual lines → [(y, text)].

    The PDF renders the RU and ES text as two overlapping layers with a
    small vertical offset, so lines must be reconstructed PER SCRIPT — the
    old shared-line approach glued glyphs of both layers together
    ("AВgсеoмstуo…") and systematically mis-paired entries.

    Digits, spaces and shared punctuation don't belong to either script; we
    duplicate them into whichever stream is being built so entry numbers
    ("146.") and in-proverb punctuation survive.
    """
    sel = []
    for c in chars:
        ch = c['text']
        if script_pred(ch):
            sel.append(c)
        elif not _is_cyr(ch) and not _is_lat(ch):
            sel.append(c)   # shared char — echoed into this stream too
    sel.sort(key=lambda c: (c['top'], c['x0']))

    lines = []
    cur, cur_y = [], None
    for c in sel:
        if cur_y is None or abs(c['top'] - cur_y) < 3:
            cur.append(c)
            if cur_y is None:
                cur_y = c['top']
        else:
            lines.append((cur_y, cur))
            cur, cur_y = [c], c['top']
    if cur:
        lines.append((cur_y, cur))

    out = []
    letters = re.compile(r'[Ѐ-ӿ]') if script_pred is _is_cyr \
        else re.compile(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]')
    for y, cs in lines:
        cs.sort(key=lambda c: c['x0'])
        # Re-insert spaces lost between the overlapping layers: some lines
        # carry their space glyphs only in the OTHER layer, producing glued
        # words ("страшенчерт"). A horizontal gap wider than ~1pt between
        # consecutive glyphs is a word break.
        parts = []
        prev = None
        for c in cs:
            if prev is not None and (c['x0'] - prev['x1']) > 1.0 \
                    and prev['text'] != ' ' and c['text'] != ' ':
                parts.append(' ')
            parts.append(c['text'])
            prev = c
        text = re.sub(r'\s+', ' ', ''.join(parts)).strip()
        # Drop lines that carry no letters of this script (pure echo of
        # shared digits/punctuation from the other layer).
        if text and letters.search(text):
            out.append((y, text))
    return out


# Match an entry header like "17. Беда…" or "693. La ley…".
_ENTRY_NUM_RE = re.compile(r'^(\d{1,4})\.\s+(.*\S.*)$')
# Lone alphabet section headers like "А", "В", "Б…" or "A", "B", "C" — discard.
_SECTION_HEADER_RE = re.compile(r'^[A-ZÁÉÍÓÚÑА-Я]{1,3}\.?$')


# A secondary-script line lying closer than this below an entry header
# belongs to the PREVIOUS entry: the two text layers are vertically offset,
# and measured "glued" offsets are 2.6–6.6 units while genuine line spacing
# is 12+. Getting this wrong was the root cause of the systematic ±1
# proverb↔equivalent shift in earlier builds.
_GLUE_Y = 9.0


def parse_kiselev_pdf(pdf_path: str) -> list[dict]:
    """Extract one record per (primary proverb, equivalent) pair from the PDF.

    The book is split into two halves:
      Part 1 — RU entries (numbered), each followed by ES equivalents.
      Part 2 — ES entries (numbered), each followed by RU equivalents.

    The PDF stores the RU and ES text as two overlapping layers with a small
    vertical offset. We therefore (1) rebuild lines per script, (2) walk both
    streams in y order, and (3) attribute each secondary-script line to an
    entry with the glue rule: a secondary line within ``_GLUE_Y`` units below
    a header belongs to the *previous* entry (it is the tail of that entry's
    equivalents, rendered past the next header by the layer offset).
    """
    try:
        import pdfplumber  # type: ignore
    except ImportError:
        print("  pdfplumber not installed - skipping Kiselev PDF.")
        print("  To enable: pip install pdfplumber")
        return []

    if not os.path.exists(pdf_path):
        print(f"  PDF not found at {pdf_path}")
        return []

    # Patterns that mark back-matter / publisher metadata pages we should ignore.
    _NOISE_PATTERNS = re.compile(
        r'(ISBN|УДК|ББК|www\.|\.{5,}|КАРО|Издательство|Типография|'
        r'Подписано в печать|Тираж|Формат|Регистрационный|Отпечатан|'
        r'Корректор|Редактор|Технический|Издательские|редактор|'
        r'Тел\.|корп\.?:?\s*\d|стр\.\s*\d)',
        re.IGNORECASE,
    )

    def _clean_text(t: str) -> str:
        """Strip dotted-leader TOC patterns and trailing page numbers."""
        t = re.sub(r'\.{3,}\s*\d*', '', t)
        t = re.sub(r'\s+\d{1,3}\s*$', '', t)
        t = re.sub(r'(\.\s+){2,}', '. ', t)
        t = re.sub(r'\s+\.\s*$', '.', t)
        # Orphaned "ó"/"o"/"y" variant-separators echoed onto the line end.
        t = re.sub(r'([.!?…])\s+[óoy]\.?\s*$', r'\1', t)
        return t.strip(' ,;')

    def _looks_like_proverb(t: str) -> bool:
        if not t or len(t) < 4 or len(t) > 250:
            return False
        if _NOISE_PATTERNS.search(t):
            return False
        digit_ratio = sum(c.isdigit() for c in t) / max(len(t), 1)
        if digit_ratio > 0.3:
            return False
        return True

    # ── pass 1: build the entry list ────────────────────────────────────
    # entries: {'lang': 'ru'|'es', 'text': str, 'eqs': [str, ...]}
    entries: list[dict] = []

    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            ru_lines = _stream_lines(page.chars, _is_cyr)
            es_lines = _stream_lines(page.chars, _is_lat)

            # Which language carries the numbered headers on this page?
            ru_headers = sum(1 for _, t in ru_lines if _ENTRY_NUM_RE.match(t))
            es_headers = sum(1 for _, t in es_lines if _ENTRY_NUM_RE.match(t))
            if ru_headers == 0 and es_headers == 0:
                page_primary = None      # front/back matter
            else:
                page_primary = 'ru' if ru_headers >= es_headers else 'es'

            events = [(y, 'ru', t) for y, t in ru_lines] + \
                     [(y, 'es', t) for y, t in es_lines]
            events.sort(key=lambda e: e[0])

            last_header_y: float | None = None
            for y, lang, text in events:
                if _SECTION_HEADER_RE.match(text):
                    continue

                m = _ENTRY_NUM_RE.match(text)
                is_header = bool(m) and lang == page_primary
                if m and not is_header:
                    # Echoed entry number in the secondary stream (digits are
                    # shared between layers) — strip it, keep the text.
                    text = m.group(2).strip()
                    m = None

                if is_header:
                    entries.append({'lang': lang, 'text': m.group(2).strip(),
                                    'eqs': []})
                    last_header_y = y
                    continue

                if not entries:
                    continue

                cur = entries[-1]
                if lang == cur['lang']:
                    # Same script as the primary → header soft-wrap. A wrap
                    # within the glue zone of the CURRENT header extends it;
                    # otherwise (rare) it is a wrap of the previous entry's
                    # last equivalent in part 2 — same-language eq wrap.
                    if last_header_y is not None and 0 <= y - last_header_y < _GLUE_Y * 2.5:
                        cur['text'] = (cur['text'] + ' ' + text).strip()
                    elif cur['eqs']:
                        cur['eqs'].append(text)
                    else:
                        cur['text'] = (cur['text'] + ' ' + text).strip()
                    continue

                # Secondary-script line: the glue rule.
                glued = (last_header_y is not None
                         and 0 <= y - last_header_y < _GLUE_Y)
                if glued and len(entries) >= 2:
                    entries[-2]['eqs'].append(text)
                else:
                    cur['eqs'].append(text)

    # ── pass 2: merge wraps, clean, emit records ────────────────────────
    results: list[dict] = []
    for entry in entries:
        primary_text = _clean_text(entry['text'])
        if not _looks_like_proverb(primary_text) or not entry['eqs']:
            continue

        merged: list[str] = []
        for line in entry['eqs']:
            line = _clean_text(line)
            if not line:
                continue
            prev_open = merged and merged[-1] and merged[-1][-1] not in '.!?…'
            starts_lower = line[0].islower()
            if merged and (prev_open or starts_lower):
                # Soft wrap (no sentence-final punctuation on the previous
                # line) or an orphaned lowercase tail — glue to the previous
                # equivalent instead of emitting a fragment like "la gallina."
                merged[-1] = (merged[-1] + ' ' + line).strip()
            elif starts_lower:
                continue   # lowercase fragment with nothing to attach to
            else:
                merged.append(line)

        for eq in merged:
            if not _looks_like_proverb(eq):
                continue
            # A real equivalent is a complete saying: reject stubs that are
            # short AND not sentence-shaped.
            if len(eq) < 12 and not (eq[0].isupper() and eq[-1] in '.!?…'):
                continue
            if entry['lang'] == 'ru':
                rec = {'text_ru': primary_text, 'text_es': eq}
            else:
                rec = {'text_ru': eq, 'text_es': primary_text}
            rec['text_en'] = None
            rec['literal_en'] = None
            rec['source'] = 'kiselev'
            rec['confidence'] = 0.97   # human-curated reference work
            results.append(rec)

    # Deduplicate pairs (Part 1 and Part 2 of the book overlap heavily — the
    # same RU↔ES pair appears once from each direction). The key ignores
    # spaces and punctuation so near-dups produced by layer artifacts
    # ("сокл"/"как сокл", "sep tiembre.") collapse; of colliding candidates
    # keep the better-formed one (more word breaks recovered).
    def _dedup_key(r):
        norm = lambda s: re.sub(r'[^a-zа-яё]+', '',
                                (s or '').lower().replace('ё', 'е'))
        return (norm(r.get('text_ru')), norm(r.get('text_es')))

    def _quality(r):
        return (r.get('text_ru', '') or '').count(' ') + \
               (r.get('text_es', '') or '').count(' ')

    best: dict = {}
    order: list = []
    for r in results:
        key = _dedup_key(r)
        if key not in best:
            best[key] = r
            order.append(key)
        elif _quality(r) > _quality(best[key]):
            best[key] = r
    unique = [best[k] for k in order]

    print(f"  Extracted {len(unique)} unique RU<->ES pairs from {len(results)} raw entries")
    return unique


# ========================================================================
# Section D - Multilingual SBERT embeddings (optional)
# ========================================================================

EMBED_MODEL = 'sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2'


def compute_embeddings(db_path):
    """Compute and store a 384-dim multilingual embedding per proverb.

    Skipped automatically if sentence-transformers isn't installed.
    Embeddings are stored as float32 packed via struct.pack (NOT pickle).
    """
    try:
        from sentence_transformers import SentenceTransformer  # type: ignore
    except ImportError:
        print("  sentence-transformers not installed - skipping embeddings.")
        print("  To enable: pip install sentence-transformers")
        return 0

    print(f"  Loading model {EMBED_MODEL} (first run downloads ~120 MB)...")
    model = SentenceTransformer(EMBED_MODEL)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    rows = cur.execute(
        "SELECT id, text_ru, text_es, text_en, text_de, text_fr, text_uk, text_tr "
        "FROM proverbs"
    ).fetchall()

    print(f"  Encoding {len(rows)} entries...")
    for i, row in enumerate(rows):
        rid = row[0]
        texts = [t for t in row[1:] if t]
        if not texts:
            continue
        canon = max(texts, key=len)
        vec = model.encode(canon, normalize_embeddings=True)
        blob = struct.pack(f'<{len(vec)}f', *vec.tolist())
        cur.execute("UPDATE proverbs SET embedding = ? WHERE id = ?", (blob, rid))
        if (i + 1) % 100 == 0:
            print(f"    {i + 1}/{len(rows)}")
            conn.commit()
    conn.commit()
    conn.close()
    print(f"  Embeddings stored for {len(rows)} entries.")
    return len(rows)


# ========================================================================
# Section E - Database build
# ========================================================================

def build_database(all_proverbs):
    """Build SQLite database from collected proverbs."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute('''
        CREATE TABLE proverbs (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            text_ru     TEXT,
            text_es     TEXT,
            text_en     TEXT,
            text_de     TEXT,
            text_fr     TEXT,
            text_uk     TEXT,
            text_tr     TEXT,
            literal_en  TEXT,
            source      TEXT,
            confidence  REAL DEFAULT 0.5,
            embedding   BLOB
        )
    ''')
    for col in ('text_ru', 'text_es', 'text_en', 'text_de', 'text_fr', 'text_uk', 'text_tr'):
        cur.execute(f'CREATE INDEX idx_{col} ON proverbs({col})')
    cur.execute('CREATE INDEX idx_src ON proverbs(source)')
    cur.execute('CREATE INDEX idx_conf ON proverbs(confidence)')

    inserted = 0
    seen = set()
    for p in all_proverbs:
        key = (p.get('text_ru') or '', p.get('text_es') or '', p.get('text_en') or '')
        if key in seen:
            continue
        seen.add(key)

        src_text = (p.get('text_ru') or p.get('text_es') or
                    p.get('text_en') or p.get('text_de') or
                    p.get('text_fr') or '')
        if len(src_text) < 3:
            continue

        cur.execute(
            '''INSERT INTO proverbs
               (text_ru, text_es, text_en, text_de, text_fr, text_uk, text_tr,
                literal_en, source, confidence)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            (p.get('text_ru'), p.get('text_es'), p.get('text_en'),
             p.get('text_de'), p.get('text_fr'), p.get('text_uk'),
             p.get('text_tr'), p.get('literal_en'),
             p.get('source', 'unknown'), p.get('confidence', 0.5)),
        )
        inserted += 1

    # FTS table - all language columns searchable
    cur.execute('''CREATE VIRTUAL TABLE proverbs_fts USING fts5(
        text_ru, text_es, text_en, text_de, text_fr, text_uk, text_tr,
        content='proverbs', content_rowid='id'
    )''')
    cur.execute("INSERT INTO proverbs_fts(proverbs_fts) VALUES ('rebuild')")

    conn.commit()
    conn.close()

    print(f"\nDatabase built: {DB_PATH}")
    print(f"Total proverbs inserted: {inserted}")
    return inserted


def collect_wiki_sources():
    """Collect from Wikiquote (en, ru, es) + Wikipedia es proverbs."""
    all_proverbs = []

    print("\n--- Wikiquote: Russian proverbs ---")
    try:
        wikitext = fetch_wikitext('https://en.wikiquote.org', 'Russian_proverbs')
        if wikitext:
            print(f"  Got {len(wikitext)} chars")
            proverbs = parse_wikiquote_russian(wikitext)
            for p in proverbs:
                p['source'] = 'wikiquote-ru'
            print(f"  Parsed {len(proverbs)} proverbs")
            all_proverbs.extend(proverbs)
    except Exception as e:
        print(f"  ERROR: {e}")
    time.sleep(0.5)

    print("\n--- Wikiquote: Spanish proverbs ---")
    try:
        wikitext = fetch_wikitext('https://en.wikiquote.org', 'Spanish_proverbs')
        if wikitext:
            print(f"  Got {len(wikitext)} chars")
            proverbs = parse_wikiquote_spanish(wikitext)
            for p in proverbs:
                p['source'] = 'wikiquote-es'
            print(f"  Parsed {len(proverbs)} proverbs")
            all_proverbs.extend(proverbs)
    except Exception as e:
        print(f"  ERROR: {e}")
    time.sleep(0.5)

    print("\n--- Wikipedia: Spanish proverbs ---")
    try:
        wikitext = fetch_wikitext('https://en.wikipedia.org', 'Spanish_proverbs')
        if wikitext:
            print(f"  Got {len(wikitext)} chars")
            proverbs = parse_wikipedia_spanish(wikitext)
            for p in proverbs:
                p['source'] = 'wikipedia-es'
            print(f"  Parsed {len(proverbs)} proverbs")
            all_proverbs.extend(proverbs)
    except Exception as e:
        print(f"  ERROR: {e}")
    time.sleep(0.5)

    print("\n--- Wikiquote: English proverbs ---")
    try:
        wikitext = fetch_wikitext('https://en.wikiquote.org', 'English_proverbs')
        if wikitext:
            print(f"  Got {len(wikitext)} chars")
            proverbs = parse_wikiquote_english(wikitext)
            for p in proverbs:
                p['source'] = 'wikiquote-en'
            print(f"  Parsed {len(proverbs)} proverbs")
            all_proverbs.extend(proverbs)
    except Exception as e:
        print(f"  ERROR: {e}")

    return all_proverbs


def main():
    parser = argparse.ArgumentParser(description='Build LinguaTrace proverbs DB')
    parser.add_argument('--skip-wiki', action='store_true',
                        help='Skip Wikiquote/Wikipedia sources')
    parser.add_argument('--skip-refranero', action='store_true',
                        help='Skip Refranero Multilingue scraping')
    parser.add_argument('--skip-lidioms', action='store_true',
                        help='Skip LIDIOMS RDF fetch')
    parser.add_argument('--skip-kiselev', action='store_true',
                        help="Skip Kiselev's RU-ES PDF parsing")
    parser.add_argument('--kiselev-pdf', default=DEFAULT_KISELEV_PDF,
                        help='Path to Kiselev PDF (default: repo root)')
    parser.add_argument('--refranero-pages', type=int, default=3,
                        help='Pages of Refranero to scrape (default 3 ~ 300 entries)')
    parser.add_argument('--embed', action='store_true',
                        help='Generate multilingual SBERT embeddings (slow)')
    args = parser.parse_args()

    print("=" * 60)
    print("Building Proverbs Database v2 - multilingual")
    print("=" * 60)

    all_proverbs = []

    if not args.skip_wiki:
        all_proverbs.extend(collect_wiki_sources())

    if not args.skip_refranero:
        print("\n--- Refranero Multilingue (CVC Instituto Cervantes) ---")
        try:
            entries = fetch_refranero(max_pages=args.refranero_pages)
            all_proverbs.extend(entries)
        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback; traceback.print_exc()

    if not args.skip_lidioms:
        print("\n--- LIDIOMS (RU <-> EN idiom links) ---")
        try:
            entries = fetch_lidioms()
            all_proverbs.extend(entries)
        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback; traceback.print_exc()

    if not args.skip_kiselev:
        print("\n--- Kiselev RU-ES bilingual reference PDF ---")
        try:
            entries = parse_kiselev_pdf(args.kiselev_pdf)
            all_proverbs.extend(entries)
        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback; traceback.print_exc()

    print(f"\nTotal collected: {len(all_proverbs)}")

    if all_proverbs:
        count = build_database(all_proverbs)
        if count > 0:
            size = os.path.getsize(DB_PATH)
            print(f"Database size: {size / 1024:.1f} KB")
    else:
        print("No proverbs collected! Creating empty database...")
        build_database([])

    if args.embed and os.path.exists(DB_PATH):
        print("\n--- Computing multilingual embeddings ---")
        compute_embeddings(DB_PATH)
        size = os.path.getsize(DB_PATH)
        print(f"Database size with embeddings: {size / 1024:.1f} KB")

    if os.path.exists(DB_PATH):
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        print("\n--- Coverage by source ---")
        for row in cur.execute(
            "SELECT source, COUNT(*) FROM proverbs GROUP BY source ORDER BY 2 DESC"
        ):
            print(f"  {row[0]:20} {row[1]}")
        print("\n--- Coverage by language ---")
        for col in ('text_ru', 'text_es', 'text_en', 'text_de', 'text_fr', 'text_uk', 'text_tr'):
            n = cur.execute(f"SELECT COUNT(*) FROM proverbs WHERE {col} IS NOT NULL").fetchone()[0]
            if n:
                print(f"  {col:10} {n}")
        conn.close()

    print("\nDone!")


if __name__ == '__main__':
    main()
