#!/usr/bin/env python3
"""scripts/ops/autoria.py — comprobaciones de uso de IA y autoría del Lab 6 (las mismas que aplica el docente).

Reglas fijas de la política de uso de IA (sin interpretación):
  D1  falta docs/bitacora/lab6-ia.md, o no declara nada                                −0,5
  D2  una IA hizo commits: coautor o firma de IA en los commits del laboratorio,
      o archivos de agente en el repositorio (.claude/, CLAUDE.md, AGENTS.md, .cursor/…)  el mayor entre 35 % y 3 puntos
  D3  entrada de lab6-ia.md con algún campo obligatorio vacío                                 −0,5 por entrada
  D5  marca de texto generado en las respuestas (contentReference, oaicite,
      utm_source=chatgpt.com, utm_source=gemini)                                         NR y −0,5 por pregunta
  D6  evidencia sin cabecera, con otro código de alumno o de otra base de datos (DBID)    NR y −1 por evidencia
      (la comparación con la hora del commit y con otros alumnos la hace el docente)

Uso:  python3 scripts/ops/autoria.py [--repo .] [--alumno E0NN] [--desde lab5-final] [--ia docs/bitacora/lab6-ia.md]
Lo ejecuta scripts/lab6/09-verificacion-final.sh. Sale con el número de problemas encontrados.
"""
import argparse
import os
import re
import subprocess
import sys

ARCHIVO_IA = 'docs/bitacora/lab6-ia.md'   # la declaración de uso de IA de ESTE laboratorio (Lab 7: lab7-ia.md)

LEIDO = re.compile(r'he le[ií]do la pol[ií]tica de uso de ia de la asignatura', re.I)

CAMPOS = [  # (clave, texto que identifica la línea del campo en IA.md, admite «no aplica»)
    ('herramienta', 'herramienta', False),
    ('prompt', 'prompt', False),
    ('codigo', 'código recibido', True),
    ('donde', 'dónde lo usé', False),
    ('proposito', 'propósito', False),
    ('que_hace', 'qué hace', False),
    ('evidencia', 'evidencia de ejecución', True),
]
NO_HE_USADO = re.compile(r'^\s*no he usado (la )?ia\b', re.I | re.M)
MARCAS_TEXTO = ['contentReference', 'oaicite', 'utm_source=chatgpt.com', 'utm_source=gemini']
ARCHIVOS_AGENTE = ['.claude', 'CLAUDE.md', 'AGENTS.md', '.cursor', '.cursorrules', 'GEMINI.md', '.gemini',
                   '.codex', '.aider.conf.yml', '.github/copilot-instructions.md', '.windsurfrules']
FIRMA_IA = re.compile(r'(co-authored-by:.*(claude|anthropic|copilot|openai|chatgpt|codex|cursor|gemini|devin|aider)'
                      r'|generated with \[?claude code|noreply@anthropic\.com|cursoragent@|copilot-swe-agent'
                      r'|🤖 generated with)', re.I)
CABECERA = re.compile(r'^== EVIDENCIA (.*)$', re.M)
CODIGO = re.compile(r'^E\d{3}$')


def sin_comentarios(texto):
    return re.sub(r'<!--.*?-->', '', texto, flags=re.S)


def leer(ruta):
    try:
        with open(ruta, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return None


# ------------------------------------------------------------------------------------------------- IA.md
def analizar_ia(repo, archivo=None):
    """Devuelve dict: existe, declara_no_uso, entradas [{n, campos{clave: texto}, vacios[]}], incompletas, d1."""
    texto = leer(os.path.join(repo, archivo or ARCHIVO_IA))
    r = {'existe': texto is not None, 'declara_no_uso': False, 'entradas': [], 'incompletas': [], 'd1': False, 'leido': False}
    if texto is None:
        r['d1'] = True
        return r
    texto = sin_comentarios(texto)
    primera = next((l.strip() for l in texto.split('\n') if l.strip()), '')
    r['leido'] = bool(LEIDO.search(primera))
    r['declara_no_uso'] = bool(NO_HE_USADO.search(texto))
    bloques = re.split(r'^##\s+Entrada\b[^\n]*\n', texto, flags=re.M | re.I)
    for n, bloque in enumerate(bloques[1:], start=1):
        campos = valores_campos(bloque)
        if not any(campos.values()):
            continue                                   # la entrada de ejemplo sin tocar no cuenta
        vacios = [clave for clave, _, admite in CAMPOS
                  if not campos[clave] or (not admite and campos[clave].lower().strip(' .') == 'no aplica')]
        r['entradas'].append({'n': n, 'campos': campos, 'vacios': vacios})
        if vacios:
            r['incompletas'].append(n)
    r['d1'] = not r['declara_no_uso'] and not r['entradas']
    return r


def valores_campos(bloque):
    """Lee los 7 campos: el texto tras «**Campo:**» en su línea, más un bloque de código que lo siga."""
    lineas = bloque.split('\n')
    pos = {}
    for i, l in enumerate(lineas):
        m = re.match(r'^\s*[-*]\s*\*\*(.+?)\*\*\s*(.*)$', l)
        if not m:
            continue
        etiqueta = m.group(1).lower()
        for clave, clavetxt, _ in CAMPOS:
            if clave not in pos and etiqueta.startswith(clavetxt):
                pos[clave] = (i, m.group(2))
                break
    orden = sorted(pos.items(), key=lambda kv: kv[1][0])
    valores = {clave: '' for clave, _, _ in CAMPOS}
    for k, (clave, (i, resto)) in enumerate(orden):
        fin = orden[k + 1][1][0] if k + 1 < len(orden) else len(lineas)
        extra = '\n'.join(lineas[i + 1:fin])
        extra = re.sub(r'```[a-zA-Z]*', '', extra)            # las vallas del bloque de código no son contenido
        valor = (resto + '\n' + extra).strip()
        valores[clave] = valor
    return valores


# ------------------------------------------------------------------------------------------------- git
def git(repo, *args):
    p = subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True)
    return p.stdout if p.returncode == 0 else ''


