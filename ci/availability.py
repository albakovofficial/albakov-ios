# Доступность ALBAKOV в App Store по странам через App Store Connect API (ключ — секреты ASC_*).
# python3 ci/availability.py all-but-eu-cn  — все страны, кроме 27 стран ЕС и материкового Китая
# python3 ci/availability.py show            — только показать, где приложение есть
import os, sys, time, json, urllib.request, urllib.error
import jwt  # PyJWT

BUNDLE = 'ru.albakovofficial.app'
API = 'https://api.appstoreconnect.apple.com'
# 27 стран ЕС (закон DSA: без статуса трейдера там нельзя) и материковый Китай (нужен номер ICP)
EU = {'AUT', 'BEL', 'BGR', 'HRV', 'CYP', 'CZE', 'DNK', 'EST', 'FIN', 'FRA', 'DEU', 'GRC', 'HUN', 'IRL', 'ITA', 'LVA',
      'LTU', 'LUX', 'MLT', 'NLD', 'POL', 'PRT', 'ROU', 'SVK', 'SVN', 'ESP', 'SWE'}
OFF = EU | {'CHN'}


def token():
    now = int(time.time())
    return jwt.encode({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'},
                      os.environ['ASC_KEY_P8'], algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})


def call(method, path, body=None):
    req = urllib.request.Request(path if path.startswith('http') else API + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        sys.exit(f'::error::{method} {path} → {e.code}: {e.read().decode()[:600]}')


def main(mode):
    app = call('GET', f'/v1/apps?filter[bundleId]={BUNDLE}')['data'][0]['id']
    av = call('GET', f'/v1/apps/{app}/appAvailabilityV2')['data']['id']
    items, url = [], f'/v2/appAvailabilities/{av}/territoryAvailabilities?limit=200&include=territory'
    while url:
        page = call('GET', url)
        items += [(t['id'], t['relationships']['territory']['data']['id'], t['attributes']['available']) for t in page['data']]
        url = page.get('links', {}).get('next')
    on = sorted(c for _, c, a in items if a)
    print(f'Всего стран: {len(items)}, приложение доступно в {len(on)}: {" ".join(on)}')
    if mode == 'show':
        return
    if len(items) < 150:
        sys.exit(f'::error::Apple вернула только {len(items)} стран — менять не стану, проверьте в App Store Connect')
    changed = 0
    for tid, code, available in items:
        want = code not in OFF
        if available != want:
            call('PATCH', f'/v1/territoryAvailabilities/{tid}',
                 {'data': {'type': 'territoryAvailabilities', 'id': tid, 'attributes': {'available': want}}})
            changed += 1
    print(f'Изменено стран: {changed}. Теперь доступно везде, кроме ЕС ({len(EU)}) и материкового Китая.')
    main('show')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'show')