def rango_commits(repo, desde):
    if desde and git(repo, 'rev-parse', '-q', '--verify', desde + '^{commit}').strip():
        return f'{desde}..HEAD'
    return 'HEAD'


def commits_ia(repo, desde):
    """Commits del laboratorio con firma o coautor de IA: [(hash corto, fecha, asunto, línea que lo delata)]."""
    salida = git(repo, 'log', rango_commits(repo, desde), '--format=%h%x1f%cI%x1f%an <%ae>%x1f%cn <%ce>%x1f%s%x1f%B%x1e')
    hallados = []
    for reg in salida.split('\x1e'):
        partes = reg.strip('\n').split('\x1f')
        if len(partes) < 6:
            continue
        h, fecha, autor, committer, asunto, cuerpo = partes[:6]
        for texto in (autor, committer, cuerpo):
            m = FIRMA_IA.search(texto)
            if m:
                linea = next((l for l in texto.split('\n') if FIRMA_IA.search(l)), m.group(0))
                hallados.append((h, fecha, asunto, linea.strip()))
                break
    return hallados


def archivos_agente(repo):
    versionados = set(git(repo, 'ls-files').split('\n'))
    hallados = []
    for a in ARCHIVOS_AGENTE:
        if a in versionados or any(f.startswith(a + '/') for f in versionados) or os.path.exists(os.path.join(repo, a)):
            hallados.append(a)
    return hallados


# ------------------------------------------------------------------------------------------------- respuestas
def marcas_respuestas(repo, archivo='docs/bitacora/lab6-respuestas.md'):
    """Preguntas (sección o número) con marcas de texto generado: [(pregunta, marca)]."""
    texto = leer(os.path.join(repo, archivo))
    if not texto:
        return []
    hallados, actual = [], 'inicio'
    for l in texto.split('\n'):
        m = re.match(r'^\s*(#{1,6}\s+.*|\*\*\s*(P|Pregunta)?\s*\d+.*|\d+[.)]\s.*)$', l, re.I)
        if m:
            actual = l.strip()[:60]
        for marca in MARCAS_TEXTO:
            if marca.lower() in l.lower() and (actual, marca) not in hallados:
                hallados.append((actual, marca))
    return hallados


# ------------------------------------------------------------------------------------------------- evidencias
def cabeceras(texto):
    """Junta los pares clave=valor de las líneas «== EVIDENCIA …». Una evidencia puede tener varias cabeceras."""
    grupos, actual = [], {}
    for linea in CABECERA.findall(texto or ''):
        pares = dict(re.findall(r'(\w+)=(\S+)', linea))
        if 'alumno' in pares and actual:
            grupos.append(actual)
            actual = {}
        actual.update(pares)
    if actual:
        grupos.append(actual)
    return grupos


def evidencias(repo, carpeta='docs/bitacora/lab6/evidencia'):
    base = os.path.join(repo, carpeta)
    res = []
    for sub in ('script', 'spool'):
        d = os.path.join(base, sub)
        if not os.path.isdir(d):
            continue
        for nombre in sorted(os.listdir(d)):
            ruta = os.path.join(d, nombre)
            if os.path.isfile(ruta):
                res.append((os.path.relpath(ruta, repo), cabeceras(leer(ruta))))
    return res


def problemas_evidencias(repo, alumno):
    """D6 que se puede comprobar en el propio repositorio: sin cabecera, otro código, otra base (DBID)."""
    lista = evidencias(repo)
    dbids = {}
    for ruta, cabs in lista:
        for c in cabs:
            if c.get('dbid'):
                dbids.setdefault(c['dbid'], []).append(ruta)
    dbid_mayoria = max(dbids, key=lambda k: len(dbids[k])) if dbids else None
    problemas = []
    for ruta, cabs in lista:
        if not cabs:
            problemas.append((ruta, 'sin cabecera de evidencia'))
            continue
        codigos = {c.get('alumno') for c in cabs}
        if alumno and codigos != {alumno}:
            problemas.append((ruta, 'código de alumno ' + ', '.join(sorted(x or '?' for x in codigos))))
        otros = {c.get('dbid') for c in cabs if c.get('dbid')} - {dbid_mayoria}
        if otros:
            problemas.append((ruta, 'DBID de otra base de datos: ' + ', '.join(sorted(otros))))
    return lista, problemas


# ------------------------------------------------------------------------------------------------- CLI
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--repo', default='.')
    ap.add_argument('--alumno', default=os.environ.get('ESTUDIANTE', ''))
    ap.add_argument('--desde', default='lab5-final', help='tag o commit donde empieza el laboratorio')
    ap.add_argument('--ia', default=ARCHIVO_IA, help='archivo de declaración de uso de IA')
    a = ap.parse_args()
    fallos = 0

    def ok(t):
        print(f'  [OK]    {t}')

    def fallo(t, d):
        nonlocal fallos
        fallos += 1
        print(f'  [FALLO] {t}  -> {d}')

    if CODIGO.match(a.alumno or ''):
        ok(f'código de alumno {a.alumno} en config/.env')
    else:
        fallo('falta ESTUDIANTE (E y tres dígitos) en config/.env', 'Parte A.3')

    ia = analizar_ia(a.repo, a.ia)
    if not ia['existe']:
        fallo(f'no existe {a.ia}', 'D1 (−0,5): copia docs/plantillas/IA.md a ese archivo (Parte A.4)')
    elif ia['d1']:
        fallo(f'{a.ia} no declara nada: ni «No he usado IA.» ni entradas', 'D1 (−0,5)')
    elif ia['entradas']:
        ok(f"{a.ia} con {len(ia['entradas'])} entrada(s) declarada(s)")
        for e in ia['entradas']:
            if e['vacios']:
                fallo(f"{a.ia}, entrada {e['n']}: campos vacíos ({', '.join(e['vacios'])})", 'D3 (−0,5 por entrada)')
        if ia['declara_no_uso']:
            fallo(f'{a.ia} dice «No he usado IA.» y también tiene entradas', 'borra una de las dos (Parte A.4)')
    else:
        ok(f'{a.ia} declara «No he usado IA.»')

    if ia['leido']:
        ok('primera línea: «He leído la política de uso de IA de la asignatura.»')
    elif ia['existe']:
        fallo(f'la primera línea de {a.ia} no es «He leído la política de uso de IA de la asignatura.»',
              'cópiala de docs/plantillas/IA.md (Parte A.4)')
    agentes = archivos_agente(a.repo)
    versionados = set(git(a.repo, 'ls-files').split('\n'))
    en_git = [x for x in agentes if x in versionados or any(f.startswith(x + '/') for f in versionados)]
    locales = [x for x in agentes if x not in en_git]
    if en_git:
        fallo('archivos de agente de IA versionados en Git: ' + ', '.join(en_git),
              'D2 (el mayor entre 35 % y 3 puntos): git rm -r --cached y añádelos a .gitignore')
    if locales:
        print('  [AVISO] archivos de agente de IA en tu carpeta, fuera de Git: ' + ', '.join(locales)
              + '  -> no los subas: añádelos a .gitignore')
    if not agentes:
        ok('ningún archivo de agente de IA (.claude/, CLAUDE.md, AGENTS.md, .cursor/…)')
    firmados = commits_ia(a.repo, a.desde)
    if firmados:
        for h, fecha, asunto, linea in firmados[:10]:
            fallo(f'commit {h} ({fecha[:16]}) «{asunto[:40]}» lleva firma de IA: {linea[:60]}', 'D2')
    else:
        ok(f'ningún commit con firma o coautor de IA ({rango_commits(a.repo, a.desde)})')

    marcas = marcas_respuestas(a.repo)
    if marcas:
        for preg, marca in marcas:
            fallo(f'marca de texto generado «{marca}» en las respuestas ({preg})', 'D5 (NR y −0,5 por pregunta)')
    else:
        ok('respuestas sin marcas de texto generado')

    lista, probl = problemas_evidencias(a.repo, a.alumno)
    if not lista:
        fallo('no hay evidencias en docs/bitacora/lab6/evidencia', 'Partes A a I')
    elif probl:
        for ruta, motivo in probl[:15]:
            fallo(f'{ruta}: {motivo}', 'D6: vuelve a generar esa evidencia en tu entorno')
    else:
        ok(f'{len(lista)} evidencias con tu cabecera ({a.alumno}) y una sola base de datos')
    return fallos


if __name__ == '__main__':
    sys.exit(min(main(), 100))
